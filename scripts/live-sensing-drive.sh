#!/bin/zsh
# The live sensing drive — TCC-GATED EVIDENCE, never a gate.
#
#   scripts/live-sensing-drive.sh
#
# Runs the real app on this Mac, opens real decoy applications in front of it, drives a real
# screen lock, and leaves artefacts in $FOCUS_EVIDENCE_DIR for a human — or the verifying agent
# — to **read**. Capturing is not the point; reading is.
#
# ## Why this is not a gate, and never may be
#
# Standing condition 5: no acceptance criterion may depend on a TCC grant. Capturing another
# process's window needs Screen Recording on the *driving shell*, and diffing the TCC databases
# needs Full Disk Access on it. A criterion that passed here would fail on a machine where those
# are revoked, for a reason that has nothing to do with the code. So when a grant is missing this
# script prints `LIVE-LANE SKIPPED: <grant>` and exits **0**, and `scripts/build-gate.sh` never
# invokes it.
#
# The half of e03's contract that must hold regardless — the observer count going `n → 0 → n`
# through a real pause, the seven decoded window keys with no name among them, both idle sources
# with the hardware one no smaller, the camera path pinned off with zero listeners installed, all
# twelve capabilities with a state each, **no authorisation surface on screen**, and the
# two-launch session reconciliation — is asserted at **zero grants** by `scripts/self-check.sh`,
# which is stages 12 and 13 of the gate.
#
# ## No `osascript`, anywhere, including here
#
# Probe P-103 reproduced e02's P-65 exactly: `osascript -e 'quit app "TextEdit"'` blocks on
# Automation consent and has to be killed. So this lane opens applications with `open -a`
# (LaunchServices, no TCC) and terminates them with `pkill` (POSIX, no TCC), and there is no
# Apple Event anywhere in it. That is also why several artefacts below are operator-assisted
# rather than automated: with no sanctioned way to send a click or a keystroke, an artefact that
# needs one needs a person.
#
# ## Three labels, and the scripts behave differently for each (plan R-51)
#
#   AUTOMATED               produced unattended, given the grants
#   OPERATOR-ASSISTED       a human performs one physical action at a prompt; on timeout the
#                           script writes <artefact>.MANUAL_REQUIRED.txt naming what was not done
#   UNAVAILABLE ON THIS RIG this machine physically cannot produce it, so the receipt is written
#                           **immediately**, naming the fact and the reproduction steps, without
#                           pretending to try
#
# A missing artefact with a receipt is honest; a missing artefact with silence is the failure
# mode this rule exists to prevent. No receipt ever affects the exit status.
#
# ## A frame that shows the wrong window is worse than a missing frame
#
# e02's lane learned that the hard way — a 900×704 picture of the cockpit filed as the
# quick-capture panel. So every capture here requires the app to own **exactly one** layer-0
# window and captures that window by id; zero windows or several is a failure, never a guess, and
# there is no "use the front-most entry" fallback anywhere in this file.
#
# ## Environment
#
#   FOCUS_EVIDENCE_DIR   where the artefacts land   (default .agents/evidence/e03)
#   FOCUS_DERIVED_DATA   build location             (default /tmp/focus-dd)
#   FOCUS_LOG_DIR        log location               (default /tmp)
#   FOCUS_OPERATOR_TIMEOUT  seconds to wait at each operator prompt (default 45)
set -u

REPO_ROOT="${0:A:h}/.."
cd "$REPO_ROOT" || exit 1

EVIDENCE_DIR="${FOCUS_EVIDENCE_DIR:-.agents/evidence/e03}"
DD="${FOCUS_DERIVED_DATA:-/tmp/focus-dd}"
LOG_DIR="${FOCUS_LOG_DIR:-/tmp}"
DESTINATION='platform=macOS,arch=arm64'
OPERATOR_TIMEOUT="${FOCUS_OPERATOR_TIMEOUT:-45}"

