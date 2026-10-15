#!/bin/zsh
# check-grants.sh — invariant I-3: the app uses no grant it never asked for (F-128).
#
# THE DEFECT THIS CLOSES. The zero-grant doctrine is cited by five epic plans and was proved by
# four unrelated readings about three families: SC-1 (`_kCGWindowName`), R-33 (eight source-level
# request calls), R-96s (five notification selectors in the Mach-O) and one counter read out of
# the running application by `check-notification-denied.sh`. Nothing enumerated the families that
# were *not* checked, and a family nobody names is a family nobody checks. `Config/tcc-families.txt`
# is that enumeration and this is the single fold over it.
#
# WHAT IT READS, AND WHY BOTH.
#
#   the artefact       every banned selector absent from the union of `nm -u` and `strings -a` over
#                      the app's executable code, per configuration. A Swift call to a C function
#                      lands in the undefined-symbol table; an Objective-C selector lands in the
#                      string table; a family checked in only one of the two is a family half
#                      checked.
#   the running app    the self-check reports of this same run: no capability is in a state the
#                      table does not allow, `requestAuthorizationCallCount` is zero, and the
#                      on-screen authorisation-surface scan found no consent dialog while the app
#                      was up. The binary half says the app cannot ask. This half says that on a
#                      Mac where somebody granted something by hand anyway, the app still does not
#                      hold it.
#
# THE CONTROLS, because "no request selector" is the same green a binary with no relationship to
# the family at all would produce:
#
#   per family    the `controls` column names the grant-free reading the app really makes, and it
#                 must be PRESENT in each configuration examined. Ten families, six controls: the
#                 four with NONE are families the app touches in no way, and for them the claim is
#                 the global floor below rather than a symbol of their own.
#   per config    the symbol universe examined must clear a floor. A `nm` that failed, a `strings`
#                 that read a stub launcher, or a path that resolved to nothing all produce an
#                 empty universe in which every ban holds vacuously.
#   per table     the ten family names are carried here as well as in the file, so a row cannot be
#                 deleted, renamed or merged into its neighbour; every capability the table names
#                 must really be published by the app; and `available` may appear in exactly one
#                 row, whose note has to say what grant-free mechanism produces it.
#
# IT LAUNCHES NOTHING AND SIGNS NOTHING. It runs `nm` and `strings` over build products and reads
# two JSON reports the gate already produced.

set -u

export FOCUS_SCRIPTS_DIR="${0:A:h}"
REPO_ROOT="${0:A:h}/.."
cd "$REPO_ROOT" || exit 1

TABLE="Config/tcc-families.txt"
SITES="Config/grant-request-sites.txt"
USE_SITES="Config/grant-use-sites.txt"
DERIVED_DATA="${FOCUS_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Focus-default}"

