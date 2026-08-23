#!/bin/zsh
# The live session drive — TCC-GATED EVIDENCE, never a gate.
#
#   scripts/live-session-drive.sh
#
# Proves F-97's promise where a person can see it: a session that was running when the app died
# comes back with the **corrected** elapsed time, not a restarted one. Two artefacts, and they
# are deliberately different kinds of thing:
#
#   session-reconciliation.json  AUTOMATED. Two separate process launches against a store of
#                                their own — one seeds a session back-dated ninety minutes and
#                                exits, the other opens it, reconciles it and reports. This is
#                                the same proof the zero-grant gate makes, recorded here so the
#                                evidence set carries it beside the frame.
#   relaunch-mid-session.png     OPERATOR-ASSISTED. A person starts a session; the script then
#                                kills the app mid-session with `pkill`, relaunches it, and
#                                captures the cockpit.
#
# ## Why the frame needs a person, and why that is stated rather than worked around
#
# `osascript` is banned from every e03 lane. Probe P-103 reproduced e02's P-65 exactly:
# `osascript -e 'quit app "TextEdit"'` blocks on Automation consent and has to be killed. With no
# Apple Events and no Accessibility, this script has no sanctioned way to press a button, so
# *starting* the session is a physical action. Everything after it — the kill, the relaunch, the
# capture — is automated.
#
# What is **not** lost by that: the reconciliation itself is proved without anybody present, in
# this lane and in the gate. `scripts/self-check.sh` runs the same two-launch proof and asserts
# `startedAt` byte-identical, ninety minutes elapsed, `phase == paused`,
# `pauseCauses == ["relaunch"]`, `resumeTo == "focus"`, the same boot identity in both launches,
# and — the one thing no unit test can reach — the uptime anchor's difference between the two
# launches matching their wall-clock difference. The frame is a picture of a fact already
# established, which is what evidence is for.
#
# ## Why this is not a gate, and never may be
#
# Capturing another process's window needs Screen Recording on the *driving shell*. No acceptance
# criterion may depend on a TCC grant (standing condition 5), so when the grant is missing this
# script prints `LIVE-LANE SKIPPED` and exits **0**, and `scripts/build-gate.sh` never invokes it.
#
# ## Environment
#
#   FOCUS_EVIDENCE_DIR      where the artefacts land   (default .agents/evidence/e03)
#   FOCUS_DERIVED_DATA      build location             (default /tmp/focus-dd)
#   FOCUS_LOG_DIR           log location               (default /tmp)
#   FOCUS_OPERATOR_TIMEOUT  seconds to wait at the operator prompt (default 45)
set -u

REPO_ROOT="${0:A:h}/.."
cd "$REPO_ROOT" || exit 1

EVIDENCE_DIR="${FOCUS_EVIDENCE_DIR:-.agents/evidence/e03}"
DD="${FOCUS_DERIVED_DATA:-/tmp/focus-dd}"
LOG_DIR="${FOCUS_LOG_DIR:-/tmp}"
DESTINATION='platform=macOS,arch=arm64'
OPERATOR_TIMEOUT="${FOCUS_OPERATOR_TIMEOUT:-45}"

WINDOW_OWNER='Focus Sentinel'
PROCESS_NAME='FocusSentinel'
APP="$DD/Build/Products/Debug/FocusSentinel.app"

mkdir -p -- "$EVIDENCE_DIR" "$LOG_DIR" || exit 1

typeset -a PRODUCED RECEIPTS FAILED
PRODUCED=()
RECEIPTS=()
FAILED=()

note() { print "== $*" }
skip() { print "LIVE-LANE SKIPPED: $*"; exit 0 }

produced() { PRODUCED+=("$1"); print "LIVE-ARTEFACT $2: $1" }
fail_artefact() { FAILED+=("$1"); print -u2 "LIVE-ARTEFACT FAILED: $1 — $2" }

manual_required() {
    local artefact="$1" label="$2" reason="$3" steps="$4"
    RECEIPTS+=("$artefact")
    print "LIVE-ARTEFACT $label: $artefact — $reason"
    {
        print "MANUAL_REQUIRED: $artefact"
        print "label:  $label"
        print "date:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        print "host:   $(sw_vers -productVersion) ($(uname -m))"
        print
        print "why this run did not produce it"
        print "-------------------------------"
        print "$reason"
        print
        print "how to reproduce it"
        print "-------------------"
        print "$steps"
    } > "$EVIDENCE_DIR/${artefact}.MANUAL_REQUIRED.txt"
}

prompt_operator() {
    local instruction="$1"
    print
    print "OPERATOR: $instruction"
    print "OPERATOR: press Return within ${OPERATOR_TIMEOUT}s when it is done, or wait to skip."
    local answer
    read -t "$OPERATOR_TIMEOUT" -r answer && return 0
    print
    return 1
}

