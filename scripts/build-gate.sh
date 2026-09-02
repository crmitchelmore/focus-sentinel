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
# not for the shell that invokes it. That includes e05's two new stages: `focus-steal` launches
# the app with `open -g -a` (LaunchServices) and reads the frontmost application with
# `lsappinfo` (a plain system query), and `notification-denied` is a plain `exec` of the built
# binary. The one behaviour neither can prove — that a person typing while the panel is on
# screen keeps their keystrokes — needs a synthetic key event and therefore an Accessibility
# grant, so it lives in the live lane (§4.9 frame 17) as read evidence rather than here. Revoking every permission on this Mac must still leave
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

# --- e04: the evaluation lane, and R-75's staleness guard ---------------------------------
#
# The snapshot lane above documents the constraint and misses one hazard, and the evaluation
# lane must not inherit it: **the staging path is shared between runs and nothing deletes it**.
# A report left behind by an earlier green tree would be parsed as this run's evidence, and a
# gate whose central number can be satisfied by a file nobody wrote today is not a gate.
#
# So the evaluation lane is two stages rather than one:
#
#   6b  eval-clean   removes $FOCUS_EVAL_OUT in its entirety and touches an mtime marker,
#                    immediately before `unit`. A missing directory is a pass; a failure to
#                    remove is a hard fail. This is the only cleanup stage in the gate.
#   7d  evaluation   runs the `FocusEvaluate` product, copies its report into this run's log
#                    directory **before** anything parses it, applies R-75's five binding
#                    checks to the copy, and only then reports the metric verdict.
#
# Emission is a *product* rather than a test side effect (R-75) for the same reason the
# snapshot note gives: `xcodebuild` does not carry an environment value into a SwiftPM test
# target's process, and a plain process does. `FocusEvaluate` is a test-lane product — no
# application target links it, and `check-boundaries.sh` asserts that rather than assuming it.
EVAL_STAGING="${FOCUS_EVAL_OUT:-${TMP_ROOT%/}/focus-eval}"
EVAL_STAGING="${EVAL_STAGING%/}"
EVAL_STAGED_REPORT="$EVAL_STAGING/evaluation.json"

# This run's own copy — the bytes the gate asserts on and the bytes it archives are the same
# bytes, which is binding check B5.
EVAL_REPORT="$LOG_DIR/evaluation.json"
EVAL_MARKER="$LOG_DIR/focus-eval.marker"
EVAL_LOG="$LOG_DIR/focus-evaluate.log"

# The run token the report must carry (R-75.2). The per-run log directory's basename is
# already unique per run, so there is nothing new to mint and nothing that can collide.
GATE_RUN_ID="${LOG_DIR:t}"

CORPUS_DIR="Packages/FocusClassify/Tests/FocusClassifyTests/Resources/GoldenCorpus"

# The committed engine literals, read from the one place they are written down.
#
# R-75.4 wants three legs to agree — the test process, the evaluation report and the running
# application — and the way to get that without three copies of a string is for each leg to
# compare against the *same* literal. `scripts/self-check.sh` reads these two lines the same
# way for the third leg; the literals themselves live only in the two suites that assert them.
committed_literal() {
    local file="$1" name="$2" line
    line=$(grep -E "static let ${name}\b" "$REPO_ROOT/$file" 2>/dev/null | head -1)
    [[ -n "$line" ]] || return 0
    print -r -- "${${line#*= }//[\"_ ]/}"
}

COMMITTED_STAMP=$(committed_literal \
    "Packages/FocusCore/Tests/FocusCoreTests/EngineStampTests.swift" \
    "committedRuntimeCacheKey")
COMMITTED_DIGEST=$(committed_literal \
    "Packages/FocusCore/Tests/FocusCoreTests/RelevancePolicyTests.swift" \
    "committedDigest")
# e05's own digest. Two policies, two digests, one stamp: the nudge's thresholds are deliberately
# NOT in `RelevancePolicy`, so that tuning a cooldown cannot invalidate e06's verdict cache
# (R-95) — which also means `policyDigest` is blind to a nudge threshold moving, and B3 would
# certify a report whose numbers no longer describe the app. Hence the third literal.
COMMITTED_INTERVENTION_DIGEST=$(committed_literal \
    "Packages/FocusCore/Tests/FocusCoreTests/InterventionPolicyTests.swift" \
    "committedDigest")

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