if (( $# < 1 )); then
    print -u2 "usage: check-grants.sh <selfcheck.json> [<selfcheck-release.json> ...]"
    exit 1
fi
for report in "$@"; do
    if [[ ! -s "$report" ]]; then
        print -u2 "FAIL [I-3] $report is missing or empty; the running-app half has nothing to read"
        exit 1
    fi
done

# The app's executable code, per configuration, RESOLVED rather than named — the same correction
# SC-1 and R-96s needed. Under the debug-dylib layout `Contents/MacOS/FocusSentinel` is a 58 KB
# launcher whose whole symbol table is libSystem: a ban aimed at it holds of nothing and a control
# demanded of it fails for the stub.
app_code_files() {
    local config="$1" app path
    app="$DERIVED_DATA/Build/Products/$config/FocusSentinel.app/Contents/MacOS"
    for path in "$app/FocusSentinel" "$app/FocusSentinel.debug.dylib"; do
        [[ -f "$path" ]] && print -r -- "$path"
    done
}

UNIVERSE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/focus-grants.XXXXXX") || exit 1
trap 'rm -rf -- "$UNIVERSE_DIR"' EXIT INT TERM

# One file per examined binary, holding the union of its undefined symbols and its strings. The
# fold below greps that, so every family reads the same universe and the two tools cannot drift
# apart between families.
MANIFEST="$UNIVERSE_DIR/manifest.txt"
: > "$MANIFEST"
for config in Debug Release; do
    binaries=(${(f)"$(app_code_files $config)"})
    binaries=(${binaries:#})
    if (( ${#binaries} == 0 )); then
        if [[ "${FOCUS_REQUIRE_BINARY_CHECK:-0}" == "1" ]]; then
            print -u2 "FAIL [I-3] FOCUS_REQUIRE_BINARY_CHECK=1 but no $config executable exists under $DERIVED_DATA"
            exit 1
        fi
        print "     [I-3] no $config product yet — the gate runs this after the build"
        continue
    fi
    for binary in $binaries; do
        universe="$UNIVERSE_DIR/${config}-${binary:t}.txt"
        { nm -u -- "$binary" 2>/dev/null; strings -a -- "$binary" 2>/dev/null } > "$universe"
        print -r -- "$config	$binary	$universe" >> "$MANIFEST"
    done
done

print "== I-3: the ten TCC families, in the artefact and in the running application"
print "table:        $TABLE"
print "request sites: $SITES"
print "use sites:     $USE_SITES"
print "derived data: $DERIVED_DATA"
print

python3 - "$TABLE" "$SITES" "$USE_SITES" "$MANIFEST" "$@" <<'PYTHON'
import json
import os
import re
import sys

# R-168. The report dictionaries are recording ones, so the `published-keys` stage can fail on a
# fact this reader never looked at. See scripts/keyreads.py.
sys.path.insert(0, os.environ["FOCUS_SCRIPTS_DIR"])
import keyreads

table_path, sites_path, use_sites_path, manifest_path = sys.argv[1:5]
report_paths = sys.argv[5:]

# The vocabulary, carried here as well as in the file. A table that names a different set is a
# table somebody edited rather than a family that stopped existing.
FAMILIES = (
    "accessibility",
    "screenRecording",
    "automation",
    "notifications",
    "camera",
    "microphone",
    "inputMonitoring",
    "location",
    "contacts",
    "calendar",
)

# The capabilities the app publishes that stand for a TCC family. Committed here so that a
# capability quietly dropped from a row is a failure rather than one fewer assertion.
CAPABILITIES_CLAIMED = {
    "accessibilityWindowContext",
    "screenCapture",
    "notifications",
    "cameraActivity",
    "microphoneActivity",
}

# The symbol-universe floor, per binary examined. Measured at 9af6d0c: the Release executable
# yields 1 791 undefined symbols and 83 934 strings; the Debug launcher stub is excluded by
# `app_code_files` resolving the dylib beside it. A universe under this floor means `nm` failed,
# `strings` read a stub, or the path resolved to something that is not this application — in every
# one of which cases each ban below holds vacuously.
UNIVERSE_FLOOR = 2000

failures = []


def check(condition, message, detail=None):
    if condition:
        print(f"ok   [I-3] {message}")
        return
    line = f"FAIL [I-3] {message}"
    if detail is not None:
        line += f"\n      got: {detail!r}"
    failures.append(line)
    print(line, file=sys.stderr)


# ---------------------------------------------------------------------------- the table

rows = {}
malformed = []
with open(table_path) as handle:
    for number, raw in enumerate(handle, start=1):
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = [part.strip() for part in line.split("·")]
        if len(parts) != 6 or not all(parts):
            malformed.append((number, line))
            continue
        family, banned, controls, capability, states, note = parts
        rows[family] = {
            "banned": [] if banned == "NONE" else [s.strip() for s in banned.split(",") if s.strip()],
            "controls": [] if controls == "NONE" else [s.strip() for s in controls.split(",") if s.strip()],
            "capability": None if capability == "NONE" else capability,
            "states": set() if states == "NONE" else {s.strip() for s in states.split(",") if s.strip()},
            "note": note,
        }

check(not malformed, "every row of the table has six non-empty columns", malformed)
check(
    set(rows) == set(FAMILIES),
    "the table names the ten committed families and nothing else",
    sorted(set(rows) ^ set(FAMILIES)),
)
check(
    {row["capability"] for row in rows.values() if row["capability"]} == CAPABILITIES_CLAIMED,
    "every capability that stands for a TCC family is claimed by exactly one row",
    sorted({row["capability"] for row in rows.values() if row["capability"]} ^ CAPABILITIES_CLAIMED),
)
# `available` is the state that would mean the app holds the grant. Exactly one family may report
# it, and that family owes a sentence saying what grant-free mechanism produces it.
# AMENDED 2026-09-09 (focus-exdi.4). Two more families may read it, and for a different reason:
# the person switched the ask on and macOS agreed. That is still not the app taking a grant it
# never asked for — it is the only route this application has to a grant at all — and each row
# owes the same sentence saying so.
available_rows = sorted(name for name, row in rows.items() if "available" in row["states"])
check(
    available_rows == ["accessibility", "microphone", "screenRecording"],
    "only the microphone property read and the two opt-in families may read 'available'",
    available_rows,
)
for name in available_rows:
    check(
        len(rows[name]["note"]) >= 40,
        f"the {name} row says in a sentence why 'available' is not a grant",
        rows[name]["note"],
    )
# A banned column that emptied out is a family that stopped being checked.
for name in sorted(rows):
    check(
        len(rows[name]["banned"]) >= 3,
        f"the {name} row bans at least three ways of asking",
        rows[name]["banned"],
    )

# ------------------------------------------------------------------- the confinement half
#
# focus-exdi.4. The two opt-in families' REQUEST selectors are no longer banned from the
# artefact; they are confined to one named source file instead. A ban that simply lifted would
# prove nothing, so this is what replaces it: the selector exists in exactly one file, and that
# file is the one the registry names. A second site is a second door.

BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)
MULTILINE_STRING = re.compile(r'"""(?:.|\n)*?"""')
STRING = re.compile(r'"(?:\\.|[^"\\\n])*"')
LINE_COMMENT = re.compile(r"//[^\n]*")


def code_only(text):
    """The file with its comments and string literals removed.

    A selector NAMED in a doc comment is not a door — three files explain in prose why the app
    does not call these, and a search that could not tell prose from code would make the honest
    explanation the violation. Same treatment `scripts/find-numeric-literals.py` gives R-70f.
    """
    text = BLOCK_COMMENT.sub(" ", text)
    text = MULTILINE_STRING.sub(" ", text)
    text = STRING.sub(" ", text)
    return LINE_COMMENT.sub(" ", text)


def read_registry(registry_path):
    found = {}
    malformed = []
    with open(registry_path) as handle:
        for number, raw in enumerate(handle, start=1):
            line = raw.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = [part.strip() for part in line.split("·")]
            if len(parts) != 2 or not all(parts):
                malformed.append((number, line))
                continue
            path, selectors = parts
            found[path] = [s.strip() for s in selectors.split(",") if s.strip()]
    return found, malformed


request_sites, sites_malformed = read_registry(sites_path)
check(not sites_malformed, "every row of the request-site registry has two non-empty columns", sites_malformed)
check(request_sites, "the registry names at least one request site", sorted(request_sites))
request_selectors = sorted({s for selectors in request_sites.values() for s in selectors})
check(
    len(request_selectors) >= 2,
    "control: the registry confines at least two request selectors",
    request_selectors,
)

# Issue #24 (owner's ruling 2026-10-15). The accessibility family's READ selectors left the
# banned column and are confined the same way, to the one reader file the use registry names.
use_sites, use_malformed = read_registry(use_sites_path)
check(not use_malformed, "every row of the use-site registry has two non-empty columns", use_malformed)
check(len(use_sites) == 1, "the use registry names exactly one reader file", sorted(use_sites))
use_selectors = sorted({s for selectors in use_sites.values() for s in selectors})
check(
    {"AXUIElementCreateApplication", "AXUIElementCopyAttributeValue"} <= set(use_selectors),
    "control: the use registry confines the two Accessibility read selectors",
    use_selectors,
)
# kCGWindowName stays banned by SC-1: the title is read through Accessibility, never the list.
check(
    not any("kCGWindow" in s for s in use_selectors),
    "no window-list key is confined as a use site (SC-1 still bans it)",
    use_selectors,
)
check(
    not (set(request_selectors) & set(use_selectors))
    and not (set(request_sites) & set(use_sites)),
    "the ask and the read live in different files and share no selector",
    (sorted(set(request_selectors) & set(use_selectors)), sorted(set(request_sites) & set(use_sites))),
)

sites = {**request_sites, **use_sites}
confined_selectors = sorted({selector for selectors in sites.values() for selector in selectors})
# A selector may not be both confined and banned: that would be a family claiming two answers.
banned_everywhere = {selector for row in rows.values() for selector in row["banned"]}
check(
    not (set(confined_selectors) & banned_everywhere),
    "no selector is both confined and banned",
    sorted(set(confined_selectors) & banned_everywhere),
)

source_files = []
for root, directories, names in os.walk("."):
    directories[:] = [d for d in directories if d not in {".build", ".git", "DerivedData"}]
    if not (root.startswith("./Packages") or root.startswith("./App")):
        continue
    for name in names:
        if name.endswith(".swift"):
            source_files.append(os.path.join(root, name))
check(
    len(source_files) >= 200,
    "control: the source tree searched for a second door is a real one",
    len(source_files),
)

for path, selectors in sorted(sites.items()):
    check(os.path.exists(path), f"the registry's site {path} exists", path)
    try:
        with open(path, errors="replace") as handle:
            body = code_only(handle.read())
    except OSError:
        body = ""
    for selector in selectors:
        check(selector in body, f"{path} names {selector}, as the registry says", selector)
        elsewhere = sorted(
            other
            for other in source_files
            if os.path.abspath(other) != os.path.abspath(path)
            and selector in code_only(open(other, errors="replace").read())
        )
        check(
            not elsewhere,
            f"{selector} appears in one file only, and it is the one its registry names",
            elsewhere,
        )

# ---------------------------------------------------------------------- the artefact half

binaries = []
with open(manifest_path) as handle:
    for line in handle:
        line = line.rstrip("\n")
        if not line:
            continue
        config, path, universe = line.split("\t")
        with open(universe, errors="replace") as text:
            binaries.append((config, path, text.read().splitlines()))

required = os.environ.get("FOCUS_REQUIRE_BINARY_CHECK", "0") == "1"
if not binaries and not required:
    print("     [I-3] SKIPPED — nothing built yet (the gate runs this after the build)")
else:
    check(binaries, "at least one build product was examined", len(binaries))

configs = sorted({config for config, _, _ in binaries})
if binaries:
    check(
        configs == ["Debug", "Release"],
        "both configurations were examined; the Release product is the one that ships",
        configs,
    )

# Judged per CONFIGURATION and not per file. Under the debug-dylib layout the executable beside
# the dylib is a launcher stub whose whole symbol table is libSystem: demanding the floor of it
# would fail for the stub while the bans held for the code, which is two halves of one wrong
# subject. What has to be true is that each configuration handed this fold a real application.
for config in configs:
    widest = max(
        (len(universe) for seen, _, universe in binaries if seen == config),
        default=0,
    )
    check(
        widest >= UNIVERSE_FLOOR,
        f"control: the {config} product yields a symbol universe worth searching",
        (widest, UNIVERSE_FLOOR),
    )

# The ban. Substring matching, because a selector appears in the string table with its
# Objective-C decoration and a C function appears in `nm` with a leading underscore.
for name in FAMILIES:
    row = rows.get(name)
    if row is None:
        continue
    for selector in row["banned"]:
        hits = [
            (config, os.path.basename(path))
            for config, path, universe in binaries
            if any(selector in entry for entry in universe)
        ]
        check(
            not hits,
            f"{name}: the artefact carries no {selector}",
            hits,
        )

# The control, judged PER CONFIGURATION rather than once for the pair — the correction R-96s
# needed. A single flag across both lanes is satisfied by whichever lane still carries the reading,
# so a Release build that dropped the framework would pass a ban vouched for by the Debug binary
# beside it.
for name in FAMILIES:
    row = rows.get(name)
    if row is None or not row["controls"]:
        continue
    for config in configs:
        here = [universe for seen, _, universe in binaries if seen == config]
        found = [
            control
            for control in row["controls"]
            for universe in here
            if any(control in entry for entry in universe)
        ]
        check(
            found,
            f"control: {name} is still read grant-free in {config} ({'/'.join(row['controls'])})",
            row["controls"],
        )

families_without_a_control = sorted(name for name in rows if not rows[name]["controls"])
print(
    "     [I-3] {} families checked; {} carry a grant-free reading of their own, {} are untouched: {}".format(
        len(rows),
        len(rows) - len(families_without_a_control),
        len(families_without_a_control),
        ", ".join(families_without_a_control),
    )
)

# ------------------------------------------------------------------- the running-app half

for report_path in report_paths:
    with open(report_path) as handle:
        report = keyreads.record(json.load(handle))
    label = os.path.basename(report_path)

    declared = report.get("capabilityStatesDeclared") or []
    check(
        set(declared) >= {"available", "denied", "restricted", "unavailable", "notRequested"},
        f"{label}: the app declares the five capability states the table is written against",
        declared,
    )

    published = {}
    for entry in report.get("capabilities") or []:
        published[entry.get("capability")] = entry.get("state")
    check(
        len(published) >= len(CAPABILITIES_CLAIMED),
        f"{label}: the report really published a capability table",
        len(published),
    )
    for name in FAMILIES:
        row = rows.get(name)
        if row is None or not row["capability"]:
            continue
        state = published.get(row["capability"])
        check(
            state in row["states"],
            f"{label}: {name} ({row['capability']}) is in a state the table allows, not a held grant: {state!r}",
            (state, sorted(row["states"])),
        )

    # It never asked. The counter is the app's own, incremented at the one call site that could
    # ever have asked; R-96g bans the call from the source and the artefact half bans the selector
    # from the binary, so this is the third independent reading of one fact.
    check(
        report.get("requestAuthorizationCallCount") == 0,
        f"{label}: requestAuthorizationCallCount is zero — the app asked for nothing",
        report.get("requestAuthorizationCallCount"),
    )

    # And no consent dialog appeared while it ran. The scan is a window-list read of the owners on
    # screen; `wasTaken` is its own non-vacuity flag and `windowsOwnedByThisProcess` is the control
    # that says the scan could see this application at all.
    scan = report.get("authorisationSurfaceScan") or {}
    if scan.get("wasTaken") is True:
        check(
            scan.get("windowsOwnedByThisProcess", 0) >= 1,
            f"{label}: control: the authorisation-surface scan could see this app's own window",
            scan.get("windowsOwnedByThisProcess"),
        )
        # **A DELTA, not a photograph of the screen** (focus-p3dl). `suspects` is the set of
        # authorisation-surface owners whose windows were NOT on the screen before the app
        # launched: a dialog somebody else's tool had open is a property of this Mac, and I-3 is
        # a claim about this application. The pre-existing set is named in the line so a reader
        # can see what was excused and satisfy themselves it was not the app's.
        preexisting = scan.get("preexistingAuthorisationSurfaceOwners") or []
        excused = (
            "; pre-existing, not this app's: {} in {} window(s)".format(
                ", ".join(preexisting),
                scan.get("preexistingAuthorisationSurfaceWindows"),
            )
            if preexisting
            else ""
        )
        check(
            (scan.get("suspects") or []) == [],
            f"{label}: no authorisation surface appeared while the app ran{excused}",
            scan.get("suspects"),
        )
        # The baseline is the subtraction's own non-vacuity fact: a delta taken against a
        # baseline nobody read is the whole suspect list with a kinder name.
        check(
            scan.get("baselineWasTaken") is True,
            f"{label}: control: a pre-launch baseline was taken to subtract — {scan.get('baselineNotTakenBecause')!r}",
            scan.get("baselineWindowCount"),
        )
        check(
            (scan.get("ownerCount") or 0) >= 1,
            f"{label}: control: the scan saw a window list rather than an empty one",
            scan.get("ownerCount"),
        )
    else:
        print(
            "     [I-3] {}: the authorisation-surface scan was not taken — {}".format(
                label, scan.get("notTakenBecause") or "no reason given"
            )
        )

print()
if failures:
    print(f"I-3 FAILED: {len(failures)} finding(s)", file=sys.stderr)
    sys.exit(1)
print("I-3: no grant asked for, and none held.")
PYTHON
