# Agent Instructions

## UI tests require explicit confirmation

Chris instructed on 8 September 2026: stop running UI tests and always confirm with him before running them in future. Obtain fresh explicit confirmation before starting UI tests, including FocusUI snapshots, native FocusHost UI tests, live UI test drives, full gates containing them, or CI triggers/retries that run them. General authorisation to complete work does not waive this requirement. Non-UI work may continue.

## Ship straight to production (owner instruction, 15 October 2026)

Chris: "just ship direct to prod for now, we're still in early development so need to iterate fast without going through multiple stages." Until he says otherwise, finished work goes all the way out in one pass, with no pause for review between stages:

1. Merge to `main` (a direct push or a self-merged squash PR; do not wait on review).
2. Dispatch **Alpha release** for that `main` SHA (`gh workflow run alpha-release.yml -f source=<sha>`). `Config/ReleasePipeline.json` stays `enabled: false`, so this is the owner-dispatch path.
3. Dispatch **Prepare Stable** with the resulting `alpha-build-N` and the next version: the next patch above the latest `v*` tag, or `version` from `ReleasePipeline.json` if there is none.
4. Dispatch **Publish Stable** with that `stable-candidate-N` and the manifest SHA-256 that Prepare Stable prints.

The UI-test rule above still holds. Shipping runs no UI tests, and Chris validates the UI himself.

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


### 2026-10-16 — Liquid Glass on the summoned surfaces

- **Glass is a token decision, not a call-site one.** `DesignTokens.drawsGlass(for:)`
  (`Design/LiquidGlass.swift`) is true only where `material(for:provenance: .summoned)` is
  `.material` and Increase Contrast is off; every helper (`glassBackdrop`, `softSlab`,
  `softField`, `CompanionSeparator`, `CompanionButtonStyle`, `CompanionSurface`, `shellSurface`'s
  `.material` case) reads it and falls back to the old opaque Inlay/Bench fills and hairlines.
- **Glass on controls and navigation only, never on content** (Apple's Tahoe guidance, and the
  cleanliness pass the same day). Cards are borderless soft Bench panes with a Light-only lift
  and a faint Spruce wash for the accented one; fields and the popover status row are soft
  neutral fills. Glass cards under glass buttons was glass on glass, and read muddy.
- **Whitespace separates cards; `CompanionSeparator` separates inside one.** No `Divider()`
  between two cards; inside a card a faint Mist rule, the system divider where glass is off.
- **Uninvited surfaces stay opaque.** The nudge panels never draw glass; `material(for:provenance:)`
  is unchanged and its tests still pin it.
- **One `GlassEffectContainer` only, in the cockpit tab bar**, so the selected-tab lozenge morphs
  between tabs. A root container would merge glass buttons into the glass cards under them.
- **Every snapshot baseline moved.** Re-record through the UI lane only with Chris's confirmation;
  check first whether `ImageRenderer` rasterises `glassEffect` at all.

### 2026-10-16 — time from other sources, through the bridge (issue #31)

- **EventKit is not every calendar.** An Exchange account behind Conditional Access never reaches
  macOS's calendar, and Graph and Outlook's own files are closed to us too, so the app now takes
  blocked time from any provider. `focus-bridge`'s `focus_set_time_blocks` /
  `focus_add_time_block` / `focus_list_time_blocks` / `focus_clear_time_blocks` (and
  `focus-bridge time-blocks …`) write `TimeBlocks/<source>.json` beside the store.
- **A file drop, not a `focus://` URL**, because blocks must persist and arrive unattended; no
  confirmation, because blocked time only makes the app do less. The contract is
  `FocusCore/Time/ExternalTimeBlocks.swift`; the app decodes through a narrow struct that reads
  kind, start and end only, so titles and details never enter the store or the export.
- **`CalendarHost` merges, it does not cache, the external source.** `agenda(at:)` asks
  `ExternalTimeBlockReader` every call; the reader re-reads only when the directory's
  (name, size, modification date) signature moves. EventKit blocks keep their 60 s cache.
  `busy`/`away`/`tentative` hold the question; `focus`/`free` do not.
- **Composed only for the person's own store, never in a lane or a self-check**, the same rule as
  the remote judge. *Delete Everything* removes the directory.
- **`MCPServer` is `@MainActor`**, so a static helper on it cannot be called from `main.swift`'s
  nonisolated command functions; shared parsing lives on `TimeBlockStore`.
- **`#expect(a.map(\.x) == [.p, .q].sorted { … })` timed out the type checker.** Bind the mapped
  array to a typed `let` first.
- **`check-grants`, `check-focus-steal` and `check-published-keys` need build artefacts** (a
  self-check JSON, an app, `FOCUS_KEYS_READ`); run alone they fail on usage, not on source.

### 2026-10-16 — today's busy time as a strip in the cockpit (focus-ext)

