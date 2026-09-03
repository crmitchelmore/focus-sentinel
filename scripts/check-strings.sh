#!/bin/zsh
# String externalisation — the F-149 lint.
#
#   scripts/check-strings.sh
#
# Three checks, all of which fail the gate:
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
#   3. **The catalogs and the code agree about DRAWING, not about spelling** (focus-pzl). Check
#      2's forward direction was satisfied, for every key in this repository, by the `case … =
#      "…"` or `case .x: "…"` line that spells the key — so the check was vacuous and forty
#      undrawable sentences shipped under it. The third section excludes a key's own definition
#      and asks what NAMES it (a Swift case name, per key) or what DRAWS it (a declared row in
#      `Config/string-draw-sites.txt`, per vocabulary). Its limits are stated in full at the
#      section itself; read them before trusting it further than it goes.
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

# **Two flags, and both exist for the self-test at the foot of this file** (focus-cv3).
#
#   --reachability-only   run only the "reachable, not merely mentioned" section, and do not
#                         recurse into the self-test. This is what each mutation run invokes on
#                         its own copy of the tree, so a mutation costs one section rather than
#                         four.
#   --no-self-test        skip the self-test on a full run. For an inner loop; the gate never
#                         passes it, because a guard that is only checked when somebody
#                         remembers to check it is a guard with a schedule rather than a proof.
ONLY_REACHABILITY=0
SELF_TEST=1
for argument in "$@"; do
    case "$argument" in
        --reachability-only) ONLY_REACHABILITY=1; SELF_TEST=0 ;;
        --no-self-test) SELF_TEST=0 ;;
        *) print -u2 "usage: ${0:t} [--reachability-only] [--no-self-test]"; exit 2 ;;
    esac
done

if (( ! ONLY_REACHABILITY )); then

print "== hardcoded user-visible strings"

