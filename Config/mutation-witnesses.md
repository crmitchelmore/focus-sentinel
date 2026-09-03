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

The R-168 round (e10a) added a seventh driver, `/private/tmp/mw2/run.zsh`, and with it the two
copies of `self-check.sh` the H-JSON rows for that round are run against; `/private/tmp/mw2/pk/`
holds the `published-keys` stage's own copy, with its own `Config/`.

The scripts that drive them are `/private/tmp/mw/run-selfcheck-tzj-witnesses.zsh` (SC-46..SC-61),
`/private/tmp/mw/run-sc-e06.zsh` (SC-71..SC-78, e06's model tier — it needs the self-check's own
side artefacts, which the script deletes on exit, so it is pointed at a run of a copy with the
`trap` removed and `SESSION_DIR` pinned; the copy reads its committed literals from the real
repository so a literal that moves moves for the harness too),
`/private/tmp/mw/run-sc-idle.zsh` (SC-91..SC-97, focus-7az's idle rows — pointed at the same kind
of pinned-`SESSION_DIR`, `trap`-free copy for the same reason),
`/private/tmp/mw/run-json-witnesses.zsh`,
`run-binary-witnesses.zsh` and `run-log-witnesses.zsh`, each of which prints, per row, either
the red line it produced or `MISS`. Every harness runs its **unmutated** copy first and requires
it to be green: a red line means nothing if the clean run was red too.


## Coverage

