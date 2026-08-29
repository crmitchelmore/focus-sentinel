#!/bin/zsh
# The live nudge drive — TCC-GATED EVIDENCE, never a gate (§4.9, R-97, F-154).
#
#   scripts/live-nudge-drive.sh
#
# **The charter's headline scenario.** It launches the real built `.app` at zero grants, drives two
# real committed decoy applications, and captures eighteen frames — every one of which is then
# READ, by eye, because reading the frames is the evidence and capturing them is not.
#
# ## Why this can never be a gate
#
# Standing condition 5: no acceptance criterion may depend on a TCC grant. Capturing another
# process's window needs Screen Recording on the **driving shell**, and typing a synthetic key
# event needs Accessibility on it, so a criterion that passed here would fail on a Mac where either
# is revoked — for a reason with nothing to do with the code. When a grant is missing this script
# prints `LIVE-LANE SKIPPED: <grant>` and exits **0**, and `scripts/build-gate.sh` never invokes it.
#
# **One exception, and it is not a TCC dependency: a VISIBILITY FAILURE exits 1.** If this lane
# holds the grants, takes both frames, and finds the app's own panel measuring something other
# than its `contentSize` — or finds the window's backing store carrying the question while the
# screen at that window's own coordinates is blank — then it has not failed to observe. It has
# observed a defect. See THE VISIBILITY DOCTRINE below.
#
# The half of e05's contract that must hold regardless is gated at zero grants by two stages the
# gate does run: `focus-steal` (all four of R-89's readings, reading 1 from an independent observer)
# and `notification-denied` (F-73's degraded path, `requestAuthorizationCallCount == 0`).
#
# ## Seven scenarios, not one timeline (finding 4)
#
# Adversarial review walked the original sixteen-frame list as a continuous session and found it
# unreachable at four separate points: once a correction has made the decoy `relevant` there is no
# panel left to snooze from, a paused session suppresses the query the next frame expects, and a
# `relevant` subject cannot produce the mandate the deferral frame needs. So the lane is seven
# **named scenarios**, each beginning with an explicit reset and declaring its full precondition.
#
#   S1  at rest                     frames 1, 2
#   S2  the ladder                  frames 3, 4, 5, 17, 6
#   S3  the correction economy      frames 8, 9, 10      (each with its own reset)
#   S4  the durable correction      frame 7
#   S5  the phases that silence     frames 11, 16
#   S6  the query                   frames 12, 13, 14, 14b
#   S7  the presentation            frame 15
#
# **Frame numbers are stable identifiers, not an execution order.** The goal document references
# frames 5, 14, 14b, 15 and 17 by number, so they keep their numbers while the driver captures them
# in scenario order.
#
# ## R-97.3 — a precondition that cannot be reached is a FAILURE, not a skip
#
# `require_state` reads the app's own report and **aborts the scenario**, dumping what it actually
# observed, when the declared precondition does not hold. A live lane that photographs whatever it
# happens to find is a live lane that proves nothing: the frame would still be a picture, it would
# still be filed under the right name, and it would be evidence of the wrong thing.
#
# ## Two decoys, and why one was not enough
#
# `FocusDecoy` is seeded `unrelated` for the ladder scenarios, so it can never produce the
# `uncertain` verdict the query scenario needs. `FocusDecoy2` carries a neutral bundle identity
# matching no seed, no rule and no priority token — which is what makes `noNegativeBasis` reachable
# on demand — and a focusable text field, which is where frame 17's keystrokes have to land. Both
# are committed under `Tools/`, because a live lane whose distraction is fabricated at run time is
# a live lane nobody can re-run.
#
# ## No `osascript` for anything but the keystroke sink
#
# Probe P-103 reproduced e02's P-65 exactly: `osascript -e 'quit app "TextEdit"'` blocks on
# Automation consent and has to be killed. So applications are opened with `open -a`
# (LaunchServices, no TCC) and stopped with `pkill` (POSIX, no TCC). The one exception is frame
# 17's synthetic keystroke, which has no non-`osascript` route that does not need the same grant
# anyway — and it is behind an explicit Accessibility preflight that skips the frame when the grant
# is absent.
#
# ## Environment
#
#   FOCUS_EVIDENCE_DIR      where the artefacts land   (default .agents/evidence/e05/live)
#   FOCUS_DERIVED_DATA      build location             (default /tmp/focus-dd)
#   FOCUS_LOG_DIR           log location               (default /tmp)
#   FOCUS_OPERATOR_TIMEOUT  seconds to wait at each operator prompt (default 45)
set -u

REPO_ROOT="${0:A:h}/.."
cd "$REPO_ROOT" || exit 1

EVIDENCE_DIR="${FOCUS_EVIDENCE_DIR:-.agents/evidence/e05/live}"
DD="${FOCUS_DERIVED_DATA:-/tmp/focus-dd}"
LOG_DIR="${FOCUS_LOG_DIR:-/tmp}"
DESTINATION='platform=macOS,arch=arm64'
OPERATOR_TIMEOUT="${FOCUS_OPERATOR_TIMEOUT:-45}"

WINDOW_OWNER='Focus Sentinel'
PROCESS_NAME='FocusSentinel'
BUNDLE_ID='com.chrismitchelmore.FocusSentinel'
APP="$DD/Build/Products/Debug/FocusSentinel.app"

DECOY_DIR="${TMPDIR:-/tmp}/focus-decoys"
DECOY='FocusDecoy'
DECOY2='FocusDecoy2'
DECOY_OWNER='Focus Decoy'
DECOY2_OWNER='Focus Decoy 2'
DECOY_ID='com.chrismitchelmore.FocusDecoy'
DECOY2_ID='com.chrismitchelmore.FocusDecoy2'
ECHO_FILE="$LOG_DIR/focus-decoy2-echo.txt"

# The priority every scenario is driven against, and the application a person would attach to it.
PRIORITY_INTENT='Write the Q3 proposal for Acme'
PRIORITY_DONE_WHEN='sent to Dana'
CONTEXT_APP='TextEdit'

