#!/bin/zsh
# The live capture drive — TCC-GATED EVIDENCE, never a gate.
#
#   scripts/live-capture-drive.sh
#
# Launches the real app on this Mac, presses the real global hot key with another application
# frontmost, drives the cockpit through its own keyboard contract, and leaves frames in
# $FOCUS_EVIDENCE_DIR for a human — or the verifying agent — to **read**. Capturing is not the
# point; reading is.
#
# ## Why this is not a gate, and never may be
#
# Standing condition 5: no acceptance criterion may depend on a TCC grant. Everything below
# needs grants held by the *driving shell* — Accessibility (to send keystrokes and read the
# window tree through System Events), Automation (to talk to System Events at all) and Screen
# Recording (to capture another process's window). A criterion that passed here would fail on
# a machine where those are revoked, for a reason that has nothing to do with the code.
#
# So: when a grant is missing this script prints `LIVE-LANE SKIPPED: <grant>` and exits **0**,
# and `scripts/build-gate.sh` never invokes it. The half of the capture contract that must hold
# regardless — that `RegisterEventHotKey` returns `noErr`, that offering the same combination
# twice returns `-9878`, that the panel is pre-built and shows in under 250 ms, and that the
# product declares the `focus` scheme — is asserted at **zero grants** by
# `scripts/self-check.sh`, which is stage 9 of the gate.
#
# ## The one claim only this lane can make (probe P-56)
#
# A process `exec`'d from a shell that already holds Accessibility inherits that shell's TCC
# responsibility and reports `AXIsProcessTrusted() == true`. `self-check.sh` launches the
# binary exactly that way, so its `axIsProcessTrusted` field is **recorded and never asserted**.
# The honest grant-free proof needs the app to be its own responsible process, which is what
# `open -n -a` gives it, and it needs the app's own Accessibility approval cleared first, which
# is what `tccutil reset` does. Both happen in section 3, and the transcript is written to
# `hotkey-untrusted.txt`: `AXIsProcessTrusted() == false`, registration status `0`, and the
# panel appearing anyway while Finder is frontmost.
#
# `tccutil reset Accessibility <this app's bundle id>` touches **only** this app's row. It does
# not clear the grant held by the terminal running this script, and it must not: the driving
# half of the lane needs it.
#
# ## Environment
#
#   FOCUS_EVIDENCE_DIR   where the artefacts land   (default .agents/evidence/e02)
#   FOCUS_DERIVED_DATA   build location             (default /tmp/focus-dd)
#   FOCUS_LOG_DIR        log location               (default /tmp)
#   FOCUS_LIVE_TEXT_SIZE set to `raised` when the system-wide Text Size has already been
#                        increased by hand (System Settings → Accessibility → Display → Text
#                        size); only then is `cockpit-accessibility.png` captured, because a
#                        frame named for a text size the machine is not running at is evidence
#                        of nothing. macOS has no injectable Dynamic Type, so the zero-grant
#                        equivalent is the snapshot lane's `ShellTextScale.accessibilityLarge`
#                        matrix plus `DynamicTextResilienceTests`.
set -u

REPO_ROOT="${0:A:h}/.."
cd "$REPO_ROOT" || exit 1

EVIDENCE_DIR="${FOCUS_EVIDENCE_DIR:-.agents/evidence/e02}"
DD="${FOCUS_DERIVED_DATA:-/tmp/focus-dd}"
LOG_DIR="${FOCUS_LOG_DIR:-/tmp}"
DESTINATION='platform=macOS,arch=arm64'

# Two names for the same application, both measured rather than assumed (e01's live lane):
# `CGWindowListCopyWindowInfo` reports "Focus Sentinel" in `kCGWindowOwnerName`, and System
# Events addresses the process by its bundle name, "FocusSentinel".
WINDOW_OWNER='Focus Sentinel'
PROCESS_NAME='FocusSentinel'
BUNDLE_ID='com.chrismitchelmore.FocusSentinel'

APP="$DD/Build/Products/Debug/FocusSentinel.app"