| stage | assertions witnessed | PROVEN | CANNOT-GO-RED |
|---|---|---|---|
| `selfcheck-debug` / `selfcheck-release` | 159 | 159 | — |
| `notification-denied` (+ Release twin) | 17 | 17 | — |
| `focus-steal` (+ Release twin) | 14 | 14 | — |
| `forbidden-binary` | 6 | 6 | — |
| `boundaries-binary` | 9 | 9 | 1 (the row literal, superseded by B-14/B-15) |
| `published-keys` | 7 | 7 | — |
| `release-artefact` | 6 | 4 | 2 (a machine policy this harness may not change; one by construction) |
| `forbidden` (R-169) | 3 | 3 | — |
| `packaging` | 7 | 7 | — |
| `unit-counts` | 5 | 5 | — |
| `evaluation` (B1–B5) | 9 | 9 | — |
| `entitlements-debug` / `entitlements-release` | 6 | 6 | 2 (seven restatement lines; one unreachable branch) |
| **total** | **239** | **237** | **5 findings** |

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
| SC-01 | `self-check.sh:2405` | `report["capabilityStatesDeclared"].append("pending")` | SC-05 — the matrix is not one answer twelve times | **PROVEN** — `FAIL: the capability vocabulary is the committed five, in order and with nothing else in it` |
| SC-02 | `self-check.sh:2375` | `report["capabilities"].pop()` | SC-05 | **PROVEN** — `FAIL: all twelve capabilities are reported, in order` |
| SC-03 | `self-check.sh:2497` | `[c.update(state="available") for c in report["capabilities"] if c["capability"] == "cameraActivity"]` | SC-05 | **PROVEN** — `FAIL: cameraActivity is unavailable, which is a decision of this build` |
| SC-04 | `self-check.sh:2510` | `[c.update(state="unavailable") for c in report["capabilities"] if c["capability"] == "windowMetadata"]` | SC-05 | **PROVEN** — `FAIL: windowMetadata is available, which is what this machine's own reading says` |
| SC-05 | `self-check.sh:2519` | `[c.update(state="available") for c in report["capabilities"]]` | is itself the control for SC-01..SC-04 | **PROVEN** — `FAIL: the matrix the app reported is not one answer repeated twelve times` |
| SC-06 | `self-check.sh:2578` | `report["authorisationSurfaceScan"]["windowsOwnedByThisProcess"] = 0` | `taken()` routes the scan (SC-35/SC-36 floors) | **PROVEN** — `FAIL: the scan listed a window belonging to this very process, so the instrument can see` |
| SC-07 | `self-check.sh:2594` | `report["authorisationSurfaces"] = ["a dialog"]` | SC-06 | **PROVEN** — `FAIL: the root's summary of the scan is the scan` |
| SC-08 | `self-check.sh:3150` | `report["notificationAuthorisationDecodeTable"] = report["notificationAuthorisationDecodeTable"].replace("denied", "authorised", 1)` | SC-09 — the cell count cannot be shrunk with the table | **PROVEN** — `FAIL: the running boundary decodes every raw status exactly as the committed table says` |
| SC-09 | `self-check.sh:3145` | `report["notificationAuthorisationDecodeCells"] = 3` | is the control for SC-08 | **PROVEN** — `FAIL: the boundary folded all 11 raw statuses it can be handed` |
| SC-10 | `self-check.sh:3114` | `report["notificationAuthorisationReads"] = 0` | SC-11, SC-12 | **PROVEN** — `FAIL: getNotificationSettings was really read: at least one completion landed` |
| SC-11 | `self-check.sh:3128` | `report["notificationAuthorisationWasRead"] = False` | SC-10 | **PROVEN** — `FAIL: the report waited for that read rather than racing it` |
| SC-12 | `self-check.sh:3133` | `report["notificationAuthorisation"] = "unread"` | SC-10 | **PROVEN** — `FAIL: the run had a decoded authorisation in hand rather than the absence of one` |
| SC-13 | `self-check.sh:3439` | `report["nudge"]["dispositionsDeclared"].pop()` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: the record's dispositions are exactly these four, one of which is a badge nobody opened` |
| SC-14 | `self-check.sh:3663` | `report["nudge"]["questionExitsDeclared"].pop()` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: every way an open question can end is enumerated, and they are exactly these five` |
| SC-15 | `self-check.sh:3700` | `report["nudge"]["rungExitsDeclared"].pop()` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: every way a delivered rung can end is enumerated, and they are exactly these six` |
| SC-16 | `self-check.sh:3749` | `report["nudge"]["ladderStatesDeclared"].pop()` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: every state the ladder can be in is a folded, named case` |
| SC-17 | `self-check.sh:3754` | `report["nudge"]["ladderSilencesDeclared"].pop()` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: every reason the ladder has for having nothing to climb to is enumerated` |
| SC-18 | `self-check.sh:3730` | `report["nudge"]["rungExitsCountingAnIgnoredAccusation"].append("answered")` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: exactly the endings the person authored advance the two ignored-accusation runs` |
| SC-19 | `self-check.sh:3682` | `report["nudge"]["questionExitsWritingAnExpiry"].append("answered")` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: exactly the exit that means the world ended it writes the question down` |
| SC-20 | `self-check.sh:3716` | `report["nudge"]["rungExitsTakingBackTheDelivery"].append("answered")` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: exactly the endings where the app took the surface away un-deliver the rung` |
| SC-21 | `self-check.sh:3765` | `report["nudge"]["ladderSilencesRetainingTheGlyph"].append("toppedOut")` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: exactly the ladder's refusals still owe the person the rung that says nothing` |
| SC-22 | `self-check.sh:3511` | `n = report["nudge"]; n["fatigueRefusalsPassingTheGlyph"].remove("cooldown"); n["fatigueRefusalsSilencingTheGlyph"].append("cooldown")` | SC-23 — the partition identity holds while the literals move | **PROVEN** — `FAIL: the only fatigue refusal that stops the glyph is the person saying it is real work` |
| SC-23 | `self-check.sh:3542` | `report["nudge"]["fatigueRefusalsDeclared"].append("seventhRefusal")` | SC-22 — the literals hold while the identity breaks | **PROVEN** — `FAIL: the three fatigue readings partition the declared refusals: each one in exactly one part` |
| SC-24 | `self-check.sh:3581` | `report["nudge"]["budgetAfterADayOfLandingsRungs"].append("badge")` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: this script prices exactly the rungs the ladder declares` |
| SC-25 | `self-check.sh:3596` | `report["nudge"]["budgetAfterADayOfLandings"]["panel"]["chargesFolded"] = 0` | SC-26 — one rung's day costs nothing and another's the whole day | **PROVEN** — `FAIL: a day of panel landings builds every landing charge(s) — stated, never inferred from an empty budget` |
| SC-26 | `self-check.sh:3611` | `d = report["nudge"]["budgetAfterADayOfLandings"]; [d[r].update(chargesFolded=0, interruptionsToday=0) for r in d]` | is the control for SC-24/SC-25 | **PROVEN** — `FAIL: the table discriminates: one rung's day costs nothing and another's costs the whole day` |
| SC-27 | `self-check.sh:3855` | `report["nudge"]["surfacesARungCanReachCellsChecked"] = 80` | SC-28 — conservation | **PROVEN** — `FAIL: the surfaces-a-rung-reaches fold covers all 160 cells rather than two` |
| SC-28 | `self-check.sh:3864` | `report["nudge"]["surfacesARungCanReachCellsDelivered"] -= 1` | SC-27 — the cell count | **PROVEN** — `FAIL: every cell of the every-rung fold either reached a surface or deferred` |
| SC-29 | `self-check.sh:3925` | `report["nudge"]["accusationRouteCellsChecked"] = 40` | SC-30 — conservation | **PROVEN** — `FAIL: the accusation-route fold covers all 80 cells rather than a subset` |
| SC-30 | `self-check.sh:3948` | `report["nudge"]["accusationRouteCellsDelivered"] -= 1` | SC-29 — the cell count | **PROVEN** — `FAIL: every cell of the accusation-route fold either reached a surface or deferred` |
| SC-31 | `self-check.sh:3959` | `n = report["nudge"]; short = 23; n["accusationRouteCellsDeferred"] += n["accusationRouteCellsDelivered"] - short; n["accusationRouteCellsDelivered"] = short` | SC-29/SC-30 | **PROVEN** — `FAIL: at least 24 of the fold's cells reach a surface, so the answerability verdict is a claim about something` |
| SC-32 | `self-check.sh:3883` | `report["nudge"]["surfacesOfferingAnAnswer"].append("notification")` | SC-27/SC-28 precede the verdict | **PROVEN** — `FAIL: exactly the two in-app decision surfaces offer the person a way to answer back` |
| SC-33 | `self-check.sh:3888` | `report["nudge"]["surfacesARungCanReach"].append("notification")` | SC-27/SC-28 precede the verdict | **PROVEN** — `FAIL: over the whole input space a rung reaches the glyph, the panel and the badge — and nothing else, so no rung reaches a notification` |
| SC-34 | `self-check.sh:4007` | `report["nudge"]["surfacesAQuestionCanReach"].append("notification")` | SC-43 precedes the verdict | **PROVEN** — `FAIL: over the whole input space a question reaches the panel and the badge, and nothing else — so no question reaches the glyph and none reaches a notification` |
| SC-35 | `self-check.sh:5019` | `report["fooWasTaken"] = True` | SC-36 — the five-fact floor | **PROVEN** — `FAIL: every reading that can be unavailable is routed through the one NOT-TAKEN mechanism` |
| SC-36 | `self-check.sh:5041` | `del report["nudge"]["panel"]["deltaReadingWasTaken"]` | is the control for SC-35 | **PROVEN** — `FAIL: every probe that may be unavailable still publishes whether its reading was taken` |
| SC-37 | `self-check.sh:3252` | `report["nudge"]["popover"]["overflowsDeclared"].remove("theContextScrolls")` | SC-38 — a value outside the published list | **PROVEN** — `FAIL: every way the popover can give way is a folded, named case` |
| SC-38 | `self-check.sh:3260` | `report["nudge"]["popover"]["fullest"]["overflow"] = "somethingElseEntirely"` | SC-37 — the published list itself | **PROVEN** — `FAIL: the fullest popover says which way it gives way` |
| SC-39 | `self-check.sh:3220` | `report["nudge"]["popover"]["fullest"]["width"] += 5` | SC-40 — the binary's own verdict must agree | **PROVEN** — `FAIL: the fullest popover is laid out at the committed width, at any priority length` |
| SC-40 | `self-check.sh:3225` | `report["nudge"]["popover"]["fullest"]["isTheCommittedWidth"] = False` | SC-39 — the arithmetic taken here | **PROVEN** — `FAIL: the popover's own width verdict agrees with the width it reported` |
| SC-41 | `self-check.sh:3265` | `p = report["nudge"]["popover"]["empty"]; p["scrolls"] = not p["scrolls"]` | SC-37/SC-38 | **PROVEN** — `FAIL: the empty popover's scroll flag and its overflow are one fact` |
| SC-42 | `self-check.sh:3991` | `report["nudge"]["querySurface"] = "notification"` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: the row the settings pane describes routes a question to the panel` |
| SC-43 | `self-check.sh:3999` | `report["nudge"]["surfacesAQuestionCanReachCellsChecked"] = 40` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: the surfaces-a-question-reaches fold covers all 80 cells rather than one` |
| SC-44 | `self-check.sh:3171` | `report["nudge"]["orphanedNudgeSurfaces"] = ["panel"]` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: no surface is offering a nudge the loop has forgotten, of either kind` |
| SC-45 | `self-check.sh:3965` | `report["nudge"]["everyAccusationRouteCanBeAnswered"] = False` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0)` | **PROVEN** — `FAIL: every accusation route offers the person a way to answer back` |
| SC-46 | `self-check.sh:3307` | `report["nudge"]["popover"]["rebuild"]["unchangedTicks"] = 0` | SC-47/SC-48 — the ceilings they state are about ticks this row requires to exist | **PROVEN** — `FAIL: the popover rebuild survey really ticked, and most of its ticks changed nothing` |
| SC-47 | `self-check.sh:3316` | `report["nudge"]["popover"]["rebuild"]["buildsOnUnchangedTicks"] = 1` | SC-46 — the survey really ticked | **PROVEN** — `FAIL: a tick that changes nothing rebuilds nothing` |
| SC-48 | `self-check.sh:3321` | `r = report["nudge"]["popover"]["rebuild"]; r["contentBuilds"] = r["presentationChanges"] + 1` | SC-49 — the hosting identity moves with it | **PROVEN** — `FAIL: the popover's content is built at most once per presentation change` |
| SC-49 | `self-check.sh:3331` | `report["nudge"]["popover"]["rebuild"]["hostingConstructions"] += 1` | SC-48 — the build count itself | **PROVEN** — `FAIL: each popover build costs three hosting controllers, and nothing else builds one` |
| SC-50 | `self-check.sh:3358` | `report["nudge"]["tickFetches"]["available"] = False` | SC-51 — the per-state rows are read from the same object | **PROVEN** — `FAIL: the per-tick fetch survey ran` |
| SC-51 | `self-check.sh:3374` | `report["nudge"]["tickFetches"]["noCommitment"]["firstTickFetches"] = 0` | SC-52/SC-53 — the ceilings it makes readable | **PROVEN** — `FAIL: the noCommitment tick survey really ticked, and its first tick really fetched` |
| SC-52 | `self-check.sh:3380` | `r = report["nudge"]["tickFetches"]["noCommitment"]; r["fetchesOverSteadyTicks"] = 2 * r["steadyTicks"] + 1` | SC-51 — the survey really ticked | **PROVEN** — `FAIL: a quiet noCommitment tick costs at most two fetches` |
| SC-53 | `self-check.sh:3390` | `report["nudge"]["tickFetches"]["noCommitment"]["nudgeFetchesOverSteadyTicks"] = 1` | SC-51 | **PROVEN** — `FAIL: the nudge half of a quiet noCommitment tick goes to the store not at all` |
| SC-54 | `self-check.sh:3395` | `report["nudge"]["tickFetches"]["commitmentPopoverOpen"]["popoverFetchesOverSteadyTicks"] = 1` | SC-51 | **PROVEN** — `FAIL: building the popover's content on a commitmentPopoverOpen tick touches no store` |
| SC-55 | `self-check.sh:2871` | `report["retention"]["windowDays"] = 30` | SC-59 — the seeded sweep cuts where the window says | **PROVEN** — `FAIL: the committed retention window is ninety days` |
| SC-56 | `self-check.sh:2876` | `report["retention"]["ranAtLaunch"] = False` | SC-58 — the seeded half still runs | **PROVEN** — `FAIL: the retention sweep ran at launch and says which local day it ran on` |
| SC-57 | `self-check.sh:2883` | `report["retention"]["rowsRemoved"] = -1` | SC-56 | **PROVEN** — `FAIL: the launch sweep says how many rows it removed` |
| SC-58 | `self-check.sh:2890` | `report["retention"]["seedAvailable"] = False` | SC-56 — the launch half is unaffected | **PROVEN** — `FAIL: the seeded retention sweep ran` |
| SC-59 | `self-check.sh:2895` | `report["retention"]["seededActivityEventsRemoved"] = 2` | SC-60 — the intervention half holds while this moves | **PROVEN** — `FAIL: an activity event at 91 days goes and one at 89 stays` |
| SC-60 | `self-check.sh:2901` | `report["retention"]["seededInterventionRowsKept"] = 0` | SC-59 | **PROVEN** — `FAIL: an intervention row at 91 days goes and one at 89 stays` |
| SC-61 | `self-check.sh:2910` | `report["retention"]["seededQueryReceiptsRemoved"] = 1` | SC-59/SC-60 — the two age-only tables hold while the receipt rule breaks | **PROVEN** — `FAIL: a 91-day-old receipt under a live priority survives the window` |

