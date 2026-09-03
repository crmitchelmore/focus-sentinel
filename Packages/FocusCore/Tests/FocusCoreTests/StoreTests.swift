import Foundation
import SwiftData
import Testing

@testable import FocusCore

@Suite("SwiftData store")
struct StoreTests {
    private let clock = FixedDateProvider.reference

    @Test("the schema declares version 1.0.0 and exactly the five v1 models")
    func schemaVersionAndModels() {
        #expect(FocusSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(FocusSchemaV1.models.count == 5)

        let names = FocusSchemaV1.models.map { String(describing: $0) }
        #expect(
            Set(names) == [
                "PriorityTask", "FocusSessionRecord", "ActivityEvent", "RelevanceRule",
                "AppSettingsRecord"
            ]
        )
    }

    @Test("the current schema the store opens is v8")
    func currentSchemaIsVersionEight() {
        // The plan's own shape — how many schemas and how many stages — is asserted in
        // MigrationV8Tests. This is the narrower claim that FocusStore names v8 as the version
        // this build understands, which is what every caller inherits.
        //
        // Fifteen entities: v3's ten, plus the query ledger's receipts, the intervention log,
        // the Intervention pane's own settings row, v6's record of what the shell remembers
        // about itself between launches, and v8's Privacy row carrying the retention window.
        // v7 added none — it re-declared one — which is why fourteen stood for two versions.
        #expect(FocusStore.schema.entities.count == 15)
        #expect(FocusMigrationPlan.schemas.last is FocusSchemaV8.Type)
    }

    @Test("in-memory: insert, save and fetch round-trip")
    @MainActor
    func inMemoryRoundTrip() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        let task = FocusSchemaV3.PriorityTask(
            intent: "Ship the native shell",
            doneWhen: "The gate is green",
            createdAt: clock.now
        )
        context.insert(task)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.intent == "Ship the native shell")
        #expect(fetched.first?.doneWhen == "The gate is green")
        // A freshly inserted task is not active: activation is a pointer row, not a column.
        #expect(fetched.first?.isActive == false)
        #expect(fetched.first?.revision == 1)
        #expect(fetched.first?.completedAt == nil)
    }

    @Test("on disk: create, save, close, reopen — with the rows intact")
    @MainActor
    func onDiskSurvivesReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "focus-store-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: FocusStore.storeFileName, directoryHint: .notDirectory)
        let knownID = UUID()

        do {
            let container = try FocusStore.makeContainer(kind: .temporary(url))
            let context = container.mainContext
            context.insert(
                FocusSchemaV3.AppSettingsRecord(
                    id: knownID,
                    appearancePreferenceRaw: AppearancePreference.dark.rawValue,
                    schemaTouchedAt: clock.now
                )
            )
            try context.save()
        }
        // The container is out of scope; the store is closed.

        #expect(FileManager.default.fileExists(atPath: url.path))

        let reopened = try FocusStore.makeContainer(kind: .temporary(url))
        let rows = try reopened.mainContext.fetch(
            FetchDescriptor<FocusSchemaV3.AppSettingsRecord>()
        )
        #expect(rows.count == 1)
        #expect(rows.first?.id == knownID)
        #expect(rows.first?.appearancePreference == .dark)
        #expect(rows.first?.schemaTouchedAt == clock.now)
    }

    @Test("making a container twice for the same kind is idempotent")
    @MainActor
    func makeContainerIsIdempotent() throws {
        let first = try FocusStore.makeContainer(kind: .inMemory)
        let second = try FocusStore.makeContainer(kind: .inMemory)

        #expect(first.schema.entities.count == second.schema.entities.count)
        #expect(first.schema.entities.count == 15)
    }

    @Test("every enum-backed field persists as its string raw value")
    @MainActor
    func enumBackedFieldsPersistAsStrings() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        context.insert(
            FocusSchemaV3.FocusSessionRecord(
                startedAt: clock.now,
                phaseRaw: SessionPhase.onBreak.rawValue
            )
        )
        context.insert(
            FocusSchemaV3.ActivityEvent(
                at: clock.now,
                kindRaw: "frontmostApplicationChanged",
                bundleID: "com.apple.dt.Xcode"
            )
        )
        context.insert(
            FocusSchemaV3.RelevanceRule(
                scopeRaw: "domain",
                subject: "news.example",
                verdictRaw: "unrelated",
                createdAt: clock.now
            )
        )
        context.insert(
            FocusSchemaV3.AppSettingsRecord(
                appearancePreferenceRaw: AppearancePreference.matchSystem.rawValue,
                schemaTouchedAt: clock.now
            )
        )
        try context.save()

        let session = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.FocusSessionRecord>()).first
        )
        // The store keeps the string and nothing else. Turning it back into a phase is
        // `SessionPhase.decode(_:)`'s job — an exhaustive switch that also carries the v1/v2
        // aliases — and its totality is asserted in `SessionMachineTests`.
        #expect(session.phaseRaw == "onBreak")

        let event = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.ActivityEvent>()).first
        )
        #expect(event.kindRaw == "frontmostApplicationChanged")

        let rule = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.RelevanceRule>()).first
        )
        #expect(rule.scopeRaw == "domain")
        #expect(rule.verdictRaw == "unrelated")

        let settings = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.AppSettingsRecord>()).first
        )
        #expect(settings.appearancePreferenceRaw == "matchSystem")
    }

    @Test("an unrecognised stored raw value decodes to a safe default rather than crashing")
    func unknownRawValuesDecodeSafely() {
        let settings = FocusSchemaV3.AppSettingsRecord(
            appearancePreferenceRaw: "solarizedFromTheFuture",
            schemaTouchedAt: clock.now
        )
        #expect(settings.appearancePreference == .matchSystem)

        // A phase this build cannot interpret is stored verbatim and never rewritten on the
        // way in; what it *decodes to* is `SessionPhase.decode(_:)`'s answer, and that a
        // stranger decodes to `.complete` — a session this build cannot read is over as far
        // as it is concerned — is asserted in `SessionMachineTests`.
        let session = FocusSchemaV3.FocusSessionRecord(
            startedAt: clock.now,
            phaseRaw: "hyperfocus"
        )
        #expect(session.phaseRaw == "hyperfocus")
    }

    @Test("appearance preference resolves against the system scheme")
    func appearancePreferenceResolves() {
        #expect(AppearancePreference.matchSystem.resolvedColorScheme(system: .dark) == .dark)
        #expect(AppearancePreference.matchSystem.resolvedColorScheme(system: .light) == .light)
        #expect(AppearancePreference.light.resolvedColorScheme(system: .dark) == .light)
        #expect(AppearancePreference.dark.resolvedColorScheme(system: .light) == .dark)
        #expect(AppearancePreference.allCases.count == 3)
    }

    @Test("a store is three files, and the helper says so")
    func storeIsThreeFiles() {
        #expect(
            FocusStore.storeFileNames() == [
                "FocusSentinel.store", "FocusSentinel.store-wal", "FocusSentinel.store-shm"
            ]
        )
    }

    @Test("the Application Support path is the documented one")
    func applicationSupportPathIsStable() {
        let url = FocusStore.applicationSupportURL
        #expect(url.lastPathComponent == "FocusSentinel.store")
        #expect(url.deletingLastPathComponent().lastPathComponent == "com.chrismitchelmore.FocusSentinel")
        #expect(url.path.contains("Application Support"))
    }
}