# The window titles the surfaces present. Read from the String Catalog by the app; written
# here because AppleScript addresses windows by title and has no other handle on them.
COCKPIT_TITLE='Focus Sentinel'
PANEL_TITLE='Quick Capture'

# The quick-capture default, ⌃⌥⌘Space (`HotKeySpec.quickCaptureDefault`, key code 49).
HOTKEY_APPLESCRIPT='key code 49 using {control down, option down, command down}'

mkdir -p -- "$EVIDENCE_DIR" "$LOG_DIR" || exit 1

typeset -a CAPTURED NOTES
CAPTURED=()
NOTES=()

note() { print "== $*" }
skip() { print "LIVE-LANE SKIPPED: $*"; exit 0 }
die()  { print -u2 "LIVE-LANE ERROR: $*"; cleanup; exit 1 }

cleanup() {
    # `pkill -x` rather than an Apple Event to the app: quitting has to work even when the app
    # is wedged, and the app itself links no Apple Events at all (standing condition 2).
    pkill -x "$PROCESS_NAME" 2>/dev/null
    return 0
}

SCREENCAPTURE="${commands[screencapture]:-/usr/sbin/screencapture}"
[[ -x "$SCREENCAPTURE" ]] || die "no screencapture binary at $SCREENCAPTURE"

# --- 0 · the grant preflight ----------------------------------------------------------------
#
# `windowid --grants` calls `AXIsProcessTrusted()` and `CGPreflightScreenCaptureAccess()`. Both
# are *preflight* calls: this script never puts a permission dialog in front of anybody.

note "building the window-id test driver"
swift build --package-path Tools/windowid > "$LOG_DIR/focus-live-windowid.log" 2>&1
build_rc=$?
print "windowid build EXIT=$build_rc log=$LOG_DIR/focus-live-windowid.log"
(( build_rc == 0 )) || die "could not build Tools/windowid"

WINDOWID="$(swift build --package-path Tools/windowid --show-bin-path 2>/dev/null)/windowid"
[[ -x "$WINDOWID" ]] || die "no windowid binary at $WINDOWID"

note "TCC preflight"
grants="$("$WINDOWID" --grants)"
grants_rc=$?
print "$grants"
if (( grants_rc != 0 )); then
    typeset -a missing
    missing=()
    [[ "$grants" == *"accessibility=no"* ]]    && missing+=("Accessibility")
    [[ "$grants" == *"screen-recording=no"* ]] && missing+=("Screen Recording")
    skip "${(j:, :)missing} not granted to the driving shell"
fi

if ! osascript -e 'tell application "System Events" to return name of first process' > /dev/null 2>&1; then
    skip "Automation (Apple Events to System Events) not granted to the driving shell"
fi

# --- 1 · build the app -----------------------------------------------------------------------

note "building the Debug app"
xcodebuild -workspace Focus.xcworkspace -scheme FocusSentinel \
    -configuration Debug -destination "$DESTINATION" -derivedDataPath "$DD" build \
    > "$LOG_DIR/focus-live-capture-build.log" 2>&1
app_rc=$?
print "build EXIT=$app_rc log=$LOG_DIR/focus-live-capture-build.log"
(( app_rc == 0 )) || die "the Debug build failed"
[[ -d "$APP" ]] || die "no app bundle at $APP"

# --- helpers ----------------------------------------------------------------------------------
#
# Never `local path=…` in zsh: `path` is tied to `PATH`, so a local assignment to it empties the
# command search path for the whole call. Measured the hard way in e01's live lane.

ax() {
    osascript 2>/dev/null <<AS
tell application "System Events" to tell process "$PROCESS_NAME"
$1
end tell
AS
}

ax_front_frame() {
    ax '    set theWindow to window 1
    set {x, y} to position of theWindow
    set {w, h} to size of theWindow
    return (x as text) & " " & (y as text) & " " & (w as text) & " " & (h as text)'
}

ax_front_title() {
    ax '    return title of window 1'
}

