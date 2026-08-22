#!/bin/zsh
# The live shell drive — TCC-GATED EVIDENCE, never a gate.
#
#   scripts/live-shell-drive.sh
#
# Launches the real app on this Mac, drives it with `osascript`, captures each window with
# `screencapture -l <window id>`, and leaves the frames in $FOCUS_EVIDENCE_DIR for a human —
# or the verifying agent — to **read**. Capturing is not the point; reading is.
#
# ## Why this is not a gate, and never may be
#
# Standing condition 5: no T1 acceptance criterion may depend on a TCC grant. Everything
# below needs grants held by the *driving shell* — Accessibility (to enumerate and click
# menus through System Events), Automation (to talk to System Events at all) and Screen
# Recording (to capture another process's window). Measured on this rig all three are
# present, which is exactly the trap: a criterion that passed here would fail on a machine
# where they are revoked, for a reason that has nothing to do with the code.
#
# So: when a grant is missing this script prints `LIVE-LANE SKIPPED: <grant>` and exits **0**,
# and `scripts/build-gate.sh` never invokes it. The half of the shell contract that must hold
# regardless is asserted, with zero grants, by `scripts/self-check.sh` — stage 9 of the gate.
#
# ## Standing condition 1
#
# Window *titles* here come from the Accessibility API, with the user's consent, through
# System Events. Window *ids* come from `Tools/windowid`, which reads owner name, layer,
# number and bounds and never requests `kCGWindowName`. The two are correlated by matching
# bounds — which is what lets this script know which window it is capturing without ever
# asking the window list for a name.
#
# ## Environment
#
#   FOCUS_EVIDENCE_DIR   where the artefacts land   (default .agents/evidence/e01)
#   FOCUS_DERIVED_DATA   build location             (default /tmp/focus-dd)
#   FOCUS_LOG_DIR        build log location         (default /tmp)
#   FOCUS_LIVE_TEXT_SIZE set to `raised` when the system-wide Text Size has already been
#                        increased by hand (System Settings → Accessibility → Display →
#                        Text size); only then is `main-accessibility.png` captured, because
#                        a frame named for a text size the machine is not running at would be
#                        evidence of nothing. macOS has no injectable Dynamic Type, so the
#                        zero-grant snapshot lane covers the enlarged shell by injecting
#                        `ShellTextScale.accessibilityLarge`; this frame is the live
#                        confirmation of it, and it is human-gated by construction.
set -u

REPO_ROOT="${0:A:h}/.."
cd "$REPO_ROOT" || exit 1

EVIDENCE_DIR="${FOCUS_EVIDENCE_DIR:-.agents/evidence/e01}"
DD="${FOCUS_DERIVED_DATA:-/tmp/focus-dd}"
LOG_DIR="${FOCUS_LOG_DIR:-/tmp}"
DESTINATION='platform=macOS,arch=arm64'

# Two different names for the same application, both measured rather than assumed:
#   * `CGWindowListCopyWindowInfo` reports the display name in `kCGWindowOwnerName`
#     → "Focus Sentinel"
#   * System Events addresses the process by its bundle name
#     → "FocusSentinel"
# The plan's sketch of this script used the bundle name for both; on this machine that finds
# no window at all.
WINDOW_OWNER='Focus Sentinel'
PROCESS_NAME='FocusSentinel'

APP="$DD/Build/Products/Debug/FocusSentinel.app"

# The appearance options, in `AppearancePreference.allCases` order. They are addressed by
# index rather than by title because the SwiftUI inline picker's radio buttons expose **no**
# accessibility title on macOS 26 — measured: `AXTitle`, `AXDescription`, `AXValueDescription`
# and `AXTitleUIElement` are all absent on all three. That is a finding of this lane, recorded
# here and in the run summary; until it is fixed, clicking by title is impossible and every
# selection below is verified by reading the radio button's value back.
typeset -a APPEARANCE_OPTIONS
APPEARANCE_OPTIONS=("Match System" "Light" "Dark")

