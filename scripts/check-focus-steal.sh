#!/bin/zsh
# Gate stage `focus-steal` — **the panel takes nothing** (§4.5, R-89, P-128, P-139).
#
#   scripts/check-focus-steal.sh <path to FocusSentinel.app>
#
# Launches the real built application with `open -g -a` — the posture a nudge actually fires in,
# and the one P-128 measured: a background application the person has never interacted with —
# shows the nudge panel through the self-check channel, and asserts **all four** of R-89's
# grant-free readings.
#
# ## Why four readings and not one
#
# An earlier draft of this stage asserted exactly one thing: that
# `NSWorkspace.frontmostApplication` was unchanged. P-139 measured a real focus theft that reading
# cannot see. Calling `makeKeyAndOrderFront(nil)` on this style mask:
#
#     panelIsKey            false -> TRUE
#     appKeyWindowIsNil     true  -> FALSE
#     NSApp.isActive        false -> TRUE
#     frontmost             com.mitchellh.ghostty -> com.mitchellh.ghostty   (unchanged!)
#
# A one-reading gate goes green over that, which is the exact shape of a green gate over a broken
# behaviour. So the panel is shown with `orderFrontRegardless()`, is never made key
# programmatically (lint R-96m), and four readings are asserted together:
#
#   1  NSWorkspace.frontmostApplication   unchanged   — the coarse theft a person would see
#   2  NSApp.isActive                     false       — the activation reading 1 is blind to
#   3  panel.isKeyWindow                  false       — the key window that would take the keyboard
#   4  NSApp.keyWindow == nil             true        — the same fact from the app's side
#
# Reading 1 is taken from an **independent observer process** (`lsappinfo`, a system tool that
# needs no grant of any kind), because a stage that took every reading from inside the app under
# test would be trusting the app to report on itself. Readings 2–4 can only be taken from inside
# the process, which is what the self-check channel is for.
#
# `NSApp.isActive` is still barred from being the *primary* or *sole* instrument (P-129): its job
# here is to be asserted false beside reading 1, not to stand in for it.
#
# ## What this stage deliberately does not prove
#
# That a person **typing** while the panel is on screen keeps their keystrokes. Synthesising a key
# event needs an Accessibility grant and no T1 criterion may depend on one (SC-5), so it is
# §4.9 frame 17 in the live lane, where the driver holds the grant and the app under test holds
# none. The grant-free half is gated here; the half that cannot be is read there.
#
# ## Zero grants
#
# Nothing below needs Accessibility, Screen Recording or Automation — not for the app, and not for
# this shell. `open -g -a` is LaunchServices, `lsappinfo` is a plain system query, and the report
# is written by the app into a file. Revoking every permission on this Mac leaves this stage green.
set -u

REPO_ROOT="${0:A:h}/.."
# R-168. The published-keys stage needs to know which report keys this reader really
# looked at, so the reader's python imports scripts/keyreads.py from here.
export FOCUS_SCRIPTS_DIR="${0:A:h}"
cd "$REPO_ROOT" || exit 1

APP="${1:-}"
if [[ -z "$APP" ]]; then
    print -u2 "usage: ${0:t} <path to FocusSentinel.app>"
    exit 2
fi
if [[ ! -d "$APP" ]]; then
    print -u2 "FAIL: no app bundle at $APP"
    exit 2
fi

BUNDLE_ID='com.chrismitchelmore.FocusSentinel'
PROCESS_NAME='FocusSentinel'
LSAPPINFO='/usr/bin/lsappinfo'
SETTLE_TIMEOUT="${FOCUS_FOCUS_STEAL_TIMEOUT:-45}"

OUT="${FOCUS_FOCUS_STEAL_JSON:-$(mktemp -t focus-focus-steal).json}"
rm -f -- "$OUT"

cleanup() {
    pkill -x "$PROCESS_NAME" 2>/dev/null
    return 0
}
trap 'cleanup' EXIT INT TERM

