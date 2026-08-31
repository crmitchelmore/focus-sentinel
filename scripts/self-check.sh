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
# ## e04: the third leg of the three-way engine agreement (plan R-75.4)
#
# The unit lane asserts `EngineStamp.current.cacheKey` and `RelevancePolicy.digest` of the
# **test process**; gate stage 7d asserts the same two literals of the **evaluation report**;
# and this script asserts them of the **running application**, on both configurations. Three
# legs, one set of committed literals — and the literals are *read out of the one place they
# are written down* rather than restated here, because a third copy of a string is a third
# thing to keep in sync by hand.
set -u

REPO_ROOT="${0:A:h}/.."

# The value of `static let <name>` in a committed source file, with Swift's digit separators
# and quotes stripped. A missing literal is an empty string, and the assertion below fails on
# it by name rather than passing vacuously.
committed_literal() {
    local file="$1" name="$2" line
    line=$(grep -E "static let ${name}\b" "$REPO_ROOT/$file" 2>/dev/null | head -1)
    [[ -n "$line" ]] || return 0
    print -r -- "${${line#*= }//[\"_ ]/}"
}

COMMITTED_STAMP=$(committed_literal \
    "Packages/FocusCore/Tests/FocusCoreTests/EngineStampTests.swift" \
    "committedRuntimeCacheKey")
COMMITTED_DIGEST=$(committed_literal \
    "Packages/FocusCore/Tests/FocusCoreTests/RelevancePolicyTests.swift" \
    "committedDigest")
# e05's own digest, read from the one place it is written down. Two policies, two digests, one
# stamp — the nudge's thresholds are deliberately NOT in `RelevancePolicy`, so that changing a
# cooldown cannot invalidate e06's verdict cache (R-95).
COMMITTED_INTERVENTION_DIGEST=$(committed_literal \
    "Packages/FocusCore/Tests/FocusCoreTests/InterventionPolicyTests.swift" \
    "committedDigest")

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

# --- the cockpit, drawn against a store this script seeded (focus-h7h) ------------------------
#
# A fourth launch, and it exists for exactly one boundary value. `sessionElapsedSeconds` is what
# the cockpit's timer reads, and the mutation that guts it hands the window `nil` — which is also
# what a Mac with no session running hands it. The mutant and the shipping code are then
# extensionally identical, and no instrument can separate them: that is a fact about the two
# programs, not a shortcoming of the reading. So the check is run where the value exists.
#
# A store of its own, seeded with a ninety-minute session and a commitment, in the temporary
# directory this script removes on the way out. `--focus-store` makes the composition root open it
# instead of the person's, so nothing anywhere writes a session into their day that never happened.

COCKPIT_STORE="$SESSION_DIR/cockpit.store"
COCKPIT_SEED_JSON="$SESSION_DIR/cockpit-seed.json"
COCKPIT_JSON="$SESSION_DIR/cockpit.json"

print
print "== $BINARY --focus-session-seed $COCKPIT_STORE"
"$BINARY" --focus-self-check "$COCKPIT_SEED_JSON" --focus-session-seed "$COCKPIT_STORE"
cockpit_seed_rc=$?
print "cockpit seed EXIT=$cockpit_seed_rc"
if (( cockpit_seed_rc != 0 )); then
    print -u2 "FAIL: the cockpit-fixture seeding launch exited $cockpit_seed_rc"
    exit 1
fi

print "== $BINARY --focus-self-check-cockpit --focus-store $COCKPIT_STORE"
"$BINARY" --focus-self-check "$COCKPIT_JSON" --focus-self-check-cockpit --focus-store "$COCKPIT_STORE"
cockpit_rc=$?
print "cockpit EXIT=$cockpit_rc"
if (( cockpit_rc != 0 )); then
    print -u2 "FAIL: the cockpit-rendering launch exited $cockpit_rc"
    exit 1
fi

if [[ -n "${FOCUS_EVIDENCE_DIR:-}" ]]; then
    cp -- "$SEED_JSON" "$FOCUS_EVIDENCE_DIR/session-seed.json"
    cp -- "$RESTORE_JSON" "$FOCUS_EVIDENCE_DIR/session-restore.json"
    cp -- "$COCKPIT_JSON" "$FOCUS_EVIDENCE_DIR/cockpit-rendering.json"
    print "evidence: $FOCUS_EVIDENCE_DIR/session-seed.json, $FOCUS_EVIDENCE_DIR/session-restore.json"
fi

print
print "== assertions"
python3 - "$OUT" "$SEED_JSON" "$RESTORE_JSON" "$COMMITTED_STAMP" "$COMMITTED_DIGEST" \
    "$COMMITTED_INTERVENTION_DIGEST" "$COCKPIT_JSON" <<'PYTHON'
import json
import sys

path = sys.argv[1]
with open(path) as handle:
    report = json.load(handle)
with open(sys.argv[2]) as handle:
    seed = json.load(handle)
with open(sys.argv[3]) as handle:
    restore = json.load(handle)
with open(sys.argv[7]) as handle:
    seeded_cockpit = json.load(handle)
committed_stamp = sys.argv[4]
committed_digest = sys.argv[5]
committed_intervention_digest = sys.argv[6]

failures = []
not_taken_readings = []


def check(condition, message, detail=None):
    if condition:
        print(f"ok   {message}")
    else:
        line = f"FAIL: {message}"
        if detail is not None:
            line += f"\n      got: {detail!r}"
        failures.append(line)
        print(line, file=sys.stderr)


def not_taken(subject, reason, detail=None):
    """A reading whose PRECONDITION was not met — never a verdict on the code (focus-jax).

    This is the third outcome, and it exists because the gate spent two runs in five naming six
    failures of the Edit-menu integration when the only fact was that `NSApp.isActive` was false.
    A reading that could not be taken is NOT TAKEN: it is not a pass, so it is listed loudly at
    the end and never counted as coverage, and it is not a failure, so it never attributes a
    machine's behaviour to a line of code. Anything that would still be true of a background
    application is asserted OUTSIDE the branch that calls this, so a probe cannot go quiet by
    losing its preconditions.
    """
    line = f"NOT TAKEN: {subject} — {reason}"
    if detail is not None:
        line += f"\n      {detail}"
    not_taken_readings.append(line)
    print(line)


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
#
# ## The chain is asserted first, so a failure names its cause (focus-h6d, focus-icq)
#
# These two assertions used to fail on this machine — `menuItemTitle` came back `Undo`, once
# `Undo Typing`, with `enabledAfterUndo` true — and the report said nothing about why. Measured
# in the running app: `journalUndoManager === keyWindow.undoManager` is TRUE, so the wiring is
# correct; the key window's first responder was a FIELD EDITOR, the shared NSTextView AppKit
# installs for a focused `TextField`, and NSTextView answers `undoManager` with its own. The menu
# was validating the text field's undo, which is macOS working — while somebody is editing text,
# Undo undoes their typing.
#
# F-93's claim is about the other state, so the probe now ends editing before reading and the
# three facts it depends on are checked here. A regression in the wiring fails on
# `windowUndoManagerIsJournal`; a probe that read the menu mid-edit fails on
# `firstResponderIsFieldEditor`; and only a genuine break in the menu integration reaches the
# four title and enablement assertions below, which are unchanged.
#
# ## The two preconditions in the same dictionary that nothing asked (focus-jax)
#
# Five gate runs on one tree: 1, 4 and 5 green, 2 and 3 red on the SAME SIX assertions in
# different configurations. Identical test counts, identical digests, and `undoManagerTitle`
# reading `Undo Change Priority` in ALL TEN readings — the wiring was correct every time. The one
# fact that differed: `applicationIsActive` and `hasKeyWindow` were false in exactly those two
# readings. The probe reported both; this script asserted NEITHER, so the gate named six failures
# of the Edit-menu integration when the only fact was that another application had taken the
# front part-way through a report that spends a second and a half turning the run loop.
#
# The block is split the way the claim is. The FRONT-FREE half — the cockpit window's manager, the
# journal's own action name before and after the undo — is asserted in every run: those are facts
# about objects and a regression in `adoptUndoManager` fails on them whatever this Mac was doing.
# The FRONT-BOUND half is AppKit's own validation, which cannot be taken by a background
# application at all; the probe asks for the front back before taking it and states whether it got
# it, and an obstacle that outlasts the recovery deadline makes those four readings **NOT TAKEN**
# rather than four failures of code that did not change. A machine that never lets the app forward
# in the first place still fails loudly, by name, in the `activation` block far above.

undo = report.get("undo") or {}
check(undo.get("available") is True, "the cockpit window has an undo manager", undo)

# --- front-free: asserted in every run, taken or not ------------------------------------------
check(
    undo.get("cockpitWindowExists") is True,
    "the cockpit window exists to carry the journal's undo manager",
    undo.get("cockpitWindowExists"),
)
check(
    undo.get("cockpitUndoManagerIsJournal") is True,
    "the journal IS the undo manager the cockpit hands to the responder chain (F-93, front-free)",
    undo.get("cockpitUndoManagerIsJournal"),
)
check(
    undo.get("undoManagerTitle") == "Undo Change Priority",
    "the journal's own manager names the operation 'Undo Change Priority' (P-50, front-free)",
    undo.get("undoManagerTitle"),
)
check(
    undo.get("canUndo") is True,
    "the journal's manager holds the scripted mutation and can take it back",
    undo.get("canUndo"),
)
check(
    undo.get("undoManagerTitleAfterUndo") == "Undo",
    "the journal's own manager reads plain 'Undo' again after taking it (front-free)",
    undo.get("undoManagerTitleAfterUndo"),
)
check(
    undo.get("canUndoAfterUndo") is False,
    "the journal's manager has nothing left to undo after taking it",
    undo.get("canUndoAfterUndo"),
)

