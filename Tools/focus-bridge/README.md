# focus-bridge

A command-line tool and stdio MCP server that let scripts and agents read Focus Sentinel's data and
propose a priority. The app's UI is not driven.

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
  `focus://start?task=…&doneWhen=…` URL as the existing handoff. Before anything is opened, the app's own
  `HandoffRequest.parse` checks the URL. Focus Sentinel shows its confirmation sheet and changes
  nothing until the person presses **Replace**.
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
focus-bridge propose --task "#8 Review Sodexo material" --done-when "Notes written" [--dry-run]
focus-bridge mcp                         # MCP server on stdio
```

`FOCUS_STORE=/path/to/FocusSentinel.store` reads a different store, such as a fixture or the
Alpha train's store.

## MCP tools

| Tool | Reads/writes | Returns |
|---|---|---|
| `focus_status` | reads | current priority (with `issue` when the intent starts `#<n> `), open session, today's totals |
| `focus_sessions` | reads | sessions with the focused seconds for each (focus phase only), filterable by `since`, `issue` and `limit` |
| `focus_export` | writes a file the caller names | path, size, counts (not the contents) |
| `focus_propose_priority` | opens `focus://start` (confirmation required) | the URL, and whether it was opened |

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
