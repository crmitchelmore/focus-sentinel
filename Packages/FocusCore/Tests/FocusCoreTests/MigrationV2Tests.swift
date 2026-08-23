import Foundation
import SwiftData
import Testing

@testable import FocusCore

/// A migration plan that stops at v2.
///
/// Recording the v2 fixture needs a container that is *actually* v2. Since e03 `FocusStore`
/// builds v3 and would migrate the store on the way out, writing a v3 file into
/// `Resources/SchemaV2` and quietly destroying the only genuine v2 artefact in the repository
/// — the exact trap `SchemaV1OnlyPlan` exists to avoid one version down.
///
/// It still goes through `ModelContainer(for:migrationPlan:configurations:)`, so R-05's rule
/// — no plan-less container, anywhere — is not weakened by its existence. It carries the real
/// v1 → v2 stage, so a re-record from a v1 file would still be migrated correctly.
enum SchemaV2OnlyPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [FocusSchemaV1.self, FocusSchemaV2.self] }
    static var stages: [MigrationStage] { [FocusMigrationPlan.v1ToV2] }
}

/// The known contents of the committed **v2** store fixture.
///
/// Recorded with the same `FOCUS_FIXTURE_RECORD=1` mechanism the v1 fixture uses, so that
/// e03's v2 → v3 stage has a genuine v2 artefact to migrate rather than one written by
/// whatever the schema happens to be on the day the test runs.
///
/// It deliberately exercises the shapes v1 could not express: a task with a context item, a
/// task-scoped rule, and the active-priority pointer.
enum SchemaV2Fixture {
    static let subdirectory = "Resources/SchemaV2"
    static let storeName = FocusStore.storeFileName

    static let taskID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
    static let contextItemID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
    static let ruleID = UUID(uuidString: "66666666-6666-4666-8666-666666666666")!
    static let settingsID = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!

    /// 2026-01-01T00:00:00Z — the same reference instant `FixedDateProvider` uses.
    static let timestamp = Date(timeIntervalSince1970: 1_767_225_600)

    static let taskIntent = "Migrate the store to schema v2"
    static let taskDoneWhen = "The v2 fixture is committed"
    static let taskRevision = 2
    static let taskTimeboxSeconds = 1_500

    static let contextItemKindRaw = "domain"
    static let contextItemValue = "https://developer.apple.com"
    static let contextItemDisplayName = "developer.apple.com"

    static let ruleScopeRaw = "app"
    static let ruleSubject = "com.apple.dt.Xcode"
    static let ruleVerdictRaw = "relevant"

    static let appearancePreferenceRaw = "dark"
    static let lastRitualLocalDay = "2026-01-01"

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
            "the committed v2 store fixture is not in the test bundle"
        )
    }

    static func copyToTemporaryDirectory() throws -> URL {
        let source = try url()
        let sourceDirectory = source.deletingLastPathComponent()
        let destinationDirectory = FileManager.default.temporaryDirectory
            .appending(path: "focus-fixture-v2-\(UUID().uuidString)", directoryHint: .isDirectory)
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

    /// A container pinned to v2, for recording only. See `SchemaV2OnlyPlan`.
    static func makeVersionTwoContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: FocusSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(for: schema, migrationPlan: SchemaV2OnlyPlan.self, configurations: configuration)
    }

    /// Insert the known rows into a v2 context. Used when re-recording, and by the
    /// round-trip assertion below.
    @MainActor
    static func populate(_ context: ModelContext) throws {
        let task = FocusSchemaV2.PriorityTask(
            id: taskID,
            intent: taskIntent,
            doneWhen: taskDoneWhen,
            createdAt: timestamp,
            revision: taskRevision,
            timeboxSeconds: taskTimeboxSeconds,
            startedAt: timestamp,
            lastActivatedAt: timestamp
        )
        context.insert(task)

        context.insert(
            FocusSchemaV2.ContextItem(
                id: contextItemID,
                kindRaw: contextItemKindRaw,
                value: contextItemValue,
                displayName: contextItemDisplayName,
                addedAt: timestamp,
                task: task
            )
        )
        context.insert(
            FocusSchemaV2.RelevanceRule(
                id: ruleID,
                scopeRaw: ruleScopeRaw,
                subject: ruleSubject,
                verdictRaw: ruleVerdictRaw,
                createdAt: timestamp,
                task: task
            )
        )
        context.insert(
            FocusSchemaV2.AppSettingsRecord(
                id: settingsID,
                appearancePreferenceRaw: appearancePreferenceRaw,
                schemaTouchedAt: timestamp,
                lastRitualLocalDay: lastRitualLocalDay
            )
        )
        // The pointer is inserted once, against a task that owns none. Never a second row.
        context.insert(FocusSchemaV2.ActivePriority(task: task, activatedAt: timestamp))
        try context.save()
    }
}

