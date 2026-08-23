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
# ## Not a gate is not the same as not honest
#
# The first version of this script exited 0 whatever happened, and three of its frames were
# wrong in ways only a reader looking at the PNGs could see:
#
#   · `capture-panel.png` was a 900x704 picture of the **cockpit**. The quick-capture panel is
#     a floating `NSPanel` at layer 3, `windowid` listed only layer 0, no bounds match was
#     possible, and the helper fell back to "the front-most entry in the list" — which is the
#     main window. It printed a note on stderr and filed the frame anyway.
#   · `cockpit-priority.png` and `context-chips.png` were byte-identical pictures of the
#     "Finish this priority" **sheet**, opened by this script's own unconditional second
#     Return landing on what was then the cockpit's default button.
#   · `quicklook.png` was never produced at all, and the run still reported success.
#
# A frame that shows the wrong window is worse than a missing frame, because a reader who sees
# a file believes it. So the contract is now:
#
#   1. **Every frame is deleted before the drive starts.** A stale PNG from a previous run must
#      never be able to stand in for one this run failed to take.
#   2. **A capture is refused unless the frontmost window is the one the frame is named for**,
#      and unless its Accessibility frame matches a real window-list entry exactly. There is no
#      "use the front-most entry" fallback anywhere in this file.
#   3. **A frame's semantic precondition is checked before it is taken** — no sheet is up
#      before the cockpit frames, the expected chips are present and the link chip really shows
#      an origin before `context-chips.png`, Quick Look really opened before `quicklook.png`,
#      and the Edit menu really names the journal's own action before `undo.png`.
#   4. **A required frame that cannot be produced fails the run**: `LIVE-FRAME FAILED` on
#      stderr and a **non-zero exit**. An optional frame that cannot be produced writes an
#      explicit `<frame>.SKIPPED.txt` marker saying why. Nothing is ever silently omitted.
#
# None of that makes this a gate. It makes the lane's own output trustworthy, which is the only
# reason to run it.
#
# ## The one claim only this lane can make (probe P-56)
#
# A process `exec`'d from a shell that already holds Accessibility inherits that shell's TCC
# responsibility and reports `AXIsProcessTrusted() == true`. `self-check.sh` launches the
# binary exactly that way, so its `axIsProcessTrusted` field is **recorded and never asserted**.
# The honest grant-free proof needs the app to be its own responsible process, which is what
# `open -n -a` gives it, and it needs the app's own Accessibility approval cleared first, which
# is what `tccutil reset` does. Both happen in section 2, and the transcript is written to
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

# What the context step is supposed to put in the pack, and what the chips must therefore
# read. The link is deliberately a full URL with a path, a query and a fragment: the frame's
# whole job is to show that what was stored is the **origin** and nothing else (SC-3).
CONTEXT_KEYWORD='partnership'
CONTEXT_LINK='https://docs.example.com/document/d/abc?draft=1#top'
CONTEXT_LINK_ORIGIN='docs.example.com'

# Two strings the app draws, written here because System Events addresses controls by the words
# on them. Both come from `FocusUI`'s String Catalog: `context.pack.heading` and
# `context.keyword.prompt`.
CONTEXT_HEADING='Context'
CONTEXT_KEYWORD_PROMPT='Add a keyword'

# What Quick Look calls its own window.
QUICKLOOK_TITLE='Quick Look'

# What the Edit menu's first item must read for `undo.png` to be the frame it claims to be.
#
# `Set Priority` is the action name `PriorityStore.setPriority` registers (`undo.priority.set`),
# and ⌘N-then-a-sentence is the verb this script can actually drive. The plan's §4.6 names
# `Undo Change Priority`, which is `activate`'s name (`undo.priority.change`) and is reachable
# only through *Work on This Again* in the recent list — a button that, measured here, exposes
# no accessible title and so cannot be addressed by name. Naming the verb the drive performs is
# the honest form of the same assertion: the journal's action name reaches the system Edit menu.
UNDO_EXPECTED_TITLE='Undo Set Priority'

mkdir -p -- "$EVIDENCE_DIR" "$LOG_DIR" || exit 1

# --- the frame ledger --------------------------------------------------------------------------
#
# Required frames fail the run when they cannot be produced. Optional ones are optional for a
# stated reason — a system setting only a human can change — and leave a marker file behind
# rather than a hole.