### Section 3's pins (focus-odz) — `selfcheck-debug` / `selfcheck-release`

H-JSON, extended. focus-odz.4, .6 and .7 are pinned on the **fourth and fifth launches** — the
cockpit drawn against a seeded store, and its relaunch against the same store — rather than on the
primary report, because the facts they are about are only true of a store this run created. So the
harness gained two reader kinds, `cockpit-release` and `relaunch-release`, each of which doctors one
of those files while the primary report and the other three stay real; `prep-reports.zsh` copies the
fifth launch's report out beside the other four. The cases file is `/private/tmp/mw/cases-odz.txt`.

| # | script:line | mutation (H-JSON) | control | status — the line it printed |
|---|---|---|---|---|
| SC-62 | `self-check.sh` reopen | `report["reopen"]["cockpitVisibleAfterReopen"] = False` | SC-65 — the close half still reads shut, so this is not a probe that never ran | **PROVEN** — `FAIL: reopenOpensTheCockpit: a Dock click with no window open put the cockpit back on the screen` |
| SC-63 | `self-check.sh` reopen | `report["reopen"]["answered"] = False` | SC-62 | **PROVEN** — `FAIL: the application answers applicationShouldHandleReopen, so a Dock click has somewhere to land` |
| SC-64 | `self-check.sh` reopen | `reopen["requestsAfter"] = reopen["requestsBefore"]` | SC-62 — the window half holds while the request half breaks | **PROVEN** — `FAIL: the reopen asked the command centre for the cockpit exactly once` |
| SC-65 | `self-check.sh` reopen | `report["reopen"]["cockpitVisibleBeforeReopen"] = True` | is itself the control for SC-62 | **PROVEN** — `FAIL: the cockpit really was shut before the Dock click was simulated` |
| SC-66 | `self-check.sh` status menu | `statusItemMenu["items"].append("about")` | SC-68 | **PROVEN** — `FAIL: the status item's secondary menu is the four declared items, in reading order` |
| SC-67 | `self-check.sh` status menu | `titlesWhilePaused = titlesWhileWatching` | SC-66 — the vocabulary holds while the state-following half breaks | **PROVEN** — `FAIL: exactly one of the four titles follows the watching state` |
| SC-68 | `self-check.sh` status menu | `[row.update(hasTarget=False) for row in drawn]` | SC-66 | **PROVEN** — `FAIL: every item in the secondary menu has something that performs it` |
| SC-69 | `self-check.sh` status menu | `statusItemMenu["autoenablesItems"] = True` | SC-68 | **PROVEN** — `FAIL: the secondary menu decides its own enabled states rather than letting AppKit guess` |
| SC-70 | `self-check.sh` status menu | `statusItemMenu["settingsMenuItemTitle"] = ""` | SC-66 | **PROVEN** — `FAIL: the app menu holds a ⌘, item for the secondary menu's Settings… to perform` |
| SC-71 | `self-check.sh` model tier | `report["relevance"]["modelTier"] = {}` | SC-74 — the other model rows fire too, so an empty reading cannot pass as a quiet one | **PROVEN** — `FAIL: the running application reports a model-tier reading` |
| SC-72 | `self-check.sh` model tier | `modelTier["availability"] = "definitelyOn"` | SC-71 | **PROVEN** — `FAIL: the model availability is one of the six named cases` |
| SC-73 | `self-check.sh` model tier | `modelTier["availabilityIsExecutable"] = not …` | SC-72 — the vocabulary holds while the executability half breaks | **PROVEN** — ``FAIL: only `available` is executable, whatever this Mac said`` |
| SC-74 | `self-check.sh` model tier | `modelTier["composesTheRung"] = True` | SC-75 — the composed-ladder witness is independent of the constant | **PROVEN** — `FAIL: this build does not compose the model rung — measured: seduced 15 of 30 hold cells, budget 0` |
| SC-75 | `self-check.sh` model tier | `modelTier["rungIsComposed"] = True` | SC-74 — **the two witnesses of one decision, each red on its own** | **PROVEN** — `FAIL: the composed ladder agrees with the release decision` |
| SC-76 | `self-check.sh` model tier | `modelTier["executableRungs"] = 9` | SC-75; and the number is read from `EvaluationPolicy.executableRungCeiling`, which stage 7d holds `evaluation.json` to | **PROVEN** — `FAIL: the running ladder holds 8 executable rungs` |
| SC-77 | `self-check.sh` model tier | `modelTier["notComposedReason"] = ""` | SC-74 — the decision holds while its reason goes missing | **PROVEN** — `FAIL: the decision not to compose carries its reason` |
| SC-78 | `self-check.sh` model tier | `modelTier["capabilityState"] = "denied"` | SC-72 — and it is the row the capability matrix is decided from, so the matrix cannot agree with a tier that disagrees with itself | **PROVEN** — ``FAIL: the capability matrix row follows the availability, and is never `denied` `` |
| SC-71 | `self-check.sh` version | `report["settingsDrewnVersion"] = "9.9.9 (99)"` | SC-72 — both readings are non-empty, so this is a disagreement rather than an absence | **PROVEN** — `FAIL: the version the General pane drew is the version this build calls itself` |
| SC-72 | `self-check.sh` version | `settingsDrewnVersion = ""; bundleVersion = ""` | is itself the non-vacuity control for SC-71 | **PROVEN** — `FAIL: the General pane drew a version at all` |
| SC-73 | `self-check.sh` About | `report["aboutCredits"] = "shell.about.credits"` | SC-74 | **PROVEN** — `FAIL: the About panel's credits resolve to a paragraph rather than to their own key` |
| SC-74 | `self-check.sh` About | `aboutCredits.replace("no permissions", "some permissions")` | SC-73 — the paragraph still resolves while what it says is false | **PROVEN** — `FAIL: the About panel says what the app does not look at and where what it records stays` |
| SC-75 | `self-check.sh` restoration | `report["restoredWindows"] = []` | SC-77 — the record still reads, so this is not a launch that read nothing | **PROVEN** — `FAIL: the Keyboard Shortcuts window the last quit recorded was asked for again` |
| SC-76 | `self-check.sh` restoration | `report["visibleSceneIdentifiers"] = ["cockpit"]` | SC-75 — the request half holds while the window half breaks | **PROVEN** — `FAIL: restoration put the Keyboard Shortcuts window back on the screen` |
| SC-77 | `self-check.sh` restoration | `report["restorationRecord"] = []` | is itself the control for SC-75 | **PROVEN** — `FAIL: the restoring launch read the window record the seeding launch wrote` |
| SC-78 | `self-check.sh` restoration | `report["hasRestoredWindows"] = False` | SC-77 | **PROVEN** — `FAIL: the launch ran its window restoration exactly once` |
| SC-79 | `self-check.sh` login item | `loginItemStatusesDeclared.append("pending")` | SC-80 | **PROVEN** — `FAIL: the login-item vocabulary is the committed four, in order and with nothing else in it` |
| SC-80 | `self-check.sh` login item | `report["loginItemOfferShown"] = not …` | SC-81 — the fold's inputs hold while its output breaks | **PROVEN** — `FAIL: loginItemOfferShown: the offer follows the service's status, the history and the record` |
| SC-81 | `self-check.sh` login item | `report["loginItemCompletedSessions"] = 0` | is itself the control for SC-80 | **PROVEN** — `FAIL: the seeded store really holds a finished session for the offer to follow` |
| SC-82 | `self-check.sh` login item | `loginItemOfferDrawn` flipped | SC-80 — the decision holds while the row disagrees with it | **PROVEN** — `FAIL: the cockpit footer drew the offer exactly when the host said to` |
| SC-83 | `self-check.sh` first run | `report["firstRunExplanationShown"] = False` | SC-84 | **PROVEN** — `FAIL: a store the app had never opened was owed the first-run explanation, and got it` |
| SC-84 | `self-check.sh` first run | `report["firstRunExplanationDrawn"] = "hidden"` | SC-83 — the decision holds while the window disagrees | **PROVEN** — `FAIL: the cockpit really put the first-run explanation on the screen` |
| SC-85 | `self-check.sh` first run | `report["firstRunExplanationOwedNow"] = True` | SC-83 | **PROVEN** — `FAIL: showing the explanation wrote it down, in the store the next launch reads` |
| SC-86 | `self-check.sh` first run | `report["firstRunExplanationStillShown"] = True` | SC-83 | **PROVEN** — `FAIL: the explanation's dismissal reached the composition root and took the sheet down` |
| SC-90 | `self-check.sh` first run | `report["attachedSheetsAfterDismissal"] = 1` | SC-86 — the state came down while the window kept the sheet | **PROVEN** — `FAIL: no sheet is attached to any window by the time the process terminates` |
| SC-87 | `self-check.sh` first run | `firstRunExplanationShown = True` (relaunch) | SC-89 — the relaunch still opened the same store | **PROVEN** — `FAIL: the launch after the one that explained is not owed the explanation again` |
| SC-88 | `self-check.sh` first run | `firstRunExplanationDrawn = "shown"` (relaunch) | SC-87 | **PROVEN** — `FAIL: the relaunched cockpit drew no first-run sheet at all` |
| SC-89 | `self-check.sh` first run | `livePriorityIntent` replaced (relaunch) | is itself the control for SC-87/SC-88 | **PROVEN** — `FAIL: the relaunch opened the same seeded store the explaining launch did` |
| SC-122 | `self-check.sh:1795` | `report["shellRendering"]["driveInterventionSink"]["storedVoiceWasRecognised"] = False` | SC-123 — the decoder still answers on a raw value no build declares, so this is a disagreement about THIS Mac's row rather than a decoder that has stopped reading | **PROVEN** — `FAIL: this build can read the deck the store holds, so nobody's voice was quietly reinterpreted` |
| SC-123 | `self-check.sh:1803` | `report["shellRendering"]["driveInterventionSink"]["anUnreadableDeckIsReported"] = False` | SC-122 — this Mac's own row still reads, so the pair cannot be green on a decoder that answers `True` to everything | **PROVEN** — `FAIL: a deck this build cannot read is reported as unread and answered with the shipped deck` |

### The idle sources (focus-7az) — `selfcheck-debug` / `selfcheck-release`

H-JSON, run by `/private/tmp/mw/run-sc-idle.zsh <log dir> release` against gate run
`/private/tmp/focus-idle-logs-3` (23/23 green). Like the focus-odz rows it needs the self-check's
own side artefacts, which the stage deletes on exit, so it is pointed at a run of a **copy** of
`self-check.sh` with three lines changed — `REPO_ROOT` pinned to the real repository so a literal
that moves moves for the harness too, `SESSION_DIR` pinned, and the `trap` removed. The control
(unmutated copy) is green: `EXIT=0`.

**What these rows replaced.** `self-check.sh` used to assert "the hardware idle figure is not
below the session one (the sources are not swapped)", on the argument that `.combinedSessionState`
counts a superset of the events `.hidSystemState` counts. It had no witness row, and it was false:
at `kCGAnyInputEventType` the hardware state returns IOHIDSystem's `HIDIdleTime`, which a HID
device report resets without producing an input event. The run above published hid **3 457.77 s**
beside combined **18 456.16 s** — the deleted assertion was red on a machine telling the truth.

| # | script:line | mutation (H-JSON) | control | status — the line it printed |
|---|---|---|---|---|
| SC-91 | `self-check.sh:2203` | `report["sensing"]["idle"]["perEventType"] = report["sensing"]["idle"]["perEventType"][:3]` | SC-93 — the agreement holds while the floor breaks | **PROVEN** — `FAIL: both idle states were read for at least 4 distinct concrete event types` / `got: ['keyDown', 'leftMouseDown', 'mouseMoved']` |
| SC-92 | `self-check.sh:2203` | four copies of one row: `r = …["perEventType"]; …["perEventType"] = [dict(r[0]) for _ in range(4)]` | SC-91 — the count alone would pass this | **PROVEN** — `FAIL: both idle states were read for at least 4 distinct concrete event types` / `got: ['mouseMoved']` |
| SC-93 | `self-check.sh:2221` | `report["sensing"]["idle"]["perEventType"][0]["hardwareSeconds"] += 5.0` | SC-91 — the floor holds while the agreement breaks | **PROVEN** — `FAIL: per concrete event type the two idle states agree within 1.0 s` / `got: [('mouseMoved', 18461.4181935, 18456.418193209)]` |
| SC-94 | `self-check.sh:2221` | `report["sensing"]["idle"]["perEventType"][2]["sessionSeconds"] += 3600.0` | SC-93 — the gap the *other* way is red too, which is the whole point | **PROVEN** — `FAIL: per concrete event type the two idle states agree within 1.0 s` / `got: [('leftMouseDown', 18456.389179583, 22056.389179542)]` |
| SC-95 | `self-check.sh:2242` | `i = report["sensing"]["idle"]; i["isIdleForThisReading"] = not i["isIdleForThisReading"]` | SC-96 — the committed pair's verdict holds while the live one breaks | **PROVEN** — `FAIL: the app's idle verdict is the longer of the two counters against the threshold` / `got: (False, 3457.770909375, 18456.162585334, 180)` |
| SC-96 | `self-check.sh:2277` | `report["sensing"]["idle"]["phantomHidPair"]["isIdle"] = False` | SC-97 — the figures hold while the verdict breaks | **PROVEN** — `FAIL: a hardware clock reset by a phantom HID report does not make an absent person present` / `got: False` |
| SC-97 | `self-check.sh:2266` | `report["sensing"]["idle"]["phantomHidPair"]["sessionSeconds"] = 14850.05` | SC-96 — the verdict holds while the pair it is about moves | **PROVEN** — `FAIL: the app judged the measured phantom-HID pair, 105.71 s against 14850.04 s at 180 s` / `got: (105.71, 14850.05, 180)` |

