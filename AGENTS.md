# Agent Instructions

## UI tests require explicit confirmation

Chris instructed on 8 September 2026: stop running UI tests and always confirm with him before running them in future. Obtain fresh explicit confirmation before starting UI tests, including FocusUI snapshots, native FocusHost UI tests, live UI test drives, full gates containing them, or CI triggers/retries that run them. General authorisation to complete work does not waive this requirement. Non-UI work may continue.

This project uses **bd** (beads) for issue tracking. Run `bd prime` for full workflow context.

> **Architecture in one line:** Issues live in a local Dolt database
> (`.beads/dolt/`); cross-machine sync uses `bd dolt push/pull` (a
> git-compatible protocol), stored under `refs/dolt/data` on your git
> remote — separate from `refs/heads/*` where your code lives.
> `.beads/issues.jsonl` is a passive export, not the wire protocol.
>
> See [SYNC_CONCEPTS.md](https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md)
> for the one-screen overview and anti-patterns (don't treat JSONL as the
> source of truth; don't `bd import` during normal operation; don't
> reach for third-party Dolt hosting before trying the default).

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work atomically
bd close <id>         # Complete work
bd dolt push          # Push beads data to remote
```

## Non-Interactive Shell Commands

**ALWAYS use non-interactive flags** with file operations to avoid hanging on confirmation prompts.

Shell commands like `cp`, `mv`, and `rm` may be aliased to include `-i` (interactive) mode on some systems, causing the agent to hang indefinitely waiting for y/n input.

**Use these forms instead:**
```bash
# Force overwrite without prompting
cp -f source dest           # NOT: cp source dest
mv -f source dest           # NOT: mv source dest
rm -f file                  # NOT: rm file

