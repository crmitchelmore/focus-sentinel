#!/bin/zsh
# The zero-grant shell self-check.
#
#   scripts/self-check.sh <path to FocusSentinel.app>
#
# Runs the built binary with `--focus-self-check <json>` — a plain `exec`, no `osascript`,
# no `screencapture`, **no TCC grant of any kind** — and asserts over the JSON it writes.
#
# This is the T1-legal half of the shell contract. No acceptance criterion may depend on a
# permission grant, and the `osascript` route needs Accessibility on the *driving shell*, so
# the claims that matter moved inside the app: it reports its own menu bar, window style
# mask, standard-button presence and claimed key equivalents from within its own process.
#
# What it cannot see, and therefore never asserts: the Apple menu (owned by the system, not
# part of `NSApp.mainMenu`) and the View-menu items AppKit inserts lazily when a real user
# opens the menu. Those belong to the TCC-gated evidence lane.
#
# Writes the JSON to $FOCUS_EVIDENCE_DIR/selfcheck.json when that directory is set, so the
# report doubles as evidence.
#
# ## e03: three launches, not one
#
# The shell report is the first. The other two are the **relaunch-mid-session proof** (plan
# R-46): one launch seeds a session back-dated ninety minutes into a store of its own and exits,
# a second, separate launch opens that store, reconciles it and reports what came back. Two
# processes are the point — `startedAt` surviving byte-identical across them, and the uptime
# anchor's difference matching the two launches' wall-clock difference, are the only things a
# unit test *cannot* prove, because it cannot span a process boundary.
#
# Both extra launches are headless: they never come forward, never read a menu and never touch
# a window, so they cost about a second between them.
set -u

APP="${1:-}"
if [[ -z "$APP" ]]; then
    print -u2 "usage: ${0:t} <path to FocusSentinel.app>"
    exit 2
fi
if [[ ! -d "$APP" ]]; then
    print -u2 "FAIL: no app bundle at $APP"
    exit 2
fi

BINARY="$APP/Contents/MacOS/FocusSentinel"
if [[ ! -x "$BINARY" ]]; then
    print -u2 "FAIL: no executable at $BINARY"
    exit 2
fi

OUT="${FOCUS_SELFCHECK_JSON:-$(mktemp -t focus-selfcheck).json}"
rm -f -- "$OUT"

print "== $BINARY --focus-self-check $OUT"
"$BINARY" --focus-self-check "$OUT"
run_rc=$?
print "launch EXIT=$run_rc"

if (( run_rc != 0 )); then
    print -u2 "FAIL: the app exited $run_rc during its self-check"
    exit 1
fi
if [[ ! -f "$OUT" ]]; then
    print -u2 "FAIL: the app did not write $OUT"
    exit 1
fi

if [[ -n "${FOCUS_EVIDENCE_DIR:-}" ]]; then
    mkdir -p -- "$FOCUS_EVIDENCE_DIR"
    cp -- "$OUT" "$FOCUS_EVIDENCE_DIR/selfcheck.json"
    print "evidence: $FOCUS_EVIDENCE_DIR/selfcheck.json"
fi

# --- the two-launch reconciliation proof (R-46, §4.6) -----------------------------------------
#
# A store of its own, in a temporary directory that is removed on the way out however this
# script exits. It can never touch the person's own store, and a leftover from a previous run
# can never stand in for one this run failed to write.

SESSION_DIR="$(mktemp -d -t focus-session-proof)"
trap 'rm -rf -- "$SESSION_DIR"' EXIT INT TERM
SESSION_STORE="$SESSION_DIR/session.store"
SEED_JSON="$SESSION_DIR/seed.json"
RESTORE_JSON="$SESSION_DIR/restore.json"

print
print "== $BINARY --focus-session-seed $SESSION_STORE"
"$BINARY" --focus-self-check "$SEED_JSON" --focus-session-seed "$SESSION_STORE"
seed_rc=$?
print "seed EXIT=$seed_rc"
if (( seed_rc != 0 )); then
    print -u2 "FAIL: the seeding launch exited $seed_rc"
    exit 1
fi