# Two names for the same application, both measured rather than assumed (e01's live lane):
# `CGWindowListCopyWindowInfo` reports "Focus Sentinel" in `kCGWindowOwnerName`, and the process
# `pkill -x` matches is "FocusSentinel".
WINDOW_OWNER='Focus Sentinel'
PROCESS_NAME='FocusSentinel'
APP="$DD/Build/Products/Debug/FocusSentinel.app"

# The decoys. Both are stock system applications, both open with `open -a`, and both are
# terminated with `pkill`. Nothing here needs a grant of any kind to start or to stop.
DECOY_ONE='TextEdit'
DECOY_TWO='Calculator'
DECOY_ONE_BUNDLE='com.apple.TextEdit'
DECOY_TWO_BUNDLE='com.apple.calculator'

USER_TCC="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
SYSTEM_TCC='/Library/Application Support/com.apple.TCC/TCC.db'

mkdir -p -- "$EVIDENCE_DIR" "$LOG_DIR" || exit 1

# --- the artefact ledger ----------------------------------------------------------------------

typeset -a PRODUCED RECEIPTS FAILED
PRODUCED=()
RECEIPTS=()
FAILED=()

note() { print "== $*" }
skip() { print "LIVE-LANE SKIPPED: $*"; exit 0 }

produced() {
    PRODUCED+=("$1")
    print "LIVE-ARTEFACT $2: $1"
}

# A required artefact that could not be produced. The run exits non-zero: the evidence set is
# incomplete, which is a different thing from a gate failing, and it must not pass in silence.
fail_artefact() {
    FAILED+=("$1")
    print -u2 "LIVE-ARTEFACT FAILED: $1 — $2"
}

# The structured receipt R-51 requires, in `live-capture-drive.sh`'s existing `SKIPPED` shape.
# The label is written into the file, because a reader finding a receipt is entitled to know
# whether nobody was at the keyboard or whether this machine could never have produced it.
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

# One physical action, asked for once, with a timeout. An unattended run reaches the timeout
# immediately (there is no terminal to read from) and files the receipt, which is exactly what
# should happen — the alternative is a lane that hangs a nightly run for ever.
prompt_operator() {
    local instruction="$1"
    print
    print "OPERATOR: $instruction"
    print "OPERATOR: press Return within ${OPERATOR_TIMEOUT}s when it is done, or wait to skip."
    local answer
    if read -t "$OPERATOR_TIMEOUT" -r answer; then
        return 0
    fi
    print
    return 1
}

cleanup() {
    # `pkill` rather than an Apple Event: quitting has to work even when an app is wedged, and
    # this programme links no Apple Events at all (standing condition 2, dissent D-03).
    pkill -x "$PROCESS_NAME" 2>/dev/null
    pkill -x "$DECOY_ONE" 2>/dev/null
    pkill -x "$DECOY_TWO" 2>/dev/null
    return 0
}
trap 'cleanup' EXIT INT TERM

SCREENCAPTURE="${commands[screencapture]:-/usr/sbin/screencapture}"

# Nothing from a previous run may survive into this one. A frame the drive fails to take must be
# *absent*, not last week's picture of a different state.
ARTEFACTS=(
    activation-timeline.json
    idle-transition.json
    cockpit.png
    pause-resume.png
    lock-transition.json
    fullscreen.png
    fullscreen.json
    space-change.json
    media-transition-mic.json
    media-transition-camera.json
    sleep-wake.txt
    tcc-diff.txt
    sensing-report.txt
)
for artefact in $ARTEFACTS; do
    rm -f -- "$EVIDENCE_DIR/$artefact" "$EVIDENCE_DIR/${artefact}.MANUAL_REQUIRED.txt"
done
rm -rf -- "$EVIDENCE_DIR/no-prompt-frames"
mkdir -p -- "$EVIDENCE_DIR/no-prompt-frames"

