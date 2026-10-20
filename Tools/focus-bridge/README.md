# focus-bridge

A command-line tool and stdio MCP server that let scripts and agents read Focus Sentinel's data,
propose a priority and propose context (apps, sites and keywords) for it, tell it about time
that is already spoken for, and mirror the person's to-do list from GitHub. The app's UI is not
driven.

It is a tool, not part of the app: nothing in `FocusSentinel.xcodeproj` links it, so it is outside
the app's dependency graph, `check-boundaries.sh` and `check-forbidden.sh` (the same reason as
`Tools/windowid`).

## Safety properties

- **The network is here, not in the app, and only for task sources.** MCP runs over stdio and no
  socket is listened on. The bridge is the app's integration host: when the person has added a
  task source it calls `api.github.com` over HTTPS to read and change that source, and the app
  (which stays network-free) runs `focus-bridge tasks sync` as a subprocess and reads the files it
  writes. With no task source configured the bridge makes no connection. Tokens come from `gh`
  and are never written or logged.
- **The live store is never opened.** Each call takes a private copy of the store with SQLite's
  online backup API, through a read-only connection. The copy is opened with `FocusStore.makeContainer`,
  which is the app's own route, migration included. The copy is in a `0700` temporary directory
  and is deleted before the call returns. Only SQLite's `-shm` index on the live store changes,
  as it does for any reader. A test checks that the database and the WAL stay byte-identical.
- **Proposals need the person.** `propose` and `focus_propose_priority` open the same
  `focus://start?task=…&doneWhen=…&context=…` URL as the existing handoff. `add-context` and
  `focus_add_context` open `focus://context?add=…`. `set-priorities` and `focus_set_priorities`
  open `focus://priorities?primary=…&secondary1=…&secondary2=…`. Before anything is opened, the app's own
  `HandoffRequest.parse` checks the URL, and an item the app would leave out is an error. Focus
  Sentinel shows its confirmation sheet and changes nothing until the person presses **Replace**
  (a new priority), **Add** (context for the current one) or **Set Priorities** (the standing
  shortlist).
- **No files from scripts.** Context items are `app:<bundle id>`, `domain:<host>` or
  `keyword:<text>`. A file path from a script is not a file the person chose, so `file:` is refused.
- **Blocked time needs no confirmation, because it only makes the app do less.** Time blocks are
  written to `TimeBlocks/<source>.json` beside the store (`0700` directory, `0600` file, atomic
  write), never into the store. The app reads only each block's kind, start and end.
- **Summaries leave out the activity log.** `status` and `sessions` give the priority, the session
  and the minutes. Only `export` writes the full `focus-sentinel.data` document, which includes
  activity events, and it writes them to a file the caller names.

## Install

```sh
Tools/focus-bridge/install.sh            # → ~/.local/bin/focus-bridge
```

## Use

```sh
focus-bridge status                      # current priority, running session, today's minutes
focus-bridge sessions --since 2026-10-13 [--issue 8] [--limit 5]
focus-bridge export --out ~/focus.json   # same document as File ▸ Export My Data…
focus-bridge propose --task "#8 Review Sodexo material" --done-when "Notes written" \
  --context app:com.microsoft.Outlook --context domain:dev.azure.com --context keyword:sodexo [--dry-run]
focus-bridge add-context --item app:com.microsoft.VSCode --item keyword:rcg [--dry-run]
focus-bridge set-priorities \
  --slot "#9 Qualify Boulanger" --done-when "Go/no-go agreed" --context keyword:boulanger \
  --slot "#62 Fellowship dogfooding" --slot "#77 Links pages loop" [--dry-run]
focus-bridge time-blocks add --source outlook --kind busy --start 2026-10-16T14:00 --minutes 30 \
  [--end …] [--id …] [--title "Standup"] [--detail …]
focus-bridge time-blocks set --source outlook [--file blocks.json]   # replaces the source; JSON on stdin otherwise
focus-bridge time-blocks list [--source outlook]
focus-bridge time-blocks clear --source outlook | --all
focus-bridge tasks add-source --name work-os --provider github-issues \
  --repository cmitchelmore_microsoft/work-os --account cmitchelmore_microsoft [--tag cat:hve]... [--default]
focus-bridge tasks sync [--source work-os] [--wait] [--quiet]
focus-bridge tasks list [--tag cat:hve]... [--source work-os] [--include-done] [--pinned]
focus-bridge tasks create --title "Book the train" [--source work-os] [--tag cat:travel]... [--pin]
focus-bridge tasks complete work-os/42 | reopen work-os/42
focus-bridge tasks pin work-os/42 [--priority UUID] | unpin work-os/42
focus-bridge tasks sources | remove-source --name work-os
focus-bridge mcp                         # MCP server on stdio
```

