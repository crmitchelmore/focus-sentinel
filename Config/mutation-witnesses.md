# Mutation witnesses — every binary- and product-level assertion in the build gate

**An assertion that cannot be shown to fail is a FAIL regardless of the run result.** This file
is the list: one row per assertion, with the exact mutation that turns it red, the control that
stops it being green for the wrong reason, and its status. Rows marked PROVEN were run and the
red line is quoted. Rows marked CANNOT-GO-RED are a finding, not a failure — each says why, and
what it would take to make it fallible.

Written for `focus-bkf` (§1.5 of the completion plan) against `e05-nudge`. The witnesses were
run on the products, reports and logs of a full green gate run; re-running them needs a gate run
of your own to point the harnesses at.

## The harnesses

Every harness is **non-committing**: it reads the gate's products, reports and logs and writes
only to `/private/tmp/mw/`. No tracked file is touched, and nothing here is ever a code change.

| harness | what it mutates | how |
|---|---|---|
| **H-BIN** | a scratch copy of `$FOCUS_DERIVED_DATA/Build/Products` | rename a symbol **in place** in the string table, NUL-padded to the same length, then run the stage with `FOCUS_DERIVED_DATA` pointed at the copy. Bytes appended past the end of a Mach-O are invisible to `strings -a` on this toolchain (measured, focus-4of) — plant in-section, never append |
| **H-OBJ** | the same scratch tree | replace a named product with `/bin/ls`: a real Mach-O that is not this application, so the controls fire without the bans firing |
| **H-ENT** | a copy of the `.app` | `codesign -d --entitlements - --xml`, edit the plist, `codesign -f -s - --entitlements <edited>` the copy, then `entitlement-check.sh <copy> <configuration>` |
| **H-JSON** | a copy of a report | extract the reader's python heredoc from its script, doctor a copy of the report, run the reader on the copy with the argv the stage passes |
| **H-LOG** | a copy of a log | `source <(sed -n '/^stage_name() {/,/^}/p' scripts/build-gate.sh)` with `LOG_DIR` and `DD` pointed at the copies |
| **H-SRC** | a throwaway worktree | `git worktree add --detach`, edit there, run the stage from that worktree |

The scripts that drive them are `/private/tmp/mw/run-json-witnesses.zsh`,
`run-binary-witnesses.zsh` and `run-log-witnesses.zsh`, each of which prints, per row, either
the red line it produced or `MISS`. Every harness runs its **unmutated** copy first and requires
it to be green: a red line means nothing if the clean run was red too.


## Coverage

| stage | assertions witnessed | PROVEN | CANNOT-GO-RED |
|---|---|---|---|
| `selfcheck-debug` / `selfcheck-release` | 45 | 45 | — |
| `notification-denied` (+ Release twin) | 17 | 17 | — |
| `focus-steal` (+ Release twin) | 14 | 14 | — |
| `forbidden-binary` | 6 | 6 | — |
| `boundaries-binary` | 9 | 9 | 1 (the row literal, superseded by B-14/B-15) |
| `packaging` | 6 | 6 | — |
| `unit-counts` | 5 | 5 | — |
| `evaluation` (B1–B5) | 9 | 9 | — |
| `entitlements-debug` / `entitlements-release` | 6 | 6 | 2 (seven restatement lines; one unreachable branch) |
| **total** | **117** | **117** | **3 findings** |

The seven rows the gate audit named as unable to go red are all fallible now, and each was run:
`self-check.sh`'s popover overflow (SC-37, SC-38) and its committed width (SC-39, SC-40),
`build-gate.sh`'s B5 (EV-07, EV-08), `check-boundaries.sh`'s framework row (B-14, B-15) and its
privacy-symbol control (B-10), `check-notification-denied.sh`'s rung fold (ND-09), and
`check-focus-steal.sh`'s popover width (FS-06, FS-07). The eighth finding was structural — both
`focus-steal` and `notification-denied` read the Debug product only — and is closed by the two
Release stages the gate now runs, which is where every ND and FS row above was witnessed.


## The witnesses

### `selfcheck-debug` / `selfcheck-release` — `scripts/self-check.sh`

H-JSON on a copy of the RELEASE report. Both stages run the same reader; the Release run is the one quoted, because it reads the artefact that ships.

