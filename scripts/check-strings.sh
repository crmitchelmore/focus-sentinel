#!/bin/zsh
# String externalisation — the F-149 lint.
#
#   scripts/check-strings.sh
#
# Two checks, both of which fail the gate:
#
#   1. **No hardcoded user-visible string.** A bare string literal in a SwiftUI position that
#      draws text — `Text("…")`, `Label("…"`, `Button("…"`, `.navigationTitle("…")`,
#      `.help("…")`, `.accessibilityLabel("…")`, `Picker("…"`, `Toggle("…"` — is a string
#      that can never be translated and never be pseudo-localised. `Text(verbatim:)` is
#      *not* a violation: it is the explicit way to draw something that is data rather than
#      prose (a file path, a ⌘W glyph), and spelling it out is the point.
#
#   2. **The catalogs and the code agree.** Every key in a module's String Catalog must be
#      referenced by that module's sources, and every catalog key a module's sources name
#      must exist in that module's catalog. A key present but unused is dead text; a key
#      used but absent resolves to itself at runtime, which is the exact failure mode the
#      lane-gated localisation tests exist to catch.
#
# ## The key convention this lint depends on
#
# A catalog key begins with one of the namespaces in NAMESPACES **and** has at least three
# dot-separated components: `<namespace>.<surface>.<element>`. That is what makes check 2
# decidable — without it a lint cannot tell the key `shell.help.heading` from the SF Symbol
# name `cup.and.saucer.fill`, nor from the action identifier `shell.closeWindow`, and would
# either miss real breakage or fail on every glyph in the repository. A new namespace is
# added to NAMESPACES below.
#
# The convention governs the *reverse* direction only (a key used in code must exist in the
# catalog). The forward direction — every catalog key must be referenced — is checked over
# the catalog itself and holds whatever a key is called.
#
# Modules are checked separately, because each resolves its own catalog against its own
# bundle: `FocusUI` cannot see the app's catalog and the app cannot see `FocusCore`'s.
#
# ## Why `App/Localizable.xcstrings` has no keys in it
#
# The app target is a composition root. It declares scenes and wires concrete types to
# protocols; every string a person can read — window titles included — is owned by `FocusUI`
# and reached through `ShellStrings`, which resolves against `FocusUI`'s bundle. So the app's
# own catalog is legitimately empty, and it is kept rather than deleted because it is the
# declared home for anything the app target ever does own, and because deleting it would take
# the `App` row out of the table below and with it the only check that notices the day an
# app-target source starts naming a catalog key. An empty catalog with a live assertion over
# it is a guard; no catalog at all is a blind spot.
#
# That is what `EXPECTS_NO_STRINGS` below enforces: the app target must keep declaring and
# referencing zero keys. A module in that list which grows a key fails the gate, and the fix
# is to move the string to `FocusUI` — or, if it genuinely belongs to the app target, to take
# the module out of the list deliberately.
set -u

REPO_ROOT="${0:A:h}/.."
cd "$REPO_ROOT" || exit 1

rc=0

print "== hardcoded user-visible strings"

typeset -a SOURCE_ROOTS
SOURCE_ROOTS=(App Packages/FocusCore/Sources Packages/FocusRules/Sources
              Packages/FocusClassify/Sources Packages/FocusSensing/Sources
              Packages/FocusUI/Sources)

# `Text(` is matched only when the literal follows immediately, so `Text(verbatim: "…")` and
# `Text(someResource)` are untouched.
#
# Two of these are not SwiftUI at all, and e02 is why (R-29). `setActionName("…")` is the
# string the **system Edit menu** draws after "Undo"; it is the most user-visible text in the
# undo journal and it is set from `FocusCore`, where nobody would think to look for prose.
# `placeholderString = "…"` is an AppKit text field's prompt — the capture panel is an
# `NSPanel`, so its placeholder can bypass every SwiftUI-shaped pattern above. Both are drawn
# to a person, so both must be String Catalog keys.
LITERAL_PATTERN='(Text|Label|Button|Picker|Toggle|TextField|Stepper)\("|\.(navigationTitle|help|accessibilityLabel|accessibilityHint|accessibilityValue|windowTitle)\("|setActionName\("|placeholderString[[:space:]]*=[[:space:]]*"'