SESSION_DIR=""
cleanup() {
    pkill -x "$PROCESS_NAME" 2>/dev/null
    [[ -n "$SESSION_DIR" ]] && rm -rf -- "$SESSION_DIR"
    return 0
}
trap 'cleanup' EXIT INT TERM

SCREENCAPTURE="${commands[screencapture]:-/usr/sbin/screencapture}"

ARTEFACTS=(session-reconciliation.json relaunch-mid-session.png)
for artefact in $ARTEFACTS; do
    rm -f -- "$EVIDENCE_DIR/$artefact" "$EVIDENCE_DIR/${artefact}.MANUAL_REQUIRED.txt"
done

# --- 1 · build the app --------------------------------------------------------------------------

note "building the Debug app"
xcodebuild -workspace Focus.xcworkspace -scheme FocusSentinel \
    -configuration Debug -destination "$DESTINATION" -derivedDataPath "$DD" build \
    > "$LOG_DIR/focus-live-session-build.log" 2>&1
app_rc=$?
print "build EXIT=$app_rc log=$LOG_DIR/focus-live-session-build.log"
(( app_rc == 0 )) || { print -u2 "LIVE-LANE ERROR: the Debug build failed"; exit 1 }
[[ -d "$APP" ]] || { print -u2 "LIVE-LANE ERROR: no app bundle at $APP"; exit 1 }

BINARY="$APP/Contents/MacOS/FocusSentinel"

# --- 2 · session-reconciliation.json · AUTOMATED ------------------------------------------------
#
# Needs no grant of any kind, so it runs **before** the preflight: an evidence set that carries
# the reconciliation proof even on a machine with no Screen Recording is a better evidence set
# than one that skips wholesale.

note "the two-launch reconciliation proof"
SESSION_DIR="$(mktemp -d -t focus-live-session)"
SESSION_STORE="$SESSION_DIR/session.store"
SEED_JSON="$SESSION_DIR/seed.json"
RESTORE_JSON="$SESSION_DIR/restore.json"

"$BINARY" --focus-self-check "$SEED_JSON" --focus-session-seed "$SESSION_STORE" \
    > "$LOG_DIR/focus-live-session-seed.log" 2>&1
seed_rc=$?
"$BINARY" --focus-self-check "$RESTORE_JSON" --focus-session-restore "$SESSION_STORE" \
    > "$LOG_DIR/focus-live-session-restore.log" 2>&1
restore_rc=$?

if (( seed_rc == 0 && restore_rc == 0 )) && [[ -s "$SEED_JSON" && -s "$RESTORE_JSON" ]]; then
    python3 - "$SEED_JSON" "$RESTORE_JSON" > "$EVIDENCE_DIR/session-reconciliation.json" <<'PYTHON'
import json, sys
seed = json.load(open(sys.argv[1]))
restore = json.load(open(sys.argv[2]))
uptime_delta = restore["uptimeSeconds"] - seed["uptimeSeconds"]
wall_delta = restore["wallSeconds"] - seed["wallSeconds"]
json.dump(
    {
        "label": "AUTOMATED",
        "what_the_reader_must_confirm": [
            "startedAt is byte-identical in both launches: it is never rewritten, on any path",
            "elapsedWallSeconds is within two seconds of 5400 — ninety minutes on the wall clock",
            "phase is paused, pauseCauses is exactly [relaunch], resumeTo is focus",
            "no clockAnomaly: wall and uptime were back-dated together, as a sleep moves them",
            "bootIdentity is non-empty and identical, so the anchor belongs to this boot",
            "uptimeDelta matches wallDelta — the anchor is a real cross-process quantity, which "
            "is the one thing a unit test cannot prove because it cannot span two processes",
        ],
        "seed": seed,
        "restore": restore,
        "startedAtIdentical": seed["startedAt"] == restore["startedAt"],
        "uptimeDeltaSeconds": uptime_delta,
        "wallDeltaSeconds": wall_delta,
        "deltaAgreementSeconds": abs(uptime_delta - wall_delta),
    },
    sys.stdout,
    indent=2,
    sort_keys=True,
)
print()
PYTHON
    produced session-reconciliation.json AUTOMATED
    python3 -c "
import json,sys
d=json.load(open('$EVIDENCE_DIR/session-reconciliation.json'))
print('note startedAt identical:', d['startedAtIdentical'])
print('note elapsed:', round(d['restore']['elapsedWallSeconds'], 3), 's')
print('note phase:', d['restore']['phase'], d['restore']['pauseCauses'], '-> resumeTo', d['restore']['resumeTo'])
print('note uptime delta', round(d['uptimeDeltaSeconds'], 6), 's vs wall delta', round(d['wallDeltaSeconds'], 6), 's')
"
else
    fail_artefact session-reconciliation.json "a seed or restore launch failed (seed=$seed_rc restore=$restore_rc)"