| # | script:line | mutation (H-JSON) | control | status — the line it printed |
|---|---|---|---|---|
| SC-01 | `self-check.sh:1809` | `report["capabilityStatesDeclared"].append("pending")` | SC-05 — the matrix is not one answer twelve times | **PROVEN** — `FAIL: the capability vocabulary is the committed five, in order and with nothing else in it` |
| SC-02 | `self-check.sh:1779` | `report["capabilities"].pop()` | SC-05 | **PROVEN** — `FAIL: all twelve capabilities are reported, in order` |
| SC-03 | `self-check.sh:1887` | `[c.update(state="available") for c in report["capabilities"] if c["capability"] == "cameraActivity"]` | SC-05 | **PROVEN** — `FAIL: cameraActivity is unavailable, which is a decision of this build` |
| SC-04 | `self-check.sh:1900` | `[c.update(state="unavailable") for c in report["capabilities"] if c["capability"] == "windowMetadata"]` | SC-05 | **PROVEN** — `FAIL: windowMetadata is available, which is what this machine's own reading says` |
| SC-05 | `self-check.sh:1909` | `[c.update(state="available") for c in report["capabilities"]]` | is itself the control for SC-01..SC-04 | **PROVEN** — `FAIL: the matrix the app reported is not one answer repeated twelve times` |
| SC-06 | `self-check.sh:1968` | `report["authorisationSurfaceScan"]["windowsOwnedByThisProcess"] = 0` | `taken()` routes the scan (SC-35/SC-36 floors) | **PROVEN** — `FAIL: the scan listed a window belonging to this very process, so the instrument can see` |
| SC-07 | `self-check.sh:1985` | `report["authorisationSurfaces"] = ["a dialog"]` | SC-06 | **PROVEN** — `FAIL: the root's summary of the scan is the scan` |
| SC-08 | `self-check.sh:2251` | `report["notificationAuthorisationDecodeTable"] = report["notificationAuthorisationDecodeTable"].replace("denied", "authorised", 1)` | SC-09 — the cell count cannot be shrunk with the table | **PROVEN** — `FAIL: the running boundary decodes every raw status exactly as the committed table says` |
| SC-09 | `self-check.sh:2246` | `report["notificationAuthorisationDecodeCells"] = 3` | is the control for SC-08 | **PROVEN** — `FAIL: the boundary folded all 11 raw statuses it can be handed` |
| SC-10 | `self-check.sh:2215` | `report["notificationAuthorisationReads"] = 0` | SC-11, SC-12 | **PROVEN** — `FAIL: getNotificationSettings was really read: at least one completion landed` |
| SC-11 | `self-check.sh:2229` | `report["notificationAuthorisationWasRead"] = False` | SC-10 | **PROVEN** — `FAIL: the report waited for that read rather than racing it` |
| SC-12 | `self-check.sh:2234` | `report["notificationAuthorisation"] = "unread"` | SC-10 | **PROVEN** — `FAIL: the run had a decoded authorisation in hand rather than the absence of one` |
| SC-13 | `self-check.sh:2421` | `report["nudge"]["dispositionsDeclared"].pop()` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: the record's dispositions are exactly these four, one of which is a badge nobody opened` |
| SC-14 | `self-check.sh:2645` | `report["nudge"]["questionExitsDeclared"].pop()` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: every way an open question can end is enumerated, and they are exactly these five` |
| SC-15 | `self-check.sh:2683` | `report["nudge"]["rungExitsDeclared"].pop()` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: every way a delivered rung can end is enumerated, and they are exactly these six` |
| SC-16 | `self-check.sh:2729` | `report["nudge"]["ladderStatesDeclared"].pop()` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: every state the ladder can be in is a folded, named case` |
| SC-17 | `self-check.sh:2735` | `report["nudge"]["ladderSilencesDeclared"].pop()` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: every reason the ladder has for having nothing to climb to is enumerated` |
| SC-18 | `self-check.sh:2710` | `report["nudge"]["rungExitsCountingAnIgnoredAccusation"].append("answered")` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: exactly the endings the person authored advance the two ignored-accusation runs` |
| SC-19 | `self-check.sh:2662` | `report["nudge"]["questionExitsWritingAnExpiry"].append("answered")` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: exactly the exit that means the world ended it writes the question down` |
| SC-20 | `self-check.sh:2696` | `report["nudge"]["rungExitsTakingBackTheDelivery"].append("answered")` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: exactly the endings where the app took the surface away un-deliver the rung` |
| SC-21 | `self-check.sh:2745` | `report["nudge"]["ladderSilencesRetainingTheGlyph"].append("toppedOut")` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: exactly the ladder's refusals still owe the person the rung that says nothing` |
| SC-22 | `self-check.sh:2491` | `n = report["nudge"]; n["fatigueRefusalsPassingTheGlyph"].remove("cooldown"); n["fatigueRefusalsSilencingTheGlyph"].append("cooldown")` | SC-23 — the partition identity holds while the literals move | **PROVEN** — `FAIL: the only fatigue refusal that stops the glyph is the person saying it is real work` |
| SC-23 | `self-check.sh:2523` | `report["nudge"]["fatigueRefusalsDeclared"].append("seventhRefusal")` | SC-22 — the literals hold while the identity breaks | **PROVEN** — `FAIL: the three fatigue readings partition the declared refusals: each one in exactly one part` |
| SC-24 | `self-check.sh:2562` | `report["nudge"]["budgetAfterADayOfLandingsRungs"].append("badge")` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: this script prices exactly the rungs the ladder declares` |
| SC-25 | `self-check.sh:2576` | `report["nudge"]["budgetAfterADayOfLandings"]["panel"]["chargesFolded"] = 0` | SC-26 — one rung's day costs nothing and another's the whole day | **PROVEN** — `FAIL: a day of panel landings builds every landing charge(s) — stated, never inferred from an empty budget` |
| SC-26 | `self-check.sh:2594` | `d = report["nudge"]["budgetAfterADayOfLandings"]; [d[r].update(chargesFolded=0, interruptionsToday=0) for r in d]` | is the control for SC-24/SC-25 | **PROVEN** — `FAIL: the table discriminates: one rung's day costs nothing and another's costs the whole day` |
| SC-27 | `self-check.sh:2833` | `report["nudge"]["surfacesARungCanReachCellsChecked"] = 80` | SC-28 — conservation | **PROVEN** — `FAIL: the surfaces-a-rung-reaches fold covers all 160 cells rather than two` |
| SC-28 | `self-check.sh:2844` | `report["nudge"]["surfacesARungCanReachCellsDelivered"] -= 1` | SC-27 — the cell count | **PROVEN** — `FAIL: every cell of the every-rung fold either reached a surface or deferred` |
| SC-29 | `self-check.sh:2903` | `report["nudge"]["accusationRouteCellsChecked"] = 40` | SC-30 — conservation | **PROVEN** — `FAIL: the accusation-route fold covers all 80 cells rather than a subset` |
| SC-30 | `self-check.sh:2923` | `report["nudge"]["accusationRouteCellsDelivered"] -= 1` | SC-29 — the cell count | **PROVEN** — `FAIL: every cell of the accusation-route fold either reached a surface or deferred` |
| SC-31 | `self-check.sh:2932` | `n = report["nudge"]; short = 23; n["accusationRouteCellsDeferred"] += n["accusationRouteCellsDelivered"] - short; n["accusationRouteCellsDelivered"] = short` | SC-29/SC-30 | **PROVEN** — `FAIL: at least 24 of the fold's cells reach a surface, so the answerability verdict is a claim about something` |
| SC-32 | `self-check.sh:2861` | `report["nudge"]["surfacesOfferingAnAnswer"].append("notification")` | SC-27/SC-28 precede the verdict | **PROVEN** — `FAIL: exactly the two in-app decision surfaces offer the person a way to answer back` |
| SC-33 | `self-check.sh:2866` | `report["nudge"]["surfacesARungCanReach"].append("notification")` | SC-27/SC-28 precede the verdict | **PROVEN** — `FAIL: over the whole input space a rung reaches the glyph, the panel and the badge — and nothing else, so no rung reaches a notification` |
| SC-34 | `self-check.sh:2980` | `report["nudge"]["surfacesAQuestionCanReach"].append("notification")` | SC-43 precedes the verdict | **PROVEN** — `FAIL: over the whole input space a question reaches the panel and the badge, and nothing else — so no question reaches the glyph and none reaches a notification` |
| SC-35 | `self-check.sh:3294` | `report["fooWasTaken"] = True` | SC-36 — the five-fact floor | **PROVEN** — `FAIL: every reading that can be unavailable is routed through the one NOT-TAKEN mechanism` |
| SC-36 | `self-check.sh:3313` | `del report["nudge"]["panel"]["deltaReadingWasTaken"]` | is the control for SC-35 | **PROVEN** — `FAIL: every probe that may be unavailable still publishes whether its reading was taken` |
| SC-37 | `self-check.sh:2353` | `report["nudge"]["popover"]["overflowsDeclared"].remove("theContextScrolls")` | SC-38 — a value outside the published list | **PROVEN** — `FAIL: every way the popover can give way is a folded, named case` |
| SC-38 | `self-check.sh:2361` | `report["nudge"]["popover"]["fullest"]["overflow"] = "somethingElseEntirely"` | SC-37 — the published list itself | **PROVEN** — `FAIL: the fullest popover says which way it gives way` |
| SC-39 | `self-check.sh:2321` | `report["nudge"]["popover"]["fullest"]["width"] += 5` | SC-40 — the binary's own verdict must agree | **PROVEN** — `FAIL: the fullest popover is laid out at the committed width, at any priority length` |
| SC-40 | `self-check.sh:2326` | `report["nudge"]["popover"]["fullest"]["isTheCommittedWidth"] = False` | SC-39 — the arithmetic taken here | **PROVEN** — `FAIL: the popover's own width verdict agrees with the width it reported` |
| SC-41 | `self-check.sh:2366` | `p = report["nudge"]["popover"]["empty"]; p["scrolls"] = not p["scrolls"]` | SC-37/SC-38 | **PROVEN** — `FAIL: the empty popover's scroll flag and its overflow are one fact` |
| SC-42 | `self-check.sh:2964` | `report["nudge"]["querySurface"] = "notification"` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: the row the settings pane describes routes a question to the panel` |
| SC-43 | `self-check.sh:2972` | `report["nudge"]["surfacesAQuestionCanReachCellsChecked"] = 40` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: the surfaces-a-question-reaches fold covers all 80 cells rather than one` |
| SC-44 | `self-check.sh:2272` | `report["nudge"]["orphanedNudgeSurfaces"] = ["panel"]` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: no surface is offering a nudge the loop has forgotten, of either kind` |
| SC-45 | `self-check.sh:2938` | `report["nudge"]["everyAccusationRouteCanBeAnswered"] = False` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: every accusation route offers the person a way to answer back` |
| SC-46 | `self-check.sh:2479` | `report["nudge"]["popover"]["rebuild"]["unchangedTicks"] = 0` | SC-47/SC-48 — the ceilings they state are about ticks this row requires to exist | **PENDING** — expected red line: `FAIL: the popover rebuild survey really ticked, and most of its ticks changed nothing` |
| SC-47 | `self-check.sh:2484` | `report["nudge"]["popover"]["rebuild"]["buildsOnUnchangedTicks"] = 1` | SC-46 — the survey really ticked | **PENDING** — expected red line: `FAIL: a tick that changes nothing rebuilds nothing` |
| SC-48 | `self-check.sh:2491` | `r = report["nudge"]["popover"]["rebuild"]; r["contentBuilds"] = r["presentationChanges"] + 1` | SC-49 — the hosting identity moves with it | **PENDING** — expected red line: `FAIL: the popover's content is built at most once per presentation change` |
| SC-49 | `self-check.sh:2502` | `report["nudge"]["popover"]["rebuild"]["hostingConstructions"] += 1` | SC-48 — the build count itself | **PENDING** — expected red line: `FAIL: each popover build costs three hosting controllers, and nothing else builds one` |
| SC-50 | `self-check.sh:2526` | `report["nudge"]["tickFetches"]["available"] = False` | SC-51 — the per-state rows are read from the same object | **PENDING** — expected red line: `FAIL: the per-tick fetch survey ran` |
| SC-51 | `self-check.sh:2543` | `report["nudge"]["tickFetches"]["noCommitment"]["firstTickFetches"] = 0` | SC-52/SC-53 — the ceilings it makes readable | **PENDING** — expected red line: `FAIL: the noCommitment tick survey really ticked, and its first tick really fetched` |
| SC-52 | `self-check.sh:2550` | `r = report["nudge"]["tickFetches"]["noCommitment"]; r["fetchesOverSteadyTicks"] = 2 * r["steadyTicks"] + 1` | SC-51 — the survey really ticked | **PENDING** — expected red line: `FAIL: a quiet noCommitment tick costs at most two fetches` |
| SC-53 | `self-check.sh:2558` | `report["nudge"]["tickFetches"]["noCommitment"]["nudgeFetchesOverSteadyTicks"] = 1` | SC-51 | **PENDING** — expected red line: `FAIL: the nudge half of a quiet noCommitment tick goes to the store not at all` |
| SC-54 | `self-check.sh:2563` | `report["nudge"]["tickFetches"]["commitmentPopoverOpen"]["popoverFetchesOverSteadyTicks"] = 1` | SC-51 | **PENDING** — expected red line: `FAIL: building the popover's content on a commitmentPopoverOpen tick touches no store` |
| SC-55 | `self-check.sh:2177` | `report["retention"]["windowDays"] = 30` | SC-59 — the seeded sweep cuts where the window says | **PENDING** — expected red line: `FAIL: the committed retention window is ninety days` |
| SC-56 | `self-check.sh:2184` | `report["retention"]["ranAtLaunch"] = False` | SC-58 — the seeded half still runs | **PENDING** — expected red line: `FAIL: the retention sweep ran at launch and says which local day it ran on` |
| SC-57 | `self-check.sh:2189` | `report["retention"]["rowsRemoved"] = -1` | SC-56 | **PENDING** — expected red line: `FAIL: the launch sweep says how many rows it removed` |
| SC-58 | `self-check.sh:2196` | `report["retention"]["seedAvailable"] = False` | SC-56 — the launch half is unaffected | **PENDING** — expected red line: `FAIL: the seeded retention sweep ran` |
| SC-59 | `self-check.sh:2202` | `report["retention"]["seededActivityEventsRemoved"] = 2` | SC-60 — the intervention half holds while this moves | **PENDING** — expected red line: `FAIL: an activity event at 91 days goes and one at 89 stays` |
| SC-60 | `self-check.sh:2208` | `report["retention"]["seededInterventionRowsKept"] = 0` | SC-59 | **PENDING** — expected red line: `FAIL: an intervention row at 91 days goes and one at 89 stays` |
| SC-61 | `self-check.sh:2217` | `report["retention"]["seededQueryReceiptsRemoved"] = 1` | SC-59/SC-60 — the two age-only tables hold while the receipt rule breaks | **PENDING** — expected red line: `FAIL: a 91-day-old receipt under a live priority survives the window` |