# Whether the process currently has a window with this title, anywhere in its window list —
# not just frontmost. This is how the hot-key evidence knows the panel arrived.
ax_has_window() {
    local wanted="$1" found
    found="$(ax "    return (count of (every window whose title is \"$wanted\")) as text")"
    [[ "$found" != "" && "$found" != "0" ]]
}

front_window_id() {
    local frame entries entry
    frame="$(ax_front_frame)"
    entries="$("$WINDOWID" "$WINDOW_OWNER" 2>/dev/null)"
    [[ -n "$entries" ]] || return 1

    if [[ -n "$frame" ]]; then
        while IFS= read -r entry; do
            [[ "${entry#* }" == "$frame" ]] && { print -r -- "${entry%% *}"; return 0 }
        done <<< "$entries"
    fi

    print -u2 "    (no window-list bounds match for AX frame '$frame'; using the front-most entry)"
    print -r -- "${${entries%%$'\n'*}%% *}"
}

# "Settled" means the app has an on-screen window that both the window list and the
# Accessibility API agree about — not a fixed sleep.
settle() {
    local attempt
    for attempt in {1..30}; do
        if [[ -n "$("$WINDOWID" "$WINDOW_OWNER" 2>/dev/null)" ]] && [[ -n "$(ax_front_frame)" ]]; then
            sleep 0.4
            return 0
        fi
        sleep 0.5
    done
    return 1
}

await_window() {
    local wanted="$1" attempt
    for attempt in {1..20}; do
        [[ "$(ax_front_title)" == "$wanted" ]] && { sleep 0.5; return 0 }
        sleep 0.4
    done
    return 1
}

capture_front() {
    local name="$1" expected_title="${2:-}"
    local id title outfile="$EVIDENCE_DIR/$1"

    title="$(ax_front_title)"
    if [[ -n "$expected_title" && "$title" != "$expected_title" ]]; then
        print -u2 "    (frontmost window is '$title', expected '$expected_title')"
    fi

    id="$(front_window_id)" || { print -u2 "    (no window to capture for $name)"; return 1 }
    "$SCREENCAPTURE" -x -o -l "$id" "$outfile"
    local rc=$?
    if (( rc == 0 )) && [[ -s "$outfile" ]]; then
        print "    captured $outfile  (window $id, title '$title')"
        CAPTURED+=("$name")
        return 0
    fi
    print -u2 "    (screencapture EXIT=$rc for $name)"
    return 1
}

raise_cockpit() {
    ax "    click menu item \"$COCKPIT_TITLE\" of menu 1 of menu bar item \"Window\" of menu bar 1" > /dev/null
    await_window "$COCKPIT_TITLE"
}

type_text() {
    ax "    keystroke \"${1//\"/\\\"}\"" > /dev/null
}

press_return() { ax '    key code 36' > /dev/null }
press_escape() { ax '    key code 53' > /dev/null }
press_space()  { ax '    key code 49' > /dev/null }
press_tab()    { ax '    key code 48' > /dev/null }

# Put the keyboard in a text field found by the placeholder the String Catalog gave it.
#
# Addressing by placeholder rather than by index: the cockpit's field count changes with what
# the priority carries, and an index that is right today is a frame of the wrong control the
# first time a row is added.
focus_field_with_placeholder() {
    local placeholder="$1" result
    result="$(ax "    set matches to (every text field of entire contents of window 1 whose value of attribute \"AXPlaceholderValue\" is \"$placeholder\")
    if (count of matches) is 0 then return \"none\"
    set focused of (item 1 of matches) to true
    return \"ok\"")"
    [[ "$result" == "ok" ]]
}

# --- 2 · the grant-free hot key, on the shipped build (P-56 reproduced) -----------------------
#
# Two measurements, both about the *app's* grant and neither about this shell's.

note "clearing this app's own Accessibility approval"
tcc_out="$(tccutil reset Accessibility "$BUNDLE_ID" 2>&1)"
tcc_rc=$?
print "    tccutil reset Accessibility $BUNDLE_ID -> EXIT=$tcc_rc $tcc_out"

cleanup
sleep 0.5

SELFCHECK_JSON="$LOG_DIR/focus-live-untrusted.json"
rm -f -- "$SELFCHECK_JSON"

note "launching as its own responsible process for the untrusted reading"
open -n -a "$APP" --args --focus-self-check "$SELFCHECK_JSON" \
    > "$LOG_DIR/focus-live-untrusted.log" 2>&1
for attempt in {1..40}; do
    [[ -s "$SELFCHECK_JSON" ]] && break
    sleep 0.5
done

untrusted_ax="(not read)"
untrusted_status="(not read)"
untrusted_duplicate="(not read)"
if [[ -s "$SELFCHECK_JSON" ]]; then
    untrusted_ax="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["axIsProcessTrusted"])' "$SELFCHECK_JSON" 2>/dev/null)"
    untrusted_status="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hotKey"]["status"])' "$SELFCHECK_JSON" 2>/dev/null)"
    untrusted_duplicate="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hotKey"]["duplicateStatus"])' "$SELFCHECK_JSON" 2>/dev/null)"
