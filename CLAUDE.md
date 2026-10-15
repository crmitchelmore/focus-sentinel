# Project Instructions for AI Agents

## UI tests require explicit confirmation

Chris instructed on 8 September 2026: stop running UI tests and always confirm with him before running them in future. Obtain fresh explicit confirmation before starting UI tests, including FocusUI snapshots, native FocusHost UI tests, live UI test drives, full gates containing them, or CI triggers/retries that run them. General authorisation to complete work does not waive this requirement. Non-UI work may continue.

This file provides instructions and context for AI coding agents working on this project.

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


## Build & Test

_Add your build and test commands here_

```bash
# Example:
# npm install
# npm test
```

## Architecture Overview

_Add a brief overview of your project architecture_

## Conventions & Patterns

_Add your project-specific conventions here_

## Learnings

Driver learnings live in `AGENTS.md` under **Learnings** — read them before re-recording
snapshot baselines, running the FocusUITests lane beside another agent's builds, or adding a
type role or a palette hue. `AGENTS.md` and `CLAUDE.md` are independent files; mirror anything
substantive across both.

### 2026-10-15 — the owner's ruling: read the selected item through Accessibility, on device (issue #24)

- **Accuracy needs more than a bundle identifier, so the Accessibility grant is now spent.** In
  a mixed-use application (GitHub Copilot, a terminal, an editor, a browser) the bundle
  identifier is the same for the task and for the distraction, so the question cannot say what
  the person is actually doing. Chris ruled on 15 October 2026 that reading the selected item —
  the focused window's title, the chat session, the project folder — is essential and is to be
  built now. This replaces "nothing reads what the grant unlocks" from the 2026-09-09 ruling; it
  does not replace "the app asks for nothing unless the person switched that ask on".
- **The privacy shape is fixed:** opt-in through the existing Settings ▸ Privacy switch; on
  device only (no network, no export of raw titles); read at nudge time from the frontmost
  application only; reduced to a short normalised subject before storage, never persisting the
  raw title; the AX use selectors confined to one registered reader file and proven from both
  sides, as `SystemGrantRequester.swift` is for the request selectors. README ▸ `grants` carries
  the ruling. Until the work lands, a lint that still bans the use selectors is describing the
  shipped build, not a mistake.
- **Landed:** `FocusCore/Sensing/SelectedItem.swift` reduces a title to a `<bundle>::<label>`
  `titleToken` subject (≤48 characters, raw title dropped); `FocusHost/SelectedItemReader.swift`
  is the one AX use file (`Config/grant-use-sites.txt`, `check-grants.sh`, R-33b). A `titleToken`
  row in item form is live; a legacy single-word row stays retired (`PriorityRuleValue.isRetired`).
  The store export writes every item label as `selected-item`. A bare `RelevanceHost` in a test
  has no active task until `host.activeCommitment` is set, so its snapshot carries no task rules.
- **Every app, not an allowlist (owner's follow-up).** In practice every app is mixed-use, so
  the reader takes any frontmost app `SensitivityGate` cleared. A live AX diagnostic on the
  owner's Mac decided the shape: the Copilot app's window title is just "GitHub Copilot" and its
  web sidebar marks no row selected, but the first `AXHeading` under the main landmark reads
  "Session: …"; native apps (Mail, Finder, Outlook) report `AXSelectedRows`. So: title first,
  then a walk of that one window for a selected row or else the first main-region heading **in
  document order** — a breadth-first walk alone picks the shallowest heading, which is the
  wrong one, so `SelectedItemSearch` carries child-index paths and compares them. One app's full
  tree took 10.6 s to walk; the walk is capped at 400 elements, depth 14 and 150 ms.
- **AX attribute names are `String` constants, bridged `as CFString` at the call.** A
  `static let x: CFString` fails Swift 6's Sendable check on a global.
- **This shell is AX-trusted.** A unit test that drives the real reader with the opt-in on reads
  real windows on the machine running it. Test the reader's logic through `SelectedItemSearch`
  over fake nodes, and the host through a fake `SelectedItemReading`.
- **Grant state needs an observable home.** `AppComposition` is a plain class, so a stored
  `grantOptIns` changed by the Privacy switch redrew nothing. `GrantAccessWatch` (`@Observable`)
  holds the switches and what macOS says, is re-read when the app becomes active and polled
  for two minutes after the person is sent to System Settings — the pattern Pasta and Just
  Speak to It use — and the pane's *Open System Settings* takes an injectable opener so the
  unit lane never opens a window.

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