### `notification-denied` / `notification-denied-release` — `scripts/check-notification-denied.sh`

H-JSON on a copy of the Release stage's report.

| # | script:line | mutation (H-JSON) | control | status — the line it printed |
|---|---|---|---|---|
| ND-01 | `check-notification-denied.sh:150` | `report["requestAuthorizationCallCount"] = 1` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL the application asked for no notification authorisation` |
| ND-02 | `check-notification-denied.sh:179` | `report["notificationAuthorisationReads"] = 0` | ND-03, ND-04 | **PROVEN** — `FAIL getNotificationSettings was really read: at least one completion landed` |
| ND-03 | `check-notification-denied.sh:184` | `report["notificationAuthorisationWasRead"] = False` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL the report waited for that read rather than racing it` |
| ND-04 | `check-notification-denied.sh:189` | `report["notificationAuthorisation"] = "unread"` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL the stage ran with a decoded authorisation in hand, not with the absence of one` |
| ND-05 | `check-notification-denied.sh:201` | `report["notificationAuthorisationDecodeCells"] = 3` | is the control for ND-06 | **PROVEN** — `FAIL the boundary folded all 11 raw statuses` |
| ND-06 | `check-notification-denied.sh:206` | `report["notificationAuthorisationDecodeTable"] = report["notificationAuthorisationDecodeTable"].replace("denied", "authorised", 1)` | ND-05 — the cell count before the table | **PROVEN** — `FAIL the running boundary decodes every raw status exactly as the committed table says` |
| ND-07 | `check-notification-denied.sh:220` | `report["routingRowFields"].append("authorisation")` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL a routing row the settings pane draws carries a rung and a route, and nothing else` |
| ND-08 | `check-notification-denied.sh:227` | `report["ladderRungsDeclared"] = 1` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL the ladder declares exactly two rungs` |
| ND-09 | `check-notification-denied.sh:279` | `report["ladderRungsDeclared"] = 1; report["surfacesARungCanReachCellsChecked"] = 80` | ND-08 — the rung count is asserted in its own right | **PROVEN** — `FAIL the surfaces-a-rung-reaches fold covers all 160 cells rather than two` |
| ND-10 | `check-notification-denied.sh:259` | `report["routes"][0]["surface"] = "notification"` | ND-11, ND-12 — the table is non-empty and two rows | **PROVEN** — `FAIL no rung routes to a notification` |
| ND-11 | `check-notification-denied.sh:240` | `report["routes"] = []` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL the router's table was reported` |
| ND-12 | `check-notification-denied.sh:244` | `report["routes"] = report["routes"][:1]` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL the table covers both rungs` |
| ND-13 | `check-notification-denied.sh:284` | `report["surfacesARungCanReach"].append("notification")` | ND-09 — the fold's size precedes the set | **PROVEN** — `FAIL over the whole input space a rung reaches the glyph, the panel and the badge, and nothing else — so no rung reaches a notification` |
| ND-14 | `check-notification-denied.sh:325` | `report["surfacesAQuestionCanReach"].append("notification")` | ND-15 — the fold's size precedes the set | **PROVEN** — `FAIL over the whole input space a question reaches the panel and the badge, and nothing else — so no question reaches the glyph and none reaches a notification` |
| ND-15 | `check-notification-denied.sh:320` | `report["surfacesAQuestionCanReachCellsChecked"] = 40` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL the surfaces-a-question-reaches fold covers all 80 cells rather than one` |
| ND-16 | `check-notification-denied.sh:254` | `report["everyRungIsInApp"] = False` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL every rung is delivered IN-APP` |
| ND-17 | `check-notification-denied.sh:315` | `report["querySurface"] = "notification"` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL the row the settings pane describes routes a question to the panel` |

