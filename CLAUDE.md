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