typeset -a SOURCE_ROOTS
SOURCE_ROOTS=(App Packages/FocusCore/Sources Packages/FocusRules/Sources
              Packages/FocusClassify/Sources Packages/FocusEvaluate/Sources
              Packages/FocusSensing/Sources
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
print "== registered verbatim sites"

# **The exemption above is a mechanism, and this is the lint over it** (focus-7zr's sweep).
#
# Check 1 lets `Text(verbatim:)` through by design, and the design is right: a file path, a ⌘W
# glyph and somebody's own sentence must never be routed through a String Catalog. But an
# exemption nobody reads is an exemption that spreads, and in this repository it did. Three
# defects reached a person's screen with this gate green, all through this one door:
#
#   * the rules list drew `com.apple.Safari` and `https://news.example.com` while the chip row
#     in the same window drew `Safari` and `docs.example.com` (focus-7zr);
#   * the Intervention pane drew `com.apple.Keynote` under "Not presentations" (focus-7zr);
#   * the budget row interpolated two `Int`s, so it drew Western Arabic digits in every locale
#     while every other number in the app went through `.formatted()`.
#
# Each was justified by a source comment saying the subject was "the user's own material", and
# each comment was true of the *slot* and false of the *value in it*.
#
# So this does not withdraw the exemption. It requires every use of it to be **registered** in
# `Config/verbatim-sites.txt`, with a line saying what that site draws. Adding a verbatim site
# then costs a row in a file whose whole content is a list of the things this app draws without
# translating, which is a thing a reviewer can read end to end.
#
# ## What it cannot do, stated so nobody mistakes it for more
#
# It cannot tell a good drawing from a bad one. A row reading "draws the bundle identifier"
# passes. What it changes is that the row has to be written, and a diff that adds one is a diff
# that says out loud what is about to be drawn untranslated. The claim is visibility, not
# correctness; correctness is R-96o for the nudge's subject slot and the snapshot baselines
# everywhere else.
#
# ## Why the needle is `verbatim:` and not `Text(verbatim:`
#
# Measured on this tree: `grep 'Text(verbatim:'` finds 33 sites and `grep 'verbatim:'` finds 35.
# The two it misses are the ones whose argument was long enough to wrap, so `Text(` sits on one
# line and `verbatim:` on the next — `VerdictInspectorView`'s drift clock and the Intervention
# pane's snooze spans. A lint whose needle can be escaped by adding a newline is a lint with a
# documented hole in it, and both of those sites are real drawings.

python3 - "$REPO_ROOT" "${SOURCE_ROOTS[@]}" <<'PYTHON'
import os
import re
import sys

root, source_roots = sys.argv[1], sys.argv[2:]
registry_path = os.path.join(root, "Config", "verbatim-sites.txt")

COMMENT = re.compile(r'^\s*(//|///|\*|/\*)')

# A site is (path relative to the repository, the expression exactly as the line has it).
found = {}
for source_root in source_roots:
    for directory, _, names in os.walk(os.path.join(root, source_root)):
        for name in sorted(names):
            if not name.endswith(".swift"):
                continue
            path = os.path.join(directory, name)
            relative = os.path.relpath(path, root)
            with open(path) as handle:
                for number, line in enumerate(handle, start=1):
                    if "verbatim:" not in line or COMMENT.match(line):
                        continue
                    expression = line.split("verbatim:", 1)[1].strip()
                    found.setdefault((relative, expression), []).append(number)

registered = {}
if not os.path.exists(registry_path):
    print(f"FAIL [F-149] no verbatim registry at {registry_path}", file=sys.stderr)
    sys.exit(1)

with open(registry_path) as handle:
    for number, line in enumerate(handle, start=1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = [part.strip() for part in line.split("|")]
        if len(parts) < 3 or not parts[2]:
            print(
                f"FAIL [F-149] {registry_path}:{number} is not "
                "`<path> | <expression> | <what it draws>`",
                file=sys.stderr,
            )
            sys.exit(1)
        registered[(parts[0], parts[1])] = parts[2]

rc = 0

# Non-vacuity. A registry and a search that both came back empty would agree perfectly and
# prove nothing — the failure mode this whole section exists to close.
if not found:
    print("FAIL [F-149] no verbatim site found in the shipping graph — the check is blind",
          file=sys.stderr)
    rc = 1

unregistered = sorted(set(found) - set(registered))
if unregistered:
    print("FAIL [F-149] a verbatim site is not registered:", file=sys.stderr)
    for path, expression in unregistered:
        lines = ", ".join(str(number) for number in found[(path, expression)])
        print(f"    {path}:{lines}  verbatim: {expression}", file=sys.stderr)
    print("    Add a row to Config/verbatim-sites.txt saying what it draws — or draw it",
          file=sys.stderr)
    print("    through ShellText/NudgeText, if it is prose the app authored.", file=sys.stderr)
    rc = 1

stale = sorted(set(registered) - set(found))
if stale:
    print("FAIL [F-149] a registered verbatim site no longer exists:", file=sys.stderr)
    for path, expression in stale:
        print(f"    {path}  verbatim: {expression}", file=sys.stderr)
    print("    Remove the row from Config/verbatim-sites.txt. A registry that describes",
          file=sys.stderr)
    print("    drawings the app no longer makes is a registry nobody can trust.",
          file=sys.stderr)
    rc = 1

if rc == 0:
    print(f"ok   all {len(found)} verbatim sites are registered with what they draw")
sys.exit(rc)
PYTHON
verbatim_rc=$?
(( verbatim_rc != 0 )) && rc=1

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
    # The composition layer. It moved out of the app target so that a test bundle could reach
    # it, and this row is what stops that move quietly retiring the assertion the app target
    # was carrying: the composition root owns no user-visible text, wherever it lives.
    "FocusHost": (
        "Packages/FocusHost/Sources/FocusHost/Resources/Localizable.xcstrings",
        "Packages/FocusHost/Sources",
    ),
}

# Modules whose catalog is deliberately empty. See the header: the app target is a
# composition root and owns no user-visible text, so its catalog is the guard rather than the
# content, and this is the assertion that keeps it one.
EXPECTS_NO_STRINGS = ("App", "FocusHost")

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
                "The app target and FocusHost are the composition layer: user-visible text",
                "belongs to FocusUI",
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

# --- e05 R-96l: the deck matrix and two more bijections ------------------------------------
#
# Three assertions, and the first is different in kind from the rest.
#
#   the matrix   NudgeVoice x NudgeCopyKey  <-> nudge.<deck>.<situation>   (65 keys)
#   R-96l        LadderRung.Kind            <-> nudge.rung.*
#   R-96l        QueryableUncertainty       <-> nudge.query.reason.*
#
# The matrix is a **product** of two vocabularies rather than one, because a voice with a
# missing line is not a missing sentence — it is a nudge that renders its own key to somebody
# at their most sensitive moment. Five decks times thirteen lines, both directions, no
# exceptions: a key with no pair is a sentence the app can never say, and a pair with no key is
# a line it would say wrongly.
#
# ## It was five, and the two that went were the ones a bijection could not save (focus-pzl)
#
# `NudgeSuppressionReason <-> nudge.suppressed.*` and `DeferralReason <-> nudge.deferred.*` were
# both **green and both total** while all twenty-eight of their sentences were undrawable, and so
# was the generic reference check over `nudge.withheld.*`. That is the lesson these three lines
# are worth: a bijection proves a vocabulary is *complete*, never that it is *reachable*. Copy
# for a closed vocabulary needs both, and the reachability half is the section below this one.
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
)

# The matrix, first.
report(
    bool(NUDGE_VOICES) and bool(NUDGE_LINES),
    "R-96l: NudgeVoice and NudgeCopyKey both declare cases",
    ["no `case` found in NudgeVoice.swift — has an enum been renamed?"],
)