else
    NOTES+=("the self-check JSON was never written to $SELFCHECK_JSON")
fi
print "    AXIsProcessTrusted=$untrusted_ax  hotKey.status=$untrusted_status  duplicateStatus=$untrusted_duplicate"

cleanup
sleep 0.5

note "launching the app for the driven half"
open -n -a "$APP" > "$LOG_DIR/focus-live-capture-launch.log" 2>&1 \
    || die "could not launch the app"
settle || die "the app never presented an on-screen window"
print "    window list: $("$WINDOWID" "$WINDOW_OWNER" | tr '\n' ';')"

# --- 3 · the panel, summoned by the real hot key with Finder frontmost -------------------------

note "bringing Finder forward, then pressing ⌃⌥⌘Space"
osascript -e 'tell application "Finder" to activate' > /dev/null 2>&1
sleep 1.0
frontmost_before="$(osascript -e 'tell application "System Events" to return name of first process whose frontmost is true' 2>/dev/null)"
print "    frontmost before the hot key: $frontmost_before"

osascript -e "tell application \"System Events\" to $HOTKEY_APPLESCRIPT" > /dev/null 2>&1
hotkey_rc=$?
panel_arrived=no
for attempt in {1..20}; do
    if ax_has_window "$PANEL_TITLE"; then panel_arrived=yes; break; fi
    sleep 0.3
done
print "    keystroke EXIT=$hotkey_rc  panel present: $panel_arrived"

if [[ "$panel_arrived" == "yes" ]]; then
    await_window "$PANEL_TITLE"
    capture_front "capture-panel.png" "$PANEL_TITLE"
else
    NOTES+=("the quick-capture panel did not appear after the hot key")
fi

{
    print "FOCUS SENTINEL — the grant-free global hot key, reproduced on the shipped build"
    print "date:            $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    print "app:             $APP"
    print "bundle id:       $BUNDLE_ID"
    print
    print "1 · the app's own Accessibility approval was cleared first"
    print "    tccutil reset Accessibility $BUNDLE_ID"
    print "    EXIT=$tcc_rc $tcc_out"
    print
    print "2 · launched as its own responsible process, NOT exec'd from this shell"
    print "    open -n -a \"$APP\" --args --focus-self-check <json>"
    print "    AXIsProcessTrusted() = $untrusted_ax        (expected: False)"
    print "    RegisterEventHotKey  = $untrusted_status    (expected: 0 — noErr)"
    print "    second registration  = $untrusted_duplicate (expected: -9878 — eventHotKeyExistsErr)"
    print
    print "3 · the hot key fired with another application frontmost"
    print "    frontmost before the keystroke: $frontmost_before"
    print "    ⌃⌥⌘Space (key code 49, control+option+command)"
    print "    quick-capture panel present afterwards: $panel_arrived"
    print
    print "Why the launch method is load-bearing (probe P-56): a process exec'd from a shell"
    print "that holds Accessibility inherits that shell's TCC responsibility and reports"
    print "AXIsProcessTrusted() == true. scripts/self-check.sh launches the binary that way, so"
    print "its axIsProcessTrusted field is recorded and never asserted. This transcript is the"
    print "honest form of the claim; the gateable half — registration returning noErr — is"
    print "asserted at zero grants by the self-check."
} > "$EVIDENCE_DIR/hotkey-untrusted.txt"
CAPTURED+=("hotkey-untrusted.txt")
print "    wrote $EVIDENCE_DIR/hotkey-untrusted.txt"