# For recursive operations
rm -rf directory            # NOT: rm -r directory
cp -rf source dest          # NOT: cp -r source dest
```

**Other commands that may prompt:**
- `scp` - use `-o BatchMode=yes` for non-interactive
- `ssh` - use `-o BatchMode=yes` to fail instead of prompting
- `apt-get` - use `-y` flag
- `brew` - use `HOMEBREW_NO_AUTO_UPDATE=1` env var

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:6cd5cc61 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->

<!-- BEGIN BEADS CODEX SETUP: generated by bd setup codex -->
## Beads Issue Tracker

Use Beads (`bd`) for durable task tracking in repositories that include it. Use the `beads` skill at `.agents/skills/beads/SKILL.md` (project install) or `~/.agents/skills/beads/SKILL.md` (global install) for Beads workflow guidance, then use the `bd` CLI for issue operations.

### Quick Reference

```bash
bd ready                # Find available work
bd show <id>            # View issue details
bd update <id> --claim  # Claim work
bd close <id>           # Complete work
bd prime                # Refresh Beads context
```

### Rules

- Use `bd` for all task tracking; do not create markdown TODO lists.
- Run `bd prime` when Beads context is missing or stale. Codex 0.129.0+ can load Beads context automatically through native hooks; use `/hooks` to inspect or toggle them.
- Keep persistent project memory in Beads via `bd remember`; do not create ad hoc memory files.

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.
<!-- END BEADS CODEX SETUP -->

## Learnings

Driver notes from the work itself, newest first. `CLAUDE.md` points here; keep the two files
mirrored for anything substantive.


### 2026-10-15 — the nudge panel lost its bottom inset to the hidden titlebar

- **A `.titled` + `.fullSizeContentView` window hands SwiftUI a top safe-area inset even when
  the titlebar is transparent, hidden and empty.** The nudge panel's `NSHostingView` reported
  `safeAreaInsets.top == 32`. The panel's height is measured off-window by `SurfaceMeasurer`,
  which never sees that inset, so the live layout squeezed content sized for the whole window
  into 32 points less. The person saw the answers sitting on the panel's bottom edge. Every
  published reading (action frames, reachability, hit tests) is relative to the content's own
  coordinate space, so none of them could see it. The fix is `.ignoresSafeArea()` on the live
  root view in `NudgePanelController.layOutContent()`.
  `NudgePanelTests.contentKeepsItsInsetFromTheWindowEdges` reads the content's frame in
  `.global` space to catch this.

### 2026-09-12 — tooltips on everything, glyph verbs, one dialog margin, and the Resume that could never clear (focus-mmty, focus-8ski, focus-udn9)

- **A restoration pause is the person's to clear, and the code said otherwise for months.**
  `SessionRestoration.reconcile` pauses a restored session with `.systemRestart` or `.relaunch`
  and documents it as "one click puts the person back where they were" — but `resumeSession()`
  sent only `resumed(cause: .user)` and `userMayResume` required `pauseCauses == [.user]`, so
  the cockpit showed "Paused because this Mac restarted" over a disabled Resume and a footnote
  promising it would clear. Nothing ever clears those two causes but the person. The rule now
  lives in `PauseReason.isClearedByThePerson` (`.user`, `.relaunch`, `.systemRestart`); the
  snapshot's `causesTheUserCannotClear` / `causesTheUserMayClear` read it, and the host sends one
  `resumed(cause:)` per person-clearable cause, so a session paused by the person *and* then
  rebooted takes one click. `.poweringOff` maps to `.systemRestart` on purpose and is exempt in
  the exhaustiveness test. `RestorationResumeTests` in FocusHost is the end-to-end witness.
- **Tooltips are catalog entries, drawn only through `View.shellHelp`** (`Design/ShellHelp.swift`).
  `check-strings.sh` bans `.help("…")`, so a tooltip is a `ShellStringKey` case plus a catalog row
  like any other sentence; 128 keys sit under the `Tooltips (focus-8ski)` MARK. The two-key form
  `shellHelp(_:disabled:when:)` shows *why* a control is off. **Put `.shellHelp` after
  `.disabled(…)`**: `.help` attaches to the view it modifies, and a tooltip inside a disabled
  view is one AppKit does not show. Verified live on this machine with `cliclick m:x,y`, a 2.5 s
  wait and `screencapture -R`: the enabled Resume glyph showed "Resume session. Picks up where it
  was paused." and the disabled *Open at login* row showed its reason sentence (evidence in
  `/Volumes/Memory/archive/focus-tooltips-evidence/`). The catalog is edited by script with
  `json.dumps(d, indent=2, ensure_ascii=False, separators=(",", " : "))` and insertion order
  kept — that reproduces the file byte for byte; `sort_keys=True` rewrites the whole file.
- **The session verbs are glyphs; the verb is the accessibility label.** `SessionControls` and
  the menu-bar popover draw `play.fill` / `pause.fill` / `cup.and.saucer.fill` /
  `arrow.triangle.branch` / `arrow.uturn.left` / `stop.fill` / `checkmark`, with
  `.accessibilityLabel(Text(ShellStrings.resource(key)))` carrying the catalog verb, so the
  registry, the shortcuts help and the label-driven tests are unchanged and the tooltip carries
  the verb *and* what it changes. The three registers (filled primary, bordered reversible,
  accent-tinted endings) are kept.
- **One dialog margin, and it does not grow with the text.** `DesignTokens.dialogInset = 24`
  and `popoverInset = 16`, reached through `.dialogInset()` / `.popoverInset()`
  (`Design/DialogInset.swift`). Before: sheets 24, General pane 12, Intervention pane 12,
  popover 10, custom-snooze 16. The first cut scaled the margin with `shellTextScale`; at
  `.accessibilityLarge` (×2) that is 48 a side on a 460-wide pane, the Privacy capability slice
  grew from 10 034 to 11 458 rows and its pseudo-localised pass crossed the ~16 000-row ceiling
  where CoreGraphics hands back an empty buffer — `PseudoLocalizationTests` reported "rendered
  no ink: 11458 and 19122 rows". A margin is a frame, not text; it stays fixed.
- **A SwiftPM store can carry a stale plan.** After adding two new files to `FocusUI`, the
  FocusHost package's first build of the dependency reported "no member 'shellHelp'" in thirty
  places and one "unable to type-check in reasonable time" while `swift build` of FocusUI alone
  was green; the second `swift build --package-path Packages/FocusHost` compiled the new files and
  passed with no source change. Rebuild once before reading a dependency's cascade as real.
- **Re-recording by export took four lane passes for 108 baselines, and the count is the
  lesson.** Pass 1 compares; export its candidates with `xcrun xcresulttool export attachments`
  and match `suggestedHumanReadableName` against `<name>.candidate_<n>_<uuid>.png` (the
  `isAssociatedWithFailure` flag is false on every attachment, so do not filter on it); copy
  them over the baselines. But a component test stops at its first mismatching *size*, so pass 1
  only yields the standard candidates; pass 2 yields the accessibilityLarge ones; pass 3 is
  green. Add one more pass for any fix made along the way. Quiet-ish machine (a Pasta CI runner
  was building beside it): 296 s, 214 s, 213 s.

### 2026-09-10 — the walkthrough and the release trains (focus-u6de, focus-h8jf)

- **A shared SwiftPM repository cache is a shared lock, and Xcode.app holds it.** Every
  `swift package resolve` and every `xcodebuild` that resolves a remote package takes
  `~/Library/Caches/org.swift.swiftpm/repositories/<pkg>.lock`. With Xcode.app open on another
  project that also depends on Sparkle, and two other sessions' `swift-package resolve` runs
  waiting on the same lock, this repository's first resolve of Sparkle hung for forty minutes
  with no child process and nothing in `-v`. Plain `git ls-remote` of the same URL answered at
  once, which is how the network was ruled out. The fix is a private cache:
  `swift package resolve --cache-path /Volumes/Memory/cache/swiftpm-cache-focus` and
  `xcodebuild … -packageCachePath /Volumes/Memory/cache/swiftpm-cache-focus`; `release-mac.yml`
  passes it. `lsof <lockfile>` names the holders; `sample` on the waiter shows nothing useful.
- **Sparkle is the one third-party package, and the gate reads it the opposite way round.**
  `check-boundaries.sh` used to prove *no* updater (no Sparkle symbol, no `SUFeedURL`); it now
  proves the updater is *opt-in*: the Release binary names `SPUStandardUpdaterController` (the
  control — a claim about a framework that is really there), the merged plist carries
  `SUEnableAutomaticChecks = false` and `SUPublicEDKey` and no `SUFeedURL`, and the self-check
  publishes `softwareUpdaterStarted = false` and `softwareUpdateChecksStored = false` on a default
  store. `FocusUpdates` is the only package allowed a remote dependency, and it must declare
  exactly `sparkle`. Adding a second remote dependency anywhere fails the gate by name.
- **R-96q gained a second allowed caller, for the rule's own reason.** The General pane's
  *Show walkthrough* button sends `.showWalkthrough`, whose `opensCockpit` is `true`, so the
  centre raises the window and buffers the command — the exact property the six silent controls
  the rule was written about lacked. `CommandRegistryTests.theWalkthroughIsAHelpCommand` pins
  `opensCockpit`; if that flips, the allowance in `check-forbidden.sh` loses its argument.
- **`-only-testing:FocusUITests/<Suite>` matched nothing for Swift Testing suites in that
  bundle under `xcodebuild test`**, while the same shape matched `FocusHostTests/FirstRunExplanationTests`.
  Not diagnosed; the walkthrough's lane-gated string assertions were checked by compiling the
  catalog with `xcrun xcstringstool compile` and reading the entries instead. Do not read an
  "Executed 0 tests" FocusUITests run as green.
- **The snapshot lane records one missing size per pass.** A component's test case stops at
  its first missing baseline, and each component has a standard and an accessibilityLarge
  picture, so twelve new components took three passes of
  `xcodebuild -scheme FocusUnitTests -only-testing:FocusUITests test`: the first wrote the
  standard sizes and failed, the second wrote the large sizes and failed, the third was green.
  Read the failure text — "no committed baseline … the candidate has been written" is progress,
  a pixel mismatch is not.
- **The walkthrough is a coach-mark tour on the real cockpit, and a step is done when the state
  says so** (focus-u6de). The sheet's Continue opens `WalkthroughPanelController`, a floating
  panel that `WalkthroughPlacement` puts beside the control the step is about and
  `WalkthroughHighlightWindow` outlines; the controls report their frames through
  `.walkthroughAnchor(_:)` into `WalkthroughAnchorRegistry`, most specific first (the capture
  field, else *Change priority*; the context pack, else the Details tab). `FocusHost.WalkthroughTour`
  takes a baseline reading on entering a step and reads completion off `PriorityHost.state`,
  `SessionHost.snapshot`, the popover's `onPopoverDidShow` and `noteSettingsRendering` — never
  off the button. The reading arrives through `PriorityHost.onStateChanged`, added because
  `onSnapshotInvalidated` fires only for the four snapshot-key facts and a definition of done
  or a timebox changes neither. *Do it for me* performs the same host call the control would.
- **Three things a floating tour panel must do, each measured on this machine.** (1) Only move
  when the step, the target or the done state changed — `refreshCockpit()` runs every five
  seconds and a panel re-placed on each tick snapped back under the person's drag and put a
  click meant for *Next* into Safari. (2) `hidesOnDeactivate = true` on the panel and the ring:
  with it `false`, a Safari click left the Spruce ring drawn over Safari's page where the
  timebox had been. Same-application windows (Settings, the popover) do not deactivate, so the
  panel stays through those steps. (3) Re-place on `NSWindow.didResizeNotification`:
  `NSHostingView.fittingSize` read in `present` is the previous step's, the content grows when
  the done sentence appears, and `setContentSize` keeps the top-left, which walked the footer
  under the Dock.
- **Driving the live app from a shell.** `osascript` menu clicks work (`click menu item "Show
  walkthrough" of menu "Help"`); `System Events` button clicks on SwiftUI sheets and `set
  position of window 1` do not (the latter moved the tour panel, which was `window 1`). Use
  `cliclick c:x,y` at screen points scaled from a `screencapture` — 1920 wide here — and read
  the picture back before the next click; a floating overlay from another application can sit
  over the button you meant.

### 2026-09-09 — merging the companion identity into the settings branch (focus-oqsx)

- **A size-derived test fixture rots silently when the surface it measures changes shape.**
  `NudgeHostDisplayChangeTests.displayTooSmall` built "a display too small" by taking one panel
  margin off the panel's measured height. That was a stranded display when an overflowing
  surface scrolled whole; under focus-din's three-way overflow the middle answer keeps the
  actions in the viewport, so the identity round's taller context moved the boundary and the
  suite began asserting a withdrawal that correctly no longer happens. Derive such a fixture
  from the production arithmetic — `NudgePanelController.overflowIfPlaced(on:)` — rather than
  from a number that was once one margin.
- **When a merge brings two spellings of one product decision, put it in the file the digest
  covers.** The snooze spans arrived spelled in the panel and spelled in the policy; the policy
  wins, because that file is where a reader looks for a threshold and where `PolicyTuning`
  offers it as a dial.
- **A self-hosted macOS runner installed as a service cannot see the screen.** `svc.sh install`
  writes `SessionCreate` into the LaunchAgent, which puts every job in its own security session
  with no window server: `CGWindowListCopyWindowInfo` answers zero rows where an ordinary shell
  in the desktop session answers dozens. Five self-check assertions depend on real windows —
  the grant-free window list, the authorisation-surface scan and its export, and the sensing
  cascade — so the gate cannot pass as a service. Removing that one key and reloading the agent
  fixes it, at the cost of CI jobs sharing the logged-in desktop; Chris approved that on
  10 September 2026, and the original plist is backed up at
  `/Volumes/Memory/archive/focus-runner-plist.backup`. Reloading needs `svc.sh stop`/`start`,
  not `launchctl bootstrap`, and the server holds the old session for a minute or two afterwards
  — "a session for this runner already exists" is that, and it clears on its own.
- **The snapshot lane needs gigabytes of scratch and fails quietly without them.** Every render
  is written to `$TMPDIR/focus-snapshots/<checkout path>` as well as compared, so one pass leaves
  around a gigabyte per checkout. On a full disk the writes fail with `NSCocoaErrorDomain
  Code=640` and the run reports them as test issues — 99 of them in one pass here — which reads
  like a hundred broken pictures rather than a full volume. Run `~/bin/disk-cleanup.sh` before a
  recording pass, and check `df -h /` when a lane fails in a way that makes no sense.
- **A red suite after a merge is not automatically a regression.** Prove which side moved
  before changing either: this one passed at the pre-merge commit, reproduced alone, and the
  other branch had touched neither file — the shape of the surface had changed, not its
  behaviour.

### 2026-09-09 — settings, dials and the conditional grant doctrine (focus-exdi)

- **A `Toggle`, a `Picker` and a columns-style `Form` all rasterise wrong.** Under
  `ImageRenderer` a switch draws SwiftUI's yellow "unrenderable view" placeholder, so a new
  switch on a snapshot-covered pane turns every baseline into yellow bars; and a columns `Form`
  at a committed width pushes its label gutter off the left edge. Draw a switch as a bordered
  button carrying its own glyph, and a settings pane as a column of sections.
- **Adding a case to a settings action enum touches six places**, and the compiler finds only
  four: the pane's `verb`/`vocabulary`/`allDeclared`, `AppComposition.perform`,
  `DataPortability.performPortability`'s exhaustive switch, the two total switches in
  `InterventionSettingsTests`, `RetentionControlTests`' vocabulary list, **and**
  `scripts/self-check.sh`'s `privacyActionsDeclared` — that last one only fails at gate time.
- **A new stored preference costs a schema version**, and the count is pinned in four places:
  `StoreTests` (entities, twice), `MigrationV<n>Tests`, `StoreExportTests`' manifest version,
  and `Config/export-field-classification.txt`'s `SCHEMA`/`ENTITIES` header plus a row per
  column. Prefer a new entity in a new version that re-declares nothing.
- **The zero-grant doctrine is now conditional** (owner's ruling): the app may ask for
  Accessibility and Screen Recording, and only where the person switched that ask on. The ban
  was replaced rather than lifted — use selectors still banned, request selectors confined to
  one registered file, runtime reading unchanged. See README under `grants`, and never add a
  second request site: two lints fail on it, from opposite directions.
- **A lint that greps source must strip comments first.** Three files explain in prose why the
  app does not call the request APIs; a confinement check that could not tell prose from code
  made the honest explanation the violation.

### 2026-09-08 — e11c cockpit hierarchy and colour (focus-6uya)

- **Re-recording snapshot baselines.** `FOCUS_SNAPSHOT_RECORD=1 swift test` is a dead route on
  this rig: every snapshot suite is *skipped* under `swift test` (the catalogs are not compiled
  there), so the README's "swift test only" recording flag records nothing. The route that
  works is the gate's: delete the baselines you mean to re-record, run the lane under
  `xcodebuild -scheme FocusUnitTests -only-testing:FocusUITests test`, and a missing baseline
  is written and *failed*; run again to confirm green. Baselines recorded under SwiftPM carry
  SF Symbol fallback glyphs; the xcodebuild lane renders the drawn marks, so expect accusation,
  popover and verdict baselines to change the first time they are re-recorded this way.
- **Fewer passes: take candidates from the result bundle.** A test that loops over variants
  stops at its first missing baseline, so deleting many at once costs several passes. Instead
  run one compare pass against the old baselines and export the candidates:
  `xcrun xcresulttool export attachments --path <RB> --output-path <dir>`; `manifest.json`
  maps `<name>.candidate…` to an exported file. Attachments survive only for failing tests.
  The `$TMPDIR/focus-snapshots` directory is not a source for this: after a run it held files
  byte-identical to the committed baselines, not the candidates.
- **What the lane cannot see.** The comparator tolerates ±8 per channel and 0.2% of pixels
  beyond that. A ground tint that moves a colour by ≤8 counts is invisible to it — an 8%
  Spruce wash over Inlay was — and on accessibilityLarge pictures a heading colour change can
  sit under the 0.2%. A deliberate colour change has to clear the tolerance or it is
  unwitnessed; `DesignTokens.wellWashOpacity` is 12% for that reason.
- **The ink heuristic reads geometry.** `PNGCompare.inkPixels` counts every pixel off the
  top-left one, so a filled well is solid ink and text drawn on it adds nothing. A composite
  can measure *fewer* ink pixels while visibly drawing more text. Measure parts, not
  composites (`PriorityComponent.measuresPseudoLocalisedInk`).
- **Memory.** The FocusUITests lane pins about 2.7 GB. With another agent's Xcode builds on
  the machine, a backgrounded run is killed by the harness's low-memory guard; a foreground
  run rolls to the background after 600 s and survives. Serialise with other agents, or wait
  for a quiet machine (no other `xcodebuild`/`swift-frontend` processes, ≥45% free) before
  starting the lane. Quiet, the lane takes ~366 s; under contention it measured 440 s, over
  the 420 s budget in `Config/performance-budgets.txt`.
- **Type roles.** A `FontRole` that forces a weight must be named in
  `TypeHierarchyTests.onlyTheHeroAndTheSectionHeadingForceAWeight`; a role drawn in a
  palette hue with a High Contrast pair needs no Increase Contrast exemption.
- **A plain Debug build leaves `FocusGitHash` empty** — only the gate passes
  `FOCUS_GIT_HASH`. Say so when reporting a locally built app's version.
- **Capturing the cockpit window.** `CGWindowListCopyWindowInfo` lists the app's windows by
  *owner PID* (the owner name is "Focus Sentinel", not the process name `FocusSentinel`), then
  `screencapture -x -o -l <windowNumber>` captures it; `osascript … activate` first.
- **Design rulings overridden by the owner.** The direction's "one hairline, never boxes" and
  "at rest the app owns no hue" were both overruled for the cockpit on the owner's reading of
  the shipped window (headings too small, no visible organisation, no colour). The cockpit is
  summoned, so it may wear the question hue; uninvited surfaces keep the original rules.