deck_declared = {key for key in core_catalog if key.startswith("nudge.")}
# Only the composed keys: `nudge.rung.*` and `nudge.query.reason.*` are single-vocabulary keys
# and are asserted by the two bijections below, not by the matrix.
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

fi

print
print "== reachable, not merely mentioned"

# **The blessing rule** (focus-pzl). Read the header note above this line before changing it.
#
# ## What was wrong with the check above
#
# "Every catalog key is referenced by that module's sources" was, measured on this tree,
# **vacuous for every key in the repository**. All of `FocusUI`'s are raw values of
# `ShellStringKey`, whose only literal is the `case … = "…"` that spells them; all of
# `FocusCore`'s are spelled by a `copyKey`-shaped switch in the file that declares the
# vocabulary. Every key was referenced — by its own definition. Deleting the last real reader of
# a string changed nothing the lint could see.
#
# What it bought: forty shipped sentences no route could draw — `nudge.suppressed.*` (12),
# `nudge.withheld.*` (12), `nudge.deferred.*` (4), `explanation.stage.*` (9) and
# `rule.authority.*` (3) — plus `settings.intervention.surface.notification` = "A notification",
# which sat four lines under the app's own promise that it "never sends a notification, and never
# asks for permission to". Every one of them passed because a switch arm somewhere MENTIONED its
# key.
#
# ## The rule, in two halves, because the repository has two shapes
#
#   **Rule 1 — a named key is blessed by its Swift case name, not by its own spelling.**
#   `FocusUI` draws by name: `ShellText(.interventionRoutingHeading, …)`. So for a key declared
#   as `case <name> = "<key>"` the declaration line is excluded, and the key is blessed only if
#   `<name>` is named somewhere else in the module. Per key, mechanical, no registry. This is
#   what catches a freshly-orphaned string: delete the last `ShellText(.foo, …)` and the key
#   named by `foo` fails here.
#
#   **Rule 2 — an unnamed key is blessed by a declared draw site.**
#   `FocusCore` never draws. It exposes a `LocalizedStringResource` and a view in `FocusUI` reads
#   it off a value whose type the call site does not spell: `ShellText(resource:
#   reason.copyResource, …)`. There is no textual path from the key to that line and no textual
#   lint can invent one — so the link is declared in `Config/string-draw-sites.txt`, one row per
#   vocabulary, and checked: the drawing file must exist and must still contain the expression.
#
# ## The four bypasses this rule shipped with, and where each one is closed (focus-cv3)
#
# The rule above was raised to stop dead copy shipping, and its whole evidence was that it caught
# the copy it was written against. Read adversarially, four ways to satisfy it without writing a
# drawing turned up, all of them a one-line edit:
#
#   1. **A second `case` of the same name.** Rule 1 excluded the key's OWN declaration line and
#      nothing else, so `enum Whatever { case interventionQuietHoursStartEarlier }` — anywhere in
#      the module, raw value or not — blessed an orphaned key. Closed: no `case` line counts as a
#      use, because a `case` is a spelling wherever it appears.
#   2. **A comment.** Both rules read raw text and skipped only comments that OWNED their line, so
#      a trailing `// .interventionQuietHoursStartEarlier`, a `/* … */` block, or the draw-site
#      expression pasted into a comment in the drawing file all passed. Closed: both rules read
#      comment-stripped source, and Rule 1 reads string-stripped source as well.
#   3. **A path that merely starts with a drawing root.** `path.startswith("App")` accepts
#      `AppTests/…`, which is exactly the "a test cannot bless a string" rule the line enforces.
#      Closed: the match is on a path boundary.
#   4. **An expression that is not a drawing.** A row could name `import SwiftUI` and stay true
#      for as long as the file existed. Closed: the expression must contain a call to one of the
#      app's drawing entry points.
#
# `--self-test` at the foot of this script mutates the tree each of those ways and asserts the
# lint goes RED. A guard whose only evidence is that it caught the strings it was written against
# is the pattern this programme keeps paying for.
#
# ## What it still cannot do, said plainly rather than left to be discovered
#
# **Rule 2 proves a vocabulary is drawn, never that a particular case is reachable.** A key named
# only in a switch arm over a wider type than the caller can produce still passes — which is
# exactly how `settings.intervention.surface.notification` survived, and Rule 1 would not have
# caught it either, because `.interventionSurfaceNotification` really was named in
# `InterventionSettingsView`. That last step is a dataflow question and is not decidable from
# text. It is closed at the type instead: narrow the drawing function's domain and assert over
# the producer's own output, the way `InterventionSettingsTests.everyDrawnRowHasASentence` now
# does against `SurfaceRouter.table(…)`.
#
# **Rule 1 does not ask whether the naming site is itself reachable.** A key spelled inside a
# private helper that nothing calls is blessed — `boundaryButtons(_:)` is the shape, though on
# this tree that function is called from `quietHoursSection` and its four keys really are drawn.
# Closing it means transitive name-reachability from a root set (a `body`, a public member, an
# `init`), which is a real lint and a much larger one; it is filed as focus-ado rather than
# half-built here.
#
# So this section makes the *mechanical* claim it can make, and states the residual. What changes
# is that a key can no longer be blessed by the line that spells it, by a second line that spells
# it, by a comment, by a test, or by a row that points at a file rather than at a drawing.