### `focus-steal` / `focus-steal-release` — `scripts/check-focus-steal.sh`

H-JSON on a copy of the Release stage's report. The observer's two readings are passed from the report the stage really produced.

| # | script:line | mutation (H-JSON) | control | status — the line it printed |
|---|---|---|---|---|
| FS-01 | `check-focus-steal.sh:229` | `report["panel"]["wasVisible"] = False` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL the nudge panel really appeared` |
| FS-02 | `check-focus-steal.sh:94` | `report["panel"]["readingsAfterShow"]["frontmostBundleIdentifier"] = "com.apple.finder"` | FS-01 — the panel really appeared | **PROVEN** — `FAIL reading 1: the app and the observer agree about who is frontmost` |
| FS-03 | `check-focus-steal.sh:341` | `report["panel"]["frame"]["width"] += 5` | FS-09 — the two contents are not one picture | **PROVEN** — `FAIL the panel is the committed 380 points wide (measured 385)` |
| FS-04 | `check-focus-steal.sh:19` | `report["panel"]["readingsAfterShow"]["applicationIsActive"] = True` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL reading 2: NSApp.isActive is false after the panel is shown` |
| FS-05 | `check-focus-steal.sh:282` | `report["panel"]["readingsAfterShow"]["panelIsKey"] = True` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL reading 3: the panel is not the key window` |
| FS-06 | `check-focus-steal.sh:442` | `report["popover"]["fullest"]["width"] += 5` | FS-07 — the binary's own verdict must agree | **PROVEN** — `FAIL the fullest popover is the committed 300 points wide (measured 305)` |
| FS-07 | `check-focus-steal.sh:448` | `report["popover"]["fullest"]["isTheCommittedWidth"] = False` | FS-06 — the arithmetic taken here | **PROVEN** — `FAIL the fullest popover's own width verdict agrees with the width it reported` |
| FS-08 | `check-focus-steal.sh:461` | `report["popover"]["fullest"]["height"] = report["popover"]["maximumContentHeight"] + 50` | FS-09 | **PROVEN** — `FAIL the fullest popover is within the 921-point ceiling (measured 971)` |
| FS-09 | `check-focus-steal.sh:472` | `report["popover"]["fullest"]["height"] = report["popover"]["empty"]["height"]` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL the fullest popover is taller than the plainest one, so the height is a measurement` |
| FS-10 | `check-focus-steal.sh:385` | `report["panel"]["everyActionIsReachable"] = False` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL every action the panel offers is on a screen and inside the panel a person can see` |
| FS-11 | `check-focus-steal.sh:390` | `report["panel"]["hitTestsEveryAction"] = False` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL a click at the centre of every offered action lands on the panel` |
| FS-12 | `check-focus-steal.sh:380` | `report["panel"]["offeredActions"] = []` | FS-10, FS-11 — reachability and a real hit test | **PROVEN** — `FAIL the panel is offering something, so the reading is about actual buttons ([])` |
| FS-13 | `check-focus-steal.sh:479` | `report["requestAuthorizationCallCount"] = 1` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL the launch asked for no notification authorisation` |


