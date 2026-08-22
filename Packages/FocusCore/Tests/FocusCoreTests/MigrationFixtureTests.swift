import Foundation
import SwiftData
import Testing

@testable import FocusCore

/// The known contents of the committed v1 store fixture.
///
/// Fixed identifiers and a fixed instant, so the assertions are about *these rows* rather
/// than about "some rows". If a future schema silently drops or rewrites a column, the
/// comparison below is what notices.
enum SchemaV1Fixture {
    static let subdirectory = "Resources/SchemaV1"
    static let storeName = FocusStore.storeFileName

    static let taskID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    static let ruleID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    static let settingsID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

    /// 2026-01-01T00:00:00Z — the same reference instant `FixedDateProvider` uses.
    static let timestamp = Date(timeIntervalSince1970: 1_767_225_600)

    static let taskIntent = "Ship the native shell"
    static let taskDoneWhen = "The build gate exits zero"
    static let taskRevision = 3

    static let ruleScopeRaw = "domain"
    static let ruleSubject = "news.example"
    static let ruleVerdictRaw = "unrelated"

    static let appearancePreferenceRaw = "dark"

    /// The environment switch that rewrites the fixture instead of asserting against it.
    static let recordEnvironmentKey = "FOCUS_FIXTURE_RECORD"
    /// Overrides where a re-recorded fixture is written.
    static let recordDirectoryEnvironmentKey = "FOCUS_FIXTURE_DIR"

    static var isRecording: Bool {
        ProcessInfo.processInfo.environment[recordEnvironmentKey] == "1"
    }

    /// Where a re-recorded fixture is written: `FOCUS_FIXTURE_DIR` if set, otherwise the
    /// source tree, derived from this file's own compile-time path.
    static var recordDestination: URL {
        if let override = ProcessInfo.processInfo.environment[recordDirectoryEnvironmentKey] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // FocusCoreTests
            .appending(path: subdirectory, directoryHint: .isDirectory)
    }

    /// Insert the known rows into a context. Used only when re-recording.
    @MainActor
    static func populate(_ context: ModelContext) throws {
        context.insert(
            FocusSchemaV1.PriorityTask(
                id: taskID,
                intent: taskIntent,
                doneWhen: taskDoneWhen,
                isActive: true,
                createdAt: timestamp,
                completedAt: nil,
                revision: taskRevision
            )
        )
        context.insert(
            FocusSchemaV1.RelevanceRule(
                id: ruleID,
                scopeRaw: ruleScopeRaw,
                subject: ruleSubject,
                verdictRaw: ruleVerdictRaw,
                createdAt: timestamp
            )
        )
        context.insert(
            FocusSchemaV1.AppSettingsRecord(
                id: settingsID,
                appearancePreferenceRaw: appearancePreferenceRaw,
                schemaTouchedAt: timestamp
            )
        )
        try context.save()
    }
}