python3 - "$REPO_ROOT" <<'PYTHON'
import json
import os
import re
import sys

root = sys.argv[1]
registry_path = os.path.join(root, "Config", "string-draw-sites.txt")

COMMENT = re.compile(r'^\s*(//|///|\*|/\*)')
# `case <name> = "<key>"`, alone on its line: the declaration of a NAMED key. Matched against a
# COMMENT-STRIPPED line, so a declaration carrying a trailing `// note` is still seen as one.
DECLARATION = re.compile(r'^\s*case\s+([A-Za-z_]\w*)\s*=\s*"([^"]+)"\s*$')
# The name a `case` DECLARES, anywhere on a line — `case foo`, `case foo = "…"`,
# `case foo(Bar)`, and `enum Whatever { case foo }` all the same. Such a name is a spelling, never
# a drawing, and the anchored `^\s*case` this replaced was itself a bypass: putting the enum on
# one line moved the `case` off the start of it, which the self-test at the foot of this script
# caught the first time it ran. A switch ARM is untouched — `case .foo:` and `case let x` do not
# match, because what follows the keyword there is not a bare identifier — so a drawing that
# shares a line with a switch arm still counts.
CASE_DECLARED_NAME = re.compile(r'\bcase\s+[A-Za-z_]\w*')
# A Swift identifier, whole. `\b` at both ends of the old per-key pattern made it a whole-token
# match already; this is the same claim asked once for the whole module instead of once per key.
IDENTIFIER = re.compile(r'[A-Za-z_]\w*')


def without_comments(lines):
    """`lines` with every comment blanked out, line count and columns preserved.

    `COMMENT` only ever matched a comment that OWNED its line, which left three ways to bless a
    string with prose (focus-cv3):

        adjust(key)                      // .interventionQuietHoursStartEarlier
        /*
           interventionQuietHoursStartEarlier
        */
        print("interventionQuietHoursStartEarlier")

    The first two are comments the old needle could not see; the third is dealt with by
    `without_comments_or_strings` below. A lint that a sentence in a comment can satisfy is a
    lint that anybody can satisfy without writing any code, which is the shape of bypass this
    guard exists to refuse.
    """
    return _strip(lines, strings=False)


def without_comments_or_strings(lines):
    """`lines` with comments AND string literals blanked out.

    A case name inside a string literal is a mention, never a drawing — and the raw value of a
    *different* key is a string literal that can spell any case name at all.
    """
    return _strip(lines, strings=True)


def _strip(lines, strings):
    out = []
    in_block = False
    for line in lines:
        kept = []
        index = 0
        in_string = False
        while index < len(line):
            pair = line[index:index + 2]
            if in_block:
                if pair == "*/":
                    in_block = False
                    index += 2
                    continue
                index += 1
                continue
            if in_string:
                if line[index] == "\\":
                    if not strings:
                        kept.append(line[index:index + 2])
                    index += 2
                    continue
                if line[index] == '"':
                    in_string = False
                if not strings:
                    kept.append(line[index])
                index += 1
                continue
            if pair == "/*":
                in_block = True
                index += 2
                continue
            if pair == "//":
                break
            if line[index] == '"':
                in_string = True
                if not strings:
                    kept.append('"')
                index += 1
                continue
            kept.append(line[index])
            index += 1
        out.append("".join(kept))
    return out

MODULES = {
    "FocusCore": (
        "Packages/FocusCore/Sources/FocusCore/Resources/Localizable.xcstrings",
        "Packages/FocusCore/Sources",
    ),
    "FocusUI": (
        "Packages/FocusUI/Sources/FocusUI/Resources/Localizable.xcstrings",
        "Packages/FocusUI/Sources",
    ),
}

# Where a drawing may live. `FocusCore` is in the list for exactly one vocabulary — the Edit
# menu's "Undo …" sentence, set from `PriorityStore` — and naming the modules rather than
# allowing any path is what stops a row pointing at a test.
DRAWING_ROOTS = (
    "Packages/FocusUI/Sources",
    "Packages/FocusHost/Sources",
    "Packages/FocusCore/Sources",
    "App",
)

failures = []


