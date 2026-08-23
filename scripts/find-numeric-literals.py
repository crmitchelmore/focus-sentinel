#!/usr/bin/env python3
"""Find numeric literals in Swift code — R-70f's instrument.

    scripts/find-numeric-literals.py --paths <dir>… --except <file>…

Exits 1 and prints `path:line: text` for every numeric literal found in code, so that
`check-forbidden.sh` can fail the gate on it.

## Why this is a script and not a grep

A numeric literal has to be found in *code*. A grep for `[0-9]` finds it in comments (`P-119`,
`0.017`, `≤ 25 ms`), in doc comments (the whole justification for every constant), in string
literals (`"%016lx"`, `"cascade.rung.sessionRule"`) and in identifiers (`FocusSchemaV3`,
`UInt64`, `BCP47`, `fnv1a`). None of those is a magic number, and a lint that cannot tell them
apart is a lint people learn to ignore.

So: block comments, line comments and string literals are removed first, and a number is only
reported when it is preceded by something that is not an identifier character.

## What is excepted, and why

* **`0` and `1`.** Array indices, clamps, empty/one comparisons and version components. A
  threshold is never 0 or 1 in a way that matters — and when it is (`minimumOverlapTokens = 1`)
  it lives in the excepted file anyway, named and digested like every other.
* **Any line comparing against `count` or `isEmpty`.** `parts.count >= 2` is arithmetic about a
  collection, not a threshold about a person.

Every other numeric literal in the searched paths is a threshold that has escaped
`RelevancePolicy`, where it would owe a name, a class, a probe, a digest entry and — if it is
behavioural — a boundary triple and a mutation witness (R-59, R-74).
"""

import os
import re
import sys

BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)
MULTILINE_STRING = re.compile(r'"""(?:.|\n)*?"""')
STRING = re.compile(r'"(?:\\.|[^"\\\n])*"')
LINE_COMMENT = re.compile(r"//[^\n]*")

NUMBER = re.compile(
    r"(?<![A-Za-z0-9_.$])"
    r"("
    r"0[xX][0-9a-fA-F_]+"
    r"|0[bB][01_]+"
    r"|0[oO][0-7_]+"
    r"|[0-9][0-9_]*(?:\.[0-9][0-9_]*)?(?:[eE][+-]?[0-9]+)?"
    r")"
)

COLLECTION_ARITHMETIC = re.compile(r"\.(count|isEmpty)\b")

ALLOWED = {"0", "1"}


def strip_non_code(source: str) -> str:
    """Blank out comments and string literals, preserving line numbers."""

    def blank(match: re.Match) -> str:
        return re.sub(r"[^\n]", " ", match.group(0))

    source = BLOCK_COMMENT.sub(blank, source)
    source = MULTILINE_STRING.sub(blank, source)
    source = STRING.sub(blank, source)
    source = LINE_COMMENT.sub(blank, source)
    return source


def literals_in(path: str) -> list[tuple[int, str, str]]:
    with open(path, encoding="utf-8") as handle:
        source = handle.read()

    findings = []
    code_lines = strip_non_code(source).splitlines()
    raw_lines = source.splitlines()

    for number, line in enumerate(code_lines, start=1):
        if COLLECTION_ARITHMETIC.search(line):
            continue
        for match in NUMBER.finditer(line):
            literal = match.group(1).replace("_", "")
            if literal in ALLOWED:
                continue
            findings.append((number, literal, raw_lines[number - 1].strip()))
    return findings


def main(argv: list[str]) -> int:
    paths: list[str] = []
    excepted: list[str] = []
    bucket = None
    for argument in argv:
        if argument == "--paths":
            bucket = paths
        elif argument == "--except":
            bucket = excepted
        elif bucket is not None:
            bucket.append(argument)
        else:
            print(f"unexpected argument: {argument}", file=sys.stderr)
            return 2

    excepted_paths = {os.path.normpath(path) for path in excepted}
    findings = []

    for root in paths:
        for base, _dirs, files in os.walk(root):
            if ".build" in base.split(os.sep):
                continue
            for name in sorted(files):
                if not name.endswith(".swift"):
                    continue
                path = os.path.normpath(os.path.join(base, name))
                if path in excepted_paths:
                    continue
                for number, literal, text in literals_in(path):
                    findings.append(f"{path}:{number}: numeric literal {literal} — {text}")

    if findings:
        for finding in findings:
            print(finding)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