# --- front-bound: AppKit's own validation, which a background application cannot take ---------
if undo.get("menuReadingWasTaken") is not True:
    not_taken(
        "the Edit menu's own validation (F-93)",
        undo.get("menuReadingNotTakenBecause") or "no reason reported",
        "frontRegained={!r} applicationIsActive={!r} hasKeyWindow={!r}; "
        "declined to judge menuItemTitle={!r} enabled={!r}".format(
            undo.get("frontRegained"),
            undo.get("applicationIsActive"),
            undo.get("hasKeyWindow"),
            undo.get("menuItemTitle"),
            undo.get("enabled"),
        ),
    )
else:
    check(
        undo.get("keyWindowIsCockpit") is True,
        "the undo reading was taken through the cockpit's own window",
        undo.get("keyWindowIsCockpit"),
    )
    check(
        undo.get("windowUndoManagerIsJournal") is True,
        "the journal registers on the manager the key window hands to the responder chain (F-93)",
        undo.get("windowUndoManagerIsJournal"),
    )
    check(
        undo.get("firstResponderIsFieldEditor") is False,
        "no field editor stands between the Edit menu and the window's undo manager",
        undo.get("firstResponderIsFieldEditor"),
    )
    check(
        undo.get("responderUndoManagerIsJournal") is True,
        "the responder chain the Edit menu is validated against resolves to the journal's manager",
        undo.get("responderUndoManagerIsJournal"),
    )
    print(
        "note the reading before editing ended: "
        f"firstResponderWasFieldEditor={undo.get('firstResponderWasFieldEditor')!r}, "
        f"menuItemTitleWhileEditing={undo.get('menuItemTitleWhileEditing')!r}, "
        f"editingEnded={undo.get('editingEnded')!r} "
        "(recorded, never asserted — a focused text field owning Undo is macOS working, and "
        "`responderUndoManagerIsJournal` above cannot pass vacuously without a responder)"
    )
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

# --- the application target's own wiring (focus-cp2) ------------------------------------------
#
# `App/` is not a package. No test bundle can import it, so every closure in the scene graph is
# unreachable from the unit lane — and four no-op mutations to those closures survived the whole
# nineteen-stage gate byte for byte: EXIT=0 five times out of five against the mutant, and an
# empty diff between the clean run's ok-assertion list and the mutant's.
#
# One `App/` wire was never in that state. Deleting `AppComposition.shared.start()` from
# `FocusSentinelApp.init()` fails seven assertions here, loudly — because this script runs the
# **shipping scene graph in the shipping process**, which no other lane in the programme does.
# That control is what says the route works; the block below brings the rest of `App/` into it.
#
# Two facts per wire, and both are needed. `wiresFired` names which closure ran, so a failure
# names the line rather than a symptom three objects away; the effect beside it says whether it
# did anything, so a wire that fired and did nothing is not let through by its own receipt.

shell = report.get("shell") or {}
fired = set(shell.get("wiresFired") or [])

check(
    "undoManagerChanged" in fired,
    "the cockpit scene's undo-manager wire ran",
    sorted(fired),
)
check(
    "appearanceChanged" in fired,
    "the cockpit scene's appearance wire ran",
    sorted(fired),
)
check(
    shell.get("undoManagerAdopted") is True,
    "the cockpit handed the journal the window's own undo manager (F-93)",
    shell.get("undoManagerAdopted"),
)
# **The sixth of focus-jax's six, and now front-free.** It read
# `journalUndoManager === NSApp.keyWindow?.undoManager`, and a background application has no key
# window at all — so on the two runs in five where the front was lost this failed as "the manager
# the journal holds is not the window's", which is a claim about a wire built out of a fact about
# the machine. The cockpit window is there whichever application is frontmost, and it is the
# window the claim is about.
check(
    shell.get("undoManagerIsTheCockpitWindows") is True,
    "the manager the journal holds is the cockpit window's own",
    shell.get("undoManagerIsTheCockpitWindows"),
)
# A sentinel, not a comparison: `QuickCaptureModel` is initialised with `.systemDefault`, so
# "the shell themed the panel" and "nobody ever told the panel anything" are the same reading
# on a machine whose appearance happens to be the default. This is the second fact.
check(
    shell.get("capturePanelTraitsAdopted") is True,
    "the cockpit scene handed the quick-capture panel its appearance traits",
    shell.get("capturePanelTraitsAdopted"),
)
# The handoff, driven through `NSApp.delegate.application(_:open:)` — which is where AppKit
# hands a kAEGetURL event to an application and, with an @NSApplicationDelegateAdaptor in play,
# is also how SwiftUI feeds the cockpit scene's `.onOpenURL`. So this runs the closure in
# App/FocusSentinelApp.swift. It shows and never mutates (F-142).
check(
    shell.get("urlHandlerAnswersOpen") is True,
    "the application answers application(_:open:), so a focus:// URL has somewhere to land",
    shell.get("urlHandlerAnswersOpen"),
)
check(
    "handoffReceived" in fired,
    "the cockpit scene's onOpenURL wire ran when a focus:// URL was delivered",
    sorted(fired),
)
check(
    shell.get("handoffWasShown") is True,
    "the delivered handoff reached CockpitState, where a person can accept or refuse it",
    shell.get("handoffWasShown"),
)
check(
    shell.get("handoffTask") == "Self-check handoff probe",
    "the handoff that arrived is the one that was sent",
    shell.get("handoffTask"),
)
# Refused on the way out, which is both the truthful end for a handoff no person asked for and
# the thing that stops the probe leaving a sheet attached — a sheet still up when NSApp.terminate
# runs is how a self-check turns into a hung gate stage.
check(
    shell.get("handoffWasDismissed") is True,
    "the probe's handoff was refused again, leaving no sheet and no stored change",
    shell.get("handoffWasDismissed"),
)
# Recorded, never asserted. `NSApp.delegate` is SwiftUI's own adaptor object rather than
# `FocusAppDelegate` itself — it forwards, which is what `urlHandlerAnswersOpen` and the drive
# above actually prove — and asserting the class would be asserting a SwiftUI implementation
# detail.
print(
    f"note NSApp.delegate is FocusAppDelegate = {shell.get('urlHandlerIsTheAppDelegate')!r}; "
    f"declared wires {shell.get('wiresDeclared')!r}; fired {sorted(fired)!r} "
    "(recorded, never asserted)"
)

# --- the cockpit scene's connection (focus-2er) -----------------------------------------------
#
# The scene used to pass five arguments read off the composition root — the state, both mutation
# hosts, the elapsed figure, the last foreign bundle identifier — and each was one compiling
# line away from a frozen placeholder. `state:` alone emptied the window: no priority, no
# session, no recents, no verdict, no capabilities, no handoff sheet. The gate stayed at PASS.
#
# It is one argument now, and the pair of receipts below is why that is worth something.
# `cockpitConnected` says the scene asked the composition root; `cockpitRendered` is recorded by
# `CockpitView.body` through a closure only the root can supply, so a scene that asked and then
# drew something else fails as loudly as one that never asked. What the connection *carries* is
# asserted in `AppCompositionConnectionTests`, which can hold the live hosts up beside it — the
# division of labour is deliberate: this lane proves the scene ran the wire, the unit lane proves
# the wire carried the truth.
check(
    "cockpitConnected" in fired,
    "the cockpit scene asked the composition root for its live connection",
    sorted(fired),
)
check(
    "cockpitRendered" in fired,
    "that connection reached CockpitView's body rather than a placeholder",
    sorted(fired),
)
check(
    "cockpitThemed" in fired,
    "the cockpit scene injected the live appearance traits into its window",
    sorted(fired),
)
# The scroll view is the scene's, not the view's: a ScrollView reports no intrinsic height, so a
# view inside one rasterises as a blank rectangle under ImageRenderer and every committed cockpit
# baseline would become a picture of nothing. That puts it in App/, where dropping it left a
# window whose last lines are unreachable at the default text size — and the whole gate green.
check(
    shell.get("cockpitContentScrolls") is True,
    "the cockpit's content is inside a scroll view, so its footer is reachable",
    shell.get("cockpitContentScrolls"),
)