SC-95 is the row that needed SC-96 beside it. On a gate rig nobody is touching, both live counters
are hours past the 180 s threshold, so `max(hid, session) >= t` and the `hid >= t` it replaced
agree and a reverted build passes SC-95's assertion in silence — measured: the first attempt at
that witness came back `MISS`. SC-96 is the case that discriminates the two rules on any rig at
any hour, because the pair is the committed one the probe measured rather than whatever the room
is doing.


SC-122 and SC-123 were **PENDING** for two rounds — no green gate run existed on this Mac to point
the harness at, because `combinedSessionState` and `hidSystemState` had diverged and both
self-check stages were red on a fact about the machine. `focus-7az` closed that (SC-91..SC-97
above), and both rows were run for this round against the green run at
`/private/tmp/focus-s8-logs-1` (23/23). They were also renumbered: they carried SC-91/SC-92, which
the idle section above had since taken, so the file held two different rows under one identifier.

### A question answered with no mouse (e07a, focus-6pr.1; SC-111 and SC-112 are focus-6pr.3's) — `selfcheck-debug` / `selfcheck-release`

H-JSON, run by `/private/tmp/mw/run-sc-e07a.zsh <FOCUS_EVIDENCE_DIR>` against a
`scripts/self-check.sh` run of the Debug product with `FOCUS_EVIDENCE_DIR` set
(`/private/tmp/focus-s6-logs-0/evidence-t1c` for SC-98..SC-110, `evidence-t5` for all fourteen, `SELF-CHECK OK`). The reader takes a **thirteenth**
argument since e07a — the sixth launch's report (`keyboard-answer.json`), the nudge block alone
against a store the script owns — and the harness doctors a copy of either the primary report or
that one. The control (unmutated copies) is green: `EXIT=0`.

