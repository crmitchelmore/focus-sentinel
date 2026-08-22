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
# ## Every run owns its own paths
#
# Two gate runs at once used to contaminate each other's evidence: the derived-data tree, the
# gate log and every stage log were fixed, shared paths, and `gate > "$GATE_LOG"` truncates.
# The observable symptom was a single gate log whose header named one result bundle and whose
# footer named another — two runs' output braided into one file that neither of them
# describes. Evidence that can be produced by a run other than the one you are reading is not
# evidence.
#
# So every default path below is derived from a per-run token: the derived data, the log
# directory (and therefore the gate log, every stage log and both self-check JSONs), the
# result bundle, and the run's copy of the snapshot renders. Two runs share nothing.
# Pinning any of the FOCUS_* variables opts back into a shared path deliberately — that is
# what they are for, and it is then the caller's problem to serialise.
#
# The cost is that a default run builds cold. `FOCUS_DERIVED_DATA=/tmp/focus-dd` restores a
# warm tree for a single-run inner loop. Per-run directories accumulate under /tmp; the
# summary prints exactly which ones this run made.
#
# ## Environment
#
#   FOCUS_RUN_TOKEN        the per-run suffix. Default <UTC timestamp>-<pid>
#   FOCUS_DERIVED_DATA     default /tmp/focus-dd-$FOCUS_RUN_TOKEN
#   FOCUS_LOG_DIR          default /tmp/focus-gate-$FOCUS_RUN_TOKEN
#   FOCUS_RESULT_BUNDLE    default $FOCUS_LOG_DIR/focus-e01-$FOCUS_RUN_TOKEN.xcresult
#   FOCUS_EVIDENCE_DIR     if set, the whole evidence set is assembled there under the names
#                          the epic's validation section asks for
#   FOCUS_SNAPSHOT_OUT     the directory the snapshot lane writes its renders into. See the
#                          note at SNAPSHOT_STAGING below: this names where to *look*, not
#                          where to write, and it is the one path the gate cannot make unique
set -u

REPO_ROOT="${0:A:h}/.."
cd "$REPO_ROOT" || exit 1

RUN_TOKEN="${FOCUS_RUN_TOKEN:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"

DD="${FOCUS_DERIVED_DATA:-/tmp/focus-dd-$RUN_TOKEN}"
LOG_DIR="${FOCUS_LOG_DIR:-/tmp/focus-gate-$RUN_TOKEN}"
LOG_DIR="${LOG_DIR%/}"
mkdir -p -- "$LOG_DIR"

# The stage scripts find the build products through FOCUS_DERIVED_DATA — check-boundaries.sh
# reads `FocusClassify.o` out of it for the binary half of the zero-networking assertion.
# With a per-run derived-data tree this export is load-bearing: without it the stage would
# fall back to its own default and read whatever object some *other* run left at
# /tmp/focus-dd, which is the same contamination in a different costume.
export FOCUS_DERIVED_DATA="$DD"

# xcodebuild refuses to write over an existing result bundle and exits 64 *before running a
# single test*. A fixed path would therefore make every second gate run fail for a reason
# that has nothing to do with the code. The gate owns the path: unique by default, and
# removed first either way, so an explicitly pinned FOCUS_RESULT_BUNDLE is re-runnable too.
RB="${FOCUS_RESULT_BUNDLE:-$LOG_DIR/focus-e01-$RUN_TOKEN.xcresult}"
rm -rf -- "$RB"

GATE_LOG="$LOG_DIR/focus-gate.log"
DESTINATION='platform=macOS,arch=arm64'

# The self-check JSON is written to a known path per configuration rather than a mktemp one,
# because it is evidence in its own right and the manifest below has to be able to find it.
SELFCHECK_JSON="$LOG_DIR/focus-selfcheck.json"
SELFCHECK_JSON_RELEASE="$LOG_DIR/focus-selfcheck-release.json"

# The snapshot lane writes every render — matching or not — to a plain directory, which is
# what makes evidence collection a `cp -R` rather than a dependence on `xcresulttool`'s
# shifting subcommand surface.
#
# This is the one path the gate cannot own, and it is worth being exact about why. The
# directory is chosen inside the *test* process, and `xcodebuild` will not carry a value into
# a SwiftPM test target's environment. Measured on this machine (Xcode 26.2), twice:
# `FOCUS_SNAPSHOT_OUT=<dir> xcodebuild … test` leaves <dir> empty, and so does declaring
# `FOCUS_SNAPSHOT_OUT = $(FOCUS_SNAPSHOT_OUT)` in the scheme's <EnvironmentVariables> and
# passing `FOCUS_SNAPSHOT_OUT=<dir>` as a command-line build setting. Both runs wrote to the
# harness's own default instead.
#
# What the gate does therefore is copy *out* of that shared staging directory into a per-run
# directory of its own, immediately after the unit stage, and treat the copy as this run's
# renders. The staging directory stays shared between concurrent runs; the renders are a
# deterministic function of the committed code, so two runs of the same tree write identical
# bytes there, and the evidence each run collects is its own snapshot of it.
TMP_ROOT="${TMPDIR:-/tmp}"
SNAPSHOT_STAGING="${FOCUS_SNAPSHOT_OUT:-${TMP_ROOT%/}/focus-snapshots}"
SNAPSHOT_STAGING="${SNAPSHOT_STAGING%/}"
SNAPSHOT_OUT="$LOG_DIR/snapshots"

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
    print "run token:      $RUN_TOKEN"
    print "derived data:   $DD"
    print "log directory:  $LOG_DIR"
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

    # 7a — take this run's own copy of the snapshot renders out of the shared staging
    # directory the test process chose. See the SNAPSHOT_STAGING note above for why the gate
    # copies rather than owns.
    if [[ -d "$SNAPSHOT_STAGING" ]]; then
        rm -rf -- "$SNAPSHOT_OUT"
        cp -R -- "$SNAPSHOT_STAGING" "$SNAPSHOT_OUT" \
            && print "GATE snapshots copied from $SNAPSHOT_STAGING to $SNAPSHOT_OUT"
    else
        print -u2 "GATE snapshots MISSING at $SNAPSHOT_STAGING"
    fi

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
    print "run token:      $RUN_TOKEN"
    print "derived data:   $DD"
    print "result bundle:  $RB"
    print "self-check:     $SELFCHECK_JSON"
    print "snapshots:      $SNAPSHOT_OUT (staged in $SNAPSHOT_STAGING)"
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
