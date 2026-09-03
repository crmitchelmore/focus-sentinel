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
# The committed decode table, read the same way from the file that owns it (focus-652). It is the
# subject of the reading that replaced "the authorisation is one of the four values the decoder is
# total over" — a restatement of a codomain that no change to the decode could turn red.
COMMITTED_DECODE_TABLE=$(committed_literal \
    "Packages/FocusUI/Tests/FocusUITests/NotificationDeliveryTests.swift" \
    "committedDecodeTable")
COMMITTED_DECODE_CELLS=$(committed_literal \
    "Packages/FocusUI/Tests/FocusUITests/NotificationDeliveryTests.swift" \
    "committedDecodeCells")

print
print "== assertions"
python3 - "$OUT" "$COMMITTED_INTERVENTION_DIGEST" \
    "$COMMITTED_DECODE_TABLE" "$COMMITTED_DECODE_CELLS" <<'PYTHON'
import json
import sys

report_path, committed_digest = sys.argv[1], sys.argv[2]
committed_decode_table, committed_decode_cells = sys.argv[3], sys.argv[4]

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

# --- the authorisation reading, which used to be a statement about a type (focus-652) ----------
#
# THIS BLOCK REPLACES A CHECK THAT COULD NOT GO RED. It read:
#
#     report["notificationAuthorisation"] in ("authorised","denied","notRequested","provisional")
#
# under the pass line "the authorisation was READ THROUGH getNotificationSettings". Those four
# strings are the entire codomain of `NotificationAuthorisation.decode(authorizationStatus:)`,
# which is an exhaustive switch with `default: .denied` — so every integer the OS can send, and
# every integer it cannot, satisfies it by construction. It restated the decoder's type. And it
# could not see the thing its own sentence claimed: `NotificationDelivery.refresh()` is
# asynchronous, `AppComposition.start()` fires it and returns, and nothing sequenced it against
# report assembly, so the reported value was WHICH SIDE OF A RACE the report landed on — five
# gate runs at one commit on one machine gave notRequested, notRequested, authorised,
# notRequested, with two reports of a single run disagreeing with each other and every stage
# green. `notRequested` was simultaneously the OS's "never asked" and the field's pre-completion
# initial value, and the check's value set was exactly the union of both sides of the race.
#
# Three readings replace it, and each of them has a state it goes red in:
#
#   1. the read HAPPENED            — delete AppComposition's one refresh() call and reads is 0
#   2. the stage ran in the state its name claims — the report says what was FOUND, never "unread"
#   3. the DECODE is the committed one — the mapping, folded whole and pinned to one literal
check(
    report.get("notificationAuthorisationReads", 0) >= 1,
    "getNotificationSettings was really read: at least one completion landed",
    report.get("notificationAuthorisationReads"),
)
check(
    report.get("notificationAuthorisationWasRead") is True,
    "the report waited for that read rather than racing it",
    report.get("notificationAuthorisationWasRead"),
)
check(
    report.get("notificationAuthorisation") != "unread",
    "the stage ran with a decoded authorisation in hand, not with the absence of one",
    report.get("notificationAuthorisation"),
)
# The size of the fold before the fold's verdict (R-96o's shape): an equality over a table can be
# satisfied by shrinking both sides together, and the count is what cannot be.
check(
    bool(committed_decode_table) and committed_decode_cells.isdigit(),
    "the committed decode table was found in NotificationDeliveryTests",
    (committed_decode_table, committed_decode_cells),
)
check(
    report.get("notificationAuthorisationDecodeCells") == int(committed_decode_cells or -1),
    f"the boundary folded all {committed_decode_cells} raw statuses",
    report.get("notificationAuthorisationDecodeCells"),
)
check(
    report.get("notificationAuthorisationDecodeTable") == committed_decode_table,
    "the running boundary decodes every raw status exactly as the committed table says",
    report.get("notificationAuthorisationDecodeTable"),
)
# The value itself stays a printed NOTE and is asserted by nothing: what a person set on this Mac
# is not a property of this build, and a check on it would be a check on the machine.
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
# **One space, named once**, before either fold's verdict: the rung fold multiplies it by the
# rungs and the query fold takes it as it is, so the two counts cannot drift apart.
# The deck factor was 5 and is 4: `playful` is retired by the ruling on focus-0nm, and this
# literal is the space the running binary folds, so it moves with the vocabulary or the fold
# reports a retired deck as a fold that shrank.
route_space_cells = 2 * 2 * 2 * 2 * 4  # presenting × mic × flag × menuBar × deck

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
    # **The whole input space, and the set pinned in both directions** (focus-3vb). This used to be
    # a set built from the two-cell `routes` table above — every rung asked once at
    # `.notPresenting`, `.idle`, `reducedInterruption: false`, `menuBarVisible: true`,
    # `voice: .standard` — so a notification route reachable under Reduce Motion, a running
    # microphone, `silentVisual` or a hidden menu bar was invisible to it. The fold is now 128
    # cells, its size is asserted before the set it qualifies, and the honest set is three: the
    # badge really is reachable, under exactly the conditions the two-cell table pinned away.
    #
    # **The size is a committed literal, not a number the report chose** (focus-bkf). Written as
    # `report["ladderRungsDeclared"] * route_space_cells`, the expected value moved with the
    # reading: a binary that declared one rung and folded 80 cells satisfied it exactly, which is
    # the defect this row exists to catch, folded in half. The literal `2` is D-06-as-amended's
    # rung count, asserted of the report in its own right above at `ladderRungsDeclared == 2`, and
    # it is the same spelling `self-check.sh:2796` uses for the same fold.
    every_rung_cells = 2 * route_space_cells
    check(
        report.get("surfacesARungCanReachCellsChecked") == every_rung_cells,
        f"the surfaces-a-rung-reaches fold covers all {every_rung_cells} cells rather than two",
        report.get("surfacesARungCanReachCellsChecked"),
    )
    check(
        report.get("surfacesARungCanReach") == ["menuBar", "panel", "popoverBadge"],
        "over the whole input space a rung reaches the glyph, the panel and the badge, and "
        "nothing else — so no rung reaches a notification",
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

# --- where a QUESTION goes, over the whole space and pinned in both directions ------------------
#
# THIS BLOCK REPLACES A CHECK THAT COULD NOT GO RED, and it is focus-3vb's defect standing in the
# question's half of the same router. It read
# `report["querySurface"] in ("panel", "popoverBadge")` under the pass line *"a question routes to
# an in-app surface and never to a notification"*. A membership test cannot see a surface
# **appearing** — route every question to a notification and it stays green while that one cell
# answers `panel` — and the one cell it read was the plainest in the space.
#
# `queryRouteAudit()` folds `routeQuery(…)` over `SelfCheck.routeSpace`, the same enumeration the
# rung fold above is taken over, so the two claims about one router are now claims about one space.
check(
    report.get("querySurface") == "panel",
    "the row the settings pane describes routes a question to the panel",
    report.get("querySurface"),
)
check(
    report.get("surfacesAQuestionCanReachCellsChecked") == route_space_cells,
    f"the surfaces-a-question-reaches fold covers all {route_space_cells} cells rather than one",
    report.get("surfacesAQuestionCanReachCellsChecked"),
)
check(
    report.get("surfacesAQuestionCanReach") == ["panel", "popoverBadge"],
    "over the whole input space a question reaches the panel and the badge, and nothing else — "
    "so no question reaches the glyph and none reaches a notification",
    report.get("surfacesAQuestionCanReach"),
)

# --- the correction economy has a surface to be on ---------------------------------------------
#
# The top rung landing on "the panel" means nothing if the panel is not a real, correctly
# configured window. R-89's six properties are asserted on the object the application actually
# showed.
#
# **This used to say "Rung 3", and the assertion below used to say the panel is what the top rung
# "falls back to".** Both described the deleted mechanism: U-2 cut the ladder to two rungs, so the
# top rung IS the panel and it falls back from nothing. The two assertions above this line already
# read the top rung's rank out of the report; a comment claiming a third rung over them told a
# reader the gate was checking something it was not.
panel = report.get("panel") or {}
check(panel.get("wasVisible") is True, "the panel the top rung lands on really appears", panel.get("wasVisible"))
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