# No sleep between the launches, deliberately. The elapsed figure the restoring launch reports
# is asserted to be within two seconds of 5 400, and every second spent waiting here is a second
# of that budget spent on nothing.
print "== $BINARY --focus-session-restore $SESSION_STORE"
"$BINARY" --focus-self-check "$RESTORE_JSON" --focus-session-restore "$SESSION_STORE"
restore_rc=$?
print "restore EXIT=$restore_rc"
if (( restore_rc != 0 )); then
    print -u2 "FAIL: the restoring launch exited $restore_rc"
    exit 1
fi

if [[ -n "${FOCUS_EVIDENCE_DIR:-}" ]]; then
    cp -- "$SEED_JSON" "$FOCUS_EVIDENCE_DIR/session-seed.json"
    cp -- "$RESTORE_JSON" "$FOCUS_EVIDENCE_DIR/session-restore.json"
    print "evidence: $FOCUS_EVIDENCE_DIR/session-seed.json, $FOCUS_EVIDENCE_DIR/session-restore.json"
fi

print
print "== assertions"
python3 - "$OUT" "$SEED_JSON" "$RESTORE_JSON" <<'PYTHON'
import json
import sys

path = sys.argv[1]
with open(path) as handle:
    report = json.load(handle)
with open(sys.argv[2]) as handle:
    seed = json.load(handle)
with open(sys.argv[3]) as handle:
    restore = json.load(handle)

failures = []


def check(condition, message, detail=None):
    if condition:
        print(f"ok   {message}")
    else:
        line = f"FAIL: {message}"
        if detail is not None:
            line += f"\n      got: {detail!r}"
        failures.append(line)
        print(line, file=sys.stderr)


CMD = 1 << 20          # NSEvent.ModifierFlags.command
SHIFT = 1 << 17        # NSEvent.ModifierFlags.shift
OPTION = 1 << 19       # NSEvent.ModifierFlags.option

menus = {menu["title"]: menu["items"] for menu in report.get("menu", [])}


def item_titles(menu_title):
    return [
        ("<separator>" if item["isSeparator"] else item["title"])
        for item in menus.get(menu_title, [])
    ]


def find(menu_title, item_title):
    for item in menus.get(menu_title, []):
        if item["title"] == item_title:
            return item
    return None


# --- identity ---------------------------------------------------------------------------

check(
    report.get("bundleIdentifier") == "com.chrismitchelmore.FocusSentinel",
    "bundle identifier is com.chrismitchelmore.FocusSentinel",
    report.get("bundleIdentifier"),
)

# --- the precondition every menu claim rests on -------------------------------------------
#
# AppKit validates a menu item by walking the **key window's** responder chain, and an
# application that is not active has no key window at all. A report written from the
# background therefore describes a menu bar nobody validated: the Edit menu's Undo item reads
# `Undo`, disabled, however many operations the journal holds. That is asserted here, first
# and by name, so a machine that will not let the app forward fails as an activation failure
# rather than as a phantom defect in the undo journal.

activation = report.get("activation") or {}
check(
    activation.get("isActive") is True,
    "the app was frontmost when its shell was read",
    activation,
)
check(
    activation.get("hasKeyWindow") is True,
    "the app had a key window when its shell was read",
    activation,
)
check(
    activation.get("cockpitIsKey") is True,
    "the cockpit — not the quick-capture panel — was the key window",
    activation,
)
print(
    f"note activation took {activation.get('waitedMilliseconds')}ms "
    f"over {activation.get('attempts')} attempt(s)"
)

# --- the menu bar -----------------------------------------------------------------------

expected_bar = ["Focus Sentinel", "File", "Edit", "View", "Window", "Help"]
check(
    report.get("menuBarTitles") == expected_bar,
    f"menu bar is exactly {expected_bar}",
    report.get("menuBarTitles"),
)

# File: the registry's four actions in registry order, then AppKit's own two. AppKit's
# un-shortcutted `Close` is a system-injected sibling, not a duplicate to delete.
expected_file = [
    "New Priority",
    "Add Files to Context…",
    "Complete Priority",
    "Start Session",
    "Pause Session",
    "Finish Session",
    "Pause Watching",
    "Close Window",
    "<separator>",
    "Close",
    "Close All",
]
check(
    item_titles("File") == expected_file,
    f"File menu is exactly {expected_file}",
    item_titles("File"),
)

