# Focus Sentinel — Handover, 8 September 2026

The table below records the 5 September baseline at `c1a7f79`. Release closeout is in progress on `codex/release-closeout`, including cockpit redesign `efdebdc`. Its 454-test comparison passed, but took 440.495 seconds against the 420-second snapshot budget; the integrated gate must remeasure that limit. App Intents adds 12 runner and 2 host tests, so the combined expected minimum is 2,289. The fresh full gate and live drive remain required. The existing Notion Status page is the primary status hub; Beads retains the engineering issue records.

## Where it stands

| | |
|---|---|
| Gate | `scripts/build-gate.sh`, 27 stages, ~30 min. Five sequential runs on `main` at `c1a7f79`: all PASS, identical counts |
| Tests | 2 275 across eight bundles (1055 / 28 / 185 / 116 / 13 / 140 / 454 / 284), floors in `Config/test-floors.txt` |
| Self-check | every published key is asserted or listed with a reason (`Config/unasserted-keys.txt`), 255 mutation witnesses in `Config/mutation-witnesses.md`, 253 proven red |
| Budgets | `Config/performance-budgets.txt`: ≤ 2 fetches per quiet tick, 0 nudge fetches, ≤ 3 hosting constructions per presentation change, snapshot lane ≤ 420 s, unit lane ≤ 900 s |
| Artefact | `FocusSentinel-0.1.0-c1a7f79.dmg` from the `release-artefact` stage; ad-hoc signed; Gatekeeper rejects it until Open is chosen from the context menu, and the README inside the image says so |
| Registry | 139 features: every one shipped, or parked with a verdict on its epic bead (`bd show focus-tee`, `focus-6pr`, `focus-26b`, `focus-qoq`, `focus-b7s`, `focus-mn7`) |

What shipped since 2 September, in order: the CoreAudio isolation crash (any microphone state change killed the app) and the gate's blindness to a dying test bundle; e05 closed and merged; the performance pass (popover no longer rebuilt every tick, quiet ticks cut from five fetches to two, 90-day retention, unit lane from 38 minutes to 10); the Mac essentials (reopen, status-item menu, About and version, launch at login, window restoration, first-run sheet); e06's on-device tier, built and honestly not composed; e11's voice, palette, hero, glyph family and icon; the idle-detection bug the gate found (the app trusted a hardware clock that resets on phantom device reports); e07a, e09a, e10a, e08a; the registry residuals; and the honest authorisation scan.

## Open issues

Tracker: `bd list --status=open` and `bd list --status=in_progress`. Release coordination is `focus-kuqz`; the concurrent cockpit redesign is `focus-6uya`.

| bead | what | why it is open |
|---|---|---|
| `focus-wh5` | The live drive: charter criteria 4 (read frames) and 5 (demonstrably nudges on a real distraction) | Needs current-build evidence and all 18 frames read. The driving surface needs Screen Recording and Accessibility; a skipped run is not completion |
| `focus-mn7` | F-141 App Intents | Implemented with literal main-bundle metadata in `App/FocusAppIntents.swift`, a narrow seven-key app catalogue, and shared command/host behaviour. Debug and Release metadata checks pass; 12 runner and 2 real-host tests passed. Final integrated gate and system discovery remain |
| `focus-b7s` | e06b: compose the model tier | Fresh 8 September evaluation on macOS 26.6.2: 135 consultations, 45 cells, three stable passes; contract passes, quality fails with 15 false silencings and 11 rescues. Remains disabled. Reopens on `seduced == 0` over three passes |

Parked with verdicts (see each epic bead's notes): e08b's marks, pulse and expansion behind notch-hardware probes P-e08-A..D; everything replay-derived in e09 behind the measurement that 8 of 28 moments replay; F-102/F-103 on D-01; F-87's sidebar on D-06; F-114's encrypted store on probe P-e07-K; F-124/F-125's grant ledger on PD-1; F-140 diagnostics with no destination in a local-only app; F-85 cut as a scope deletion; e12's rung 3 with a five-point verdict (`focus-5ab`).

Known residuals recorded in code and tests rather than beads: `IdleReading.syntheticInputSuspected` is one-sided; the accusation header's largest-size behaviour is proven by picture, not by a fold; the six-name authorisation-suspect list is not exhaustive (stated in the suite's vacuity guard); RA-05 (Gatekeeper accepting an ad-hoc build) cannot be witnessed red without changing the machine's security policy; the notch companion ships no toggle until a stored preference lands at schema v8.