# --- the appearance observer, live (focus-2er) ------------------------------------------------
#
# It lived in `App/` where nothing could reach it, so the object that decides whether the shell
# honours dark mode and the four accessibility settings had no test in the programme. It is in
# `FocusHost` now and `AppearanceObserverTests` drives it; what this lane adds is that the
# **running application** resolved its traits against the Mac it is on rather than against a
# constant.
check(
    shell.get("appearanceTraitsMatchTheSystem") is True,
    "the shell's appearance traits are the person's preference resolved against this Mac",
    (
        shell.get("appearancePreference"),
        shell.get("appearanceColorScheme"),
        shell.get("appearanceSystemColorScheme"),
    ),
)
# **The two values that were printed side by side and never compared** (focus-8ry). This note said
# "(recorded, never asserted)" in as many words, and on a seeded launch the two disagreed: stored
# `light`, live `matchSystem`. It is an assertion now. On the person's own store the two usually
# agree at `matchSystem`, which is why the seeded lane above carries the load — but a launch that
# stopped reading the store at all fails here too, for anybody who has ever chosen a scheme.
check(
    shell.get("appearancePreferenceIsTheStored") is True,
    "the shell's live appearance preference is the one in the store",
    (shell.get("appearancePreference"), shell.get("storedAppearancePreference")),
)
# --- the cockpit can be opened from a surface that is not the cockpit (focus-mwm) -------------
#
# The popover's "Open Focus Sentinel" button asks the command centre to raise the main window, and
# the only thing that can answer is the closure `ShellCommands` installs out of SwiftUI's
# `openWindow`. Measured before the repair: the button sent `.newPriority` down a channel whose
# only listener is the cockpit's own view, so with the window closed it did nothing at all, and
# with the window open behind another application it set a capture flag on a window nobody could
# see. Nothing but a launch with a real scene graph can take this reading.
check(
    shell.get("canRaiseCockpit") is True,
    "the shell installed the one route that can open the cockpit window",
    shell.get("canRaiseCockpit"),
)
print(
    f"note appearance refreshCount={shell.get('appearanceRefreshCount')!r} "
    f"colorScheme={shell.get('appearanceColorScheme')!r} "
    f"system={shell.get('appearanceSystemColorScheme')!r}"
)

# --- e02 · the quick-capture panel (F-06) -----------------------------------------------------

