#!/bin/zsh
# The live handoff drive — TCC-GATED EVIDENCE, never a gate.
#
#   scripts/live-handoff-drive.sh
#
# Registers the built app with LaunchServices, opens `focus://start?task=…` against it, and
# captures the confirmation sheet — with the previous priority still in the store behind it.
# Then it puts the machine back exactly as it found it.
#
# ## Why this is not a gate, and never may be — two independent reasons
#
# 1. **It needs grants.** Driving and capturing another process's window needs Accessibility,
#    Automation and Screen Recording on the *driving shell*. Standing condition 5 forbids any
#    acceptance criterion that depends on a TCC grant, so a missing grant here prints
#    `LIVE-LANE SKIPPED: <grant>` and exits **0**.
#
# 2. **It mutates the user's LaunchServices database.** Probe P-59, measured: an app under
#    `/private/tmp` is recorded by `lsregister` with `bundle flags: in-temp-dir` and
#    `NSWorkspace.urlsForApplications(toOpen:)` resolves **no** handler for `focus:`. Copied to
#    `~/Applications` and re-registered, it resolves immediately and exclusively. So the only
#    way to drive the scheme for real is to put a copy somewhere permanent — which is a change
#    to the machine, and a gate step may not make one.
#
# The zero-grant half of the same contract is asserted by the gate: `scripts/self-check.sh`
# reads `CFBundleURLTypes` out of the built product's merged `Info.plist` and requires exactly
# `["focus"]`, `scripts/build-gate.sh`'s packaging stage proves the merge is real on both
# configurations, and `HandoffRequestTests` runs the whole hostile corpus through the parser as
# a pure function and asserts the store is byte-identical afterwards.
#
# ## The copy is removed on exit, including on failure
#
# A `trap` on EXIT, INT and TERM unregisters the copy with `lsregister -u` and deletes it. That
# is not politeness: leaving a stale registration behind means the user's `focus://` links point
# at a directory this script deleted, or worse, at a build that is months old. If the copy
# cannot be removed the summary says so in the loudest terms it has.
#
# ## Environment
#
#   FOCUS_EVIDENCE_DIR   where the artefacts land   (default .agents/evidence/e02)
#   FOCUS_DERIVED_DATA   build location             (default /tmp/focus-dd)
#   FOCUS_LOG_DIR        log location               (default /tmp)
set -u

REPO_ROOT="${0:A:h}/.."
cd "$REPO_ROOT" || exit 1

EVIDENCE_DIR="${FOCUS_EVIDENCE_DIR:-.agents/evidence/e02}"
DD="${FOCUS_DERIVED_DATA:-/tmp/focus-dd}"
LOG_DIR="${FOCUS_LOG_DIR:-/tmp}"
DESTINATION='platform=macOS,arch=arm64'

WINDOW_OWNER='Focus Sentinel'
PROCESS_NAME='FocusSentinel'
COCKPIT_TITLE='Focus Sentinel'

APP="$DD/Build/Products/Debug/FocusSentinel.app"

# The copy this script makes, and the only thing outside $LOG_DIR it ever writes. Named for the
# lane so that a copy found here after a crash is unmistakably this script's litter and not an
# installation the user made.
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/FocusSentinel-live-handoff.app"

LSREGISTER='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'

# The handoff URL. Deliberately carries an unknown query item so the confirm sheet has a flag to
# disclose: the frame is worth more when it shows the disclosure than when it shows the tidy case.
HANDOFF_URL='focus://start?task=Draft%20the%20migration%20note%20for%20the%20storage%20change&doneWhen=The%20note%20is%20in%20the%20shared%20folder&project=storage'

# The priority set before the handoff arrives, so the sheet has a "working on now" side and the
# store has something the handoff must not be able to take.
EXISTING_PRIORITY='Finish and submit the Q3 partnership proposal'

mkdir -p -- "$EVIDENCE_DIR" "$LOG_DIR" || exit 1

typeset -a CAPTURED NOTES
CAPTURED=()
NOTES=()

note() { print "== $*" }

cleanup_app() {
    pkill -x "$PROCESS_NAME" 2>/dev/null
    return 0
}

