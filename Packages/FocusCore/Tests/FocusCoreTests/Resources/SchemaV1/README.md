# Schema v1 store fixture

`FocusSentinel.store`, `FocusSentinel.store-wal` and `FocusSentinel.store-shm` are a real
SwiftData store, written through `FocusSchemaV1` (`Schema.Version(1, 0, 0)`) and committed
as-is.

## Why it is committed

`MigrationFixtureTests` copies these three files somewhere writable, opens the copy through
`FocusStore.makeContainer(kind:)` — and therefore through `FocusMigrationPlan` — and asserts
the rows come back unmodified.

The point is that the bytes were written by v1 and are never rewritten. A test that writes
today's data with today's code and reads it back with today's code proves that today's code
is self-consistent, which is not the claim anyone cares about. When e02 introduces
`FocusSchemaV2` and its first `MigrationStage`, *this* file is what proves the stage does
not lose data.

All three files are needed. A store copied without its write-ahead log opens perfectly well
and is missing whatever had not yet been checkpointed — a silent, intermittent way to lose
exactly the rows a test was about to assert on.

## What is in it

One row in each of three tables; the other two v1 tables are present and empty.

| table | field | value |
|---|---|---|
| `PriorityTask` | `id` | `11111111-1111-4111-8111-111111111111` |
| | `intent` | `Ship the native shell` |
| | `doneWhen` | `The build gate exits zero` |
| | `isActive` | `true` |
| | `createdAt` | `2026-01-01T00:00:00Z` |
| | `completedAt` | `nil` |
| | `revision` | `3` |
| `RelevanceRule` | `id` | `22222222-2222-4222-8222-222222222222` |
| | `scopeRaw` | `domain` |
| | `subject` | `news.example` |
| | `verdictRaw` | `unrelated` |
| | `createdAt` | `2026-01-01T00:00:00Z` |
| `AppSettingsRecord` | `id` | `33333333-3333-4333-8333-333333333333` |
| | `appearancePreferenceRaw` | `dark` |
| | `schemaTouchedAt` | `2026-01-01T00:00:00Z` |
| `FocusSessionRecord` | — | no rows |
| `ActivityEvent` | — | no rows |

The same values are declared in code, in `SchemaV1Fixture` inside
`Tests/FocusCoreTests/MigrationFixtureTests.swift`. The table above is documentation; that
enum is the source of truth for both writing and asserting, so the two cannot disagree.

## How it was produced, and how to regenerate it

```
cd Packages/FocusCore
FOCUS_FIXTURE_RECORD=1 swift test
```

`FOCUS_FIXTURE_RECORD=1` disables the assertions and enables the `recordFixture` test, which
writes a fresh v1 store into a temporary directory, closes it, and copies all three files
back over the ones here. `FOCUS_FIXTURE_DIR` overrides the destination if you want to
inspect the result before replacing anything.

**Regenerating is a decision, not a fix.** If `MigrationFixtureTests` fails, the useful
question is almost always "what changed about the schema?", not "how do I make the fixture
match again". Re-record only when the fixture is deliberately being extended — and say so in
the commit message.

## How the test finds it

```swift
Bundle.module.url(forResource: "FocusSentinel.store", withExtension: nil, subdirectory: "Resources/SchemaV1")
```

That resolves because `FocusCoreTests` declares `resources: [.copy("Resources")]`, and
`.copy` preserves the directory structure verbatim. A repo-root `Fixtures/` directory would
not work at all: SwiftPM bundles only resources declared *inside* a package, so a fixture
placed outside one is simply absent from the built product — in both the `swift test` and
the `xcodebuild test` lane.
