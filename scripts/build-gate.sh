#!/bin/zsh
# The build gate.
#
#   scripts/build-gate.sh
#
# Ten stages. Every build and test command redirects **unpiped** to its own log file — no
# `tee`, no `xcpretty`, no `| grep` — and is judged on its exit status alone. A build whose
# output was piped into something is not a verified build.
#
# The gate does **not** short-circuit: every stage runs, so one early failure cannot hide
# three later ones. It prints a summary table and exits non-zero if any stage failed.
#
# ## Zero grants, by construction
#
# Nothing here needs Accessibility, Screen Recording or Automation — not for the app, and
# not for the shell that invokes it. Revoking every permission on this Mac must still leave
# a green gate. That is why the live `osascript` + `screencapture` lane is not a stage: it
# produces evidence a human reads, never a pass/fail criterion, and the gate never invokes
# it.
#
# ## Environment
#
#   FOCUS_DERIVED_DATA     default /tmp/focus-dd
#   FOCUS_LOG_DIR          default /tmp
#   FOCUS_RESULT_BUNDLE    default a unique timestamped path under $FOCUS_LOG_DIR
#   FOCUS_EVIDENCE_DIR     if set, logs and the self-check JSON are copied here at the end
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

{
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

    # 8 — entitlements, on both configurations
    run_stage "entitlements-debug" "$LOG_DIR/focus-entitlements.log" \
        scripts/entitlement-check.sh "$DD/Build/Products/Debug/FocusSentinel.app"
    run_stage "entitlements-release" "$LOG_DIR/focus-entitlements-release.log" \
        scripts/entitlement-check.sh "$DD/Build/Products/Release/FocusSentinel.app"

    # 9 — the zero-grant shell self-check, on both configurations
    run_stage "selfcheck-debug" "$LOG_DIR/focus-selfcheck.log" \
        scripts/self-check.sh "$DD/Build/Products/Debug/FocusSentinel.app"
    run_stage "selfcheck-release" "$LOG_DIR/focus-selfcheck-release.log" \
        scripts/self-check.sh "$DD/Build/Products/Release/FocusSentinel.app"

    # 10 — project integrity again. Stages 5–7 are the ones that could provoke a rewrite.
    run_stage "project-post" "$LOG_DIR/focus-project-post.log" scripts/verify-project.sh

    # --- summary --------------------------------------------------------------------------

    failed=0
    print
    print "=============================================================="
    printf '%-24s %-6s %s\n' "STAGE" "EXIT" "LOG"
    print "--------------------------------------------------------------"
    for i in {1..${#STAGE_NAMES}}; do
        printf '%-24s %-6s %s\n' "${STAGE_NAMES[$i]}" "${STAGE_CODES[$i]}" "${STAGE_LOGS[$i]}"
        (( STAGE_CODES[$i] != 0 )) && failed=1
    done
    print "--------------------------------------------------------------"
    print "result bundle: $RB"
    print "finished:      $(date -u +%Y-%m-%dT%H:%M:%SZ)"

    if (( failed == 0 )); then
        print "GATE RESULT: PASS"
    else
        print "GATE RESULT: FAIL"
    fi
    print "=============================================================="

    if [[ -n "${FOCUS_EVIDENCE_DIR:-}" ]]; then
        mkdir -p -- "$FOCUS_EVIDENCE_DIR"
        for i in {1..${#STAGE_LOGS}}; do
            [[ -f "${STAGE_LOGS[$i]}" ]] && cp -- "${STAGE_LOGS[$i]}" "$FOCUS_EVIDENCE_DIR/"
        done
        print "evidence copied to $FOCUS_EVIDENCE_DIR"
    fi

    exit $failed
# Unpiped, like every stage inside it: the gate's own summary is redirected to a file, never
# piped through `tee`. It is echoed to the terminal afterwards by reading the file back.
} > "$GATE_LOG" 2>&1
gate_rc=$?

cat -- "$GATE_LOG"
exit $gate_rc