### `forbidden-binary` — `scripts/check-forbidden.sh`

H-BIN and H-OBJ on a scratch copy of `Build/Products`. **Two measured facts about the
instruments**, because they decide where a plant has to go: bytes appended past the end of a
Mach-O are invisible to `strings -a` (focus-4of), and a name planted only in `__LINKEDIT`'s
symbol string table is read by `nm` but **not** reported by `strings -a` on this toolchain
(measured here, B-05). So an `nm` row is mutated in the symbol string table and a `strings` row
over an equal-length printable run in a loaded section.

| # | script:line | mutation | control | status — the line it printed |
|---|---|---|---|---|
| B-01 | `check-forbidden.sh:1508` | H-BIN: rename `_swift_bridgeObjectRetain` to `_kCGWindowName` in the Release app binary | B-02, B-04 | **PROVEN** — `FAIL [SC-1] …/Release/FocusSentinel.app/Contents/MacOS/FocusSentinel references kCGWindowName at the symbol level` |
| B-02 | `check-forbidden.sh:1581` | H-OBJ: the Release app's executable replaced by `/bin/ls`, its `.debug.dylib` removed | is the control for B-01 | **PROVEN** — `FAIL [SC-1] no Release app file reads the four sanctioned window keys` |
| B-03 | `check-forbidden.sh:1499` | `mv` the Release `FocusHost.o` aside | the list is explicit, not a glob | **PROVEN** — `FAIL [SC-1] FOCUS_REQUIRE_BINARY_CHECK=1 but …/Release/FocusHost.o does not exist` |
| B-04 | `check-forbidden.sh:1535` | H-BIN: rename `_kCGWindowOwnerName` in the Release `FocusSensing.o` | is the control for B-01 | **PROVEN** — `FAIL [SC-1] Release FocusSensing.o no longer reads _kCGWindowOwnerName` |
| B-05 | `check-forbidden.sh:1683` | H-BIN (bytes): `TokenOverlapCodingKeys` → `addNotificationRequest` in the Release binary's text | B-06 | **PROVEN** — `FAIL [R-96s] FocusSentinel (Release) carries addNotificationRequest (2) — it can post a notification` |
| B-06 | `check-forbidden.sh:1707` | H-OBJ: the Release executable replaced by `/bin/ls`; Debug stays green | is the control for B-05, per configuration | **PROVEN** — `FAIL [R-96s] no examined Release binary carries a notification-READING selector` |

