"""Record which self-check report keys a gate reader actually looked at (R-168).

WHY THIS EXISTS. `SelfCheck` publishes several hundred facts about the running application.
A fact nobody reads is not evidence; it is a number in a file. The `published-keys` stage
(`scripts/check-published-keys.sh`) fails the gate when a published key is read by nothing and
is not listed, with a reason, in `Config/unasserted-keys.txt`.

WHY IT INSTRUMENTS RATHER THAN GREPS. The obvious implementation — grep the reader scripts for
each key's name — is provably wrong in both directions. It over-counts, because a name read in
one section of the report counts as read in every other section that spells it the same way;
and it under-counts, because `scripts/self-check.sh` indexes dynamically (`for flag in
("titled", "closable", ...): style.get(flag)`), so the key never appears as a literal at the
read site at all. So the reader records what it *did*: every dictionary in the loaded report is
replaced by a `_Recording` that knows its own dotted path and notes every key that is fetched
through it. The 180-odd `check(...)` sites are not touched.

The dotted path of a list element is the list's own path — `windows[].styleMask.titled` is the
single path `windows.styleMask.titled`, not eleven of them. That is the same shape the publish
walk in `check-published-keys.sh` emits, and it is honest here because every array in this
report is homogeneous: the elements are the same kind of thing, so a reading taken of one of
them is a reading of that field.

Recording is always on — a `dict` subclass behaves exactly like a `dict`, so a hand run of the
reader exercises the same code the gate does. Only the flush is conditional: with
`FOCUS_KEYS_READ` unset nothing is written and nothing is read of the result.
"""

import atexit
import os

_OUT = os.environ.get("FOCUS_KEYS_READ") or ""

# Every dotted path any reader in this process fetched. One process per stage; the gate points
# all five readers at one file and each appends.
READ = set()


class _Recording(dict):
    """A `dict` that remembers where it lives and notes what is asked of it."""

    __slots__ = ("_focus_path",)

    def __init__(self, items, path):
        dict.__init__(self, items)
        self._focus_path = path

    def _note(self, key):
        if isinstance(key, str):
            READ.add(f"{self._focus_path}.{key}" if self._focus_path else key)

    def __getitem__(self, key):
        self._note(key)
        return dict.__getitem__(self, key)

    def get(self, key, default=None):
        self._note(key)
        return dict.get(self, key, default)

    def __contains__(self, key):
        self._note(key)
        return dict.__contains__(self, key)


def record(node, path=""):
    """Return `node` with every dictionary inside it replaced by a recording one."""
    if isinstance(node, dict):
        return _Recording(
            {
                key: record(value, f"{path}.{key}" if path else key)
                for key, value in node.items()
            },
            path,
        )
    if isinstance(node, list):
        return [record(value, path) for value in node]
    return node


def also_read(paths):
    """Fold in paths a reader knows it consumed without a dictionary fetch.

    `self-check.sh`'s `taken(subject, path)` is the case: it walks to the reading's
    `wasTaken`/`notTakenBecause` pair and the sweep at the foot of that script folds every
    takenness fact over the set of routed ones. Those are reads, and they are recorded as such.
    """
    for path in paths:
        if isinstance(path, str):
            READ.add(path)


@atexit.register
def _flush():
    if not _OUT or not READ:
        return
    with open(_OUT, "a") as handle:
        for path in sorted(READ):
            handle.write(path + "\n")