**What was measured on the way to these rows.** SwiftUI pushes a changed `.disabled(…)` into an
`NSMenuItem` only when AppKit asks the menu's delegate `menuNeedsUpdate(_:)` — before a tracking
session and before a key-equivalent search through `NSApplication.sendEvent(_:)`. `NSMenu.update()`
and a direct `NSMenu.performKeyEquivalent(with:)` do **not** ask, and the first draft of this
block pressed a stale item: `commandsObservedOnPress = []`, nothing written. The block now sends
the key through `sendEvent`, and the report carries the stale read beside the refreshed one
(`itemsAsLastDrawn*` / `itemsEnabled*`) so the laziness is a fact in the evidence rather than a
surprise in the next repair.

| # | script:line | mutation (H-JSON) | control | status — the line it printed |
|---|---|---|---|---|
| SC-98 | `self-check.sh` keyboard | primary: `report["nudge"]["keyboardAnswer"]["wasTaken"] = True` | SC-99 — the owned-store launch still took it | **PROVEN** — `FAIL: the ordinary launch did not answer a question in the person's own store` / `got: {'notTakenBecause': …, 'wasTaken': True}` |
| SC-99 | `self-check.sh` keyboard | keyboard: `wasTaken = False; notTakenBecause = "doctored"` | SC-98 — the ordinary launch's NOT TAKEN still holds | **PROVEN** — `FAIL: the keyboard-answer reading was taken against the owned store` / `got: (False, 'doctored')` |
| SC-100 | `self-check.sh` keyboard | keyboard: `activationWasObserved = False` | SC-101 — the question's survival is read separately | **PROVEN** — `FAIL: activating the application really brought this process to the front` / `got: ('com.google.Chrome', 'com.chrismitchelmore.FocusSentinel')` |
| SC-101 | `self-check.sh` keyboard | keyboard: `questionSurvivedActivation = False` | SC-100 — the activation really happened | **PROVEN** — `FAIL: activating the application (a ⌘-Tab to Focus) leaves the open question and its panel standing` / `got: (False, True)` |
| SC-102 | `self-check.sh` keyboard | keyboard: `itemsEnabledWithQuestion["nudge.answerNo"] = False` | SC-103 — the withdrawn side still holds | **PROVEN** — `FAIL: with a question open, all three answering items are enabled in the View menu` / `got: {'nudge.answerNo': False, 'nudge.answerNotNow': True, 'nudge.answerYes': True}` |
| SC-103 | `self-check.sh` keyboard | keyboard: `itemsEnabledWithoutQuestion["nudge.answerYes"] = True` | SC-102 — the offered side still holds | **PROVEN** — `FAIL: with the question answered, all three answering items are withdrawn from the View menu` / `got: {'nudge.answerNo': False, 'nudge.answerNotNow': False, 'nudge.answerYes': True}` |
| SC-104 | `self-check.sh` keyboard | keyboard: `questionOpenAfterPress = True` | SC-105 — the receipt still reads as written | **PROVEN** — `FAIL: ⌃⌘Y ended the question and took its panel down` / `got: (True, False)` |
| SC-105 | `self-check.sh` keyboard | keyboard: `receiptOutcome = "declined"` | SC-106 — the rule half is read separately | **PROVEN** — `FAIL: the receipt is the answer the title promised, on the subject the question was about` / `got: ('declined', 'com.chrismitchelmore.FocusKeyboardProbe', …)` |
| SC-106 | `self-check.sh` keyboard | keyboard: `ruleVerdict = "unrelated"` | SC-105 — the receipt half is read separately | **PROVEN** — `FAIL: the rule is the verdict the title promised, on the subject the question was about` / `got: ('unrelated', 'com.chrismitchelmore.FocusKeyboardProbe', …)` |
| SC-107 | `self-check.sh` keyboard | keyboard: `commandsObservedOnPress = ["answerYes", "answerYes"]` | SC-104 — one press, one ending | **PROVEN** — `FAIL: the key reached the command centre as exactly one answerYes` / `got: ['answerYes', 'answerYes']` |
| SC-108 | `self-check.sh` keyboard | keyboard: `receiptsAfterSecondPress = 2` | SC-105 — the first press's receipt is still the one | **PROVEN** — `FAIL: a second ⌃⌘Y with no question open wrote nothing` / `got: (2, 1)` |
| SC-109 | `self-check.sh` availability | primary: `report["commands"]["world"].pop("hasOpenQuestion")` | SC-110 — the per-item rule still reads the field | **PROVEN** — `FAIL: the app reported the whole world its menu availability is computed from` / `got: ['hasOpenNudge', 'hasPriority', 'sessionPhase']` |
| SC-110 | `self-check.sh` availability | primary: `nudge.answerNotNow`'s `isAvailable = True` | SC-109 — the world is still whole | **PROVEN** — `FAIL: 'Answer Not Now' is offered exactly when the app could carry it out` / `got: (True, False, {… 'hasOpenQuestion': False …})` |
| SC-111 | `self-check.sh` privacy | primary: `shellRendering.privacyActionsDeclared = ["deleteEverything", "exportEverything"]` | SC-112 — the sink is still held | **PROVEN** — `FAIL: the Privacy pane's action vocabulary is exactly deleteEverything` / `got: ['deleteEverything', 'exportEverything']` |
| SC-112 | `self-check.sh` privacy | primary: `shellRendering.privacySinkHeld = False` | SC-111 — the vocabulary is still one case | **PROVEN** — `FAIL: the Settings window handed back the sink the Privacy pane's control reaches` / `got: False` |

### History, and correcting a silence (e09a, focus-tee.4 / focus-tee.5) — `selfcheck-debug` / `selfcheck-release`