### `boundaries-binary` — `scripts/check-boundaries.sh`

| # | script:line | mutation | control | status — the line it printed |
|---|---|---|---|---|
| B-07 | `check-boundaries.sh:343` | H-BIN: rename a symbol in the Release `FocusClassify.o` to `_URLSessionXXXXX` | B-08 | **PROVEN** — `FAIL: Release FocusClassify.o has undefined networking symbols:` |
| B-08 | `check-boundaries.sh:353` | H-OBJ: `FocusClassify.o` replaced by `/bin/ls` | is the control for B-07 | **PROVEN** — `FAIL: Release FocusClassify.o names no NaturalLanguage symbol at all` |
| B-09 | `check-boundaries.sh:395` | H-BIN: rename a symbol to `_AXUIElementCrea` | B-10 | **PROVEN** — `FAIL: Release FocusClassify.o names a window-list, Accessibility or capture symbol:` |
| B-10 | `check-boundaries.sh:406` | H-OBJ: `FocusClassify.o` replaced by `/bin/ls` | is the control for B-09, and it is this block's OWN control (focus-bkf) | **PROVEN** — `symbols cannot certify that it probes no privacy boundary — the absence` |
| B-11 | `check-boundaries.sh:478` | H-BIN: rename a symbol in the Release `FocusCore.o` to `_CGWindowListXXXX` | B-12 | **PROVEN** — `FAIL: the Release nudge object names a sensing or networking symbol:` |
| B-12 | `check-boundaries.sh:487` | H-OBJ: `FocusCore.o` replaced by `/bin/ls` | is the control for B-11 | **PROVEN** — `FAIL: Release FocusCore.o carries no SurfaceRouter symbol at all` |
| B-13 | `check-boundaries.sh:469` | `mv` the Release `FocusCore.o` aside | — | **PROVEN** — `FAIL: FOCUS_REQUIRE_BINARY_CHECK=1 but there is no build product at …/Release/FocusCore.o` |
| B-14 | `check-boundaries.sh:552` | H-BIN: rename `__swift_FORCE_LOAD_$_swiftNaturalLanguage` to `…_swiftCoreGraphics` | B-08's NL control | **PROVEN** — `FAIL: the Release FocusClassify.o framework closure has changed` |
| B-15 | `check-boundaries.sh:564` | H-SRC: widen `ALLOWED_FRAMEWORKS[FocusClassify]` in a worktree copy | B-14 | **PROVEN** — `FAIL: the row permits CoreGraphics, which Debug FocusClassify.o does not link` |

### `packaging` — `scripts/build-gate.sh` (`check_packaging`)

H-LOG: `source <(sed -n '/^check_packaging() {/,/^}/p' scripts/build-gate.sh)` with `LOG_DIR`
and `DD` pointed at copies of the run's logs and products.