press_escape
sleep 0.6

# --- 4 · a vague intent, answered constructively -----------------------------------------------

note "cockpit — a vague intent"
raise_cockpit || NOTES+=("the cockpit did not come forward")
ax '    keystroke "n" using command down' > /dev/null
sleep 0.8
type_text "proposal"
sleep 0.4
press_return
sleep 1.0
capture_front "capture-vague.png" "$COCKPIT_TITLE" \
    || NOTES+=("capture-vague.png was not captured")

# Escape abandons the refinement without committing, which is the point of the strip: the
# user's own sentence is never thrown away and never forced through either.
press_escape
sleep 0.6

# --- 5 · the priority, set for real ------------------------------------------------------------

note "cockpit — setting the priority"
raise_cockpit
ax '    keystroke "n" using command down' > /dev/null
sleep 0.8
type_text "Finish and submit the Q3 partnership proposal"
sleep 0.4
press_return
sleep 1.2
press_return
sleep 1.2
capture_front "cockpit-priority.png" "$COCKPIT_TITLE" \
    || NOTES+=("cockpit-priority.png was not captured")

# --- 6 · the context pack ------------------------------------------------------------------------
#
# The keyword and the pasted link are driven here. A **real cross-app drag** from Finder is not
# something a script can perform — it is a pointer gesture held across two processes, and P-65
# measured that even reading another app's copy through `osascript` blocks on Automation
# consent. That half is a human step, described in the summary, and the frame is re-captured
# after it. The decode path itself is unit-tested at zero grants (`ContextDropTests`).

note "context pack — a keyword and a pasted link"
if focus_field_with_placeholder "Add a keyword"; then
    type_text "partnership"
    press_return
    sleep 0.8
else
    NOTES+=("the keyword field was not found by its placeholder")
fi

osascript -e 'set the clipboard to "https://docs.example.com/document/d/abc?draft=1#top"' > /dev/null 2>&1
if focus_field_with_placeholder "Add a keyword"; then
    ax '    keystroke "v" using command down' > /dev/null
    sleep 0.4
    press_return
    sleep 0.8
else
    NOTES+=("the pasted link could not be delivered: the keyword field was not found")
fi

sleep 0.6
capture_front "context-chips.png" "$COCKPIT_TITLE" \
    || NOTES+=("context-chips.png was not captured")

# --- 7 · a file attachment and Quick Look ---------------------------------------------------------
#
# ⌘O is the File menu's "Add Files to Context…". The open panel is AppKit's own, and ⌘⇧G is the
# standard way to hand it a path, so this drives the real importer rather than reaching around it.

note "context pack — a file, then Quick Look"
QL_FIXTURE="$LOG_DIR/focus-live-quicklook.txt"
{
    print "Focus Sentinel — Quick Look fixture"
    print
    print "This file exists so the live lane has something real to preview."
} > "$QL_FIXTURE"

ax '    keystroke "o" using command down' > /dev/null
sleep 1.5
ax '    keystroke "g" using {command down, shift down}' > /dev/null
sleep 1.0
type_text "$QL_FIXTURE"
sleep 0.5
press_return
sleep 1.0
press_return
sleep 1.5

file_chip=no
raise_cockpit
if ax "    return (count of (every UI element of entire contents of window 1 whose description contains \"focus-live-quicklook\")) as text" \
    | grep -qv '^0$'; then
    file_chip=yes
fi

if [[ "$file_chip" == "yes" ]]; then
    # Space on the focused file chip is the Mac idiom, and it is the only route the app offers:
    # `QLPreviewPanel` is never driven by hand (R-22, probe P-62).
    press_tab
    press_space
    sleep 1.5
    capture_front "quicklook.png" \
        || NOTES+=("quicklook.png was not captured")
    press_escape
    sleep 0.5
