# Focus personality: design verification

The owner selected Little Signal with Lookout elements on 9 September 2026. `Design/Reference.png` is the source concept board. This report covers the combined native personality, duration picker, motion and copy refinements. The owner approved this local UI/snapshot/native validation batch and its repair reruns.

## Implemented design

The companion and lighthouse appear in responsive headers, with warm ivory and deep teal materials, Spruce selection states and a matching app icon. The cockpit groups the current priority separately from session and context controls, uses two columns where space permits, and retains a single column at larger text sizes. Settings, history, first-run guidance, completion sheets, popovers and nudges use the same controls and section treatment.

Quiet durations are 1, 5, 20 minutes and Custom. Custom accepts whole minutes from 1 to 1,440, with explicit Apply and Cancel controls. Compact labels retain full spoken duration labels.

Hover, press, selection, editor reveals and session changes use short, event-driven transitions. Reduce Motion disables motion; there are no repeating animations. The priority editor requests keyboard focus after its reveal finishes. Its former default-focus rule could pull focus back to Done when and has been removed.

All 527 English catalogue strings were reviewed using the owner's linked Unslop guidance; 274 were revised. Keys and ordered format arguments remain unchanged. The approved heading “A small question.” remains. See `Design/Copy.md` for voice and examples.

## Verified results

Normal comparison, with recording disabled and unchanged comparison tolerances, passed all 468 tests in 59 suites in `personality-combined-final.xcresult` (198.831 seconds). The previous full comparison also passed all 468 tests in 246.358 seconds. A final rerun after the native focus repair is recorded below.

The suite covers light/dark palettes, Increased Contrast, Reduce Motion, Reduce Transparency, large text, pseudo-localisation, responsive headers and action reachability. Intentional candidate images were exported from failed Xcode result bundles, visually reviewed, then adopted. The successful normal comparisons are the evidence; missing-baseline recording runs are not counted as passes.

Native CUA checks used an isolated preview store and a small fixture hosting the compiled shipping `AccusationPanelView`:

- Custom values 0, -1, 1441, 1.5, letters and empty input kept Apply disabled. Cancel produced no action. Seven minutes produced 420 seconds; 1,440 produced 86,400 seconds; focused Return applied one minute as 60 seconds. Invalid Return applied nothing. Boundary and invalid-Return checks also ran with Reduce Motion enabled.
- Dark Settings window chrome matched the body. The selected nudge voice had both visible emphasis and accessibility selection. Retention choices were readable and their selected state was visible.
- Cockpit and Settings scrolled and remained operable. Session controls were exercised against the fixture. Change priority focused its revealed field; typing reached that field, Return committed a disposable priority, and Command-N reopened and focused the editor.

The final Debug app build and string/forbidden-symbol checks passed. The focused non-UI copy/undo run passed 30 tests. Native control receipts are recorded in `personality-native-controls.json` in the evidence directory.

## Repairs found during validation

The Custom Apply label previously formed two buttons and now uses one explicit label stack. Popover context can scroll while decision controls remain pinned at large text sizes. Privacy snapshot fixtures are split into three sections because their unbounded pseudo-localised render exceeded the image renderer's height limit; the shipping pane remains one scrolling view. Retention buttons wrap instead of truncating. Immutable localised formats resolve once per view value, avoiding repeated catalogue lookup during layout.

Earlier repairs restored asset-catalogue image lookup, kept embedded nudge headers compact, preserved the companion at narrow/wide widths, and placed Settings introductions inside their scrolling bounds. Source-board comparisons assess the shared illustration, hierarchy and materials; the board is not a pixel-equivalent app state.

## Evidence and release boundary

Evidence directory: `/Users/bravostation/work/focus-release-evidence`. Source task: Assess project status, `01a08142-1e4c-7b10-a7e6-1526bd668ab3` (share URL unavailable). The result bundles, build/check logs, reviewed candidate contact sheets and native receipts are retained there. Committed snapshots are under `Packages/FocusUI/Tests/FocusUITests/__Snapshots__/`.

The main checkout and another agent's uncommitted settings work were left untouched. The preview used an explicit disposable store; no installed-app replacement or persistent-store recovery is claimed. A seed-launch isolation issue and Privacy's hardcoded fixture-path disclosure are tracked separately as `focus-k2in`; no destructive Privacy action was pressed.

GitHub CI is skipped to honour the owner's no-spend instruction. These local design checks do not replace the complete release gate or satisfy the required GitHub status check. Release merge remains pending those checks.

Final focus-repair comparison: **PASS**, all 468 tests in 59 suites in 185.657 seconds, `personality-combined-focus-final.xcresult`. This run compiled the final source including the native capture-focus repair; recording was disabled and tolerances were unchanged.