# The independent observer. `lsappinfo front` prints the front application's ASN and
# `lsappinfo info -only bundleid` turns it into a bundle identifier; neither call is
# permission-gated, and both run in **this** process rather than in the app under test.
#
# **An unreadable observer prints nothing, and the sentinel is unreadable.** The old guard checked
# only that `lsappinfo front` printed *something*, then handed whatever followed the first `=` back
# as a bundle identifier. When the front ASN resolves to no bundle id — which is what `lsappinfo`
# does for a process with no bundle, and is reproducible on demand:
#
#     $ /usr/bin/lsappinfo info -only bundleid "ASN:0x0-0xffffff:"
#     "CFBundleIdentifier"=[ NULL ]
#
# — `${line#*=}` passed `[ NULL ] ` through as if it were an identifier. It is not empty, so the
# `-z` guards below let the stage run; the app then reported its own honest reading, the two were
# compared as strings at *the app and the observer agree about who is frontmost*, and the stage
# printed a RED gate naming a focus theft that had not happened. A gate that can fail the
# application for the observer's own blindness is worse than no gate: it teaches a reader to
# discount it.
#
# So the result is validated as an identifier rather than trusted as one. A bundle identifier is a
# non-empty run of `[A-Za-z0-9._-]` and nothing else — `[ NULL ]` fails on the brackets and the
# spaces, and so does every other diagnostic shape `lsappinfo` can print. Anything that does not
# parse is reported as **no reading**, and the callers below turn no reading into a failure that
# names the observer.
observe_frontmost() {
    local asn line value
    asn="$("$LSAPPINFO" front 2>/dev/null)"
    [[ -n "$asn" ]] || { print -r -- ""; return 0 }
    line="$("$LSAPPINFO" info -only bundleid "$asn" 2>/dev/null)"
    # `"CFBundleIdentifier"="com.google.Chrome"` → `com.google.Chrome`
    [[ "$line" == *=* ]] || { print -r -- ""; return 0 }
    value="${line#*=}"
    value="${value//\"/}"
    # A bundle identifier carries no whitespace, so stripping it cannot corrupt a real one and it
    # collapses `[ NULL ] ` to `[NULL]`, which the character check then rejects outright.
    value="${value//[[:space:]]/}"
    [[ -n "$value" && "$value" != *[^A-Za-z0-9._-]* ]] || { print -r -- ""; return 0 }
    print -r -- "$value"
}

print "FOCUS-STEAL — the panel takes nothing (§4.5, R-89, P-139)"
print "app:      $APP"
print "report:   $OUT"

if [[ ! -x "$LSAPPINFO" ]]; then
    print -u2 "FAIL: no independent observer at $LSAPPINFO"
    print -u2 "      Reading 1 must come from outside the app under test; without it this stage"
    print -u2 "      would be the app reporting on itself, which is not evidence."
    exit 1
fi

# Nothing of ours may already be running: `open` hands arguments to a *new* instance only, and an
# instance left over from an earlier stage would be activated instead of launched.
cleanup
sleep 1

FRONT_BEFORE="$(observe_frontmost)"
print "observer: frontmost before = ${FRONT_BEFORE:-<none>}"

if [[ -z "$FRONT_BEFORE" ]]; then
    print -u2 "FAIL: the observer could not read a frontmost application"
    print -u2 "      lsappinfo printed no ASN, or an ASN that resolves to no bundle identifier."
    print -u2 "      Reading 1 is unavailable, so this stage cannot be green — but note that this"
    print -u2 "      names the OBSERVER, not the app: nothing here has been measured about it yet."
    exit 1
fi
if [[ "$FRONT_BEFORE" == "$BUNDLE_ID" ]]; then
    print -u2 "FAIL: $BUNDLE_ID was already frontmost before the stage began"
    print -u2 "      P-128's posture is a background application that has never been frontmost;"
    print -u2 "      starting from the front would make every reading below meaningless."
    exit 1
fi

# `open -g -a` — the launch that reproduces the posture a nudge fires in. **Not** `open -a`, which
# brings the application forward and would make this stage assert something about `open` rather
# than about the panel.
print "launching with: open -g -a"
open -g -a "$APP" --args --focus-self-check "$OUT" --focus-self-check-nudge
launch_rc=$?
print "open EXIT=$launch_rc"
if (( launch_rc != 0 )); then
    print -u2 "FAIL: open -g -a exited $launch_rc"
    exit 1
fi

# Poll rather than sleep a fixed span: the report is the signal, and a fixed delay would make this
# a race against whatever else the machine is doing.
waited=0
while (( waited < SETTLE_TIMEOUT )); do
    [[ -s "$OUT" ]] && break
    sleep 1
    (( waited += 1 ))
done
print "settled after ${waited}s"

FRONT_AFTER="$(observe_frontmost)"
print "observer: frontmost after  = ${FRONT_AFTER:-<none>}"