# --- 0 · the grant preflight -------------------------------------------------------------------
#
# `windowid --grants` calls `AXIsProcessTrusted()` and `CGPreflightScreenCaptureAccess()`. Both
# are *preflight* calls: this script never puts a permission dialog in front of anybody.
#
# Only Screen Recording is required here. Accessibility is not, and that is the point of the
# no-`osascript` rule: this lane never drives another process, so it never needs to be trusted to.

note "building the window-id test driver"
swift build --package-path Tools/windowid > "$LOG_DIR/focus-live-sensing-windowid.log" 2>&1
build_rc=$?
print "windowid build EXIT=$build_rc log=$LOG_DIR/focus-live-sensing-windowid.log"
(( build_rc == 0 )) || { print -u2 "LIVE-LANE ERROR: could not build Tools/windowid"; exit 1 }

WINDOWID="$(swift build --package-path Tools/windowid --show-bin-path 2>/dev/null)/windowid"
[[ -x "$WINDOWID" ]] || { print -u2 "LIVE-LANE ERROR: no windowid binary at $WINDOWID"; exit 1 }

note "TCC preflight"
grants="$("$WINDOWID" --grants)"
print "$grants"
[[ "$grants" == *"screen-recording=yes"* ]] || skip "Screen Recording not granted to the driving shell"
[[ -x "$SCREENCAPTURE" ]] || skip "no screencapture binary at $SCREENCAPTURE"

# --- 1 · build the app --------------------------------------------------------------------------

note "building the Debug app"
xcodebuild -workspace Focus.xcworkspace -scheme FocusSentinel \
    -configuration Debug -destination "$DESTINATION" -derivedDataPath "$DD" build \
    > "$LOG_DIR/focus-live-sensing-build.log" 2>&1
app_rc=$?
print "build EXIT=$app_rc log=$LOG_DIR/focus-live-sensing-build.log"
(( app_rc == 0 )) || { print -u2 "LIVE-LANE ERROR: the Debug build failed"; exit 1 }
[[ -d "$APP" ]] || { print -u2 "LIVE-LANE ERROR: no app bundle at $APP"; exit 1 }

BINARY="$APP/Contents/MacOS/FocusSentinel"

# --- helpers ------------------------------------------------------------------------------------
#
# Never `local path=…` in zsh: `path` is tied to `PATH`, so a local assignment to it empties the
# command search path for the whole call. Measured the hard way in e01's live lane.

# The app's single layer-0 window id, or empty. **Exactly one** — zero means the cockpit is not
# up, several means the frame would be a guess, and a guess filed as evidence is the failure this
# check exists to prevent.
cockpit_window_id() {
    local lines count
    lines="$("$WINDOWID" "$WINDOW_OWNER" 2>/dev/null)"
    [[ -n "$lines" ]] || return 1
    count="$(print -r -- "$lines" | wc -l | tr -d ' ')"
    [[ "$count" == "1" ]] || return 1
    print -r -- "${lines%% *}"
}

# Capture the app's cockpit by window id, or fail loudly. Every frame is copied into
# no-prompt-frames/ as well, because the reader's job there is to confirm that **no TCC prompt
# appears in any frame captured during the drive**.
capture_cockpit() {
    local artefact="$1" window
    if ! window="$(cockpit_window_id)"; then
        return 1
    fi
    "$SCREENCAPTURE" -x -o -l "$window" "$EVIDENCE_DIR/$artefact" 2>/dev/null || return 1
    [[ -s "$EVIDENCE_DIR/$artefact" ]] || return 1
    cp -- "$EVIDENCE_DIR/$artefact" "$EVIDENCE_DIR/no-prompt-frames/$artefact"
    return 0
}