typeset -a REQUIRED_FRAMES OPTIONAL_FRAMES
REQUIRED_FRAMES=(
    hotkey-untrusted.txt
    capture-panel.png
    capture-vague.png
    cockpit-priority.png
    context-chips.png
    quicklook.png
    undo.png
)
OPTIONAL_FRAMES=(cockpit-accessibility.png)

typeset -a CAPTURED SKIPPED FAILED NOTES
CAPTURED=()
SKIPPED=()
FAILED=()
NOTES=()

note() { print "== $*" }
skip() { print "LIVE-LANE SKIPPED: $*"; exit 0 }
die()  { print -u2 "LIVE-LANE ERROR: $*"; cleanup; exit 1 }

# A frame that should have been produced and was not. The run will exit non-zero.
fail_frame() {
    FAILED+=("$1")
    NOTES+=("$1 — $2")
    print -u2 "LIVE-FRAME FAILED: $1 — $2"
}

# A frame this machine cannot produce right now, for a reason worth writing down. The marker
# file is the point: a reader assembling the evidence set finds an explicit statement instead
# of wondering whether the frame was forgotten.
skip_frame() {
    SKIPPED+=("$1")
    NOTES+=("$1 — SKIPPED: $2")
    print "LIVE-FRAME SKIPPED: $1 — $2"
    {
        print "SKIPPED: $1"
        print "date:    $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        print
        print "$2"
    } > "$EVIDENCE_DIR/${1}.SKIPPED.txt"
}

cleanup() {
    # `pkill -x` rather than an Apple Event to the app: quitting has to work even when the app
    # is wedged, and the app itself links no Apple Events at all (standing condition 2).
    pkill -x "$PROCESS_NAME" 2>/dev/null
    return 0
}

SCREENCAPTURE="${commands[screencapture]:-/usr/sbin/screencapture}"
[[ -x "$SCREENCAPTURE" ]] || die "no screencapture binary at $SCREENCAPTURE"

# Nothing from a previous run may survive into this one. A frame the drive fails to take must
# be *absent*, not last week's picture of a different priority.
for frame in $REQUIRED_FRAMES $OPTIONAL_FRAMES; do
    rm -f -- "$EVIDENCE_DIR/$frame" "$EVIDENCE_DIR/${frame}.SKIPPED.txt"
done

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

# How many sheets are attached to the front window. `unknown` when Accessibility could not
# answer, which is treated as "not safe to capture" by every caller.
ax_sheet_count() {
    local found
    found="$(ax '    return (count of sheets of window 1) as text')"
    [[ -n "$found" ]] && print -r -- "$found" || print -r -- "unknown"
}

# Whether the front window contains a piece of static text reading exactly this. Chips draw
# their subject with `Text(verbatim:)`, so this is how the drive knows a chip really arrived —
# and, for the link, that what arrived is the *origin* rather than the whole URL.
#
# **The elements are walked by index, never with a `whose` filter.** Measured on this machine:
# `every static text of entire contents of window 1 whose …` raises
# `-1728 Can't get every text field of entire contents of window 1`, and `repeat with e in
# (entire contents of …)` yields references whose properties all read back empty. Only
# `item i of (entire contents …)` resolves. The old helpers used the two broken forms, which is
# why every context assertion in this lane reported "not found" whatever was on screen.
ax_has_static_text() {
    local wanted="$1" found
    found="$(ax "    set ec to entire contents of window 1
    repeat with i from 1 to (count of ec)
        set e to item i of ec
        try
            if (role of e) as text is \"AXStaticText\" then
                if (value of e) as text is \"$wanted\" then return \"yes\"
            end if
        end try
    end repeat
    return \"no\"")"
    [[ "$found" == "yes" ]]
}

