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
# A catalog key begins `shell.`, `settings.` or `status.` **and** has at least three
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
LITERAL_PATTERN='(Text|Label|Button|Picker|Toggle|TextField|Stepper)\("|\.(navigationTitle|help|accessibilityLabel|accessibilityHint|accessibilityValue|windowTitle)\("'

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

NAMESPACES = ("shell.", "settings.", "status.")

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

LITERAL = re.compile(r'"([^"\\\n]+)"')
COMMENT = re.compile(r'^\s*(//|///|\*|/\*)')

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

    unreferenced = sorted(declared - referenced)
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
