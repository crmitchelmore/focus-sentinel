import Foundation
import SwiftData
import Testing

@testable import FocusCore

/// The known contents of the committed **v8** store fixture.
///
/// Recorded with the same `FOCUS_FIXTURE_RECORD=1` mechanism the v1, v2, v3 and v7 fixtures use,
/// and for the same reason: whichever epic bumps the schema next needs a genuine v8 artefact to
/// migrate from, rather than one written by whatever the schema happens to be on the day the
/// test runs.
///
/// It deliberately carries a `PrivacyPreferencesRecord` holding a window that is **not** the
/// committed default, so a later version can tell a stored choice from an absent one across its
/// own stage — the same reason the v7 fixture stores an explanation rather than leaving the
/// column `nil`.
enum SchemaV8Fixture {
    static let subdirectory = "Resources/SchemaV8"
    static let storeName = FocusStore.storeFileName

    static let taskID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
    static let privacyID = UUID(uuidString: "80808080-8080-4080-8080-808080808080")!

    /// 2026-01-01T00:00:00Z — the same reference instant every other fixture uses.
    static let timestamp = Date(timeIntervalSince1970: 1_767_225_600)

    static let taskIntent = "Say how long the app remembers, and mean it"
    /// Deliberately not `RetentionWindow.committedDefault`.
    static let retentionWindow: RetentionWindow = .thirtyDays

    static var recordDestination: URL {
        if let override = ProcessInfo.processInfo
            .environment[SchemaV1Fixture.recordDirectoryEnvironmentKey] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // FocusCoreTests
            .appending(path: subdirectory, directoryHint: .isDirectory)
    }

    static func url() throws -> URL {
        try #require(
            Bundle.module.url(
                forResource: storeName,
                withExtension: nil,
                subdirectory: subdirectory
            ),
            "the committed v8 store fixture is not in the test bundle"
        )
    }

    static func copyToTemporaryDirectory() throws -> URL {
        let source = try url()
        let sourceDirectory = source.deletingLastPathComponent()
        let destinationDirectory = FileManager.default.temporaryDirectory
            .appending(path: "focus-fixture-v8-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )

        for name in FocusStore.storeFileNames(for: storeName) {
            let from = sourceDirectory.appending(path: name, directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: from.path) else { continue }
            try FileManager.default.copyItem(
                at: from,
                to: destinationDirectory.appending(path: name, directoryHint: .notDirectory)
            )
        }

        return destinationDirectory.appending(path: storeName, directoryHint: .notDirectory)
    }

    /// Insert the known rows into a v8 context. Used when re-recording and when reading back.
    @MainActor
    static func populate(_ context: ModelContext) throws {
        let task = FocusSchemaV3.PriorityTask(
            id: taskID,
            intent: taskIntent,
            createdAt: timestamp,
            lastActivatedAt: timestamp
        )
        context.insert(task)
        context.insert(FocusSchemaV3.ActivePriority(task: task, activatedAt: timestamp))
        context.insert(
            FocusSchemaV8.PrivacyPreferencesRecord(
                id: privacyID,
                retentionDays: retentionWindow.storedDays,
                touchedAt: timestamp
            )
        )
        try context.save()
    }
}

/// The v7 → v8 migration, and the one entity it exists for (F-115, focus-l7n).
///
/// **What this suite owns that no earlier one can**: the plan's tip — how long the chain is now —
/// and, for this version, the *strict* additive invariant. v7 was the first version since v2 to
/// re-declare anything and paid for it with a narrower claim; v8 re-declares **nothing**, which
/// is the stronger statement and the one asserted below.
@Suite("Schema v8 migration")
@MainActor
struct MigrationV8Tests {
    static let timestamp = Date(timeIntervalSince1970: 1_767_225_600)

    static func temporaryStoreURL() -> URL {
        let directory = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            .appending(path: "focus-v8-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: FocusStore.storeFileName, directoryHint: .notDirectory)
    }

    /// **The plan's tip**, which the newest version's suite owns.
    @Test("v8 is the eighth schema and the seventh stage")
    func planShape() {
        // The newest schema is v9 since focus-exdi; `MigrationV9Tests` pins the plan's tail.
        #expect(FocusSchemaV8.versionIdentifier == Schema.Version(8, 0, 0))
        #expect(FocusMigrationPlan.schemas.count >= 8)
        #expect(FocusMigrationPlan.schemas[7] is FocusSchemaV8.Type)
        #expect(FocusMigrationPlan.stages.count >= 7)
    }

    /// **One entity added, none re-declared, nothing removed.**
    ///
    /// Read from the SwiftData `Schema` on both sides rather than from a list written here, so a
    /// second column quietly added to a v7 class fails this without anybody remembering a number.
    @Test("v8 adds exactly one entity and re-declares none")
    func versionEightIsStrictlyAdditive() {
        #expect(FocusSchemaV8.models.count == FocusSchemaV7.models.count + 1)

        // Every v7 class is carried by object identity, not merely by name.
        for prior in FocusSchemaV7.models {
            #expect(
                FocusSchemaV8.models.contains { $0 == prior },
                "v8 re-declared \(String(describing: prior))"
            )
        }

        let before = Schema(versionedSchema: FocusSchemaV7.self)
        let after = Schema(versionedSchema: FocusSchemaV8.self)
        let beforeNames = Set(before.entities.map(\.name))
        let afterNames = Set(after.entities.map(\.name))
        #expect(afterNames.subtracting(beforeNames) == ["PrivacyPreferencesRecord"])
        #expect(
            beforeNames.subtracting(afterNames).isEmpty,
            "v8 removed an entity, which no lightweight stage may do"
        )

