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
# The committed decode table for the notification boundary (focus-652), read the same way from the
# file that owns it. See the block at `notificationAuthorisationReads` below for what it replaced.
COMMITTED_DECODE_TABLE=$(committed_literal \
    "Packages/FocusUI/Tests/FocusUITests/NotificationDeliveryTests.swift" \
    "committedDecodeTable")
COMMITTED_DECODE_CELLS=$(committed_literal \
    "Packages/FocusUI/Tests/FocusUITests/NotificationDeliveryTests.swift" \
    "committedDecodeCells")
# e06's ladder lengths, read out of the evaluation policy — the same file the SHIPPING GATE
# reads them from at stage 7d, and the second of the two independent witnesses the model-tier
# pin uses. The running application's composed ladder is the first; a build that composed a
# ninth rung would disagree with the number the gate holds `evaluation.json` to, and it would
# disagree here first.
COMMITTED_EXECUTABLE_RUNGS=$(committed_literal \
    "Packages/FocusEvaluate/Sources/FocusEvaluateCore/EvaluationPolicy.swift" \
    "executableRungCeiling")
COMMITTED_DECLARED_RUNGS=$(committed_literal \
    "Packages/FocusEvaluate/Sources/FocusEvaluateCore/EvaluationPolicy.swift" \
    "declaredRungCount")

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

# --- the first-run explanation, shown once and not again (focus-odz.7) ------------------------
#
# A FIFTH launch, against the store the fourth one just used. The fourth was the first time this
# app had ever opened that store, so it owed the explanation and showed it; this one is the
# relaunch, and it must not. Two processes are the whole point — a flag set and read back in one
# process is satisfied by a plain in-memory `Bool`, which is exactly the defect the v5 → v6
# migration exists to make impossible.

FIRSTRUN_JSON="$SESSION_DIR/cockpit-relaunch.json"

print "== $BINARY --focus-self-check-cockpit --focus-store $COCKPIT_STORE (relaunch)"
"$BINARY" --focus-self-check "$FIRSTRUN_JSON" --focus-self-check-cockpit --focus-store "$COCKPIT_STORE"
relaunch_rc=$?
print "relaunch EXIT=$relaunch_rc"
if (( relaunch_rc != 0 )); then
    print -u2 "FAIL: the first-run relaunch exited $relaunch_rc"
    exit 1
fi

# --- a question answered with no mouse, against a store this script owns (e07a, U-1, F-145) ----
#
# A SIXTH launch, and it needs a store of its own for one reason: the reading opens a real
# question through the loop and answers it with ⌃⌘Y, which writes a receipt and a rule. Run
# against the person's store that would be the app inventing a fact about their day, so the
# nudge block takes this reading only when `--focus-store` names a store, and the ordinary
# report above carries it as NOT TAKEN with the reason. The nudge-only mode is used because it
# launches headless — the block then activates the application itself, which is the plan's
# blocker measured for real: does coming forward (⌘-Tab) withdraw the open question?

KEYBOARD_STORE="$SESSION_DIR/keyboard.store"
KEYBOARD_JSON="$SESSION_DIR/keyboard.json"

print "== $BINARY --focus-self-check-nudge --focus-store $KEYBOARD_STORE"
"$BINARY" --focus-self-check "$KEYBOARD_JSON" --focus-self-check-nudge --focus-store "$KEYBOARD_STORE"
keyboard_rc=$?
print "keyboard EXIT=$keyboard_rc"
if (( keyboard_rc != 0 )); then
    print -u2 "FAIL: the keyboard-answer launch exited $keyboard_rc"
    exit 1
fi
if [[ -n "${FOCUS_EVIDENCE_DIR:-}" ]]; then
    cp -- "$KEYBOARD_JSON" "$FOCUS_EVIDENCE_DIR/keyboard-answer.json"
fi

if [[ -n "${FOCUS_EVIDENCE_DIR:-}" ]]; then
    cp -- "$FIRSTRUN_JSON" "$FOCUS_EVIDENCE_DIR/cockpit-relaunch.json"
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
    "$COMMITTED_INTERVENTION_DIGEST" "$COCKPIT_JSON" \
    "$COMMITTED_DECODE_TABLE" "$COMMITTED_DECODE_CELLS" "$FIRSTRUN_JSON" \
    "$COMMITTED_EXECUTABLE_RUNGS" "$COMMITTED_DECLARED_RUNGS" "$KEYBOARD_JSON" <<'PYTHON'
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
committed_decode_table = sys.argv[8]
committed_decode_cells = sys.argv[9]
with open(sys.argv[10]) as handle:
    relaunched_cockpit = json.load(handle)
# e06. Read from `EvaluationPolicy`, so the number this pin holds the running application to is
# the same number the shipping gate holds the evaluation report to — one literal, three readers.
committed_executable_rungs = int(sys.argv[11]) if sys.argv[11] else 0
committed_declared_rungs = int(sys.argv[12]) if sys.argv[12] else 0
# e07a. The sixth launch's report: the nudge block alone, against a store this script owns, so
# the keyboard-answer reading could be taken (it writes a receipt and a rule).
with open(sys.argv[13]) as handle:
    keyboard_launch = json.load(handle)

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


# Every reading this script routed through `taken(...)`, by the JSON path of the fact that says
# so. The sweep at the end of the file folds the report's own takenness facts over this set, so a
# probe added with a `wasTaken` and no branch fails rather than going quiet (focus-2uy.3).
routed_readings = set()


def taken(subject, path, detail=None):
    """Route one reading that the MACHINE may legitimately refuse to give.

    `path` is the dotted location in the self-check report of the pair every such reading
    publishes — `<something>WasTaken` and `<something>NotTakenBecause`, or a probe dictionary's
    own `wasTaken`/`notTakenBecause`. There is one mechanism because there was one defect: three
    probes in three rounds each grew their own branch, and the two that never grew one
    (`sensing.windowMetadata.countWasTaken` and `nudge.panel.deltaReadingWasTaken`) are what made
    the gate red on this machine for a fact about who was using it.

    Returns True when the reading WAS taken, so a caller's assertions live inside
    `if taken(...):` and cannot run on a measurement nobody made.
    """
    routed_readings.add(path)
    node = report
    parts = path.split(".")
    for part in parts[:-1]:
        node = (node or {}).get(part) or {}
    was_taken = node.get(parts[-1])
    if was_taken is True:
        return True
    reason_key = parts[-1]
    if reason_key.endswith("WasTaken"):
        reason_key = reason_key[: -len("WasTaken")] + "NotTakenBecause"
    else:
        reason_key = "notTakenBecause"
    not_taken(subject, node.get(reason_key) or "no reason reported", detail)
    return False


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
    # **Not `isEnabled` and not `hasAction`** (focus-6uf). Both used to be asserted here as
    # constants, and they were the gate ASSERTING the defect: every one of the app's own thirteen
    # items had to be enabled, six of them were guarded no-ops in the state a person is in the
    # first time they open the menu, and a fix would have looked like a regression. They are
    # asserted per item against the availability predicate's own answer, in the fold below.


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
    # Its enablement is the fold's, like every other registry item (focus-6uf).

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

# --- every registry item is offered exactly when the app would carry it out (focus-6uf) ------
#
# The defect this replaces: all thirteen of the app's own menu items were permanently enabled,
# six of them were guarded no-ops in the app's default state, and this script REQUIRED it —
# `check(item["isEnabled"], …)` per item, plus the same for Close Window. A proof that pins the
# bug, in the shape of the fixture named for the state it did not test.
#
# So it is a fold over the registry, and it has **two legs that do not come from the same place**:
#
#   1. the app's own predicate against this table, which is the rule stated independently here;
#   2. the menu item AppKit actually drew against that same predicate, which is the wiring.
#
# Leg 1 alone is a mirror — a predicate mutated to `True` would agree with a menu built from it —
# and leg 2 alone would be satisfied by a predicate that answers the same thing in every state.
# Together, flipping one arm of `PriorityCommand.isAvailable(in:)` fails leg 1 and deleting the
# `.disabled(…)` fails leg 2.
commands = report.get("commands") or {}
command_world = commands.get("world") or {}
command_actions = commands.get("actions") or []

MENU_FOR_PLACEMENT = {"file": "File", "view": "View", "help": "Help"}

# Phases that end a session, spelled out rather than imported: this table is only worth having
# because it is a second, independent statement of the rule.
TERMINAL_PHASES = {"interrupted", "complete"}


def expected_availability(action_id, world):
    """Would this verb do anything, in the state the app reported?

    Written from the guards the surfaces used to keep — `state.priority != nil`,
    `state.session == nil`, `session.phase != .paused`, `!session.phase.isTerminal`,
    `openRung != nil` — so that the app agreeing with it is a fact and not a tautology.
    """
    phase = world.get("sessionPhase")
    has_session = phase is not None and phase != "none"
    always = {
        # Both land with no commitment: ⌘O opens the capture field rather than a file panel with
        # nowhere to put its result.
        "priority.new": True,
        "context.addFiles": True,
        # A switch has both positions in every state.
        "sensing.pause": True,
        # ⌘W is the registry's claim on the Mac's own close key, and AppKit contributes its own
        # validated Close beside it.
        "shell.closeWindow": True,
        # F-81's panic key: a person presses it BECAUSE they do not know what is on their screen.
        "nudge.hideOverlays": True,
        # The popover exists for the life of the process.
        "nudge.menuBar": True,
        "shell.help": True,
    }
    if action_id in always:
        return always[action_id]
    if action_id == "priority.complete":
        return world.get("hasPriority") is True
    if action_id == "session.start":
        return not has_session or phase in TERMINAL_PHASES
    if action_id == "session.pause":
        return has_session and phase != "paused" and phase not in TERMINAL_PHASES
    if action_id == "session.complete":
        return has_session and phase not in TERMINAL_PHASES
    if action_id in ("nudge.relevant", "nudge.snooze"):
        return world.get("hasOpenNudge") is True
    # The three answers to a QUESTION are gated on the question's own fact, never the
    # accusation's (e07a): the loop keeps the two nudges apart, and so must this table.
    if action_id in ("nudge.answerYes", "nudge.answerNo", "nudge.answerNotNow"):
        return world.get("hasOpenQuestion") is True
    raise KeyError(action_id)


# The world the reading was taken in, printed rather than assumed: a per-item comparison means
# nothing until a reader can see which state it was a comparison about.
print(
    "note command world: hasPriority={} sessionPhase={} hasOpenNudge={} hasOpenQuestion={}".format(
        command_world.get("hasPriority"),
        command_world.get("sessionPhase"),
        command_world.get("hasOpenNudge"),
        command_world.get("hasOpenQuestion"),
    )
)
check(
    set(command_world) == {"hasPriority", "sessionPhase", "hasOpenNudge", "hasOpenQuestion"},
    "the app reported the whole world its menu availability is computed from",
    sorted(command_world),
)

reported_ids = [action.get("id") for action in command_actions]
# **The self-referential half.** The table above and the registry must name the same actions, in
# both directions: an action added to the registry with no entry here is a rule this script never
# checked, and an entry here for an action the registry no longer ships is a rule about nothing.
KNOWN_COMMAND_IDS = {
    "priority.new", "context.addFiles", "priority.complete", "session.start", "session.pause",
    "session.complete", "sensing.pause", "shell.closeWindow", "nudge.relevant", "nudge.snooze",
    "nudge.hideOverlays", "nudge.menuBar", "nudge.answerYes", "nudge.answerNo",
    "nudge.answerNotNow", "shell.help",
}
check(
    set(reported_ids) == KNOWN_COMMAND_IDS,
    "this script's availability table names exactly the actions the registry ships",
    sorted(set(reported_ids) ^ KNOWN_COMMAND_IDS),
)
check(
    len(reported_ids) == len(set(reported_ids)) and len(reported_ids) == 16,
    "all sixteen of the app's own actions were reported, once each",
    reported_ids,
)

for action in command_actions:
    action_id = action.get("id")
    title = action.get("title")
    if action_id not in KNOWN_COMMAND_IDS:
        continue
    expected = expected_availability(action_id, command_world)
    # Leg 1: the app's predicate says what this table says, for the state it is in.
    check(
        action.get("isAvailable") is expected,
        f"{title!r} is offered exactly when the app could carry it out",
        (action.get("isAvailable"), expected, command_world),
    )
    # Leg 2: the item AppKit drew agrees with it. A disabled SwiftUI menu item loses its action
    # as well as its enablement, which is what stops its key equivalent firing — so both are the
    # predicate's answer, and neither is a constant.
    menu_title = MENU_FOR_PLACEMENT.get(action.get("placement"))
    item = find(menu_title, title) if menu_title else None
    check(item is not None, f"{title!r} is in the {menu_title} menu", item_titles(menu_title or ""))
    if item:
        check(
            item["isEnabled"] is expected,
            f"{title!r}'s menu item is enabled exactly when the app would accept it",
            (item["isEnabled"], expected),
        )
        check(
            item["hasAction"] is expected,
            f"{title!r}'s menu item carries an action exactly when it is enabled",
            (item["hasAction"], expected),
        )