def fail(message, detail=()):
    line = f"FAIL [F-149] {message}"
    if detail:
        line += "\n" + "\n".join(f"    {d}" for d in detail)
    failures.append(line)
    print(line, file=sys.stderr)


def sources(directory):
    found = []
    for base, _dirs, names in os.walk(os.path.join(root, directory)):
        for name in sorted(names):
            if name.endswith(".swift"):
                found.append(os.path.join(base, name))
    return found


# --- Rule 1: a named key is blessed by its case name -----------------------------------------

named = {}          # key -> (module, relative path, line number, case name)
blessed_by_name = set()

for module, (catalog_path, source_dir) in sorted(MODULES.items()):
    with open(os.path.join(root, catalog_path)) as handle:
        keys = set(json.load(handle).get("strings", {}))

    paths = sources(source_dir)
    raw = {path: open(path).read().split("\n") for path in paths}
    # Two views of every file. Declarations are read with the strings still in — a declaration IS
    # its string — and uses are counted with both comments and strings gone, because neither can
    # draw anything.
    prose_free = {path: without_comments(raw[path]) for path in paths}
    code = {path: without_comments_or_strings(raw[path]) for path in paths}

    for path in paths:
        for number, line in enumerate(prose_free[path], start=1):
            found = DECLARATION.match(line)
            if found and found.group(2) in keys:
                named[found.group(2)] = (
                    module, os.path.relpath(path, root), number, found.group(1)
                )

    # **Every identifier this module writes in code that is not a `case` line.**
    #
    # One pass rather than one regular expression per key: the question "is this case name named
    # anywhere else" is answered by a set, and building the set once turns a check that took five
    # seconds into one that takes a fraction of it — which is what makes the self-test at the foot
    # of this script affordable enough to run every time.
    #
    # **No name a `case` declares contributes** (focus-cv3). Excluding only the key's OWN
    # declaration left the rule open to a one-line bypass: declare the same case name a second
    # time — in any enum, with or without a raw value, in any file of the module — and the
    # orphaned key is blessed by a line that draws nothing.
    #
    #     enum Whatever { case interventionQuietHoursStartEarlier }
    #
    # A `case` declares a spelling wherever it appears, so the name it declares is struck from the
    # line before the line is read. Measured on this tree the day the rule changed: zero keys were
    # relying on one.
    spoken = set()
    for path in paths:
        for line in code[path]:
            spoken.update(IDENTIFIER.findall(CASE_DECLARED_NAME.sub(" ", line)))

    orphans = []
    for key, (owner, relative, number, case) in sorted(named.items()):
        if owner != module:
            continue
        if case in spoken:
            blessed_by_name.add(key)
        else:
            orphans.append(f"{key}: nothing names `{case}` outside {relative}:{number}")

    mine = sum(1 for key in named if named[key][0] == module)
    # Non-vacuity, per module. If `DECLARATION` ever stops matching — a reformat, a rename, a new
    # way of spelling a key — every key silently falls through to Rule 2, and Rule 2's registry
    # says nothing about `FocusUI`. The whole of Rule 1 would then be an empty loop printing `ok`.
    if not mine:
        fail(
            f"{module}: Rule 1 found no `case … = \"…\"` declaration at all",
            [
                "Every key would fall to the draw-site registry, which does not cover this",
                "module — so the case-name check would be an empty loop reporting success.",
            ],
        )

    if orphans:
        fail(
            f"{module}: a catalog key is blessed only by the line that spells it",
            orphans + [
                "A `case … = \"…\"` declaration is the key's spelling, not a use of it. Draw the",
                "key through ShellText/NudgeText, or delete it: a string no code names is a",
                "sentence the app cannot say."
            ],
        )
    elif mine:
        print(f"ok   {module}: all {mine} named key(s) are named by code, not by their own declaration")

# --- Rule 2: an unnamed key is blessed by a declared draw site -------------------------------

if not os.path.exists(registry_path):
    fail(f"no draw-site registry at {registry_path}")
    print()
    print("REACHABILITY LINT FAILED", file=sys.stderr)
    sys.exit(1)