        // And every carried entity's columns are untouched — the condition P-51 measured.
        for name in beforeNames {
            let beforeProperties = Set(
                before.entities.first { $0.name == name }?.properties.map(\.name) ?? []
            )
            let afterProperties = Set(
                after.entities.first { $0.name == name }?.properties.map(\.name) ?? []
            )
            #expect(!beforeProperties.isEmpty, "the v7 entity \(name) was not found")
            #expect(beforeProperties == afterProperties, "v8 changed the columns of \(name)")
        }
    }

    /// The new entity's one meaningful column carries a property default, which is what makes an
    /// upgrading store answer ninety days rather than zero — and zero is *forever*, so a default
    /// that had gone missing would silently stop the sweep for everybody who upgraded.
    @Test("a row inserted with no window carries the committed default")
    func theColumnDefaultIsNinetyDays() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        let row = FocusSchemaV8.PrivacyPreferencesRecord(touchedAt: Self.timestamp)
        context.insert(row)
        try context.save()

        #expect(row.retentionDays == 90)
        #expect(row.retentionWindow.window == .ninetyDays)
        #expect(row.retentionWindow.wasRecognised)
    }

    /// **The committed v7 fixture, opened by today's store**: one lightweight stage, every v7 row
    /// intact, and *no* privacy row — which is the honest state for a store written before the
    /// question could be asked, and reads as the ninety days that build was already keeping.
    @Test("the committed v7 fixture opens under v8 with its rows intact and no window stored")
    func versionSevenFixtureOpensUnderVersionEight() throws {
        let source = try SchemaV7Fixture.copyToTemporaryDirectory()
        let container = try FocusStore.makeContainer(kind: .temporary(source))
        let context = container.mainContext

        let tasks = try context.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>())
        #expect(tasks.map(\.intent) == [SchemaV7Fixture.taskIntent])

        let records = try context.fetch(FetchDescriptor<FocusSchemaV7.InterventionRecord>())
        #expect(records.count == 1)
        #expect(records.first?.explanationKinds == SchemaV7Fixture.recordExplanationKinds)

        #expect(
            FocusStore.privacyPreferencesRow(in: context) == nil,
            "the stage invented a privacy row for a store that never had one"
        )
        #expect(FocusStore.privacyPreferences(in: context) == .defaults)
        #expect(FocusStore.retentionPolicy(in: context).window == .ninetyDays)
    }

    /// The whole chain, in one open: a **v1** file across all seven stages into v8, still holding
    /// the priority v1's custom stage carried, and answering the default window.
    @Test("the committed v1 fixture migrates through all seven stages to v8")
    func versionOneFixtureMigratesToVersionEight() throws {
        let source = try SchemaV1Fixture.copyToTemporaryDirectory()
        let container = try FocusStore.makeContainer(kind: .temporary(source))
        let context = container.mainContext

        let tasks = try context.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>())
        #expect(!tasks.isEmpty, "the v1 fixture lost its tasks on the way to v8")
        let active = try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>())
        #expect(active.count == 1, "the v1 → v2 stage's carried priority did not survive to v8")
        #expect(FocusStore.retentionPolicy(in: context).window == .ninetyDays)
    }

    /// The committed **v8** fixture itself: written by a v8 build, read back by this one, with a
    /// stored window that is not the default.
    @Test("the committed v8 fixture opens with its stored window intact")
    func versionEightFixtureRoundTrips() throws {
        let source = try SchemaV8Fixture.copyToTemporaryDirectory()
        let container = try FocusStore.makeContainer(kind: .temporary(source))
        let context = container.mainContext

        let tasks = try context.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>())
        #expect(tasks.map(\.intent) == [SchemaV8Fixture.taskIntent])

        let stored = FocusStore.privacyPreferences(in: context)
        #expect(stored.retention == SchemaV8Fixture.retentionWindow)
        #expect(stored.retention != .committedDefault, "the fixture stopped being a real choice")
        #expect(stored.storedWindowWasRecognised)
    }

    /// Records the v8 fixture in the source tree, so whichever epic bumps the schema next has a
    /// real source. Runs only under `FOCUS_FIXTURE_RECORD=1`.
    @Test(
        "re-record the committed v8 fixture",
        .enabled(if: SchemaV1Fixture.isRecording)
    )
    func recordVersionEightFixture() throws {
        let staging = FileManager.default.temporaryDirectory
            .appending(
                path: "focus-fixture-v8-record-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let stagedStore = staging.appending(
            path: SchemaV8Fixture.storeName,
            directoryHint: .notDirectory
        )

        do {
            let container = try FocusStore.makeContainer(kind: .temporary(stagedStore))
            try SchemaV8Fixture.populate(container.mainContext)
        }
        // Container released: the store is closed and its sidecars are on disk.

        let destination = SchemaV8Fixture.recordDestination
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in FocusStore.storeFileNames(for: SchemaV8Fixture.storeName) {
            let from = staging.appending(path: name, directoryHint: .notDirectory)
            let to = destination.appending(path: name, directoryHint: .notDirectory)
            if FileManager.default.fileExists(atPath: to.path) {
                try FileManager.default.removeItem(at: to)
            }
            if FileManager.default.fileExists(atPath: from.path) {
                try FileManager.default.copyItem(at: from, to: to)
            }
        }

        print("RE-RECORDED SCHEMA V8 FIXTURE AT \(destination.path)")
        #expect(
            FileManager.default.fileExists(
                atPath: destination.appending(path: SchemaV8Fixture.storeName).path
            )
        )
    }
}