| # | script:line | mutation | control | status — the line it printed |
|---|---|---|---|---|
| PK-01 | `build-gate.sh:282` | append `warning: The Copy Bundle Resources build phase contains …` to the Release log copy | PK-02 | **PROVEN** — `FAIL [Release] 1 Copy-Bundle-Resources Info.plist warning(s) in …/focus-build-release.log` |
| PK-02 | `build-gate.sh:275` | move the Debug build log aside | — | **PROVEN** — `FAIL [Debug] no build log at …/focus-build.log` |
| PK-03 | `build-gate.sh:297` | `touch Contents/Resources/Info.plist` in the copied bundle | PK-06 | **PROVEN** — `FAIL [Release] the product ships a stray Contents/Resources/Info.plist` |
| PK-04 | `build-gate.sh:308` | `PlistBuddy -c "Delete :CFBundleURLTypes"` on the copied merged plist | PK-06 | **PROVEN** — `FAIL [Release] the merged Info.plist does not declare the focus scheme` |
| PK-05 | `build-gate.sh:318` | `PlistBuddy -c "Delete :NSPrincipalClass"` on the copy | PK-06 | **PROVEN** — `FAIL [Release] the merged Info.plist lost the generated key NSPrincipalClass` |
| PK-06 | `build-gate.sh:291` | move the copied `.app` aside | — | **PROVEN** — `FAIL [Release] no app bundle at …/Release/FocusSentinel.app` |

### `unit-counts` — `scripts/build-gate.sh` (`unit_counts_stage`)

H-LOG on a copy of `focus-test.log`. The floors are `>=`, read from `Config/test-floors.txt`
and paired positionally with the scheme's testables.

| # | script:line | mutation | control | status — the line it printed |
|---|---|---|---|---|
| UC-01 | `build-gate.sh:396` | append `Program crashed: Signal 11` to the log copy | the clean copy is green; the markers are 0× in it | **PROVEN** — `FAIL [unit-counts] the unit log contains 'Program crashed' (1)` |
| UC-02 | `build-gate.sh:396` | append `Restarting after unexpected exit …` | as above | **PROVEN** — `FAIL [unit-counts] the unit log contains 'Restarting after unexpected exit' (1)` |
| UC-03 | `build-gate.sh:420` | delete the last `Test run with N tests` line | `${#NAMES}` comes from the committed floors | **PROVEN** — `FAIL [unit-counts] only 5 of 6 bundles reported a test run` |
| UC-04 | `build-gate.sh:438` | rewrite the first summary as `Test run with 5 tests` | UC-03 | **PROVEN** — `FAIL [unit-counts] FocusCoreTests ran 5 tests, below its committed floor of 944` |
| UC-05 | `build-gate.sh:448` | append a seventh summary line | UC-03 | **PROVEN** — `FAIL [unit-counts] 7 bundles reported but only 6 floors are committed` |

### `evaluation` — `scripts/build-gate.sh`, R-75's binding checks B1–B5

The reader is extracted from the stage and run on copies: a parsed copy, a staged copy, a
marker and a corpus directory, exactly the argv the stage passes.