# The app's own event-stream export, through the mode the self-check host owns. A separate,
# short-lived launch: the running instance holds the store, and SwiftData is content with a
# second reader.
export_events() {
    local destination="$1" report="$LOG_DIR/focus-live-export.json"
    "$BINARY" --focus-self-check "$report" --focus-export-events "$destination" \
        > "$LOG_DIR/focus-live-export.log" 2>&1 || return 1
    [[ -s "$destination" ]] || return 1
    return 0
}

# --- 2 · the drive ------------------------------------------------------------------------------

note "launching the app"
cleanup
sleep 1
open -a "$APP"
sleep 4

if ! cockpit_window_id > /dev/null; then
    print -u2 "LIVE-LANE ERROR: the app did not put exactly one layer-0 window on screen"
    exit 1
fi

# --- sensing-report.txt · AUTOMATED -----------------------------------------------------
#
# The grant-free instrument, recorded on the shipped build while it runs: the owners of every
# on-screen window, and the assertion that not one of them is a process macOS puts an
# authorisation dialog on the screen through (probe P-95(c)). This is the same scan the
# zero-grant self-check makes; recording it here puts it beside the frames a human reads.
note "recording the app's own grant-free report of what it is watching"
SURFACE_REPORT="$LOG_DIR/focus-live-surfaces.json"
if "$BINARY" --focus-self-check "$SURFACE_REPORT" > "$LOG_DIR/focus-live-surfaces.log" 2>&1 \
    && [[ -s "$SURFACE_REPORT" ]]; then
    python3 - "$SURFACE_REPORT" > "$EVIDENCE_DIR/sensing-report.txt" <<'PYTHON'
import json, sys

report = json.load(open(sys.argv[1]))
sensing = report.get("sensing") or {}
media = sensing.get("media") or {}
idle = sensing.get("idle") or {}

print("AUTOMATED · what the shipped build says about itself, at zero grants")
print()
print("== the app never triggers a permission prompt (probe P-95(c))")
print("suspect owners found:", report.get("authorisationSurfaces"))
print("every on-screen window owner while the app ran:")
for owner in report.get("onScreenWindowOwners", []):
    print("   ", owner)
print()
print("== the global switch detaches rather than sets a flag (F-119)")
print("observers:", sensing.get("liveObserverCount"),
      "->", sensing.get("liveObserverCountAfterPause"),
      "->", sensing.get("liveObserverCountAfterResume"))
print("CoreAudio listeners after pause:", sensing.get("audioListenerCountAfterPause"))
print("redundant activations ignored:", sensing.get("redundantActivations"))
print()
print("== what is read, and what is not (F-29, SC-1)")
print("decoded window keys:", (sensing.get("windowMetadata") or {}).get("decodedKeys"))
print("none of them names a window:",
      (sensing.get("windowMetadata") or {}).get("decodedKeysAreTitleFree"))
print()
print("== idle, both sources (F-32, probe P-85)")
print("hardware:", idle.get("hardwareSeconds"), "s   session:", idle.get("sessionSeconds"), "s")
print("threshold:", idle.get("thresholdSeconds"), "s   currently idle:", idle.get("isIdle"))
print()
print("== media: microphone live, camera held off (F-36, probes P-96/P-104)")
print("audio input devices:", media.get("inputDeviceCount"),
      "  output devices:", media.get("outputDeviceCount"))
print("microphoneRunning:", media.get("microphoneRunning"))
print("cameraRunning:", media.get("cameraRunning"),
      "  cameraState:", media.get("cameraState"),
      "  reason:", media.get("cameraReason"))
print("CoreMediaIO listeners ever installed:", media.get("cameraListenersInstalled"))
print()
print("== the capability matrix, as the app itself computed it (F-126)")
for entry in report.get("capabilities", []):
    print(f"   {entry.get('capability'):<28} {entry.get('state')}")
PYTHON
    produced sensing-report.txt AUTOMATED
    # The app has to come back: reading its own report terminated that launch, not this one.
    open -a "$APP"; sleep 3
else
    fail_artefact sensing-report.txt "the self-check launch produced no report"