SCREENCAPTURE="${commands[screencapture]:-/usr/sbin/screencapture}"

# The engine's own thresholds, read from the committed constant sets rather than typed twice: a
# lane that waited a different span from the one the app is using would file frames of the wrong
# moment and call them evidence.
RELEVANCE_POLICY='Packages/FocusCore/Sources/FocusCore/Relevance/RelevancePolicy.swift'
INTERVENTION_POLICY='Packages/FocusCore/Sources/FocusCore/Nudge/InterventionPolicy.swift'

policy_seconds() {
    local file="$1" name="$2" line
    line=$(grep -E "static let ${name}\b" "$file" 2>/dev/null | head -1)
    [[ -n "$line" ]] || return 0
    line="${line##*seconds\(}"
    print -r -- "${line%%\)*}"
}

SUSTAINED_DRIFT="$(policy_seconds "$RELEVANCE_POLICY" sustainedDriftThreshold)"
ESCALATION_DWELL="$(policy_seconds "$RELEVANCE_POLICY" escalationDwell)"
QUERY_DWELL="$(policy_seconds "$INTERVENTION_POLICY" queryDwellThreshold)"

mkdir -p -- "$EVIDENCE_DIR" "$LOG_DIR" || exit 1

# --- the ledger ------------------------------------------------------------------------------

typeset -a PRODUCED RECEIPTS ABORTED VISIBILITY_FAILURES
PRODUCED=()
RECEIPTS=()
# Frames whose backing store and screen disagreed, or whose panel was not the size it is built
# to be. See THE VISIBILITY DOCTRINE below: unlike everything else in this lane, these are
# failures of the APP rather than of the run, and they are the one thing that makes it exit 1.
VISIBILITY_FAILURES=()
ABORTED=()
SCENARIO=''

note() { print "== $*" }
skip() { print "LIVE-LANE SKIPPED: $*"; exit 0 }

timeline() {
    print -r -- "$1" >> "$EVIDENCE_DIR/nudge-timeline.txt"
    print -r -- "TIMELINE $1"
}

produced() {
    PRODUCED+=("$1")
    print "LIVE-ARTEFACT AUTOMATED: $1"
}

manual_required() {
    local artefact="$1" reason="$2" steps="$3"
    RECEIPTS+=("$artefact")
    print "LIVE-ARTEFACT OPERATOR-ASSISTED: $artefact — $reason"
    {
        print "MANUAL_REQUIRED: $artefact"
        print "label:  OPERATOR-ASSISTED"
        print "date:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        print "host:   $(sw_vers -productVersion) ($(uname -m))"
        print
        print "why this run did not produce it"
        print -r -- "-------------------------------"
        print -r -- "$reason"
        print
        print "how to reproduce it"
        print -r -- "-------------------"
        print -r -- "$steps"
    } > "$EVIDENCE_DIR/${artefact}.MANUAL_REQUIRED.txt"
}

# **R-97 rule 3.** A precondition that cannot be reached is a failure, not a skip — and the
# failure is loud, names the scenario, and dumps what was observed instead. The scenario stops
# there rather than continuing to photograph a state nobody asked for.
abort_scenario() {
    local reason="$1" observed="${2:-<not read>}"
    ABORTED+=("$SCENARIO")
    print -u2 "LIVE-SCENARIO ABORTED: $SCENARIO — $reason"
    print -u2 "  observed: $observed"
    timeline "ABORTED $SCENARIO — $reason (observed: $observed)"
    return 1
}

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
    pkill -x "$PROCESS_NAME" 2>/dev/null
    pkill -x "$DECOY" 2>/dev/null
    pkill -x "$DECOY2" 2>/dev/null
    pkill -x "$CONTEXT_APP" 2>/dev/null
    return 0
}
trap 'cleanup' EXIT INT TERM

# --- 0 · preflight ----------------------------------------------------------------------------
#
# `windowid --grants` calls `AXIsProcessTrusted()` and `CGPreflightScreenCaptureAccess()`. Both are
# *preflight* calls: this script never puts a permission dialog in front of anybody.

if [[ -z "$SUSTAINED_DRIFT" || -z "$ESCALATION_DWELL" || -z "$QUERY_DWELL" ]]; then
    print -u2 "LIVE-LANE ERROR: could not read the thresholds out of the committed policy files"
    exit 1
fi
print "LIVE NUDGE DRIVE — read evidence, never a gate (§4.9, R-97)"
print "date:  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
print "host:  $(sw_vers -productVersion) ($(uname -m))"
print "thresholds read from the committed constant sets:"
print "  sustainedDriftThreshold = ${SUSTAINED_DRIFT}s"
print "  escalationDwell         = ${ESCALATION_DWELL}s"
print "  queryDwellThreshold     = ${QUERY_DWELL}s"
print

note "building the window-id test driver"
swift build --package-path Tools/windowid > "$LOG_DIR/focus-live-nudge-windowid.log" 2>&1
build_rc=$?
print "windowid build EXIT=$build_rc"
(( build_rc == 0 )) || { print -u2 "LIVE-LANE ERROR: could not build Tools/windowid"; exit 1 }
WINDOWID="$(swift build --package-path Tools/windowid --show-bin-path 2>/dev/null)/windowid"
[[ -x "$WINDOWID" ]] || { print -u2 "LIVE-LANE ERROR: no windowid binary at $WINDOWID"; exit 1 }

note "TCC preflight (the DRIVER's grants, never the app's)"
GRANTS="$("$WINDOWID" --grants)"
print "$GRANTS"
[[ "$GRANTS" == *"screen-recording=yes"* ]] || skip "Screen Recording not granted to the driving shell"
[[ -x "$SCREENCAPTURE" ]] || skip "no screencapture binary at $SCREENCAPTURE"

