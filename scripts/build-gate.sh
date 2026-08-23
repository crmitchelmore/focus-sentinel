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
# warm tree for a single-run inner loop.
#
# A green run then **gives its derived data and result bundle back** — see `release_scratch`
# below for why that is a correctness matter and not tidiness. The logs always survive.
#
# ## Environment
#
#   FOCUS_RUN_TOKEN        the per-run suffix. Default <UTC timestamp>-<pid>
#   FOCUS_DERIVED_DATA     default /tmp/focus-dd-$FOCUS_RUN_TOKEN. Pinning it also means the
#                          gate will not delete it: a pinned path is the caller's
#   FOCUS_LOG_DIR          default /tmp/focus-gate-$FOCUS_RUN_TOKEN. Never deleted
#   FOCUS_RESULT_BUNDLE    default $FOCUS_LOG_DIR/focus-e01-$FOCUS_RUN_TOKEN.xcresult
#   FOCUS_KEEP_DERIVED_DATA  set to keep a green run's derived data and result bundle too
#   FOCUS_EVIDENCE_DIR     if set, the whole evidence set is assembled there under the names
#                          the epic's validation section asks for
#   FOCUS_SNAPSHOT_OUT     the directory the snapshot lane writes its renders into. See the
#                          note at SNAPSHOT_STAGING below: this names where to *look*, not
#                          where to write, and it is the one path the gate cannot make unique
set -u

REPO_ROOT="${0:A:h}/.."
cd "$REPO_ROOT" || exit 1

RUN_TOKEN="${FOCUS_RUN_TOKEN:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"

# Whether the gate derived these paths itself, decided *here* — before the export below
# overwrites the caller's view of FOCUS_DERIVED_DATA, and before `release_scratch` has to
# answer "is this mine to delete?". A pinned path belongs to whoever pinned it.
if [[ -n "${FOCUS_DERIVED_DATA:-}" ]]; then DD_IS_OURS=0; else DD_IS_OURS=1; fi

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
if [[ -n "${FOCUS_RESULT_BUNDLE:-}" ]]; then RB_IS_OURS=0; else RB_IS_OURS=1; fi

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

# Give this run's scratch back to the volume.
#
# Incident inc-01: the disk hit ENOSPC mid-epic and Bash could not create so much as a tool
# output file. The gate's contribution to that was structural rather than incidental. Giving
# every invocation its own derived-data tree is what stops two runs braiding their evidence
# together — but it also meant every invocation left three quarters of a gigabyte behind for
# ever, and nine green runs is seven gigabytes. The failure mode that buys is the worst one a
# gate has: a build that dies on a full volume does not fail a check, it produces no exit
# status at all, so the run reports no failing stage and no verdict rather than a red one.
#
# So a run that owns its scratch frees it, under three bounds:
#
#   * only paths the gate derived from the run token. A caller who pinned FOCUS_DERIVED_DATA
#     or FOCUS_RESULT_BUNDLE asked for that path deliberately and gets it back untouched —
#     deleting a warm tree somebody else is using is the same contamination in reverse.
#   * never the log directory. The stage logs *are* the evidence, they are kilobytes, and
#     they are what a human reads afterwards. Only the derived data and the result bundle go,
#     and both are regenerable by construction.
#   * only after a green run. A red one keeps everything, because the inside of a failed
#     build is exactly the thing you then need to look at.
#
# FOCUS_KEEP_DERIVED_DATA=1 keeps it either way, for an inner loop that wants a warm tree
# without pinning a path two runs could then share.
release_scratch() {
    local verdict="$1"

    if [[ -n "${FOCUS_KEEP_DERIVED_DATA:-}" ]]; then
        print "GATE scratch kept (FOCUS_KEEP_DERIVED_DATA is set): $DD"
        return 0
    fi
    if [[ "$verdict" == "fail" ]]; then
        print "GATE scratch kept for the failure: $DD"
        return 0
    fi

    if (( DD_IS_OURS )) && [[ -d "$DD" ]]; then
        rm -rf -- "$DD" && print "GATE freed this run's derived data: $DD"
    elif (( ! DD_IS_OURS )); then
        print "GATE derived data was pinned by the caller and is left alone: $DD"
    fi
    if (( RB_IS_OURS )) && [[ -e "$RB" ]]; then
        rm -rf -- "$RB" && print "GATE freed this run's result bundle: $RB"
    fi
    print "GATE logs kept: $LOG_DIR"
    return 0
}

