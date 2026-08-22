#!/bin/zsh
# The build gate.
#
#   scripts/build-gate.sh
#
# Every build and test command redirects **unpiped** to its own log file — no `tee`, no
# `xcpretty`, no `| grep` — and is judged on its exit status alone. A build whose output was
# piped into something is not a verified build.
#
# The gate does **not** short-circuit: every stage runs, so one early failure cannot hide
# three later ones. It prints a summary table and exits non-zero if any stage failed.
#
# ## Zero grants, by construction
#
# Nothing here needs Accessibility, Screen Recording or Automation — not for the app, and
# not for the shell that invokes it. Revoking every permission on this Mac must still leave
# a green gate. That is why the live `osascript` + `screencapture` lane is not a stage and is
# never invoked from here: it produces evidence a human reads, never a pass/fail criterion.
# Run it separately, when the grants exist:
#
#   scripts/live-shell-drive.sh
#
# ## Environment
#
#   FOCUS_DERIVED_DATA     default /tmp/focus-dd
#   FOCUS_LOG_DIR          default /tmp
#   FOCUS_RESULT_BUNDLE    default a unique timestamped path under $FOCUS_LOG_DIR
#   FOCUS_EVIDENCE_DIR     if set, the whole evidence set is assembled there under the names
#                          the epic's validation section asks for
#   FOCUS_SNAPSHOT_OUT     where the snapshot lane wrote its renders; defaults to the
#                          harness's own default, $TMPDIR/focus-snapshots
set -u

REPO_ROOT="${0:A:h}/.."
cd "$REPO_ROOT" || exit 1

DD="${FOCUS_DERIVED_DATA:-/tmp/focus-dd}"
LOG_DIR="${FOCUS_LOG_DIR:-/tmp}"
mkdir -p -- "$LOG_DIR"

# xcodebuild refuses to write over an existing result bundle and exits 64 *before running a
# single test*. A fixed path would therefore make every second gate run fail for a reason
# that has nothing to do with the code. The gate owns the path: unique by default, and
# removed first either way, so an explicitly pinned FOCUS_RESULT_BUNDLE is re-runnable too.
RB="${FOCUS_RESULT_BUNDLE:-$LOG_DIR/focus-e01-$(date -u +%Y%m%dT%H%M%SZ)-$$.xcresult}"
rm -rf -- "$RB"

GATE_LOG="$LOG_DIR/focus-gate.log"
DESTINATION='platform=macOS,arch=arm64'

# The self-check JSON is written to a known path per configuration rather than a mktemp one,
# because it is evidence in its own right and the manifest below has to be able to find it.
SELFCHECK_JSON="$LOG_DIR/focus-selfcheck.json"
SELFCHECK_JSON_RELEASE="$LOG_DIR/focus-selfcheck-release.json"

# The snapshot lane writes every render — matching or not — to a plain directory, which is
# what makes evidence collection a `cp -R` rather than a dependence on `xcresulttool`'s
# shifting subcommand surface. Measured: `xcodebuild` does not forward its own environment to
# a SwiftPM test target's process, so setting this here cannot *redirect* the renders; it
# names where to look for them, and the default is the harness's own default.
TMP_ROOT="${TMPDIR:-/tmp}"
SNAPSHOT_OUT="${FOCUS_SNAPSHOT_OUT:-${TMP_ROOT%/}/focus-snapshots}"
SNAPSHOT_OUT="${SNAPSHOT_OUT%/}"

typeset -a STAGE_NAMES STAGE_CODES STAGE_LOGS

record() {
    STAGE_NAMES+=("$1")
    STAGE_CODES+=("$2")
    STAGE_LOGS+=("$3")
    print "GATE $1 EXIT=$2 log=$3"
}

run_stage() {
    local name="$1" log="$2"
    shift 2
    "$@" > "$log" 2>&1
    record "$name" "$?" "$log"
}