H-JSON, run by `/private/tmp/mw/run-sc-e09a.zsh <FOCUS_EVIDENCE_DIR>` against a
`scripts/self-check.sh` run of the Debug product with `FOCUS_EVIDENCE_DIR` set
(`/private/tmp/mw/e09a-evid`, `SELF-CHECK OK`), in the same shape as `run-sc-e07a.zsh`: the
reader's own python heredoc is extracted from the script and run against a doctored **copy** of
the primary report with the argv the stage passes. Nothing tracked is touched. The harness runs
the unmutated copy first and refuses to report a row if the control is not green.

SC-121 is the one row in this block that is about a **measurement rather than a claim**. The
replay-fidelity figures are printed and asserted about in no way at all — that is deliberate, and
the argument is in `SelfCheck.replayFidelityReport()` — so the only thing there is to witness is
that the block ran, which is exactly what a block that quietly stopped producing figures would
otherwise look like.

| # | script:line | mutation (H-JSON) | control | status — the line it printed |
|---|---|---|---|---|
| SC-113 | `self-check.sh` history | `historyLedger.available = False; error = "doctored"` | the harness runs the unmutated copy first: `CONTROL … EXIT=0` | **PROVEN** — `FAIL: the seeded history ledger was built` / `got: 'doctored'` |
| SC-114 | `self-check.sh` history | `historyLedger.sessions = 0` | SC-115 — the silent-interval count is asserted in its own right | **PROVEN** — `FAIL: the ledger drew the one intervention, the one question and the one session it was seeded` / `got: (1, 1, 0)` |
| SC-115 | `self-check.sh` history | `historyLedger.silences = 4` | SC-114 — the other three counts still hold | **PROVEN** — `FAIL: four observations over three subjects become three silent intervals` / `got: (4, 4)` |
| SC-116 | `self-check.sh` history | `silencesWithdrawn = 0; silencesOffered = 3; withdrawalReasons = ""` | SC-115 — the interval count is unchanged, so this is about the affordance and not about the rows | **PROVEN** — `FAIL: the two application intervals are correctable and the origin one is withdrawn, with a reason` / `got: (3, 0, '')` |
| SC-117 | `self-check.sh` history | `historyLedger.entriesAreChronological = False` | the harness runs the unmutated copy first: `CONTROL … EXIT=0` | **PROVEN** — `FAIL: the ledger's rows are one list in one order` / `got: False` |
| SC-118 | `self-check.sh` history | `historyLedger.rulesWrittenByCorrection = 0` | SC-119, SC-120 — the ledger and the log are asserted separately | **PROVEN** — `FAIL: correcting a silence writes exactly one rule` / `got: (True, 0)` |
| SC-119 | `self-check.sh` history | `historyLedger.queryReceiptsAfter = 2` | SC-118 — the rule was still written, so this is D3 and not "nothing happened" | **PROVEN** — `FAIL: correcting a silence is never a re-ask: the query ledger does not move` / `got: (1, 2)` |
| SC-120 | `self-check.sh` history | `historyLedger.interventionRowsAfterCorrection = 2` | SC-118 — the rule was still written | **PROVEN** — `FAIL: correcting a silence never edits the log` / `got: 2` |
| SC-121 | `self-check.sh` history | `historyReplay.available = False; error = "doctored"` | the harness runs the unmutated copy first: `CONTROL … EXIT=0` | **PROVEN** — `FAIL: the replay-fidelity measurement ran` / `got: 'doctored'` |

### R-168 — the facts the report publishes that nothing used to read — `selfcheck-debug` / `selfcheck-release`

H-JSON, run by `/private/tmp/mw2/run.zsh <label> <mutation>` against the green run at
`/private/tmp/focus-s8-logs-1` (23/23). Like the focus-odz and focus-7az rows it needs the
self-check's own side artefacts, which the stage deletes on exit, so it is pointed at a **copy**
of `self-check.sh` with `REPO_ROOT` pinned to the real repository, `SESSION_DIR` pinned and the
`trap` removed; a second copy replaces the six application launches with copies of the captured
reports, so a mutation costs a second rather than a launch. The control (unmutated copy) is
green: `EXIT=0`, 671 ok.

Every row below is an assertion the `published-keys` round added: before it, each of these keys
was published by the Release binary and fetched by no reader at all.

| # | script:line | mutation (H-JSON) | control | status — the line it printed |
|---|---|---|---|---|
| SC-124 | `self-check.sh:4478` | `r["nudge"]["chargesPaidFor"] += 1` | SC-125 — the channels hold while the join breaks | **PROVEN** — `FAIL: every delivered intervention row was paid for by a perception receipt` |
| SC-125 | `self-check.sh:4486` | `r["nudge"]["chargeChannels"] = ["notAChannel"]` | SC-124 | **PROVEN** — `FAIL: every charge was perceived on a channel some surface really has` |
| SC-126 | `self-check.sh:4515` | `r["nudge"]["budgetAfterADayOfLandings"]["panel"]["accusationsToday"] = 7` | SC-124 — the live join holds while the seeded day breaks, which is the non-vacuous half | **PROVEN** — `FAIL: a day of eight panel landings spends eight accusations and binds on the daily cap` |
| SC-127 | `self-check.sh:4584` | `r["relevance"]["skippedRuleCount"] = 1` | the harness runs the unmutated copy first: `CONTROL … GREEN (EXIT=0, 671 ok)` | **PROVEN** — `FAIL: the snapshot builder dropped no rule it could not read` |
| SC-128 | `self-check.sh:4532` | `r["nudge"]["surfacesOfferingAnAnswer"] = list(r["nudge"]["surfacesHoldingTheInterruptionSlot"])` | SC-129 — the row-wise table holds while the two lists are conflated | **PROVEN** — `FAIL: holding the interruption slot and offering an answer are still two different questions` |
| SC-129 | `self-check.sh:4556` | `[row.__setitem__("holdsTheInterruptionSlot", True) for row in r["nudge"]["surfaceAttention"] if row["surface"] == "popoverBadge"]` | SC-128 — the lists hold while the table they are folded from breaks | **PROVEN** — `FAIL: the surfaces whose rows hold the interruption slot are exactly the list that says so` |
| SC-130 | `self-check.sh:4648` | `[w.__setitem__("title", "Nope") for w in r["windows"] if w.get("identifier") == "cockpit"]` | SC-131 — the summary holds while the list disagrees with it | **PROVEN** — `FAIL: the cockpit's row in the window list agrees with the cockpitWindow summary field by field` |
| SC-131 | `self-check.sh:4677` | `r["cockpitWindow"]["styleMask"] += 16` | SC-130 | **PROVEN** — `FAIL: the cockpit window's style mask is exactly titled, closable, miniaturizable, resizable and full-size content` |
| SC-132 | `self-check.sh:4697` | `r["nudge"]["panel"]["properties"]["canBecomeKey"] = False` | the app's own `propertiesAreCorrect` fold stays green, which is why the nine are read one by one | **PROVEN** — `FAIL: the nudge panel's canBecomeKey is True` |
| SC-133 | `self-check.sh:4711` | `r["nudge"]["panel"]["subjectNaming"]["running"]["displayName"] = "Something Else"` | the other four naming cases hold | **PROVEN** — `FAIL: asked about a running application, the panel gives its display name and its bundle id` |
| SC-134 | `self-check.sh:4753` | `r["nudge"]["panel"]["frontMovedDuringTheShow"] = True` | R-89 reading 1 holds; this is reading 4's own fact | **PROVEN** — `FAIL: reading 4: the frontmost application was read both times and did not move` |
| SC-135 | `self-check.sh:4882` | `r["shellRendering"]["rendered"]["cockpit"]["values"]["status"] = None` | SC-136 — the totality holds while a receipt goes missing | **PROVEN** — `FAIL: every field the cockpit drew carries a receipt` |
| SC-136 | `self-check.sh:4897` | `r["shellRendering"]["totalities"]["cockpit"]["strandedPaths"] = ["state.ghost"]` | SC-135 | **PROVEN** — `FAIL: the cockpit connection is total: nothing stranded, unmapped or unreported` |
| SC-137 | `self-check.sh:4924` | `r["shell"]["handoffURL"] = "focus://start?task=Something%20else"` | the handoff rendering's own fold holds | **PROVEN** — `FAIL: the handoff URL carries exactly the task the app says it received` |
| SC-138 | `self-check.sh:4977` | `r["historyReplay"]["momentsBeforeIntentEdit"] = 15` | the three seeded counts hold | **PROVEN** — `FAIL: sixteen of the replayed moments predate the intent edit that makes them unreplayable` |
| SC-139 | `self-check.sh:4961` | `r["nudge"]["tickFetches"]["noCommitment"]["cockpitFetchesOverSteadyTicks"] = 17` | the other two lanes hold, so this is one lane's rate and not the fold | **PROVEN** — `FAIL: the cockpit fetched the store exactly twice a tick over the noCommitment lane` |
| SC-140 | `self-check.sh:4936` | `r["sensing"]["cascade"] = ["windowMetadata", "frontmostApplication"]` | the order is the assertion: the same two sources, reversed | **PROVEN** — `FAIL: the sensing cascade is exactly the two sources, in order` |
| SC-141 | `self-check.sh:5093` | `r["authorisationSurfaceScan"]["notTakenBecause"] = "a reason it should not have"` | the NOT-TAKEN sweep and its six-fact floor hold; this is the pair's consistency | **PROVEN** — `FAIL: every reading that was taken gives no reason, and every one refused says why` |
| SC-142 | `self-check.sh:4598` | `r["relevance"]["verdict"]["stampKey"] = "s9.p9.l9.e9.m9"` | the block's own stamp and digest hold | **PROVEN** — `FAIL: the verdict carries the stamp of the engine that produced it` |
| SC-143 | `self-check.sh:4786` | `r["nudge"]["routes"][0]["isInApp"] = False` | the folded `everyRungIsInApp` holds, which is why the rows are read too | **PROVEN** — `FAIL: every route in the table stays inside the application` |
| SC-144 | `self-check.sh:4798` | `r["statusItemMenu"]["installed"] = False` | the menu's four drawn items hold | **PROVEN** — `FAIL: the status item's menu is installed` |
| SC-145 | `self-check.sh:4813` | `r["settingsDrewnVersion"] = "9.9.9 (9)"` | the bundle's own version fields hold | **PROVEN** — `FAIL: the version Settings drew is the version the bundle carries` |

