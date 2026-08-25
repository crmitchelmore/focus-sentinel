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
observe_frontmost() {
    local asn line
    asn="$("$LSAPPINFO" front 2>/dev/null)"
    [[ -n "$asn" ]] || { print -r -- ""; return 0 }
    line="$("$LSAPPINFO" info -only bundleid "$asn" 2>/dev/null)"
    # `"CFBundleIdentifier"="com.google.Chrome"` → `com.google.Chrome`
    line="${line#*=}"
    print -r -- "${line//\"/}"
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

if [[ ! -s "$OUT" ]]; then
    print -u2 "FAIL: the app wrote no nudge report at $OUT within ${SETTLE_TIMEOUT}s"
    exit 1
fi

print
print "== assertions"
python3 - "$OUT" "$FRONT_BEFORE" "$FRONT_AFTER" "$BUNDLE_ID" "${0:A}" <<'PYTHON'
import json
import sys

report_path, front_before, front_after, bundle_id, own_path = sys.argv[1:6]

with open(report_path) as handle:
    report = json.load(handle)

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
intended = panel.get("contentSize") or {}
tolerance = 1.0
for axis in ("width", "height"):
    measured = frame.get(axis)
    expected = intended.get(axis)
    check(
        isinstance(measured, (int, float))
        and isinstance(expected, (int, float))
        and abs(measured - expected) <= tolerance,
        f"the panel's {axis} is its intended {expected} (measured {measured})",
        {"frame": frame, "contentSize": intended},
    )
check(
    panel.get("presentedAtIntendedSize") is True,
    "the panel is one a person could actually read: visible AND its intended size",
    {"frame": frame, "contentSize": intended},
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