CONTROL = 1 << 18


def check_shortcut(menu_title, item_title, key, mask):
    item = find(menu_title, item_title)
    check(item is not None, f"{menu_title} has a {item_title!r} item", item_titles(menu_title))
    if not item:
        return
    check(
        item["keyEquivalent"] == key and (item["modifierMask"] & 0xFFFF0000) == mask,
        f"{item_title} is bound to the expected key equivalent",
        (item["keyEquivalent"], item["modifierMask"]),
    )
    check(item["isEnabled"], f"{item_title} is enabled")
    check(item["hasAction"], f"{item_title} has an action")


# The three e02 priority commands, each with the key equivalent the registry declares.
# `\r` is Return: Complete Priority is Ctrl-Cmd-Return, deliberately not the plain Return that
# belongs to whichever field the user is actually typing in.
check_shortcut("File", "New Priority", "n", CMD)
check_shortcut("File", "Add Files to Context…", "o", CMD)
check_shortcut("File", "Complete Priority", "\r", CMD | CONTROL)

# The four e03 verbs, every one of them a Control-Command combination. `Pause Watching` was
# Shift-Command-W and is not: the key-equivalent probe below measured a plain Cmd-W reaching it
# and flipping the stored watching switch, which would have been the app taking Cmd-W away from
# the person.
check_shortcut("File", "Start Session", "s", CMD | CONTROL)
check_shortcut("File", "Pause Session", "p", CMD | CONTROL)
check_shortcut("File", "Finish Session", "f", CMD | CONTROL)
check_shortcut("File", "Pause Watching", "e", CMD | CONTROL)

close_window = find("File", "Close Window")
check(close_window is not None, "File has a Close Window item")
if close_window:
    check(
        close_window["keyEquivalent"] == "w"
        and close_window["modifierMask"] & CMD
        and not (close_window["modifierMask"] & (SHIFT | OPTION)),
        "Close Window is bound to Cmd-W",
        (close_window["keyEquivalent"], close_window["modifierMask"]),
    )
    check(close_window["isEnabled"], "Close Window is enabled")
    check(close_window["hasAction"], "Close Window has an action")

close_all = find("File", "Close All")
check(
    close_all is not None
    and close_all["keyEquivalent"] == "w"
    and close_all["modifierMask"] & OPTION,
    "AppKit's Close All is present and bound to Opt-Cmd-W",
    close_all,
)

# Help: exactly one item, and it is ours. SwiftUI's default Help item opens a help book that
# does not exist — a menu item leading nowhere is a defect, and this is where it is caught.
help_items = menus.get("Help", [])
check(len(help_items) == 1, "Help has exactly one item", item_titles("Help"))
if help_items:
    entry = help_items[0]
    check(
        entry["title"] == "Focus Sentinel Help",
        "the Help item is 'Focus Sentinel Help'",
        entry["title"],
    )
    check(
        entry["title"] != "FocusSentinel Help",
        "the Help item is not SwiftUI's default help-book item",
        entry["title"],
    )
    check(
        entry["keyEquivalent"] == "?" and entry["modifierMask"] & CMD,
        "the Help item is bound to Cmd-?",
        (entry["keyEquivalent"], entry["modifierMask"]),
    )
    check(entry["hasAction"], "the Help item has an action")

# App menu: Settings arrives from the `Settings` scene.
settings = find("Focus Sentinel", "Settings…")
check(settings is not None, "the app menu contains Settings…", item_titles("Focus Sentinel"))
if settings:
    check(
        settings["keyEquivalent"] == "," and settings["modifierMask"] & CMD,
        "Settings… is bound to Cmd-,",
        (settings["keyEquivalent"], settings["modifierMask"]),
    )

for expected in ("About Focus Sentinel", "Services", "Hide Focus Sentinel", "Quit Focus Sentinel"):
    check(
        find("Focus Sentinel", expected) is not None,
        f"the app menu contains {expected!r}",
        item_titles("Focus Sentinel"),
    )