fi

# --- activation-timeline.json · AUTOMATED -------------------------------------------------------
note "opening two decoy applications with open -a"
open -a "$DECOY_ONE"; sleep 3
open -a "$DECOY_TWO"; sleep 3
pkill -x "$DECOY_TWO" 2>/dev/null; sleep 1
pkill -x "$DECOY_ONE" 2>/dev/null; sleep 1
open -a "$APP"; sleep 3

note "exporting the event stream"
if export_events "$EVIDENCE_DIR/activation-timeline.json"; then
    python3 - "$EVIDENCE_DIR/activation-timeline.json" "$DECOY_ONE_BUNDLE" "$DECOY_TWO_BUNDLE" <<'PYTHON'
import json, sys
events = json.load(open(sys.argv[1]))
rows = events if isinstance(events, list) else events.get("events", [])
decoys = set(sys.argv[2:])
seen = {r.get("bundleID") for r in rows}
print(f"note {len(rows)} exported event(s); decoys present: {sorted(decoys & seen)}")
# Normalised evidence only. There is no NormalisedDetail(String), so this cannot fail unless
# something reached the store another way — which is exactly what it is here to notice.
for row in rows:
    detail = row.get("detail")
    if detail in (None, ""):
        continue
    for token in str(detail).split(","):
        token = token.strip()
        if not token:
            continue
        if token.replace("-", "").replace(".", "").isdigit():
            continue
        if not token.replace(":", "").replace("-", "").isalnum():
            print(f"SUSPECT detail value: {detail!r}", file=sys.stderr)
PYTHON
    produced activation-timeline.json AUTOMATED
else
    fail_artefact activation-timeline.json "the event export produced nothing"
fi
open -a "$APP"; sleep 3

# --- cockpit.png · AUTOMATED ------------------------------------------------------------
note "capturing the cockpit as the person sees it"
if capture_cockpit cockpit.png; then
    produced cockpit.png AUTOMATED
else
    fail_artefact cockpit.png "the app did not own exactly one layer-0 window"
fi

# --- idle-transition.json · AUTOMATED -----------------------------------------------------------
#
# No input is generated by this script, so the hardware idle counter climbs on its own. The
# corroboration tick samples every five seconds and writes exactly one row per transition. On a
# machine somebody is actively using, the threshold (180 s by default) will not be crossed inside
# this window — which is a true fact about that machine, and gets a receipt rather than a wait.
note "watching for an idle transition (no input is generated by this script)"
sleep 20
if export_events "$EVIDENCE_DIR/idle-transition.json"; then
    if grep -q '"userIdle"' "$EVIDENCE_DIR/idle-transition.json"; then
        produced idle-transition.json AUTOMATED
    else
        rm -f -- "$EVIDENCE_DIR/idle-transition.json"
        manual_required idle-transition.json "OPERATOR-ASSISTED" \
"The hardware idle counter had not crossed the stored threshold while this ran, so no
userIdle row exists to export. That is a fact about this machine at this moment — somebody
was using it — and not a defect." \
"Leave the Mac untouched for longer than settings.idleThresholdSeconds (180 s by default)
with the app running, then re-run this lane. The zero-grant equivalent, which needs no
waiting at all, is IdleReaderTests plus the self-check's live idle pair."
    fi
else
    fail_artefact idle-transition.json "the event export produced nothing"
fi
open -a "$APP"; sleep 2

# --- lock-transition.json · AUTOMATED -----------------------------------------------------------
#
# A real screen lock, driven the only way that is drivable here: `pmset displaysleepnow` locks the
# screen, and `caffeinate -u -t 3` wakes it (probe P-87). A real *system* sleep is not drivable —
# see the sleep-wake.txt receipt below.
note "driving a real screen lock with pmset displaysleepnow"
pmset displaysleepnow
sleep 6
caffeinate -u -t 3
sleep 8
open -a "$APP"; sleep 3