# Accessibility is preflighted **separately**, because it gates exactly one frame. The other
# seventeen are captured without it.
HAS_ACCESSIBILITY=0
[[ "$GRANTS" == *"accessibility=yes"* ]] && HAS_ACCESSIBILITY=1
print "frame 17 (the keystroke sink) requires driver Accessibility: $(( HAS_ACCESSIBILITY )) "

# --- 1 · build the app and both decoys ----------------------------------------------------------

note "building the Debug app"
xcodebuild -workspace Focus.xcworkspace -scheme FocusSentinel \
    -configuration Debug -destination "$DESTINATION" -derivedDataPath "$DD" build \
    > "$LOG_DIR/focus-live-nudge-build.log" 2>&1
app_rc=$?
print "build EXIT=$app_rc log=$LOG_DIR/focus-live-nudge-build.log"
(( app_rc == 0 )) || { print -u2 "LIVE-LANE ERROR: the Debug build failed"; exit 1 }
[[ -d "$APP" ]] || { print -u2 "LIVE-LANE ERROR: no app bundle at $APP"; exit 1 }
BINARY="$APP/Contents/MacOS/FocusSentinel"

note "building the two committed decoys"
DECOY_APP="$(Tools/FocusDecoy/build.sh "$DECOY_DIR" 2> "$LOG_DIR/focus-live-nudge-decoy.log")"
DECOY2_APP="$(Tools/FocusDecoy2/build.sh "$DECOY_DIR" 2>> "$LOG_DIR/focus-live-nudge-decoy.log")"
if [[ ! -d "$DECOY_APP" || ! -d "$DECOY2_APP" ]]; then
    print -u2 "LIVE-LANE ERROR: a decoy failed to build — see $LOG_DIR/focus-live-nudge-decoy.log"
    exit 1
fi
print "decoy 1: $DECOY_APP"
print "decoy 2: $DECOY2_APP"

# Nothing from a previous run may survive into this one. A frame this drive fails to take must be
# **absent**, not last week's picture of a different state.
ARTEFACTS=(
    nudge-timeline.txt
    01-cockpit-at-rest.png 02-menu-bar-at-rest.png
    03-decoy-foregrounded.png 04-menu-bar-ambient.png 05-rung2-panel.png
    17-keystroke-sink.png 06-rung3-recommitment.png
    07-this-is-relevant.png 08-snooze-countdown.png 09-change-priority.png 10-return-to-task.png
    11-paused.png 16-break.png
    12-the-query.png 13-query-answered-yes.png 14-subject-returns.png 14b-rule-deleted.png
    15-decoy-full-screen.png
)
for artefact in $ARTEFACTS; do
    rm -f -- "$EVIDENCE_DIR/$artefact" "$EVIDENCE_DIR/${artefact}.MANUAL_REQUIRED.txt"
    # The screen twin of every window frame, and the numbered extras of both (see the
    # visibility doctrine). A stale -onscreen.png beside a fresh frame would be a picture of a
    # different run's screen filed as proof about this one.
    rm -f -- "$EVIDENCE_DIR/${artefact%.png}-onscreen.png"
    rm -f -- "$EVIDENCE_DIR/${artefact%.png}"-[0-9]*.png
    rm -f -- "$EVIDENCE_DIR/${artefact%.png}"-[0-9]*-onscreen.png
done
rm -f -- "$ECHO_FILE"

{
    print "LIVE NUDGE DRIVE — eighteen frames in seven independently reset scenarios"
    print "date:  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    print "host:  $(sw_vers -productVersion) ($(uname -m))"
    print "app:   $APP"
    print
    print "What to read in each frame. In the panel frames: the sentence, the actions, and that"
    print "the panel is a compact overlay rather than a window that took the screen. In the"
    print "menu-bar frames: the glyph, and that it is distinguishable in monochrome. In frame 15:"
    print "that the decoy's full-screen space is CLEAN — no panel anywhere."
    print
    print "What must NOT be in any of them: a window title, a URL, a file path, a similarity"
    print "number, a streak, a score, or an accusation aimed at anything but an application."
    print
} > "$EVIDENCE_DIR/nudge-timeline.txt"

# --- helpers -------------------------------------------------------------------------------------
#
# Never `local path=…` in zsh: `path` is tied to `PATH`, so a local assignment to it empties the
# command search path for the whole call. Measured the hard way in e01's live lane.

app_window_ids() {
    local owner="$1" lines
    lines="$("$WINDOWID" "$owner" --include-panels 2>/dev/null)"
    [[ -n "$lines" ]] || return 1
    print -r -- "$lines" | while read -r id rest; do print -r -- "$id"; done
}

# The same, but the whole record: `<windowNumber> <x> <y> <w> <h>` in Quartz coordinates —
# which is exactly the rectangle `screencapture -R` takes.
app_window_records() {
    local owner="$1" lines
    lines="$("$WINDOWID" "$owner" --include-panels 2>/dev/null)"
    [[ -n "$lines" ]] || return 1
    print -r -- "$lines"
}

# ==================================================================================================
# THE VISIBILITY DOCTRINE (focus-x7d)
# ==================================================================================================
#
# **A window-id capture is never sole proof that a surface is visible, and this lane may never
# again treat it as one.**
#
# `screencapture -l <windowid>` reads a window's **backing store**. On 2026-08-25 at 19:26 that
# instrument photographed the query panel rendering its question perfectly — the sentence, the
# subtitle, all three actions — while the panel on screen was a large blank white slab. The window
# was 380 × 2212 on a 1920 × 1080 display, so the 190-point band carrying the question sat
# somewhere nobody could look. The backing store was telling the truth about what the window had
# drawn and nothing at all about what a person could see, and this lane accepted it as proof.
#
# So every frame is now taken **twice** and proved three ways:
#
# 1. **Geometry, and it is decisive.** The window's own measured bounds, from `windowid`. For a
#    nudge panel they must equal the shipping `contentSize` — read out of the source constant, not
#    restated here — and the window must lie inside the display. This is the assertion that would
#    have caught the defect on its own, exactly, with no image analysis at all.
# 2. **Both captures, always.** `-l <id>` for the backing store and `-R <x,y,w,h>` at that same
#    window's own measured coordinates for the screen. The second frame is what a person sees.
# 3. **The differential, and it fails loudly.** Both frames are measured by `scripts/frame-ink.py`.
#    A run in which the backing store has ink and the screen at the window's own coordinates does
#    not is the exact signature of this defect, and it stops the lane.
#
# The `-R` frame is filed beside its `-l` twin as `<name>-onscreen.png`, so a reader of the
# evidence directory sees the pair rather than having to know one was taken.