hits=$(grep -rnE "$LITERAL_PATTERN" "${SOURCE_ROOTS[@]}" --include='*.swift' 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|///|\*|/\*)')

if [[ -n "$hits" ]]; then
    print -u2 "FAIL [F-149] a user-visible string is hardcoded rather than taken from a String Catalog:"
    print -u2 "$hits" | sed 's/^/    /'
    print -u2 "    Use ShellText(_:) with a ShellStringKey, or Text(verbatim:) if it is data rather than prose."
    rc=1
else
    print "ok   no bare string literal in a text-drawing position"
fi

print
print "== catalog completeness"

python3 - "$REPO_ROOT" <<'PYTHON'
import json
import os
import re
import sys

root = sys.argv[1]

# e03 adds three namespaces (plan R-52). `session.` and `capability.` are `FocusUI`'s, for the
# session surfaces and the capability matrix; `sensing.` is `FocusUI`'s too, for the pause
# switch and the sensing status line. `FocusCore` keeps only the `undo.` and `status.` keys it
# already owns — the session machine returns typed values, and the labels for them live in the
# UI package where every other user-visible string does.
#
# e04 adds five, and all five are **`FocusCore`'s**, which is a departure worth stating: the
# relevance vocabulary — the cascade ladder, the explanation clauses, the suppression reasons,
# the evidence bands and the per-app dispositions — is declared in `FocusCore` because `FocusUI`
# may not import `FocusClassify` (plan R-53), and a surface that cannot name a rung is a surface
# that cannot draw the precedence pane. Each vocabulary exposes its keys as
# `LocalizedStringResource`s resolved against `FocusCore`'s own bundle, in exactly the shape
# `FocusStatus.shortLabelResource` already ships, so `FocusUI` renders them without writing a
# single string of its own.
#
# e05 adds one, `nudge.`, and it is FocusCore's for the same reason the five e04 namespaces
# are: the nudge vocabulary is declared where `FocusUI` can reach it without importing
# `FocusClassify`, and every key is exposed as a `LocalizedStringResource` resolved against
# FocusCore's own bundle.
NAMESPACES = ("shell.", "settings.", "status.", "priority.", "capture.", "context.",
              "handoff.", "undo.", "session.", "sensing.", "capability.",
              "cascade.", "explanation.", "suppression.", "evidence.", "rule.",
              "nudge.")

# module name -> (catalog path, source directory)
MODULES = {
    "App": ("App/Localizable.xcstrings", "App"),
    "FocusCore": (
        "Packages/FocusCore/Sources/FocusCore/Resources/Localizable.xcstrings",
        "Packages/FocusCore/Sources",
    ),
    "FocusUI": (
        "Packages/FocusUI/Sources/FocusUI/Resources/Localizable.xcstrings",
        "Packages/FocusUI/Sources",
    ),
}

# Modules whose catalog is deliberately empty. See the header: the app target is a
# composition root and owns no user-visible text, so its catalog is the guard rather than the
# content, and this is the assertion that keeps it one.
EXPECTS_NO_STRINGS = ("App",)

LITERAL = re.compile(r'"([^"\\\n]+)"')
COMMENT = re.compile(r'^\s*(//|///|\*|/\*)')
CASE_DECLARATION = re.compile(r"^\s*case\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:=\s*\"([^\"]*)\")?")

# --- e05: the deck matrix is COMPOSED, and that is why it is checked as a bijection --------
#
# Sixty-five keys — five voices x thirteen lines — and not one of them appears as a literal in
# any source file. `NudgeVoice.key(_:)` composes `nudge.<deck>.<situation>` from two enums, so
# the "every catalog key is referenced by a source literal" check below cannot see them and
# would report all sixty-five as dead text.
#
# Writing them out as sixty-five literals to satisfy that check would be the wrong fix: it is
# the fifth place the vocabulary is written down, and it is the one that rots. The right fix is
# the **stronger** assertion — a bijection between `NudgeVoice x NudgeCopyKey` and the
# `nudge.<deck>.*` keys, in both directions — so the deck keys are exempted from the reference
# check *here* and re-asserted *there*, never merely skipped.
#
# A missing deck entry is an untranslated nudge shipped to somebody at their most sensitive
# moment (R-96l).
NUDGE_SOURCE = "Packages/FocusCore/Sources/FocusCore/Nudge"


def enum_case_values(path, name):
    """The raw values of `enum <name>` in `path`, in declaration order.

    A case with no `= "..."` contributes its own name, which is what a `String`-raw Swift enum
    does. Read from the source rather than from a list here, because a list here would be the
    fifth place the vocabulary is written down.
    """
    with open(os.path.join(root, path)) as handle:
        lines = handle.readlines()

    values = []
    depth = 0
    inside = False
    for line in lines:
        if not inside:
            if re.search(rf"\benum\s+{name}\b", line) and not COMMENT.match(line):
                inside = True
                depth = line.count("{") - line.count("}")
            continue
        if COMMENT.match(line):
            continue
        found = CASE_DECLARATION.match(line)
        if found:
            values.append(found.group(2) or found.group(1))
        depth += line.count("{") - line.count("}")
        if depth <= 0:
            break
    return values


NUDGE_VOICES = enum_case_values(os.path.join(NUDGE_SOURCE, "NudgeVoice.swift"), "NudgeVoice")
NUDGE_LINES = enum_case_values(os.path.join(NUDGE_SOURCE, "NudgeVoice.swift"), "NudgeCopyKey")
DECK_MATRIX = {f"nudge.{voice}.{line}" for voice in NUDGE_VOICES for line in NUDGE_LINES}

failures = []


def report(ok, message, detail=None):
    if ok:
        print(f"ok   {message}")
        return
    line = f"FAIL [F-149] {message}"
    if detail:
        line += "\n" + "\n".join(f"    {d}" for d in detail)
    failures.append(line)
    print(line, file=sys.stderr)


def catalog_keys(path):
    with open(os.path.join(root, path)) as handle:
        doc = json.load(handle)
    return doc.get("strings", {})


def literals_in(directory):
    found = set()
    for base, _dirs, files in os.walk(os.path.join(root, directory)):
        for name in files:
            if not name.endswith(".swift"):
                continue
            with open(os.path.join(base, name)) as handle:
                for line in handle:
                    if COMMENT.match(line):
                        continue
                    for literal in LITERAL.findall(line):
                        # <namespace>.<surface>.<element>: the three-component rule is what
                        # separates a catalog key from an action identifier such as
                        # "shell.closeWindow" or an SF Symbol such as "cup.and.saucer.fill".
                        if literal.startswith(NAMESPACES) and literal.count(".") >= 2:
                            found.add(literal)
    return found


for module, (catalog_path, source_dir) in sorted(MODULES.items()):
    entries = catalog_keys(catalog_path)
    referenced = literals_in(source_dir)
    declared = set(entries)

    print(f"-- {module}: {len(declared)} catalog key(s), {len(referenced)} referenced in source")

    if module in EXPECTS_NO_STRINGS:
        owned = sorted(declared | referenced)
        report(
            not owned,
            f"{module}: owns no user-visible text, as the catalog split intends",
            [f"unexpected key: {key}" for key in owned]
            + [
                "The app target is a composition root: user-visible text belongs to FocusUI",
                "and is reached through ShellStrings. Move the key there, or take this module",
                "out of EXPECTS_NO_STRINGS deliberately.",
            ],
        )

    # The composed deck keys are exempt here and asserted as a bijection below — never
    # skipped, replaced by a stronger check.
    unreferenced = sorted(declared - referenced - DECK_MATRIX)
    report(
        not unreferenced,
        f"{module}: every catalog key is referenced by {source_dir}",
        [f"unreferenced: {key}" for key in unreferenced],
    )

    missing = sorted(referenced - declared)
    report(
        not missing,
        f"{module}: every key named in {source_dir} exists in the catalog",
        [f"missing from {catalog_path}: {key}" for key in missing],
    )

    # A key whose English value is absent, empty, or not marked translated resolves to the
    # key itself at runtime — the same silent failure as a missing key.
    untranslated = []
    for key, entry in sorted(entries.items()):
        unit = (
            entry.get("localizations", {})
            .get("en", {})
            .get("stringUnit", {})
        )
        if unit.get("state") != "translated" or not unit.get("value"):
            untranslated.append(key)
    report(
        not untranslated,
        f"{module}: every catalog entry has a translated English value",
        [f"not translated: {key}" for key in untranslated],
    )

# --- e04: three bijections between a Swift vocabulary and its copy (plan R-70k/l/m) --------
#
# The catalog checks above are about *presence*: every key is referenced, every referenced key
# exists. These three are about *totality*, which is a different property and the one that
# actually matters for a closed vocabulary:
#
#   R-70k  CascadeStage.allCases        ↔ cascade.rung.*
#   R-70l  ExplanationClause's cases    ↔ explanation.clause.*
#   R-70m  SuppressionReason.allCases   ↔ suppression.reason.*
#
# Why a bijection rather than a subset in each direction. A rung with no copy is a row the
# precedence pane cannot draw — and that pane exists precisely to show a person that their own
# rules outrank everything, so a missing row is a broken promise rather than a cosmetic gap. A
# copy key with no rung is a sentence the app can never say, which is how a catalog rots. And
# `check-strings.sh` is the fourth reader of `CascadePrecedence.rungs` (plan R-54): the runtime
# iterates it, the explanation builder switches over it, the Settings pane renders it, and this
# compares it to the copy. Three of the four are mechanically checked; this is one of them.
#
# The cases are read out of the **source**, by parsing the `case` declarations of the named
# enum, rather than from a hand-kept list here — a list in this script would be a fifth place
# the vocabulary is written down, and the whole ruling is that there is no fifth place.

RELEVANCE_SOURCE = "Packages/FocusCore/Sources/FocusCore/Relevance"

BIJECTIONS = (
    ("R-70k", "CascadeStage", "CascadePrecedence.swift", "cascade.rung."),
    ("R-70l", "ExplanationClause", "Explanation.swift", "explanation.clause."),
    ("R-70m", "SuppressionReason", "UncertaintyReason.swift", "suppression.reason."),
)

# Keys inside a namespace that are captions rather than members of the vocabulary. Named one by
# one, because "everything that does not parse" would be a hole the next caption falls through.
NON_MEMBER_KEYS = {"cascade.rung.unavailable"}

def enum_cases(path, name):
    """The case names declared by `enum <name>` in `path`, in declaration order."""
    with open(os.path.join(root, path)) as handle:
        lines = handle.readlines()

    cases = []
    depth = 0
    inside = False
    for line in lines:
        if not inside:
            if re.search(rf"\benum\s+{name}\b", line) and not COMMENT.match(line):
                inside = True
                depth = line.count("{") - line.count("}")
            continue
        if COMMENT.match(line):
            continue
        found = CASE_DECLARATION.match(line)
        if found:
            cases.append(found.group(1))
        depth += line.count("{") - line.count("}")
        if depth <= 0:
            break
    return cases


core_catalog = catalog_keys(MODULES["FocusCore"][0])

for condition, enum_name, file_name, namespace in BIJECTIONS:
    declared = set(enum_cases(os.path.join(RELEVANCE_SOURCE, file_name), enum_name))
    keys = {
        key
        for key in core_catalog
        if key.startswith(namespace) and key not in NON_MEMBER_KEYS
    }
    suffixes = {key[len(namespace):] for key in keys}

    report(
        bool(declared),
        f"{condition}: {enum_name} declares at least one case",
        [f"no `case` found in {file_name} — has the enum been renamed?"],
    )
    report(
        not (declared - suffixes),
        f"{condition}: every {enum_name} case has a {namespace}* key",
        [f"no copy for {enum_name}.{case}: add {namespace}{case}" for case in sorted(declared - suffixes)],
    )
    report(
        not (suffixes - declared),
        f"{condition}: every {namespace}* key names a {enum_name} case",
        [f"{namespace}{suffix} names no case of {enum_name}" for suffix in sorted(suffixes - declared)],
    )

# --- e05 R-96l: the deck matrix and four more bijections -----------------------------------
#
# Five assertions, and the first is different in kind from the rest.
#
#   the matrix   NudgeVoice x NudgeCopyKey  <-> nudge.<deck>.<situation>   (65 keys)
#   R-96l        LadderRung.Kind            <-> nudge.rung.*
#   R-96l        QueryableUncertainty       <-> nudge.query.reason.*
#   R-96l        NudgeSuppressionReason     <-> nudge.suppressed.*
#   R-96l        DeferralReason             <-> nudge.deferred.*
#
# The matrix is a **product** of two vocabularies rather than one, because a voice with a
# missing line is not a missing sentence — it is a nudge that renders its own key to somebody
# at their most sensitive moment. Five decks times thirteen lines, both directions, no
# exceptions: a key with no pair is a sentence the app can never say, and a pair with no key is
# a line it would say wrongly.
#
# `nudge.withheld.*` is deliberately NOT here. Those keys ARE written out as literals in
# `QueryWithholdingReason.copyKey`, so the generic reference check above already covers them in
# both directions; adding a bijection would be the same assertion twice.
#
# **The tone assertion is not here either, and that is deliberate.** R-96f — no line under a
# `nudge.*.query.*` key may accuse anybody — lives in `check-forbidden.sh`, where the
# accusatory word list exists exactly once. Splitting the list across two scripts would be the
# fifth-place drift R-54 forbids everywhere else, and a word list that disagrees with itself is
# worse than one that lives in the file whose name says "forbidden".

NUDGE_BIJECTIONS = (
    ("R-96l", "LadderRung.Kind", "LadderRung.swift", "Kind", "nudge.rung."),
    (
        "R-96l", "QueryableUncertainty", "QueryableUncertainty.swift",
        "QueryableUncertainty", "nudge.query.reason.",
    ),
    (
        "R-96l", "NudgeSuppressionReason", "SuppressionStack.swift",
        "NudgeSuppressionReason", "nudge.suppressed.",
    ),
    ("R-96l", "DeferralReason", "RungDelivery.swift", "DeferralReason", "nudge.deferred."),
)

# The matrix, first.
report(
    bool(NUDGE_VOICES) and bool(NUDGE_LINES),
    "R-96l: NudgeVoice and NudgeCopyKey both declare cases",
    ["no `case` found in NudgeVoice.swift — has an enum been renamed?"],
)

deck_declared = {key for key in core_catalog if key.startswith("nudge.")}
# Only the composed keys: `nudge.rung.*`, `nudge.suppressed.*` and friends are single-vocabulary
# keys and are asserted by the four bijections below, not by the matrix.
deck_declared = {
    key
    for key in deck_declared
    if len(key.split(".")) > 2 and key.split(".")[1] in set(NUDGE_VOICES)
}

report(
    not (DECK_MATRIX - deck_declared),
    f"R-96l: all {len(DECK_MATRIX)} deck keys "
    f"({len(NUDGE_VOICES)} voices x {len(NUDGE_LINES)} lines) exist in the catalog",
    [f"missing deck entry: {key}" for key in sorted(DECK_MATRIX - deck_declared)],
)
report(
    not (deck_declared - DECK_MATRIX),
    "R-96l: every nudge.<deck>.* key names a real voice and line",
    [
        f"{key} names no NudgeVoice x NudgeCopyKey pair"
        for key in sorted(deck_declared - DECK_MATRIX)
    ],
)

for condition, label, file_name, enum_name, namespace in NUDGE_BIJECTIONS:
    declared = set(enum_case_values(os.path.join(NUDGE_SOURCE, file_name), enum_name))
    keys = {key for key in core_catalog if key.startswith(namespace)}
    suffixes = {key[len(namespace):] for key in keys}

    report(
        bool(declared),
        f"{condition}: {label} declares at least one case",
        [f"no `case` found for {enum_name} in {file_name} — has it been renamed?"],
    )
    report(
        not (declared - suffixes),
        f"{condition}: every {label} case has a {namespace}* key",
        [f"no copy for {label}.{case}: add {namespace}{case}" for case in sorted(declared - suffixes)],
    )
    report(
        not (suffixes - declared),
        f"{condition}: every {namespace}* key names a {label} case",
        [f"{namespace}{suffix} names no case of {label}" for suffix in sorted(suffixes - declared)],
    )

print()
if failures:
    print(f"STRING LINT FAILED — {len(failures)} check(s)", file=sys.stderr)
    sys.exit(1)
print("catalog completeness OK")
PYTHON
catalog_rc=$?
(( catalog_rc != 0 )) && rc=1

print
if (( rc == 0 )); then
    print "STRING LINT OK"
else
    print -u2 "STRING LINT FAILED"
fi
exit $rc