| # | script:line | mutation | control | status — the line it printed |
|---|---|---|---|---|
| EV-01 | `build-gate.sh:572` | H-JSON: `report["runID"] = "some-other-run"` | EV-02 | **PROVEN** — `FAIL B1 runID is this run's token (focus-s15-logs-0)` |
| EV-02 | `build-gate.sh:589` | `touch` a marker after the report | EV-01 | **PROVEN** — `FAIL B2 the report is newer than the eval-clean marker` |
| EV-03 | `build-gate.sh:601` | H-JSON: `report["stamp"] = "0xdeadbeefdeadbeef"` | the literals were found at all (`bool(expected_stamp)`) | **PROVEN** — `FAIL B3 the report was produced by engine s1.p3.l1.e1.m0` |
| EV-04 | `build-gate.sh:619` | H-JSON: `report["nudge"]["interventionDigest"] = "0x0000000000000000"` | as above | **PROVEN** — `FAIL B3 the report's intervention digest is 0x4b15b93ff3a0e36b` |
| EV-05 | `build-gate.sh:674` | flip a byte in a copy of the golden corpus | EV-06 | **PROVEN** — `FAIL B4 the report describes the corpus on disk` |
| EV-06 | `build-gate.sh:671` | point the reader at an empty corpus directory | is the control for EV-05 | **PROVEN** — `FAIL B4 the corpus was read from the working tree (0 file(s))` |
| EV-07 | `build-gate.sh:716` | rewrite the staged copy so its bytes differ from the parsed one | EV-08, and `build-gate.sh:704` (the copy is non-empty) | **PROVEN** (focus-bkf's repair) — `FAIL B5 the copy is byte-identical to the report FocusEvaluate wrote (887bc5741dfd264f)` |
| EV-08 | `build-gate.sh:709` | pass the staging path as the parsed path (same device and inode) | EV-07 | **PROVEN** — `FAIL B5 the parsed bytes are the per-run copy, not the shared staging file` |
| EV-09 | `build-gate.sh:704` | truncate the parsed copy to nothing | — | **PROVEN** — the reader exits non-zero on the empty file before any metric is reported |

### `entitlements-debug` / `entitlements-release` — `scripts/entitlement-check.sh`

H-ENT: the bundle is copied, `codesign -d --entitlements - --xml` is dumped and edited, the
copy is re-signed `codesign -f -s - --entitlements <edited>`, and the stage is run against it.

| # | script:line | mutation | control | status — the line it printed |
|---|---|---|---|---|
| EN-01 | `entitlement-check.sh:188` | H-ENT: add `com.apple.security.get-task-allow` to the Release copy | EN-04 | **PROVEN** — `FAIL the Release product carries exactly the committed entitlement keys` |
| EN-02 | `entitlement-check.sh:195` | H-ENT: `app-sandbox = true` | EN-04 | **PROVEN** — `FAIL every committed Release entitlement carries the value it was committed with` |
| EN-03 | `entitlement-check.sh:188` | H-ENT: add `com.apple.security.network.client` | EN-04 | **PROVEN** — the symmetric difference names it: `[Key] com.apple.security.network.client` |
| EN-04 | `entitlement-check.sh:175` | H-ENT: re-sign with an empty entitlements plist | is the floor for every row above | **PROVEN** — `FAIL the product's entitlements were read as a plist and are not empty` |
| EN-05 | `entitlement-check.sh:181` | run the reader with `Staging` as the configuration | — | **PROVEN** — `FAIL there is a committed entitlement set for Staging` (from the CLI the same edit is caught earlier still, by the configuration guard at `:76`) |
| EN-06 | `entitlement-check.sh:265` | `PlistBuddy -c "Add :NSCameraUsageDescription string x"` on the copied bundle | EN-07 | **PROVEN** — `FAIL: NSCameraUsageDescription is declared in the merged Info.plist` |


### The two self-lints, and what they are worth

| # | script:line | mutation | status |
|---|---|---|---|
| FS-14 | `check-focus-steal.sh:490` | run the reader with a copy of its own script from which `observe_frontmost` has been deleted | **PROVEN** — `FAIL this stage still performs reading 1 from an independent observer ('observe_frontmost')`. It is red only for an edit to the stage itself, which is exactly what it is for: a stage that quietly lost reading 1 would still print a page of green lines |
| — | `check-boundaries.sh:548` | H-SRC: change `EXPECTED_CLASSIFY_FRAMEWORKS` or the row | **CANNOT-GO-RED against any artefact** — one constant in this file against another. It is kept because it names the guarantee, and B-14/B-15 are the readings that make the row a fact about the built object |

## CANNOT-GO-RED — the findings, in full

Three, and each is a finding rather than a failure: none is a reading the gate credits as
coverage, and each says what stands in its place.

1. **`entitlement-check.sh:210-221` — seven rows implied by the dictionary comparison.** The five
   FORBIDDEN keys, `app-sandbox` present, `get-task-allow` per configuration. Every edit that
   would falsify one of them fails `:188` or `:195` first, so none can go red alone. They stay,
   because a red log should name the guarantee a reader is looking for, and the log now says
   what they are: `the seven lines below RESTATE the comparison above; none can fail on its own`,
   and each prints as `restatement — …`. **Coverage: EN-01 and EN-02.**
2. **`check-boundaries.sh:548` — the framework row compared to a literal in the same file.** As
   above: kept for its sentence, not counted. **Coverage: B-14 (the built object's overlay
   closure, pinned both ways) and B-15 (a widened row is a promise the product does not keep).**
3. **`entitlement-check.sh:260` — `no merged Info.plist at …`.** Unreachable from outside: a
   bundle with no `Contents/Info.plist` cannot be read by `codesign -d` either, so the stage
   fails louder and earlier — `FAIL: codesign could not read entitlements (exit 1)` at `:96`,
   which is red. A defensive branch behind a stronger guard, not coverage.

## What this list is still green for, stated

- **A probe that reads the right inputs and files them under the wrong name.** The capability
  matrix's rule and the app's probe are both written from `PlatformCapabilityProbe.states()`;
  they would agree in the same wrong way. SC-05 is what stops the weaker failure — a matrix that
  has stopped being a measurement.
- **A rung whose `spendsTheInterruptionCap` answer is wrong in the same direction as the day
  table's expectation** (`self-check.sh:2562-2567` states this residual in the file itself).
  SC-26 is what stops the failure the reading exists for: an arithmetic that folded nothing.
- **What a person has actually granted on this Mac.** Every entitlement row proves what is
  SIGNED INTO the product. A TCC row is not an entitlement and no dump would show one.
- **A person typing while the panel is on screen.** Synthesising a key event needs an
  Accessibility grant, so it is live-lane evidence (§4.9 frame 17), never a gate stage.

## Re-running this

The harnesses need a green gate run to point at:

```
FOCUS_DERIVED_DATA=/private/tmp/dd FOCUS_LOG_DIR=/private/tmp/logs \
    FOCUS_KEEP_DERIVED_DATA=1 scripts/build-gate.sh > /private/tmp/run.log 2>&1

FOCUS_MW_DD=/private/tmp/dd zsh /private/tmp/mw/prep-reports.zsh
zsh /private/tmp/mw/run-json-witnesses.zsh /private/tmp/mw/cases-selfcheck.txt
zsh /private/tmp/mw/run-json-witnesses.zsh /private/tmp/mw/cases-stages.txt
FOCUS_MW_DD=/private/tmp/dd zsh /private/tmp/mw/run-binary-witnesses.zsh
FOCUS_MW_LOGS=/private/tmp/logs FOCUS_MW_DD=/private/tmp/dd \
    zsh /private/tmp/mw/run-log-witnesses.zsh
```

Each prints one line per row: the red line it produced, or `MISS`. A `MISS` is the same verdict
as a red gate — an assertion that cannot be shown to fail is a FAIL regardless of the run result.