### The ceiling itself, not the panel against it (focus-ocs) — `selfcheck-*` and `focus-steal-*`

H-JSON on the same harness as the R-168 rows. `check-focus-steal.sh` carries the identical
`check_ceiling` block over the same two surfaces, so a row proven here is proven there; the third
instance, in the unit lane, is `NudgePanelTests` and is asserted in Swift.

The old row — *the panel is within the N-point ceiling* — read N out of the report the panel's own
controller wrote. SC-146 is the mutant the bead measured: it used to leave the stage GREEN with the
text re-rendered as *within the 4000-point ceiling (measured 149)*. SC-148 is the other half, and it
is why the committed number is written in the gate as well as read from the source: a round that
wanted a taller panel could raise the constant and, with the source pin alone, the gate would
raise its bound to match.

| # | script:line | mutation | control | status — the line it printed |
|---|---|---|---|---|
| SC-146 | `self-check.sh:4839` | `r["nudge"]["panel"]["maximumContentHeight"] = 4000.0 — the bead's own mutant, `maximumContentHeight` returning 4000, as the report carries it` | SC-147 — the constant holds while the function that reads it stops | **PROVEN** — `FAIL: the panel's ceiling is within what the display can hold with its margins out (4000.0 <= 972 - 48)`, and `FAIL: the panel's ceiling is within its own proportionality limit (4000.0 <= 800)` |
| SC-147 | `self-check.sh:4853` | `r["nudge"]["panel"]["absoluteMaximumHeight"] = 4000.0` | SC-146 — the display bound holds while the limit the binary reports moves | **PROVEN** — `FAIL: the panel's proportionality limit is the committed 800 points` |
| SC-148 | `self-check.sh:4871` | `the SOURCE constant raised — `static let absoluteMaximumHeight: Double = 4000` in NudgePanelController.swift, with the binary unchanged. **This is the mutant the old row could not catch**: raising the constant raised the bound, and the gate followed it up` | SC-146 — the report is untouched, so this is the script's own committed number doing the work | **PROVEN** — `FAIL: NudgePanelController.absoluteMaximumHeight is still the committed 800 in the source it is declared in` |
| SC-149 | `self-check.sh:4839` | `r["nudge"]["popover"]["maximumContentHeight"] = 4000.0` | SC-150 — the popover declares no limit of its own, so the display is all that bounds it | **PROVEN** — `FAIL: the popover's ceiling is within what the display can hold with its margins out (4000.0 <= 972 - 50)` |
| SC-150 | `self-check.sh:4833` | `r["nudge"]["panel"]["heightReservedForMargins"] = 0` | SC-146 — the ceiling holds while the margin it reserves goes to nothing | **PROVEN** — `FAIL: the panel reserves margin rather than offering to fill the display (0)` |

### The disagreement reading, driven rather than waited for (focus-0gq) — `selfcheck-*`

**H-SRC, and it is the bead's own mutation**: `PriorityHost.swift`'s `activeCommitment =
nextCommitment` becomes `if activeCommitment == nil { activeCommitment = nextCommitment }`, so the
field freezes after its first assignment while `snapshotKey` and `state.priority` move on. Built
into `/private/tmp/focus-s9-mut-dd`, run, and the source restored. Control: the unmutated build
is green at EXIT=0.

**What this replaced.** The two standing assertions — `commitmentDisagreements == []` and
`mandatesWithoutACommitment == 0` — survived that exact mutation at EXIT=0 with an empty
ok-assertion diff, because nothing in an automated run ever changed the active priority after it
was seeded. The keyboard launch now seeds a priority, opens and answers a real question, and
REPLACES the priority; the mutant then publishes three named disagreements.

| # | script:line | mutation (H-SRC) | control | status — the line it printed |
|---|---|---|---|---|
| SC-151 | `self-check.sh:4133` | freeze `PriorityHost.activeCommitment` after its first assignment | SC-152 — the non-vacuity half: a probe that replaced nothing proves nothing | **PROVEN** — `FAIL: the probe really replaced the active priority, so the readings below had a chance to part` |
| SC-152 | `self-check.sh:4138` | freeze `PriorityHost.activeCommitment` after its first assignment | SC-151 | **PROVEN** — `FAIL: every statement of the commitment still agrees after the priority is replaced` |
| SC-153 | `self-check.sh:4143` | freeze `PriorityHost.activeCommitment` after its first assignment | SC-152 — a representation that lags by exactly one tick passes SC-152 and fails here | **PROVEN** — `FAIL: and still agrees a turn of the loop later, so nothing lags by one tick` |

The mutant's own report, quoted because it is what the invariant exists to say: `disagreementsAfterReplacement` came back as `['snapshotKey.priorityID … ≠ activeCommitment …', 'state.priority.id … ≠ activeCommitment …', 'state.priority.intent ≠ activeCommitment.intent']`.

### `published-keys` — `scripts/check-published-keys.sh`