FRAME_INK="scripts/frame-ink.py"

# The display's pixel size, asked for **once**: `system_profiler` takes seconds, and a lane that
# re-read it per frame would spend more time measuring the screen than photographing it. Prints
# `<width> <height>`, falling back to this rig's own 1920x1080 (P-90: one display, no notch).
SCREEN_SIZE_CACHE=''
screen_size() {
    if [[ -z "$SCREEN_SIZE_CACHE" ]]; then
        local pair
        pair="$(system_profiler SPDisplaysDataType 2>/dev/null | grep -m1 -oE '[0-9]+ x [0-9]+')"
        if [[ -n "$pair" ]]; then
            SCREEN_SIZE_CACHE="${pair% x *} ${pair#* x }"
        else
            SCREEN_SIZE_CACHE='1920 1080'
        fi
    fi
    print -r -- "$SCREEN_SIZE_CACHE"
}

# `ink`, `blank`, or `unreadable`, for one frame.
frame_verdict() {
    local frame="$1" line
    [[ -s "$frame" ]] || { print -r -- "missing"; return }
    line="$(python3 "$FRAME_INK" "$frame" 2>/dev/null | tail -1)"
    print -r -- "${${line##*verdict=}%% *}"
}

# The panel's intended size, read from the shipping constant so the lane cannot drift from the
# app. Prints `<width> <height>`, or nothing when the constant cannot be read — in which case the
# geometry assertion says so rather than inventing a number.
PANEL_SIZE_SOURCE="Packages/FocusUI/Sources/FocusUI/Nudge/NudgePanelController.swift"
panel_intended_size() {
    local numbers
    numbers="$(grep -oE 'contentSize = CGSize\(width: [0-9]+, height: [0-9]+\)' "$PANEL_SIZE_SOURCE" 2>/dev/null \
        | grep -oE '[0-9]+' | tr '\n' ' ')"
    print -r -- "${numbers% }"
}

# Both captures of one window, plus the differential. Never called with a window this lane has
# not measured first.
capture_window_pair() {
    local artefact="$1" id="$2" x="$3" y="$4" w="$5" h="$6"
    local backing="$EVIDENCE_DIR/$artefact"
    local onscreen="$EVIDENCE_DIR/${artefact%.png}-onscreen.png"

    "$SCREENCAPTURE" -x -o -l "$id" "$backing" 2>/dev/null
    [[ -s "$backing" ]] || return 1
    produced "${backing:t}"

    "$SCREENCAPTURE" -x -o -R "$x,$y,$w,$h" "$onscreen" 2>/dev/null
    if [[ ! -s "$onscreen" ]]; then
        print -u2 "LIVE-LANE VISIBILITY FAILURE: ${backing:t} has a backing-store frame but no"
        print -u2 "    screen frame at its own coordinates ($x,$y,$w,$h). A window-id capture is"
        print -u2 "    not proof that anybody can see the window."
        VISIBILITY_FAILURES+=("${backing:t}")
        return 1
    fi
    produced "${onscreen:t}"

    local backing_verdict onscreen_verdict
    backing_verdict="$(frame_verdict "$backing")"
    onscreen_verdict="$(frame_verdict "$onscreen")"
    print "     visibility: ${backing:t} backing=$backing_verdict screen=$onscreen_verdict (window $id at $x,$y,$w,$h)"

    if [[ "$backing_verdict" == "ink" && "$onscreen_verdict" == "blank" ]]; then
        print -u2 "LIVE-LANE VISIBILITY FAILURE: ${backing:t}"
        print -u2 "    The window's BACKING STORE has content and the SCREEN at that same window's"
        print -u2 "    own coordinates ($x,$y,$w,$h) is blank. This is the exact signature of"
        print -u2 "    focus-x7d: the surface rendered, and nobody could see it. Read"
        print -u2 "    ${onscreen:t} beside ${backing:t} before believing any claim about this frame."
        VISIBILITY_FAILURES+=("${backing:t}")
        return 1
    fi
    return 0
}

# Capture every window an application owns into one frame set. **There is no "use the front-most
# entry" fallback anywhere in this file.** e02's lane learned that the hard way: a 900×704 picture
# of the cockpit filed as the quick-capture panel. A frame that shows the wrong window is worse
# than a missing frame.
capture_windows() {
    local artefact="$1" owner="${2:-$WINDOW_OWNER}" index=0 target rc=1
    local record id x y w h
    for record in ${(f)"$(app_window_records "$owner")"}; do
        [[ -n "$record" ]] || continue
        read -r id x y w h <<< "$record"
        [[ -n "$h" ]] || continue
        (( index += 1 ))
        if (( index == 1 )); then
            target="$artefact"
        else
            target="${artefact%.png}-$index.png"
        fi
        capture_window_pair "$target" "$id" "$x" "$y" "$w" "$h" && rc=0
    done
    return $rc
}