panel = report.get("capturePanel") or {}
check(panel.get("prebuilt") is True, "the quick-capture panel was built at launch", panel.get("prebuilt"))
check(panel.get("visibleAfterShow") is True, "showing the panel makes it visible", panel.get("visibleAfterShow"))
# The probe's own cleanup receipt, reported since it was written and asked by nobody
# (focus-jax's sweep). A self-check that shows the capture panel and leaves it on the screen has
# changed the machine it was measuring, and every window reading after this line is about a
# screen the probe put a panel on.
check(
    panel.get("hiddenAfterHide") is True,
    "the capture-panel probe put the panel away again",
    panel.get("hiddenAfterHide"),
)
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
# **The reading before it, or the one after it proves nothing** (focus-jax's sweep).
#
# `audioListenerCountBeforePause` sat in the same dictionary as the assertion below, reported and
# asked by nobody — and `after == 0` is satisfied perfectly by a graph that had no CoreAudio
# listener to remove. The observer assertion three lines above has always had its before-reading;
# this one did not, so half of the pause claim was `0 -> 0` wearing the same green as `n -> 0`.
check(
    isinstance(sensing.get("audioListenerCountBeforePause"), int)
    and sensing["audioListenerCountBeforePause"] > 0,
    "the graph holds CoreAudio property listeners before the pause probe",
    sensing.get("audioListenerCountBeforePause"),
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

# --- every wire in App/, after all three windows have existed (focus-2er) ---------------------
#
# The block above reads the shell while the cockpit is the only window open. The Settings and
# Keyboard Shortcuts windows do not exist until Cmd-comma and Cmd-question have been pressed, so
# their wires are read here, afterwards, with a turn of the run loop in between.
#
# The acceptance criterion for this boundary is an **enumeration**, not a list of fixes: every
# closure, binding, environment injection, observer registration and preference read that crosses
# out of App/ has a declared name, and the assertion is that the fired set equals the declared
# set. A wire gutted stops arriving; a wire declared and never wired never arrives; a wire added
# later without a receipt cannot be added at all, because ShellWire is what App/ calls.
after = report.get("shellAfterProbes") or {}
after_fired = set(after.get("wiresFired") or [])
declared = set(after.get("wiresDeclared") or [])
check(
    bool(declared) and after_fired >= declared,
    "every wire App/ declares actually fired in the running application",
    {
        "notFired": after.get("wiresNotFired"),
        "windows": after.get("windowTitles"),
    },
)
# Named individually as well as as a set, so a failure says which line stopped working rather
# than "one of eleven".
for wire, sentence in [
    ("undoManagerChanged", "the cockpit scene's undo-manager wire"),
    ("appearanceChanged", "the cockpit scene's appearance wire"),
    ("handoffReceived", "the cockpit scene's onOpenURL wire"),
    ("cockpitConnected", "the cockpit scene's request for its live connection"),
    ("cockpitRendered", "the cockpit connection reaching CockpitView's body"),
    ("cockpitThemed", "the cockpit window's appearance-traits injection"),
    ("helpRendered", "the Keyboard Shortcuts reference reaching its window"),
    ("helpThemed", "the Keyboard Shortcuts window's appearance-traits injection"),
    ("settingsThemed", "the Settings window's appearance-traits injection"),
    ("settingsConnected", "the Settings scene's request for its live connection"),
    ("settingsRendered", "the Settings connection reaching ShellSettingsView's body"),
    ("settingsAppeared", "the Settings window's stored-appearance re-read on appear"),
]:
    check(wire in after_fired, f"{sentence} ran", sorted(after_fired))

# Non-vacuity: the set assertion above would pass if ShellWire were emptied. It is not.
check(
    len(declared) >= 12,
    "App/ still declares every wire this epic enumerated",
    sorted(declared),
)
# The three windows the wires belong to really existed when the reading was taken, so a wire
# that fired is a wire a window actually ran.
titles = after.get("windowTitles") or []
check(
    any("Keyboard Shortcuts" in t for t in titles),
    "the Keyboard Shortcuts window was open when the wire reading was taken",
    titles,
)

# --- what the three windows actually DREW (focus-h7h) -----------------------------------------
#
# The block above proves every wire in App/ fired. That was measured to be worth nothing on its
# own. An eight-part mutation that kept every one of those receipts firing and replaced only the
# VALUES — the cockpit's whole state a frozen placeholder, the session timer reading nothing, the
# Privacy pane always saying nothing is watched, the three windows ignoring dark mode and every
# accessibility setting, the theme never persisted, the Intervention pane's controls reaching
# nothing, the Keyboard Shortcuts window empty — passed the whole nineteen-stage gate: EXIT=0,
# 262 ok-assertions against 262, and an EMPTY diff between the clean run's assertion list and the
# mutant's.
#
# A receipt that fires when a closure runs cannot distinguish a closure that produced the right
# value from one that produced a constant. So each window now reports the values it put on the
# screen, through the same SwiftUI preference mechanism `DecisionSurfaceReachability` proved on
# the nudge panel, and the composition root holds them up beside what it handed over.

rendering = report.get("shellRendering") or {}
readings = rendering.get("readings") or {}

for surface, sentence in [
    ("cockpit", "the cockpit"),
    ("settings", "the Settings window"),
    ("help", "the Keyboard Shortcuts window"),
]:
    reading = readings.get(surface) or {}
    check(
        reading.get("drewWhatTheAppKnows") is True,
        f"{sentence} drew every value the composition root handed it",
        reading.get("summary"),
    )

# The set, beside the names, for the reason the wire block asserts both: a surface added later
# without a reading cannot be added at all, because ShellThemedSurface is what App/ calls.
check(
    set(rendering.get("surfacesThatDrewWhatTheAppKnows") or [])
    == set(rendering.get("surfacesDeclared") or [])
    and len(rendering.get("surfacesDeclared") or []) >= 3,
    "every window App/ themes reported what it drew, and drew what the app knows",
    (
        rendering.get("surfacesThatDrewWhatTheAppKnows"),
        rendering.get("surfacesDeclared"),
    ),
)

# NON-VACUITY. A field the root has no opinion about is skipped rather than failed, so a root that
# recorded nothing at all would make every assertion above pass for a window drawing anything.
# These floors are the same job `len(declared) >= 12` does for the wire enumeration.
# The settings floor was 15 and is 14: the presentation-exclusion field went with the section that
# instructed a person to add an app the application offered no way to add (focus-1qm). A floor
# lowered because a value was deleted is a different act from one lowered because a value stopped
# arriving, and this is the first kind.
for surface, floor in [("cockpit", 18), ("settings", 14), ("help", 2)]:
    reading = readings.get(surface) or {}
    check(
        isinstance(reading.get("expectedFieldCount"), int)
        and reading["expectedFieldCount"] >= floor,
        f"the composition root recorded at least {floor} values it handed the {surface} window",
        reading.get("expectedFieldCount"),
    )

# --- TOTALITY: the boundary, not the enumeration (focus-7ow) -----------------------------------
#
# THE DOCTRINE FAILURE THIS BLOCK EXISTS TO END. The block above answers "did the window draw what
# it was handed", and for five consecutive rounds it could only answer it about fields somebody had
# thought to list. `ShellRenderedField` had a case for every value the round-3 mutant touched and
# for nothing else, so a residue mutant built out of four values nobody had enumerated — two of
# them boolean FLIPS — reproduced the round-3 invisibility signature verbatim: 286 ok against 286,
# an EMPTY ok-assertion diff, a full nineteen-stage PASS, and four things on the screen saying
# something false. The cockpit's footer told the person their store was unavailable when it was
# fine; the Privacy pane printed `/` as where their data lives, with Reveal in Finder wired to
# open it.
#
# So the composition root now walks each connection with `Mirror` and asserts that EVERY STORED
# PROPERTY is bound to a receipt the root records an expectation for. It cannot be written to a
# known failure, because it does not know what the failure is — it knows only what the type has.
# Add a field and report nothing, and this goes red naming the field.

# **And the walk now goes to the leaves** (focus-cxs). Round 6 closed the boundary at the
# connection struct and named its own residue in the same breath — "deeper structs are leaves,
# covered by a whole-value digest that does not participate in the comparison" — and a three-line
# residue mutant then gave 19/19 PASS, 303 ok against 303 and an EMPTY ok-assertion diff while
# three drawn things lied. A `.drawn` binding no longer stops the walk: it descends into every
# value type of this programme's own, so a field invented inside `PrioritySnapshot` or
# `InterventionSettings` is an unmapped path rather than an invisible one.
#
# The floors below are the live app's own counts, which are LOWER than the unit lane's: a nil
# optional has no members to walk, and the running app has no pending handoff. The type-level
# question is `ShellConnectionTotalityTests`', asked of a value with every branch filled in; this
# is the value-level one, asked of whatever is really on the screen.
totalities = rendering.get("totalities") or {}
for surface, connection, floor in [
    ("cockpit", "CockpitConnection", 30),
    ("settings", "ShellSettingsConnection", 40),
]:
    totality = totalities.get(surface) or {}
    check(
        totality.get("isTotal") is True,
        f"every field of {connection} is echoed by a receipt",
        totality.get("summary"),
    )
    # NON-VACUITY, and it is the same job the field-count floors above do: an audit that walked
    # nothing has an empty `unmappedPaths` and would pass every clause for a connection nobody
    # looked at.
    check(
        isinstance(totality.get("fieldCount"), int) and totality["fieldCount"] >= floor,
        f"the audit of {connection} walked at least {floor} fields",
        (totality.get("fieldCount"), totality.get("walkedPaths")),
    )

check(
    set(rendering.get("connectionsThatAreTotal") or []) == {"cockpit", "settings"},
    "both scene connections are total",
    rendering.get("connectionsThatAreTotal"),
)

# **Two live values describing one thing, disagreeing** (focus-zrs). The totality readings above
# are about FIELDS — is every property bound to a receipt. This is about VALUES: the cockpit draws
# a projection of what is being watched and the Privacy pane draws the graph's own summary; the
# engine builds its snapshot for one commitment and the nudge loop writes its receipts under
# another. Each pair has a wire that keeps it honest, and each wire is a thing somebody could
# delete. This is the reading that would say so.
check(
    rendering.get("projectionDisagreements") == [],
    "no fact the shell holds twice is held two different ways",
    rendering.get("projectionDisagreements"),
)

# --- the structural residue round 5 named, closed (focus-7ow) ----------------------------------
#
# A macOS TabView builds only the selected pane. Measured: the Privacy pane's own receipts never
# arrived, because nobody had clicked Privacy — so every Settings value had to be reported from
# the WINDOW, out of the argument it was about to hand a pane, and a defect INSIDE an unselected
# pane was invisible to every lane in the programme. The selection is driven from the composition
# root now and the self-check walks all three panes; these assert that the walk happened, that it
# put the person's tab back, and that the panes between them reported the values only they can.

panes = rendering.get("settingsPanesWalked") or {}
check(
    panes.get("visited") == panes.get("declared"),
    "the self-check put every declared Settings pane in front",
    (panes.get("visited"), panes.get("declared")),
)
check(
    panes.get("restored") is True,
    "the Settings pane the person had selected was put back",
    panes.get("restored"),
)
# The fields that can ONLY come from inside a pane: the Privacy pane's store path and the
# Intervention fields that were carried into the window and reported by nothing. If the walk
# silently stopped working these would be absent and the reading above would already be red — this
# names them, so the failure says which pane stopped drawing rather than only that one did.
#
# `notificationAuthorisation` is not among them any more: the section that drew it asked for a
# permission the app cannot use, and went (focus-wy0).
reported_after_walk = set(panes.get("reportedAfterTheWalk") or [])
for field in [
    "privacyStorePath",
    "quietHours",
    "interruptionUsage",
    "reducedInterruptionForced",
]:
    check(
        field in reported_after_walk,
        f"a Settings pane reported {field}, which no window-level stamp can produce",
        sorted(reported_after_walk),
    )

# The cockpit drew the LIVE handoff rather than a placeholder's empty one. The handoff probe puts
# a sentence into CockpitState that no person would ever type, which is what makes this a value a
# frozen placeholder cannot be carrying. `handoffWasShown` above reads the store's answer, and a
# window drawing a placeholder passes it: the handoff really did arrive, and the window really did
# draw something else.
check(
    shell.get("cockpitDrewTheHandoff") is True,
    "the cockpit drew the handoff that arrived, not a placeholder's empty one",
    (shell.get("cockpitDrewnHandoffTask"), (shell.get("cockpitRenderingWithHandoff") or {}).get("summary")),
)

# NON-VACUITY for the three appearance-traits fields. `AppearanceTraits.systemDefault` is a light
# appearance with every accessibility setting off, which is exactly what an untouched Mac reports
# — so on a light Mac a window that ignores the injection and one that honours it draw the SAME
# traits and nothing whatsoever could tell them apart. The self-check drives the preference to
# dark for two-thirds of a second, and this is the assertion that the drive actually moved it.
check(
    rendering.get("drivenTraitsDifferFromTheDefault") is True,
    "the driven appearance really differs from the default, so the traits readings mean something",
    (rendering.get("drivenTraits"), rendering.get("defaultTraits")),
)
check(
    rendering.get("appearancePreferenceRestored") is True,
    "the appearance the drive moved was put back exactly as it was found",
    rendering.get("appearancePreferenceRestored"),
)
# The quick-capture panel followed the LIVE change. `capturePanelTraitsAdopted` above is a
# sentinel — somebody told the panel something — and a scene that told it the default satisfies it
# exactly as well as one that told it the truth.
check(
    rendering.get("capturePanelFollowedTheLiveTheme") is True,
    "the quick-capture panel followed the live appearance change rather than a constant",
    (rendering.get("capturePanelTraits"), rendering.get("drivenTraits")),
)

# --- the two wires no value can reach, driven (focus-h7h) --------------------------------------
#
# `setPreference` and `onInterventionAction` are only ever called by a CLICK, and no lane in this
# programme holds the Accessibility grant it would take to press one — which is exactly why
# `{ _ in }` in their place survived two rounds of gates. So the Settings window hands back the
# closures its controls are actually holding, the self-check calls them, and the composition
# root's own graph is watched for the change. Everything is put back.

appearance_drive = rendering.get("driveSetPreference") or {}
check(
    appearance_drive.get("available") is True,
    "the Settings window handed back the sinks its controls are wired to",
    appearance_drive,
)
check(
    appearance_drive.get("reachedTheObserver") is True,
    "the Appearance picker's writer reaches the observer the shell re-renders from",
    (appearance_drive.get("probe"), appearance_drive.get("observerAfter")),
)
check(
    appearance_drive.get("reachedTheStore") is True,
    "the Appearance picker's writer reaches the store, so the choice survives a quit (M4)",
    (appearance_drive.get("probe"), appearance_drive.get("storedAfter")),
)
check(
    appearance_drive.get("restored") is True,
    "the appearance probe put the person's stored preference back",
    (appearance_drive.get("storedBefore"), appearance_drive.get("restored")),
)

intervention_drive = rendering.get("driveInterventionSink") or {}
check(
    intervention_drive.get("available") is True,
    "the Intervention pane handed back the sink its controls are wired to",
    intervention_drive,
)
check(
    intervention_drive.get("voiceReachedTheLoop") is True,
    "the Intervention pane's Voice control reaches the running nudge loop (M3)",
    (intervention_drive.get("voiceProbe"), intervention_drive.get("voiceAfter")),
)
check(
    intervention_drive.get("reducedReachedTheLoop") is True,
    "the Intervention pane's Reduced-Interruption control reaches the running nudge loop",
    (intervention_drive.get("reducedProbe"), intervention_drive.get("reducedAfter")),
)
# **And the store** (focus-40i). Both controls reached the loop and neither reached a column: a
# person who picked Warm, or asked to be interrupted less, got neutral and full panels back on
# the next launch, and the probe above could not see it because it read the value back in the
# same process it had just set it in.
check(
    intervention_drive.get("voiceReachedTheStore") is True,
    "the Intervention pane's Voice control reaches the store, so the deck survives a quit",
    (intervention_drive.get("voiceProbe"), intervention_drive.get("voiceStored")),
)
check(
    intervention_drive.get("reducedReachedTheStore") is True,
    "Interrupt me less reaches the store, so a person who asked for quiet keeps it",
    (intervention_drive.get("reducedProbe"), intervention_drive.get("reducedStored")),
)
# **Quiet hours, at all three depths** (focus-z7g). The pane's "Set a window" button emitted an
# action the composition root discarded with `break`, so the control redrew "Off" for ever and
# gate 8 of the twelve-gate suppression stack was dead code in the shipping app. Three readings
# because two of them were separately capable of being green over a dead control: the loop's own
# field, the NudgeSurroundings the stack is handed, and the row on disk.
check(
    intervention_drive.get("quietHoursReachedTheLoop") is True,
    "the Intervention pane's Quiet-hours control reaches the running nudge loop",
    (intervention_drive.get("quietHoursProbe"), intervention_drive.get("quietHoursAfter")),
)
check(
    intervention_drive.get("quietHoursReachedTheGate") is True,
    "the quiet-hours window reaches the surroundings the suppression stack evaluates (gate 8)",
    (
        intervention_drive.get("quietHoursProbe"),
        intervention_drive.get("quietHoursInSurroundings"),
    ),
)
check(
    intervention_drive.get("quietHoursReachedTheStore") is True,
    "the quiet-hours window reaches the store, so a window survives a quit",
    (intervention_drive.get("quietHoursProbe"), intervention_drive.get("quietHoursStored")),
)
# Non-vacuity: the probe is the other state from whatever this Mac's store holds, so a sink that
# ignored the action entirely could not satisfy the three readings above by coincidence.
check(
    intervention_drive.get("quietHoursProbe") != intervention_drive.get("quietHoursStoredBefore"),
    "the quiet-hours probe drove the window to the state it was not already in",
    (
        intervention_drive.get("quietHoursProbe"),
        intervention_drive.get("quietHoursStoredBefore"),
    ),
)
check(
    intervention_drive.get("restored") is True,
    "the intervention probe put all three preferences back, including the person's stored window",
    intervention_drive.get("restored"),
)

# --- the session timer, where the figure exists (focus-h7h) ------------------------------------
#
# The fourth launch, against a store this script seeded with a ninety-minute session and a
# commitment. The non-vacuity assertions come first and they are the point: if the fixture failed
# to arrive, the reading below would pass by comparing two absences, which is the exact failure
# mode this whole launch exists to escape.

check(
    seeded_cockpit.get("livePriorityIntent") == seeded_cockpit.get("seededPriorityIntent"),
    "the seeded commitment reached the composition root, so the cockpit had a session to draw",
    (seeded_cockpit.get("livePriorityIntent"), seeded_cockpit.get("seededPriorityIntent")),
)
seeded_elapsed = seeded_cockpit.get("liveSessionElapsedSeconds")
check(
    isinstance(seeded_elapsed, (int, float)) and seeded_elapsed > 5_000,
    "the seeded session really is running, so 'none' is a value the app never produces here",
    seeded_elapsed,
)
check(
    seeded_cockpit.get("drawnSessionElapsedSeconds") not in ("", "none", None),
    "the cockpit's session timer drew a figure rather than nothing",
    seeded_cockpit.get("drawnSessionElapsedSeconds"),
)
check(
    seeded_cockpit.get("drewWhatTheAppKnows") is True,
    "the cockpit drew every value the composition root handed it, against a seeded session",
    (seeded_cockpit.get("reading") or {}).get("summary"),
)

# --- the appearance a person chose, on the launch after the one that chose it (focus-8ry) ------
#
# The same fourth launch, and the same reason it exists. The ordinary self-check opens the
# PERSON's store, whose appearance is whatever they last set — almost always `matchSystem`, which
# a shell that never read the store answers correctly by accident. This store was seeded `light`
# by the launch above, so `matchSystem` here is the defect's signature and nothing else's, on a
# light Mac and a dark one alike.
#
# Measured before the repair, on two consecutive seeded launches: stored `light`, live
# `matchSystem`, and the whole shell drawn Dark — until the person happened to press Cmd-comma,
# at which point it flipped underneath them.
seeded_appearance = seeded_cockpit.get("seededAppearancePreference")
check(
    seeded_appearance not in (None, "", "matchSystem"),
    "the seeded appearance is a real choice, so 'never read the store' cannot answer it by accident",
    seeded_appearance,
)
check(
    seeded_cockpit.get("storedAppearancePreference") == seeded_appearance,
    "the seeded appearance really is in the store this launch opened",
    (seeded_cockpit.get("storedAppearancePreference"), seeded_appearance),
)
check(
    seeded_cockpit.get("appearancePreference") == seeded_appearance,
    "the shell restored the stored appearance at launch, without waiting for the Settings window",
    (seeded_cockpit.get("appearancePreference"), seeded_appearance),
)
# …and it resolved it. A wire that read the store and then failed to recompute the traits from it
# would satisfy the reading above and still draw every window in the system's scheme.
check(
    seeded_cockpit.get("appearanceColorScheme") == "light",
    "the shell's windows are drawn in the scheme the stored preference resolves to",
    (
        seeded_cockpit.get("appearanceColorScheme"),
        seeded_cockpit.get("appearancePreference"),
    ),
)

# --- the Help menu holds nothing that opens an alert (focus-h7h) -------------------------------
#
# AppKit installs its own "<App> Help" item, bound to showHelp: and to Cmd-?, beside the registry's
# action — which is titled the same thing. showHelp: on an application with no help book runs a
# MODAL ALERT, and this script performs Cmd-? as one of its five key-equivalent probes. Measured
# twice, in isolation: the app took the main thread inside -[NSAlert runModal] and never wrote its
# report, and the lane had to be killed after ten minutes. A mutation-testing lane whose failure
# mode is a hang is a lane that cannot be used for mutation testing.
check(
    (report.get("menusWithAnAutomaticHelpItem") or []) == [],
    "no menu in the menu bar holds an item that would open a help alert",
    report.get("menusWithAnAutomaticHelpItem"),
)
print(
    "note AppKit re-installed "
    f"{report.get('automaticHelpItemsReinstalled')!r} automatic help item(s) after launch "
    "(recorded, never asserted)"
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
# **Two checks, because there are two ways to fail and they are not the same failure**
# (focus-2vi). The count used to arrive as `-1` when it could not be taken at all, and the
# single assertion below then reported `got: -1` — a number, for a reading nobody made. The
# report now says `countWasTaken` as its own fact and names which of the two obstacles it hit,
# so a run in which this graph never learned who was frontmost reads as NOT TAKEN rather than
# as a window list that came back empty.
check(
    windows_read.get("countWasTaken") is True,
    "the grant-free window list was READ AT ALL (a reading that could not be taken is NOT TAKEN)",
    windows_read.get("countNotTakenBecause") or windows_read.get("count"),
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
# **And the note under it said which, without reading which** (focus-jax's sweep).
#
# `SensingHost.FrontmostReadingObstacle` exists precisely because "no presentation reading" is two
# different facts: a stand-down the person is entitled to, and this graph never having been told
# who was frontmost — "a defect wearing the same clothes", as its own doc says. The report carries
# `notTakenBecause` to tell them apart; this note asserted the first one in prose whichever it
# was. A gate that names a cause it did not read is the failure this whole round is about, one
# note smaller.
presentation = sensing.get("presentation") or {}
if presentation.get("suppressed"):
    if presentation.get("notTakenBecause") == "theSensitivityGateStoodDown":
        print("note the frontmost application was suppressed by the sensitivity gate")
    else:
        not_taken(
            "the presentation quorum's three inputs",
            presentation.get("notTakenBecause") or "the report named no obstacle at all",
            "the graph was never told who was frontmost, which is not the gate standing down",
        )
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

# --- e04: the relevance engine, as the running application reports it ----------------------
#
# The stamp and the policy digest are the third leg of R-75.4. They are compared against the
# literals read out of `EngineStampTests` and `RelevancePolicyTests` — the one place they are
# written down — so a build whose thresholds moved without a version bump fails here as well
# as in the unit lane and in the evaluation stage.

relevance = report.get("relevance") or {}

check(
    bool(committed_stamp),
    "the committed engine stamp was found in EngineStampTests",
    committed_stamp,
)
check(
    bool(committed_digest),
    "the committed policy digest was found in RelevancePolicyTests",
    committed_digest,
)
check(
    report.get("engineStamp") == committed_stamp,
    f"the running application stamps {committed_stamp}",
    report.get("engineStamp"),
)
check(
    report.get("policyDigest") == committed_digest,
    f"the running application's policy digest is {committed_digest}",
    report.get("policyDigest"),
)

# The seam and the inspector are one object. Two would be two drift accumulators, and the
# verdict a person reads would not be the answer anything else in the app was given.
check(
    relevance.get("classifierIsEngine") is True,
    "the RelevanceClassifier the composition root publishes IS the engine",
    relevance.get("classifierIsEngine"),
)

# The snapshot was really built — the four-invalidation contract fired at least once at
# launch — and it was built under the policy this build is running.
check(
    (relevance.get("snapshotBuildCount") or 0) >= 1,
    "the rule snapshot was built at least once",
    relevance.get("snapshotBuildCount"),
)
check(
    relevance.get("snapshotMatchesRunningPolicy") is True,
    "the snapshot was built under the policy this build is running",
    relevance.get("snapshotMatchesRunningPolicy"),
)

# The engine RAN, in this process, at zero grants. A stamp alone would only prove it was
# constructed.
check(
    (relevance.get("judgementCount") or 0) >= 1,
    "the engine judged at least once during the self-check",
    relevance.get("judgementCount"),
)

# **The verdict answers the question, whichever way it answers it** (focus-lmy).
#
# This block used to read `verdict.isMandated in (False, None)` under the heading "Nothing may
# be mandated here. There is no nudge in this build to consume a mandate" — six lines above the
# check that the ladder declares exactly two rungs. One script asserted that the ladder exists
# AND that nothing may feed it, and the contradiction went unread for an epic because the false
# half is satisfied by a self-check run that has no active priority: `.noActivePriority` is the
# first guard `decide(…)` reaches, so the check passed for a reason unrelated to its heading.
#
# What is asserted instead is the shape `InterventionEligibility` actually has — two cases, and
# the pane draws one sentence per case. Exactly one of them is reported, never both and never
# neither, which is a claim the shipping path can break in either direction and which no longer
# needs the app to be quiet in order to pass.
verdict = relevance.get("verdict") or {}
if verdict:
    check(
        bool(verdict.get("isMandated")) != bool(verdict.get("suppressionReason")),
        "the running verdict either carries a mandate or names why it stayed silent",
        (verdict.get("isMandated"), verdict.get("suppressionReason")),
    )
else:
    # No application came forward, so nothing has been judged and the inspector draws
    # "nothing judged yet". A missing verdict is a real answer; an empty one that claimed a
    # suppression reason would not be.
    print("note the self-check judged nothing to report an eligibility for")

# R-72.2. The affordance that writes a session rule has arrived — `NudgeHost` inserts one when
# somebody presses the panel's *"not now"* correction — so this is no longer a record that a
# mechanism is absent. It is the record that nothing wrote to the box **unbidden**: a self-check
# presses nothing, so a non-zero count here is the loop correcting a person who never spoke.
check(
    relevance.get("sessionRuleCount") == 0,
    "the session rule box is empty — nothing wrote to it without a person pressing something",
    relevance.get("sessionRuleCount"),
)

# --- e05: the nudge loop, as the running application reports it ----------------------------
#
# Three claims, and each is what one of this epic's gates rests on. Every one of them is made
# at **zero grants**, from a plain `exec`, with no prompt of any kind — which is the whole of
# standing condition 5 for e05.

nudge = report.get("nudge") or {}
panel = nudge.get("panel") or {}

# 1 — the digest. The nudge's thresholds live in their own manifest with their own digest, so
# that tuning a cooldown never invalidates e06's verdict cache (R-95). Asserted against the one
# place the literal is written down, exactly as the engine stamp and the policy digest are.
check(
    bool(committed_intervention_digest),
    "the committed intervention digest was found in InterventionPolicyTests",
    committed_intervention_digest,
)
check(
    report.get("interventionDigest") == committed_intervention_digest,
    f"the running application's intervention digest is {committed_intervention_digest}",
    report.get("interventionDigest"),
)
# …and it is NOT the relevance digest. Two policies, two digests: if these two were ever equal
# the split would have collapsed and a snooze duration would be keying a verdict cache.
check(
    report.get("interventionDigest") != report.get("policyDigest"),
    "the intervention digest and the policy digest are two different numbers",
    (report.get("interventionDigest"), report.get("policyDigest")),
)

# 2 — **nothing asked for anything.** The number that discharges standing condition 5 for this
# epic. `requestAuthorization` appears in exactly one file in the repository — the Intervention
# settings pane's user-initiated button — and no routing path, no host and no gate stage can
# reach it, so this is a property of the call graph rather than of a counter somebody remembered
# to leave alone.
check(
    report.get("requestAuthorizationCallCount") == 0,
    "the application asked for no notification authorisation",
    report.get("requestAuthorizationCallCount"),
)
check(
    report.get("notificationAuthorisation") in
    ("authorised", "denied", "notRequested", "provisional"),
    "the notification authorisation was read, and decoded to one of the four states",
    report.get("notificationAuthorisation"),
)

# 2a — **no question the person can still answer that the loop has forgotten** (focus-v0u).
#
# THE MOST USER-VISIBLE DEFECT THIS EPIC PRODUCED. `accuse(…)` cleared `openWarrant` on one line
# and then touched the panel on the `.panel` branch ALONE — so a question displaced onto the
# menu-bar glyph, the popover badge or a notification was left on screen, fully drawn and fully
# clickable, while the host had forgotten it. `answer(_:)` hit `guard let warrant = openWarrant
# else { return }` and dropped the click; `defer { closeSurfaces() }` tidied the evidence away.
# Measured on the loop that still had preemption: before visible=true reachable=true, after
# reachable=true and "every offered action is reachable" — the person clicks "Yes, add it", ZERO
# rules are written, the receipt says "expired", and the question is asked AGAIN. The ladder's
# entry rung is the glyph, which made that the commonest displacement there was.
#
# Every earlier finding in this epic was the app silencing itself. That one was the app ignoring
# the person and asking again, which is U-1's repeat-asking clause broken from the other side.
check(
    nudge.get("orphanedNudgeSurfaces") == [],
    "no surface is offering a nudge the loop has forgotten, of either kind",
    nudge.get("orphanedNudgeSurfaces"),
)
# **A nudge that raises no window is visible in the menu bar, or it is visible nowhere**
# (focus-mkk, focus-2xw).
#
# `NudgeSurface.holdsTheInterruptionSlot` is false for exactly the two surfaces that raise no
# window — the glyph and the badge — and those are exactly the two whose whole physical presence
# is the status item. A surface on that list with no mark on the item is a nudge with nowhere to
# be, and the app charged the day's budget for six of them: measured on the shipping loop, seven
# drifts 700 s apart gave six delivered rows on `menuBar`, `accusationsToday` 6 of 6, the query
# budget squeezed from 4 to 1, and ONE write to the menu bar — made by `install()` before the
# first rung existed.
#
# The counts beside it are the reading that finding needed and did not have. They are printed
# rather than gated: an automated run raises no rung, so a threshold on them would be a threshold
# on zero. What is gated is the join, which is a fact about the vocabulary and holds in every run.
# **The badge's own surface has a size, and it is the one the product committed to** (focus-5yu).
#
# This report carried `panel.contentSize` and nothing at all for the popover — the surface the
# quiet route sends every rung to, and the one that had committed to no size. Measured before the
# repair, on a 1920 x 1080 display: 346 x 855 with a 21-character priority and 346 x 3127 with a
# long one, both placed as though they were about 340 tall. `check-focus-steal.sh` makes the full
# set of assertions about it; this is the one that belongs in every self-check, including the
# Release one, because it is the number a person's popover is drawn at.
popover = nudge.get("popover") or {}
check(
    isinstance(popover.get("committedWidth"), (int, float))
    and popover["committedWidth"] > 0,
    "the popover reports the width it commits to",
    popover.get("committedWidth"),
)
check(
    (popover.get("fullest") or {}).get("isTheCommittedWidth") is True,
    "the fullest popover is laid out at the committed width, at any priority length",
    popover.get("fullest"),
)

check(
    nudge.get("surfacesWithNoWindowAndNoMark") == [],
    "every nudge surface that raises no window marks the status item",
    nudge.get("surfacesWithNoWindowAndNoMark"),
)
print(
    "     menu bar: {} glyph write(s), {} title write(s), {} announcement(s), attention {}".format(
        nudge.get("menuBarGlyphWrites"),
        nudge.get("menuBarTitleWrites"),
        nudge.get("menuBarAnnouncements"),
        nudge.get("menuBarAttention"),
    )
)

# **Only a delivery spends a cap** (R-81, focus-sq7).
#
# `unopened` is the fourth disposition and the second way of not reaching somebody: a nudge that
# reached the badge and waited behind a click nobody made. Before it there was no case for that at
# all, so such a nudge wrote NO ROW — and a day on which the app raised its top rung and nobody
# looked was indistinguishable in the record from a day on which the ladder never left the glyph.
#
# Asserted as a set rather than a count, because the danger of a new disposition is not that there
# are four of them but that one of them starts charging: `spendsBudget` is what the daily caps sum
# on, and an invitation nobody opened is an attempt rather than an interruption.
check(
    nudge.get("dispositionsSpendingACap") == ["delivered"],
    "only a delivery spends a cap, whatever the record has learned to say",
    nudge.get("dispositionsSpendingACap"),
)
check(
    "unopened" in (nudge.get("dispositionsDeclared") or []),
    "the record can say a badge invitation was never opened",
    nudge.get("dispositionsDeclared"),
)

# The exits are enumerated, and the unit lane walks every one of them. Asserted here so an exit
# added to the enum is visible in the gate log rather than only in a test file.
#
# **Five** (focus-h0s). It was four, and before U-2 it was five with `preempted` in it — that one
# went with the mechanism, because an accusation can no longer take a question's ask or its
# surface. The fifth now is `screenReclaimed`: F-81's "give me my screen back", which used to
# travel as `worldMovedOn` and wrote nothing only because the panel had already been ordered out
# and `QuestionLedgerPolicy` refused a receipt it could not prove readable. Once the record moved
# inside the door that accident would have become a write, so the exit says for itself that it
# owes none.
#
# Exact equality rather than a floor: a floor cannot see an exit being *removed*, and both edits
# this line has survived were removals. A count that only fails upward is half a lint.
check(
    len(nudge.get("questionExitsDeclared") or []) == 5,
    "every way an open question can end is enumerated",
    nudge.get("questionExitsDeclared"),
)
# **And exactly one of them owes the record** (focus-h0s).
#
# The count above says the vocabulary is whole; this says the *obligation* is placed, which is the
# half that was wrong. `resolve(_:snoozeDuration:)` was the fifth producer of `worldMovedOn` and
# the only one that did not call `expireOpenQuestion()` first, so Ctrl-Cmd-R aimed at the menu-bar
# glyph destroyed a question on the panel with nothing written down. The obligation lives on the
# exit now instead of on five callers remembering.
#
# Named rather than counted: an exit quietly joining or leaving the writing set is the edit that
# matters, and `["worldMovedOn"]` says which one it is. `answered` writes through the ledger's own
# transaction; `surfaceWentOutOfReach` and `neverDelivered` are un-askings R-81 forbids a receipt
# for; `screenReclaimed` is F-81.
check(
    nudge.get("questionExitsWritingAnExpiry") == ["worldMovedOn"],
    "exactly the exit that means the world ended it writes the question down",
    nudge.get("questionExitsWritingAnExpiry"),
)

# **The active priority is still one fact** (focus-zrs).
#
# The invariant above reads EMPTY throughout the defect this round is about, which is the whole
# lesson: an invariant sees only the contradiction it was built for. Round 7's finding was the
# ACTIVE PRIORITY held twice — gate 1 decided by `priorityHost.state.priority != nil`, the whole
# lifecycle of the interruption that gate admitted keyed to a SECOND, live `PriorityStore` read
# inside the loop. Measured on a divergence: panel visible showing .question, every offered action
# reachable, rules written 0, receipts [], settled false, RE-ASKED FIVE TIMES — and one function
# on, `displacedQuestion(from:)` answered nil so `PreemptionCredit` was never consulted at all.
#
# These four are the readings that would have seen it, taken off the shipping graph.
check(
    nudge.get("commitmentDisagreements") == [],
    "every statement of the active commitment agrees with every other",
    nudge.get("commitmentDisagreements"),
)
check(
    nudge.get("mandatesWithoutACommitment") == 0,
    "no interruption was mandated without the commitment it would be written under",
    nudge.get("mandatesWithoutACommitment"),
)
# A person really can press a day-old banner, so this is not zero by construction — it is zero
# because nothing in an automated run presses one. What it proves is that the refusal is wired and
# reporting: a run in which a stale press was OBEYED would leave this at zero too, which is why the
# unit lane drives the refusal and this only watches for it happening unbidden.
check(
    nudge.get("staleNotificationActions") == 0,
    "no notification action from a rung that is over reached the loop",
    nudge.get("staleNotificationActions"),
)

# D-06 as amended by U-2: two rungs, no more and no fewer — asserted in the running application
# as well as in the policy manifest and the evaluation report. The third rung, explicit
# recommitment, is deferred to epic focus-5ab. Amended rather than relaxed: it still fails on drift
# in either direction.
check(
    report.get("ladderRungsDeclared") == 2,
    "the ladder declares exactly two rungs",
    report.get("ladderRungsDeclared"),
)

# 2b — **no rung is delivered by notification at all** (U-2).
#
# This used to be a subtler claim: the notification carried the correction but its delivery could
# not be read, so it was allowed to carry the top rung and not allowed to settle the question it
# displaced. Both halves are gone. There is no preemption to settle anything, and the recommitment
# rung the notification existed to carry is deferred to focus-5ab — so the surfaces a rung can
# reach are the app's own, and that is asserted in the running application rather than argued.
check(
    "notification" not in (nudge.get("surfacesARungCanReach") or []),
    "no rung reaches a notification: the ladder is entirely in-app",
    nudge.get("surfacesARungCanReach"),
)

# 3 — **every rung reaches an in-app surface, and no authorisation can change that.** Since U-2 no
# rung routes to a notification, and since focus-wy0 `SurfaceRouter.route(…)` does not take an
# authorisation at all — so F-73's degraded path is not a path, it is the whole product. The
# in-app assertion is therefore unconditional rather than made only on a Mac that happens to be
# in the degraded state.
check(
    nudge.get("everyRungHasASurface") is True,
    "every rung of the ladder reaches a surface",
    nudge.get("routes"),
)
check(
    nudge.get("everyRungIsInApp") is True,
    "every rung is delivered in-app, whatever this Mac says about notifications",
    nudge.get("routes"),
)
# 3a — **and every accusation lands somewhere the person can answer it** (focus-uru).
#
# "In-app" is the weaker claim and it was the only one anybody made. Under macOS Reduce Motion —
# which AppearanceObserver forces `reducedInterruption` on for — the top rung routed to the
# popover badge, and the popover was a read-only label: no dismiss, no "this is relevant", no
# snooze. That passed `everyRungIsInApp` every time. This reading names the offending cells
# rather than answering a bare False.
#
# **The size of the fold is checked first, and that is focus-vxo's lesson** (R-96o's shape). The
# reading came back True while the running loop was putting a delivered accusation on the
# menu-bar glyph, because the fold asked the rung a *deck* claimed to draw and pinned an idle
# microphone and no presentation — so True was true of a space chosen so it could not be false.
# A verdict over a space the gate does not measure is not evidence, so the cell count is asserted
# before the verdict it qualifies.
ACCUSATION_ROUTE_CELLS = 1 * 2 * 2 * 2 * 2 * 5  # rung × presenting × mic × flag × menuBar × deck
check(
    nudge.get("accusationRouteCellsChecked") == ACCUSATION_ROUTE_CELLS,
    f"the accusation-route fold covers all {ACCUSATION_ROUTE_CELLS} cells rather than a subset",
    nudge.get("accusationRouteCellsChecked"),
)
check(
    nudge.get("everyAccusationRouteCanBeAnswered") is True,
    "every accusation route offers the person a way to answer back",
    nudge.get("accusationRoutesWithNoWayToAnswer"),
)
# A question is never a notification (R-82): its route takes no authorisation at all.
check(
    nudge.get("querySurface") in ("panel", "popoverBadge"),
    "a question routes to an in-app surface and never to a notification",
    nudge.get("querySurface"),
)

# **Every deck and every flag, not only the cell that always answers `panel`** (focus-kby).
#
# This stage used to ask the router exactly one question — standard deck, reduced interruption
# off, nothing playing — which always answers `.panel`. The badge route was therefore invisible
# to every gate in the programme, and the badge route is the one the ledger was burning questions
# on: the silentVisual deck, reduced interruption (forced on by Reduce Motion) and a live
# microphone or camera, which is anybody on a call.
query_routes = nudge.get("queryRoutes") or []
check(
    len(query_routes) >= 15,
    f"the router is exercised across every deck and flag ({len(query_routes)} cells)",
    len(query_routes),
)
check(
    nudge.get("everyQueryRouteCanCarryAQuestion") is True,
    "every cell routes a question to a surface that can actually carry one",
    [row for row in query_routes if not row.get("canCarryAQuestion")],
)
check(
    (nudge.get("queryRoutesReachingTheBadge") or 0) > 0,
    "the badge route is reachable, and is therefore exercised rather than assumed unreachable",
    nudge.get("queryRoutesReachingTheBadge"),
)
check(
    (nudge.get("queryRoutesReachingThePanel") or 0) > 0,
    "the panel route is still reachable too, so the table has not collapsed to one answer",
    nudge.get("queryRoutesReachingThePanel"),
)
# P-131: a badge in a hidden menu bar is a deferral, never a question nobody can answer.
check(
    nudge.get("querySurfaceWhenMenuBarHidden") == ""
    and nudge.get("queryDeferralWhenMenuBarHidden") == "menuBarHidden",
    "a question routed to a hidden menu bar is deferred rather than delivered to nothing",
    {
        "surface": nudge.get("querySurfaceWhenMenuBarHidden"),
        "deferral": nudge.get("queryDeferralWhenMenuBarHidden"),
    },
)

# 4 — **the panel takes nothing**, on all four of R-89's grant-free readings.
#
# Reading 1 alone is what an earlier draft of this gate asserted, and P-139 measured a real
# focus theft it cannot see: `makeKeyAndOrderFront(nil)` on this style mask flips
# `NSApp.isActive` from false to true and installs a key window **while the frontmost
# application never moves**. Readings 2-4 are the ones that catch it, and none needs a grant.
before = panel.get("readingsBeforeShow") or {}
after = panel.get("readingsAfterShow") or {}

check(
    panel.get("wasVisible") is True,
    "the nudge panel really appeared, so the readings are about something",
    panel.get("wasVisible"),
)

# --- the sentence names the APP, not its bundle identifier (focus-ebv) -------------------------
#
# Every nudge said "Is com.figma.Desktop part of Write the Q3 proposal?" for the whole of e05,
# on four user-visible surfaces, one of them directly under a button reading "Back to Pages".
# Nothing in this gate could see it: the probe drew a panel and measured its window, and three
# unit tests PINNED the identifier as the expected output.
#
# So the running binary is asked what its panel actually says. The subject is this process's own
# identifier, which is running by definition, so the workspace lookup either produces a name or
# the fix is not in the build being checked. Three assertions, and the third is what stops the
# first two being satisfied by a name that happens to equal the key.
check(
    panel.get("subjectResolved") is True,
    "the nudge resolved a name for the application it is about",
    (panel.get("subjectIdentifier"), panel.get("subjectDisplayName")),
)
sentence = panel.get("subjectSentence") or ""
display_name = panel.get("subjectDisplayName") or ""
identifier = panel.get("subjectIdentifier") or ""
check(
    bool(display_name) and display_name != identifier,
    "the display half is a name rather than a second copy of the storage key",
    (identifier, display_name),
)
check(
    bool(sentence) and display_name in sentence and identifier not in sentence,
    "the sentence a person reads names the application and never its bundle identifier",
    sentence,
)

# --- the same seam, over inputs that CAN fail (focus-2pd) --------------------------------------
#
# The three readings above are all about ONE subject: this process's own identifier, which is
# running by definition. Its own comment in `SelfCheck.swift` said so — "the lookup either
# produces a name or the fix is not in the binary" — which is the honest description of a fixed
# point, not of a test. Every branch of `SubjectNaming` that can go wrong is unreachable from
# that input: the installed-but-not-running lookup, the origin derivation, the whitespace guard
# and the identifier fallback.
#
# So the binary now walks all five and the gate judges each. The running reading stays and is
# named the control it is.
naming = panel.get("subjectNaming") or {}
check(
    bool(naming),
    "the binary reported the subject seam over more than its own identifier",
    sorted(naming),
)

running = naming.get("running") or {}
check(
    running.get("namedNobody") is False and running.get("isANameNotTheKey") is True,
    "control: the running application resolves to a name rather than to its own key",
    running,
)

# An origin is not an application. It has no localised name to have been looked up, so the host
# is DERIVED — and the one wrong answer available here is a browser's name for a site.
origin = naming.get("origin") or {}
check(
    origin.get("namedNobody") is False
    and origin.get("identifier") == "https://docs.google.com"
    and origin.get("displayName") == "docs.google.com",
    "an origin is named by its host, never by a browser and never by the whole URL",
    origin,
)

# e04's mixed drift carries "". A nudge that named nobody must go on naming nobody: all three of
# nil, empty and whitespace are the same absence, and none of them may acquire a blank name.
for label in ("whitespace", "empty", "nothing"):
    absence = naming.get(label) or {}
    check(
        absence.get("namedNobody") is True,
        f"a subject of {label} names nobody rather than acquiring a blank name",
        absence,
    )

# The last resort, and the reason it is not the empty string: an identifier is ugly, an empty
# sentence is a bug the person is being asked to answer.
absent = naming.get("notInstalled") or {}
check(
    absent.get("namedNobody") is False
    and absent.get("displayName") == "com.example.focus.sentinel.absent"
    and absent.get("isANameNotTheKey") is False,
    "an identifier nothing answers to falls back to itself, never to an empty sentence",
    absent,
)

# **Installed and not running** — focus-7gc's second branch, which this process's own identifier
# can never reach. It is the one reading that cannot be guaranteed on an arbitrary Mac, so a
# skip is reported by name and read as a skip here rather than as a pass.
anchor = naming.get("installedNotRunning") or {}
if anchor.get("skipped") is True:
    print(f"SKIP  installed-but-not-running: {anchor.get('reason')}")
else:
    check(
        anchor.get("namedNobody") is False and anchor.get("isANameNotTheKey") is True,
        "an application installed and NOT running is named from its bundle, not by its key",
        anchor,
    )
    check(
        bool(anchor.get("returnTargetName"))
        and anchor.get("returnTargetName") == anchor.get("displayName"),
        "the sentence and the 'Back to …' button call the same not-running application the same",
        (anchor.get("displayName"), anchor.get("returnTargetName")),
    )

# --- the dark-mode probe, which used to be light-pinned itself (focus-7wy) ----------------------
#
# `panelReport()` built the panel with no `traits:` argument, so it took the default —
# `AppearanceTraits.systemDefault`, which is LIGHT. focus-pq8's fix is real; the instrument that
# was supposed to notice it regressing could not see one, because it always drew in the
# appearance it was meant to be checking against.
#
# Four assertions, and the last two are what stop the first two being a coincidence: the probe
# drives the appearance to dark before it renders, so the live traits differ from the default
# whatever this Mac is set to. `.get(...) is True` fails on an ABSENT key as well as a false one,
# which is the point — the defect was a value quietly defaulting, not a value reading false.
check(
    panel.get("drivenTraitsDifferFromTheDefault") is True,
    "the probe drove the appearance away from the light default, so its reading is a claim",
    (panel.get("liveAppearanceTraits"), panel.get("defaultAppearanceTraits")),
)
check(
    panel.get("panelIsDark") is True,
    "the nudge panel was built in the DARK appearance the probe drove it to",
    panel.get("appearanceTraits"),
)
check(
    panel.get("panelDrewTheLiveAppearance") is True,
    "the nudge panel drew the traits the app holds, rather than a default it fell back to",
    (panel.get("appearanceTraits"), panel.get("liveAppearanceTraits")),
)
check(
    panel.get("appearanceRestored") is True,
    "the probe put the appearance preference back where it found it",
    panel.get("appearanceRestored"),
)
# **Was it taken, and only then: did it move** (focus-2vi). One assertion used to carry both
# questions, and when `NSWorkspace.shared.frontmostApplication` came back nil at both ends it
# printed `got: ('', '')` — a message about the frontmost application not being byte-identical,
# for a pair of readings in which there was no frontmost application to be identical to. The
# nil now serialises as `null` and is asked about first, by name.
check(
    panel.get("frontmostWasReadBothTimes") is True,
    "reading 1 was TAKEN at both ends — nil frontmost is NOT TAKEN, never an application",
    (before.get("frontmostBundleIdentifier"), after.get("frontmostBundleIdentifier")),
)
# Reading 3 is absolute here as well: the panel becomes key only when a person clicks it, and
# that is true whether or not the application is active. It is asserted OUTSIDE the branch
# below, because nothing about it depends on who happened to be frontmost.
check(
    after.get("panelIsKey") is False,
    "reading 3: the panel is not the key window",
    after.get("panelIsKey"),
)
# **And in which direction it moved** (focus-jax, focus-doy set B).
#
# The four delta readings spend two and a half seconds of run loop between their two ends, and
# any application coming forward in that window changes the frontmost identifier and flips
# `NSApp.isActive`. focus-doy measured exactly that: the front went from this app to a Chrome PWA
# the app under test cannot activate, and the gate reported two failures of R-89 — the panel
# named for something a `.nonactivatingPanel` cannot do.
#
# A panel can only ever move the front TOWARD this process. So a front that moved and ended on
# US is a real R-89 failure and is asserted below; a front that moved and ended on somebody else
# is the world moving, and the reading is NOT TAKEN. The absolute form of the claim is §4.5's
# `focus-steal` stage, which launches the app with `open -g -a` — never frontmost, which is the
# posture a nudge really fires in (P-128, P-139) — and it is unaffected by any of this.
if panel.get("deltaReadingWasTaken") is not True:
    not_taken(
        "R-89's four focus deltas around the nudge panel",
        panel.get("deltaNotTakenBecause") or "no reason reported",
        "reading 3 (the panel is not the key window) was taken absolutely and passed; "
        "the absolute form of the rest is the focus-steal stage",
    )
else:
    check(
        bool(before.get("frontmostBundleIdentifier"))
        and before.get("frontmostBundleIdentifier") == after.get("frontmostBundleIdentifier"),
        "reading 1: the frontmost application is byte-identical before and after the panel is shown",
        (before.get("frontmostBundleIdentifier"), after.get("frontmostBundleIdentifier")),
    )
    # Readings 2 and 4 are asserted as a **delta**, not absolutely, and the reason is this
    # launch. The shell survey activates the application on purpose — AppKit validates a menu
    # item by walking the *key window's* responder chain, and a background application has no key
    # window at all — so `NSApp.isActive` is legitimately true here before the panel is shown.
    # Requiring it to be false would be asserting something about the self-check's own launch
    # rather than about the panel.
    check(
        panel.get("changedNothing") is True,
        "showing the nudge changed none of the four focus readings",
        (before, after),
    )
    check(
        after.get("applicationIsActive") == before.get("applicationIsActive"),
        "reading 2: NSApp.isActive is exactly what it was before the panel was shown",
        (before.get("applicationIsActive"), after.get("applicationIsActive")),
    )
    check(
        after.get("applicationKeyWindowIsNil") == before.get("applicationKeyWindowIsNil"),
        "reading 4: showing the panel installed no key window",
        (before.get("applicationKeyWindowIsNil"), after.get("applicationKeyWindowIsNil")),
    )
check(
    panel.get("hiddenAfter") is True,
    "the panel was put away again, so a self-check leaves no window on the screen",
    panel.get("hiddenAfter"),
)

# R-89's six properties, on the real window object the application actually showed.
properties = panel.get("properties") or {}
check(
    panel.get("propertiesAreCorrect") is True,
    "the panel is non-activating, key-capable, never main, and never hides on deactivate",
    properties,
)
check(
    properties.get("isNonActivating") is True,
    "the panel's style mask carries .nonactivatingPanel",
    properties.get("isNonActivating"),
)
check(
    properties.get("canBecomeMain") is False,
    "the panel can never become the application's main window",
    properties.get("canBecomeMain"),
)

# The menu bar is really installed, so the ambient rung has somewhere to be.
check(
    nudge.get("menuBarInstalled") is True,
    "the menu-bar command centre is installed",
    nudge.get("menuBarInstalled"),
)

# ------------------------------------------------------------------------------------------

print()
# **Listed, never counted as coverage** (focus-jax). A NOT TAKEN reading is not a pass, and a run
# in which one of them went quiet has to say so in the same breath as it says OK — otherwise a
# probe that stopped being takeable becomes a probe that stopped being a probe, and the gate
# reports green for the absence of evidence.
if not_taken_readings:
    print(f"NOT TAKEN — {len(not_taken_readings)} reading(s) whose precondition was not met:")
    for line in not_taken_readings:
        print(f"  {line}")
    print()
if failures:
    print(f"SELF-CHECK FAILED — {len(failures)} assertion(s)", file=sys.stderr)
    sys.exit(1)
print("SELF-CHECK OK")
PYTHON
rc=$?

exit $rc