The stage reads two artefacts of one run — the report the Release binary wrote and the read set
`scripts/keyreads.py` recorded — against one committed list. So its harness is neither H-JSON nor
H-SRC: a copy of the script sits in `/private/tmp/mw2/pk/scripts/` with its own `Config/`, and each
row doctors the report, the read set or the list. The control (nothing doctored) is green:
`PUBLISHED-KEYS OK — 772 published, 758 read, 14 listed`.

All four rules are witnessed, in both directions, because a list linted one way is an off-switch:
PK-02 is the row deleted, PK-03b is the row added to excuse a key that is still read.

| # | rule | mutation | control | status — the line it printed |
|---|---|---|---|---|
| PK-01 | 1 | `report["witnessOnlyKey"] = 1` — a published key no reader fetches | the unmutated copy is green | **PROVEN** — `FAIL [R-168] every published key is either read by a gate reader or listed with a reason` / `got: ['witnessOnlyKey']` |
| PK-02 | 1 | delete the `relevance.verdict.band` row while the key is still unread | PK-01 — the report is untouched, so this is the list's own rot | **PROVEN** — `FAIL [R-168] every published key is either read by a gate reader or listed with a reason` / `got: ['relevance.verdict.band']` |
| PK-03a | 1 | remove `nudge.surfacesOfferingAnAnswer` from the read set, as deleting its `check(...)` would | PK-01 | **PROVEN** — `FAIL [R-168] every published key is either read by a gate reader or listed with a reason` / `got: ['nudge.surfacesOfferingAnAnswer']` |
| PK-03b | 3 | add that same key to the list **without** deleting the read | PK-03a — the two halves of one defect; rule 3 is what stops the list excusing a key that is asserted | **PROVEN** — `FAIL [R-168] no listed key is now read; a key that gained an assertion loses its row` / `got: ['nudge.surfacesOfferingAnAnswer']` |
| PK-04 | 2 | add a row for `nudge.keyThatWasRemoved`, a key nothing publishes | PK-01 | **PROVEN** — `FAIL [R-168] every listed key is still published by the self-check` / `got: ['nudge.keyThatWasRemoved']` |
| PK-05 | 4 | blank the reason column of the `sensing.media.audioListenerCount` row | PK-01 | **PROVEN** — `FAIL [R-168] every row carries a path, a reason and a bead column` / `got: [(27, 'sensing.media.audioListenerCount ·  · NONE-BY-DESIGN')]` |
| PK-06 | floor | empty the read set, as a reader dying before its first fetch would | the four rules above are all satisfied by a read set that is merely short — this is the case where the FILE is empty | **PROVEN** — `FAIL [R-168] <path> is empty: no gate reader recorded a single fetch` |

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


### R-169 — the menu-bar stage's NOT TAKEN outcome (focus-39x) — `forbidden`

H-SRC on the working tree, restored immediately. The rule is a text scan over the twelve suites
that open the stage, so its harness is the edit a careless caller would make.

| # | rule | mutation | control | status — the line it printed |
|---|---|---|---|---|
| FB-01 | R-169 (bind) | drop the `let opened =` from `NudgeFloorTests.swift:361`, leaving `try MenuBarStage.open(` | the other eleven suites stay green, so this is one call site and not the scan | **PROVEN** — `[R-169] FAIL Packages/FocusHost/Tests/FocusHostTests/NudgeFloorTests.swift — 1 call(s) to MenuBarStage.open whose outcome is not bound` |
| FB-02 | R-169 (ask) | delete that site's `guard MenuBarStage.taken(opened) else { return }` | FB-01 — a suite that binds and never asks is the bare green the bead refuses, and it is a separate line | **PROVEN** — `[R-169] FAIL … — opens the stage and never asks MenuBarStage.taken(...)` |
| FB-03 | R-169 (vacuity) | no suite opens the stage at all | is the floor under FB-01 and FB-02, both of which are satisfied by an empty file set | **PROVEN by construction** — the rule counts the suites and fails at zero: `[R-169] FAIL no suite opens the menu-bar stage at all, so this rule is vacuous` |

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

### `release-artefact` — `scripts/build-gate.sh` (`release_artefact_stage`) and `scripts/package-release.sh`

The stage mounts the disk image read-only and asks six things of what is inside. Its harness is a
copy of the stage function sourced out of `build-gate.sh` with `package-release.sh` stubbed, so a
doctored image can be put where the honest one would be. The control is the honest image, which is
green: `STAGE EXIT=0`, `every file in both trees hashes the same:
18a20c8bd6eae8a3c24c07ff7c50f17dbec61a4190e3363a3eaf2a122fce5b21`.

| # | what it defends | mutation | control | status — the line it printed |
|---|---|---|---|---|
| RA-01 | the image holds exactly two things | add `EXTRA.txt` to the staging folder and rebuild the image | the honest image is green | **PROVEN** — `FAIL the image holds 'EXTRA.txt FocusSentinel.app README.txt ', not the application and the README alone` |
| RA-02 | the packaged application IS the built one | append one byte to `Contents/Info.plist` in the staged copy | RA-01 — the contents check and the digest are separate lines, and this moves the digest | **PROVEN** — `FAIL the packaged application is not the built one`, and `FAIL the packaged application's signature does not verify` beside it, which is the seal noticing the same byte |
| RA-03 | the artefact came from THIS tree | run the stage with the tree's commit set to `deadbee` while the product carries `741449c` | the honest run prints `ok the packaged product carries this tree's commit, 741449c` | **PROVEN** — `FAIL the packaged product carries '741449c', not this tree's 'deadbee'` |
| RA-04 | the README says what the commands said | rewrite `rejected` to `accepted` in the README on the image | RA-01 — the file is still there and still the only other one | **PROVEN** — `FAIL the README does not quote the rejection` |
| RA-05 | Gatekeeper really rejects it | — | — | **CANNOT-GO-RED here, and it is a finding rather than a failure.** The branch asserts `spctl` exits non-zero and fires when it exits **zero**, which needs a Mac that has been told to accept this artefact (`spctl --add`) — a change to the machine's own security policy, which this programme's harnesses may not make. The honest reading is exercised on every run and quoted: `rejected`, `spctl EXIT=3`. What is proven is that the reading is TAKEN and asserted, not merely printed; what is not proven is the machine lying about it. |
| RA-06 | the packager never signs | — | — | **BY CONSTRUCTION, and checked by R-96e's neighbours rather than by a mutation.** `scripts/package-release.sh` names `codesign` twice, both times with `--verify` or `-dv`; it names no identity, opens no keychain, and passes `hdiutil` no signing argument. |

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

### The baked commit (e10a) — `packaging`

| # | what it defends | mutation | control | status — the line it printed |
|---|---|---|---|---|
| PKG-07 | the product carries THIS tree's commit | build with `FOCUS_GIT_HASH=deadbee` and run the key loop against the merged plist | the ordinary build prints `ok [Debug] the merged Info.plist carries this tree's commit, 741449c` | **PROVEN** — `FAIL [Debug] the merged Info.plist's FocusGitHash is 'deadbee', not '741449c'`. The value is asserted and not merely the key's presence, because `FOCUS_GIT_HASH` defaults to EMPTY: a build made without it renders an empty string and every other check in this stage passes. |

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
zsh /private/tmp/mw/run-json-witnesses.zsh /private/tmp/mw/cases-odz.txt
zsh /private/tmp/mw/run-sc-idle.zsh /private/tmp/mw/idle-run release
FOCUS_MW_DD=/private/tmp/dd zsh /private/tmp/mw/run-binary-witnesses.zsh
FOCUS_MW_LOGS=/private/tmp/logs FOCUS_MW_DD=/private/tmp/dd \
    zsh /private/tmp/mw/run-log-witnesses.zsh
```

Each prints one line per row: the red line it produced, or `MISS`. A `MISS` is the same verdict
as a red gate — an assertion that cannot be shown to fail is a FAIL regardless of the run result.