mkdir -p -- "$EVIDENCE_DIR" "$LOG_DIR" || exit 1

typeset -a CAPTURED NOTES
CAPTURED=()
NOTES=()

note()  { print "== $*" }
skip()  { print "LIVE-LANE SKIPPED: $*"; exit 0 }
die()   { print -u2 "LIVE-LANE ERROR: $*"; cleanup; exit 1 }

cleanup() {
    # `pkill -x` rather than an Apple Event to the app: quitting has to work even when the app
    # is wedged, and the app itself links no Apple Events at all (standing condition 2).
    pkill -x "$PROCESS_NAME" 2>/dev/null
    return 0
}

# `screencapture` lives in /usr/sbin. Resolving it once, up front, turns "the PATH this
# script inherited was unusual" into one clear message instead of five failed captures.
SCREENCAPTURE="${commands[screencapture]:-/usr/sbin/screencapture}"
[[ -x "$SCREENCAPTURE" ]] || die "no screencapture binary at $SCREENCAPTURE"

# --- 0 · the grant preflight ---------------------------------------------------------------
#
# `windowid --grants` calls `AXIsProcessTrusted()` and `CGPreflightScreenCaptureAccess()`.
# Both are *preflight* calls: this script never puts a permission dialog in front of anybody.

note "building the window-id test driver"
swift build --package-path Tools/windowid > "$LOG_DIR/focus-live-windowid.log" 2>&1
build_rc=$?
print "windowid build EXIT=$build_rc log=$LOG_DIR/focus-live-windowid.log"
(( build_rc == 0 )) || die "could not build Tools/windowid"

# `swift run` writes its build chatter to stdout, which would contaminate the tool's own
# output, so its two halves are run separately and the built binary is invoked directly.
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

# Automation is a third grant, separate from Accessibility: sending Apple Events to System
# Events can be refused on its own, and that refusal looks like error -1743.
if ! osascript -e 'tell application "System Events" to return name of first process' > /dev/null 2>&1; then
    skip "Automation (Apple Events to System Events) not granted to the driving shell"
fi

# --- 1 · build the app --------------------------------------------------------------------

note "building the Debug app"
xcodebuild -workspace Focus.xcworkspace -scheme FocusSentinel \
    -configuration Debug -destination "$DESTINATION" -derivedDataPath "$DD" build \
    > "$LOG_DIR/focus-live-build.log" 2>&1
app_rc=$?
print "build EXIT=$app_rc log=$LOG_DIR/focus-live-build.log"
(( app_rc == 0 )) || die "the Debug build failed"
[[ -d "$APP" ]] || die "no app bundle at $APP"

# --- helpers --------------------------------------------------------------------------------
#
# A note on variable names: never `local path=…` in zsh. `path` is tied to `PATH`, so a local
# assignment to it empties the command search path for the whole call — measured here the hard
# way, as five consecutive "command not found: screencapture".

ax() {
    osascript 2>/dev/null <<AS
tell application "System Events" to tell process "$PROCESS_NAME"
$1
end tell
AS
}

# The frame of the application's frontmost window, read through the Accessibility API — the
# sanctioned geometry and title source, because the user consented to it.
ax_front_frame() {
    ax '    set theWindow to window 1
    set {x, y} to position of theWindow
    set {w, h} to size of theWindow
    return (x as text) & " " & (y as text) & " " & (w as text) & " " & (h as text)'
}

ax_front_title() {
    ax '    return title of window 1'
}

# The window id of the frontmost window. `windowid` lists an owner's on-screen windows front
# to back; the match is then confirmed against the Accessibility frame, so a re-ordered list
# can never send a capture to the wrong window.
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

    # The AX frame and the window list disagree — which happens while a window is animating
    # open. The front-most entry is used and the disagreement is reported rather than hidden.
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

# Wait for a particular window to come forward, by its Accessibility title.
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

click_menu_item() {
    local menu="$1" item="$2"
    ax "    click menu item \"$item\" of menu 1 of menu bar item \"$menu\" of menu bar 1" > /dev/null
}