# Packaging — the assertions exit status cannot make (e02 R-15, probes P-66a/P-66b).
#
# `CFBundleURLTypes` is an array of dictionaries, which no `INFOPLIST_KEY_*` build setting can
# express, so it ships as a partial `Config/FocusSentinel-Info.plist` merged with the generated
# one. Measured: putting that partial file in `App/` instead builds **green** and still gets it
# wrong — `App/` is a `PBXFileSystemSynchronizedRootGroup`, so the plist joins Copy Bundle
# Resources, the log gains `warning: The Copy Bundle Resources build phase contains this
# target's Info.plist file …`, and the product ships a second, misleading `Info.plist` inside
# `Contents/Resources/`. `EXCLUDED_SOURCE_FILE_NAMES` does not suppress it.
#
# A green build is therefore not evidence that the packaging is right. These three reads are:
# the warning is absent from both build logs, neither product has a stray resource plist, and
# the merged plist still carries the scheme on both configurations.
check_packaging() {
    local rc=0 config log app warnings key
    for config in Debug Release; do
        if [[ "$config" == "Debug" ]]; then
            log="$LOG_DIR/focus-build.log"
        else
            log="$LOG_DIR/focus-build-release.log"
        fi
        app="$DD/Build/Products/$config/FocusSentinel.app"

        if [[ ! -f "$log" ]]; then
            print -u2 "FAIL [$config] no build log at $log"
            rc=1
            continue
        fi

        warnings=$(grep -c "Copy Bundle Resources build phase contains" "$log" 2>/dev/null)
        if [[ "$warnings" != "0" ]]; then
            print -u2 "FAIL [$config] $warnings Copy-Bundle-Resources Info.plist warning(s) in $log"
            print -u2 "    The partial plist has drifted back inside the synchronized App/ group."
            print -u2 "    It belongs at Config/FocusSentinel-Info.plist (plan R-15, probe P-66b)."
            rc=1
        else
            print "ok   [$config] no Copy-Bundle-Resources Info.plist warning"
        fi

        if [[ ! -d "$app" ]]; then
            print -u2 "FAIL [$config] no app bundle at $app"
            rc=1
            continue
        fi

        if [[ -e "$app/Contents/Resources/Info.plist" ]]; then
            print -u2 "FAIL [$config] the product ships a stray Contents/Resources/Info.plist"
            rc=1
        else
            print "ok   [$config] Contents/Resources holds no Info.plist"
            print "     $(ls -1 -- "$app/Contents/Resources" | tr '\n' ' ')"
        fi

        if /usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' \
            "$app/Contents/Info.plist" 2>/dev/null | grep -qx 'focus'; then
            print "ok   [$config] the merged Info.plist declares the focus scheme"
        else
            print -u2 "FAIL [$config] the merged Info.plist does not declare the focus scheme"
            rc=1
        fi

        # The generated keys have to survive the merge too — that is the half P-66 measured and
        # the half a hand-written plist would silently take away.
        for key in CFBundleDisplayName LSMinimumSystemVersion NSPrincipalClass CFBundleIdentifier; do
            if /usr/libexec/PlistBuddy -c "Print :$key" "$app/Contents/Info.plist" > /dev/null 2>&1; then
                print "ok   [$config] the merged Info.plist still carries $key"
            else
                print -u2 "FAIL [$config] the merged Info.plist lost the generated key $key"
                rc=1
            fi
        done
    done
    return $rc
}

# SC-1's binary half needs one product the workspace scheme does not build: `Tools/windowid`
# is a standalone SwiftPM package outside `Packages/`, so nothing in stages 5–7 produces it.
# Building it here is what lets the check treat a missing product as a failure rather than a
# skipped line — an absent binary must never be the reason a symbol check passes.
forbidden_binary_stage() {
    swift build -c release --package-path Tools/windowid || return $?
    FOCUS_REQUIRE_BINARY_CHECK=1 scripts/check-forbidden.sh
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

    # 6a — packaging, read from the two logs and the two products stages 5 and 6 just made.
    # Zero grants, and it catches the one failure a green build cannot (see check_packaging).
    run_stage "packaging" "$LOG_DIR/focus-packaging.log" check_packaging

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

    # 7c — the binary half of SC-1, for the same reason and in the same shape (e03 R-32).
    # `kCGWindowName` is an exported CFStringRef, so a reference to it leaves
    # `_kCGWindowName` among an object's undefined symbols; a grep can be defeated by
    # building the string at runtime, and the symbol cannot. Stage 3 runs before anything is
    # built and reports a skip; this run promotes that skip to a failure, over seven products
    # named one by one — the app binary, the five package objects and `Tools/windowid`.
    #
    # `windowid` is built here rather than assumed, because it lives outside the workspace
    # scheme and stages 5 and 6 therefore never touch it. The check also asserts the four
    # sanctioned window-list symbols are still *present* in it, so the tool cannot pass by
    # having been gutted.
    run_stage "forbidden-binary" "$LOG_DIR/focus-forbidden-binary.log" \
        forbidden_binary_stage

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
        "focus-forbidden-binary.log:forbidden-binary.log"
        "focus-strings.log:strings.log"
        "focus-build.log:build-debug.log"
        "focus-build-release.log:build-release.log"
        "focus-packaging.log:packaging.log"
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

# An interrupted run has no verdict and no reader, and the interruption is quite likely to
# have been the full volume itself. Free its scratch on the way out rather than leaving the
# largest object of the run behind at the worst possible moment.
trap 'release_scratch aborted; exit 130' INT
trap 'release_scratch aborted; exit 143' TERM

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

# Last of all, and only now: every stage, the packaging reads, the entitlement checks and both
# self-checks have finished with the build products, and the evidence set has been copied out
# of the log directory, which this never touches.
if (( gate_rc == 0 )); then
    release_scratch pass
else
    release_scratch fail
fi

exit $gate_rc