# Window menu is entirely the system's; assert it is intact rather than customised away.
for expected in ("Minimize", "Zoom", "Bring All to Front"):
    check(
        find("Window", expected) is not None,
        f"the Window menu contains {expected!r}",
        item_titles("Window"),
    )
for scene_title in ("Focus Sentinel", "Keyboard Shortcuts"):
    check(
        find("Window", scene_title) is not None,
        f"the Window menu lists the {scene_title!r} scene",
        item_titles("Window"),
    )

# View exists. Its contents are AppKit's, inserted lazily when a real user opens the menu,
# and are therefore invisible here — that is evidence for the live lane, not a gate.
check("View" in menus, "a View menu exists")

# No menu item may lead nowhere.
for title, items in menus.items():
    for item in items:
        if item["isSeparator"] or item["hasSubmenu"]:
            continue
        check(
            item["hasAction"] or not item["isEnabled"],
            f"{title} → {item['title']!r} is enabled only if it has an action",
            item,
        )

# --- key equivalents actually claimed ----------------------------------------------------
#
# Cmd-Q is never probed: performing it terminates the app before the report can be written.

claims = report.get("keyEquivalentClaims", {})
for key in ("cmd-n", "cmd-o", "cmd-w", "cmd-comma", "cmd-question"):
    check(claims.get(key) is True, f"the menu bar claims {key}", claims.get(key))

# --- the cockpit window ------------------------------------------------------------------
#
# `fullSizeContentView` is SwiftUI's own default for a `Window` scene — the style mask reads
# 32783 — so it is never asserted absent. Standard-title-bar-ness is asserted through
# `titlebarAppearsTransparent == false` plus the three standard buttons.

window = report.get("cockpitWindow") or {}
check(bool(window), "a titled cockpit window exists")
for flag in ("titled", "closable", "miniaturizable", "resizable"):
    check(window.get(flag) is True, f"the cockpit window is {flag}", window.get(flag))
check(
    window.get("titlebarAppearsTransparent") is False,
    "the cockpit window has a standard, non-transparent title bar",
    window.get("titlebarAppearsTransparent"),
)
buttons = window.get("standardButtons") or {}
for button in ("close", "miniaturize", "zoom"):
    check(buttons.get(button) is True, f"the cockpit window has a standard {button} button", buttons)

# --- status tokens ------------------------------------------------------------------------

tokens = report.get("statusTokens", [])
check(len(tokens) == 5, "there are five status tokens", len(tokens))
check(
    len({t["symbol"] for t in tokens}) == len(tokens),
    "every status token has a distinct SF Symbol",
    [t["symbol"] for t in tokens],
)
check(
    len({t["shape"] for t in tokens}) == len(tokens),
    "every status token has a distinct shape",
    [t["shape"] for t in tokens],
)
check(
    len({t["label"] for t in tokens}) == len(tokens),
    "every status token has a distinct label",
    [t["label"] for t in tokens],
)
for token in tokens:
    check(
        token["label"] and token["label"] != token["labelKey"],
        f"{token['case']} resolves to a real label rather than echoing its key",
        token["label"],
    )

check(
    report.get("localizationCatalogsCompiled") is True,
    "the running app has compiled String Catalogs",
    report.get("localizationCatalogsCompiled"),
)

# --- e02 · the URL type (F-142) -------------------------------------------------------------
#
# Read from the *built product*, which is the only witness that can say whether the partial
# `Config/FocusSentinel-Info.plist` really merged with the generated one (R-15, P-66b).

check(
    report.get("urlSchemes") == ["focus"],
    "the product declares exactly one URL scheme, 'focus'",
    report.get("urlSchemes"),
)

# --- e02 · the global hot key (F-06) ---------------------------------------------------------
#
# Every assertion here is grant-free. `RegisterEventHotKey` is a public Carbon call whose
# return value no TCC permission influences (P-55, P-56), which is precisely why it is the
# gateable half of F-06 and `AXIsProcessTrusted` is not.

hot_key = report.get("hotKey") or {}
check(hot_key.get("available") is True, "a hot-key registrar is available", hot_key.get("available"))
check(
    hot_key.get("status") == 0,
    "registering the quick-capture hot key returned noErr",
    (hot_key.get("status"), hot_key.get("outcome")),
)
check(
    hot_key.get("registeredSpecMatches") is True,
    "the registrar holds the combination the app asked for",
    hot_key.get("registeredSpecMatches"),
)