# The whole reason this lane is not a gate step, undone. Registered as a trap before the copy is
# ever made, so an interrupt between `cp` and `lsregister` still cleans up.
REMOVED_CLEANLY=unattempted
remove_installed_copy() {
    [[ -e "$INSTALLED_APP" ]] || { REMOVED_CLEANLY=nothing-to-remove; return 0 }
    cleanup_app
    if [[ -x "$LSREGISTER" ]]; then
        "$LSREGISTER" -u "$INSTALLED_APP" > "$LOG_DIR/focus-live-handoff-unregister.log" 2>&1
    fi
    rm -rf -- "$INSTALLED_APP"
    if [[ -e "$INSTALLED_APP" ]]; then
        REMOVED_CLEANLY=no
        print -u2 "LIVE-LANE ERROR: could not remove $INSTALLED_APP — delete it by hand"
        return 1
    fi
    # Re-scan the directory so LaunchServices forgets the record rather than keeping a claim on
    # a path that no longer exists.
    [[ -x "$LSREGISTER" ]] && \
        "$LSREGISTER" -f -R -domain local -domain system -domain user "$INSTALL_DIR" \
            >> "$LOG_DIR/focus-live-handoff-unregister.log" 2>&1
    REMOVED_CLEANLY=yes
    return 0
}

on_exit() {
    cleanup_app
    remove_installed_copy
}
trap on_exit EXIT INT TERM

skip() { print "LIVE-LANE SKIPPED: $*"; exit 0 }
die()  { print -u2 "LIVE-LANE ERROR: $*"; exit 1 }

SCREENCAPTURE="${commands[screencapture]:-/usr/sbin/screencapture}"
[[ -x "$SCREENCAPTURE" ]] || die "no screencapture binary at $SCREENCAPTURE"

# --- 0 · the grant preflight -----------------------------------------------------------------

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

[[ -x "$LSREGISTER" ]] || skip "no lsregister at $LSREGISTER"

# --- 1 · build ---------------------------------------------------------------------------------

note "building the Debug app"
xcodebuild -workspace Focus.xcworkspace -scheme FocusSentinel \
    -configuration Debug -destination "$DESTINATION" -derivedDataPath "$DD" build \
    > "$LOG_DIR/focus-live-handoff-build.log" 2>&1
app_rc=$?
print "build EXIT=$app_rc log=$LOG_DIR/focus-live-handoff-build.log"
(( app_rc == 0 )) || die "the Debug build failed"
[[ -d "$APP" ]] || die "no app bundle at $APP"

# --- helpers -------------------------------------------------------------------------------------

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

ax_front_title() { ax '    return title of window 1' }

