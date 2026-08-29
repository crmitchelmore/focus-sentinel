#!/bin/zsh
# Gate stage `notification-denied` — **F-73's degraded path, as an automated gate** (§4.5, R-82).
#
#   scripts/check-notification-denied.sh <path to FocusSentinel.app>
#
# **This is what discharges standing condition 5 for e05.** The whole epic's headline behaviour —
# a two-rung ladder that reaches somebody — must work on a Mac that has granted the app nothing,
# and must reach that state without ever putting a permission dialog on the screen.
#
# ## What P-134 measured, and why the router needs no grant
#
# From an ad-hoc-signed bundle at zero grants, **without ever calling `requestAuthorization`**:
#
#     authorizationStatus            0  (.notDetermined)
#     every setting                  0  (.notSupported)
#     setNotificationCategories      registered 0 categories — it does not take while unauthorised
#     add(request)                   UNErrorDomain code 1, "Notifications are not allowed"
#
# `getNotificationSettings` is obtainable, answers completely and **never prompts**. It is now the
# only thing this app ever asks the notification centre, and `requestAuthorization` appears in
# **no** file of this repository (lint R-96g, which passes at zero files) — so
# `requestAuthorizationCallCount == 0` is a fact about the call graph rather than a number
# somebody remembered to leave alone.
#
# ## Why ONE routing table is asserted, and not three (focus-wy0)
#
# It used to be three. This Mac's own authorisation is whatever a person set it to, so the
# self-check also asked `SurfaceRouter.route(…)` what it would do at `denied` and at
# `notRequested` — otherwise a stage would silently stop asserting the degraded path the moment
# somebody granted notifications.
#
# That was the right shape while the authorisation was a routing input. U-2 removed the only rung
# that could reach a notification, and from then on all three tables came back byte-identical in
# every run: the same reading printed three times, which reads like corroboration and is
# repetition. `SurfaceRouter.route(…)` no longer accepts an authorisation at all, so "denied,
# notRequested and authorised deliver alike" is a fact about the function's type, and the thing
# left to assert is the **shape of what the settings pane renders** — `routingRowFields`, read off
# the compiled `SurfaceRoutingRow` with `Mirror`. A route reading could not catch the column
# coming back, because every route would be identical; the row is what would change.
#
# ## Zero grants
#
# A plain `exec` of the built binary. No `osascript`, no `screencapture`, no Automation, and no
# prompt of any kind — for the app or for this shell.
set -u

REPO_ROOT="${0:A:h}/.."
cd "$REPO_ROOT" || exit 1

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

OUT="${FOCUS_NOTIFICATION_DENIED_JSON:-$(mktemp -t focus-notification-denied).json}"
rm -f -- "$OUT"

print "NOTIFICATION-DENIED — F-73's degraded path (§4.5, R-82, P-134)"
print "app:    $APP"
print "report: $OUT"
print

print "== $BINARY --focus-self-check $OUT --focus-self-check-nudge"
"$BINARY" --focus-self-check "$OUT" --focus-self-check-nudge
run_rc=$?
print "launch EXIT=$run_rc"

if (( run_rc != 0 )); then
    print -u2 "FAIL: the app exited $run_rc during its nudge self-check"
    exit 1
fi
if [[ ! -s "$OUT" ]]; then
    print -u2 "FAIL: the app wrote no nudge report at $OUT"
    exit 1
fi

# The committed intervention digest, read from the one place it is written down — the same
# instrument `self-check.sh` and the evaluation stage use, so three legs compare against one
# literal rather than three copies of a string.
committed_literal() {
    local file="$1" name="$2" line
    line=$(grep -E "static let ${name}\b" "$REPO_ROOT/$file" 2>/dev/null | head -1)
    [[ -n "$line" ]] || return 0
    print -r -- "${${line#*= }//[\"_ ]/}"
}
COMMITTED_INTERVENTION_DIGEST=$(committed_literal \
    "Packages/FocusCore/Tests/FocusCoreTests/InterventionPolicyTests.swift" \
    "committedDigest")

print
print "== assertions"
python3 - "$OUT" "$COMMITTED_INTERVENTION_DIGEST" <<'PYTHON'
import json
import sys

report_path, committed_digest = sys.argv[1], sys.argv[2]

with open(report_path) as handle:
    report = json.load(handle)

failures = []


def check(condition, message, detail=None):
    if condition:
        print(f"ok   {message}")
        return
    line = f"FAIL {message}"
    if detail is not None:
        line += f"\n      got: {detail!r}"
    failures.append(line)
    print(line, file=sys.stderr)


def surfaces(table):
    return [entry.get("surface") for entry in table or []]