# Stage 7' — unit-counts (focus-jg7). **The gate must be able to see a test bundle die.**
#
# ## What happened, and why the exit status did not catch it
#
# Gate run `finalgate`, 2026-09-02: 19 of 20 stages `EXIT=0`, `unit` `EXIT=65`, and EVERY TEST
# PASSED — zero `Issue recorded` in a 124 000-line log, all six bundles printing `passed`. The
# `FocusHost` bundle ran FIVE tests in ONE suite where it runs about 200, and then the run
# ended. `xcodebuild` printed `** TEST FAILED **` with no failing-test summary, which is what a
# bundle *dying* rather than a test *failing* looks like. The cause was a CoreAudio listener
# calling `MainActor.assumeIsolated` off the main queue (focus-068): SIGTRAP, mid-suite.
#
# The exit status did catch that one. What it cannot catch is the same death on a run whose
# `xcodebuild` recovers — `Restarting after unexpected exit, crash, or test timeout; summary
# will include totals from previous launches` is a retry, and a retry that then passes exits
# `0` having run a fraction of the suite. Totals: 1729 that day against 1863 the run before.
# Nothing in the gate compared those numbers or complained.
#
# ## So three readings, and each has a state it goes red in
#
# 1. **The log names a death.** `Program crashed`, `Restarting after unexpected exit`, or a
#    `Test Suite 'Selected tests' started` retry banner — measured absent from a clean six-bundle
#    log (`focus-gate-20260831T215543Z-27482`: zero occurrences of all three) and present in the
#    `finalgate` one. Judged REGARDLESS OF EXIT STATUS, because the recovering case is the one
#    the exit status hides.
# 2. **Six bundles reported.** Fewer `Test run with N tests` lines than the scheme has testables
#    means a bundle produced no summary at all, which is the loudest form of the same failure.
# 3. **Each bundle is at or above its committed floor**, from `Config/test-floors.txt`, paired
#    with the summary lines POSITIONALLY in the scheme's testable order. Floors, never
#    equalities: adding a test may not redden the gate, and losing one must.
#
# It is a stage of its own rather than a line inside `unit`, for the reason stage 7d is:
# it has to fail the gate *on a number*, and a number that only lives inside an `.xcresult` is a
# number nobody reads.
unit_counts_stage() {
    local log="$LOG_DIR/focus-test.log"
    local floors="Config/test-floors.txt"
    local rc=0

    print "unit log:   $log"
    print "floors:     $floors"

    if [[ ! -f "$log" ]]; then
        print -u2 "FAIL [unit-counts] there is no unit-lane log at $log"
        print -u2 "    A missing log is not an absent reading, it is an unread one."
        return 1
    fi
    if [[ ! -f "$floors" ]]; then
        print -u2 "FAIL [unit-counts] the committed floors are missing at $floors"
        return 1
    fi

    # --- 1: the log names a death ---------------------------------------------------------
    local -a DEATH_MARKERS=(
        "Program crashed"
        "Restarting after unexpected exit"
        "Test Suite 'Selected tests' started"
    )
    local marker hits
    for marker in $DEATH_MARKERS; do
        hits=$(grep -c -F -- "$marker" "$log")
        if (( hits > 0 )); then
            print -u2 "FAIL [unit-counts] the unit log contains '$marker' ($hits)"
            print -u2 "    A bundle died or was restarted mid-run. Every test that ran may well"
            print -u2 "    have passed; the ones that never ran are the reading that matters."
            rc=1
        else
            print "ok   [unit-counts] no '$marker' in the unit log"
        fi
    done

    # --- 2 and 3: the six summaries, positionally against the committed floors -------------
    local -a NAMES FLOOR_VALUES COUNTS
    local line name value
    while IFS= read -r line; do
        [[ "$line" == \#* || -z "${line// /}" ]] && continue
        name="${line%% *}"
        value="${line##* }"
        NAMES+=("$name")
        FLOOR_VALUES+=("$value")
    done < "$floors"

    COUNTS=(${(f)"$(grep -o 'Test run with [0-9]* tests' "$log" | grep -o '[0-9]*')"})

    print "     [unit-counts] ${#NAMES} floors committed, ${#COUNTS} bundle summaries in the log"
    if (( ${#COUNTS} < ${#NAMES} )); then
        print -u2 "FAIL [unit-counts] only ${#COUNTS} of ${#NAMES} bundles reported a test run"
        print -u2 "    Counts seen: ${COUNTS}"
        print -u2 "    A bundle that printed no summary produced no evidence, whatever the"
        print -u2 "    lane's exit status says."
        rc=1
    fi

    local i floor count
    for i in {1..${#NAMES}}; do
        name="${NAMES[$i]}"
        floor="${FLOOR_VALUES[$i]}"
        count="${COUNTS[$i]:-}"
        if [[ -z "$count" ]]; then
            print -u2 "FAIL [unit-counts] $name reported no test count at all (floor $floor)"
            rc=1
            continue
        fi
        if (( count < floor )); then
            print -u2 "FAIL [unit-counts] $name ran $count tests, below its committed floor of $floor"
            print -u2 "    Either tests were deleted — in which case say so and lower the floor in"
            print -u2 "    Config/test-floors.txt — or the bundle did not finish."
            rc=1
        else
            print "ok   [unit-counts] $name ran $count tests (floor $floor)"
        fi
    done

    if (( ${#COUNTS} > ${#NAMES} )); then
        print -u2 "FAIL [unit-counts] ${#COUNTS} bundles reported but only ${#NAMES} floors are committed"
        print -u2 "    A testable was added to the scheme without a floor. Add its line to"
        print -u2 "    Config/test-floors.txt, in the scheme's order — the pairing is positional."
        rc=1
    fi

    return $rc
}

# Stage 6b — eval-clean (R-75.1, R-75.3).
#
# Delete the shared staging directory in its entirety, then touch the marker every later
# freshness comparison is made against. It runs immediately before `unit` so that nothing
# between the deletion and the emission can leave a file the gate would then believe.
#
# A missing directory is a **pass**: there is nothing stale if there is nothing at all. A
# failure to remove is a **hard fail**, because a staging directory that survived a `rm -rf` is
# exactly the condition under which a stale report reaches the parser.
eval_clean_stage() {
    print "staging directory: $EVAL_STAGING"

    if [[ -e "$EVAL_STAGING" ]]; then
        if ! rm -rf -- "$EVAL_STAGING"; then
            print -u2 "FAIL [R-75.1] could not remove $EVAL_STAGING"
            return 1
        fi
        print "ok   removed the staging directory"
    else
        print "ok   nothing to remove (a missing staging directory is a pass)"
    fi

    if [[ -e "$EVAL_STAGING" ]]; then
        print -u2 "FAIL [R-75.1] $EVAL_STAGING is still present after rm -rf"
        return 1
    fi

    rm -f -- "$EVAL_MARKER"
    if ! : > "$EVAL_MARKER"; then
        print -u2 "FAIL [R-75.3] could not write the mtime marker at $EVAL_MARKER"
        return 1
    fi
    print "ok   marker touched: $EVAL_MARKER"
    print "     any report not newer than this marker is not this run's evidence"
    print "run token: $GATE_RUN_ID"
    return 0
}

# Stage 7d — evaluation (R-67, R-75, §4.4).
#
# Order matters and is the ruling rather than a preference. The report is copied out of staging
# **before** anything parses it; R-75's five binding checks are applied to that copy **first**;
# and only then is the metric verdict reported. A stale or foreign report is not a failing
# number — it is *no evidence at all* — and reporting it as a metric failure would send a
# reader looking in the wrong place.
#
# The metric thresholds themselves are **not** restated here. They live in
# `FocusEvaluateCore.EvaluationGate`, which `FocusEvaluate` decides its exit status from and
# which `EvaluationGateTests` asserts in the unit lane, so `swift test` alone still catches a
# metric regression. Writing the twelve numbers into this script a second time would be the
# fifth-place drift R-54 forbids everywhere else in this epic.
evaluation_stage() {
    # Unpiped, into a log of its own, judged on exit status — the same doctrine every build
    # command in this gate follows. The log is printed at the foot of this stage rather than
    # here, so the binding verdict is what a reader meets first.
    FOCUS_EVAL_OUT="$EVAL_STAGING" FOCUS_GATE_RUN_ID="$GATE_RUN_ID" \
        swift run --package-path Packages/FocusClassify -c release FocusEvaluate \
        > "$EVAL_LOG" 2>&1
    local produce_rc=$?

    if [[ ! -f "$EVAL_STAGED_REPORT" ]]; then
        print -u2 "FAIL [R-75] FocusEvaluate wrote no report at $EVAL_STAGED_REPORT (EXIT=$produce_rc)"
        print
        cat -- "$EVAL_LOG"
        return 1
    fi

    rm -f -- "$EVAL_REPORT"
    if ! cp -- "$EVAL_STAGED_REPORT" "$EVAL_REPORT"; then
        print -u2 "FAIL [R-75] could not copy the report to $EVAL_REPORT"
        return 1
    fi
    print "report copied from $EVAL_STAGED_REPORT"
    print "                to $EVAL_REPORT"
    print

    print "== R-75 binding checks (evaluated before any metric)"
    python3 - \
        "$EVAL_REPORT" "$EVAL_STAGED_REPORT" "$EVAL_MARKER" "$GATE_RUN_ID" \
        "$COMMITTED_STAMP" "$COMMITTED_DIGEST" "$REPO_ROOT/$CORPUS_DIR" \
        "$COMMITTED_INTERVENTION_DIGEST" <<'PYTHON'
import hashlib
import json
import os
import sys

parsed_path, staging_path, marker_path = sys.argv[1], sys.argv[2], sys.argv[3]
expected_run_id, expected_stamp, expected_digest = sys.argv[4], sys.argv[5], sys.argv[6]
corpus_dir = sys.argv[7]
expected_intervention_digest = sys.argv[8]

failures = []


def check(condition, message, detail=None):
    if condition:
        print(f"ok   {message}")
        return
    line = f"FAIL {message}"
    if detail is not None:
        line += f"\n      got: {detail!r}"
    failures.append(line)
    print(line, file=sys.stderr)


with open(parsed_path) as handle:
    report = json.load(handle)

# --- B1 · the report names this run ------------------------------------------------------
#
# The assertion that survives even if the pre-`unit` deletion silently no-ops. Belt as well as
# braces, because the failure mode is *accepting stale evidence*, which is invisible when it
# happens.
check(
    report.get("runID") == expected_run_id,
    f"B1 runID is this run's token ({expected_run_id})",
    report.get("runID"),
)

# --- B2 · newer than the marker the gate touched before `unit` ---------------------------
try:
    report_mtime = os.stat(parsed_path).st_mtime
    marker_mtime = os.stat(marker_path).st_mtime
except OSError as error:
    report_mtime = marker_mtime = None
    check(False, "B2 the report and the marker both exist", str(error))

if report_mtime is not None:
    # A check that cannot be performed has not been performed; there is no benefit of the
    # doubt here, because an unperformed check reads exactly like a green one.
    check(
        report_mtime > marker_mtime,
        "B2 the report is newer than the eval-clean marker",
        (report_mtime, marker_mtime),
    )

# --- B3 · the same engine ----------------------------------------------------------------
#
# Compared against the committed literals the unit lane asserts of the test process and both
# self-checks assert of the running application. Three legs, one set of literals.
check(bool(expected_stamp), "B3 the committed engine stamp was found in EngineStampTests", expected_stamp)
check(bool(expected_digest), "B3 the committed policy digest was found in RelevancePolicyTests", expected_digest)
check(
    report.get("stamp") == expected_stamp,
    f"B3 the report was produced by engine {expected_stamp}",
    report.get("stamp"),
)
check(
    report.get("policyDigest") == expected_digest,
    f"B3 the report's policy digest is {expected_digest}",
    report.get("policyDigest"),
)
# e05's third digest. `policyDigest` cannot see a nudge threshold move — that is the point of
# giving the nudge its own manifest — so without this line B3 would happily certify a report whose
# caps, cooldowns and snooze durations are not the ones the app is running.
check(
    bool(expected_intervention_digest),
    "B3 the committed intervention digest was found in InterventionPolicyTests",
    expected_intervention_digest,
)
check(
    (report.get("nudge") or {}).get("interventionDigest") == expected_intervention_digest,
    f"B3 the report's intervention digest is {expected_intervention_digest}",
    (report.get("nudge") or {}).get("interventionDigest"),
)

# --- B4 · the same corpus ----------------------------------------------------------------
#
# FNV-1a over the concatenated corpus bytes, in sorted relative-path order, with each path
# hashed alongside its own bytes so that renaming a file changes the digest. FNV-1a and never
# a language hash: P-118 measured Swift's `Hasher` returning a different value for identical
# data in two processes, and Python's own `hash()` is salted per process for the same reason.
FNV_OFFSET = 0xCBF29CE484222325
FNV_PRIME = 0x100000001B3
MASK = 0xFFFFFFFFFFFFFFFF


def fnv1a(data):
    value = FNV_OFFSET
    for byte in data:
        value ^= byte
        value = (value * FNV_PRIME) & MASK
    return value


def corpus_entries(directory):
    entries = []
    for name in ("baseline", "rules", "heuristic", "adversarial"):
        path = os.path.join(directory, f"{name}.json")
        if os.path.exists(path):
            with open(path, "rb") as handle:
                entries.append((f"{name}.json", handle.read()))
    # The sequences AND the realistic days: both are corpus files, and `queriesPerFocusDay` and
    # `interruptionsPerFocusDayMax` are measured on the days alone. A digest that did not cover
    # them would let a day fixture be edited under a report that still bound.
    for subdirectory in ("sequences", "days"):
        path = os.path.join(directory, subdirectory)
        if not os.path.isdir(path):
            continue
        for name in sorted(os.listdir(path)):
            if not name.endswith(".json"):
                continue
            with open(os.path.join(path, name), "rb") as handle:
                entries.append((f"{subdirectory}/{name}", handle.read()))
    return entries


accumulated = bytearray()
entries = corpus_entries(corpus_dir)
for path, data in sorted(entries, key=lambda entry: entry[0]):
    accumulated += path.encode("utf-8")
    accumulated += data
recomputed = f"0x{fnv1a(bytes(accumulated)):016x}"

check(bool(entries), f"B4 the corpus was read from the working tree ({len(entries)} file(s))", corpus_dir)
check(
    report.get("corpusDigest") == recomputed,
    "B4 the report describes the corpus on disk",
    (report.get("corpusDigest"), recomputed),
)

# --- B5 · the bytes parsed are this run's copy of what the product wrote -------------------
#
# **This row used to compare two paths the script had computed from its own constants**
# (focus-bkf): `parsed_path != staging_path` is a statement about two shell variables, and no
# state of the product, the report or the filesystem could falsify it. It was green by
# construction, under a sentence claiming something about bytes.
#
# The claim is about bytes, so bytes are what it reads. Three readings, and each has a state it
# goes red in: the copy exists and is not empty; it is a *different file* from the staging one
# (device and inode, not spelling, so a symlink or a second name for the same file is caught);
# and it is byte-identical to the report `FocusEvaluate` actually wrote, which is what makes
# "the copy is this run's evidence" a fact rather than a naming convention.
try:
    with open(parsed_path, "rb") as handle:
        parsed_bytes = handle.read()
    with open(staging_path, "rb") as handle:
        staged_bytes = handle.read()
    parsed_stat = os.stat(parsed_path)
    staged_stat = os.stat(staging_path)
except OSError as error:
    parsed_bytes = staged_bytes = parsed_stat = staged_stat = None
    check(False, "B5 both the parsed copy and the staged report could be read", str(error))

if parsed_bytes is not None:
    check(
        len(parsed_bytes) > 0,
        f"B5 the parsed copy carries the report's bytes ({len(parsed_bytes)} of them)",
        parsed_path,
    )
    check(
        (parsed_stat.st_dev, parsed_stat.st_ino) != (staged_stat.st_dev, staged_stat.st_ino),
        "B5 the parsed bytes are the per-run copy, not the shared staging file",
        (parsed_path, staging_path),
    )
    parsed_digest = hashlib.sha256(parsed_bytes).hexdigest()
    staged_digest = hashlib.sha256(staged_bytes).hexdigest()
    check(
        parsed_digest == staged_digest,
        f"B5 the copy is byte-identical to the report FocusEvaluate wrote ({parsed_digest[:16]})",
        (parsed_digest, staged_digest),
    )

print()
if failures:
    print(f"BINDING CHECKS FAILED — {len(failures)} of 5 (the report is NOT this run's evidence)", file=sys.stderr)
    sys.exit(1)
print("BINDING CHECKS OK — the report is this run's evidence; the metrics below are about it")
PYTHON
    local binding_rc=$?

    print
    print "== FocusEvaluate (emission and the committed metric thresholds of §4.4)"
    cat -- "$EVAL_LOG"

    if (( binding_rc != 0 )); then
        print
        print -u2 "FAIL [R-75] the report is not this run's evidence; its numbers certify nothing"
        return 1
    fi
    return $produce_rc
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

    # 6b — eval-clean. The only cleanup stage in the gate, and it runs immediately before
    # `unit` so that nothing between the deletion and stage 7d's emission can leave a file the
    # gate would then believe (R-75.1/3).
    run_stage "eval-clean" "$LOG_DIR/focus-eval-clean.log" eval_clean_stage

    # 7 — the headless unit lane, the only lane that compiles String Catalogs
    rm -rf -- "$RB"
    run_stage "unit" "$LOG_DIR/focus-test.log" \
        xcodebuild -workspace Focus.xcworkspace -scheme FocusUnitTests \
        -destination "$DESTINATION" -derivedDataPath "$DD" -resultBundlePath "$RB" test

    # 7' — unit-counts. Immediately after `unit`, because it reads that stage's log, and
    # before the snapshot copy so that a bundle which died is reported before anything else
    # this run produces is read as though the suite had finished.
    run_stage "unit-counts" "$LOG_DIR/focus-unit-counts.log" unit_counts_stage

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

    # 7d — the evaluation lane. It runs **before** the binary stages so that a metric
    # regression is visible in the same summary table as a symbol regression, and it runs the
    # `FocusEvaluate` product rather than reading a test's leavings (R-75). It is a separate
    # stage rather than a test assertion because it has to fail the gate *on a number*, and a
    # number that only lives inside an `.xcresult` is a number nobody reads.
    run_stage "evaluation" "$LOG_DIR/focus-evaluation.log" evaluation_stage

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
    # 9a — focus-steal (§4.5, R-89, P-128, P-139). **The epic's headline gate.**
    #
    # Launches the Debug app with `open -g -a` — a background application that has never been
    # frontmost, which is the posture a nudge really fires in — shows the panel, and asserts all
    # FOUR of R-89's grant-free readings. Reading 1 comes from an independent observer process,
    # because a stage that took every reading from inside the app under test would be trusting the
    # app to report on itself; readings 2-4 can only come from inside, which is what the
    # self-check channel is for. P-139 measured a focus theft that reading 1 alone cannot see.
    FOCUS_FOCUS_STEAL_JSON="$LOG_DIR/focus-focus-steal.json" \
        run_stage "focus-steal" "$LOG_DIR/focus-focus-steal.log" \
        scripts/check-focus-steal.sh "$DD/Build/Products/Debug/FocusSentinel.app"

    # 9b — notification-denied (§4.5, R-82, P-134). **This discharges standing condition 5.**
    #
    # Zero grants, no prompt of any kind, and the whole ladder still reaches somebody: every rung
    # in-app at both unauthorised states, the top rung on the panel, and
    # `requestAuthorizationCallCount == 0`.
    FOCUS_NOTIFICATION_DENIED_JSON="$LOG_DIR/focus-notification-denied.json" \
        run_stage "notification-denied" "$LOG_DIR/focus-notification-denied.log" \
        scripts/check-notification-denied.sh "$DD/Build/Products/Debug/FocusSentinel.app"

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
    print "evaluation:     $EVAL_REPORT (staged in $EVAL_STAGING, run token $GATE_RUN_ID)"
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
        "focus-focus-steal.log:focus-steal.log"
        "focus-focus-steal.json:focus-steal.json"
        "focus-notification-denied.log:notification-denied.log"
        "focus-notification-denied.json:notification-denied.json"
        "focus-selfcheck-release.json:selfcheck-release.json"
        "focus-eval-clean.log:eval-clean.log"
        "focus-evaluation.log:evaluation.log"
        "focus-evaluate.log:focus-evaluate.log"
        # The report itself, so a closing epic is audited from an artefact rather than from an
        # assertion about an artefact — and two runs of one tree produce two diffable files,
        # which P-118's determinism is what makes true (R-67, §4.4).
        "evaluation.json:evaluation.json"
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