# Whether the frontmost window currently presents a sheet. The handoff surface is a sheet on the
# cockpit window, so this — not a title — is how the lane knows it arrived.
ax_has_sheet() {
    local found
    found="$(ax '    return (count of sheets of window 1) as text')"
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
    local name="$1" id title outfile="$EVIDENCE_DIR/$1"
    title="$(ax_front_title)"
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

type_text()    { ax "    keystroke \"${1//\"/\\\"}\"" > /dev/null }
press_return() { ax '    key code 36' > /dev/null }
press_escape() { ax '    key code 53' > /dev/null }

# --- 2 · install and register the copy -------------------------------------------------------------

note "copying the product to $INSTALLED_APP"
cleanup_app
sleep 0.5
mkdir -p -- "$INSTALL_DIR" || die "could not create $INSTALL_DIR"
rm -rf -- "$INSTALLED_APP"
cp -R -- "$APP" "$INSTALLED_APP" || die "could not copy the product to $INSTALLED_APP"

note "registering it with LaunchServices"
"$LSREGISTER" -f -R "$INSTALLED_APP" > "$LOG_DIR/focus-live-handoff-register.log" 2>&1
register_rc=$?
print "    lsregister EXIT=$register_rc log=$LOG_DIR/focus-live-handoff-register.log"

# Resolution is read back rather than assumed. P-59: a bundle under /tmp registers *and*
# resolves to nothing, so "lsregister exited 0" is not evidence that the scheme is bound.
handler=""
for attempt in {1..20}; do
    handler="$(osascript 2>/dev/null <<'AS'
use framework "AppKit"
use framework "Foundation"
use scripting additions

set theURL to current application's NSURL's URLWithString:"focus://start"
set handlers to (current application's NSWorkspace's sharedWorkspace()'s ¬
    URLsForApplicationsToOpenURL:theURL)
if handlers is missing value then return ""
set report to ""
repeat with candidate in handlers
    set report to report & ((candidate's |path|()) as text) & linefeed
end repeat
return report
AS
)"
    [[ -n "$handler" ]] && break
    sleep 0.5
done
print "    focus: resolves to:"
print -r -- "${handler:-    (nothing)}" | sed 's/^/      /'
if [[ "$handler" != *"FocusSentinel-live-handoff.app"* ]]; then
    NOTES+=("LaunchServices did not resolve focus: to the registered copy; the frame below may have been produced by another build")
fi

# --- 3 · a priority to defend ------------------------------------------------------------------------

note "launching the registered copy and setting a priority"
open -n -a "$INSTALLED_APP" > "$LOG_DIR/focus-live-handoff-launch.log" 2>&1 \
    || die "could not launch $INSTALLED_APP"
settle || die "the app never presented an on-screen window"
await_window "$COCKPIT_TITLE"

ax '    keystroke "n" using command down' > /dev/null
sleep 0.8
type_text "$EXISTING_PRIORITY"
sleep 0.4
press_return
sleep 1.2
press_return
sleep 1.2
before_hero="$(ax '    return value of static text 1 of scroll area 1 of group 1 of window 1')"
print "    the cockpit now reads: ${before_hero:-(could not read the hero)}"

# --- 4 · the handoff arrives -------------------------------------------------------------------------

note "open '$HANDOFF_URL'"
open "$HANDOFF_URL" > "$LOG_DIR/focus-live-handoff-open.log" 2>&1
open_rc=$?
print "    open EXIT=$open_rc"

sheet_arrived=no
for attempt in {1..20}; do
    if ax_has_sheet; then sheet_arrived=yes; break; fi
    sleep 0.4
done
print "    confirmation sheet present: $sheet_arrived"

if [[ "$sheet_arrived" == "yes" ]]; then
    sleep 0.6
    capture_front "handoff-confirm.png" || NOTES+=("handoff-confirm.png was not captured")
else
    NOTES+=("no confirmation sheet appeared after the focus:// open")
fi

# --- 5 · the binding condition, read rather than asserted ------------------------------------------------
#
# F-142's binding condition is that external input can never replace the priority without a
# person pressing the button. Escape cancels; what the cockpit says afterwards is the evidence.

press_escape
sleep 1.0
after_hero="$(ax '    return value of static text 1 of scroll area 1 of group 1 of window 1')"
print "    after cancelling, the cockpit reads: ${after_hero:-(could not read the hero)}"
if [[ -n "$before_hero" && "$after_hero" != "$before_hero" ]]; then
    NOTES+=("the priority CHANGED across a cancelled handoff: '$before_hero' -> '$after_hero'")
fi

{
    print "FOCUS SENTINEL — focus:// handoff, driven against a registered copy"
    print "date:          $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    print "source:        $APP"
    print "registered as: $INSTALLED_APP"
    print
    print "url:           $HANDOFF_URL"
    print "open EXIT:     $open_rc"
    print "sheet present: $sheet_arrived"
    print
    print "priority before the handoff:  ${before_hero:-(unread)}"
    print "priority after cancelling it: ${after_hero:-(unread)}"
    print
    print "focus: resolved to:"
    print -r -- "${handler:-(nothing)}"
    print
    print "Probe P-59: an app under /private/tmp registers with 'bundle flags: in-temp-dir' and"
    print "resolves no handler at all, which is why this lane copies the product to ~/Applications"
    print "first — and why it is evidence rather than a gate step, since that copy is a change to"
    print "the user's machine. The copy is unregistered and deleted on exit, including on failure."
} > "$EVIDENCE_DIR/handoff-transcript.txt"
CAPTURED+=("handoff-transcript.txt")
print "    wrote $EVIDENCE_DIR/handoff-transcript.txt"

# --- 6 · leave the machine as it was found -----------------------------------------------------------------

note "removing the registered copy"
cleanup_app
remove_installed_copy
trap - EXIT INT TERM

# --- summary ------------------------------------------------------------------------------------------------

print
print "=============================================================="
print "LIVE HANDOFF LANE — TCC-GATED EVIDENCE (never a gate)"
print "evidence: $EVIDENCE_DIR"
for artefact in $CAPTURED; do
    print "  captured  $artefact"
done
for expected in handoff-confirm.png handoff-transcript.txt; do
    (( ${CAPTURED[(Ie)$expected]} )) || print "  MISSING   $expected"
done
print
print "installed copy: $INSTALLED_APP"
print "removed:        $REMOVED_CLEANLY"
if [[ "$REMOVED_CLEANLY" != "yes" && "$REMOVED_CLEANLY" != "nothing-to-remove" ]]; then
    print
    print "  *** THE MACHINE WAS NOT LEFT AS IT WAS FOUND ***"
    print "  Delete $INSTALLED_APP by hand and re-run:"
    print "    $LSREGISTER -f -R -domain local -domain system -domain user $INSTALL_DIR"
fi
if (( ${#NOTES} )); then
    print
    print "notes:"
    for entry in $NOTES; do
        print "  · $entry"
    done
fi
print
print "Capturing is not the gate and not the point. READ the frame:"
print "  handoff-confirm.png   the confirmation sheet showing the CURRENT priority beside the"
print "                        incoming one, every flag the parser raised, and exactly two"
print "                        buttons — Keep Mine (the default) and Replace Priority. The"
print "                        cockpit behind it must still be showing the old priority: nothing"
print "                        outside the app may change what you are working on without a"
print "                        person pressing the button."
print "=============================================================="
exit 0