registry = []       # (line number, prefix, drawing path, expression)
with open(registry_path) as handle:
    for number, line in enumerate(handle, start=1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = [part.strip() for part in line.split("|")]
        if len(parts) != 3 or not all(parts):
            fail(
                f"{registry_path}:{number} is not "
                "`<key prefix> | <drawing file> | <expression>`"
            )
            continue
        registry.append((number, parts[0], parts[1], parts[2]))

# A prefix is `<namespace>.<vocabulary>.` — exactly two components. Without this a single row
# reading `nudge.` would bless seventy keys, which is the coarseness that makes a registry a
# rubber stamp.
for number, prefix, _path, _expression in registry:
    if not prefix.endswith(".") or prefix.count(".") != 2:
        fail(
            f"{registry_path}:{number} prefix `{prefix}` is not `<namespace>.<vocabulary>.`",
            ["A row may bless one vocabulary, never a whole namespace."],
        )

# The drawing site must still be there. A registry describing a drawing the app no longer makes
# is the same failure as a catalog key nobody draws, one level up.
#
# ## Three things a row now has to be, because it used to have to be none of them (focus-cv3)
#
# The row was a path and a substring, and the substring was looked for in the whole file. So a
# row could be kept true forever by:
#
#   * pasting the expression into a COMMENT in the drawing file — the check read the raw text,
#     comments and all, and a sentence in a comment draws nothing;
#   * pointing the path at anything whose name STARTS WITH a drawing root. `AppTests/…`,
#     `Apple.swift` and `Packages/FocusUI/SourcesOld/…` all satisfied `startswith`, which is
#     precisely the "a test cannot bless a string" rule the line was written to enforce;
#   * naming an expression that is not a drawing at all. `import SwiftUI` is in every one of
#     these files, and a row carrying it would have passed for as long as the file existed.
#
# All three are closed below. The third is the coarsest of the checks — a call to one of the
# app's drawing entry points is necessary, never sufficient — but it is the difference between a
# row that has to point at a drawing and a row that has to point at a file.
DRAW_CALLS = (
    "ShellText(", "NudgeText(", "Text(", "Label(",
    "String(localized:", "setActionName(",
)

for number, prefix, path, expression in registry:
    if not any(
        path == drawing_root or path.startswith(drawing_root + "/")
        for drawing_root in DRAWING_ROOTS
    ):
        fail(
            f"{registry_path}:{number} draws `{prefix}` from {path}",
            [f"which is not under one of {', '.join(DRAWING_ROOTS)} — "
             "a test cannot bless a string."],
        )
        continue
    if not any(call in expression for call in DRAW_CALLS):
        fail(
            f"{registry_path}:{number} the expression for `{prefix}` is not a drawing",
            [
                f"expected one of {', '.join(DRAW_CALLS)} in: {expression}",
                "A row has to point at the line that draws the copy, not merely at a line that",
                "exists in the file that draws it.",
            ],
        )
        continue
    full = os.path.join(root, path)
    if not os.path.exists(full):
        fail(f"{registry_path}:{number} names a drawing file that does not exist: {path}")
        continue
    drawing = "\n".join(without_comments(open(full).read().split("\n")))
    if expression not in drawing:
        fail(
            f"{registry_path}:{number} the drawing of `{prefix}` is gone from {path}",
            [
                f"expected to find, in code rather than in a comment: {expression}",
                "Point the row at the site that draws it now, or delete the copy: a vocabulary",
                "whose last reader went is a vocabulary nobody can read.",
            ],
        )

# Every key must be blessed by one rule or the other, and no row may cover only keys Rule 1
# already blesses — two mechanisms over one key is a row nobody has to keep true.
covered_by_row = {number: 0 for number, _p, _f, _e in registry}
for module, (catalog_path, _source_dir) in sorted(MODULES.items()):
    with open(os.path.join(root, catalog_path)) as handle:
        keys = sorted(json.load(handle).get("strings", {}))

    unreachable = []
    by_row = 0
    for key in keys:
        if key in blessed_by_name:
            continue
        rows = [number for number, prefix, _f, _e in registry if key.startswith(prefix)]
        if not rows:
            unreachable.append(key)
            continue
        by_row += 1
        for number in rows:
            covered_by_row[number] += 1

    if unreachable:
        fail(
            f"{module}: a catalog key has no draw site and no code names it",
            [f"unreachable: {key}" for key in unreachable] + [
                f"Add a row to {registry_path} naming the file that draws it — or delete the",
                "key. It is a sentence in the shipped binary that no route can produce.",
            ],
        )
    else:
        print(f"ok   {module}: every unnamed key ({by_row}) has a live draw site")

redundant = [
    f"{registry_path}:{number} `{prefix}` covers no key the case-name check leaves to it"
    for number, prefix, _f, _e in registry
    if covered_by_row[number] == 0
]
if redundant:
    fail("a draw-site row is redundant or stale", redundant)

# Non-vacuity: a registry and a catalog that were both empty would agree perfectly.
if not registry:
    fail("the draw-site registry is empty — the check is blind")
elif not failures:
    print(f"ok   all {len(registry)} draw-site row(s) still draw what they claim")

print()
if failures:
    print(f"REACHABILITY LINT FAILED — {len(failures)} check(s)", file=sys.stderr)
    sys.exit(1)
print("reachability OK")
PYTHON
reachable_rc=$?
(( reachable_rc != 0 )) && rc=1

# --- the guard's own proof ---------------------------------------------------------------------
#
# **Mutation, because a guard's only evidence was that it caught the strings it was written
# against** (focus-cv3).
#
# Everything above is a lint. Nothing above says the lint can FAIL. That is the pattern this
# programme keeps paying for — a proof written to the known failure, counted as coverage — and it
# is why `6db2351`'s blessing rule shipped with four one-line bypasses in it.
#
# So the reachability rule is mutated, on a throwaway copy of the tree, eight ways: one control
# that must stay GREEN, three that orphan a string and must go RED, and four that orphan a string
# and then try each closed bypass in turn, which must ALSO go RED. Each mutation run is
# `--reachability-only`, so the whole proof costs about a second.
#
# The control is not a formality. If the copy were incomplete, every mutation would go red for the
# wrong reason and the whole proof would be a tautology about a broken directory.

if (( SELF_TEST )); then
    print
    print "== the guard's own proof (mutation)"
    python3 - "$REPO_ROOT" <<'PYTHON'
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

root = sys.argv[1]
COPIED = (
    "Config",
    "App",
    "Packages/FocusCore/Sources",
    "Packages/FocusUI/Sources",
    "Packages/FocusHost/Sources",
)
DECLARATION = re.compile(r'^\s*case\s+([A-Za-z_]\w*)\s*=\s*"([^"]+)"\s*$')

UI_KEYS = "Packages/FocusUI/Sources/FocusUI/Resources/Localizable.xcstrings"
UI_SOURCES = "Packages/FocusUI/Sources"
CORE_KEYS = "Packages/FocusCore/Sources/FocusCore/Resources/Localizable.xcstrings"
REGISTRY = "Config/string-draw-sites.txt"

failures = []


def victim():
    """A named `FocusUI` key to orphan, and the file that declares it, read out of the tree.

    Naming a key in this file would be a fifth place the vocabulary lives, and it would rot the
    day somebody renamed it. The first declaration in sorted order is as good as any: what is
    being proved is that the rule has power, not that it has power over one particular sentence.
    """
    with open(os.path.join(root, UI_KEYS)) as handle:
        keys = set(json.load(handle).get("strings", {}))
    for base, _dirs, names in os.walk(os.path.join(root, UI_SOURCES)):
        for name in sorted(names):
            if not name.endswith(".swift"):
                continue
            path = os.path.join(base, name)
            with open(path) as handle:
                for line in handle:
                    found = DECLARATION.match(line)
                    if found and found.group(2) in keys:
                        return (
                            found.group(1),
                            found.group(2),
                            os.path.relpath(path, root),
                        )
    return None, None, None


# The file the victim is declared in is the file the bypass mutations append to, so there is no
# path written down in this harness to go stale.
CASE_NAME, CASE_KEY, CASE_FILE = victim()
if CASE_NAME is None:
    print("FAIL [F-149] self-test found no named key to orphan — the proof is blind",
          file=sys.stderr)
    sys.exit(1)


def fresh():
    directory = tempfile.mkdtemp(prefix="focus-string-guard-")
    os.makedirs(os.path.join(directory, "scripts"))
    shutil.copy2(
        os.path.join(root, "scripts", "check-strings.sh"),
        os.path.join(directory, "scripts", "check-strings.sh"),
    )
    for relative in COPIED:
        shutil.copytree(
            os.path.join(root, relative),
            os.path.join(directory, relative),
            symlinks=True,
        )
    return directory


def orphan_the_named_key(directory):
    """Rename every USE of the victim case, leaving its declaration alone.

    That is exactly the shape of the defect: the last reader of a string goes, the `case … = "…"`
    stays, and the catalog keeps a sentence no route can produce.
    """
    pattern = re.compile(r'(?<![A-Za-z0-9_])' + re.escape(CASE_NAME) + r'\b')
    for base, _dirs, names in os.walk(os.path.join(directory, UI_SOURCES)):
        for name in sorted(names):
            if not name.endswith(".swift"):
                continue
            path = os.path.join(base, name)
            with open(path) as handle:
                lines = handle.read().split("\n")
            changed = False
            for index, line in enumerate(lines):
                if DECLARATION.match(line):
                    continue
                replaced = pattern.sub(CASE_NAME + "Renamed", line)
                if replaced != line:
                    lines[index] = replaced
                    changed = True
            if changed:
                with open(path, "w") as handle:
                    handle.write("\n".join(lines))


def append(directory, relative, text):
    with open(os.path.join(directory, relative), "a") as handle:
        handle.write(text)


def first_row(directory):
    """The line number, prefix, path and expression of the registry's first real row."""
    path = os.path.join(directory, REGISTRY)
    with open(path) as handle:
        lines = handle.read().split("\n")
    for index, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        parts = [part.strip() for part in stripped.split("|")]
        if len(parts) == 3:
            return path, lines, index, parts
    return path, lines, None, None


def rewrite_row(directory, replacement):
    path, lines, index, parts = first_row(directory)
    if index is None:
        return None
    lines[index] = replacement(parts)
    with open(path, "w") as handle:
        handle.write("\n".join(lines))
    return parts


def remove_the_drawing(directory):
    """Delete the expression the registry's first row points at, from the file it points at."""
    _path, _lines, index, parts = first_row(directory)
    if index is None:
        return None
    drawing = os.path.join(directory, parts[1])
    with open(drawing) as handle:
        text = handle.read()
    with open(drawing, "w") as handle:
        handle.write(text.replace(parts[2], "// the drawing was removed"))
    return parts


def run(directory):
    finished = subprocess.run(
        [os.path.join(directory, "scripts", "check-strings.sh"), "--reachability-only"],
        capture_output=True,
        text=True,
    )
    return finished.returncode, finished.stdout + finished.stderr


def expect(name, want_red, mutate, needle=None):
    directory = fresh()
    try:
        mutate(directory)
        code, output = run(directory)
        red = code != 0
        if red != want_red:
            failures.append(
                f"{name}: expected {'RED' if want_red else 'GREEN'}, got "
                f"{'RED' if red else 'GREEN'}"
            )
            print(f"FAIL [F-149] mutation `{name}` did not move the lint", file=sys.stderr)
            for line in output.strip().split("\n")[-12:]:
                print(f"    {line}", file=sys.stderr)
            return
        if needle is not None and needle not in output:
            failures.append(f"{name}: went RED without saying {needle!r}")
            print(f"FAIL [F-149] mutation `{name}` failed for the wrong reason", file=sys.stderr)
            for line in output.strip().split("\n")[-12:]:
                print(f"    {line}", file=sys.stderr)
            return
        print(f"ok   {name}: {'RED' if red else 'GREEN'}, as the rule claims")
    finally:
        shutil.rmtree(directory, ignore_errors=True)


# The control. A copy nobody touched must pass, or every RED below proves nothing.
expect("an untouched copy of the tree", False, lambda directory: None)

# --- Rule 1 has power, and none of its three closed bypasses restores it ----------------------

expect(
    f"the last reader of `{CASE_KEY}` deleted",
    True,
    orphan_the_named_key,
    "blessed only by the line that spells it",
)

expect(
    "…and a second `case` of the same name added (bypass 1)",
    True,
    lambda directory: (
        orphan_the_named_key(directory),
        append(
            directory,
            CASE_FILE,
            f"\n\nenum StringGuardSelfTest {{ case {CASE_NAME} }}\n",
        ),
    ),
    "blessed only by the line that spells it",
)

expect(
    "…and the case name written in comments instead (bypass 2)",
    True,
    lambda directory: (
        orphan_the_named_key(directory),
        append(
            directory,
            CASE_FILE,
            f"\n// {CASE_NAME}\nlet selfTestNote = 0 // {CASE_NAME}\n"
            f"/*\n {CASE_NAME}\n*/\n",
        ),
    ),
    "blessed only by the line that spells it",
)

expect(
    "…and the case name written inside a string literal (bypass 2)",
    True,
    lambda directory: (
        orphan_the_named_key(directory),
        append(
            directory,
            CASE_FILE,
            f'\nlet selfTestLiteral = "{CASE_NAME}"\n',
        ),
    ),
    "blessed only by the line that spells it",
)

# --- Rule 2 has power, and none of its two closed bypasses restores it ------------------------

expect(
    "the drawing a registry row points at deleted",
    True,
    remove_the_drawing,
    "is gone from",
)

expect(
    "…and the expression pasted back into a comment (bypass 2)",
    True,
    lambda directory: (
        remove_the_drawing(directory),
        append(
            directory,
            first_row(directory)[3][1],
            "\n// " + first_row(directory)[3][2] + "\n",
        ),
    ),
    "is gone from",
)

expect(
    "a registry row pointed at a test directory (bypass 3)",
    True,
    lambda directory: rewrite_row(
        directory,
        lambda parts: f"{parts[0]} | AppTests/Fake.swift | {parts[2]}",
    ),
    "a test cannot bless a string",
)

expect(
    "a registry row whose expression draws nothing (bypass 4)",
    True,
    lambda directory: rewrite_row(
        directory,
        lambda parts: f"{parts[0]} | {parts[1]} | import SwiftUI",
    ),
    "is not a drawing",
)

print()
if failures:
    print(f"GUARD PROOF FAILED — {len(failures)} mutation(s) the lint did not notice",
          file=sys.stderr)
    sys.exit(1)
print("the reachability guard fails when it should")
PYTHON
    selftest_rc=$?
    (( selftest_rc != 0 )) && rc=1
fi

print
if (( rc == 0 )); then
    print "STRING LINT OK"
else
    print -u2 "STRING LINT FAILED"
fi
exit $rc