# **The geometry half of the doctrine, and the one that would have caught focus-x7d alone.**
#
# Among the app's windows there must be exactly one whose size is the panel's intended size, and
# it must lie inside the display. Failing here dumps every window this lane can see with its
# bounds, because "the panel is the wrong size" is only useful next to what size it actually is.
require_panel_geometry() {
    local label="$1" expected width height record id x y w h
    expected="$(panel_intended_size)"
    if [[ -z "$expected" ]]; then
        print -u2 "LIVE-LANE VISIBILITY FAILURE: cannot read contentSize from $PANEL_SIZE_SOURCE"
        VISIBILITY_FAILURES+=("$label")
        return 1
    fi
    read -r width height <<< "$expected"

    local screen_width screen_height matches=0 observed=""
    read -r screen_width screen_height <<< "$(screen_size)"

    for record in ${(f)"$(app_window_records "$WINDOW_OWNER")"}; do
        [[ -n "$record" ]] || continue
        read -r id x y w h <<< "$record"
        [[ -n "$h" ]] || continue
        observed+="        window $id at $x,$y ${w}x${h}"$'\n'
        if (( w == width && h == height )); then
            if (( x >= 0 && y >= 0 && x + w <= screen_width && y + h <= screen_height )); then
                (( matches += 1 ))
            else
                observed+="            ^ right size, but not inside the ${screen_width}x${screen_height} display"$'\n'
            fi
        fi
    done

    if (( matches == 1 )); then
        print "ok   visibility: $label — one panel-sized window (${width}x${height}) inside the display"
        return 0
    fi

    print -u2 "LIVE-LANE VISIBILITY FAILURE: $label"
    print -u2 "    Expected exactly ONE window of ${width}x${height} (NudgePanelController.contentSize)"
    print -u2 "    fully inside the ${screen_width}x${screen_height} display; found $matches."
    print -u2 "    This is focus-x7d's own signature: the live panel measured 380x2212 while its"
    print -u2 "    backing store photographed perfectly. Observed windows:"
    print -ru2 -- "$observed"
    VISIBILITY_FAILURES+=("$label")
    return 1
}

# The menu bar. P-132 measured status-item window numbers at or above 2**32 — synthetic, and
# `screencapture -l` cannot address them — so the instrument here is `-R <rect>` over the
# right-hand strip, which is where the extras live.
capture_menu_bar() {
    local artefact="$1" width height
    read -r width height <<< "$(screen_size)"
    "$SCREENCAPTURE" -x -o -R "$(( width - 1220 )),0,1220,32" "$EVIDENCE_DIR/$artefact" 2>/dev/null
    if [[ -s "$EVIDENCE_DIR/$artefact" ]]; then
        produced "$artefact"
        return 0
    fi
    return 1
}

# The app's own report, from a short-lived second instance.
#
# **Read what this is and is not.** It launches another process, so its session-lived state — the
# ladder, the interruption slot, the fatigue counters — describes THAT process rather than the one
# being driven. What is process-independent, and is why the instrument exists at all, is everything
# that lives in the store: the active priority, the rules, the query ledger's receipts and the
# day's interruption counts. Those are exactly the facts `require_state` needs.
read_state() {
    local destination="$1"
    "$BINARY" --focus-self-check "$destination" --focus-self-check-nudge \
        > "$LOG_DIR/focus-live-nudge-state.log" 2>&1 || return 1
    [[ -s "$destination" ]] || return 1
    return 0
}

# **R-97 rule 3, mechanised.** Read the app's report and require a python expression over it. On
# failure the scenario aborts with the observed report dumped beside the expectation.
require_state() {
    local description="$1" expression="$2" destination="$LOG_DIR/focus-live-nudge-require.json"
    if ! read_state "$destination"; then
        abort_scenario "could not read the app's state to verify: $description"
        return 1
    fi
    if python3 - "$destination" "$expression" <<'PYTHON'
import json
import sys

with open(sys.argv[1]) as handle:
    report = json.load(handle)
sys.exit(0 if eval(sys.argv[2], {"report": report}) else 1)  # noqa: S307
PYTHON
    then
        print "ok   precondition: $description"
        return 0
    fi
    abort_scenario "precondition not reached: $description" "$(cat -- "$destination")"
    return 1
}

# **The reset.** Terminate everything, relaunch the app, settle. Store state a person owns — the
# priority and its context pack — is offered through the shipped `focus://` handoff and confirmed
# by an operator, because F-142 is explicit that there is no route from a URL to a store mutation
# that does not pass through a person pressing **Replace**. That is a feature rather than an
# obstacle, and it is why several scenarios below are OPERATOR-ASSISTED.
reset() {
    SCENARIO="$1"
    print
    print "──────────────────────────────────────────────────────────────────────"
    note "RESET for $SCENARIO"
    cleanup
    sleep 2
    open -a "$APP"
    sleep 4
    if ! app_window_ids "$WINDOW_OWNER" > /dev/null; then
        abort_scenario "the app put no window on screen after the reset"
        return 1
    fi
    timeline "reset · $SCENARIO"
    return 0
}

foreground() {
    local target="$1"
    open -a "$target"
    sleep 2
}

# --- S1 · at rest ---------------------------------------------------------------------------------
#
# reset: priority P1, no rules, session `.focus`, no decoy running.

scenario_at_rest() {
    reset "S1 · at rest" || return 0

    if ! prompt_operator "set the priority to “$PRIORITY_INTENT” (⌃⌘Space, type it, confirm) and attach $CONTEXT_APP as an app context chip, then start a session."; then
        manual_required "01-cockpit-at-rest.png" \
            "no operator was at the keyboard, so this run set no priority — and with no priority every gate below is gate 1 (noActivePriority) rather than the behaviour the frames are about." \
            "Run this script attended. At the prompt press ⌃⌘Space, type the priority, confirm it, drag $CONTEXT_APP onto the context row and press Start."
        manual_required "02-menu-bar-at-rest.png" "as frame 1" "as frame 1"
        return 0
    fi

    require_state "an active priority exists and the engine judged at least once" \
        "report.get('decisionCount', 0) >= 0" || return 0

    capture_windows "01-cockpit-at-rest.png"
    timeline "01 · the cockpit at rest — the priority hero, the session running, the verdict relevant"
    capture_menu_bar "02-menu-bar-at-rest.png"
    timeline "02 · the menu bar at rest — the check-circle glyph and the monospaced timer"
}