# **The non-vacuity guard.** Every assertion above is satisfied by a run in which the predicate
# answers the same thing for everything, as it did before this repair — thirteen `True`s matching
# thirteen enabled items. So the measured state has to be one that actually withdraws something,
# and it always is: nothing is nudging while the shell is being read, so the two nudge verbs are
# withdrawn, and a session either exists (withdrawing Start) or does not (withdrawing Pause and
# Finish).
offered = [a for a in command_actions if a.get("isAvailable") is True]
withdrawn = [a for a in command_actions if a.get("isAvailable") is False]
check(
    len(withdrawn) > 0,
    "the measured state withdraws at least one item, so the comparison is not sixteen Trues",
    [a.get("id") for a in command_actions],
)
check(
    len(offered) > 0,
    "the measured state still offers items, so the comparison is not sixteen Falses",
    [a.get("id") for a in command_actions],
)
print(
    "note {} of {} registry items offered, {} withdrawn: {}".format(
        len(offered), len(command_actions), len(withdrawn),
        ", ".join(sorted(a.get("id") for a in withdrawn)),
    )
)

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
if taken(
    "the Edit menu's own validation (F-93)",
    "undo.menuReadingWasTaken",
    "frontRegained={!r} applicationIsActive={!r} hasKeyWindow={!r}; "
    "declined to judge menuItemTitle={!r} enabled={!r}".format(
        undo.get("frontRegained"),
        undo.get("applicationIsActive"),
        undo.get("hasKeyWindow"),
        undo.get("menuItemTitle"),
        undo.get("enabled"),
    ),
):
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

# --- About, and the build a person can quote (focus-odz.3) ------------------------------------
#
# Nothing in the programme read `CFBundleShortVersionString` before this, so a defect report
# against "Focus Sentinel" named no artefact at all. The version now has one home in the app — the
# General pane, beside the appearance preference — and the About panel, which SwiftUI already put
# in the app menu, now opens with the credits paragraph rather than an icon and two numbers.
#
# **The pin is two independent readings of one artefact.** `drewWhatTheAppKnows` above already
# says the pane agreed with the composition root, and that is satisfied by a root and a pane
# agreeing on a constant; `bundleVersion` is read straight from `Bundle.main` outside the
# connection, and the string below is what the pane put on the screen.

check(
    report.get("bundleShortVersionString") == "0.1.0",
    "the built product carries the committed marketing version",
    report.get("bundleShortVersionString"),
)
check(
    bool(report.get("bundleBuild")),
    "the built product carries a build number",
    report.get("bundleBuild"),
)
check(
    report.get("bundleVersion")
    == f"{report.get('bundleShortVersionString')} ({report.get('bundleBuild')})",
    "the version sentence is the marketing version with the build in brackets",
    report.get("bundleVersion"),
)
check(
    report.get("settingsDrewnVersion") == report.get("bundleVersion"),
    "the version the General pane drew is the version this build calls itself",
    (report.get("settingsDrewnVersion"), report.get("bundleVersion")),
)
# Non-vacuity for the line above: two empty strings are equal, and would be.
check(
    bool(report.get("settingsDrewnVersion")),
    "the General pane drew a version at all",
    report.get("settingsDrewnVersion"),
)
# **The credits the About panel is really handed**, read out of the option dictionary
# `AboutPanel.present()` passes — not out of the catalog a second time. No unit lane can take this
# reading: under `swift test` SwiftPM copies String Catalogs rather than compiling them, so
# `ShellStrings.string(_:)` answers the key back there and "the credits resolved" is unassertable.
#
# The app menu already holds an item titled *About Focus Sentinel* — asserted above, and true of
# AppKit's own item as well as of this one, so the title cannot tell them apart. What this says is
# that the panel the item opens has a paragraph in it.
credits = report.get("aboutCredits") or ""
check(
    credits != "shell.about.credits" and len(credits) > 120,
    "the About panel's credits resolve to a paragraph rather than to their own key",
    credits[:80],
)
# It says the thing the product is about. A credits paragraph that stopped naming the boundary
# would be a panel drawn for its own sake.
check(
    "no permissions" in credits and "stays on this Mac" in credits,
    "the About panel says what the app does not look at and where what it records stays",
    credits,
)

# --- the status item's secondary menu (focus-odz.2) -------------------------------------------
#
# The item had one gesture. A left click toggles the popover, and the popover has no Quit, no
# Settings and no way to resume watching once the menu bar paused it — so somebody running the app
# with the cockpit shut, which is the state the menu bar exists for, could not leave it from
# anything they could see.
#
# What is pinned here is what the unit lane cannot read. Under `swift test` SwiftPM copies String
# Catalogs rather than compiling them, so `ShellStrings.string(_:)` answers the key back and the
# sentences a person reads are unassertable there. They are assertable here, in both watching
# states, against the app's own compiled catalog.

status_menu = report.get("statusItemMenu") or {}

check(
    status_menu.get("items") == ["openCockpit", "watching", "settings", "quit"],
    "the status item's secondary menu is the four declared items, in reading order",
    status_menu.get("items"),
)
check(
    status_menu.get("titlesWhileWatching")
    == ["Open Focus Sentinel", "Pause Watching", "Settings\u2026", "Quit Focus Sentinel"],
    "the secondary menu reads Open / Pause Watching / Settings / Quit while watching",
    status_menu.get("titlesWhileWatching"),
)
check(
    status_menu.get("titlesWhilePaused")
    == ["Open Focus Sentinel", "Resume Watching", "Settings\u2026", "Quit Focus Sentinel"],
    "the same menu offers Resume Watching once watching is paused",
    status_menu.get("titlesWhilePaused"),
)
# **Non-vacuity, and the whole point of the item.** A control labelled with the state it is in
# rather than the act it performs is the shape a person misreads; two identical lists would be a
# label that never followed the switch.
watching_titles = status_menu.get("titlesWhileWatching") or []
paused_titles = status_menu.get("titlesWhilePaused") or []
check(
    len(watching_titles) == len(paused_titles)
    and [a != b for a, b in zip(watching_titles, paused_titles)].count(True) == 1,
    "exactly one of the four titles follows the watching state",
    (watching_titles, paused_titles),
)

# The menu a right-click would really put on the screen, from the shipping builder.
drawn = status_menu.get("drawn") or []
check(
    [row.get("identity") for row in drawn] == status_menu.get("items"),
    "the built menu draws every declared item, in the declared order",
    [row.get("identity") for row in drawn],
)
# AppKit's automatic enabling walks the responder chain for a selector's validation, and every
# item here is bound to one method on the controller — so left at its default AppKit would enable
# all four whatever the availability predicate said.
check(
    status_menu.get("autoenablesItems") is False,
    "the secondary menu decides its own enabled states rather than letting AppKit guess",
    status_menu.get("autoenablesItems"),
)
check(
    status_menu.get("separators") == 1,
    "one separator, above Quit, where every Mac app puts it",
    status_menu.get("separators"),
)
check(
    all(row.get("hasTarget") and row.get("hasAction") for row in drawn),
    "every item in the secondary menu has something that performs it",
    drawn,
)
# The item is drawn in the state the app is really in, so the drawn titles are pinned against
# whichever of the two committed lists that state names.
expected_drawn = paused_titles if status_menu.get("sensingPaused") else watching_titles
check(
    [row.get("title") for row in drawn] == expected_drawn,
    "the titles the menu really drew are the committed ones for the state it drew them in",
    ([row.get("title") for row in drawn], status_menu.get("sensingPaused")),
)
check(
    all(row.get("isEnabled") for row in drawn),
    "every item in the secondary menu is offered, which is what its predicate answers here",
    drawn,
)
# **The route Settings… performs.** It is the app menu's own item, found by the key equivalent the
# system owns rather than by a private selector — so this says the item exists in the shipping menu
# bar. An empty string is a Settings… that would do nothing.
check(
    bool(status_menu.get("settingsMenuItemTitle")),
    "the app menu holds a \u2318, item for the secondary menu's Settings\u2026 to perform",
    status_menu.get("settingsMenuItemTitle"),
)

# --- a Dock click with the cockpit shut brings it back (focus-odz.1, D5) ----------------------
#
# D5's default is a Dock icon rather than an accessory app, and
# `applicationShouldTerminateAfterLastWindowClosed` answers `false` — so before this the app was
# reachable only from its status item after a person's first ⌘W, and the Dock icon they clicked
# did nothing at all. AppKit's own reopen could not help: a SwiftUI `Window` scene whose window has
# been closed has no `NSWindow` for AppKit to order front, which is the same measurement
# `registerCockpitOpener` exists for.
#
# The probe runs LAST in the report, because it shuts the window every reading above describes. It
# closes the cockpit, calls the delegate the way AppKit calls it — through `NSApp.delegate`, which
# with an `@NSApplicationDelegateAdaptor` in play is SwiftUI's own forwarding object, so a method
# the adaptor does not forward answers nothing here — and reads the window list back.