## Approved copy (D-11)

Chris approved all 19 pending nudge and notch lines on 8 September 2026 in Codex task `01a08142-1e4c-7b10-a7e6-1526bd668ab3`. Catalogue comments now record `APPROVED BY USER (D-11, 2026-09-08)`; the wording is unchanged.

- Thirteen nudge lines, including the restart cue, in `Packages/FocusCore/Sources/FocusCore/Resources/Localizable.xcstrings`.
- Six notch lines in `Packages/FocusUI/Sources/FocusUI/Resources/Localizable.xcstrings`.

## Next steps, in order

1. **The live drive**. After the final integrated gate, from a driving surface holding Screen Recording and Accessibility:
   ```
   cd ~/work/focus
   FOCUS_DERIVED_DATA=/path/to/verified/derived-data \
   FOCUS_EVIDENCE_DIR="$PWD/.agents/evidence/e05/live-2026-09-08" \
   scripts/live-nudge-drive.sh > /private/tmp/focus-live-nudge.log 2>&1; echo "EXIT=$?"
   ```
   Read every frame under that directory, sign or refuse criteria 4 and 5 in `.agents/evidence/e05/README.md`, then `bd close focus-wh5`. If the kept derived data is gone, any green gate run with `FOCUS_KEEP_DERIVED_DATA=1` produces another.
2. **Integrate and verify** the cockpit redesign, then review and merge [PR #1](https://github.com/chrismitchelmore/focus-sentinel/pull/1), retaining the gate evidence and release artefact.
3. **Developer ID**, for a notarised distribution: a Developer ID Application identity and notarisation credentials are not present on this Mac. `scripts/package-release.sh` packages the already-signed app; it does not sign or notarise. A notarised release needs an explicit signing and notarisation workflow and verification of its output.
4. **Use the app for two weeks** and watch the direction document's own falsifier (`.agents/plans/epic-e11-identity-direction.md` §4): if rung-2 return-to-task decays towards the ambient baseline, the fix is cadence in `InterventionPolicy`, not copy.
5. **e11b follow-ups**: the `"%@" is waiting.` title is on probation with a flat fallback drafted; the colour-literal lint (S2 AC-3) was not built.
6. **e06b**, if a prompt or OS change makes `seduced == 0` reachable: flip `ModelTierRelease.composesTheRung`, record the green run under `.agents/evidence/e06/`, update the README's cascade table.
7. **App Intents**: finish system discovery and integrated verification on `focus-mn7`. `scripts/check-app-intents.py` validates the exported actions, required parameter, translated titles and foreground execution in both packaged configurations.
8. **Notch hardware**: on a notched MacBook, run probes P-e08-A..D from `.agents/plans/epic-e08a-prep.md` and file the receipts on the e08 bead; then e08b.

## How to work here

- Read `README.md` first; it is the operating manual and the gate's contract.
- `bd prime` for the tracker; `bd remember` and `bd memories <keyword>` for programme memory (rulings PD-1, the e07a/e09a/e10a/e08a rulings, the rig facts, the close).
- The gate is the bar. Never pipe `xcodebuild`; redirect unpiped and read the exit status. Pin `FOCUS_DERIVED_DATA` to a warm tree; a full run is about 30 minutes.
- Every fix carries a test that was red before it, every new self-check reading a pin and a mutation witness. A check that cannot go red is a defect.
- `.agents/` (plans, evidence, reviews, the completion plan) is gitignored by charter policy and lives only on the driving Mac. The completion plan and the six adversarial plan reviews are under `.agents/plans/`.

## Rig facts that matter

Mac mini `Mac16,10`, no built-in display, one external 1920×1080: the notch companion reports `noBuiltInDisplay` here by design. One code-signing identity (Apple Development), no Developer ID. FoundationModels is available and opens no socket. The gate passes on an untouched Mac since the idle-invariant fix; a permission dialog left on screen by another tool is reported as the machine's, not the app's.