# ⌃⌥⌘Space. Not ⌘Space, and the reason is measured rather than tasteful: P-55 registered
# Spotlight's combination successfully and quietly took the key, so the app must not be able to
# ship a system shortcut as its default.
spec = hot_key.get("spec") or {}
check(spec.get("keyCode") == 49, "the default hot key is Space (key code 49)", spec.get("keyCode"))
check(
    spec.get("modifierFlags") == (CONTROL | OPTION | CMD),
    "the default hot key carries Control, Option and Command",
    spec.get("modifierFlags"),
)
check(
    spec.get("glyphs") == "⌃⌥⌘Space",
    "the default hot key draws as ⌃⌥⌘Space",
    spec.get("glyphs"),
)

# A self-collision stays detectable, which is what makes the settings tab's conflict path real
# rather than decorative. -9878 is `eventHotKeyExistsErr` (P-55).
check(
    hot_key.get("duplicateStatus") == -9878,
    "registering the same combination twice reports eventHotKeyExistsErr (-9878)",
    (hot_key.get("duplicateStatus"), hot_key.get("duplicateOutcome")),
)

# `axIsProcessTrusted` is RECORDED, never asserted. Probe P-56: a binary `exec`'d from a shell
# that holds Accessibility inherits that shell's TCC responsibility and reports `true` — and
# this script `exec`s the binary exactly that way. Requiring `false` would fail on a granted
# developer machine for a reason that has nothing to do with the code. The honest grant-free
# proof is scripts/live-capture-drive.sh's `open -a` launch after a `tccutil reset`.
print(f"note axIsProcessTrusted = {report.get('axIsProcessTrusted')!r} (recorded, never asserted — P-56)")

# --- e02 · undo through the system Edit menu (F-93) -------------------------------------------
#
# The title is read from the item AppKit built and validated, not from the UndoManager's own
# `undoMenuItemTitle`: F-93's claim is that the domain journal reaches the standard Edit menu
# with no menu code of our own, and only the menu can witness that.

undo = report.get("undo") or {}
check(undo.get("available") is True, "the cockpit window has an undo manager", undo)
check(
    undo.get("menuItemTitle") == "Undo Change Priority",
    "the Edit menu reads 'Undo Change Priority' after one scripted mutation",
    undo.get("menuItemTitle"),
)
check(
    undo.get("enabled") is True,
    "the Edit menu's Undo item is enabled after that mutation",
    undo.get("enabled"),
)
check(
    undo.get("menuItemTitleAfterUndo") == "Undo",
    "the Edit menu reads plain 'Undo' again after taking it",
    undo.get("menuItemTitleAfterUndo"),
)
check(
    undo.get("enabledAfterUndo") is False,
    "the Edit menu's Undo item is disabled again after taking it",
    undo.get("enabledAfterUndo"),
)

# --- e02 · the quick-capture panel (F-06) -----------------------------------------------------

panel = report.get("capturePanel") or {}
check(panel.get("prebuilt") is True, "the quick-capture panel was built at launch", panel.get("prebuilt"))
check(panel.get("visibleAfterShow") is True, "showing the panel makes it visible", panel.get("visibleAfterShow"))
# 250 ms is a regression guard with two orders of magnitude of slack, not a restatement of the
# claim: P-57 measured 34 ms from the hot key to a visible, focused panel. What it catches is
# somebody moving the panel's construction into `show()`.
shown_ms = panel.get("showMilliseconds")
check(
    isinstance(shown_ms, (int, float)) and shown_ms < 250,
    "the panel is on screen in under 250 ms",
    shown_ms,
)

# --- e02 · the priority is the hero, structurally (F-02, F-147) --------------------------------

hero = report.get("priorityHero") or {}
check(
    isinstance(hero.get("pointSize"), (int, float))
    and isinstance(hero.get("largestOtherPointSize"), (int, float))
    and hero["pointSize"] > hero["largestOtherPointSize"],
    "the priority hero is larger than every other type role in the running app",
    (hero.get("pointSize"), hero.get("largestOtherRole"), hero.get("largestOtherPointSize")),
)