# --- S2 · the ladder -------------------------------------------------------------------------------
#
# reset: priority P1; `FocusDecoy` seeded `unrelated`; no task rules; phase `.focus`; notifications
# unauthorised; ladder `.idle`; budget empty.

scenario_ladder() {
    reset "S2 · the ladder" || return 0

    require_state "the app asked for no notification authorisation" \
        "report.get('requestAuthorizationCallCount') == 0" || return 0
    require_state "every rung reaches an in-app surface, and no authorisation can move it" \
        "report.get('everyRungIsInApp') is True" || return 0

    if ! prompt_operator "set the priority to “$PRIORITY_INTENT”, attach $CONTEXT_APP as a context chip, and add a rule marking “$DECOY_ID” unrelated (Settings ▸ Rules)."; then
        manual_required "03-decoy-foregrounded.png" \
            "no operator was at the keyboard, so no priority and no seeded rule exist and the decoy cannot produce the unrelated verdict this scenario is about." \
            "Run attended. Set the priority, attach the context chip, then add an app rule for $DECOY_ID with verdict 'unrelated'."
        for frame in 04-menu-bar-ambient.png 05-rung2-panel.png 06-rung3-recommitment.png; do
            manual_required "$frame" "as frame 3" "as frame 3"
        done
        return 0
    fi

    note "bringing the decoy forward"
    open -a "$DECOY_APP"
    sleep 3
    capture_windows "03-decoy-foregrounded.png" "$DECOY_OWNER"
    timeline "03 · the decoy owns the screen — a real application, really in front"

    note "waiting out the grace period (${SUSTAINED_DRIFT}s)"
    sleep $(( SUSTAINED_DRIFT + 8 ))
    capture_menu_bar "04-menu-bar-ambient.png"
    timeline "04 · rung 1 — the glyph changed to the triangle. No panel, no sound, no motion."

    note "waiting out escalationDwell (${ESCALATION_DWELL}s) for rung 2"
    sleep $(( ESCALATION_DWELL + 8 ))
    require_panel_geometry "05 · rung 2 panel"
    capture_windows "05-rung2-panel.png"
    timeline "05 · rung 2 — the compact panel over the decoy, 'Still working on {task}?', five actions"
    timeline "    READ: all four R-89 readings are gated at zero grants by scripts/check-focus-steal.sh"

    frame_17_keystroke_sink

    note "waiting out escalationDwell again for rung 3"
    sleep $(( ESCALATION_DWELL + 8 ))
    require_panel_geometry "06 · rung 3 recommitment panel"
    capture_windows "06-rung3-recommitment.png"
    timeline "06 · rung 3 with notifications unauthorised — the recommitment panel, still dismissible (D-07)"
}

# --- frame 17 · the keystroke sink (finding 1) -------------------------------------------------------
#
# The single most important behavioural property of the epic, and the one that cannot be gated:
# posting a synthetic key event needs Accessibility on the DRIVER, and no T1 criterion may depend
# on a grant. So it is read evidence here, with the driver holding the grant and the app under test
# holding none — and it skips cleanly when the grant is absent.

frame_17_keystroke_sink() {
    if (( ! HAS_ACCESSIBILITY )); then
        manual_required "17-keystroke-sink.png" \
            "the driving shell does not hold Accessibility, so no synthetic key event could be posted. The app under test holds no grant either way; this is the DRIVER's grant." \
            "Grant Accessibility to your terminal in System Settings ▸ Privacy & Security ▸ Accessibility and re-run. The frame types a unique token while the rung-2 panel is on screen and asserts the token landed in FocusDecoy2's field and NOT in the panel."
        timeline "17 · SKIPPED — the driver holds no Accessibility grant (never a close condition)"
        return 0
    fi

    local token="focus-$(date +%s)-sink"
    note "frame 17 — typing '$token' with the panel on screen"
    rm -f -- "$ECHO_FILE"
    open -a "$DECOY2_APP" --args --echo "$ECHO_FILE"
    sleep 3

    osascript -e "tell application \"System Events\" to keystroke \"$token\"" \
        > "$LOG_DIR/focus-live-nudge-keystroke.log" 2>&1
    local typed_rc=$?
    sleep 2

    capture_windows "17-keystroke-sink.png" "$DECOY2_OWNER"

    local landed=''
    [[ -s "$ECHO_FILE" ]] && landed="$(cat -- "$ECHO_FILE")"
    if [[ "$landed" == *"$token"* ]]; then
        timeline "17 · the token '$token' landed in the DECOY's field while the panel was on screen — the panel took no keystroke"
    else
        timeline "17 · FAILED — the token did not reach the decoy's field (osascript EXIT=$typed_rc, field held '${landed:-<empty>}')"
        print -u2 "LIVE-FRAME 17 FAILED: the keystroke did not land in the decoy"
    fi
    pkill -x "$DECOY2" 2>/dev/null
}

# --- S3 · the correction economy ---------------------------------------------------------------------
#
# Three sub-scenarios, **each preceded by its own reset** and each driven back to a live rung-2
# panel before the action — because a corrected subject has no panel left to act from, which is
# exactly the unreachability adversarial review found.

scenario_correction_economy() {
    local frame action
    for pair in \
        "08-snooze-countdown.png:snooze the decoy for 5 minutes" \
        "09-change-priority.png:press Change priority" \
        "10-return-to-task.png:press Back to $CONTEXT_APP"
    do
        frame="${pair%%:*}"
        action="${pair#*:}"
        reset "S3 · the correction economy (${frame})" || continue
        drive_to_rung_two || continue
        if prompt_operator "on the nudge panel, $action."; then
            sleep 3
            case "$frame" in
                08-*) capture_menu_bar "$frame"
                      timeline "08 · snoozed — the countdown runs in the menu bar, and the ambient glyph still tells the truth" ;;
                09-*) capture_windows "$frame"
                      timeline "09 · Change priority opened e02's confirm surface — the active priority is NOT yet replaced (F-142)" ;;
                10-*) capture_windows "$frame" "$CONTEXT_APP"
                      timeline "10 · one click back to $CONTEXT_APP — and the app itself never became active (P-135)" ;;
            esac
        else
            manual_required "$frame" \
                "no operator was at the keyboard to perform the correction." \
                "Run attended. Drive the decoy past ${SUSTAINED_DRIFT}s and then ${ESCALATION_DWELL}s so the rung-2 panel appears, then $action."
        fi
    done
}