Each `--slot` starts a standing priority (the first is the main one, at most three) and the
`--done-when` and `--context` options after it belong to it, up to 8 context items each.

`FOCUS_STORE=/path/to/FocusSentinel.store` reads a different store, such as a fixture or the
Alpha train's store. Time blocks go beside that store, or to `FOCUS_TIME_BLOCKS=/path/to/dir`;
the task mirror goes beside it too, or to `FOCUS_TASK_MIRROR=/path/to/dir`.

### Time blocks

A provider — a calendar it can read, a rota, a script — owns one source (`a–z`, `0–9`, `.`, `_`,
`-`, up to 64 characters). `set` replaces everything that source said; `add` adds one block, or
replaces the one with the same `id`. Blocks that have ended are dropped on every write; a source
holds at most 500 blocks, each at most 31 days long.

| Kind | The app |
|---|---|
| `busy`, `away`, `tentative` | treats it as a meeting: no timebox starts in or runs into it, questions wait (gate 13), the cockpit names the next one |
| `focus`, `free` | records it but holds nothing |

A block needs `kind` and either `end` or `duration_minutes`; `start` defaults to now. Times are
ISO 8601 (`2026-10-16T14:00:00Z`, `2026-10-16T14:00:00+01:00`) or local (`2026-10-16T14:00`).
`title` and `detail` are for the provider's own records; the app does not read them.

### Tasks

The bridge mirrors tasks from outside to-do systems into `TaskMirror/` beside the store (or
`FOCUS_TASK_MIRROR`), through the contract in `FocusCore/Tasks/TaskMirror.swift`:

| File | Written by |
|---|---|
| `config.json` | `add-source` / `remove-source` (`sources`, `pollSeconds`, `createSource`) |
| `sources/<source>.json` | `tasks sync` only: `syncedAt`, `lastError`, `tasks` |
| `local.json` | the local list (source `local`, reserved) |
| `pins.json` | `pin` / `unpin`: task key → priority UUID |
| `outbox/<uuid>.json` | queued complete, reopen and create actions, sent on the next sync |
| `.sync.lock` | `flock` held by a running sync |

A task's key is `<source>/<id>`: `work-os/42`, `board/PVTI_…`, `local/<uuid>`.

**Providers.** Each source names a provider; a new to-do system is a `TaskProvider`
(`fetch`, `complete`, `reopen`, `create`) registered under its provider string in
`TaskProviderRegistry`.

| Provider | Settings | Mirrors | Complete / reopen | Create |
|---|---|---|---|---|
| `github-issues` | `repository` (`owner/name`), `account`? | open issues, and issues closed in the last 3 days; pull requests skipped. Tags are labels | closes the issue (`state_reason: completed`) / reopens it | a new issue with the tags as labels |
| `github-project` | `owner`, `number`, `account`?, `doneStatus`? (`Done`), `reopenStatus`?, `statusField`? (`Status`) | a Projects v2 board's issues and drafts (archived items and pull requests skipped); done when Status is `doneStatus` or the issue is closed | sets Status to `doneStatus` / to `reopenStatus`, else `Todo`, else the first other option | a draft issue on the board |

A source's `tags` keep only tasks carrying any of them (case-insensitive). A project user or
organisation is found either way.

**Auth.** A source with an `account` runs `gh auth token --user <account>`; without one,
`FOCUS_GITHUB_TOKEN` if it is set, else `gh auth token`. `GH_TOKEN` and `GITHUB_TOKEN` are removed
from `gh`'s environment so the stored login, not an inherited token, answers. `gh` is looked for
on `PATH`, `/opt/homebrew/bin` and `/usr/local/bin`. A project needs the `read:project` scope
(`project` to change it): `gh auth refresh -s project --user <account>`.

**Sync.** `tasks sync` takes the lock (or prints `{"alreadyRunning": true, …}` and exits 0 at once
unless `--wait`), sends the outbox in order, fetches every enabled source (or `--source`), and
prunes local tasks done more than a week ago. A queued action is dropped when the source refuses
it for good (HTTP 404/410/422, a task that no longer exists) or when it is more than a week old,
and kept otherwise. A source that cannot be read keeps its last tasks and gets `lastError`, such
as `GitHub said 401: Bad credentials` or `could not get a token for account X: …`. It prints:

```json
{"alreadyRunning": false, "ok": true, "syncedAt": "…",
 "sources": [{"name": "work-os", "provider": "github-issues", "tasks": 42, "error": null}],
 "actions": [{"id": "…", "kind": "complete", "source": "work-os", "key": "work-os/42", "outcome": "applied"}]}
```

`outcome` is `applied`, `kept`, `dropped` or `skipped` (another source's action during
`--source`). `ok` is false when any source or action failed.

**Changes are immediate.** `complete`, `reopen` and `create` on a GitHub source queue the action
and sync that source at once, so the issue closes before the command returns; if GitHub cannot be
reached the action stays queued, and the reply says `pending`. `create` goes to `--source`, else
the source added with `--default`, else the local list. `--pin` pins the new task to the current
priority (a queued create carries the pin and it moves to the real key when GitHub answers).

**Exit codes.** 0 when the command ran — including a sync in which a source failed; read `ok`.
1 when a change was refused (unknown key, unknown source, a permanent refusal) or on any other
error, with the message on stderr. 2 for a usage error.

## MCP tools

| Tool | Reads/writes | Returns |
|---|---|---|
| `focus_status` | reads | current priority (with `issue` when the intent starts `#<n> `, and its `context` as `kind:value`), the `standing` priorities (main first, `isCurrent`), open session, today's totals |
| `focus_sessions` | reads | sessions with the focused seconds for each (focus phase only), filterable by `since`, `issue` and `limit` |
| `focus_export` | writes a file the caller names | path, size, counts (not the contents) |
| `focus_propose_priority` | opens `focus://start` (confirmation required); optional `context` items | the URL, and whether it was opened |
| `focus_set_priorities` | opens `focus://priorities` (confirmation required); one main and up to two secondary, each with `done_when` and `context` | the URL, and whether it was opened |
| `focus_add_context` | opens `focus://context` (confirmation required); adds to the current priority, skipping items it already has | the URL, and whether it was opened |
| `focus_set_time_blocks` | writes the source's file, replacing it | the source, the count kept, the path |
| `focus_add_time_block` | adds one block to the source's file (same `id` replaces) | the source, the count, the path |
| `focus_list_time_blocks` | reads the files, optionally one `source` | each source's blocks |
| `focus_clear_time_blocks` | deletes one source's file, or every file when `source` is omitted | the sources removed |
| `focus_list_tasks` | reads the mirror; filter by `tags` (any of), `source`, `include_done`, `pinned_only` | `items` (key, title, url, reference, tags, state, pinned, pinnedToCurrentPriority, pending), `sources` with their `lastError`, every tag |
| `focus_create_task` | adds to `source` (default: the default source, else local) with `tags`; `pin_to_current_priority` | the new key, and whether it is still pending |
| `focus_complete_task` | completes `key` upstream (`reopen: true` reopens) | the key, state and whether it is pending |
| `focus_sync_tasks` | sends queued changes and fetches every source, or one `source` | the sync summary above |
| `focus_list_task_sources` | reads `config.json` and each source's status | name, provider, settings, tags, enabled, `isDefaultForCreate`, last sync and error |
| `focus_add_task_source` | adds or replaces a source (`name`, `provider`, `settings`, `tags`, `make_default`) | the source as stored |
| `focus_remove_task_source` | removes a source, its mirrored file, its queued actions and its pins | what was removed |

Context reaches the app in two ways. Items sent with a new priority are attached to it when the
person presses Replace. `focus_add_context` adds to the priority that is current when the person
presses Add; with no current priority the app ignores the URL, so the tool refuses first.

Standing priorities are a shortlist of starting points, not a backlog. Setting them does not
change the current priority. The app lists them under **Your priorities** on Now while no session
is open, and behind **Change priority** while one is; **Focus on this** makes one current with its
context. Sending the same set again reuses the stored tasks, and a task whose intent matches
gets the new done-when.

Register it with Copilot CLI for one repository (`.github/mcp.json`) or for all of them:

```sh
copilot mcp add focus-sentinel -- ~/.local/bin/focus-bridge mcp
```

## Test

```sh
cd Tools/focus-bridge && swift test
```

There are no UI tests. The tests build a store in a temporary directory with the app's own
`PriorityStore`, and read it back through the snapshot path. The task tests answer GitHub with a fake `HTTPTransport`
and a fake token provider, so they make no connection.