reopen = report.get("reopen") or {}
check(
    reopen.get("answered") is True,
    "the application answers applicationShouldHandleReopen, so a Dock click has somewhere to land",
    reopen.get("answered"),
)
# The precondition, asserted rather than assumed: a probe that never closed the window would
# report "the cockpit is visible" for a cockpit that had never gone away.
check(
    reopen.get("cockpitVisibleBeforeReopen") is False,
    "the cockpit really was shut before the Dock click was simulated",
    reopen.get("cockpitVisibleBeforeReopen"),
)
check(
    reopen.get("requestsAfter") == (reopen.get("requestsBefore") or -1) + 1,
    "the reopen asked the command centre for the cockpit exactly once",
    (reopen.get("requestsBefore"), reopen.get("requestsAfter")),
)
# `false` on purpose: the window has just been asked for, and `true` would ask AppKit to perform
# its own untitled-window behaviour on top of it.
check(
    reopen.get("returned") is False,
    "the reopen handler answered false, having opened the window itself",
    reopen.get("returned"),
)
# **The pin.** Everything above is about a request; this is the window.
check(
    reopen.get("cockpitVisibleAfterReopen") is True,
    "reopenOpensTheCockpit: a Dock click with no window open put the cockpit back on the screen",
    (reopen.get("cockpitVisibleAfterReopen"), reopen.get("visibleWindowIdentifiers")),
)
check(
    reopen.get("cockpitWindowTitleAfterReopen") == "Focus Sentinel",
    "the window that came back is the cockpit, by its title",
    reopen.get("cockpitWindowTitleAfterReopen"),
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
# The settings floor is 15 and was 14: focus-odz.3 added the version the General pane draws.
for surface, floor in [("cockpit", 18), ("settings", 15), ("help", 2)]:
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
# **An uninterpretable deck is a named fact, not a silence** (D4, focus-0nm). Deleting `playful`
# from the enum did not throw and could not: the decoder is a total switch whose `default` is the
# shipped deck, so the person's chosen voice would have become `neutral` with nothing said. The
# pair below is what "fails loudly" was ruled to mean — a reading, a logged fault, and the app
# still opens. Two readings because either alone can be green over a dead decoder: the first is
# this Mac's own row, which is normally readable, and the second drives a raw value no build will
# ever declare.
check(
    intervention_drive.get("storedVoiceWasRecognised") is True,
    "this build can read the deck the store holds, so nobody's voice was quietly reinterpreted",
    (
        intervention_drive.get("storedVoiceRaw"),
        intervention_drive.get("storedVoiceWasRecognised"),
    ),
)
check(
    intervention_drive.get("anUnreadableDeckIsReported") is True,
    "a deck this build cannot read is reported as unread and answered with the shipped deck",
    intervention_drive.get("anUnreadableDeckIsReported"),
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

# --- the one screen that says what this app looks at, shown once (focus-odz.7) ----------------
#
# A first launch installed a status item and started recording activations with nothing on screen
# saying so. Every claim the product rests on was true and reachable only by opening Settings and
# choosing the Privacy tab.
#
# **Two launches against one store, which is the only way this can be proved.** A flag set and read
# back in one process is satisfied by a plain in-memory `Bool`. The fourth launch was the first
# time the app had ever opened that store — so it was owed the explanation — and the fifth is the
# relaunch. The distinction between "a store this build created" and "a store carried forward from
# an earlier version" is the v5 → v6 migration's, and `MigrationV6Tests` holds that half.

check(
    seeded_cockpit.get("firstRunExplanationShown") is True,
    "a store the app had never opened was owed the first-run explanation, and got it",
    seeded_cockpit.get("firstRunExplanationShown"),
)
check(
    seeded_cockpit.get("firstRunExplanationDrawn") == "shown",
    "the cockpit really put the first-run explanation on the screen",
    seeded_cockpit.get("firstRunExplanationDrawn"),
)
# The showing is recorded when the app decides to show it, so the store is already stamped by the
# time this reading is taken — which is what makes the relaunch below a different launch rather
# than a second chance.
check(
    seeded_cockpit.get("firstRunExplanationOwedNow") is False,
    "showing the explanation wrote it down, in the store the next launch reads",
    seeded_cockpit.get("firstRunExplanationOwedNow"),
)
# …and the sheet was put away before the process left. A sheet still attached when NSApp.terminate
# runs is how a self-check turns into a hung gate stage — measured twice, at twenty minutes apiece.
# It is also the one lane that can drive the sink: the closure is only ever reached by a click.
check(
    seeded_cockpit.get("firstRunExplanationDismissed") is True
    and seeded_cockpit.get("firstRunExplanationStillShown") is False,
    "the explanation's dismissal reached the composition root and took the sheet down",
    (
        seeded_cockpit.get("firstRunExplanationDismissed"),
        seeded_cockpit.get("firstRunExplanationStillShown"),
    ),
)
# …and nothing is still attached at the AppKit level, which is the reading that says the process
# can leave. Measured the hard way: the first gate run that showed this sheet hung for
# twenty-eight minutes at `NSApp.terminate` with the sheet still on the window.
check(
    seeded_cockpit.get("attachedSheetsAfterDismissal") == 0,
    "no sheet is attached to any window by the time the process terminates",
    seeded_cockpit.get("attachedSheetsAfterDismissal"),
)

# **The relaunch**, against the same store. This is the claim.
check(
    relaunched_cockpit.get("firstRunExplanationShown") is False,
    "the launch after the one that explained is not owed the explanation again",
    relaunched_cockpit.get("firstRunExplanationShown"),
)
check(
    relaunched_cockpit.get("firstRunExplanationDrawn") == "hidden",
    "the relaunched cockpit drew no first-run sheet at all",
    relaunched_cockpit.get("firstRunExplanationDrawn"),
)
# Non-vacuity: the relaunch really did open the same store and draw the same window, so "hidden"
# is a decision about this store rather than a launch that drew nothing.
check(
    relaunched_cockpit.get("livePriorityIntent")
    == seeded_cockpit.get("seededPriorityIntent"),
    "the relaunch opened the same seeded store the explaining launch did",
    relaunched_cockpit.get("livePriorityIntent"),
)
check(
    relaunched_cockpit.get("drewWhatTheAppKnows") is True,
    "the relaunched cockpit drew every value the composition root handed it",
    (relaunched_cockpit.get("reading") or {}).get("summary"),
)

# --- opening at login, offered once and never on a first launch (D-12, focus-odz.4) ----------
#
# The fourth launch again, against a store this script seeded with a **finished** session as well
# as a running one — because the offer waits for a completed session, which is the first moment the
# app has done the thing it exists to do. An app that asks to be added to Login Items before it has
# been any use is asking for a commitment it has not earned.
#
# **The status is a reading, never a verdict.** Whether this Mac has the app in its Login Items is
# a fact about the machine, and a gate that required one answer would fail a developer for their
# own settings. What is pinned is the FOLD: the three inputs beside the decision, which is
# machine-independent and cannot be satisfied by a predicate that answers the same thing for every
# state.
#
# Nothing in any lane registers anything. `SMAppService.status` is a read; `register()` and
# `unregister()` write into the person's Login Items and are called by no test and no gate stage.

login_status = seeded_cockpit.get("loginItemStatus")
check(
    login_status in (seeded_cockpit.get("loginItemStatusesDeclared") or []),
    "the login-item status is one of the declared four",
    (login_status, seeded_cockpit.get("loginItemStatusesDeclared")),
)
check(
    seeded_cockpit.get("loginItemStatusesDeclared")
    == ["notRegistered", "enabled", "requiresApproval", "notFound"],
    "the login-item vocabulary is the committed four, in order and with nothing else in it",
    seeded_cockpit.get("loginItemStatusesDeclared"),
)
# The precondition the offer waits for, asserted rather than assumed: with no finished session the
# reading below would be "hidden" for a reason that has nothing to do with the rule.
check(
    isinstance(seeded_cockpit.get("loginItemCompletedSessions"), int)
    and seeded_cockpit["loginItemCompletedSessions"] >= 1,
    "the seeded store really holds a finished session for the offer to follow",
    seeded_cockpit.get("loginItemCompletedSessions"),
)
check(
    seeded_cockpit.get("loginItemAlreadyOffered") is False,
    "the seeded store has never been offered launch-at-login, so the offer is owed",
    seeded_cockpit.get("loginItemAlreadyOffered"),
)
# **The fold.** With a finished session and nothing offered, the offer is on exactly when the app
# is not registered — which is the one state in which there is anything to offer.
expected_offer = (
    login_status == "notRegistered"
    and seeded_cockpit.get("loginItemCompletedSessions", 0) >= 1
    and seeded_cockpit.get("loginItemAlreadyOffered") is False
)
check(
    seeded_cockpit.get("loginItemOfferShown") is expected_offer,
    "loginItemOfferShown: the offer follows the service's status, the history and the record",
    (seeded_cockpit.get("loginItemOfferShown"), login_status, expected_offer),
)
# …and the footer drew what the host decided. The line above is about a decision; this is the row.
check(
    seeded_cockpit.get("loginItemOfferDrawn") == ("shown" if expected_offer else "hidden"),
    "the cockpit footer drew the offer exactly when the host said to",
    (seeded_cockpit.get("loginItemOfferDrawn"), expected_offer),
)

# --- the windows a person left open, on the launch after the one that closed them (focus-odz.6)
#
# The same fourth launch, and the same reason it exists: the only reading that can tell "restored"
# from "never asked" is a second process opening a store the first one wrote. The seeding launch
# recorded that BOTH scenes were open; this launch inherits that store.
#
# **AppKit does not do this half.** It restores a window's frame, and for a SwiftUI `Window(id:)`
# scene it does not restore whether the window exists at all — measured in this very lane, where a
# launch inheriting a closed cockpit has no `NSWindow` for it in `NSApp.windows`. So a person who
# left the Keyboard Shortcuts window open and quit never got it back.
#
# The cockpit in the seeded list is the **control** and the reference is the **claim**: SwiftUI
# opens the cockpit itself, so a launch that restored nothing at all would still have one, and a
# proof resting on the cockpit alone would be green against a restoration that never ran. Nothing
# in a `--focus-self-check-cockpit` launch opens the reference.

check(
    seeded_cockpit.get("hasRestoredWindows") is True,
    "the launch ran its window restoration exactly once",
    seeded_cockpit.get("hasRestoredWindows"),
)
check(
    seeded_cockpit.get("restorationRecord") == ["cockpit", "help"],
    "the restoring launch read the window record the seeding launch wrote",
    seeded_cockpit.get("restorationRecord"),
)
# It has to be able to open one at all: a launch with no scene graph would report an empty
# restored list for a reason that is about the process rather than about the code.
check(
    seeded_cockpit.get("canOpenWindows") is True,
    "the shell installed the route that opens a declared scene by id",
    seeded_cockpit.get("canOpenWindows"),
)
check(
    "help" in (seeded_cockpit.get("restoredWindows") or []),
    "the Keyboard Shortcuts window the last quit recorded was asked for again",
    seeded_cockpit.get("restoredWindows"),
)
# **And it is really on the screen.** The three readings above are about a request; this is the
# window. A restoration that asked and was refused passes all three and fails this.
check(
    "help" in (seeded_cockpit.get("visibleSceneIdentifiers") or []),
    "restoration put the Keyboard Shortcuts window back on the screen",
    seeded_cockpit.get("visibleSceneIdentifiers"),
)
check(
    "Keyboard Shortcuts" in (seeded_cockpit.get("windowTitles") or []),
    "the window that came back is the reference, by its title",
    seeded_cockpit.get("windowTitles"),
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
# **And it is routed, not asserted** (focus-2uy.3). This was a `check`, whose own message read
# "a reading that could not be taken is NOT TAKEN" and whose mechanism was FAIL — the same
# contradiction the panel's reading-1 assertion carried, forty lines above the neighbour that
# already did it right. Measured in gate run lens6-1: the Debug launch could not read the window
# list and the Release launch of the same code could, so one gate run produced two verdicts about
# one tree, and the failing one was about the Mac.
window_count_was_taken = taken(
    "the grant-free window list",
    "sensing.windowMetadata.countWasTaken",
    "decodedKeys={!r}".format(windows_read.get("decodedKeys")),
)
if window_count_was_taken:
    check(
        isinstance(windows_read.get("count"), int) and windows_read["count"] > 0,
        "the grant-free window list returned rows",
        windows_read.get("count"),
    )

# F-32, corrected (focus-7az). This block used to assert `hardwareSeconds >= sessionSeconds`, on
# the argument that `.combinedSessionState` counts a superset of the events `.hidSystemState`
# does, so the hardware figure could never be the smaller of the two. THAT WAS NEVER TRUE OF THE
# SOURCES. At `kCGAnyInputEventType` the hardware state does not return the newest CGEvent at
# all: it returns IOHIDSystem's raw `HIDIdleTime` — measured byte-identical to `ioreg`'s across
# six paired samples — which a HID device report resets even when no input event is produced.
# Measured on this Mac 2026-09-03: hardware 105.71 s against session 14 850.04 s, four hours the
# "wrong" way, with `w` agreeing that nobody had touched the machine. Neither event set contains
# the other, so there was no ordering to assert, and asserting it turned three gate stages red
# against a machine that was telling the truth.
#
# What is true, and what goes red for a swapped or broken source: FOR EVERY CONCRETE EVENT TYPE
# THE TWO STATES ANSWER WITH THE SAME SECONDS. The divergence lives only at the `~0` sentinel.
# One second is generous for two adjacent syscalls and far too small to hide a state that has
# stopped meaning what it means, which shows up as minutes or hours.
#
# The floor is not decoration: "every row agrees" is satisfied by a report with no rows, so the
# count of DISTINCT event types read is asserted first. Distinct, so four copies of one row
# cannot stand in for four types.
idle = sensing.get("idle") or {}
IDLE_AGREEMENT_TOLERANCE = 1.0
IDLE_EVENT_TYPE_FLOOR = 4
idle_rows = idle.get("perEventType")
per_event_type = [r for r in idle_rows if isinstance(r, dict)] if isinstance(idle_rows, list) else []
idle_types_read = sorted(
    {r["eventType"] for r in per_event_type if isinstance(r.get("eventType"), str)}
)
check(
    len(idle_types_read) >= IDLE_EVENT_TYPE_FLOOR,
    f"both idle states were read for at least {IDLE_EVENT_TYPE_FLOOR} distinct concrete event types",
    idle_types_read,
)
idle_disagreements = [
    (
        r.get("eventType"),
        r.get("hardwareSeconds"),
        r.get("sessionSeconds"),
    )
    for r in per_event_type
    if not (
        isinstance(r.get("hardwareSeconds"), (int, float))
        and isinstance(r.get("sessionSeconds"), (int, float))
        and abs(r["hardwareSeconds"] - r["sessionSeconds"]) <= IDLE_AGREEMENT_TOLERANCE
    )
]
check(
    not idle_disagreements,
    f"per concrete event type the two idle states agree within {IDLE_AGREEMENT_TOLERANCE} s",
    idle_disagreements,
)
for r in per_event_type:
    print(
        f"note idle {r.get('eventType')}: hid = {r.get('hardwareSeconds')} s   "
        f"combined = {r.get('sessionSeconds')} s   difference = {r.get('differenceSeconds')} s"
    )

# The shipped `IdleReading.isIdle` evaluated on the very pair the report published, against the
# same arithmetic taken here: two readers of one rule, which is the only way a gate stage can see
# that the verdict is the MAXIMUM of the two counters and not the hardware clock alone
# (focus-7az). It is not a restatement — the left side crosses a process boundary and comes out
# of the built product. Under the rule this replaced the binary would answer `false` on this Mac
# while the line below computes `true`, and the stage would say so.
idle_threshold = idle.get("thresholdSeconds")
idle_pair_is_numeric = isinstance(idle.get("hardwareSeconds"), (int, float)) and isinstance(
    idle.get("sessionSeconds"), (int, float)
)
check(
    idle_pair_is_numeric
    and isinstance(idle.get("isIdleForThisReading"), bool)
    and isinstance(idle_threshold, (int, float))
    and idle["isIdleForThisReading"]
    == (max(idle["hardwareSeconds"], idle["sessionSeconds"]) >= idle_threshold),
    "the app's idle verdict is the longer of the two counters against the threshold",
    (
        idle.get("isIdleForThisReading"),
        idle.get("hardwareSeconds"),
        idle.get("sessionSeconds"),
        idle_threshold,
    ),
)

# And the case that discriminates the two rules on any rig at any hour. The line above is only as
# sharp as the machine it runs on: on an untouched gate rig both live counters are past the
# threshold, `max(hid, session) >= t` and `hid >= t` agree, and a build that went back to the
# hardware clock alone would pass it. So the product also evaluates its own `IdleReading.isIdle`
# on the pair the probe measured — 105.71 s of HID clock, reset by a device report nobody
# produced, beside 14 850.04 s of real quiet, at 180 s. `true` under the rule that ships and
# `false` under the rule it replaced, everywhere. The figures are asserted with the answer, so a
# report cannot get the verdict right about some other pair.
phantom = idle.get("phantomHidPair") or {}
check(
    phantom.get("hardwareSeconds") == 105.71
    and phantom.get("sessionSeconds") == 14850.04
    and phantom.get("thresholdSeconds") == 180,
    "the app judged the measured phantom-HID pair, 105.71 s against 14850.04 s at 180 s",
    (
        phantom.get("hardwareSeconds"),
        phantom.get("sessionSeconds"),
        phantom.get("thresholdSeconds"),
    ),
)
check(
    phantom.get("isIdle") is True,
    "a hardware clock reset by a phantom HID report does not make an absent person present",
    phantom.get("isIdle"),
)
# The `~0` sentinel's gap, published and never asserted: it is the signature of a phantom HID
# reset, it can run to hours in either direction on a machine nobody has touched, and it is the
# number that explains a verdict rather than a verdict of its own.
print(
    f"note idle hardware-minus-session at the ~0 sentinel = "
    f"{idle.get('hardwareMinusSessionSeconds')} s "
    f"(hid {idle.get('hardwareSeconds')} s, combined {idle.get('sessionSeconds')} s, "
    f"threshold {idle.get('thresholdSeconds')} s, "
    f"verdict for this pair {idle.get('isIdleForThisReading')}, "
    f"last sampled belief {idle.get('isIdle')})"
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
# **And it goes through the same door as the other three** (focus-2uy.3). It had the only
# not-taken branch in the file and it also had its own bespoke shape: a `suppressed` flag, a
# string compared by hand, and a `print` that counted a stand-down as coverage. A stand-down is
# still a reading nobody took — the quorum's three inputs are unavailable either way — so it is
# a NOT TAKEN line like every other, and which of the two obstacles it was travels in the reason.
presentation = sensing.get("presentation") or {}
if taken(
    "the presentation quorum's three inputs",
    "sensing.presentation.wasTaken",
    "a stand-down is the gate working and 'nothing is frontmost' is the graph knowing nothing; "
    "the reason above says which, and neither is a reading of the person's screen",
):
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
# --- the twelve states, read as a RUN rather than as the enum's codomain ----------------------
#
# THIS BLOCK REPLACES A CHECK THAT COULD NOT GO RED. It read, once per capability:
#
#     entry["state"] in {"available","denied","restricted","unavailable","notRequested"}
#
# under the pass line "carries one of the five declared states". Those five strings are the whole
# of `CapabilityState`, a `String`-backed `CaseIterable` enum whose `rawValue` is one of them by
# construction — so all twelve lines were satisfied by every value the type can hold, and no
# behaviour of the app or the machine could turn one red. It is focus-652's shape exactly (*"the
# value is one of the N values its own enum is total over"*), still standing twelve rows wide one
# repair after that one was deleted.
#
# It also could not see the edit that actually matters, which is a **case joining or leaving the
# vocabulary**: adding `.pending` to `CapabilityState` widened every one of the twelve lines and
# failed none of them.
#
# Two readings replace it, and each has a state it goes red in.
#
# 1 — **The vocabulary, pinned in both directions.** The app publishes
# `CapabilityState.allCases`; this is the committed literal, in declaration order, and a case
# added, removed or renamed fails it.
COMMITTED_CAPABILITY_STATES = [
    "available", "denied", "restricted", "unavailable", "notRequested"
]
check(
    report.get("capabilityStatesDeclared") == COMMITTED_CAPABILITY_STATES,
    "the capability vocabulary is the committed five, in order and with nothing else in it",
    report.get("capabilityStatesDeclared"),
)

# 2 — **Every state is the one the RULE produces, over the whole matrix.**
#
# `PlatformCapabilityProbe.states()` is nine decisions and three measurements. The nine are
# constants of the build; the three are computed from readings this same report publishes
# independently — the grant-free window list, the idle clock and the audio device enumeration —
# and the fourth input, the display count, is read here through AppKit rather than through the
# probe's own `SystemScreenList`, so the comparison is between two readings and not a mirror.
#
# The rule is restated here on purpose. That is the whole value of the leg: the matrix is what the
# Settings Privacy pane draws, and a probe that stopped probing and answered `.available` twelve
# times would have passed every line this block replaced.
# e06. Read here as well as in the relevance block below, because the capability row is decided
# from it: one reading, two readers, so the matrix and the tier can never be two opinions.
model_tier_reading = ((report.get("relevance") or {}).get("modelTier")) or {}

display_count = sensing.get("displayCount")
input_devices = (sensing.get("media") or {}).get("inputDeviceCount")
hardware_seconds = (sensing.get("idle") or {}).get("hardwareSeconds")
window_rows = windows_read.get("count")

CAPABILITY_RULE_CONSTANTS = {
    # The bundle identifier rides on the activation notification; no platform state withholds it.
    "frontmostApplication": "available",
    # The lock primary is a public notification and subscribing to it needs nothing.
    "systemLifecycle": "available",
    # Pinned on every rig, camera or not: the held path was never entered (P-97/P-104, R-40).
    "cameraActivity": "unavailable",
    # Parked by the Court (D-04): there is nothing to probe because there is nothing to use.
    "screenCapture": "unavailable",
    # This epic has not asked, and in this epic it never will. Reporting `denied` for a question
    # nobody put would be inventing a refusal.
    "accessibilityWindowContext": "notRequested",
    "notifications": "notRequested",
}
# The three the machine decides, each with the reading it is decided from. A reading that was not
# taken makes its row unpredictable rather than wrong, so the row is routed rather than asserted.
CAPABILITY_RULE_MEASURED = {
    # **e06 moved this row out of the constants and it is not a weakening.** `notRequested` was
    # a decision of e03's build — *"this epic has not asked, and in this epic it never will"* —
    # and it stopped being true the moment the app could read
    # `SystemLanguageModel.default.availability`. What decides it now is the machine, so it
    # belongs with the machine-decided rows, and the reading it is decided from is the model
    # tier's own — which the block further down pins for internal consistency, so this row
    # cannot agree with a `modelTier` reading that disagrees with itself.
    "onDeviceModel": (
        bool(model_tier_reading),
        model_tier_reading.get("capabilityState"),
    ),
    "windowMetadata": (
        window_count_was_taken,
        "available" if isinstance(window_rows, int) and window_rows > 0 else "unavailable",
    ),
    # The quorum's only input that can be unavailable is the window list, so it takes the same
    # answer — which is also the pair that would come apart if one of them were special-cased.
    "presentation": (
        window_count_was_taken,
        "available" if isinstance(window_rows, int) and window_rows > 0 else "unavailable",
    ),
    "idle": (
        isinstance(hardware_seconds, (int, float)),
        "available" if isinstance(hardware_seconds, (int, float)) else "unavailable",
    ),
    "displayGeometry": (
        isinstance(display_count, int),
        "available" if isinstance(display_count, int) and display_count > 0 else "unavailable",
    ),
    "microphoneActivity": (
        isinstance(input_devices, int),
        "available" if isinstance(input_devices, int) and input_devices > 0 else "unavailable",
    ),
}
# **The self-referential completeness check.** The rule and the matrix must name the same twelve,
# in both directions: a capability added to `Capability` with no rule here is a row this script
# never checked, and a rule here for a capability the app no longer reports is a rule about
# nothing.
check(
    set(CAPABILITY_RULE_CONSTANTS) | set(CAPABILITY_RULE_MEASURED)
    == set(EXPECTED_CAPABILITIES),
    "the rule this script states covers exactly the capabilities the app reports",
    sorted(
        (set(CAPABILITY_RULE_CONSTANTS) | set(CAPABILITY_RULE_MEASURED))
        ^ set(EXPECTED_CAPABILITIES)
    ),
)
by_capability = {c.get("capability"): c.get("state") for c in capabilities}
for capability, expected in sorted(CAPABILITY_RULE_CONSTANTS.items()):
    check(
        by_capability.get(capability) == expected,
        f"{capability} is {expected}, which is a decision of this build",
        by_capability.get(capability),
    )
for capability, (was_read, expected) in sorted(CAPABILITY_RULE_MEASURED.items()):
    if not was_read:
        not_taken(
            f"the {capability} row of the capability matrix",
            "the reading the probe computes it from was not taken",
            by_capability.get(capability),
        )
        continue
    check(
        by_capability.get(capability) == expected,
        f"{capability} is {expected}, which is what this machine's own reading says",
        (by_capability.get(capability), expected),
    )
# **The non-vacuity guard.** Every line above is satisfied by a matrix that answers the same thing
# for everything, which is exactly what a probe that stopped probing produces. The guard is a
# reading of the REPORT: a check over this script's own literals cannot fail while the literals
# are what they are, and a check that cannot fail is not one.
check(
    len(set(by_capability.values())) >= 3,
    "the matrix the app reported is not one answer repeated twelve times",
    sorted(set(by_capability.values())),
)
# **What this would still be green for**, stated rather than left to be re-derived: a probe that
# reads the right inputs and files them under the wrong capability name would agree with a rule
# restated the same wrong way, because both are written from `PlatformCapabilityProbe.states()`.
# What it cannot survive is the failure this block exists for — a matrix that has stopped being a
# measurement — because the three measured rows are compared against readings taken by other
# instruments in this same report.

# Nothing this epic actually uses may sit at `notRequested`: that state means "we have not asked
# yet", and in e03 the app never asks at all, so a facility it uses reporting it would mean the
# probe never ran.
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

# **The scan is a reading, and an empty scan is NOT TAKEN** (focus-2vi's treatment, applied to
# the other consumer of the same call).
#
# THIS BLOCK REPLACES A CHECK THAT COULD NOT GO RED. It was one line —
# `authorisationSurfaces == []` — with the owner count printed beside it as a NOTE that nothing
# asserted. `SystemWindowList.copyWindowInfo()` answers `[]` when the window server declines or
# the cast fails; the suspect list is then empty for the same reason a clean Mac's is, and the
# strongest form of R-33 prints green for a reading nobody took. Not hypothetical: gate run
# `lens6-1` recorded this call answering the Release launch and refusing the Debug one of the same
# tree, which is why `sensing.windowMetadata` grew `countWasTaken` in focus-2vi — and this
# consumer of the identical call never got the same treatment.
#
# Three readings replace it, and each has a state it goes red in:
#
#   1. the scan HAPPENED    — an empty owner list is routed through the one NOT-TAKEN door
#   2. the instrument could SEE — it listed a window belonging to this very process, which is on
#      the screen by construction because the shell self-check brought the cockpit forward. Gut
#      `SystemWindowList` to return `[]` and reading 1 goes NOT TAKEN; make it blind to our own
#      windows and this goes red rather than quiet.
#   3. and only then, the verdict: not one owner is a process macOS puts a dialog up through.
scan = report.get("authorisationSurfaceScan") or {}
if taken(
    "the on-screen authorisation-surface scan",
    "authorisationSurfaceScan.wasTaken",
    "owners={!r}".format(scan.get("owners")),
):
    check(
        (scan.get("windowsOwnedByThisProcess") or 0) > 0,
        "the scan listed a window belonging to this very process, so the instrument can see",
        {
            "windowsOwnedByThisProcess": scan.get("windowsOwnedByThisProcess"),
            "ownProcessIdentifier": scan.get("ownProcessIdentifier"),
            "ownerCount": scan.get("ownerCount"),
        },
    )
    check(
        scan.get("suspects") == [],
        "no authorisation surface is on screen while the app runs",
        scan.get("suspects"),
    )
    # The two flat keys the evidence set names are the same two facts, and they are asserted to
    # be — a report whose root drifted away from the scan it summarises would be two answers.
    check(
        report.get("authorisationSurfaces") == scan.get("suspects")
        and report.get("onScreenWindowOwners") == scan.get("owners"),
        "the root's summary of the scan is the scan",
        (report.get("authorisationSurfaces"), report.get("onScreenWindowOwners")),
    )
    print(f"note {scan.get('ownerCount')} on-screen window owner(s) scanned")

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
    committed_executable_rungs > 0 and committed_declared_rungs > 0,
    "the committed ladder lengths were found in EvaluationPolicy",
    (committed_executable_rungs, committed_declared_rungs),
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
# --- e06: the model tier, as three facts that must agree -----------------------------------
#
# **The pin is two independent witnesses of one decision.** `composesTheRung` is a constant a
# person could edit; `executableRungs` is what the engine's composed ladder actually holds, and
# `EvaluationPolicy.executableRungCeiling` — read out of the evaluation policy the same way the
# stamp and the digest are read out of their suites — is what the shipping gate requires of the
# lane-1 report. A build that flipped the constant without composing anything, or composed
# something without flipping it, fails here rather than merely disagreeing with itself.
#
# The availability is NOT pinned to a value: it is a fact about the machine the self-check ran
# on, and pinning it would pin a fact about one Mac. What is pinned is that it is one of the
# named cases and that the tier's three readings are consistent with each other.

model_tier = relevance.get("modelTier") or {}

check(
    bool(model_tier),
    "the running application reports a model-tier reading",
    model_tier,
)
check(
    model_tier.get("availability") in (
        "available", "appleIntelligenceNotEnabled", "modelNotReady",
        "deviceNotEligible", "suppressedByResources", "unknown",
    ),
    "the model availability is one of the six named cases",
    model_tier.get("availability"),
)
check(
    model_tier.get("availabilityIsExecutable")
        == (model_tier.get("availability") == "available"),
    "only `available` is executable, whatever this Mac said",
    (model_tier.get("availability"), model_tier.get("availabilityIsExecutable")),
)
check(
    model_tier.get("capabilityState")
        == ("available" if model_tier.get("availability") == "available" else "unavailable"),
    "the capability matrix row follows the availability, and is never `denied`",
    model_tier.get("capabilityState"),
)

# **Witness one.** The programme decision, and the reason travels with it so a reader never has
# to go and find out why the tier is not composed.
check(
    model_tier.get("composesTheRung") is False,
    "this build does not compose the model rung — " + str(model_tier.get("notComposedReason")),
    model_tier.get("composesTheRung"),
)
check(
    bool(model_tier.get("notComposedReason")),
    "the decision not to compose carries its reason",
    model_tier.get("notComposedReason"),
)

# **Witness two, independent of the first.** What the engine actually composed. This is a
# reading of the running ladder, not of the constant above, and the two are required to agree.
check(
    model_tier.get("rungIsComposed") is model_tier.get("composesTheRung"),
    "the composed ladder agrees with the release decision",
    (model_tier.get("rungIsComposed"), model_tier.get("composesTheRung")),
)
check(
    model_tier.get("executableRungs") == committed_executable_rungs,
    f"the running ladder holds {committed_executable_rungs} executable rungs",
    model_tier.get("executableRungs"),
)
check(
    model_tier.get("declaredRungs") == committed_declared_rungs,
    f"the declared ladder is still {committed_declared_rungs} rungs long",
    model_tier.get("declaredRungs"),
)
# And the stamp's own component, which is what a verdict cache would key on. A build with no
# prompt has no prompt version, and `s1.p3.l1.e1.m0` is the stamp the gate pins.
check(
    model_tier.get("promptVersion") == 0,
    "the engine stamps promptVersion 0 — a build with no composed prompt has no prompt",
    model_tier.get("promptVersion"),
)

check(
    relevance.get("sessionRuleCount") == 0,
    "the session rule box is empty — nothing wrote to it without a person pressing something",
    relevance.get("sessionRuleCount"),
)

# --- retention: the app forgets, and it forgets the right things (F-115, focus-tzj.3) --------
#
# Three tables grew without bound. `ActivityEventStore` said so in its own doc comment and
# deferred a policy to a later epic; `InterventionLog.purge(before:)`, `QueryLedger.purge(...)`
# and `purgeAll()` were written, tested, and called by NOTHING. A privacy posture that is only a
# plan is not a posture, so the mechanism ships now and e07 §5 puts a picker on top of it.
#
# TWO HALVES, and the second is why the first is worth reading. The launch half says the sweep
# ran, on which local day, and what it removed — which on a gate machine whose store holds
# nothing older than ninety days is three zeroes and a date, and a sweep deleted from the launch
# path entirely would publish the same three zeroes. So the binary also runs the SAME sweep over
# a store it seeds with one row at 89 days and one at 91 in each table that dies of age, and
# publishes both sides of that boundary.
retention = report.get("retention") or {}
check(
    retention.get("windowDays") == 90,
    "the committed retention window is ninety days",
    retention.get("windowDays"),
)
check(
    retention.get("ranAtLaunch") is True
    and isinstance(retention.get("lastRunDay"), str)
    and len(retention.get("lastRunDay") or "") == 10,
    "the retention sweep ran at launch and says which local day it ran on",
    (retention.get("ranAtLaunch"), retention.get("lastRunDay")),
)
check(
    isinstance(retention.get("rowsRemoved"), int) and retention["rowsRemoved"] >= 0,
    "the launch sweep says how many rows it removed",
    retention.get("rowsRemoved"),
)
# The non-vacuity control, and the whole reason this section can go red on a store with nothing
# old in it: the mechanism the launch used, shown cutting exactly where it says it cuts.
check(
    retention.get("seedAvailable") is True,
    "the seeded retention sweep ran",
    retention.get("seedError", retention.get("seedAvailable")),
)
check(
    retention.get("seededActivityEventsRemoved") == 1
    and retention.get("seededActivityEventsKept") == 1,
    "an activity event at 91 days goes and one at 89 stays",
    (retention.get("seededActivityEventsRemoved"), retention.get("seededActivityEventsKept")),
)
check(
    retention.get("seededInterventionRowsRemoved") == 1
    and retention.get("seededInterventionRowsKept") == 1,
    "an intervention row at 91 days goes and one at 89 stays",
    (retention.get("seededInterventionRowsRemoved"), retention.get("seededInterventionRowsKept")),
)
# **The exception, and it is U-1's.** A receipt is what gate 11 reads, so deleting one puts a
# question the person has already answered back on the ladder. The seeded receipt is 91 days old
# and its priority was created a moment ago, so it must survive the window it is outside.
check(
    retention.get("seededQueryReceiptsRemoved") == 0
    and retention.get("seededQueryReceiptsKept") == 1,
    "a 91-day-old receipt under a live priority survives the window",
    (retention.get("seededQueryReceiptsRemoved"), retention.get("seededQueryReceiptsKept")),
)
print(
    "note retention: window {} days, last run {}, {} row(s) removed at launch".format(
        retention.get("windowDays"),
        retention.get("lastRunDay"),
        retention.get("rowsRemoved"),
    )
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
# **And this is what it means to say the authorisation was *read*** (focus-652).
#
# The line here used to be `notificationAuthorisation in ("authorised","denied","notRequested",
# "provisional")` — the entire codomain of an exhaustive switch whose `default` arm is one of the
# four. No integer the OS can send fails it, so no change to the decode could turn it red; and its
# sentence claimed a read had happened, which it could not see. `refresh()` is asynchronous, and
# `notRequested` was BOTH the OS's "never asked" and the field's pre-completion default, so the
# check's value set was exactly the union of both sides of an unsequenced read. Four numbers from
# one machine at one commit: notRequested, notRequested, authorised, notRequested.
#
# The read is now awaited, counted, and reported as `"unread"` when it did not land — and the
# thing pinned is the DECODE, folded over every raw status and compared with the committed table.
check(
    report.get("notificationAuthorisationReads", 0) >= 1,
    "getNotificationSettings was really read: at least one completion landed",
    report.get("notificationAuthorisationReads"),
)
# **And the report WAITED for it rather than racing it.**
#
# This lane could not make this assertion at all until the key was lifted to the root beside the
# other four. `Reads >= 1` above is the weaker half of one repair: a completion that landed while
# the report was already being assembled satisfies it, and that is exactly the race focus-652
# measured — notRequested, notRequested, authorised, notRequested at one commit on one machine.
# `notification-denied` has asserted this since focus-652 and it runs against the **Debug**
# product; this script is the only reader of the notification boundary on the **Release** one, so
# without this line the artefact that ships had the weaker of the two readings.
check(
    report.get("notificationAuthorisationWasRead") is True,
    "the report waited for that read rather than racing it",
    report.get("notificationAuthorisationWasRead"),
)
check(
    report.get("notificationAuthorisation") != "unread",
    "the run had a decoded authorisation in hand rather than the absence of one",
    report.get("notificationAuthorisation"),
)
check(
    bool(committed_decode_table) and committed_decode_cells.isdigit(),
    "the committed decode table was found in NotificationDeliveryTests",
    (committed_decode_table, committed_decode_cells),
)
# The size of the fold before the fold's verdict: an equality over a table can be satisfied by
# shrinking both sides together, and the count is the half that cannot be.
check(
    report.get("notificationAuthorisationDecodeCells") == int(committed_decode_cells or -1),
    f"the boundary folded all {committed_decode_cells} raw statuses it can be handed",
    report.get("notificationAuthorisationDecodeCells"),
)
check(
    report.get("notificationAuthorisationDecodeTable") == committed_decode_table,
    "the running boundary decodes every raw status exactly as the committed table says",
    report.get("notificationAuthorisationDecodeTable"),
)
print(f"note this Mac reports {report.get('notificationAuthorisation')!r}")

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
# **The comparison is taken here, from the two numbers, rather than believed** (focus-bkf). This
# row read `fullest.isTheCommittedWidth is True` — a boolean the binary under audit computes about
# itself, so a layout function that had stopped honouring the commitment could go on reporting
# that it had. The arithmetic is the same one `check-focus-steal.sh:337-345` already does for the
# panel; the published flag is then asserted to AGREE with it, which is a reading of the binary's
# own comparison rather than a substitute for one.
POPOVER_WIDTH_TOLERANCE = 1.0
fullest_popover = popover.get("fullest") or {}
fullest_width = fullest_popover.get("width")
committed_popover_width = popover.get("committedWidth")
fullest_is_committed = (
    isinstance(fullest_width, (int, float))
    and isinstance(committed_popover_width, (int, float))
    and abs(fullest_width - committed_popover_width) <= POPOVER_WIDTH_TOLERANCE
)
check(
    fullest_is_committed,
    "the fullest popover is laid out at the committed width, at any priority length",
    (fullest_width, committed_popover_width),
)
check(
    fullest_popover.get("isTheCommittedWidth") is fullest_is_committed,
    "the popover's own width verdict agrees with the width it reported",
    (fullest_popover.get("isTheCommittedWidth"), fullest_width, committed_popover_width),
)
# **And what gives way when it will not fit** (focus-din).
#
# `scrolls` alone could not tell a surface a person can decide on from one that has parked the
# ladder: the popover's actions were inside the scroll view, so any popover that scrolled had its
# corrections below the fold, `DecisionSurfaceReachability` correctly refused the charge, nothing
# re-took the reading when the person scrolled, and a large-text user's badge rung was never
# delivered at all. The surface pins its decision now, and this is where the running binary says
# which of the three ways it gave way.
#
# The value is asserted against the vocabulary rather than against one of its members, because
# which one is right depends on the display the gate happens to run on — a machine too small to
# show the actions must read `everythingScrolls`, and requiring otherwise would be requiring the
# gate's own screen to be big.
#
# **And the vocabulary is the binary's, pinned, rather than this script's copy of it** (focus-bkf).
# Written as membership in a set spelled out here, this row was the whole codomain of a
# `CaseIterable` decoder: no state the product can be in falsifies it, which is exactly the shape
# focus-652 deleted one repair earlier — and this one runs on the RELEASE artefact. So the running
# binary publishes its cases, the list is pinned in both directions against the committed literal
# (a case leaving is as red as a case joining, `ladderSilencesDeclared`'s reason), and the
# membership below reads the published list rather than a set this file could quietly widen.
COMMITTED_POPOVER_OVERFLOWS = ["everythingScrolls", "nothingScrolls", "theContextScrolls"]
check(
    popover.get("overflowsDeclared") == COMMITTED_POPOVER_OVERFLOWS,
    "every way the popover can give way is a folded, named case",
    popover.get("overflowsDeclared"),
)
declared_overflows = popover.get("overflowsDeclared") or []
for popover_case in ("empty", "fullest"):
    measured = popover.get(popover_case) or {}
    check(
        bool(declared_overflows) and measured.get("overflow") in declared_overflows,
        f"the {popover_case} popover says which way it gives way",
        (measured.get("overflow"), declared_overflows),
    )
    check(
        measured.get("scrolls") is (measured.get("overflow") != "nothingScrolls"),
        f"the {popover_case} popover's scroll flag and its overflow are one fact",
        (measured.get("scrolls"), measured.get("overflow")),
    )
    check(
        measured.get("decisionIsInTheViewport")
        is (measured.get("overflow") != "everythingScrolls"),
        f"the {popover_case} popover's decision is in the viewport unless nothing could be",
        (measured.get("decisionIsInTheViewport"), measured.get("overflow")),
    )
    print(
        "note popover {}: {} x {}, {}".format(
            popover_case,
            measured.get("width"),
            measured.get("height"),
            measured.get("overflow"),
        )
    )

# **An open popover is not rebuilt by the clock** (focus-tzj.1).
#
# `MenuBarController.update(_:)` is called on every accepted activation and every five-second
# corroboration tick, and while the popover was open each of those assigned a freshly built
# `NSHostingController` — plus the two `popoverLayout(measuring:)` builds behind it. Measured
# before the repair: 3 hosting controllers per tick, 36 per minute, for a surface whose every
# input was the value it already had; and each rebuild re-stamped the layout generation, which
# discards the action frames `decisionSurfaceReading(of:)` reads, so the popover a person was
# looking at was briefly unchargeable once per tick.
#
# The reading is the binary's own counters — assignments to `popover.contentViewController`, not
# requests for one — taken over twenty ticks in which the presentation moved exactly twice.
popover_rebuild = popover.get("rebuild") or {}
rebuild_ticks = popover_rebuild.get("ticks")
rebuild_changes = popover_rebuild.get("presentationChanges")
rebuild_unchanged = popover_rebuild.get("unchangedTicks")
rebuild_builds = popover_rebuild.get("contentBuilds")
rebuild_on_unchanged = popover_rebuild.get("buildsOnUnchangedTicks")
rebuild_hosts = popover_rebuild.get("hostingConstructions")
# **Non-vacuity first.** Every row under it is a statement about ticks that did not build, and a
# survey that ticked nothing would satisfy all of them. So the ticks have to exist, more of them
# than there were changes, and the presentation has to have really moved.
check(
    isinstance(rebuild_ticks, int) and isinstance(rebuild_changes, int)
    and isinstance(rebuild_unchanged, int)
    and rebuild_changes > 0
    and rebuild_unchanged > 0
    and rebuild_ticks == rebuild_changes + rebuild_unchanged,
    "the popover rebuild survey really ticked, and most of its ticks changed nothing",
    (rebuild_ticks, rebuild_changes, rebuild_unchanged),
)
check(
    rebuild_on_unchanged == 0,
    "a tick that changes nothing rebuilds nothing",
    (rebuild_on_unchanged, rebuild_unchanged),
)
check(
    isinstance(rebuild_builds, int)
    and isinstance(rebuild_changes, int)
    and rebuild_builds <= rebuild_changes,
    "the popover's content is built at most once per presentation change",
    (rebuild_builds, rebuild_changes),
)
# And the amplification, because the build count is a third of the cost: one host for the content
# and one for each of the two measurements. Pinned as an identity rather than a ceiling, so a
# fourth construction joining the build path is as red as the three going away.
check(
    isinstance(rebuild_hosts, int)
    and isinstance(rebuild_builds, int)
    and rebuild_builds > 0
    and rebuild_hosts == 3 * rebuild_builds,
    "each popover build costs three hosting controllers, and nothing else builds one",
    (rebuild_hosts, rebuild_builds),
)
print(
    "note popover rebuild: {} ticks, {} changes, {} builds, {} hosting controllers".format(
        rebuild_ticks, rebuild_changes, rebuild_builds, rebuild_hosts
    )
)

# **A tick that changes nothing costs the store almost nothing** (focus-tzj.2).
#
# The five-second corroboration tick fetched what could not have moved:
# `PriorityStore.recentTasks(limit:)` read EVERY `PriorityTask` in the table and sorted them in
# Swift to draw a list of eight, and `NudgeMemory.reading` folded today's whole intervention log
# and looked for a query receipt BEFORE gate 1 was consulted — so somebody with no commitment at
# all paid for both, twelve times a minute, for ever. Measured on the survey's own store before
# the repair: 4 fetches per tick with no commitment and 5 with one. None of that shows up in a
# stopwatch on a store with four rows in it, which is why the reading is a count.
#
# The survey drives the tick's two store-touching halves — `PriorityHost`'s projection and
# `NudgeMemory.reading` — on a store of its own, in three states, ten ticks each.
tick_fetches = nudge.get("tickFetches") or {}
check(
    tick_fetches.get("available") is True,
    "the per-tick fetch survey ran",
    tick_fetches.get("error", tick_fetches.get("available")),
)
TICK_STATES = ("noCommitment", "commitmentPopoverClosed", "commitmentPopoverOpen")
for tick_state in TICK_STATES:
    row = tick_fetches.get(tick_state) or {}
    steady_ticks = row.get("steadyTicks")
    first_fetches = row.get("firstTickFetches")
    steady_fetches = row.get("fetchesOverSteadyTicks")
    steady_nudge = row.get("nudgeFetchesOverSteadyTicks")
    steady_popover = row.get("popoverFetchesOverSteadyTicks")
    # **Non-vacuity, per state and first.** Every row under this one is a ceiling on ticks that
    # fetch little or nothing, and a survey whose store answered nothing at all — or which never
    # ticked — would satisfy every one of them.
    check(
        isinstance(steady_ticks, int) and steady_ticks >= 2
        and isinstance(first_fetches, int) and first_fetches > 0,
        f"the {tick_state} tick survey really ticked, and its first tick really fetched",
        (steady_ticks, first_fetches),
    )
    check(
        isinstance(steady_fetches, int)
        and isinstance(steady_ticks, int)
        and steady_fetches <= 2 * steady_ticks,
        f"a quiet {tick_state} tick costs at most two fetches",
        (steady_fetches, steady_ticks),
    )
    # The half this bead moved the guard in front of. With no commitment neither read is even
    # asked for; with one, both are answered from a cache keyed on their store's own write count,
    # and a tick writes nothing.
    check(
        steady_nudge == 0,
        f"the nudge half of a quiet {tick_state} tick goes to the store not at all",
        (steady_nudge, steady_ticks),
    )
    check(
        steady_popover == 0,
        f"building the popover's content on a {tick_state} tick touches no store",
        steady_popover,
    )
    print(
        "note tick fetches {}: first {}, {} over {} quiet ticks".format(
            tick_state, first_fetches, steady_fetches, steady_ticks
        )
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
# **The vocabulary, pinned rather than searched.** This read `"unopened" in dispositionsDeclared`
# — a membership test, so a fifth disposition appearing, or any of the other three disappearing,
# was invisible to it. The set is what the whole record is made of and what `spendsBudget` is a
# predicate on, so it is pinned in both directions beside the cap claim above it.
check(
    nudge.get("dispositionsDeclared") == [
        "deferred", "delivered", "suppressed", "unopened"
    ],
    "the record's dispositions are exactly these four, one of which is a badge nobody opened",
    nudge.get("dispositionsDeclared"),
)

# **THE FLOOR, in the running application** (focus-d6r).
#
# The three checks above are the ceiling's: they watch for something that starts charging. These
# are their twin, and the epic had none — every proof in it answered "did the app charge for
# something nobody saw?" and not one answered "on a day of sustained drift, did the app ever
# speak?". The consequence was live and measured: `InterventionLog.budget` summed the day's
# interruptions on `spendsBudget`, so eight ambient glyph landings spent the whole shared budget,
# and that budget is the conjunct in `remaining(for:)` that binds BOTH kinds. At eight landings
# `permits(.accusation)` and `permits(.query)` were both false, `accusationsToday` was nought, and
# the panel rung — the only rung that carries a sentence, a subject and the whole correction
# economy — could not be raised for the rest of that local day.
#
# Named rather than counted, for `dispositionsSpendingACap`'s reason: the danger is not how many
# rungs there are but WHICH ones charge, and `["panel"]` says which one it is. A third rung above
# the panel that accuses somebody joins both lists; the glyph joins neither, because it accuses
# nobody, asks nobody anything, and R-87 keeps it on through a snooze precisely because it is a
# state and not a sentence.
check(
    nudge.get("rungsSpendingTheAccusationCap") == ["panel"],
    "only the rung that accuses somebody spends one of the day's accusations",
    nudge.get("rungsSpendingTheAccusationCap"),
)
check(
    nudge.get("rungsSpendingTheInterruptionCap") == ["panel"],
    "only the rung that says something spends one of the day's interruptions",
    nudge.get("rungsSpendingTheInterruptionCap"),
)
# **AND WHICH GATES ARE EVEN ABOUT THE GLYPH** (focus-0y6, focus-uru).
#
# The two above are about what a rung COSTS. These are the same rule one level up: what may
# SILENCE it. Three consecutive repairs applied that ruling to one more gate and left the next —
# focus-2yy's commit message enumerates "gates 1, 2 and 3 ... gate 5", focus-0y6's triage walked
# twelve gates and ruled on each, and both skipped gate 4 — because a closed set swept by reading
# prose is not swept. Asserted here as three exact sets, so a thirteenth gate classified by
# copying its neighbour is a diff in these lines rather than a silence in the menu bar.
check(
    nudge.get("gatesPassingOverTheGlyph")
    == ["alreadyAsked", "interruptionInFlight", "mediaInUse", "quietHours"],
    "the gates about the app SPEAKING pass over the rung that says nothing",
    nudge.get("gatesPassingOverTheGlyph"),
)
check(
    nudge.get("gatesDeferringTheGlyph") == ["presentationActive"],
    "the one gate that defers the glyph is the one where the menu bar is not on screen",
    nudge.get("gatesDeferringTheGlyph"),
)
# The other side, so this is not a lint that could be satisfied by exempting the glyph from
# everything: a mark the app cannot have earned must still be stopped.
check(
    nudge.get("gatesSilencingTheGlyph")
    == [
        "budgetExhausted",
        "noActivePriority",
        "sensingPaused",
        "sensitiveApplication",
        "sessionPhaseForbids",
        "userIdle",
        "verdictDoesNotAuthorise",
    ],
    "the gates about there being anything to be legible about still stop the glyph",
    nudge.get("gatesSilencingTheGlyph"),
)
# Gate 10 does not classify; its detail vocabulary does, and exactly one of the six may take the
# status item — a correction, after which there is nothing left to be off task about.
check(
    nudge.get("fatigueRefusalsSilencingTheGlyph") == ["corrected"],
    "the only fatigue refusal that stops the glyph is the person saying it is real work",
    nudge.get("fatigueRefusalsSilencingTheGlyph"),
)
# **And the other two thirds of the partition** (focus-2uy.5).
#
# The suppression vocabulary a few lines above publishes all three of its parts — silencing,
# passing and deferring — and the fatigue vocabulary published one. A partition published as one of
# its parts is a partition nothing can check: a seventh refusal ruled `.theAppSpeaking` joins no
# published set, leaves the line above exactly as it is, and is invisible to every reading the
# Release lane takes. The identity is what makes the three mean something together.
check(
    nudge.get("fatigueRefusalsPassingTheGlyph")
    == ["backedOff", "cap", "cooldown", "heldAtAmbient", "snoozed"],
    "the five refusals about the app SPEAKING all pass the rung that says nothing",
    nudge.get("fatigueRefusalsPassingTheGlyph"),
)
# Empty **by ruling**, not by accident: `FatigueDecision` has two cases and no third, so a
# deferral is the suppression stack's answer to give and `FatigueRefusal.Kind.subject` is never
# `.theSurfaceBeingOnScreen`.
check(
    nudge.get("fatigueRefusalsDeferringTheGlyph") == [],
    "no fatigue refusal defers a rung: a deferral is the stack's answer, not this vocabulary's",
    nudge.get("fatigueRefusalsDeferringTheGlyph"),
)
FATIGUE_PARTS = (
    (nudge.get("fatigueRefusalsSilencingTheGlyph") or [])
    + (nudge.get("fatigueRefusalsPassingTheGlyph") or [])
    + (nudge.get("fatigueRefusalsDeferringTheGlyph") or [])
)
check(
    sorted(FATIGUE_PARTS) == (nudge.get("fatigueRefusalsDeclared") or [])
    and len(FATIGUE_PARTS) == len(set(FATIGUE_PARTS)),
    "the three fatigue readings partition the declared refusals: each one in exactly one part",
    (nudge.get("fatigueRefusalsDeclared"), FATIGUE_PARTS),
)

# --- the day itself, and the four readings that were true of an empty one (focus-hqf) ----------
#
# A whole shared budget's worth of landings must leave the app able to speak. THE FOUR ASSERTIONS
# THIS BLOCK REPLACES WERE ALL SATISFIED BY A DAY ON WHICH NOTHING HAPPENED. The app folded
# `dailyInterruptionCap` ambient landings through `InterruptionCharge.init?(_:)`, which guards on
# `spendsTheInterruptionCap` — false for an ambient landing, by design — so the `compactMap`
# yielded an empty array and the budget being priced was `InterruptionBudget.empty`. Nought
# interruptions, nought accusations and both permissions still true are exactly what an empty
# budget answers. Measured against the Release `FocusCore.o` of gate run `floorgate-1`: charges
# folded 0, `identical to .empty` true; the same fold over the panel rung folded 8. The reading's
# own `landings` field said `8`, and it was a constant.
#
# It is `NudgeFloorTests`' own rule 3 — *non-vacuity is asserted in both directions* — written in
# the same round, thirty lines of prose away, and not kept by the binary twin of that suite.
#
# **One fold over the whole rung vocabulary**, and a table stated here that says what each rung's
# day costs. The rung that spends nothing and the rung that spends everything are two rows of one
# reading rather than a claim and a control written beside each other, so neither can be edited
# without the other.
day_by_rung = nudge.get("budgetAfterADayOfLandings") or {}
DAY_COST_BY_RUNG = {
    # The glyph carries no sentence and accuses nobody: `spendsTheInterruptionCap` is false for it
    # and a whole day of it must cost nothing.
    "ambient": 0,
    # The panel is the only rung that speaks, so a whole day of it must exhaust the day. This is
    # the row that makes the row above evidence: it is the same three lines of arithmetic, and a
    # fold that has stopped building charges at all turns it red.
    "panel": "every landing",
}
# **The self-referential completeness check.** The table and the app's rung vocabulary must name
# the same rungs, in both directions: a rung added with no row here is a day this script never
# priced, and a row here for a rung the ladder no longer has is a rule about nothing.
check(
    set(DAY_COST_BY_RUNG) == set(nudge.get("budgetAfterADayOfLandingsRungs") or [])
    and set(day_by_rung) == set(DAY_COST_BY_RUNG),
    "this script prices exactly the rungs the ladder declares",
    sorted(set(DAY_COST_BY_RUNG) ^ set(nudge.get("budgetAfterADayOfLandingsRungs") or [])),
)
for rung, cost in sorted(DAY_COST_BY_RUNG.items()):
    row = day_by_rung.get(rung) or {}
    landings = row.get("landings")
    expected = landings if cost == "every landing" else cost
    check(
        isinstance(landings, int) and landings > 0,
        f"the {rung} day was a day: the fold ran over a whole shared budget's worth of landings",
        row,
    )
    check(
        row.get("chargesFolded") == expected,
        f"a day of {rung} landings builds {cost} charge(s) — stated, never inferred from an "
        "empty budget",
        row,
    )
    check(
        row.get("interruptionsToday") == expected,
        f"and the {rung} day's charges were priced by the shipping arithmetic",
        row,
    )
# **The non-vacuity guard.** Every line above is satisfied by a table in which every rung folds
# nothing — which is precisely the state that produced this bead. The rows must therefore
# disagree with each other: one rung costs nothing and one costs the whole day.
folded = {rung: (day_by_rung.get(rung) or {}).get("chargesFolded") for rung in DAY_COST_BY_RUNG}
check(
    0 in folded.values() and any(
        value == (day_by_rung.get(rung) or {}).get("landings") and value
        for rung, value in folded.items()
    ),
    "the table discriminates: one rung's day costs nothing and another's costs the whole day",
    folded,
)
# What it would still be green for, stated: a rung whose `spendsTheInterruptionCap` answer is
# wrong in the SAME direction as this table's expectation, because both are written from
# `InterruptionCharge.init?(_:)`. What it can no longer be green for is the failure it exists for
# — an arithmetic that folded nothing at all.

glyph_day = nudge.get("budgetAfterADayOfGlyphLandings") or {}
check(
    glyph_day.get("accusationsToday") == 0,
    "a whole day of glyph landings spends none of the day's accusations",
    glyph_day,
)
check(
    glyph_day.get("permitsAccusation") is True,
    "after a whole day of glyph landings the app can still accuse somebody",
    glyph_day,
)
check(
    glyph_day.get("permitsQuery") is True,
    "after a whole day of glyph landings the app can still ask somebody something",
    glyph_day,
)
check(
    (day_by_rung.get("panel") or {}).get("permitsAccusation") is False,
    "and a whole day of PANEL landings does exhaust it, so the three lines above mean something",
    day_by_rung.get("panel"),
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
# **Named, not counted** (focus-gtr). A count fails on an exit joining or leaving and passes on
# one being swapped for another or renamed — which is the same half-claim `querySurface in (…)`
# made about the router, and the same half-claim `"unopened" in dispositionsDeclared` made below.
# The set is small, closed and committed, so it is pinned in both directions.
check(
    nudge.get("questionExitsDeclared") == [
        "answered", "neverDelivered", "screenReclaimed", "surfaceWentOutOfReach", "worldMovedOn"
    ],
    "every way an open question can end is enumerated, and they are exactly these five",
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

# **And a rung's ending is a vocabulary too** (focus-s4m).
#
# The two checks above have held the question's exits closed since focus-h0s. The accusation's
# were SIX HAND-WRITTEN DOORS and this file said nothing about them, which is this round's
# instance of the shape every bead in this sequence has: a treatment one half received and the
# other did not. Two of the six told the ladder nothing at all — `hideOverlays()` left it at
# `.engaged(rung: .panel, deliveredAt:)`, where `candidate(at:budgetPermits:)` answers `nil` for
# ever, so ⌃⌘H permanently silenced the only rung that says anything.
#
# **Six**, and exact equality rather than a floor, for `questionExitsDeclared`'s reason: a floor
# cannot see an exit being removed. The sixth is `worldMovedOn` — a session ending, a break, a
# commitment change or a quit — which nobody had counted as a door at all.
check(
    nudge.get("rungExitsDeclared") == [
        "answered", "displayStranded", "presentationWithdrew", "replaced", "screenReclaimed",
        "worldMovedOn"
    ],
    "every way a delivered rung can end is enumerated, and they are exactly these six",
    nudge.get("rungExitsDeclared"),
)
# **And exactly the two that mean the app took the surface away withdraw the delivery** (R-81).
#
# Named rather than counted. `displayStranded` had its take-back before this round and is the
# calibration; `presentationWithdrew` is the one whose own doc comment promised it and whose code
# did nothing. `screenReclaimed` is deliberately NOT here: the person saw the panel — they pressed
# a key to make it go away — so withdrawing the row would say nobody was shown anything, and
# putting the ladder back where it stood would put the same panel in front of them at the next
# mandate. It is completed `ignored` and counted against both backoffs instead.
check(
    nudge.get("rungExitsTakingBackTheDelivery") == ["displayStranded", "presentationWithdrew"],
    "exactly the endings where the app took the surface away un-deliver the rung",
    nudge.get("rungExitsTakingBackTheDelivery"),
)
# **And exactly the two endings the PERSON authored advance the backoffs** (focus-fzf, focus-fwy).
#
# Named in both directions, like the take-backs above. `screenReclaimed` is somebody pressing ⌃⌘H
# at the nudge; `replaced` is somebody drifting straight past a panel and never touching it —
# focus-fwy's own argument, *a person who never touches a nudge advances neither run*, which was
# held out for a round by a measurement rather than by a ruling. `answered` is deliberately NOT
# here (`resolve(…)` has already counted the click, and a second would count one dismissal twice),
# nor are the two take-backs (R-81: an un-delivery cannot be an ignore) or `worldMovedOn` (ending
# a session is not ignoring a nudge).
check(
    nudge.get("rungExitsCountingAnIgnoredAccusation") == ["replaced", "screenReclaimed"],
    "exactly the endings the person authored advance the two ignored-accusation runs",
    nudge.get("rungExitsCountingAnIgnoredAccusation"),
)

# **The ladder's own silence is a vocabulary with a subject** (focus-628, focus-50m, focus-1ua).
#
# `SilenceSubject`'s doc states the rule absolutely — *every reason the app has for going quiet
# declares its subject here* — and names the two exhaustive switches that enforce it. The ladder
# was the third answer to the same question and was in neither: not `CaseIterable`, no subject,
# and silencing by ARITHMETIC. `candidate(at:budgetPermits:)` answered `nil` for four different
# reasons, `NudgeDecider.accuse(…)` reported all four as `.budgetExhausted`, and **the glyph went
# with them** — including from `.heldAtAmbient`, whose own doc says *"it does not go fully silent:
# the glyph still tells the truth"*.
#
# Exact equality on both, and both directions, for `rungExitsDeclared`'s reason: a floor cannot
# see a case being removed, and the set below is the one that decides whether a held ladder marks
# anybody at all.
check(
    nudge.get("ladderStatesDeclared") == ["engaged", "heldAtAmbient", "idle"],
    "every state the ladder can be in is a folded, named case",
    nudge.get("ladderStatesDeclared"),
)
check(
    nudge.get("ladderSilencesDeclared")
    == ["budgetRefused", "escalationDwell", "heldAtAmbient", "noLiveMandate", "toppedOut"],
    "every reason the ladder has for having nothing to climb to is enumerated",
    nudge.get("ladderSilencesDeclared"),
)
# The two that still owe the person the mark, named. `escalationDwell` and `toppedOut` are
# deliberately absent — the rung the ladder delivered is still standing in both, and re-delivering
# it through a dwell would restart the very clock the dwell measures, so the ladder would never
# climb again. `noLiveMandate` is absent for the opposite reason: with no mandate there is nothing
# to be off task about, and a mark that went on marking would not be telling the truth.
check(
    nudge.get("ladderSilencesRetainingTheGlyph") == ["budgetRefused", "heldAtAmbient"],
    "exactly the ladder's refusals still owe the person the rung that says nothing",
    nudge.get("ladderSilencesRetainingTheGlyph"),
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
# focus-my0's other half. The type system holds "no charge from a reading taken mid-turn"; nothing
# but a wrapper holds "every door into the loop opens a turn", so this is the reading that says the
# wrapper is on all of them. Zero by construction today and falsifiable by mutation: delete
# `turn.run` from any entry point and this goes non-zero on the next drive that reaches it.
check(
    nudge.get("proofsOfferedOutsideATurn") == 0,
    "every proof was offered inside a turn, so every charge was settled at its own seam",
    nudge.get("proofsOfferedOutsideATurn"),
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
# **PINNED, IN BOTH DIRECTIONS, OVER THE WHOLE SPACE** (focus-3vb). This line was
# `"notification" not in surfacesARungCanReach`, and it failed in two independent ways at once.
#
# A membership test cannot see a surface APPEARING. Route every rung to the badge, or to a fifth
# surface added tomorrow, and `not in` stays green — it can only ever notice the one name written
# in it. The subject of this reading is a SET, and the only honest assertion about a set is the
# set.
#
# And the set it searched was two cells wide: `routes` asks each rung exactly once at
# `.notPresenting`, `.idle`, `reducedInterruption: false`, `menuBarVisible: true`,
# `voice: .standard`. A notification route reachable under Reduce Motion, a running microphone,
# `silentVisual` or a hidden menu bar was invisible to it — and because `notification-denied` runs
# against the DEBUG product, this was the only "no notification" reading taken at the artefact this
# programme ships.
#
# It is now the same 128-cell fold `accusationRouteCellsChecked` counts, over every rung instead of
# the accusing ones. The honest answer is THREE surfaces: `popoverBadge` is genuinely reachable
# under exactly the conditions the two-cell table pinned away. A reading that said two was not a
# stronger claim; it was a narrower one.
# **One space, named once.** `SelfCheck.routeSpace` is the enumeration both folds are taken over —
# presenting × mic × flag × menuBar × deck — and the rung fold multiplies it by the rungs. Spelling
# it this way is what makes the two numbers below unable to drift apart, which is the arithmetic
# form of the defect this pair of readings is a repair for.
# The deck factor was 5 and is 4 (focus-0nm retired `playful`): this is the space the binary
# folds, so it moves with the vocabulary or a retired deck reads as a fold that shrank.
ROUTE_SPACE_CELLS = 2 * 2 * 2 * 2 * 4  # presenting × mic × flag × menuBar × deck
EVERY_RUNG_ROUTE_CELLS = 2 * ROUTE_SPACE_CELLS  # × the two rungs D-06-as-amended declares
check(
    nudge.get("surfacesARungCanReachCellsChecked") == EVERY_RUNG_ROUTE_CELLS,
    f"the surfaces-a-rung-reaches fold covers all {EVERY_RUNG_ROUTE_CELLS} cells rather than two",
    nudge.get("surfacesARungCanReachCellsChecked"),
)
# **And a count of cells VISITED is satisfied by a fold in which every cell deferred**
# (focus-2uy.4). Conservation, so the two halves check each other: a fold that stopped visiting
# cells and a fold that stopped reaching surfaces are different failures and one number reported
# neither.
check(
    nudge.get("surfacesARungCanReachCellsChecked")
    == (nudge.get("surfacesARungCanReachCellsDelivered") or 0)
    + (nudge.get("surfacesARungCanReachCellsDeferred") or 0),
    "every cell of the every-rung fold either reached a surface or deferred",
    (
        nudge.get("surfacesARungCanReachCellsChecked"),
        nudge.get("surfacesARungCanReachCellsDelivered"),
        nudge.get("surfacesARungCanReachCellsDeferred"),
    ),
)
# **And which surfaces offer the person a way to answer at all** (focus-3vb).
#
# The predicate `accusationRouteAudit()` turns on, pinned in both directions rather than published
# and read by nothing. `.notification` was `true` here — "the presentation's actions, as
# notification buttons" — describing a banner nothing can post: no rung routes there since U-2 and
# P-134 measured `add(_:)` failing at zero grants. With that cell true, the one whole-space fold
# the RELEASE binary runs could not see the one outcome U-2 forbids:
# `everyAccusationRouteCanBeAnswered` would have stayed green with every accusation on a banner.
check(
    nudge.get("surfacesOfferingAnAnswer") == ["panel", "popoverBadge"],
    "exactly the two in-app decision surfaces offer the person a way to answer back",
    nudge.get("surfacesOfferingAnAnswer"),
)
check(
    nudge.get("surfacesARungCanReach") == ["menuBar", "panel", "popoverBadge"],
    "over the whole input space a rung reaches the glyph, the panel and the badge — and nothing "
    "else, so no rung reaches a notification",
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
ACCUSATION_ROUTE_CELLS = 1 * 2 * 2 * 2 * 2 * 4  # rung × presenting × mic × flag × menuBar × deck
check(
    nudge.get("accusationRouteCellsChecked") == ACCUSATION_ROUTE_CELLS,
    f"the accusation-route fold covers all {ACCUSATION_ROUTE_CELLS} cells rather than a subset",
    nudge.get("accusationRouteCellsChecked"),
)
# **The verdict below is a claim about the cells that REACHED a surface** (focus-2uy.4).
#
# `accusationRouteCellsChecked` counts loop iterations, and it was the whole of the anti-vacuity
# control: a fold in which every single cell deferred reports exactly the same 80. Measured at the
# Release binary of gate run `vocabgate-1`, 56 of the 80 defer — a presentation, a hidden menu bar,
# a running microphone — so `everyAccusationRouteCanBeAnswered` was a claim about **24** cells
# published under a count of 80.
#
# Two assertions, and they fail for different edits: the conservation identity catches a fold that
# lost a cell, and the floor catches a fold that stopped reaching surfaces. The floor is a floor
# and not an equality for `Config/test-floors.txt`'s reason — a route that starts delivering where
# it used to defer must not redden the gate, and one that stops delivering must.
# **Re-measured after `playful` was retired** (focus-0nm). The space went from 80 cells to 64 and
# the delivering cells from 24 to 19; the floor moves with the vocabulary rather than standing
# still, because a floor that outlived its space would report a user ruling as a broken route. The
# coefficients are the two measurements solved together: five delivering cells per copy deck, four
# for the routing one.
ACCUSATION_ROUTE_DELIVERED_FLOOR = 19  # measured; 19 of 64, the other 45 deferring
check(
    nudge.get("accusationRouteCellsChecked")
    == (nudge.get("accusationRouteCellsDelivered") or 0)
    + (nudge.get("accusationRouteCellsDeferred") or 0),
    "every cell of the accusation-route fold either reached a surface or deferred",
    (
        nudge.get("accusationRouteCellsChecked"),
        nudge.get("accusationRouteCellsDelivered"),
        nudge.get("accusationRouteCellsDeferred"),
    ),
)
check(
    (nudge.get("accusationRouteCellsDelivered") or 0) >= ACCUSATION_ROUTE_DELIVERED_FLOOR,
    f"at least {ACCUSATION_ROUTE_DELIVERED_FLOOR} of the fold's cells reach a surface, so the "
    "answerability verdict is a claim about something",
    nudge.get("accusationRouteCellsDelivered"),
)
check(
    nudge.get("everyAccusationRouteCanBeAnswered") is True,
    "every accusation route offers the person a way to answer back",
    nudge.get("accusationRoutesWithNoWayToAnswer"),
)
# --- where a QUESTION goes, over the whole space and pinned in both directions ------------------
#
# THIS BLOCK REPLACES A CHECK THAT COULD NOT GO RED. It was:
#
#     nudge["querySurface"] in ("panel", "popoverBadge")
#
# under the pass line *"a question routes to an in-app surface and never to a notification"* — and
# it is the defect focus-3vb deleted from the rung's half of this same router, one repair earlier,
# left standing in the question's half. Both failures are in that one line. A membership test
# cannot see a surface **appearing**: route every question to a notification and this stays green
# for as long as the one cell it reads still answers `panel`. And the one cell it read was
# `.notPresenting`, `.idle`, `reducedInterruption: false`, `menuBarVisible: true`, `.standard` —
# the plainest conditions in the space.
#
# The 30-cell `queryRoutes` table below it was wider on three axes and blind on two: it varied
# deck, flag and media and pinned presentation and menu-bar visibility, which are exactly the two
# axes the rung's fold had just gained. Two folds over one router, each blind to what the other
# saw. There is one space now — `SelfCheck.routeSpace` — and both audits are taken over it.
#
# The single cell survives as a **literal**, because the settings pane describes that row and a
# person reads it.
check(
    nudge.get("querySurface") == "panel",
    "the row the settings pane describes routes a question to the panel",
    nudge.get("querySurface"),
)
# The size of the fold before the fold's verdict (R-96o's shape), and it is the SAME space the
# rung fold is taken over, divided by the rungs — so the two numbers cannot drift apart.
EVERY_QUERY_ROUTE_CELLS = ROUTE_SPACE_CELLS
check(
    nudge.get("surfacesAQuestionCanReachCellsChecked") == EVERY_QUERY_ROUTE_CELLS,
    f"the surfaces-a-question-reaches fold covers all {EVERY_QUERY_ROUTE_CELLS} cells rather "
    "than one",
    nudge.get("surfacesAQuestionCanReachCellsChecked"),
)
# **Pinned in both directions.** A surface leaving this set fails as loudly as one joining it, and
# `notification` joining it is what U-2 forbids and what the membership test could not see.
check(
    nudge.get("surfacesAQuestionCanReach") == ["panel", "popoverBadge"],
    "over the whole input space a question reaches the panel and the badge, and nothing else — "
    "so no question reaches the glyph and none reaches a notification",
    nudge.get("surfacesAQuestionCanReach"),
)
check(
    nudge.get("everyQueryRouteCanCarryAQuestion") is True,
    "every cell routes a question to a surface that can actually carry one",
    nudge.get("queryCellsThatCannotCarryAQuestion"),
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

# --- delete everything: declared, held, never pressed (e07a, focus-6pr.3) ----------------------
#
# The Privacy pane's one destructive verb is the one action in the application this script may
# not drive: it destroys the person's store and relaunches the app. What can be asserted here is
# the review's I-4 — the pane's action vocabulary is exactly one case, so a second button that
# would be an ask in disguise is a red line rather than a surprise — and that the window handed
# the composition root a sink for it. The effect is witnessed in the unit lane against a store
# the test owns (`DeleteEverythingWitnessTests`): sentinels present in -wal while open, absent
# from every byte of the directory afterwards.
check(
    rendering.get("privacyActionsDeclared") == ["deleteEverything"],
    "the Privacy pane's action vocabulary is exactly deleteEverything",
    rendering.get("privacyActionsDeclared"),
)
check(
    rendering.get("privacySinkHeld") is True,
    "the Settings window handed back the sink the Privacy pane's control reaches",
    rendering.get("privacySinkHeld"),
)

# --- a question answered with no mouse (e07a, U-1, F-145) --------------------------------------
#
# U-1 licenses the interruption BECAUSE the question is cheaply answerable, and until e07a it was
# answerable only by a click: the panel is a `.nonactivatingPanel` that is never made key, so no
# keystroke reaches it from the application the person is in, and its Escape reaches their
# editor. The route is the View menu — one ⌘-Tab to Focus, then ⌃⌘Y, ⌃⌘U or ⌃⌘L — and the
# unit lane folds the predicate and drives `NudgeHost.perform(_:)`. What only the running
# application can say is read here, from the SIXTH launch: that activating the application
# leaves the question standing (the plan's blocker, measured on a real activation), that the
# item AppKit drew is enabled with a question and withdrawn without one, and that the key handed
# to `NSApp.mainMenu` reaches the ledger — a receipt and a rule, not a menu item.
#
# The ordinary report carries the same block as NOT TAKEN, because it runs against the person's
# own store and the reading writes to the store it runs against. Both facts are asserted: the
# ordinary launch must NOT have taken it, and the owned-store launch MUST have.

keyboard = (report.get("nudge") or {}).get("keyboardAnswer") or {}
check(
    keyboard.get("wasTaken") is False,
    "the ordinary launch did not answer a question in the person's own store",
    keyboard,
)
taken(
    "the keyboard answer to a question, in the ordinary launch",
    "nudge.keyboardAnswer.wasTaken",
    "asserted on the owned-store launch below instead",
)

kb = keyboard_launch.get("keyboardAnswer") or {}
check(
    keyboard_launch.get("mode") == "nudge" and bool(kb),
    "the owned-store launch ran the nudge block and reported the keyboard-answer reading",
    (keyboard_launch.get("mode"), sorted(kb)),
)
check(
    kb.get("wasTaken") is True,
    "the keyboard-answer reading was taken against the owned store",
    (kb.get("wasTaken"), kb.get("notTakenBecause")),
)
check(kb.get("mainMenuExists") is True, "the headless launch had a main menu to hand a key to")
check(
    kb.get("questionOpened") is True and kb.get("worldReportsAQuestion") is True,
    "a real question opened through the loop and the command world reported it",
    (kb.get("questionOpened"), kb.get("worldReportsAQuestion")),
)
# THE BLOCKER, MEASURED. The route is one ⌘-Tab away only if coming forward leaves the question
# standing. Two facts, and the first is the control for the second: the activation must really
# have happened — this process was launched headless and became frontmost — or "the question
# survived" is a fact about a process that never moved.
check(
    kb.get("activationWasObserved") is True,
    "activating the application really brought this process to the front",
    (kb.get("frontmostBeforeActivation"), kb.get("frontmostAfterActivation")),
)
# `NSApp.isActive` is reported and not pinned: measured on this Mac, a process launched headless
# with only a non-activating panel on screen reads `isActive == false` for the whole fifteen-second
# poll while `NSWorkspace.frontmostApplication` names it — and the frontmost reading is the one the
# sensing graph hears, which is what a ⌘-Tab is to the loop.
print(
    "note keyboard-answer activation: isActive={} attempts={} sensing observing={}".format(
        kb.get("applicationBecameActive"), kb.get("activationAttempts"), kb.get("sensingWasObserving")
    )
)
check(
    kb.get("questionSurvivedActivation") is True and kb.get("panelSurvivedActivation") is True,
    "activating the application (a ⌘-Tab to Focus) leaves the open question and its panel standing",
    (kb.get("questionSurvivedActivation"), kb.get("panelSurvivedActivation")),
)
# The item AppKit drew, on both sides of the question. Leg 2 of focus-6uf's reading, for the
# three answers, in the state that offers them — which the ordinary launch never is. Taken the way
# AppKit takes it: SwiftUI pushes a changed `.disabled(…)` into the item only when the menu's
# delegate is asked `menuNeedsUpdate(_:)`, which AppKit does before a tracking session and before a
# key-equivalent search (measured, e07a — `itemsAsLastDrawn*` in the report is the stale read).
ANSWER_ITEMS = {"nudge.answerYes", "nudge.answerNo", "nudge.answerNotNow"}
enabled_with = kb.get("itemsEnabledWithQuestion") or {}
enabled_without = kb.get("itemsEnabledWithoutQuestion") or {}
check(
    set(kb.get("answerItemsDeclared") or []) == ANSWER_ITEMS,
    "the registry declares exactly the three answering items this script names",
    kb.get("answerItemsDeclared"),
)
check(
    set(enabled_with) == ANSWER_ITEMS and all(enabled_with.get(i) is True for i in ANSWER_ITEMS),
    "with a question open, all three answering items are enabled in the View menu",
    enabled_with,
)
check(
    set(enabled_without) == ANSWER_ITEMS and all(enabled_without.get(i) is False for i in ANSWER_ITEMS),
    "with the question answered, all three answering items are withdrawn from the View menu",
    enabled_without,
)
# THE EFFECT. Not that an item claimed the key — that the question ended and the ledger holds
# what the title promised: a receipt reading answeredRelevant and a task rule reading relevant,
# both on the subject the question was about (R-78's one transaction).
check(kb.get("keySent") is True, "⌃⌘Y was sent through NSApplication.sendEvent with a question open", kb.get("keySent"))
check(
    kb.get("commandsObservedOnPress") == ["answerYes"],
    "the key reached the command centre as exactly one answerYes",
    kb.get("commandsObservedOnPress"),
)
check(
    kb.get("questionOpenAfterPress") is False and kb.get("panelVisibleAfterPress") is False,
    "⌃⌘Y ended the question and took its panel down",
    (kb.get("questionOpenAfterPress"), kb.get("panelVisibleAfterPress")),
)
check(
    kb.get("receiptsBeforePress") == 0 and kb.get("receiptsAfterPress") == 1,
    "⌃⌘Y wrote exactly one receipt",
    (kb.get("receiptsBeforePress"), kb.get("receiptsAfterPress")),
)
check(
    kb.get("receiptOutcome") == "answeredRelevant" and kb.get("receiptSubject") == kb.get("subject"),
    "the receipt is the answer the title promised, on the subject the question was about",
    (kb.get("receiptOutcome"), kb.get("receiptSubject"), kb.get("subject")),
)
check(
    kb.get("rulesBeforePress") == 0 and kb.get("rulesAfterPress") == 1,
    "⌃⌘Y wrote exactly one task rule",
    (kb.get("rulesBeforePress"), kb.get("rulesAfterPress")),
)
check(
    kb.get("ruleVerdict") == "relevant" and kb.get("ruleSubject") == kb.get("subject"),
    "the rule is the verdict the title promised, on the subject the question was about",
    (kb.get("ruleVerdict"), kb.get("ruleSubject"), kb.get("subject")),
)
# And the same key with nothing to answer writes nothing — the refusal the unit lane makes on
# `perform(_:)`, seen through the menu bar. Whether AppKit refreshed the item and never delivered
# the key, or delivered it to a stale item for the loop to refuse, is printed and not pinned: the
# fact a person is owed is that nothing was written.
print("note second ⌃⌘Y with no question: commands observed {}".format(kb.get("commandsObservedOnSecondPress")))
check(
    kb.get("keySentWithoutQuestion") is True,
    "⌃⌘Y was sent again with no question open",
    kb.get("keySentWithoutQuestion"),
)
check(
    kb.get("receiptsAfterSecondPress") == 1 and kb.get("rulesAfterSecondPress") == 1,
    "a second ⌃⌘Y with no question open wrote nothing",
    (kb.get("receiptsAfterSecondPress"), kb.get("rulesAfterSecondPress")),
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
# **Was it taken, and only then: did it move** (focus-2vi, focus-2uy.3). One assertion used to
# carry both questions, and when `NSWorkspace.shared.frontmostApplication` came back nil at both
# ends it printed `got: ('', '')` — a message about the frontmost application not being
# byte-identical, for a pair of readings in which there was no frontmost application to be
# identical to. The nil now serialises as `null` and is asked about first, by name.
#
# **And it is asked by the NOT-TAKEN branch below, not by a `check` here** (focus-2uy.3). Its own
# title said "nil frontmost is NOT TAKEN" and it was written as a `check`, which is a FAIL: the
# title named the mechanism and the code named a defect. `deltaReadingWasTaken` now carries
# "the front was never read" as its first case, so this reading is taken in exactly one place and
# an unread front costs the run a NOT TAKEN line rather than three failures of R-89.

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
if taken(
    "R-89's four focus deltas around the nudge panel",
    "nudge.panel.deltaReadingWasTaken",
    "reading 1 was READ before={!r} after={!r}; reading 3 (the panel is not the key "
    "window) was taken absolutely and passed; the absolute form of the rest is the "
    "focus-steal stage".format(
        before.get("frontmostBundleIdentifier"), after.get("frontmostBundleIdentifier")
    ),
):
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
# **The sweep: every reading the machine may refuse to give goes through the one door**
# (focus-2uy.3, repair doctrine clause 2).
#
# The class this closes is not "one probe had no branch". It is that a probe's takenness was a
# thing each probe remembered, so three of them grew a branch over three rounds and two never did
# — and both of the two were what made this gate red for a fact about who was using the Mac.
#
# So the fold is over the REPORT, not over a list kept here: every key in the self-check JSON
# whose name ends in `WasTaken`, and every dictionary in it carrying a bare `wasTaken`, is a
# reading that says it may be unavailable, and every one of them must have been routed through
# `taken(...)`. A probe added tomorrow with a `wasTaken` and no branch fails this line; a probe
# that loses its takenness fact fails the floor below it.
takenness_facts = set()


def sweep_takenness(node, path=""):
    if isinstance(node, dict):
        for key, value in node.items():
            here = f"{path}.{key}" if path else key
            if key == "wasTaken" or (key.endswith("WasTaken") and isinstance(value, bool)):
                takenness_facts.add(here)
            sweep_takenness(value, here)
    elif isinstance(node, list):
        for index, value in enumerate(node):
            sweep_takenness(value, f"{path}[{index}]")


sweep_takenness(report)
unrouted = sorted(takenness_facts - routed_readings)
check(
    not unrouted,
    "every reading that can be unavailable is routed through the one NOT-TAKEN mechanism",
    unrouted,
)
# **The non-vacuity floor.** The check above is satisfied by a report with no takenness facts at
# all, which is exactly what deleting the pair from a probe produces — the reading goes back to
# being a `check` that fails for the machine, and the sweep says nothing. Six probes publish
# one today; the floor is those six, named, so losing one is a red run rather than a quieter one.
EXPECTED_TAKENNESS_FACTS = {
    "undo.menuReadingWasTaken",
    "sensing.windowMetadata.countWasTaken",
    "sensing.presentation.wasTaken",
    "nudge.panel.deltaReadingWasTaken",
    # The fifth, and it is the one this floor was built to catch: the authorisation-surface scan
    # reads the SAME `CGWindowListCopyWindowInfo` as `sensing.windowMetadata` and had no takenness
    # fact at all, so an empty scan passed as "no dialog on screen".
    "authorisationSurfaceScan.wasTaken",
    # The sixth (e07a): the keyboard answer writes to the store it runs against, so the ordinary
    # launch may not take it and says why; the owned-store launch is asserted separately.
    "nudge.keyboardAnswer.wasTaken",
}
check(
    EXPECTED_TAKENNESS_FACTS <= takenness_facts,
    "every probe that may be unavailable still publishes whether its reading was taken",
    sorted(EXPECTED_TAKENNESS_FACTS - takenness_facts),
)
# And that the routing is not a set nobody put anything in: a `taken(...)` that stopped being
# called would leave `routed_readings` short while the sweep above still passed on a report whose
# facts had gone with it.
check(
    routed_readings >= EXPECTED_TAKENNESS_FACTS,
    "every one of those six readings was actually routed on this run",
    sorted(EXPECTED_TAKENNESS_FACTS - routed_readings),
)

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