/// The v1 → v2 migration, and the shape of the plan that performs it.
///
/// A wrong migration is data loss, so these assertions are about the **committed** v1 store —
/// bytes a v1 build actually wrote — and not about a v1 store synthesised by today's code.
@Suite("Schema v2 migration")
struct MigrationV2Tests {
    /// v2's own half of the plan's shape. The full three-schema, two-stage claim lives in
    /// `MigrationV3Tests`; what is asserted here is that v2 is still in the chain, still at
    /// version 2.0.0, and still declares exactly the seven models it shipped with — because a
    /// migration *source* that today's code has quietly edited proves nothing about tomorrow.
    @Test("v2 is still the plan's second schema, unchanged")
    func planShape() {
        #expect(FocusSchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
        #expect(FocusMigrationPlan.schemas.count == 3)
        #expect(FocusMigrationPlan.schemas[0] is FocusSchemaV1.Type)
        #expect(FocusMigrationPlan.schemas[1] is FocusSchemaV2.Type)
        #expect(FocusMigrationPlan.schemas[0].versionIdentifier == Schema.Version(1, 0, 0))
        #expect(FocusMigrationPlan.schemas[1].versionIdentifier == Schema.Version(2, 0, 0))
        #expect(FocusMigrationPlan.stages.count == 2)

        #expect(FocusSchemaV2.models.count == 7)
        let names = Set(FocusSchemaV2.models.map { String(describing: $0) })
        #expect(
            names == [
                "PriorityTask", "ActivePriority", "ContextItem", "FocusSessionRecord",
                "ActivityEvent", "RelevanceRule", "AppSettingsRecord"
            ]
        )
    }

    @Test("the v1 task that carried isActive arrives as the single ActivePriority row")
    @MainActor
    func activeFlagBecomesThePointerRow() throws {
        let url = try SchemaV1Fixture.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let container = try FocusStore.makeContainer(kind: .temporary(url))
        let context = container.mainContext

        let pointers = try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>())
        #expect(pointers.count == 1, "a lightweight stage would have dropped the active priority")

        let pointer = try #require(pointers.first)
        #expect(pointer.slot == FocusSchemaV3.ActivePriority.singletonSlot)
        #expect(pointer.task?.id == SchemaV1Fixture.taskID)
        // R-17: the carried pointer is stamped with the task's own creation instant, because
        // there is no honest record of when v1 activated it.
        #expect(pointer.activatedAt == SchemaV1Fixture.timestamp)

        let task = try #require(pointer.task)
        #expect(task.isActive == true)
        #expect(task.activePointer?.slot == FocusSchemaV3.ActivePriority.singletonSlot)
    }

    @Test("isActive is a projection: there is no stored column behind it")
    func isActiveIsNotAStoredColumn() throws {
        let entity = try #require(
            FocusStore.schema.entities.first { $0.name == "PriorityTask" },
            "the v2 schema has no PriorityTask entity"
        )
        let attributeNames = Set(entity.attributes.map(\.name))
        #expect(!attributeNames.contains("isActive"))
        #expect(attributeNames.contains("lastActivatedAt"))
        #expect(attributeNames.contains("timeboxSeconds"))
        #expect(attributeNames.contains("shipped"))
        #expect(attributeNames.contains("restartPoint"))

        let relationshipNames = Set(entity.relationships.map(\.name))
        #expect(relationshipNames.contains("activePointer"))
        #expect(relationshipNames.contains("contextItems"))
        #expect(relationshipNames.contains("rules"))
    }

    @Test("new optional and defaulted columns arrive with their defaults, not with garbage")
    @MainActor
    func newColumnsCarryTheirDefaults() throws {
        let url = try SchemaV1Fixture.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let container = try FocusStore.makeContainer(kind: .temporary(url))
        let context = container.mainContext

        let task = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>()).first
        )
        #expect(task.timeboxSeconds == nil)
        #expect(task.startedAt == nil)
        #expect(task.shipped == nil)
        #expect(task.restartPoint == nil)
        #expect(task.lastActivatedAt == nil)
        #expect(task.contextItems.isEmpty)
        #expect(task.rules.isEmpty)

        let settings = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.AppSettingsRecord>()).first
        )
        #expect(settings.lastRitualLocalDay == nil)
        #expect(settings.ritualEnabled == true)
        #expect(settings.hotKeyKeyCode == FocusSchemaV3.defaultHotKeyKeyCode)
        #expect(settings.hotKeyModifierFlags == FocusSchemaV3.defaultHotKeyModifierFlags)
        // control | option | command, as NSEvent.ModifierFlags raw values.
        #expect(FocusSchemaV2.defaultHotKeyModifierFlags == 1_835_008)
    }

    /// Re-opening a store that is already at v2 must not run the custom stage again. If it
    /// did, every launch would re-assert a priority the user had cleared.
    @Test("reopening an already-migrated store does not re-run the stage")
    @MainActor
    func reopeningDoesNotReRunTheStage() throws {
        let url = try SchemaV1Fixture.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let container = try FocusStore.makeContainer(kind: .temporary(url))
            let context = container.mainContext
            let pointers = try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>())
            #expect(pointers.count == 1)
            // Clear the priority, exactly as a user would.
            for pointer in pointers { context.delete(pointer) }
            try context.save()
        }

        let reopened = try FocusStore.makeContainer(kind: .temporary(url))
        let pointers = try reopened.mainContext
            .fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>())
        #expect(pointers.isEmpty, "the stage ran a second time and resurrected a cleared priority")

        // And the task itself is still there: clearing a priority is not deleting it.
        let tasks = try reopened.mainContext.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>())
        #expect(tasks.count == 1)
        #expect(tasks.first?.isActive == false)
    }

    @Test(
        "the committed v2 fixture opens with its rows intact",
        .enabled(if: !SchemaV1Fixture.isRecording)
    )
    @MainActor
    func versionTwoFixtureRoundTrips() throws {
        let url = try SchemaV2Fixture.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let container = try FocusStore.makeContainer(kind: .temporary(url))
        let context = container.mainContext

        let task = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>()).first
        )
        #expect(task.id == SchemaV2Fixture.taskID)
        #expect(task.intent == SchemaV2Fixture.taskIntent)
        #expect(task.doneWhen == SchemaV2Fixture.taskDoneWhen)
        #expect(task.revision == SchemaV2Fixture.taskRevision)
        #expect(task.timeboxSeconds == SchemaV2Fixture.taskTimeboxSeconds)
        #expect(task.startedAt == SchemaV2Fixture.timestamp)
        #expect(task.lastActivatedAt == SchemaV2Fixture.timestamp)
        #expect(task.isActive == true)

        #expect(task.contextItems.count == 1)
        let item = try #require(task.contextItems.first)
        #expect(item.id == SchemaV2Fixture.contextItemID)
        #expect(item.kindRaw == SchemaV2Fixture.contextItemKindRaw)
        #expect(item.value == SchemaV2Fixture.contextItemValue)
        #expect(item.displayName == SchemaV2Fixture.contextItemDisplayName)
        #expect(item.bookmark == nil)

        #expect(task.rules.count == 1)
        let rule = try #require(task.rules.first)
        #expect(rule.id == SchemaV2Fixture.ruleID)
        #expect(rule.scopeRaw == SchemaV2Fixture.ruleScopeRaw)
        #expect(rule.subject == SchemaV2Fixture.ruleSubject)
        #expect(rule.verdictRaw == SchemaV2Fixture.ruleVerdictRaw)
        #expect(rule.task?.id == SchemaV2Fixture.taskID)

        let settings = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.AppSettingsRecord>()).first
        )
        #expect(settings.id == SchemaV2Fixture.settingsID)
        #expect(settings.appearancePreference == .dark)
        #expect(settings.lastRitualLocalDay == SchemaV2Fixture.lastRitualLocalDay)

        let pointers = try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>())
        #expect(pointers.count == 1)
        #expect(pointers.first?.task?.id == SchemaV2Fixture.taskID)
    }

    @Test(
        "opening the v2 copy never touches the fixture in the bundle",
        .enabled(if: !SchemaV1Fixture.isRecording)
    )
    @MainActor
    func openingTheVersionTwoCopyDoesNotMutateTheFixture() throws {
        let source = try SchemaV2Fixture.url()
        let before = try Data(contentsOf: source)

        let url = try SchemaV2Fixture.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let container = try FocusStore.makeContainer(kind: .temporary(url))
        _ = try container.mainContext.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>())

        let after = try Data(contentsOf: source)
        #expect(before == after, "the v2 fixture test mutated its own fixture")
    }

    /// Records the v2 fixture in the source tree, so e03's v2 → v3 stage has a real source.
    /// Runs only under `FOCUS_FIXTURE_RECORD=1`.
    @Test(
        "re-record the committed v2 fixture",
        .enabled(if: SchemaV1Fixture.isRecording)
    )
    @MainActor
    func recordVersionTwoFixture() throws {
        let staging = FileManager.default.temporaryDirectory
            .appending(path: "focus-fixture-v2-record-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let stagedStore = staging.appending(
            path: SchemaV2Fixture.storeName,
            directoryHint: .notDirectory
        )

        do {
            // Through a **v2-pinned** container, not `FocusStore` — which since e03 opens v3
            // and would write a v3 file into `Resources/SchemaV2`, destroying the migration
            // source this suite exists to read.
            let container = try SchemaV2Fixture.makeVersionTwoContainer(at: stagedStore)
            try SchemaV2Fixture.populate(container.mainContext)
        }
        // Container released: the store is closed and its sidecars are on disk.

        let destination = SchemaV2Fixture.recordDestination
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in FocusStore.storeFileNames(for: SchemaV2Fixture.storeName) {
            let from = staging.appending(path: name, directoryHint: .notDirectory)
            let to = destination.appending(path: name, directoryHint: .notDirectory)
            if FileManager.default.fileExists(atPath: to.path) {
                try FileManager.default.removeItem(at: to)
            }
            if FileManager.default.fileExists(atPath: from.path) {
                try FileManager.default.copyItem(at: from, to: to)
            }
        }

        print("RE-RECORDED SCHEMA V2 FIXTURE AT \(destination.path)")
        #expect(
            FileManager.default.fileExists(
                atPath: destination.appending(path: SchemaV2Fixture.storeName).path
            )
        )
    }
}