- **`CalendarAgenda.day(at:calendar:)` is the model; `CalendarDayStrip` only draws it.** Busy
  blocks (calendar and every outside source, already merged) are clipped to the local day; the
  span is 08:00–18:00 widened to whole hours for an early or late block and for now. It is an
  enum (`CalendarDay`) so the shell's totality walk stops at one binding line,
  `state.priority.calendarDay`, as `CalendarOutlook` does. The strip draws nothing for `.unread`
  or a day with no busy time, and lives in `TimeboxControl`, so it shows only with a priority.
- **The read window had to grow.** `CalendarHost.agenda` read now ± 12 h, which in the morning
  missed the evening; it now reads the union with the local day, using `calendarHost.calendar`
  (set from the composition's calendar).
- **A clock time drawn in a snapshot must come from the environment.** `date.formatted(...)`
  uses the process's zone and locale, so a baseline recorded on bravo would differ elsewhere.
  The strip formats with `@Environment(\.locale)`/`(\.timeZone)`; the fixture injects UTC and
  en_GB. Each new `Text(verbatim:)` also needs a row in `Config/verbatim-sites.txt`.
- **The lint scripts are zsh** (`${0:A:h}`); `bash scripts/check-*.sh` fails on line one with
  "A: unbound variable". Run them with `zsh`.

### 2026-10-16 — the remote judge gets a switch, and stops caching a judge it could not reach

- **Composed is not on.** The judge is composed for the person's own store whenever the
  configuration parses (an absent endpoint now takes the measured default), and gated at call
  time by `RemoteJudgeSwitch`, mirrored for SwiftUI in `GrantAccessWatch.remoteJudgeOn`, set by
  `PrivacySettingsAction.setRemoteJudge` and stored as `FocusRemoteJudgeEnabled` in defaults —
  not the store, so no schema version. Switched off or cooling down, `judge` declines before it
  asks the context source, so nothing is read.
- **`.notAvailable` is the transient decline and is never cached.** `FocusModelRung.record()`
  drops it and does not count it as a generation; `.refused` stays cached for the key. An
  unreachable judge (no token, network error, 401/403/408/429/5xx) answers `.notAvailable` and
  starts a one-minute `RemoteJudgeBackoff`, a clock read rather than a timer.
- **A Privacy action costs four pins:** the enum's `verb`/`allDeclared`/`vocabulary`,
  `DataPortability`'s early-return list, `RetentionControlTests` (list and count) and
  `self-check.sh`'s `privacyActionsDeclared`. The `.grantOptIns` receipt carries
  ` remoteJudge=on` on both sides — the pane and `ShellConnectionFactory`'s `expect`.
- **The catalog cannot be round-tripped through `json.dumps` any more**: some entries are
  written inline (`{ "en" : { … } }`), so a dump rewrites the file. Insert or replace text.
- **Two FocusHost tests only failed on a runner.** `startSession` calls
  `reconcileSensitivePause()`, which reads the real frontmost app; on bravo that is unbundled
  or sensitive, so the session started paused. Pin `sensingHost.frontmostPayload`. An in-memory
  root's `activeStoreURL` is nil; compare against it, not `FocusStore.applicationSupportURL`.
- **Never run UI tests on Chris's Mac.** FocusHost's whole `swift test` presents windows; run a
  pure suite with `--filter`, and run the rest on the bravo runner through Local CI.

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

### 2026-10-02 — dropped apps, paths pasted as keywords, and site entry hidden (focus-6ji4)

- **What the app can observe is one named fact.** `ShippingObservation.readsBrowserSite`
  (`FocusCore/Context/ShippingObservation.swift`) is `false` because `RelevanceHost` judges
  with `ClassificationInput(bundleIdentifier:)` alone. `PriorityRuleScope.isObserved` and
  `ContextItemKind.isObserved` read it; the rules pane's `authorableScopes`, its inert rows, the
  site chip's caption and `ContextItemDraft.site(from:)` read those. This is *not* a retirement:
  the engine still reads stored `.domain` rows, and the day an origin producer ships is one line.
  Chris chose hiding over a footnote (2026-10-02).
- **Drop, paste and ⌘O decode in `FocusCore`, on `ContextItemDraft`.** `attachment(url:)` turns
  an `.app` into an app item by `Bundle(url:)?.bundleIdentifier`; `pasted(_:)` refuses any text
  shaped like a location (path, `file:`/hierarchical URL, `mailto:`-family, scheme-less
  host/path) as a keyword. `FocusCore` may not import `UniformTypeIdentifiers`
  (`check-boundaries.sh`), so the app test is `URLResourceValues.isApplication`.
- **`swift test --package-path Packages/FocusUI --filter <PureSuite>` runs no snapshot case**
  ("Executed 0 tests" on the XCTest side). `StringCatalogTests` is lane-gated and *skips* under
  `swift test`; its duplicate-value pin was checked by reading the catalog instead.

### 2026-09-12 — the calendar, the third opt-in grant and the first one spent (calendar-aware focus blocks)

- **A third grant is a dozen pins, and most of them only fail at gate time.** Adding
  `Capability.calendarEvents` / `GrantOptIn.calendarEvents` touched: `self-check.sh`'s
  `EXPECTED_CAPABILITIES`, `CAPABILITY_RULE_CONSTANTS` and the "all thirteen" sentence;
  `check-grants.sh`'s `CAPABILITIES_CLAIMED` and the `available_rows` allow-list; the calendar row
  of `Config/tcc-families.txt` (its banned column may not name the confined selector — a selector
  cannot be both); `Config/grant-request-sites.txt`; R-33's pattern in `check-forbidden.sh`;
  `ALLOWED_FRAMEWORKS[FocusHost]` in `check-boundaries.sh`; the committed entitlement sets in
  `entitlement-check.sh`; `BootIdentityTests` and the capability-matrix snapshot fixtures. The
  Swift `EKEventStore.authorizationStatus(for:)` does emit `authorizationStatusForEntityType` in the
  Release Mach-O, so it is a sound grant-free control.
- **The hardened runtime denies EventKit without `com.apple.security.personal-information.calendars`.**
  The local project builds with `ENABLE_HARDENED_RUNTIME = NO`, so a Debug run would prompt and read
  happily while every notarised train failed silently. The entitlement lives in
  `App/FocusSentinel.entitlements`, which `sign-and-notarise.sh` uses.
- **A new suppression gate is appended, never inserted.** Gate 13 `calendarMeeting` keeps 1–12's
  numbers, which the self-check's `gatesPassingOverTheGlyph` list and every decision record cite.
- **Refuse at the host, not only at the control.** `PriorityHost.setTimebox` refuses a colliding
  timebox with no write and refreshes the cockpit; the control disabling a preset is the courtesy,
  not the rule. A nil timebox (clearing) is never refused.
- **R-26 trips on `Packages/FocusHost/.build/checkouts/Sparkle` after a plain `swift build`/`swift
  test` of FocusHost**: `check()` does not exclude `.build`. Delete that directory before reading
  R-26 as real.
- **`-packageCachePath` to a path that does not exist fails as "Missing package product" for every
  local package**, not as a missing directory. `/Volumes/Memory` is not mounted on every machine
  that builds this repository; check it before borrowing the flag from the notes above.
- **Several FocusHost suites draw real windows** (ReduceMotionWireTests, NudgeHostDisplayChangeTests,
  ReleaseReviewRegressionTests, NudgeFloorTests, KeyboardAnswerTests, UndoResponderChainTests,
  NudgeDayShapeTests). Under the UI-test confirmation rule they were skipped with `--skip`; the
  Privacy pane and capability-matrix baselines still need re-recording through the UI lane.

### 2026-09-13 — the opt-in remote judge (Decision-1)

- **The on-device model failed for lack of evidence, not lack of size.** Token-only input
  (bundle id plus priority tokens) failed the 45-cell corpus on every model tried, Decision-1
  and fifteen Foundry deployments included. Given the window's title, web address, file and
  Accessibility text (`Tools/ContextSpike`, "full"), `gpt-5.6-luna` and Microsoft's
  Decision-1 both rescued 15/15 holds with 0 seductions. Luna holds that from threshold 0.5 to
  0.98; Decision-1 only at 0.5–0.8 (0.6 at "meta"), but it answers in ~0.2 s against ~0.9 s and
  costs ~$46 per 1,000 users a month against ~$179. Decision-1 shipped, at 0.6.
- **Where each piece had to go, and why.** The window read lives in `SelectedItemReader.swift`
  because `Config/grant-use-sites.txt` allows exactly one Accessibility reader file and three
  selectors; it returns a closure so the bounded walk (4,000 elements, 1.5 s) runs off the main
  actor after the main-actor checks. The network call lives in
  `RemoteJudge/DecisionOneJudge.swift`, the one path `check-boundaries.sh` exempts and which
  fails the gate if it disappears. `R-97` reads any `fetch()` call as an uncounted SwiftData
  fetch, so a helper named `fetch` fails `check-forbidden.sh` — it is `askTheCLI()`.
- **It is never composed in a lane.** `AppComposition` builds it only for the
  `.applicationSupport` store and without `--focus-self-check`, so unit tests and self-checks
  keep the on-device rung, `rungIsComposed == composesTheRung == false` and zero sockets.
  `RelevanceHost(releasesModelRung:)` is the switch; its default is still
  `ModelTierRelease.composesTheRung`.
- **The rung caches by priority revision and selected item.** `RuleCascade.modelAnswer` now
  appends `selectedItem.subject` to the evidence key, so two pages of one browser are judged
  apart. A transient failure is cached as `.refused` for that key for the session.
- **Package `.build` directories trip the source lints.** `check-forbidden.sh` greps the tree,
  so a `swift build` of FocusHost leaves `Packages/FocusHost/.build/checkouts/Sparkle` for R-26
  to find, and a spike's `Tools/*/.build` binaries carry `kCGWindowName` for SC-1. Delete them
  before reading those failures as real.

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
  field, else *Change priority*; the context pack, else *Configure context…* — the Details tab until focus-g9iw). `FocusHost.WalkthroughTour`
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