# **The second half of the same repair.** An observer that goes unreadable *after* the show used to
# reach the assertions below as an empty string or, before the parse was validated, as `[ NULL ] `
# — and every one of reading 1's comparisons then failed, printing "the frontmost application is
# unchanged" and "the app and the observer agree about who is frontmost" as failures of the
# application. Neither is a statement about the application when the observer has no reading to
# compare. The stage still cannot be green without reading 1; it must simply say whose fault it is.
if [[ -z "$FRONT_AFTER" ]]; then
    print -u2 "FAIL: the observer could not read a frontmost application after the show"
    print -u2 "      It read '$FRONT_BEFORE' before. Reading 1 needs both, so this stage fails —"
    print -u2 "      but it is the OBSERVER that failed. Readings 2, 3 and 4 are in $OUT and are"
    print -u2 "      taken in-process; nothing here says the panel took anything."
    exit 1
fi

if [[ ! -s "$OUT" ]]; then
    print -u2 "FAIL: the app wrote no nudge report at $OUT within ${SETTLE_TIMEOUT}s"
    exit 1
fi

print
print "== assertions"
python3 - "$OUT" "$FRONT_BEFORE" "$FRONT_AFTER" "$BUNDLE_ID" "${0:A}" <<'PYTHON'
import json
import os
import sys

# R-168. Every dictionary the readers below fetch from is a recording one, so the
# `published-keys` stage can fail on a fact this reader never looked at. See scripts/keyreads.py.
sys.path.insert(0, os.environ["FOCUS_SCRIPTS_DIR"])
import keyreads

report_path, front_before, front_after, bundle_id, own_path = sys.argv[1:6]

with open(report_path) as handle:
    # The nudge-only launch writes the full report's `nudge` block at the top level and
    # nothing else, so its reads are recorded under that prefix — which is where the
    # published-keys stage looks for them. It pins the equivalence rather than assuming it.
    report = keyreads.record(json.load(handle), "nudge")

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


check(report.get("mode") == "nudge", "the app ran its nudge-only self-check", report.get("mode"))

panel = report.get("panel") or {}
before = panel.get("readingsBeforeShow") or {}
after = panel.get("readingsAfterShow") or {}

# The readings are about something: a panel that never appeared takes nothing trivially.
check(panel.get("wasVisible") is True, "the nudge panel really appeared", panel.get("wasVisible"))
check(
    before.get("panelIsVisible") is False,
    "the panel was not already on screen before the show",
    before.get("panelIsVisible"),
)

# --- reading 1 · from the independent observer ----------------------------------------------
#
# Two forms of the same fact, and both are asserted. The observer's is the one that matters —
# it is taken outside the app under test — and the app's own reading is compared against it so a
# disagreement between the two is itself a failure.
check(
    front_before == front_after,
    f"reading 1 (observer): the frontmost application is unchanged ({front_before})",
    (front_before, front_after),
)
check(
    front_after != bundle_id,
    "reading 1 (observer): the app under test never came forward",
    front_after,
)
# Asked before the comparison, because `nil == nil` is true and two readings neither of which
# was taken are not evidence that the front did not move (focus-2vi).
check(
    before.get("frontmostWasRead") is True and after.get("frontmostWasRead") is True,
    "reading 1 (in-process) was TAKEN at both ends — nil frontmost is NOT TAKEN",
    (before.get("frontmostBundleIdentifier"), after.get("frontmostBundleIdentifier")),
)
check(
    before.get("frontmostBundleIdentifier") == after.get("frontmostBundleIdentifier"),
    "reading 1 (in-process): the frontmost reading is byte-identical across the show",
    (before.get("frontmostBundleIdentifier"), after.get("frontmostBundleIdentifier")),
)
check(
    after.get("frontmostBundleIdentifier") == front_after,
    "reading 1: the app and the observer agree about who is frontmost",
    (after.get("frontmostBundleIdentifier"), front_after),
)

# --- readings 2, 3 and 4 · absolute, because this launch was never frontmost -------------------
#
# This is where `focus-steal` differs from `selfcheck-debug`. That stage activates the application
# on purpose — AppKit validates a menu item by walking the key window's responder chain, and a
# background application has no key window at all — so it can only assert these three as a delta.
# `open -g -a` gives this stage the posture in which the absolute form is the honest one.
check(
    after.get("applicationIsActive") is False,
    "reading 2: NSApp.isActive is false after the panel is shown",
    after.get("applicationIsActive"),
)
check(
    after.get("panelIsKey") is False,
    "reading 3: the panel is not the key window",
    after.get("panelIsKey"),
)
check(
    after.get("applicationKeyWindowIsNil") is True,
    "reading 4: the application has no key window at all",
    after.get("applicationKeyWindowIsNil"),
)
check(
    panel.get("tookNothing") is True,
    "all four readings hold together (FocusReadings.tookNothing)",
    (before, after),
)