if export_events "$EVIDENCE_DIR/lock-transition.json"; then
    python3 - "$EVIDENCE_DIR/lock-transition.json" <<'PYTHON'
import json, sys
events = json.load(open(sys.argv[1]))
rows = events if isinstance(events, list) else events.get("events", [])
kinds = [r.get("kind") for r in rows]
print("note lifecycle rows:", kinds.count("displayInactive"))
print("note phase-change rows:", kinds.count("sessionPhaseChanged"))
print("note the reader must confirm: a loginwindow activation, a pause with cause")
print("     screenLocked, and a resume by that SAME cause (plan §4.8, probe P-87)")
PYTHON
    produced lock-transition.json AUTOMATED
else
    fail_artefact lock-transition.json "the event export produced nothing"
fi
open -a "$APP"; sleep 3

# --- pause-resume.png · OPERATOR-ASSISTED -------------------------------------------------------
#
# Relabelled from AUTOMATED deliberately, and the reason is a rule rather than a limitation:
# `osascript` is banned from every e03 lane (probe P-103), and with no Apple Events and no
# Accessibility there is no sanctioned way for this script to click a switch. The **gateable**
# proof of the same claim needs no click at all — `scripts/self-check.sh` pauses and resumes the
# live graph in-process and asserts `n → 0 → n` — so what is lost here is a picture, not an
# assertion.
note "pause-resume.png needs one click"
if prompt_operator "click the cockpit's \"Watch what I am working on\" switch OFF"; then
    sleep 2
    if capture_cockpit pause-resume.png; then
        produced pause-resume.png OPERATOR-ASSISTED
        prompt_operator "click the same switch back ON" && sleep 2
    else
        fail_artefact pause-resume.png "the app did not own exactly one layer-0 window"
    fi
else
    manual_required pause-resume.png "OPERATOR-ASSISTED" \
"Nobody answered the prompt within ${OPERATOR_TIMEOUT}s. This lane may not send a click:
osascript is banned from every e03 lane because it blocks on Automation consent (probe
P-103), and there is no other grant-free way to operate a control." \
"Run this lane attended and click the cockpit's \"Watch what I am working on\" switch off
when prompted. The gateable form of the same claim is scripts/self-check.sh, which pauses
and resumes the live observer graph in-process and asserts n -> 0 -> n at zero grants."
fi

# --- fullscreen.png + fullscreen.json · OPERATOR-ASSISTED ---------------------------------------
note "fullscreen.png needs one full-screen transition"
if prompt_operator "put any application into full screen and leave it there"; then
    sleep 3
    if export_events "$EVIDENCE_DIR/fullscreen.json"; then
        produced fullscreen.json OPERATOR-ASSISTED
    else
        fail_artefact fullscreen.json "the event export produced nothing"
    fi
    open -a "$APP"; sleep 3
    if capture_cockpit fullscreen.png; then
        produced fullscreen.png OPERATOR-ASSISTED
    else
        fail_artefact fullscreen.png "the app did not own exactly one layer-0 window"
    fi
    prompt_operator "take that application back out of full screen"
else
    manual_required fullscreen.png "OPERATOR-ASSISTED" \
"Nobody answered the prompt within ${OPERATOR_TIMEOUT}s. Entering full screen is a physical
action this lane may not perform." \
"Run this lane attended and put an application into full screen when prompted. The reader
must confirm at least two of the quorum's three inputs agreeing. The zero-grant equivalent
is PresentationQuorumTests plus the self-check's live presentation block, which records all
three inputs whatever the verdict."
    manual_required fullscreen.json "OPERATOR-ASSISTED" \
"Same prompt as fullscreen.png: no full-screen transition was performed." \
"See fullscreen.png.MANUAL_REQUIRED.txt."
fi

