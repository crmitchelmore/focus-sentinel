#!/bin/zsh
# Export-field classification — the registry lint (focus-tee.3, e09 plan §7).
#
#   scripts/check-export-fields.sh
#
# **The claim this lint makes is not "the export omits window titles".** No exporter exists yet.
# The claim is the one that has to be true *before* an exporter can be written honestly: every
# column this store keeps has been looked at by a person and classified, and a column nobody
# classified fails the build. The hostile question the e09 plan asks is not *does the export
# leak?* — it is **does an epic create the first column that could?** This is the answer, and it
# is installed before the exporter so that the exporter arrives into an enforcing gate rather
# than into a promise.
#
# ## What it reads
#
# `Config/export-field-classification.txt`, in the shape this repository already uses for
# `Config/string-draw-sites.txt` and `Config/verbatim-sites.txt`:
#
#   <entity> | <column> | <class> | <what it is>
#
# and the `@Model` declarations in `Packages/FocusCore/Sources/FocusCore/Store/FocusSchemaV*.swift`.
#
# ## Scope: THE CURRENT SCHEMA ONLY, derived rather than declared
#
# v1…v6 are frozen migration **sources** — the stores earlier builds actually wrote — and nothing
# fetches them; classifying their columns would be classifying rows no exporter can reach. So the
# lint computes the current entity set the same way the schema chain does: **for each entity
# name, the declaration in the highest-numbered schema wins**. That is exactly what
# `FocusSchemaV7.models` is (v6's list with `InterventionRecord` replaced), and deriving it means
# a version that re-declares a class cannot leave the lint reading the old columns.
#
# Two cross-checks stop the derivation from drifting quietly:
#
#   * `SCHEMA <n>` in the registry must equal the highest schema file present. Bumping the schema
#     without opening this file fails here.
#   * `ENTITIES <n>` must equal the number of entities derived. A `@Model` class added to a new
#     version — or one this parser has stopped seeing — fails here rather than silently
#     shrinking the set every other check is folded over.
#
# ## The five classes
#
#   KEY       bundle identifiers, normalised `scheme://host[:port]` origins, UUIDs
#   TOKEN     closed-vocabulary raw values and `NormalisedToken`s — re-derived on the way out
#   MEASURE   instants, durations, counts, booleans
#   OWN       the person's own typed words. Exportable BECAUSE it is theirs
#   EXCLUDED  never leaves, and the row says why
#
# ## What this lint is NOT
#
# It is deliberately independent of any exporter's own manifest. A lint that read the exporter's
# field list to decide what to require would be the exporter marking its own homework: the two
# have to be able to disagree, and the disagreement has to be what fails.
#
# It also says nothing about whether a classification is *correct*. `ContextItem.value` is an
# absolute path when the item is a file, and it is classified `OWN` because the person attached
# it rather than the app observing it — that is a judgement, recorded in the registry's own
# fourth column, and no script can check it. What the script guarantees is that the judgement was
# made, by somebody, in a reviewable file.
set -u

cd "${0:A:h}/.."

registry="Config/export-field-classification.txt"
store="Packages/FocusCore/Sources/FocusCore/Store"

print "EXPORT-FIELD CLASSIFICATION"
print "  registry: $registry"
print "  schemas:  $store/FocusSchemaV*.swift"
print

python3 - "$registry" "$store" <<'PYTHON'
import os, re, sys

registry_path, store_dir = sys.argv[1], sys.argv[2]

CLASSES = {"KEY", "TOKEN", "MEASURE", "OWN", "EXCLUDED"}

failures = []


def fail(message, *detail):
    failures.append(message)
    print(f"FAIL {message}", file=sys.stderr)
    for line in detail:
        print(f"    {line}", file=sys.stderr)


# ---------------------------------------------------------------- the schemas

schema_files = {}
for name in os.listdir(store_dir):
    match = re.fullmatch(r"FocusSchemaV(\d+)\.swift", name)
    if match:
        schema_files[int(match.group(1))] = os.path.join(store_dir, name)

if not schema_files:
    fail("no FocusSchemaV*.swift found — the lint would pass over nothing")
    sys.exit(1)

newest = max(schema_files)

# (version, entity) -> [column, ...], in declaration order.
declared = {}