open_settings() {
    click_menu_item "$PROCESS_NAME" "Settings…" || return 1
    # The Settings window is titled by its selected tab.
    await_window "General" || await_window "Privacy" || return 1
    return 0
}

select_settings_tab() {
    local tab="$1"
    ax "    click button \"$tab\" of toolbar 1 of window 1" > /dev/null || return 1
    await_window "$tab"
}

# Escape, because that is what both Settings panes declare as their cancel action — so
# closing the window exercises the declared behaviour rather than working around it. The
# close button is the fallback, so a pane that ignores Escape is reported, not fatal.
close_front_window() {
    local before after
    before="$(ax_front_title)"
    ax '    key code 53' > /dev/null
    sleep 0.6
    after="$(ax_front_title)"
    if [[ -n "$before" && "$after" == "$before" ]]; then
        print -u2 "    (Escape did not close '$before'; using the close button)"
        ax '    click button 1 of window 1' > /dev/null
        sleep 0.6
    fi
    return 0
}

# The appearance preference. Selecting it drives the real persistence path through
# `AppSettingsRecord` — which is the point: the frame that follows shows the app after a user
# choice, not after a `defaults write`.
set_appearance() {
    local wanted="$1" index value
    index=${APPEARANCE_OPTIONS[(Ie)$wanted]}
    (( index > 0 )) || { print -u2 "    (unknown appearance option '$wanted')"; return 1 }

    open_settings || { print -u2 "    (Settings did not open)"; return 1 }
    select_settings_tab "General" || print -u2 "    (could not select the General tab)"

    ax "    click radio button $index of radio group 1 of group 1 of group 1 of window 1" > /dev/null
    sleep 0.8

    value="$(ax "    return (value of radio button $index of radio group 1 of group 1 of group 1 of window 1) as text")"
    close_front_window
    sleep 0.6

    if [[ "$value" != "1" ]]; then
        print -u2 "    (appearance '$wanted' did not take: radio $index reads '$value')"
        return 1
    fi
    print "    appearance set to $wanted (radio $index)"
    return 0
}

raise_cockpit() {
    click_menu_item "Window" "Focus Sentinel"
    await_window "Focus Sentinel"
}

# --- 2 · launch ------------------------------------------------------------------------------

cleanup
sleep 0.5

note "launching $APP"
open -n "$APP" || die "could not launch the app"
settle || die "the app never presented an on-screen window"
print "    window list: $("$WINDOWID" "$WINDOW_OWNER" | tr '\n' ';')"

# --- 3 · the menu bar, as the system sees it -------------------------------------------------
#
# This is what the zero-grant self-check cannot reach: the Apple menu belongs to the system
# and is not part of `NSApp.mainMenu`, and AppKit inserts the View menu's items lazily, when a
# real user opens the menu. Both appear here.

note "enumerating the menu bar"
osascript > "$EVIDENCE_DIR/menus.txt" 2>&1 <<AS
tell application "System Events" to tell process "$PROCESS_NAME"
    set report to ""
    repeat with barItem in menu bar items of menu bar 1
        set report to report & (name of barItem) & linefeed
        try
            repeat with theItem in menu items of menu 1 of barItem
                set itemName to name of theItem
                if itemName is missing value then
                    set report to report & "    ----" & linefeed
                else
                    set cmdChar to ""
                    try
                        set cmdChar to (value of attribute "AXMenuItemCmdChar" of theItem) as text
                    end try
                    set cmdMods to ""
                    try
                        set cmdMods to (value of attribute "AXMenuItemCmdModifiers" of theItem) as text
                    end try
                    set report to report & "    " & itemName
                    if cmdChar is not "" and cmdChar is not "missing value" then
                        set report to report & "  [" & cmdChar & " mods=" & cmdMods & "]"
                    end if
                    set report to report & linefeed
                end if
            end repeat
        end try
    end repeat
    return report