# --- space-change.json · OPERATOR-ASSISTED ------------------------------------------------------
note "space-change.json needs one Space switch"
if prompt_operator "switch to another Space and back"; then
    sleep 2
    if export_events "$EVIDENCE_DIR/space-change.json"; then
        produced space-change.json OPERATOR-ASSISTED
    else
        fail_artefact space-change.json "the event export produced nothing"
    fi
    open -a "$APP"; sleep 2
else
    manual_required space-change.json "OPERATOR-ASSISTED" \
"Nobody answered the prompt within ${OPERATOR_TIMEOUT}s. Switching Space is a physical action
this lane may not perform, and it cannot be waited for either: probe P-92 measured
NSWorkspace.activeSpaceDidChangeNotification NEVER firing across four full-screen cycles,
two bundle identifiers and both a windowed and a windowless observer." \
"Run this lane attended and switch Space when prompted. What the reader must confirm is that
the display mapping is re-evaluated on the next accepted activation regardless — which is the
contract, precisely because the notification cannot be relied on."
fi

# --- media-transition-mic.json · OPERATOR-ASSISTED ----------------------------------------------
note "media-transition-mic.json needs a real microphone to start"
if prompt_operator "start something that opens the microphone (a voice memo, a call), then stop it"; then
    sleep 2
    if export_events "$EVIDENCE_DIR/media-transition-mic.json"; then
        produced media-transition-mic.json OPERATOR-ASSISTED
    else
        fail_artefact media-transition-mic.json "the event export produced nothing"
    fi
    open -a "$APP"; sleep 2
else
    manual_required media-transition-mic.json "OPERATOR-ASSISTED" \
"Nobody answered the prompt within ${OPERATOR_TIMEOUT}s. Opening a microphone is a physical
action this lane may not perform." \
"Run this lane attended and start something that opens the microphone when prompted. The
reader must confirm microphoneRunning flipping false -> true -> false on the shipped build,
matching probes P-94/P-96. The zero-grant equivalents are MediaActivityObserverTests and the
self-check's live media block, which reports the input and output device counts separately."
fi