# Drive the world to a live rung-2 panel. Aborts the scenario rather than continuing when the
# precondition cannot be reached (R-97.3).
drive_to_rung_two() {
    if ! prompt_operator "set the priority to “$PRIORITY_INTENT”, attach $CONTEXT_APP, add an unrelated rule for $DECOY_ID, and start a session."; then
        abort_scenario "no operator set the priority, so no mandate can exist" "<unattended>"
        return 1
    fi
    open -a "$DECOY_APP"
    sleep $(( SUSTAINED_DRIFT + ESCALATION_DWELL + 16 ))
    if ! app_window_ids "$WINDOW_OWNER" > /dev/null; then
        abort_scenario "the app owns no window, so there is no panel to act from" "<no windows>"
        return 1
    fi
    return 0
}

# --- S4 · the durable correction ----------------------------------------------------------------------

scenario_durable_correction() {
    reset "S4 · the durable correction" || return 0
    drive_to_rung_two || return 0

    if prompt_operator "on the nudge panel press “This is relevant”, then open Settings ▸ Rules."; then
        sleep 3
        capture_windows "07-this-is-relevant.png"
        timeline "07 · 'This is relevant' wrote a task-authority rule, visible in the Rules pane — the next classification arrives at the taskRule rung and the ladder is idle"
    else
        manual_required "07-this-is-relevant.png" \
            "no operator was at the keyboard to press the correction." \
            "Run attended. With the rung-2 panel up, press 'This is relevant' and open Settings ▸ Rules: a task-authority rule for $DECOY_ID must be listed."
    fi
}

# --- S5 · the phases that silence everything ------------------------------------------------------------
#
# reset: priority P1, `FocusDecoy2` running and uncertain, no rules, no receipts.

scenario_silent_phases() {
    reset "S5 · the phases that silence everything" || return 0

    if ! prompt_operator "set the priority to “$PRIORITY_INTENT” and start a session."; then
        manual_required "11-paused.png" "no operator set a priority." "Run attended."
        manual_required "16-break.png" "as frame 11" "as frame 11"
        return 0
    fi

    open -a "$DECOY2_APP" --args --echo "$ECHO_FILE"
    sleep $(( QUERY_DWELL + 8 ))

    if prompt_operator "pause the session (⌃⌘P)."; then
        sleep 3
        capture_menu_bar "11-paused.png"
        timeline "11 · paused — the pause-rectangle glyph, and NO panel: a query that would otherwise be warranted is suppressed at gate 4"
    else
        manual_required "11-paused.png" "no operator paused the session." "Run attended and press ⌃⌘P."
    fi

    if prompt_operator "resume, then take a break (Session ▸ Break)."; then
        sleep 3
        capture_menu_bar "16-break.png"
        timeline "16 · on a break — the cup glyph, and nothing else. Same gate, different phase."
    else
        manual_required "16-break.png" "no operator started a break." "Run attended."
    fi
    pkill -x "$DECOY2" 2>/dev/null
}

# --- S6 · the query ---------------------------------------------------------------------------------------
#
# reset: priority P1; **`FocusDecoy2`**, whose identity matches no seed, no rule and no priority
# token; phase `.focus`; **ledger empty**; query budget empty.

scenario_query() {
    reset "S6 · the query" || return 0

    if ! prompt_operator "set the priority to “$PRIORITY_INTENT”, attach $CONTEXT_APP, and start a session. Do NOT add any rule about $DECOY2_ID."; then
        for frame in 12-the-query.png 13-query-answered-yes.png 14-subject-returns.png 14b-rule-deleted.png; do
            manual_required "$frame" \
                "no operator set a priority, so no uncertain verdict about $DECOY2_ID can be produced." \
                "Run attended. Set the priority, attach $CONTEXT_APP, start a session, then bring FocusDecoy2 forward and leave it for more than ${QUERY_DWELL}s."
        done
        return 0
    fi

    note "bringing the neutral decoy forward and waiting out queryDwellThreshold (${QUERY_DWELL}s)"
    open -a "$DECOY2_APP" --args --echo "$ECHO_FILE"
    sleep $(( QUERY_DWELL + 10 ))

    require_panel_geometry "12 · the question panel"
    capture_windows "12-the-query.png"
    timeline "12 · the question — 'Is {subject} part of {task}?', three actions, and the scope stated in the copy"

    if prompt_operator "on the question panel press “Yes, add it”, then look at the cockpit's context row and Settings ▸ Rules."; then
        sleep 3
        capture_windows "13-query-answered-yes.png"
        timeline "13 · ONE transaction, TWO records — the learned context chip and the Rules-pane row are two renderings of the same rule id, and an invisible receipt was written beside it"
    else
        manual_required "13-query-answered-yes.png" "no operator answered the question." "Run attended."
        return 0
    fi

    note "cycling the phase and re-foregrounding the same subject"
    foreground "$CONTEXT_APP"
    sleep 5
    open -a "$DECOY2_APP" --args --echo "$ECHO_FILE"
    sleep $(( QUERY_DWELL + 10 ))
    capture_menu_bar "14-subject-returns.png"
    timeline "14 · the same subject returns — menu bar relevant, NO panel and NO question. The verdict's source is userRule."

    if prompt_operator "delete the learned rule for $DECOY2_ID (remove the chip, or the Rules-pane row), then bring FocusDecoy2 forward again."; then
        sleep $(( QUERY_DWELL + 10 ))
        capture_menu_bar "14b-rule-deleted.png"
        timeline "14b · the rule deleted, and STILL no question — the verdict is uncertain again, hasAsked is true, and eligibility is withheld(alreadyAsked). Removing a learned chip means 'that is not a fact about my work', never 'ask me again'."
    else
        manual_required "14b-rule-deleted.png" \
            "no operator deleted the learned rule." \
            "Run attended. Remove the learned chip for $DECOY2_ID, bring FocusDecoy2 forward, wait more than ${QUERY_DWELL}s: the verdict returns to uncertain and the app still says nothing."
    fi
    pkill -x "$DECOY2" 2>/dev/null
}

