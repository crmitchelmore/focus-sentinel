#!/bin/zsh
# authorisation-baseline.sh — the windows that were on the screen BEFORE the app was (focus-p3dl).
#
# SOURCE THIS, do not run it. It defines one function, `focus_take_authorisation_baseline`, which
# every script that launches the application calls once, before the launch.
#
# THE DEFECT THIS CLOSES. `SelfCheck.authorisationSurfaceReport()` is the gateable form of R-33 —
# *the app never triggers a permission prompt*. It was written as "no authorisation-surface owner
# is on the screen at all", and that is a different claim: it is a claim about the Mac. On
# 2026-09-05 the difference was measured. An unrelated tool had a `UserNotificationCenter` alert
# open asking for access to a removable volume — pid 56791, a window that predated the checkout —
# and `selfcheck-debug`, `selfcheck-release` and `grants` went red with
#
#     FAIL no authorisation surface is on screen while the app runs
#           got: ['UserNotificationCenter']
#
# for a decision that belonged to the person sitting at the machine. The gate does not get to
# dismiss somebody's permission dialog to make itself green, so the reading became a DELTA:
# what is on the screen after the app launched, minus what was on it before.
#
# WHAT IT WRITES. `<windowNumber>\t<ownerName>` for every on-screen window at every layer, from
# `Tools/windowid --window-owners` — a grant-free `CGWindowListCopyWindowInfo` read of four keys,
# none of them a window name (standing condition 1). The file's path goes into
# `FOCUS_AUTHORISATION_BASELINE`, which the app reads at the moment it takes its own scan.
#
# WHY THE TOOL AND NOT THE APP. The baseline has to be taken by a process that is not the process
# under test, and before it exists. `windowid` is the only reader of the window list this
# repository has outside the app, it already lives outside the app's package graph, and it already
# never asks for `kCGWindowName`.
#
# WHY IT FILTERS NOTHING. The six owner names a permission dialog belongs to live in
# `SelfCheck.authorisationSurfaceOwners` and nowhere else. A copy of that list here would be a
# second place to change, and a baseline filtered through a stale copy would quietly stop covering
# a name the app had started watching for. So the baseline is every window, and the app subtracts.
#
# NOT TAKEN IS A STATE. If the tool cannot be built or the window server names nobody, the file is
# left absent and the variable unset: the app then reports `baselineWasTaken == false`, subtracts
# nothing, and the gate fails that fact by name rather than passing on a subtraction it did not
# make.

# Take the baseline and export FOCUS_AUTHORISATION_BASELINE.
#
#   $1  where to write the baseline (a path this caller owns and cleans up)
#
# Always returns 0: a baseline that could not be taken is a fact the app publishes, not a reason
# for the launching script to stop before it has launched anything.
FOCUS_BASELINE_SCRIPTS_DIR="${0:A:h}"

focus_take_authorisation_baseline() {
    local out="$1"
    local repo="${FOCUS_SCRIPTS_DIR:-$FOCUS_BASELINE_SCRIPTS_DIR}/.."
    local tool="$repo/Tools/windowid/.build/release/windowid"

    if [[ ! -x "$tool" ]]; then
        # The gate builds this at the `forbidden-binary` stage, long before any launch; a hand run
        # of one script builds it here. Unpiped, into a log of its own, like every other build.
        swift build -c release --package-path "$repo/Tools/windowid" \
            > "${TMPDIR:-/tmp}/focus-authorisation-baseline-build.log" 2>&1
    fi
    if [[ ! -x "$tool" ]]; then
        print "     baseline: NOT TAKEN — no windowid at $tool"
        unset FOCUS_AUTHORISATION_BASELINE
        return 0
    fi

    if ! "$tool" --window-owners > "$out" 2>/dev/null; then
        print "     baseline: NOT TAKEN — the window server named nobody at all"
        rm -f -- "$out"
        unset FOCUS_AUTHORISATION_BASELINE
        return 0
    fi

    export FOCUS_AUTHORISATION_BASELINE="$out"
    print "     baseline: $(wc -l < "$out" | tr -d ' ') window(s) on screen before the launch → $out"
    return 0
}
