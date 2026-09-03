#!/bin/zsh
# check-published-keys.sh — R-168. Every fact the self-check publishes is read by somebody.
#
# THE DEFECT THIS CLOSES. `SelfCheck` writes several hundred facts about the running
# application, and until this round a quarter of them were fetched by no reader at all. A fact
# nobody reads is not evidence; it is a number in a file. Three beads in the e10 set —
# `focus-9o8` (the charging invariant), `focus-d2d` (`skippedRuleCount`) and `focus-8kw` (the
# two surface lists) — are the same defect found one key at a time. This is the rule that
# stops the class rather than its members.
#
# WHAT IT COMPARES. Two artefacts of the SAME gate run, never a script's text:
#
#   published  — every dotted path in the Release self-check report and its Debug twin. A list's
#                elements share their list's own path, because the arrays in this report are
#                homogeneous: `windows[].titled` is the single path `windows.titled`.
#   read       — every dotted path a reader really fetched, recorded at runtime by
#                `scripts/keyreads.py`, which replaces every dictionary in a loaded report with
#                one that notes what is asked of it. Five stages append to one file:
#                selfcheck-debug, focus-steal, notification-denied, selfcheck-release and the
#                two Release twins of the last two.
#
# WHY NOT A GREP. A grep over the readers is wrong in both directions. It over-counts, because a
# key read in one section of the report counts as read in every section that spells it the same;
# and it under-counts, because `self-check.sh` indexes dynamically — `for flag in ("titled",
# "closable", ...)` — so the key is never a literal at the read site. The static estimates this
# round started from were 426 and 481 published; the runtime walk says 772.
#
# THE LINT, BOTH WAYS. `Config/unasserted-keys.txt` carries the exceptions, and every one of the
# four rules below can fail, so the list cannot become the gate's off-switch:
#
#   1. published − read must be a subset of the list; otherwise a new unread key is a failure.
#   2. every listed path must still be published; otherwise the list rots invisibly.
#   3. every listed path must still be unread; otherwise a key that gained an assertion goes on
#      being excused, and the next unread key can be hidden by editing its neighbour's row.
#   4. every row must carry a non-empty reason and a bead column.
#
# And one floor, because all four rules are satisfied by a read set that is empty for the wrong
# reason — a reader that died before its first fetch, or instrumentation that stopped recording:
# the count of published keys really read must not fall below READ_FLOOR.
#
# IT SIGNS NOTHING, LAUNCHES NOTHING AND READS NO SOURCE. It reads two JSON reports, one text
# file the gate wrote, and one committed list.

set -u

REPO_ROOT="${0:A:h}/.."
cd "$REPO_ROOT" || exit 1

LIST="Config/unasserted-keys.txt"

if [[ -z "${FOCUS_KEYS_READ:-}" ]]; then
    print -u2 "FAIL [R-168] FOCUS_KEYS_READ is unset, so no reader recorded what it read"
    exit 1
fi
if [[ ! -s "$FOCUS_KEYS_READ" ]]; then
    print -u2 "FAIL [R-168] $FOCUS_KEYS_READ is empty: no gate reader recorded a single fetch"
    exit 1
fi
if (( $# < 1 )); then
    print -u2 "usage: check-published-keys.sh <selfcheck.json> [<selfcheck-release.json> ...]"
    exit 1
fi
for report in "$@"; do
    if [[ ! -s "$report" ]]; then
        print -u2 "FAIL [R-168] $report is missing or empty; the stage has nothing to read"
        exit 1
    fi
done

python3 - "$LIST" "$FOCUS_KEYS_READ" "$@" <<'PYTHON'
import json
import sys

list_path, read_path = sys.argv[1], sys.argv[2]
report_paths = sys.argv[3:]

# The floor. It is a committed number rather than a ratio so that a round which publishes fifty
# new keys and reads none of them cannot satisfy it by growing the denominator.
READ_FLOOR = 700

failures = []


def check(condition, message, detail=None):
    if condition:
        print(f"ok   {message}")
        return
    line = f"FAIL [R-168] {message}"
    if detail is not None:
        line += f"\n      got: {detail!r}"
    failures.append(line)
    print(line, file=sys.stderr)


def walk(node, path, out):
    """Every dotted path in a report. A list's elements share the list's own path."""
    if isinstance(node, dict):
        for key, value in node.items():
            here = f"{path}.{key}" if path else key
            out.add(here)
            walk(value, here, out)
    elif isinstance(node, list):
        for value in node:
            walk(value, path, out)


published = set()
for report_path in report_paths:
    with open(report_path) as handle:
        walk(json.load(handle), "", published)

with open(read_path) as handle:
    read = {line.strip() for line in handle if line.strip()}

listed = {}
malformed = []
with open(list_path) as handle:
    for number, raw in enumerate(handle, start=1):
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = [part.strip() for part in line.split("·")]
        if len(parts) != 3 or not all(parts):
            malformed.append((number, line))
            continue
        listed[parts[0]] = (parts[1], parts[2])

print(f"note {len(published)} keys published across {len(report_paths)} report(s)")
print(f"note {len(published & read)} of them were read by a gate reader")
print(f"note {len(listed)} listed in {list_path}")

# Rule 4 first, because a malformed row is not a row and the three rules below would read it wrong.
check(not malformed, "every row carries a path, a reason and a bead column", malformed)

unread = published - read
# Rule 1.
unlisted = sorted(unread - set(listed))
check(
    not unlisted,
    "every published key is either read by a gate reader or listed with a reason",
    unlisted,
)
# Rule 2. A row for a key that is no longer published is a claim about a report that no longer
# exists, and it is how a list stops describing the thing it excuses.
rotted = sorted(key for key in listed if key not in published)
check(not rotted, "every listed key is still published by the self-check", rotted)
# Rule 3. Without this the list is an off-switch: a key that gained an assertion would go on
# being excused, and the row could be edited to cover its unread neighbour instead.
now_read = sorted(key for key in listed if key in read)
check(
    not now_read,
    "no listed key is now read; a key that gained an assertion loses its row",
    now_read,
)
# The floor.
check(
    len(published & read) >= READ_FLOOR,
    f"at least {READ_FLOOR} published keys were really fetched by a reader",
    len(published & read),
)

print()
if failures:
    print(f"PUBLISHED-KEYS FAILED — {len(failures)} rule(s)", file=sys.stderr)
    sys.exit(1)
print(
    f"PUBLISHED-KEYS OK — {len(published)} published, {len(published & read)} read, "
    f"{len(listed)} listed"
)
PYTHON
