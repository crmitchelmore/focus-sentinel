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

print
print "== assertions"
python3 - "$OUT" <<'PYTHON'
import json
import sys

path = sys.argv[1]
with open(path) as handle:
    report = json.load(handle)

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

# ------------------------------------------------------------------------------------------

print()
if failures:
    print(f"SELF-CHECK FAILED — {len(failures)} assertion(s)", file=sys.stderr)
    sys.exit(1)
print("SELF-CHECK OK")
PYTHON
rc=$?

exit $rc