else
    NOTES+=("no file chip arrived, so Quick Look was not driven: drive ⌘O by hand, focus the file chip and press Space")
fi

# --- 8 · undo, in the system's own Edit menu --------------------------------------------------------
#
# The whole of F-93's claim is that the domain journal reaches the standard Edit menu with no
# menu code of our own. The zero-grant self-check reads the item's title and enablement in
# process; this is the same fact with a menu open in front of it.

note "the Edit menu, showing the undo action name"
raise_cockpit
ax '    click menu bar item "Edit" of menu bar 1' > /dev/null
sleep 1.0
undo_title="$(ax '    return name of menu item 1 of menu 1 of menu bar item "Edit" of menu bar 1')"
print "    Edit ▸ item 1 reads: $undo_title"
capture_front "undo.png" || NOTES+=("undo.png was not captured")
press_escape
sleep 0.5
if [[ "$undo_title" != "Undo Change Priority" ]]; then
    NOTES+=("the Edit menu's first item read '$undo_title', not 'Undo Change Priority'")
fi

# --- 9 · the enlarged cockpit, when a human has raised the system Text Size ---------------------------

if [[ "${FOCUS_LIVE_TEXT_SIZE:-}" == "raised" ]]; then
    note "cockpit at the raised system text size"
    raise_cockpit
    capture_front "cockpit-accessibility.png" "$COCKPIT_TITLE" \
        || NOTES+=("cockpit-accessibility.png was not captured")
else
    NOTES+=("cockpit-accessibility.png not captured: raise System Settings → Accessibility → Display → Text size by hand, then re-run with FOCUS_LIVE_TEXT_SIZE=raised. macOS has no injectable Dynamic Type; the zero-grant equivalent is DynamicTextResilienceTests")
fi

# --- 10 · leave the machine as it was found -------------------------------------------------------------

cleanup
rm -f -- "$QL_FIXTURE"

# --- summary -----------------------------------------------------------------------------------------

print
print "=============================================================="
print "LIVE CAPTURE LANE — TCC-GATED EVIDENCE (never a gate)"
print "evidence: $EVIDENCE_DIR"
for artefact in $CAPTURED; do
    print "  captured  $artefact"
done
for expected in hotkey-untrusted.txt capture-panel.png capture-vague.png cockpit-priority.png context-chips.png quicklook.png undo.png; do
    (( ${CAPTURED[(Ie)$expected]} )) || print "  MISSING   $expected"
done
if (( ${#NOTES} )); then
    print
    print "notes:"
    for entry in $NOTES; do
        print "  · $entry"
    done
fi
print
print "Capturing is not the gate and not the point. READ the frames:"
print "  hotkey-untrusted.txt  AXIsProcessTrusted() == False, registration status 0, and the"
print "                        panel arriving anyway with Finder frontmost"
print "  capture-panel.png     the quick-capture panel, focused and ready to type, summoned by"
print "                        the real hot key while another application was frontmost"
print "  capture-vague.png     'proposal' answered with an explanation, one suggested rewrite"
print "                        built from the user's own word, and a still-enabled Set Priority"
print "  cockpit-priority.png  the priority unmistakably the largest and highest element; the"
print "                        status badge showing glyph AND label; no dashboard clutter"
print "  context-chips.png     chips for a keyword and a link, the link shown as an ORIGIN and"
print "                        never as a full URL — no path, no query, no fragment"
print "  quicklook.png         Quick Look previewing the attached file"
print "  undo.png              the Edit menu reading 'Undo Change Priority', enabled"
print
print "The human half, which no script can perform: drag a file from Finder and an app icon"
print "onto the context row, and paste a link from Safari with ⌘V. Re-capture context-chips.png"
print "afterwards. A cross-application drag is a pointer gesture held across two processes;"
print "probe P-65 measured that even reading another app's copy headlessly blocks on Automation"
print "consent. The decode path itself is unit-tested at zero grants in ContextDropTests."
print "=============================================================="
exit 0