# --- e03 · the observer graph (F-119, F-23, F-29, F-32, F-35, F-36) ---------------------------
#
# Every assertion below is grant-free, and every one of them is about the *shipped* build
# reporting on itself in its own process. None of it needs a permission, for the app or for this
# shell, which is what makes it part of the pass/fail contract rather than evidence.

sensing = report.get("sensing") or {}

# F-119: a pause that leaves an observer attached is not a pause. The graph is attached first
# where the person had it off, so this is `n > 0 -> 0 -> n` whatever the stored switch says.
check(
    isinstance(sensing.get("liveObserverCount"), int) and sensing["liveObserverCount"] > 0,
    "the observer graph holds observers before the pause probe",
    sensing.get("liveObserverCount"),
)
check(
    sensing.get("liveObserverCountAfterPause") == 0,
    "pause() leaves zero notification observers attached",
    sensing.get("liveObserverCountAfterPause"),
)
check(
    sensing.get("liveObserverCountAfterResume") == sensing.get("liveObserverCount"),
    "resume() restores exactly the observers pause() removed",
    (sensing.get("liveObserverCount"), sensing.get("liveObserverCountAfterResume")),
)
check(
    sensing.get("audioListenerCountAfterPause") == 0,
    "pause() removes every CoreAudio property listener",
    sensing.get("audioListenerCountAfterPause"),
)
check(
    isinstance(sensing.get("redundantActivations"), int),
    "the redundant-activation counter is reported and numeric",
    sensing.get("redundantActivations"),
)

# A shortcut that quietly changes a stored setting somebody else owns is exactly what a menu bar
# can do unseen. Measured: with Pause Watching on Shift-Cmd-W, a synthesised plain Cmd-W reached
# it and flipped the switch on three consecutive runs.
check(
    report.get("settingSensingPausedAfterKeyProbes") == sensing.get("settingSensingPaused"),
    "the key-equivalent probes left the stored watching switch exactly as they found it",
    (sensing.get("settingSensingPaused"), report.get("settingSensingPausedAfterKeyProbes")),
)

# F-29 / SC-1: seven keys, and not one of them names a window.
EXPECTED_WINDOW_KEYS = [
    "kCGWindowOwnerName",
    "kCGWindowOwnerPID",
    "kCGWindowLayer",
    "kCGWindowNumber",
    "kCGWindowBounds",
    "kCGWindowIsOnscreen",
    "kCGWindowAlpha",
]
windows_read = sensing.get("windowMetadata") or {}
check(
    windows_read.get("decodedKeys") == EXPECTED_WINDOW_KEYS,
    f"the window reader decodes exactly {EXPECTED_WINDOW_KEYS}",
    windows_read.get("decodedKeys"),
)
# There is deliberately no assertion here naming the banned key. Standing condition 1 bans it
# from the **whole repository** outside a comment, this file included, and a check that wrote it
# out would fail the very lint it was restating. It is not needed either: the exact-list assertion
# above already proves the key is not decoded, and `decodedKeysAreTitleFree` proves the stronger
# property — that no decoded key names a window rather than its owning application, which would
# still hold for a future key called something else.
check(
    windows_read.get("decodedKeysAreTitleFree") is True,
    "no decoded window key names a window rather than its owning application",
    windows_read.get("decodedKeys"),
)
check(
    isinstance(windows_read.get("count"), int) and windows_read["count"] > 0,
    "the grant-free window list returned rows",
    windows_read.get("count"),
)

# F-32: `.combinedSessionState` counts a superset of the events `.hidSystemState` does, so the
# hardware figure can never be the smaller of the two at a single instant. The tolerance is for
# the one thing ordering cannot fix: a real input event landing between the two reads resets the
# hardware counter while the session figure already taken stays large. Half a second is generous
# for two adjacent syscalls and far too small to hide a swapped source, which would show up as a
# divergence of minutes (P-85 measured 21 of them).
idle = sensing.get("idle") or {}
IDLE_READ_TOLERANCE = 0.5
check(
    isinstance(idle.get("hardwareSeconds"), (int, float))
    and isinstance(idle.get("sessionSeconds"), (int, float))
    and idle["hardwareSeconds"] >= idle["sessionSeconds"] - IDLE_READ_TOLERANCE,
    "the hardware idle figure is not below the session one (the sources are not swapped)",
    (idle.get("hardwareSeconds"), idle.get("sessionSeconds")),
)
print(
    f"note idle hardware-minus-session = {idle.get('hardwareMinusSessionSeconds')} s "
    f"(threshold {idle.get('thresholdSeconds')} s)"
)

