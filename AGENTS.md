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