fi

# --- 3 · the grant preflight, for the frame only ------------------------------------------------

note "building the window-id test driver"
swift build --package-path Tools/windowid > "$LOG_DIR/focus-live-session-windowid.log" 2>&1
build_rc=$?
print "windowid build EXIT=$build_rc"
(( build_rc == 0 )) || { print -u2 "LIVE-LANE ERROR: could not build Tools/windowid"; exit 1 }
WINDOWID="$(swift build --package-path Tools/windowid --show-bin-path 2>/dev/null)/windowid"

note "TCC preflight"
grants="$("$WINDOWID" --grants)"
print "$grants"
if [[ "$grants" != *"screen-recording=yes"* ]]; then
    manual_required relaunch-mid-session.png "AUTOMATED" \
"Screen Recording is not granted to the driving shell, so no window of another process can be
captured. That is a fact about the shell and never about the app." \
"Grant Screen Recording to the terminal running this lane and re-run it. The proof itself
needs no grant and is already here: see session-reconciliation.json, and the same assertions
run in the zero-grant gate through scripts/self-check.sh."
    print
    print "LIVE-LANE SKIPPED: Screen Recording not granted to the driving shell"
    print "(session-reconciliation.json was produced anyway — it needs no grant)"
    exit 0
fi

# --- 4 · relaunch-mid-session.png · OPERATOR-ASSISTED -------------------------------------------

cockpit_window_id() {
    local lines count
    lines="$("$WINDOWID" "$WINDOW_OWNER" 2>/dev/null)"
    [[ -n "$lines" ]] || return 1
    count="$(print -r -- "$lines" | wc -l | tr -d ' ')"
    [[ "$count" == "1" ]] || return 1
    print -r -- "${lines%% *}"
}

note "launching the app"
pkill -x "$PROCESS_NAME" 2>/dev/null
sleep 1
open -a "$APP"
sleep 4

if ! cockpit_window_id > /dev/null; then
    print -u2 "LIVE-LANE ERROR: the app did not put exactly one layer-0 window on screen"
    exit 1
fi

if prompt_operator "set a priority if there is none, then press Start Session (or ⌃⌘S)"; then
    note "letting the session run"
    sleep 20

    note "killing the app mid-session with pkill"
    pkill -x "$PROCESS_NAME"
    sleep 3

    note "relaunching"
    open -a "$APP"
    sleep 6

    if capture_id="$(cockpit_window_id)" \
        && "$SCREENCAPTURE" -x -o -l "$capture_id" "$EVIDENCE_DIR/relaunch-mid-session.png" 2>/dev/null \
        && [[ -s "$EVIDENCE_DIR/relaunch-mid-session.png" ]]; then
        produced relaunch-mid-session.png OPERATOR-ASSISTED
        print "note the reader must confirm the SAME task and a CORRECTED elapsed figure —"
        print "     roughly the seconds the session really ran, not a restarted zero (F-97)"
    else
        fail_artefact relaunch-mid-session.png "the relaunched app did not own exactly one layer-0 window"
    fi
else
    manual_required relaunch-mid-session.png "OPERATOR-ASSISTED" \
"Nobody answered the prompt within ${OPERATOR_TIMEOUT}s, so no session was started and there
was nothing to relaunch into. This lane may not press the button itself: osascript is banned
from every e03 lane because it blocks on Automation consent (probe P-103), and there is no
other grant-free way to operate a control." \
"Run this lane attended and press Start Session when prompted; the kill, the relaunch and the
capture after it are automatic. The reconciliation the frame illustrates is already proved
without anybody present — see session-reconciliation.json in this directory, and the same
assertions in the zero-grant gate through scripts/self-check.sh."
fi

# --- the summary ---------------------------------------------------------------------------------

cleanup

print
print "=============================================================="
print "LIVE SESSION DRIVE — evidence, never a gate"
print "evidence: $EVIDENCE_DIR"
print "--------------------------------------------------------------"
for artefact in $PRODUCED; do
    print "  PRODUCED  $artefact"
done
for artefact in $RECEIPTS; do
    print "  RECEIPT   $artefact  (see ${artefact}.MANUAL_REQUIRED.txt)"
done
for artefact in $FAILED; do
    print "  FAILED    $artefact"
done
print "--------------------------------------------------------------"
print "Receipts never affect the exit status, and none of this is a close condition."
print "=============================================================="

(( ${#FAILED} == 0 )) || exit 1
exit 0