# The whole gate is a function rather than a `{ … }` block. A `{ … } > log` group is not a
# subshell, so an `exit` inside it terminates the script outright — which is what used to
# happen here, and it meant the summary table was written to the log and then never echoed:
# running the gate printed nothing at all. A function returns, and the caller stays alive to
# print what it produced.
gate() {
    print "FOCUS BUILD GATE"
    print "repo:           $REPO_ROOT"
    print "derived data:   $DD"
    print "result bundle:  $RB"
    print "started:        $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    print

    # 1 — project integrity, before anything can rewrite it
    run_stage "project" "$LOG_DIR/focus-project.log" scripts/verify-project.sh

    # 2 — package boundaries and the zero-networking assertion
    run_stage "boundaries" "$LOG_DIR/focus-boundaries.log" scripts/check-boundaries.sh

    # 3 — forbidden symbols (standing conditions 1, 2, 8 and the migration-plan rule)
    run_stage "forbidden" "$LOG_DIR/focus-forbidden.log" scripts/check-forbidden.sh

    # 4 — string externalisation: no hardcoded user-visible text, and the catalogs and the
    # code agree in both directions.
    run_stage "strings" "$LOG_DIR/focus-strings.log" scripts/check-strings.sh

    # 5 — Debug build
    run_stage "build-debug" "$LOG_DIR/focus-build.log" \
        xcodebuild -workspace Focus.xcworkspace -scheme FocusSentinel \
        -configuration Debug -destination "$DESTINATION" -derivedDataPath "$DD" build

    # 6 — Release build
    run_stage "build-release" "$LOG_DIR/focus-build-release.log" \
        xcodebuild -workspace Focus.xcworkspace -scheme FocusSentinel \
        -configuration Release -destination "$DESTINATION" -derivedDataPath "$DD" build

    # 7 — the headless unit lane, the only lane that compiles String Catalogs
    rm -rf -- "$RB"
    run_stage "unit" "$LOG_DIR/focus-test.log" \
        xcodebuild -workspace Focus.xcworkspace -scheme FocusUnitTests \
        -destination "$DESTINATION" -derivedDataPath "$DD" -resultBundlePath "$RB" test

    # 7b — the binary half of the zero-networking assertion.
    # Stage 2 runs before anything is built, so on a cold checkout `nm -u FocusClassify.o`
    # has no object to read and reports a skip. Re-running the same script here, with the
    # skip promoted to a failure, is what makes the strongest form of F-112 fire on every
    # gate run rather than only on a warm tree.
    FOCUS_REQUIRE_BINARY_CHECK=1 \
        run_stage "boundaries-binary" "$LOG_DIR/focus-boundaries-binary.log" \
        scripts/check-boundaries.sh

    # 8 — entitlements, on both configurations. The configuration is passed explicitly
    # because the assertion differs: get-task-allow belongs in Debug and must be absent from
    # the Release product, which is the artefact this programme actually ships.
    run_stage "entitlements-debug" "$LOG_DIR/focus-entitlements.log" \
        scripts/entitlement-check.sh "$DD/Build/Products/Debug/FocusSentinel.app" Debug
    run_stage "entitlements-release" "$LOG_DIR/focus-entitlements-release.log" \
        scripts/entitlement-check.sh "$DD/Build/Products/Release/FocusSentinel.app" Release

    # 9 — the zero-grant shell self-check, on both configurations.
    # FOCUS_EVIDENCE_DIR is deliberately cleared for the child: the gate assembles the
    # evidence set itself, under one set of names, after every stage has finished. Left set,
    # the Release run would silently overwrite the Debug run's selfcheck.json.
    FOCUS_EVIDENCE_DIR= FOCUS_SELFCHECK_JSON="$SELFCHECK_JSON" \
        run_stage "selfcheck-debug" "$LOG_DIR/focus-selfcheck.log" \
        scripts/self-check.sh "$DD/Build/Products/Debug/FocusSentinel.app"
    FOCUS_EVIDENCE_DIR= FOCUS_SELFCHECK_JSON="$SELFCHECK_JSON_RELEASE" \
        run_stage "selfcheck-release" "$LOG_DIR/focus-selfcheck-release.log" \
        scripts/self-check.sh "$DD/Build/Products/Release/FocusSentinel.app"

    # 10 — project integrity again. Stages 5–7 are the ones that could provoke a rewrite.
    run_stage "project-post" "$LOG_DIR/focus-project-post.log" scripts/verify-project.sh

    # --- summary --------------------------------------------------------------------------

    local failed=0 i
    print
    print "=============================================================="
    printf '%-24s %-6s %s\n' "STAGE" "EXIT" "LOG"
    print "--------------------------------------------------------------"
    for i in {1..${#STAGE_NAMES}}; do
        printf '%-24s %-6s %s\n' "${STAGE_NAMES[$i]}" "${STAGE_CODES[$i]}" "${STAGE_LOGS[$i]}"
        (( STAGE_CODES[$i] != 0 )) && failed=1
    done
    print "--------------------------------------------------------------"
    print "result bundle:  $RB"
    print "self-check:     $SELFCHECK_JSON"
    print "snapshots:      $SNAPSHOT_OUT"
    print "finished:       $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    print
    print "The live osascript/screencapture lane is deliberately NOT a stage: it needs"
    print "Accessibility and Screen Recording on the driving shell, and no acceptance"
    print "criterion may depend on a permission grant. Run scripts/live-shell-drive.sh"
    print "separately for that evidence; it skips and exits 0 when a grant is missing."
    print

    if (( failed == 0 )); then
        print "GATE RESULT: PASS"
    else
        print "GATE RESULT: FAIL"
    fi
    print "=============================================================="

    return $failed
}

# Assemble the evidence set under the names the epic's validation section asks for. The
# evidence directory is never committed; it exists so a closing epic can be audited from
# artefacts rather than from assertions about artefacts.
collect_evidence() {
    local dir="$1" from to
    mkdir -p -- "$dir" || return 1

    # source-in-$LOG_DIR  →  name-in-evidence
    local -a manifest
    manifest=(
        "focus-project.log:project.log"
        "focus-project-post.log:project-post.log"
        "focus-boundaries.log:boundaries.log"
        "focus-boundaries-binary.log:boundaries-binary.log"
        "focus-forbidden.log:forbidden.log"
        "focus-strings.log:strings.log"
        "focus-build.log:build-debug.log"
        "focus-build-release.log:build-release.log"
        "focus-test.log:test.log"
        "focus-entitlements.log:entitlements.txt"
        "focus-entitlements-release.log:entitlements-release.txt"
        "focus-selfcheck.log:selfcheck.log"
        "focus-selfcheck-release.log:selfcheck-release.log"
        "focus-selfcheck.json:selfcheck.json"
        "focus-selfcheck-release.json:selfcheck-release.json"
    )

    print
    print "== evidence → $dir"
    local entry
    for entry in $manifest; do
        from="$LOG_DIR/${entry%%:*}"
        to="$dir/${entry##*:}"
        if [[ -f "$from" ]]; then
            cp -- "$from" "$to" && print "   $to"
        else
            print -u2 "   MISSING $from (would have been ${entry##*:})"
        fi
    done

    # The snapshot renders: a plain directory copy, by design.
    if [[ -d "$SNAPSHOT_OUT" ]]; then
        rm -rf -- "$dir/snapshots"
        cp -R -- "$SNAPSHOT_OUT" "$dir/snapshots" \
            && print "   $dir/snapshots ($(ls -1 -- "$dir/snapshots" | wc -l | tr -d ' ') files)"
    else
        print -u2 "   MISSING $SNAPSHOT_OUT (the snapshot renders)"
    fi

    print
    print "The live lane's artefacts — menus.txt and the shell frames — are written straight"
    print "into this directory by scripts/live-shell-drive.sh when the grants exist, and are"
    print "absent when they do not. That absence never blocks the epic."
}

gate > "$GATE_LOG" 2>&1
gate_rc=$?

if [[ -n "${FOCUS_EVIDENCE_DIR:-}" ]]; then
    collect_evidence "$FOCUS_EVIDENCE_DIR" >> "$GATE_LOG" 2>&1
fi

cat -- "$GATE_LOG"

# gate.log is copied last, because until now it was still being written.
if [[ -n "${FOCUS_EVIDENCE_DIR:-}" ]]; then
    cp -- "$GATE_LOG" "$FOCUS_EVIDENCE_DIR/gate.log"
fi

exit $gate_rc