/// Proves that a store written by schema v1 still opens, through the migration plan, with
/// its rows unmodified.
///
/// This is what turns "no data loss on upgrade" from an intention into a fact. From e02
/// onwards, when `FocusSchemaV2` and its migration stage arrive, this same fixture — an
/// actual v1 store, byte-for-byte as v1 wrote it — is what proves the stage works. A test
/// that writes v1 data with today's code and reads it back with today's code would prove
/// nothing of the kind.
@Suite("Schema v1 store fixture")
struct MigrationFixtureTests {
    /// The fixture as it sits inside the built test bundle.
    ///
    /// Resolved with an explicit `subdirectory:` because the resource is declared
    /// `.copy("Resources")` on the test target, which preserves the directory structure.
    /// A repo-root `Fixtures/` directory is not usable here: SwiftPM bundles only resources
    /// declared inside a package, so such a file is simply absent from the built product in
    /// both lanes.
    private func fixtureURL() throws -> URL {
        try #require(
            Bundle.module.url(
                forResource: SchemaV1Fixture.storeName,
                withExtension: nil,
                subdirectory: SchemaV1Fixture.subdirectory
            ),
            "the committed v1 store fixture is not in the test bundle"
        )
    }

    /// Copy the store and both sidecars somewhere writable, and return the copy's URL.
    ///
    /// All three files matter. A store copied without its write-ahead log opens fine and is
    /// missing whatever had not been checkpointed — a silent, intermittent way to lose test
    /// data.
    private func copyFixtureToTemporaryDirectory() throws -> URL {
        let source = try fixtureURL()
        let sourceDirectory = source.deletingLastPathComponent()
        let destinationDirectory = FileManager.default.temporaryDirectory
            .appending(path: "focus-fixture-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )

        for name in FocusStore.storeFileNames(for: SchemaV1Fixture.storeName) {
            let from = sourceDirectory.appending(path: name, directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: from.path) else { continue }
            try FileManager.default.copyItem(
                at: from,
                to: destinationDirectory.appending(path: name, directoryHint: .notDirectory)
            )
        }

        return destinationDirectory.appending(
            path: SchemaV1Fixture.storeName,
            directoryHint: .notDirectory
        )
    }

    @Test(
        "the committed v1 store opens through the migration plan with its rows intact",
        .enabled(if: !SchemaV1Fixture.isRecording)
    )
    @MainActor
    func fixtureOpensWithRowsIntact() throws {
        let url = try copyFixtureToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        // Through `FocusStore.makeContainer`, therefore through `FocusMigrationPlan`.
        let container = try FocusStore.makeContainer(kind: .temporary(url))
        let context = container.mainContext

        let tasks = try context.fetch(FetchDescriptor<FocusSchemaV1.PriorityTask>())
        #expect(tasks.count == 1)
        let task = try #require(tasks.first)
        #expect(task.id == SchemaV1Fixture.taskID)
        #expect(task.intent == SchemaV1Fixture.taskIntent)
        #expect(task.doneWhen == SchemaV1Fixture.taskDoneWhen)
        #expect(task.isActive == true)
        #expect(task.completedAt == nil)
        #expect(task.revision == SchemaV1Fixture.taskRevision)
        #expect(task.createdAt == SchemaV1Fixture.timestamp)

        let rules = try context.fetch(FetchDescriptor<FocusSchemaV1.RelevanceRule>())
        #expect(rules.count == 1)
        let rule = try #require(rules.first)
        #expect(rule.id == SchemaV1Fixture.ruleID)
        #expect(rule.scopeRaw == SchemaV1Fixture.ruleScopeRaw)
        #expect(rule.subject == SchemaV1Fixture.ruleSubject)
        #expect(rule.verdictRaw == SchemaV1Fixture.ruleVerdictRaw)
        #expect(rule.createdAt == SchemaV1Fixture.timestamp)

        let settings = try context.fetch(FetchDescriptor<FocusSchemaV1.AppSettingsRecord>())
        #expect(settings.count == 1)
        let row = try #require(settings.first)
        #expect(row.id == SchemaV1Fixture.settingsID)
        #expect(row.appearancePreferenceRaw == SchemaV1Fixture.appearancePreferenceRaw)
        #expect(row.appearancePreference == .dark)
        #expect(row.schemaTouchedAt == SchemaV1Fixture.timestamp)

        // Tables declared in v1 but not written by the fixture are present and empty —
        // not missing, which is what a dropped table would look like.
        #expect(try context.fetch(FetchDescriptor<FocusSchemaV1.FocusSessionRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FocusSchemaV1.ActivityEvent>()).isEmpty)
    }

    @Test(
        "opening the copy never touches the fixture in the bundle",
        .enabled(if: !SchemaV1Fixture.isRecording)
    )
    @MainActor
    func openingTheCopyDoesNotMutateTheFixture() throws {
        let source = try fixtureURL()
        let before = try Data(contentsOf: source)

        let url = try copyFixtureToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let container = try FocusStore.makeContainer(kind: .temporary(url))
        _ = try container.mainContext.fetch(FetchDescriptor<FocusSchemaV1.PriorityTask>())

        let after = try Data(contentsOf: source)
        #expect(before == after, "the migration test mutated its own fixture")
    }

    /// Re-records the fixture in the source tree. Runs only under
    /// `FOCUS_FIXTURE_RECORD=1`, so the committed bytes never change by accident.
    @Test(
        "re-record the committed v1 fixture",
        .enabled(if: SchemaV1Fixture.isRecording)
    )
    @MainActor
    func recordFixture() throws {
        let staging = FileManager.default.temporaryDirectory
            .appending(path: "focus-fixture-record-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let stagedStore = staging.appending(
            path: SchemaV1Fixture.storeName,
            directoryHint: .notDirectory
        )

        do {
            let container = try FocusStore.makeContainer(kind: .temporary(stagedStore))
            try SchemaV1Fixture.populate(container.mainContext)
        }
        // Container released: the store is closed and its sidecars are on disk.

        let destination = SchemaV1Fixture.recordDestination
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in FocusStore.storeFileNames(for: SchemaV1Fixture.storeName) {
            let from = staging.appending(path: name, directoryHint: .notDirectory)
            let to = destination.appending(path: name, directoryHint: .notDirectory)
            if FileManager.default.fileExists(atPath: to.path) {
                try FileManager.default.removeItem(at: to)
            }
            if FileManager.default.fileExists(atPath: from.path) {
                try FileManager.default.copyItem(at: from, to: to)
            }
        }

        print("RE-RECORDED SCHEMA V1 FIXTURE AT \(destination.path)")
        #expect(
            FileManager.default.fileExists(
                atPath: destination.appending(path: SchemaV1Fixture.storeName).path
            )
        )
    }
}
