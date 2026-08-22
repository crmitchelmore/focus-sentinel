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

    @Test("the current schema the store opens is v2")
    func currentSchemaIsVersionTwo() {
        // The plan's own shape — two schemas, one custom stage — is asserted in
        // MigrationV2Tests. This is the narrower claim that FocusStore names v2 as the
        // version this build understands, which is what every caller inherits.
        #expect(FocusStore.schema.entities.count == 7)
        #expect(FocusMigrationPlan.schemas.last is FocusSchemaV2.Type)
    }

    @Test("in-memory: insert, save and fetch round-trip")
    @MainActor
    func inMemoryRoundTrip() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        let task = FocusSchemaV2.PriorityTask(
            intent: "Ship the native shell",
            doneWhen: "The gate is green",
            createdAt: clock.now
        )
        context.insert(task)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<FocusSchemaV2.PriorityTask>())
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
                FocusSchemaV2.AppSettingsRecord(
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
            FetchDescriptor<FocusSchemaV2.AppSettingsRecord>()
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
        #expect(first.schema.entities.count == 7)
    }

    @Test("every enum-backed field persists as its string raw value")
    @MainActor
    func enumBackedFieldsPersistAsStrings() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        context.insert(
            FocusSchemaV2.FocusSessionRecord(
                startedAt: clock.now,
                phaseRaw: SessionPhase.onBreak.rawValue
            )
        )
        context.insert(
            FocusSchemaV2.ActivityEvent(
                at: clock.now,
                kindRaw: "frontmostApplicationChanged",
                bundleID: "com.apple.dt.Xcode"
            )
        )
        context.insert(
            FocusSchemaV2.RelevanceRule(
                scopeRaw: "domain",
                subject: "news.example",
                verdictRaw: "unrelated",
                createdAt: clock.now
            )
        )
        context.insert(
            FocusSchemaV2.AppSettingsRecord(
                appearancePreferenceRaw: AppearancePreference.matchSystem.rawValue,
                schemaTouchedAt: clock.now
            )
        )
        try context.save()

        let session = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV2.FocusSessionRecord>()).first
        )
        #expect(session.phaseRaw == "onBreak")
        #expect(session.phase == .onBreak)

        let event = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV2.ActivityEvent>()).first
        )
        #expect(event.kindRaw == "frontmostApplicationChanged")

        let rule = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV2.RelevanceRule>()).first
        )
        #expect(rule.scopeRaw == "domain")
        #expect(rule.verdictRaw == "unrelated")

        let settings = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV2.AppSettingsRecord>()).first
        )
        #expect(settings.appearancePreferenceRaw == "matchSystem")
    }

    @Test("an unrecognised stored raw value decodes to a safe default rather than crashing")
    func unknownRawValuesDecodeSafely() {
        let settings = FocusSchemaV2.AppSettingsRecord(
            appearancePreferenceRaw: "solarizedFromTheFuture",
            schemaTouchedAt: clock.now
        )
        #expect(settings.appearancePreference == .matchSystem)

        let session = FocusSchemaV2.FocusSessionRecord(
            startedAt: clock.now,
            phaseRaw: "hyperfocus"
        )
        #expect(session.phase == .ended)
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