# The window-list id of the window whose Accessibility frame is exactly `$1`.
#
# **There is no fallback, and there must never be one.** The previous version returned "the
# front-most entry in the list" when nothing matched, which is how a request for the
# quick-capture panel came back with the cockpit's id and a 900x704 picture of the main window
# was filed as `capture-panel.png`. If the frame cannot be matched, the honest answer is that
# this script does not know which window it is looking at, and the caller must fail the frame.
#
# `--include-panels` because the panel is a floating `NSPanel` at layer 3 and the default
# layer-0 listing cannot contain it (measured: layer=3 number=4629 bounds=680,241,560,121 for
# the panel against layer=0 number=4634 bounds=495,58,900,704 for the cockpit).
window_id_for_frame() {
    local frame="$1" entries entry
    [[ -n "$frame" ]] || return 1
    entries="$("$WINDOWID" "$WINDOW_OWNER" --include-panels 2>/dev/null)"
    [[ -n "$entries" ]] || return 1

    while IFS= read -r entry; do
        [[ "${entry#* }" == "$frame" ]] && { print -r -- "${entry%% *}"; return 0 }
    done <<< "$entries"
    return 1
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

# Capture the frontmost window — but only if it is the window this frame is named for, and only
# by an id that a real window-list entry matched. Anything else returns non-zero and writes no
# file at all.
capture_window() {
    local name="$1" expected_title="$2"
    local outfile="$EVIDENCE_DIR/$name" title frame id rc

    title="$(ax_front_title)"
    if [[ "$title" != "$expected_title" ]]; then
        print -u2 "    frontmost window is '$title', expected '$expected_title'"
        return 1
    fi

    frame="$(ax_front_frame)"
    if ! id="$(window_id_for_frame "$frame")"; then
        print -u2 "    no window-list entry matches the frame '$frame' of '$title'"
        return 1
    fi

    "$SCREENCAPTURE" -x -o -l "$id" "$outfile"
    rc=$?
    if (( rc != 0 )) || [[ ! -s "$outfile" ]]; then
        print -u2 "    (screencapture EXIT=$rc for $name)"
        rm -f -- "$outfile"
        return 1
    fi

    print "    captured $outfile  (window $id, '$title', frame $frame)"
    CAPTURED+=("$name")
    return 0
}

# The cockpit, with nothing modal in front of it. Every cockpit frame goes through here, so
# "the frame shows the surface it is named for" is checked once rather than hoped for four
# times.
capture_cockpit() {
    local name="$1" sheets
    sheets="$(ax_sheet_count)"
    if [[ "$sheets" != "0" ]]; then
        print -u2 "    the cockpit has $sheets sheet(s) attached; refusing to capture $name"
        return 1
    fi
    capture_window "$name" "$COCKPIT_TITLE"
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
# first time a row is added. Walked by index for the reason `ax_has_static_text` documents.
focus_field_with_placeholder() {
    local placeholder="$1" result
    result="$(ax "    set ec to entire contents of window 1
    repeat with i from 1 to (count of ec)
        set e to item i of ec
        try
            if (role of e) as text is \"AXTextField\" then
                if (value of attribute \"AXPlaceholderValue\" of e) as text is \"$placeholder\" then
                    set focused of e to true
                    return \"ok\"
                end if
            end if
        end try
    end repeat
    return \"none\"")"
    [[ "$result" == "ok" ]]
}

# Put the keyboard on the rightmost button sharing a row with the keyword field — the context
# pack's own *Add Files…* button — so that ⌘V reaches the row's `pasteDestination`.
#
# **Why not by name.** Measured on this machine: a SwiftUI button whose label is a custom view
# exposes neither `AXTitle` nor `AXDescription` to System Events. Every button in the cockpit
# reads back as an anonymous `button`, so "the button called Add Files…" is not a question the
# Accessibility API can answer here. Geometry is: the button is on the keyword field's row and
# to the right of it, and it is the last one there.
#
# **Why the row's button and not the field.** ⌘V with the keyword field focused pastes text
# *into the field*, and committing that stores the whole URL as a keyword. `pasteDestination`
# is what runs a link through `ContextDecoder`, which normalises it to a `scheme://host[:port]`
# origin and drops the path, query and fragment (SC-3) — and it only sees the keystroke when
# focus is inside the row but outside the text field. Verified live: focusing this button and
# pressing ⌘V produced the chip `docs.example.com` from
# `https://docs.example.com/document/d/abc?draft=1#top`.
focus_context_paste_target() {
    local result
    result="$(ax "    set ec to entire contents of window 1
    set fieldY to -1
    set fieldH to 0
    set fieldRight to -1
    repeat with i from 1 to (count of ec)
        set e to item i of ec
        try
            if (role of e) as text is \"AXTextField\" then
                if (value of attribute \"AXPlaceholderValue\" of e) as text is \"$CONTEXT_KEYWORD_PROMPT\" then
                    set {fx, fy} to position of e
                    set {fw, fh} to size of e
                    set fieldY to fy
                    set fieldH to fh
                    set fieldRight to fx + fw
                    exit repeat
                end if
            end if
        end try
    end repeat
    if fieldY is -1 then return \"none\"
    set bestX to -1
    set bestIndex to -1
    repeat with i from 1 to (count of ec)
        set e to item i of ec
        try
            if (role of e) as text is \"AXButton\" then
                set {btnX, btnY} to position of e
                if btnY ≥ (fieldY - fieldH) and btnY ≤ (fieldY + fieldH) and btnX > fieldRight then
                    if btnX > bestX then
                        set bestX to btnX
                        set bestIndex to i
                    end if
                end if
            end if
        end try
    end repeat
    if bestIndex is -1 then return \"none\"
    set focused of (item bestIndex of ec) to true
    return \"ok\"")"
    [[ "$result" == "ok" ]]
}

# Put the keyboard on the last previewable context chip — which is to say, on a **file** chip.
#
# File chips are the only chips that are buttons: `ContextChip` wraps its body in
# `Button(action: preview)` when the item is a file, which is what makes Space open Quick Look
# (F-95, the Mac idiom). They cannot be addressed by name for the reason above, so they are
# found structurally instead: a chip sits *above* the keyword field, and every chip's remove
# control carries the identifier `xmark.circle.fill` — so a button above the field with no
# identifier at all is a file chip and nothing else.
#
# The search is bounded at both ends — below the *Context* heading and above the keyword field
# — so that with no file attached it finds nothing rather than wandering up into the timebox
# presets and pressing Space on one of those.
focus_last_file_chip() {
    local result
    result="$(ax "    set ec to entire contents of window 1
    set headingY to -1
    set fieldY to -1
    repeat with i from 1 to (count of ec)
        set e to item i of ec
        try
            if (role of e) as text is \"AXStaticText\" and headingY is -1 then
                if (value of e) as text is \"$CONTEXT_HEADING\" then
                    set {hx, hy} to position of e
                    set headingY to hy
                end if
            end if
        end try
        try
            if (role of e) as text is \"AXTextField\" and fieldY is -1 then
                if (value of attribute \"AXPlaceholderValue\" of e) as text is \"$CONTEXT_KEYWORD_PROMPT\" then
                    set {fx, fy} to position of e
                    set fieldY to fy
                end if
            end if
        end try
    end repeat
    if headingY is -1 or fieldY is -1 then return \"none\"
    set chosen to -1
    set found to 0
    repeat with i from 1 to (count of ec)
        set e to item i of ec
        try
            if (role of e) as text is \"AXButton\" then
                set {btnX, btnY} to position of e
                set {btnW, btnH} to size of e
                -- Wholly above the keyword field, not merely starting above it. Measured on
                -- this machine the field sits at y=422 and *Add Files…* at y=421: a bare
                -- \`btnY < fieldY\` matched the row's own button, focused it, and Space then
                -- re-opened the file importer instead of previewing anything.
                if btnY > headingY and (btnY + btnH) ≤ fieldY then
                    set identifier to \"\"
                    try
                        set identifier to (value of attribute \"AXIdentifier\" of e) as text
                    end try
                    if identifier is \"\" then
                        set chosen to i
                        set found to found + 1
                    end if
                end if
            end if
        end try
    end repeat
    if chosen is -1 then return \"none\"
    set focused of (item chosen of ec) to true
    return \"ok \" & (found as text)")"

    if [[ "$result" == ok* ]]; then
        print "    file chips on the context row: ${result#ok }"
        return 0
    fi
    return 1
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
fi
print "    AXIsProcessTrusted=$untrusted_ax  hotKey.status=$untrusted_status  duplicateStatus=$untrusted_duplicate"

cleanup
sleep 0.5

note "launching the app for the driven half"
open -n -a "$APP" > "$LOG_DIR/focus-live-capture-launch.log" 2>&1 \
    || die "could not launch the app"
settle || die "the app never presented an on-screen window"
print "    window list: $("$WINDOWID" "$WINDOW_OWNER" --include-panels | tr '\n' ';')"

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
    if await_window "$PANEL_TITLE"; then
        # The title check inside `capture_window` is what makes this frame mean what it says.
        # The panel is 560x121 and the cockpit is 900x704; a frame of the wrong one is
        # obvious to a reader and was, for three runs, exactly what this file produced.
        capture_window "capture-panel.png" "$PANEL_TITLE" \
            || fail_frame "capture-panel.png" \
                "the panel was present but could not be captured by its own window id"
    else
        fail_frame "capture-panel.png" "the panel never became the frontmost window"
    fi
else
    fail_frame "capture-panel.png" "the quick-capture panel did not appear after the hot key"
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

# The transcript is only evidence if the three readings in it are readings. A file full of
# "(not read)" looks like a record and is not one.
if [[ "$untrusted_ax" == "False" && "$untrusted_status" == "0" && "$panel_arrived" == "yes" ]]; then
    CAPTURED+=("hotkey-untrusted.txt")
    print "    wrote $EVIDENCE_DIR/hotkey-untrusted.txt"
else
    fail_frame "hotkey-untrusted.txt" \
        "the untrusted reading is not the claim: AXIsProcessTrusted=$untrusted_ax status=$untrusted_status panel=$panel_arrived"
fi

press_escape
sleep 0.6

# --- 4 · a vague intent, answered constructively -----------------------------------------------

note "cockpit — a vague intent"
raise_cockpit || NOTES+=("the cockpit did not come forward")
ax '    keystroke "n" using command down' > /dev/null
sleep 0.8
type_text "proposal"
sleep 0.4
# One Return. It reveals the refinement strip rather than committing, which is the whole point
# of F-07's "explain once, commit on the next press".
press_return
sleep 1.0
capture_cockpit "capture-vague.png" \
    || fail_frame "capture-vague.png" "the refinement strip could not be captured"

# Escape abandons the refinement without committing, which is the point of the strip: the
# user's own sentence is never thrown away and never forced through either.
press_escape
sleep 0.6

# --- 5 · the priority, set for real ------------------------------------------------------------
#
# **One Return, not two.** The second press used to be unconditional here, and after the fix to
# `CockpitView` it would simply do nothing — but before it, the cockpit's Complete button was
# the window's default action, so the stray press opened the completion sheet and every frame
# taken afterwards was a picture of that sheet. Driving a surface with more keystrokes than a
# user would send is how a driver invents its own bug reports.

note "cockpit — setting the priority"
raise_cockpit
ax '    keystroke "n" using command down' > /dev/null
sleep 0.8
type_text "Finish and submit the Q3 partnership proposal"
sleep 0.4
press_return
sleep 1.5

sheets_after_capture="$(ax_sheet_count)"
if [[ "$sheets_after_capture" != "0" ]]; then
    # Loud, because this is the exact failure that made three runs' worth of frames wrong.
    fail_frame "cockpit-priority.png" \
        "committing the capture field left $sheets_after_capture sheet(s) up — a stray Return reached a default button"
    press_escape
    sleep 0.6
else
    capture_cockpit "cockpit-priority.png" \
        || fail_frame "cockpit-priority.png" "the cockpit could not be captured after the priority was set"
fi

# --- 6 · the context pack ------------------------------------------------------------------------
#
# The keyword and the pasted link are driven here. A **real cross-app drag** from Finder is not
# something a script can perform — it is a pointer gesture held across two processes, and P-65
# measured that even reading another app's copy through `osascript` blocks on Automation
# consent. That half is a human step, described in the summary, and the frame is re-captured
# after it. The decode path itself is unit-tested at zero grants (`ContextDropTests`).

note "context pack — a keyword and a pasted link"
if focus_field_with_placeholder "$CONTEXT_KEYWORD_PROMPT"; then
    type_text "$CONTEXT_KEYWORD"
    press_return
    sleep 0.8
else
    NOTES+=("the keyword field was not found by its placeholder")
fi

# The link goes to the **row's** paste destination, not into the keyword field. `addKeyword`
# would store the whole URL as a keyword; `pasteDestination` runs it through `ContextDecoder`,
# which normalises it to an origin and drops the path, query and fragment (SC-3). Focusing the
# row's own button is how the keystroke reaches the row instead of the text field.
osascript -e "set the clipboard to \"$CONTEXT_LINK\"" > /dev/null 2>&1
if focus_context_paste_target; then
    ax '    keystroke "v" using command down' > /dev/null
    sleep 1.2
else
    NOTES+=("the context row's paste target was not found, so the link could not be pasted")
fi

sleep 0.6

# The precondition, checked rather than assumed: both chips are on screen, and the link chip
# reads the origin. A frame captured without this is a picture of whatever happened to be
# there, which is what `context-chips.png` was.
missing_chips=()
ax_has_static_text "$CONTEXT_KEYWORD"      || missing_chips+=("the keyword chip '$CONTEXT_KEYWORD'")
ax_has_static_text "$CONTEXT_LINK_ORIGIN"  || missing_chips+=("the origin chip '$CONTEXT_LINK_ORIGIN'")

if ax_has_static_text "$CONTEXT_LINK"; then
    fail_frame "context-chips.png" \
        "a chip is showing the whole URL '$CONTEXT_LINK' rather than its origin — SC-3"
elif (( ${#missing_chips} )); then
    fail_frame "context-chips.png" "${(j:, and :)missing_chips} never arrived"
else
    capture_cockpit "context-chips.png" \
        || fail_frame "context-chips.png" "the chips were present but the cockpit could not be captured"
fi

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

raise_cockpit
ax '    keystroke "o" using command down' > /dev/null
sleep 2.0
importer_sheets="$(ax_sheet_count)"
print "    ⌘O put $importer_sheets sheet(s) on the cockpit"

if [[ "$importer_sheets" == "0" ]]; then
    fail_frame "quicklook.png" \
        "⌘O opened no file importer, so nothing could be attached (is a sheet already up?)"
else
    # ⌘⇧G is the standard way to hand an open panel a path, so this drives the real importer
    # rather than reaching around it. First Return dismisses the Go-to-folder sheet with the
    # file selected; second Return is the panel's own Open.
    ax '    keystroke "g" using {command down, shift down}' > /dev/null
    sleep 1.2
    type_text "$QL_FIXTURE"
    sleep 0.8
    press_return
    sleep 1.5
    press_return
    sleep 2.0

    raise_cockpit

    # A file chip cannot be verified by name: measured here, a SwiftUI `.buttonStyle(.plain)`
    # button exposes no `AXTitle` and no `AXDescription`, so the chip's own accessibility label
    # is unreadable from System Events and every button in the window reads as "button". What
    # the frame actually claims is that Space on the focused file chip previews the file — so
    # that is what is driven, and the preview window's existence is the proof the chip is there.
    if focus_last_file_chip; then
        # Focus set through the Accessibility API needs a beat to become the key view before a
        # keystroke lands on it. Without this the Space arrives while the chip is not yet
        # focused and nothing previews.
        sleep 1.0
        press_space
        sleep 2.5
        ql_title="$(ax_front_title)"
        print "    frontmost window after Space: '$ql_title'"
        if [[ "$ql_title" == "$QUICKLOOK_TITLE" ]]; then
            capture_window "quicklook.png" "$QUICKLOOK_TITLE" \
                || fail_frame "quicklook.png" "the Quick Look window could not be captured"
            press_escape
            sleep 0.8
        else
            fail_frame "quicklook.png" \
                "Space on the focused file chip opened no '$QUICKLOOK_TITLE' window (front window is '$ql_title')"
        fi
    else
        fail_frame "quicklook.png" \
            "the file importer attached no chip, so there was nothing to preview: drive ⌘O by hand, focus the file chip and press Space"
    fi
fi

# --- 8 · undo, in the system's own Edit menu --------------------------------------------------------
#
# The whole of F-93's claim is that the domain journal reaches the standard Edit menu with no
# menu code of our own. The zero-grant self-check reads the item's title and enablement in
# process; this is the same fact with a menu open in front of it.

note "the Edit menu, showing the undo action name"
raise_cockpit

# One last mutation, so the frame is about the *priority* rather than about whichever context
# chip happened to be added last. ⌘N and a sentence is the app's primary act.
ax '    keystroke "n" using command down' > /dev/null
sleep 0.8
type_text "Draft the partnership summary for review"
sleep 0.4
press_return
sleep 1.5

ax '    click menu bar item "Edit" of menu bar 1' > /dev/null
sleep 1.0
undo_title="$(ax '    return name of menu item 1 of menu 1 of menu bar item "Edit" of menu bar 1')"
print "    Edit ▸ item 1 reads: $undo_title  (expected: $UNDO_EXPECTED_TITLE)"

if [[ "$undo_title" == "$UNDO_EXPECTED_TITLE" ]]; then
    capture_window "undo.png" "$COCKPIT_TITLE" \
        || fail_frame "undo.png" "the Edit menu was open but the window could not be captured"
else
    # The frame's entire claim is the words in that menu item — that F-93's domain journal
    # reaches the system Edit menu with no menu code of our own. Capturing it anyway would file
    # a picture of a menu reading something else under a name that says otherwise. A bare
    # "Undo" here means the journal's action name never reached the menu, which is a fact about
    # the app and belongs in the run's output rather than under a green tick.
    fail_frame "undo.png" \
        "the Edit menu's first item reads '$undo_title', not '$UNDO_EXPECTED_TITLE'"
fi
press_escape
sleep 0.5

# --- 9 · the enlarged cockpit, when a human has raised the system Text Size ---------------------------

if [[ "${FOCUS_LIVE_TEXT_SIZE:-}" == "raised" ]]; then
    note "cockpit at the raised system text size"
    raise_cockpit
    capture_cockpit "cockpit-accessibility.png" \
        || fail_frame "cockpit-accessibility.png" "the enlarged cockpit could not be captured"
else
    skip_frame "cockpit-accessibility.png" \
        "the system-wide Text Size is not raised. Raise System Settings → Accessibility → Display → Text size by hand, then re-run with FOCUS_LIVE_TEXT_SIZE=raised. macOS has no injectable Dynamic Type; the zero-grant equivalent is the snapshot lane's ShellTextScale matrix plus DynamicTextResilienceTests."
fi

# --- 10 · leave the machine as it was found -------------------------------------------------------------

cleanup
rm -f -- "$QL_FIXTURE"

# --- summary -----------------------------------------------------------------------------------------
#
# A required frame that was never captured and never explicitly failed is still a failure: the
# ledger is reconciled here rather than trusted.

for expected in $REQUIRED_FRAMES; do
    (( ${CAPTURED[(Ie)$expected]} )) && continue
    (( ${FAILED[(Ie)$expected]} ))   && continue
    fail_frame "$expected" "never produced, and the drive did not say why"
done

print
print "=============================================================="
print "LIVE CAPTURE LANE — TCC-GATED EVIDENCE (never a gate)"
print "evidence: $EVIDENCE_DIR"
for artefact in $CAPTURED; do
    print "  captured  $artefact"
done
for artefact in $SKIPPED; do
    print "  SKIPPED   $artefact  (see ${artefact}.SKIPPED.txt)"
done
for artefact in $FAILED; do
    print "  FAILED    $artefact"
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
print "  capture-panel.png     the quick-capture PANEL — 560x121, titled 'Quick Capture', not"
print "                        the 900x704 cockpit — focused and ready to type, summoned by the"
print "                        real hot key while another application was frontmost"
print "  capture-vague.png     'proposal' answered with an explanation, one suggested rewrite"
print "                        built from the user's own word, and a still-enabled Set Priority"
print "  cockpit-priority.png  the priority unmistakably the largest and highest element; the"
print "                        status badge showing glyph AND label; no dashboard clutter, and"
print "                        NO sheet in front of it"
print "  context-chips.png     chips for a keyword and a link, the link shown as an ORIGIN and"
print "                        never as a full URL — no path, no query, no fragment"
print "  quicklook.png         Quick Look previewing the attached file"
print "  undo.png              the Edit menu's first item naming the journal's own action"
print "                        ('$UNDO_EXPECTED_TITLE'), enabled — a bare 'Undo' means the"
print "                        action name never reached the menu"
print
print "The human half, which no script can perform: drag a file from Finder and an app icon"
print "onto the context row. Re-capture context-chips.png afterwards. A cross-application drag"
print "is a pointer gesture held across two processes; probe P-65 measured that even reading"
print "another app's copy headlessly blocks on Automation consent. The decode path itself is"
print "unit-tested at zero grants in ContextDropTests."
print "=============================================================="

if (( ${#FAILED} )); then
    print "RESULT: FAILED — ${#FAILED} required frame(s) could not be produced honestly."
    print "This lane is not a gate (standing condition 5) and build-gate.sh never invokes it."
    print "A non-zero exit here means the evidence set is incomplete, not that the app is broken."
    exit 1
fi

print "RESULT: OK — every required frame was produced and passed its own precondition."
exit 0