# The six properties of R-89, on the real window object the application actually showed.
properties = panel.get("properties") or {}
check(
    panel.get("propertiesAreCorrect") is True,
    "the panel is non-activating, key-capable, never main, and never hides on deactivate",
    properties,
)
check(
    properties.get("isNonActivating") is True,
    "the style mask carries .nonactivatingPanel",
    properties.get("isNonActivating"),
)
check(
    properties.get("canBecomeMain") is False,
    "the panel can never become the application's main window",
    properties.get("canBecomeMain"),
)
check(
    panel.get("hiddenAfter") is True,
    "the panel was put away again, so this stage leaves no window on the screen",
    panel.get("hiddenAfter"),
)

# --- it SHOWS something, and not only TAKES nothing (focus-x7d) ---------------------------------
#
# Every assertion above is about what the panel did not do. This stage had no assertion at all
# about what it did — and it showed an EMPTY panel, so it proved with great rigour that a window
# with nothing in it takes nothing. Meanwhile the panel a person meets, with the real question in
# it, grew to 380 x 2212 on a 1920 x 1080 display: on screen a blank white slab, while
# `screencapture -l` read the backing store and photographed the question perfectly.
#
# The self-check now puts the real question in the panel, shows it, and lets the run loop turn
# before reading the frame — the turn is the assertion, because the window is exactly the right
# size until it happens. Zero grants: a window's own frame needs no permission to read.
frame = panel.get("frame") or {}
measured = panel.get("contentSize") or {}
tolerance = 1.0

# The WIDTH is a commitment and is asserted against the constant.
width = frame.get("width")
committed = panel.get("contentWidth")
check(
    isinstance(width, (int, float))
    and isinstance(committed, (int, float))
    and abs(width - committed) <= tolerance,
    f"the panel is the committed {committed} points wide (measured {width})",
    {"frame": frame, "contentWidth": committed},
)

# The HEIGHT is measured from the content, so the assertion is a bound rather than an equality:
# a constant here is exactly what shipped the clipped panel, in which content needing 237 to 404
# points was laid into 190 and three and a half of six actions were drawn.
height = frame.get("height")
ceiling = panel.get("maximumContentHeight")
check(
    isinstance(height, (int, float)) and height > 0,
    f"the panel has a height at all (measured {height})",
    {"frame": frame},
)
check(
    isinstance(height, (int, float))
    and isinstance(ceiling, (int, float))
    and height <= ceiling + tolerance,
    f"the panel is within the {ceiling}-point ceiling (measured {height})",
    {"frame": frame, "maximumContentHeight": ceiling},
)
check(
    isinstance(height, (int, float))
    and isinstance(measured.get("height"), (int, float))
    and abs(height - measured["height"]) <= tolerance,
    "the window and the content it was sized for are the same height",
    {"frame": frame, "contentSize": measured},
)

# --- and the assertion that replaced "the frame equals a constant" -----------------------------
#
# A size comparison passed a panel at y = -1186 (off screen as well as oversized) and passed a
# panel whose Pause and Change priority rows were below the clip. The only claim worth making
# about a decision surface is that every action it offers can be clicked: on screen, on a
# display, inside the content the person can see. Both instruments are asserted — the geometric
# reading and a real AppKit hit test at the centre of each action.
offered = panel.get("offeredActions") or []
check(
    len(offered) > 0,
    f"the panel is offering something, so the reading is about actual buttons ({offered})",
    offered,
)
check(
    panel.get("everyActionIsReachable") is True,
    "every action the panel offers is on a screen and inside the panel a person can see",
    panel.get("decisionSurface"),
)
check(
    panel.get("hitTestsEveryAction") is True,
    "a click at the centre of every offered action lands on the panel",
    panel.get("decisionSurface"),
)
surface_reading = panel.get("decisionSurface") or {}
check(
    surface_reading.get("isWhollyOnAScreen") is True,
    "the panel is wholly inside a display's visible frame (the y = -1186 case)",
    surface_reading,
)
check(
    surface_reading.get("unreportedActions") == []
    and surface_reading.get("unreachableActions") == [],
    "no offered action is missing from the layout or out of reach in it",
    surface_reading,
)