end tell
AS
menus_rc=$?
print "    menus EXIT=$menus_rc -> $EVIDENCE_DIR/menus.txt"
(( menus_rc == 0 )) && CAPTURED+=("menus.txt")

# --- 4 · the cockpit, light ------------------------------------------------------------------
#
# The preference is chosen explicitly rather than inherited from whatever mode this Mac
# happens to be in, so a frame called `main-light.png` is always a frame of the light shell.

note "cockpit, light appearance"
set_appearance "Light" || NOTES+=("could not select the Light appearance")
raise_cockpit
capture_front "main-light.png" "Focus Sentinel"

# --- 5 · the Settings window, both tabs -------------------------------------------------------

note "Settings — General"
if open_settings; then
    select_settings_tab "General" || NOTES+=("could not select the General tab")
    capture_front "settings-general.png" "General"

    note "Settings — Privacy"
    select_settings_tab "Privacy" || NOTES+=("could not select the Privacy tab")
    capture_front "settings-privacy.png" "Privacy"

    close_front_window
else
    NOTES+=("the Settings… menu item did not open a window")
fi

# --- 6 · the Help destination ------------------------------------------------------------------
#
# SwiftUI's default Help item opens a help book that does not exist. This frame is the evidence
# that it was replaced by a real destination rather than merely renamed.

note "Help → Focus Sentinel Help"
if click_menu_item "Help" "Focus Sentinel Help" && await_window "Keyboard Shortcuts"; then
    capture_front "help-shortcuts.png" "Keyboard Shortcuts"
    close_front_window
else
    NOTES+=("the Help item did not open the Keyboard Shortcuts window")
fi

# --- 7 · the cockpit, dark ----------------------------------------------------------------------

note "cockpit, dark appearance"
set_appearance "Dark" || NOTES+=("could not select the Dark appearance")
raise_cockpit
capture_front "main-dark.png" "Focus Sentinel"

# --- 8 · the enlarged shell, when a human has raised the system Text Size -------------------------

if [[ "${FOCUS_LIVE_TEXT_SIZE:-}" == "raised" ]]; then
    note "cockpit at the raised system text size"
    set_appearance "Light" || NOTES+=("could not select the Light appearance")
    raise_cockpit
    capture_front "main-accessibility.png" "Focus Sentinel"
else
    NOTES+=("main-accessibility.png not captured: raise System Settings → Accessibility → Display → Text size by hand, then re-run with FOCUS_LIVE_TEXT_SIZE=raised. macOS has no injectable Dynamic Type; the zero-grant equivalent is the snapshot lane's ShellTextScale.accessibilityLarge matrix")
fi

# --- 9 · leave the app as it was found -----------------------------------------------------------

note "restoring the appearance preference to Match System"
set_appearance "Match System" || NOTES+=("could not restore the Match System appearance")

cleanup

# --- summary --------------------------------------------------------------------------------------

print
print "=============================================================="
print "LIVE LANE — TCC-GATED EVIDENCE (never a gate)"
print "evidence: $EVIDENCE_DIR"
for artefact in $CAPTURED; do
    print "  captured  $artefact"
done
for expected in menus.txt main-light.png main-dark.png settings-general.png settings-privacy.png help-shortcuts.png; do
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
print "  menus.txt             Apple · Focus Sentinel · File · Edit · View · Window · Help;"
print "                        File has Close Window ⌘W, Close and Close All and no New Window;"
print "                        Help has exactly one item and it is not the default help book;"
print "                        View shows the items AppKit inserts lazily, invisible to the self-check"
print "  main-light.png        standard title bar and traffic lights, no custom chrome, single"
print "                        column with no sidebar, status badge showing glyph AND label"
print "  main-dark.png         the same, correct in dark, with no light-mode residue"
print "  settings-general.png  standard Settings chrome, two tabs, appearance picker present"
print "  settings-privacy.png  the local-only statement and the reveal button; no empty pane"
print "  help-shortcuts.png    the shortcut reference, populated, matching menus.txt"
print "=============================================================="
exit 0