for version in sorted(schema_files):
    source = open(schema_files[version], encoding="utf-8").read()
    for match in re.finditer(r"@Model\s*\n\s*public final class (\w+)\s*\{", source):
        entity = match.group(1)
        # The class body, by brace balance from the opening brace the match ends on.
        start = match.end() - 1
        depth = 0
        end = start
        for index in range(start, len(source)):
            if source[index] == "{":
                depth += 1
            elif source[index] == "}":
                depth -= 1
                if depth == 0:
                    end = index
                    break
        body = source[start:end]

        columns = []
        for line in body.splitlines():
            stripped = line.strip()
            # A STORED column is `public var name: Type…` with no `{` — a trailing brace is a
            # computed property (`isActive`, `openWindowsAtLastQuit`), which is a projection of
            # other columns and is not in the store. `public internal(set) var` is stored and is
            # written by exactly one owner, which is a fact about the writer, not about storage.
            declaration = re.match(
                r"public (?:internal\(set\) |private\(set\) )?var (\w+)\s*:\s*(.+)$", stripped
            )
            if not declaration:
                continue
            if "{" in declaration.group(2):
                continue
            columns.append(declaration.group(1))
        declared[(version, entity)] = columns

# The current set: for each entity name, the highest version that declares it. This is exactly
# how `FocusSchemaV<newest>.models` is composed, and deriving it rather than listing it is what
# keeps a re-declared class from leaving the lint reading the old columns.
current = {}
for (version, entity), columns in sorted(declared.items()):
    current[entity] = (version, columns)

expected_pairs = {
    (entity, column) for entity, (_, columns) in current.items() for column in columns
}

# ------------------------------------------------------------- the registry

if not os.path.exists(registry_path):
    fail(f"{registry_path} does not exist")
    sys.exit(1)

rows = {}
header_schema = None
header_entities = None

for number, raw in enumerate(open(registry_path, encoding="utf-8"), start=1):
    line = raw.rstrip("\n")
    if not line.strip() or line.lstrip().startswith("#"):
        continue

    directive = re.fullmatch(r"(SCHEMA|ENTITIES) (\d+)", line.strip())
    if directive:
        if directive.group(1) == "SCHEMA":
            header_schema = int(directive.group(2))
        else:
            header_entities = int(directive.group(2))
        continue

    parts = [part.strip() for part in line.split("|")]
    if len(parts) != 4:
        fail(
            f"{registry_path}:{number} is not four `|`-separated fields",
            f"read: {line}",
            "Rows are `<entity> | <column> | <class> | <what it is>`.",
        )
        continue

    entity, column, classification, description = parts
    if classification not in CLASSES:
        fail(
            f"{registry_path}:{number} classifies {entity}.{column} as {classification!r}",
            f"The classes are {', '.join(sorted(CLASSES))}.",
        )
    if not description:
        fail(
            f"{registry_path}:{number} classifies {entity}.{column} and says nothing about it",
            "The fourth field is what makes the row reviewable. A class with no sentence is a",
            "row somebody ticked rather than read.",
        )
    if (entity, column) in rows:
        fail(f"{registry_path}:{number} classifies {entity}.{column} twice")
    rows[(entity, column)] = classification

# ------------------------------------------------------------ the two folds

if header_schema is None:
    fail(f"{registry_path} has no `SCHEMA <n>` line")
elif header_schema != newest:
    fail(
        f"{registry_path} says SCHEMA {header_schema}; the newest schema file is v{newest}",
        "Bumping the schema means reading this file, which is the point of the line.",
    )

if header_entities is None:
    fail(f"{registry_path} has no `ENTITIES <n>` line")
elif header_entities != len(current):
    fail(
        f"{registry_path} says ENTITIES {header_entities}; {len(current)} were derived",
        "Either a @Model class arrived and has not been classified, or this parser has",
        "stopped seeing one and every check below is folded over a smaller set than it",
        "claims. Both are failures; neither is a number to bump without looking.",
    )

unclassified = sorted(expected_pairs - set(rows))
for entity, column in unclassified:
    version = current[entity][0]
    fail(
        f"{entity}.{column} (declared by FocusSchemaV{version}) has no classification",
        f"Add a row to {registry_path} saying what it is and whether it may leave the app.",
    )

orphans = sorted(set(rows) - expected_pairs)
for entity, column in orphans:
    known = entity in current
    fail(
        f"{registry_path} classifies {entity}.{column}, which the current schema does not declare",
        (
            f"{entity} is declared by FocusSchemaV{current[entity][0]} and has no such column."
            if known
            else f"No current schema entity is named {entity}."
        ),
        "A registry that describes columns nobody has is a registry nobody can trust.",
    )

# ------------------------------------------------------------------- report

print(f"     schema v{newest}, {len(current)} entities, {len(expected_pairs)} columns")
by_class = {}
for classification in rows.values():
    by_class[classification] = by_class.get(classification, 0) + 1
for classification in sorted(by_class):
    print(f"     {classification:<9} {by_class[classification]}")

if failures:
    print()
    print(
        f"EXPORT-FIELD CLASSIFICATION FAILED — {len(failures)} problem(s)",
        file=sys.stderr,
    )
    sys.exit(1)

print()
print("EXPORT-FIELD CLASSIFICATION OK")
PYTHON
rc=$?

exit $rc