# F-35: the quorum's three inputs, recorded whatever the verdict.
presentation = sensing.get("presentation") or {}
if presentation.get("suppressed"):
    print("note the frontmost application was suppressed by the sensitivity gate")
else:
    for signal in ("frontmostWindowFillsAScreen", "presentationOptionsSayFullScreen", "menuBarHidden"):
        check(
            isinstance(presentation.get(signal), bool),
            f"the presentation quorum reports its {signal} input",
            presentation.get(signal),
        )
    check(
        presentation.get("isPresenting") is False or presentation.get("agreementCount", 0) >= 2,
        "the presentation quorum never decides on a single signal",
        presentation,
    )

# F-36, the microphone half: inputs and outputs counted separately, because an *output* device
# running is a person listening to music and never a meeting (P-96).
media = sensing.get("media") or {}
for key in ("inputDeviceCount", "outputDeviceCount"):
    check(isinstance(media.get(key), int), f"the media observer reports {key}", media.get(key))
check(
    media.get("inputDeviceCount", -1) > 0 or media.get("microphoneRunning") is False,
    "microphoneRunning is false where there is no input device to compute it from",
    media,
)

# F-36, the camera half: **pinned off on every rig, camera or not.** What is asserted is that
# the held path was never entered — not an accident of this Mac having no camera (P-97/P-104).
check(
    media.get("cameraState") == "unavailable",
    "cameraActivity is unavailable unconditionally",
    media.get("cameraState"),
)
check(
    media.get("cameraRunning") is False,
    "cameraRunning is false",
    media.get("cameraRunning"),
)
expected_reason = "noDevices" if media.get("cameraDeviceCount") == 0 else "unprovenOnThisHardware"
check(
    media.get("cameraReason") == expected_reason,
    f"the camera reason is {expected_reason!r} for {media.get('cameraDeviceCount')} device(s)",
    media.get("cameraReason"),
)
check(
    media.get("cameraListenersInstalled") == 0,
    "no CoreMediaIO listener was ever installed",
    media.get("cameraListenersInstalled"),
)
check(
    sensing.get("cameraListenersInstalledAfterPause") == 0,
    "no CoreMediaIO listener exists after a pause either",
    sensing.get("cameraListenersInstalledAfterPause"),
)

# --- e03 · the capability matrix (F-126) ------------------------------------------------------

capabilities = report.get("capabilities") or []
EXPECTED_CAPABILITIES = [
    "frontmostApplication", "windowMetadata", "idle", "systemLifecycle",
    "displayGeometry", "presentation", "microphoneActivity", "cameraActivity",
    "accessibilityWindowContext", "screenCapture", "notifications", "onDeviceModel",
]
check(
    [c.get("capability") for c in capabilities] == EXPECTED_CAPABILITIES,
    "all twelve capabilities are reported, in order",
    [c.get("capability") for c in capabilities],
)
STATES = {"available", "denied", "restricted", "unavailable", "notRequested"}
for entry in capabilities:
    check(
        entry.get("state") in STATES,
        f"{entry.get('capability')} carries one of the five declared states",
        entry.get("state"),
    )

# Nothing this epic actually uses may sit at `notRequested`: that state means "we have not asked
# yet", and in e03 the app never asks at all, so a facility it uses reporting it would mean the
# probe never ran.
by_capability = {c.get("capability"): c.get("state") for c in capabilities}
for capability in EXPECTED_CAPABILITIES[:8]:
    check(
        by_capability.get(capability) != "notRequested",
        f"{capability} is not notRequested — this epic uses it",
        by_capability.get(capability),
    )
check(
    by_capability.get("cameraActivity") == "unavailable",
    "cameraActivity is unavailable in the matrix as well as in the media report",
    by_capability.get("cameraActivity"),
)