# --- media-transition-camera.json · UNAVAILABLE ON THIS RIG -------------------------------------
#
# Written immediately, without pretending to try. There is nothing here to wait for.
manual_required media-transition-camera.json "UNAVAILABLE ON THIS RIG" \
"This Mac has no camera at all. CoreMediaIO enumerated zero devices (probe P-97) and
\`system_profiler SPCameraDataType\` reports no camera hardware, so there is no transition to
observe. It would make no difference if there were: the camera path is switched OFF in this
version on EVERY Mac — cameraRunning is pinned false and cameraActivity is pinned
CapabilityState.unavailable — because the per-device read and the listener install have never
been observed for prompts on real camera hardware (probe P-104). The gate asserts the held
path was never entered rather than asserting an accident of this rig:
cameraListenersInstalled == 0 on both configurations." \
"Turning the camera half on is NOT a close condition of this epic. It requires the R-40
re-probe, on a Mac that has a camera, from an ad-hoc-signed bundle launched with \`open -a\`:
enumeration returning >= 1 device; a per-device kCMIODevicePropertyDeviceIsRunningSomewhere
read returning status 0; a listener install AND remove returning 0; a real 0 -> 1 -> 0
transition while another application opens the camera; and all four P-95 prompt instruments
clean across the whole run (both TCC databases byte-identical, no com.apple.TCC log line
naming the process, the grant-free authorisation-surface scan empty before and after, and the
on-screen window count unchanged). Until every one of those exists, FOCUS_CAMERA_PROBE stays
unset — it is set nowhere in the app, the gate or any lane."

# --- sleep-wake.txt · UNAVAILABLE ON THIS RIG ---------------------------------------------------
manual_required sleep-wake.txt "UNAVAILABLE ON THIS RIG" \
"A real system sleep is not drivable from this lane. Measured (probe P-86): \`pmset -g custom\`
reports this Mac configured never to sleep — sleep 0, displaysleep 0, disksleep 0, standby 0 —
\`sysctl kern.sleeptime\` and \`kern.waketime\` both read { sec = 0 }, and kern.boottime shows
8.55 days of uptime with zero sleeps. Forcing one would also suspend the very process running
this lane, so the artefact could not be written even if the sleep succeeded. What IS drivable
is the screen lock, and this lane drives it: see lock-transition.json." \
"On a Mac that sleeps: start a session, run \`pmset sleepnow\`, wake it after several minutes,
and export the event stream. The reader must confirm the session paused with a distinct cause
and resumed by that SAME cause, and that the elapsed figure advanced by the wall-clock time —
the anchor is mach_continuous_time, which keeps counting across sleep, so wall and uptime
advance together and NO clock anomaly is raised (plan R-46). The zero-grant equivalent is
SessionRestorationTests, which exercises exactly that case with injected clocks."

# --- tcc-diff.txt · AUTOMATED (needs Full Disk Access on the shell) -----------------------------
#
# Probe P-95's instruments (a) and (b), reproduced on the shipped build. Reading either database
# needs Full Disk Access on the *driving shell*, which is why this can never gate.
note "diffing both TCC databases across the drive"
tcc_before="$LOG_DIR/focus-live-tcc-before.txt"
tcc_after="$LOG_DIR/focus-live-tcc-after.txt"
dump_tcc() {
    : > "$1"
    local db
    for db in "$USER_TCC" "$SYSTEM_TCC"; do
        print -r -- "== $db" >> "$1"
        sqlite3 "$db" 'SELECT service, client, auth_value FROM access ORDER BY service, client;' \
            >> "$1" 2>> "$1"
    done
}
dump_tcc "$tcc_after"
if grep -qi 'unable to open database\|authorization denied\|Error:' "$tcc_after"; then
    manual_required tcc-diff.txt "AUTOMATED" \
"Neither TCC database could be read, which means this shell does not hold Full Disk Access.
That is a fact about the shell and never about the app: no acceptance criterion may depend on
a grant, so this artefact is evidence and its absence blocks nothing." \
"Grant Full Disk Access to the terminal running this lane (System Settings -> Privacy &
Security -> Full Disk Access) and re-run it. The gateable form of the same claim needs no
database at all: scripts/self-check.sh enumerates the on-screen window owners — grant-free —
and asserts that no authorisation surface is present while the app runs."
else
    # A second dump after one more drive of the app, and the diff between them.
    cp -- "$tcc_after" "$tcc_before"
    open -a "$DECOY_ONE"; sleep 2; pkill -x "$DECOY_ONE" 2>/dev/null; sleep 1
    open -a "$APP"; sleep 3
    dump_tcc "$tcc_after"
    {
        print "AUTOMATED · probe P-95's instruments (a) and (b), on the shipped build"
        print "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        print
        print "== diff of both TCC databases, before and after a drive"
        if diff -u "$tcc_before" "$tcc_after"; then
            print "(empty — the databases are identical)"
        fi
        print
        print "== com.apple.TCC log lines naming FocusSentinel, over the last 10 minutes"
        log show --last 10m --predicate 'subsystem == "com.apple.TCC"' --style compact 2>/dev/null \
            | grep -i 'FocusSentinel' || print "(none)"
    } > "$EVIDENCE_DIR/tcc-diff.txt"
    produced tcc-diff.txt AUTOMATED
fi

# --- the summary ---------------------------------------------------------------------------------

cleanup

print
print "=============================================================="
print "LIVE SENSING DRIVE — evidence, never a gate"
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
print "no-prompt-frames/ holds every frame captured during the drive."
print "A human must read them and confirm that NO TCC prompt appears in any of them."
print "Receipts never affect the exit status, and none of this is a close condition."
print "=============================================================="

(( ${#FAILED} == 0 )) || exit 1
exit 0
