# focus-bridge

A command-line tool and stdio MCP server that let scripts and agents read Focus Sentinel's data,
propose a priority and propose context (apps, sites and keywords) for it. The app's UI is not
driven.

It is a tool, not part of the app: nothing in `FocusSentinel.xcodeproj` links it, so it is outside
the app's dependency graph, `check-boundaries.sh` and `check-forbidden.sh` (the same reason as
`Tools/windowid`).

## Safety properties

- **No network.** MCP runs over stdio. No socket is opened.
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
focus-bridge mcp                         # MCP server on stdio
```

Each `--slot` starts a standing priority (the first is the main one, at most three) and the
`--done-when` and `--context` options after it belong to it, up to 8 context items each.

`FOCUS_STORE=/path/to/FocusSentinel.store` reads a different store, such as a fixture or the
Alpha train's store.

## MCP tools

| Tool | Reads/writes | Returns |
|---|---|---|
| `focus_status` | reads | current priority (with `issue` when the intent starts `#<n> `, and its `context` as `kind:value`), the `standing` priorities (main first, `isCurrent`), open session, today's totals |
| `focus_sessions` | reads | sessions with the focused seconds for each (focus phase only), filterable by `since`, `issue` and `limit` |
| `focus_export` | writes a file the caller names | path, size, counts (not the contents) |
| `focus_propose_priority` | opens `focus://start` (confirmation required); optional `context` items | the URL, and whether it was opened |
| `focus_set_priorities` | opens `focus://priorities` (confirmation required); one main and up to two secondary, each with `done_when` and `context` | the URL, and whether it was opened |
| `focus_add_context` | opens `focus://context` (confirmation required); adds to the current priority, skipping items it already has | the URL, and whether it was opened |

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
`PriorityStore`, and read it back through the snapshot path.