check(report.get("mode") == "nudge", "the app ran its nudge-only self-check", report.get("mode"))

# --- SC-5, and it is the number the whole epic turns on ----------------------------------------
#
# `requestAuthorization` appears in NO file of the repository (focus-wy0), so no routing path, no
# host, no settings pane and no gate stage can reach it. The lint proves the shape; this proves
# the run.
check(
    report.get("requestAuthorizationCallCount") == 0,
    "the application asked for no notification authorisation",
    report.get("requestAuthorizationCallCount"),
)
check(
    report.get("notificationAuthorisation")
    in ("authorised", "denied", "notRequested", "provisional"),
    "the authorisation was read through getNotificationSettings and decoded to one of four",
    report.get("notificationAuthorisation"),
)
print(f"note this Mac reports {report.get('notificationAuthorisation')!r}")

# **The routing does not read it, and the pane does not draw it** (focus-wy0).
#
# `SurfaceRoutingRow` is what `SurfaceRouter.table(...)` is made of and what the Intervention pane
# renders row for row. An authorisation column here is the defect returning: four rows per rung,
# four headings, one route — a pane promising a consequence the router does not produce.
check(
    report.get("routingRowFields") == ["route", "rung"],
    "a routing row the settings pane draws carries a rung and a route, and nothing else",
    report.get("routingRowFields"),
)

# --- D-06 as amended by U-2: two rungs, no more and no fewer -----------------------------------
check(
    report.get("ladderRungsDeclared") == 2,
    "the ladder declares exactly two rungs",
    report.get("ladderRungsDeclared"),
)

# --- the degraded path, which is now the ONLY path ---------------------------------------------
#
# Whatever this Mac says about notifications, both rungs land on a surface a person can see —
# and there is no longer a second answer for them to land differently in.
table = report.get("routes")
check(bool(table), "the router's table was reported", table)
if table:
    check(
        len(table) == 2,
        "the table covers both rungs",
        [entry.get("rung") for entry in table],
    )
    check(
        all(entry.get("surface") for entry in table),
        "EVERY rung reaches a surface",
        surfaces(table),
    )
    check(
        report.get("everyRungIsInApp") is True,
        "every rung is delivered IN-APP",
        surfaces(table),
    )
    check(
        all(entry.get("surface") != "notification" for entry in table),
        "no rung routes to a notification",
        surfaces(table),
    )
    check(
        report.get("surfacesARungCanReach") == ["menuBar", "panel"],
        "the only surfaces any rung reaches are the glyph and the panel",
        report.get("surfacesARungCanReach"),
    )
    top = [entry for entry in table if entry.get("rung") == "panel"]
    check(len(top) == 1, "the ladder has a panel rung", table)
    if top:
        check(
            top[0].get("surface") == "panel",
            "the top rung lands on the panel",
            top[0],
        )
        check(
            top[0].get("rank") == 1,
            "the panel rung is the top of the ladder",
            top[0],
        )

# A question is never a notification (R-82): its route takes no authorisation at all.
check(
    report.get("querySurface") in ("panel", "popoverBadge"),
    "a question routes to an in-app surface and never to a notification",
    report.get("querySurface"),
)

# --- the correction economy has a surface to be on ---------------------------------------------
#
# Rung 3 landing on "the panel" means nothing if the panel is not a real, correctly configured
# window. R-89's six properties are asserted on the object the application actually showed.
panel = report.get("panel") or {}
check(panel.get("wasVisible") is True, "the panel the top rung falls back to really appears", panel.get("wasVisible"))
check(
    panel.get("propertiesAreCorrect") is True,
    "that panel is non-activating, key-capable, never main and never hides on deactivate",
    panel.get("properties"),
)
check(
    panel.get("hiddenAfter") is True,
    "the panel was put away again, so this stage leaves no window on the screen",
    panel.get("hiddenAfter"),
)

# The menu bar is really installed, so the ambient rung has somewhere to be.
check(
    report.get("menuBarInstalled") is True,
    "the menu-bar command centre is installed, so rung 1 has a surface",
    report.get("menuBarInstalled"),
)

# --- the engine that produced all of this ------------------------------------------------------
check(
    bool(committed_digest),
    "the committed intervention digest was found in InterventionPolicyTests",
    committed_digest,
)
check(
    report.get("interventionDigest") == committed_digest,
    f"the running application's intervention digest is {committed_digest}",
    report.get("interventionDigest"),
)

print()
if failures:
    print(f"NOTIFICATION-DENIED FAILED — {len(failures)} assertion(s)", file=sys.stderr)
    sys.exit(1)
print("NOTIFICATION-DENIED OK — every rung reaches a person with nothing granted and nothing asked")
PYTHON
rc=$?

exit $rc