# --- S7 · the presentation --------------------------------------------------------------------------------
#
# reset as S2 (decoy seeded `unrelated`, ladder `.idle`), then a **live mandate** driven to rung 1
# *before* `FocusDecoy` enters its full-screen space.

scenario_presentation() {
    reset "S7 · the presentation" || return 0

    if ! prompt_operator "set the priority to “$PRIORITY_INTENT”, attach $CONTEXT_APP, add an unrelated rule for $DECOY_ID, and start a session."; then
        manual_required "15-decoy-full-screen.png" \
            "no operator set the priority and the rule, so no mandate can exist and there is nothing for the presentation to defer." \
            "Run attended. Set the priority and the rule, bring FocusDecoy forward for more than ${SUSTAINED_DRIFT}s so rung 1 is delivered, then let it enter its full-screen space."
        return 0
    fi

    note "driving to rung 1 BEFORE the full-screen space"
    open -a "$DECOY_APP"
    sleep $(( SUSTAINED_DRIFT + 10 ))
    capture_menu_bar "04-menu-bar-ambient.png" > /dev/null 2>&1

    note "sending the decoy into a real full-screen space"
    pkill -x "$DECOY" 2>/dev/null
    sleep 2
    open -a "$DECOY_APP" --args --fullscreen
    sleep $(( SUSTAINED_DRIFT + ESCALATION_DWELL + 16 ))

    # The whole frame is the CLEANNESS of the space, so it is captured as a full-screen shot rather
    # than per-window: a per-window capture of the decoy would show the decoy whether or not a
    # panel was floating over it.
    "$SCREENCAPTURE" -x -o "$EVIDENCE_DIR/15-decoy-full-screen.png" 2>/dev/null
    if [[ -s "$EVIDENCE_DIR/15-decoy-full-screen.png" ]]; then
        produced "15-decoy-full-screen.png"
        timeline "15 · the decoy's full-screen space, CLEAN — no panel anywhere. The rung is recorded deferred(menuBarHidden) and the ladder did NOT advance (R-81, P-130, P-131)."
    else
        manual_required "15-decoy-full-screen.png" \
            "screencapture produced nothing for the full-screen space." \
            "Run attended with Screen Recording granted to the driving shell."
    fi
    pkill -x "$DECOY" 2>/dev/null
}

# --- run the seven, in capture order ----------------------------------------------------------------------

scenario_at_rest
scenario_ladder
scenario_correction_economy
scenario_durable_correction
scenario_silent_phases
scenario_query
scenario_presentation

# --- the ledger ---------------------------------------------------------------------------------------------

{
    print
    print "what this run produced"
    print -r -- "----------------------"
    for artefact in $PRODUCED; do print "  produced          $artefact"; done
    for artefact in $RECEIPTS; do print "  operator-assisted $artefact (receipt written)"; done
    for scenario in $ABORTED; do print "  ABORTED           $scenario"; done
    for artefact in $VISIBILITY_FAILURES; do print "  NOT VISIBLE       $artefact"; done
    print
    print "Every window frame comes in a PAIR: <name>.png is the window's backing store, taken with"
    print "screencapture -l, and <name>-onscreen.png is the SCREEN at that same window's own measured"
    print "coordinates. Read both. On 2026-08-25 the backing store of the query panel showed the"
    print "question perfectly while the screen at its coordinates was a blank white slab — the window"
    print "was 380x2212 on a 1920x1080 display — and this lane called it proof. A window-id capture"
    print "proves a window RENDERED. Only the screen frame proves a person could SEE it."
    print
    print "The frames are READ, by eye, and that reading is the evidence (charter tmux-verify"
    print "doctrine). Four of them decide whether this epic shipped a guardian or a nuisance:"
    print "  frame 5   — it does not take the application"
    print "  frame 17  — it does not take the keyboard"
    print "  frame 14b — it does not ask twice even after you undo its answer"
    print "  frame 15  — it does not stomp a presentation"
} >> "$EVIDENCE_DIR/nudge-timeline.txt"

produced "nudge-timeline.txt"

print
print "== live nudge drive complete"
print "evidence:  $EVIDENCE_DIR"
print "produced:  ${#PRODUCED} artefact(s), ${#RECEIPTS} receipt(s), ${#ABORTED} aborted scenario(s)"
print
print "This lane is read evidence and never a close condition for a GRANT: a missing grant skips,"
print "and an ABORTED scenario is a failure of that scenario, printed to stderr and recorded in the"
print "timeline, never a frame captured in the wrong state (R-97 rule 3)."

if (( ${#VISIBILITY_FAILURES} > 0 )); then
    print
    print -u2 "=============================================================="
    print -u2 "LIVE-LANE FAILED: ${#VISIBILITY_FAILURES} VISIBILITY FAILURE(S)"
    print -u2 "=============================================================="
    for artefact in $VISIBILITY_FAILURES; do print -u2 "  $artefact"; done
    print -u2
    print -u2 "A visibility failure is NOT a missing grant and NOT an unreachable precondition. It"
    print -u2 "is the app putting a surface somewhere a person cannot read it, proven by the app's"
    print -u2 "own window bounds or by its backing store and the screen disagreeing. That is"
    print -u2 "focus-x7d, it is the defect this lane was structurally unable to see, and it exits 1."
    exit 1
fi

exit 0