# --- the OTHER surface that draws these actions (focus-5yu) -------------------------------------
#
# Every assertion above is about the panel. The popover draws the SAME AccusationPanelView and
# the SAME QueryPanelView, it is where `SurfaceRouter` sends every rung under Reduce Motion,
# "Interrupt me less", the Silent-and-visual deck or a live microphone — and this report carried
# nothing at all about it. Measured before the repair, on a 1920 x 1080 display: the real popover
# was 346 x 855 with a 21-character priority and 346 x 3127 with a long one, both placed as
# though they were about 340 points tall, so most of each stood above the top of the screen.
#
# What is read here is the shipping layout function, on the shipping view, for the plainest and
# the fullest content this surface can hold at a priority far longer than any interface expects.
# It is not an open popover: the popover opens when a person clicks the status item, and a survey
# that clicked it would be reporting a click nobody made.
popover = report.get("popover") or {}
popover_width = popover.get("committedWidth")
check(
    isinstance(popover_width, (int, float)) and popover_width > 0,
    f"the popover commits to a width at all ({popover_width})",
    popover,
)
popover_ceiling = popover.get("maximumContentHeight")
for state in ("empty", "fullest"):
    measured_popover = popover.get(state) or {}
    # **The comparison is taken here, from the two numbers** (focus-bkf). This row read the
    # binary's own `isTheCommittedWidth`, so a layout function that had stopped honouring its
    # commitment could go on reporting that it had and this stage would believe it. The
    # arithmetic below is the one the panel's width row does at :337-345; the published flag is
    # then asserted to AGREE with it, which reads the binary's comparison without trusting it.
    state_width = measured_popover.get("width")
    is_committed = (
        isinstance(state_width, (int, float))
        and isinstance(popover_width, (int, float))
        and abs(state_width - popover_width) <= tolerance
    )
    check(
        is_committed,
        f"the {state} popover is the committed {popover_width} points wide "
        f"(measured {state_width})",
        measured_popover,
    )
    check(
        measured_popover.get("isTheCommittedWidth") is is_committed,
        f"the {state} popover's own width verdict agrees with the width it reported",
        (measured_popover.get("isTheCommittedWidth"), state_width, popover_width),
    )
    popover_height = measured_popover.get("height")
    check(
        isinstance(popover_height, (int, float)) and popover_height > 0,
        f"the {state} popover has a measured height at all ({popover_height})",
        measured_popover,
    )
    check(
        isinstance(popover_height, (int, float))
        and isinstance(popover_ceiling, (int, float))
        and popover_height <= popover_ceiling + tolerance,
        f"the {state} popover is within the {popover_ceiling}-point ceiling "
        f"(measured {popover_height})",
        {"popover": measured_popover, "maximumContentHeight": popover_ceiling},
    )

# The two contents are not the same picture: a height that ignored its content would satisfy
# every bound above and would be the constant 380 x 190 the panel was clipped into.
check(
    isinstance((popover.get("empty") or {}).get("height"), (int, float))
    and isinstance((popover.get("fullest") or {}).get("height"), (int, float))
    and popover["fullest"]["height"] > popover["empty"]["height"],
    "the fullest popover is taller than the plainest one, so the height is a measurement",
    {"empty": popover.get("empty"), "fullest": popover.get("fullest")},
)

# --- SC-5, restated here because this stage launches the app -----------------------------------
check(
    report.get("requestAuthorizationCallCount") == 0,
    "the launch asked for no notification authorisation",
    report.get("requestAuthorizationCallCount"),
)

# --- the stage checks its own assertion path ----------------------------------------------------
#
# A stage that quietly lost the frontmost check and kept only the in-process readings would be
# trusting the app under test to report on itself — and it would still print a page of green
# lines. So the script greps ITSELF for the observer's reading before declaring a pass.
with open(own_path) as handle:
    own_source = handle.read()
for fragment in ("lsappinfo front", "observe_frontmost", "reading 1 (observer)"):
    check(
        fragment in own_source,
        f"this stage still performs reading 1 from an independent observer ({fragment!r})",
    )

print()
if failures:
    print(f"FOCUS-STEAL FAILED — {len(failures)} assertion(s)", file=sys.stderr)
    sys.exit(1)
print("FOCUS-STEAL OK — the panel was shown and took nothing on all four readings")
PYTHON
rc=$?

exit $rc