# --- e03 · the app never triggers a permission prompt (R-33, P-95(c)) -------------------------
#
# The gateable form of the hard constraint: enumerate the owners of every on-screen window —
# grant-free — and assert that not one of them is a process macOS puts an authorisation dialog
# on the screen through, while the app is running.

check(
    report.get("authorisationSurfaces") == [],
    "no authorisation surface is on screen while the app runs",
    report.get("authorisationSurfaces"),
)
print(f"note {len(report.get('onScreenWindowOwners') or [])} on-screen window owner(s) scanned")

# --- e03 · the relaunch-mid-session proof, across two processes (F-97, R-46) ------------------

check(seed.get("mode") == "seed", "the first launch ran in seed mode", seed.get("mode"))
check(restore.get("mode") == "restore", "the second launch ran in restore mode", restore.get("mode"))
check(restore.get("restored") is True, "the second launch found the seeded session", restore)

# `startedAt` is never rewritten. Not on restore, not on resume, not ever — compared as the
# string both launches formatted, so this is byte-identical rather than nearly equal.
check(
    seed.get("startedAt") == restore.get("startedAt") and bool(seed.get("startedAt")),
    "startedAt is byte-identical across the two launches",
    (seed.get("startedAt"), restore.get("startedAt")),
)
check(
    seed.get("sessionID") == restore.get("sessionID"),
    "it is the same session in both launches",
    (seed.get("sessionID"), restore.get("sessionID")),
)

elapsed = restore.get("elapsedWallSeconds")
check(
    isinstance(elapsed, (int, float)) and abs(elapsed - 5400) <= 2.0,
    "the restored session reports ninety minutes elapsed on the wall clock",
    elapsed,
)
check(
    restore.get("phase") == "paused",
    "a session last touched ninety minutes ago comes back paused",
    restore.get("phase"),
)
check(
    restore.get("pauseCauses") == ["relaunch"],
    "it is paused for exactly one cause, and that cause is the relaunch",
    restore.get("pauseCauses"),
)
check(
    restore.get("resumeTo") == "focus",
    "resumeTo names the phase it was actually in, so one click puts the person back",
    restore.get("resumeTo"),
)
check(
    "clockAnomaly" not in (restore.get("notes") or []),
    "no clock anomaly is manufactured: wall and uptime were back-dated together",
    restore.get("notes"),
)

# The boot identity says which machine-lifetime a persisted anchor belongs to. Same boot, same
# string, byte for byte.
check(
    bool(seed.get("bootIdentity")) and seed.get("bootIdentity") == restore.get("bootIdentity"),
    "the boot identity is non-empty and identical across the two launches",
    (seed.get("bootIdentity"), restore.get("bootIdentity")),
)
check(
    seed.get("bootIdentity") == report.get("bootIdentity"),
    "the shell launch read the same boot identity as the session launches",
    (report.get("bootIdentity"), seed.get("bootIdentity")),
)

# **The one assertion a unit test cannot make.** The anchor is a real cross-process quantity
# rather than a per-process zero — which `MonotonicClock.elapsed` and `ContinuousClock.Instant`
# both are, and either of which would sail through the whole unit lane and fail right here.
uptime_delta = restore.get("uptimeSeconds", 0) - seed.get("uptimeSeconds", 0)
wall_delta = restore.get("wallSeconds", 0) - seed.get("wallSeconds", 0)
check(
    uptime_delta > 0,
    "the restoring launch reports a greater uptime than the seeding one",
    (seed.get("uptimeSeconds"), restore.get("uptimeSeconds")),
)
check(
    abs(uptime_delta - wall_delta) <= 1.0,
    "the uptime difference between the two launches matches their wall-clock difference",
    (uptime_delta, wall_delta),
)
print(f"note uptime delta {uptime_delta:.6f} s against a wall delta of {wall_delta:.6f} s")

# ------------------------------------------------------------------------------------------

print()
if failures:
    print(f"SELF-CHECK FAILED — {len(failures)} assertion(s)", file=sys.stderr)
    sys.exit(1)
print("SELF-CHECK OK")
PYTHON
rc=$?

exit $rc
