import Foundation
import SwiftData
import Testing

@testable import FocusCore

/// The known contents of the committed **v3** store fixture.
///
/// Recorded with the same `FOCUS_FIXTURE_RECORD=1` mechanism the v1 and v2 fixtures use, so
/// that whichever epic bumps the schema next has a genuine v3 artefact to migrate rather than
/// one written by whatever the schema happens to be on the day the test runs.
///
/// It deliberately exercises the shapes v2 could not express: a session carrying the whole
/// restoration anchor and a two-cause pause set, a transition row attached to it, a seeded
/// sensitive-app entry and a capability observation.
enum SchemaV3Fixture {
    static let subdirectory = "Resources/SchemaV3"
    static let storeName = FocusStore.storeFileName

    static let taskID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
    static let sessionID = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
    static let transitionID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
    static let sensitiveID = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
    static let capabilityID = UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!
    static let settingsID = UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!
    static let eventID = UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")!

    /// 2026-01-01T00:00:00Z — the same reference instant the v1 and v2 fixtures use.
    static let timestamp = Date(timeIntervalSince1970: 1_767_225_600)

    static let taskIntent = "Give the app eyes without asking for a grant"

    static let sessionPhaseRaw = "paused"
    static let sessionResumeToRaw = "focus"
    static let sessionKindRaw = "countdown"
    static let sessionPlannedSeconds = 1_500
    /// Seconds since boot, in the shape `mach_continuous_time()` produces (probe P-106).
    static let sessionUptimeAnchorSeconds = 741_532.264_185_666_6
    static let sessionBootIdentity = "1786742847.869178"
    /// Sorted and comma-joined, which is what makes the encoding deterministic.
    static let sessionPauseCausesRaw = "screenLocked,user"

    static let transitionFromRaw = "focus"
    static let transitionToRaw = "paused"
    static let transitionEventRaw = "paused"
    static let transitionReasonRaw = "user"
    static let transitionOutcomeRaw = "accepted"

    static let sensitiveBundleID = "com.apple.keychainaccess"
    static let sensitiveKindRaw = "sensitive"

    static let capabilityRaw = "cameraActivity"
    static let capabilityStateRaw = "unavailable"

    static let eventKindRaw = "sessionPhaseChanged"
    static let eventBundleID = "com.apple.dt.Xcode"
    static let eventDwellSeconds = 42.5
    static let eventDisplayID = 3

    static let appearancePreferenceRaw = "dark"

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
            "the committed v3 store fixture is not in the test bundle"
        )
    }

    static func copyToTemporaryDirectory() throws -> URL {
        let source = try url()
        let sourceDirectory = source.deletingLastPathComponent()
        let destinationDirectory = FileManager.default.temporaryDirectory
            .appending(path: "focus-fixture-v3-\(UUID().uuidString)", directoryHint: .isDirectory)
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

    /// Insert the known rows into a v3 context. Used when re-recording, and by the round-trip
    /// assertion below.
    @MainActor
    static func populate(_ context: ModelContext) throws {
        let task = FocusSchemaV3.PriorityTask(
            id: taskID,
            intent: taskIntent,
            createdAt: timestamp,
            lastActivatedAt: timestamp
        )
        context.insert(task)

        let session = FocusSchemaV3.FocusSessionRecord(
            id: sessionID,
            taskID: taskID,
            startedAt: timestamp,
            phaseRaw: sessionPhaseRaw,
            phaseChangedAt: timestamp,
            resumeToRaw: sessionResumeToRaw,
            kindRaw: sessionKindRaw,
            plannedSeconds: sessionPlannedSeconds,
            uptimeAnchorSeconds: sessionUptimeAnchorSeconds,
            bootIdentity: sessionBootIdentity,
            pauseCausesRaw: sessionPauseCausesRaw
        )
        context.insert(session)

        context.insert(
            FocusSchemaV3.SessionTransitionRecord(
                id: transitionID,
                at: timestamp,
                fromRaw: transitionFromRaw,
                toRaw: transitionToRaw,
                eventRaw: transitionEventRaw,
                reasonRaw: transitionReasonRaw,
                outcomeRaw: transitionOutcomeRaw,
                session: session
            )
        )

        context.insert(
            FocusSchemaV3.ActivityEvent(
                id: eventID,
                at: timestamp,
                kindRaw: eventKindRaw,
                bundleID: eventBundleID,
                sessionID: sessionID,
                dwellSeconds: eventDwellSeconds,
                displayID: eventDisplayID
            )
        )

        context.insert(
            FocusSchemaV3.SensitiveAppEntry(
                id: sensitiveID,
                bundleID: sensitiveBundleID,
                kindRaw: sensitiveKindRaw,
                isBuiltIn: true,
                addedAt: timestamp
            )
        )

        context.insert(
            FocusSchemaV3.CapabilityRecord(
                id: capabilityID,
                capabilityRaw: capabilityRaw,
                stateRaw: capabilityStateRaw,
                observedAt: timestamp
            )
        )

        context.insert(
            FocusSchemaV3.AppSettingsRecord(
                id: settingsID,
                appearancePreferenceRaw: appearancePreferenceRaw,
                schemaTouchedAt: timestamp
            )
        )

        // The pointer is inserted once, against a task that owns none. Never a second row.
        context.insert(FocusSchemaV3.ActivePriority(task: task, activatedAt: timestamp))
        try context.save()
    }
}

/// The v2 → v3 migration, the **chain** from v1, and the shape of the plan that performs both.
///
/// The chain is the claim that matters. e01 shipped a plan with no stages so that e02 would be
/// *adding* one rather than retrofitting migration onto a store that never had any; e02 added
/// the custom v1 → v2 stage; e03 adds the lightweight v2 → v3 one. A user who has not opened
/// this app since e01 must therefore cross **two** stages on their next launch, and nothing
/// they wrote may be lost on the way. That is asserted here against the **committed** v1
/// store — bytes a v1 build actually wrote — rather than against a v1 store synthesised by
/// today's code, which would prove nothing of the kind.
@Suite("Schema v3 migration")
struct MigrationV3Tests {
    @Test("the plan declares three schemas and exactly two stages")
    func planShape() {
        #expect(FocusSchemaV3.versionIdentifier == Schema.Version(3, 0, 0))
        #expect(FocusMigrationPlan.schemas.count == 3)
        #expect(FocusMigrationPlan.schemas[0] is FocusSchemaV1.Type)
        #expect(FocusMigrationPlan.schemas[1] is FocusSchemaV2.Type)
        #expect(FocusMigrationPlan.schemas[2] is FocusSchemaV3.Type)
        #expect(FocusMigrationPlan.schemas[2].versionIdentifier == Schema.Version(3, 0, 0))
        #expect(FocusMigrationPlan.stages.count == 2)

        #expect(FocusSchemaV3.models.count == 10)
        let names = Set(FocusSchemaV3.models.map { String(describing: $0) })
        #expect(
            names == [
                "PriorityTask", "ActivePriority", "ContextItem", "FocusSessionRecord",
                "SessionTransitionRecord", "ActivityEvent", "RelevanceRule",
                "SensitiveAppEntry", "CapabilityRecord", "AppSettingsRecord"
            ]
        )

        // v1 and v2 are migration sources and must stay exactly as they shipped. A source you
        // have edited is not a source.
        #expect(FocusSchemaV1.models.count == 5)
        #expect(FocusSchemaV2.models.count == 7)
    }

    /// The committed **v2** fixture, opened by today's store: one lightweight stage, every row
    /// intact, and the three v2 shapes that v1 could not express still present.
    @Test(
        "the committed v2 fixture opens under v3 with its rows intact",
        .enabled(if: !SchemaV1Fixture.isRecording)
    )
    @MainActor
    func versionTwoFixtureOpensUnderVersionThree() throws {
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

        // The context pack: v2's addition, and still here.
        #expect(task.contextItems.count == 1)
        let item = try #require(task.contextItems.first)
        #expect(item.id == SchemaV2Fixture.contextItemID)
        #expect(item.kindRaw == SchemaV2Fixture.contextItemKindRaw)
        #expect(item.value == SchemaV2Fixture.contextItemValue)
        #expect(item.displayName == SchemaV2Fixture.contextItemDisplayName)

        // The task-scoped rule: v2's other addition.
        #expect(task.rules.count == 1)
        let rule = try #require(task.rules.first)
        #expect(rule.id == SchemaV2Fixture.ruleID)
        #expect(rule.subject == SchemaV2Fixture.ruleSubject)
        #expect(rule.verdictRaw == SchemaV2Fixture.ruleVerdictRaw)
        #expect(rule.task?.id == SchemaV2Fixture.taskID)

        // The pointer row, which is the single-active-priority invariant itself.
        let pointers = try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>())
        #expect(pointers.count == 1)
        #expect(pointers.first?.task?.id == SchemaV2Fixture.taskID)
        #expect(pointers.first?.slot == FocusSchemaV3.ActivePriority.singletonSlot)

        let settings = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.AppSettingsRecord>()).first
        )
        #expect(settings.id == SchemaV2Fixture.settingsID)
        #expect(settings.appearancePreference == .dark)
        #expect(settings.lastRitualLocalDay == SchemaV2Fixture.lastRitualLocalDay)
    }

    /// The chain: a **v1** file, across both stages, in one open.
    @Test(
        "the committed v1 fixture migrates through both stages to v3",
        .enabled(if: !SchemaV1Fixture.isRecording)
    )
    @MainActor
    func versionOneFixtureMigratesThroughBothStages() throws {
        let url = try SchemaV1Fixture.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let container = try FocusStore.makeContainer(kind: .temporary(url))
        let context = container.mainContext

        let task = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>()).first
        )
        #expect(task.id == SchemaV1Fixture.taskID)
        #expect(task.intent == SchemaV1Fixture.taskIntent)
        #expect(task.doneWhen == SchemaV1Fixture.taskDoneWhen)
        #expect(task.revision == SchemaV1Fixture.taskRevision)
        #expect(task.createdAt == SchemaV1Fixture.timestamp)

        // The v1 → v2 stage's whole reason for being custom: `isActive` became a pointer row,
        // and it has to survive the second stage as well as the first.
        let pointers = try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>())
        #expect(pointers.count == 1, "the active priority did not survive the two-stage chain")
        #expect(pointers.first?.task?.id == SchemaV1Fixture.taskID)
        #expect(pointers.first?.activatedAt == SchemaV1Fixture.timestamp)
        #expect(task.isActive == true)

        let rule = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.RelevanceRule>()).first
        )
        #expect(rule.id == SchemaV1Fixture.ruleID)
        #expect(rule.subject == SchemaV1Fixture.ruleSubject)
        #expect(rule.verdictRaw == SchemaV1Fixture.ruleVerdictRaw)
        #expect(rule.task == nil, "a v1 rule is a global rule; v1 could not scope one")

        let settings = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.AppSettingsRecord>()).first
        )
        #expect(settings.id == SchemaV1Fixture.settingsID)
        #expect(settings.appearancePreference == .dark)
        #expect(settings.schemaTouchedAt == SchemaV1Fixture.timestamp)

        // The three tables e03 adds are present and empty — not missing, which is what a
        // failed stage would look like.
        #expect(try context.fetch(FetchDescriptor<FocusSchemaV3.SessionTransitionRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FocusSchemaV3.SensitiveAppEntry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FocusSchemaV3.CapabilityRecord>()).isEmpty)
    }

    /// Every v3 addition arrives `nil` or at its documented default, on a row that predates it.
    ///
    /// This is what makes the lightweight stage legitimate rather than lucky: probe P-51
    /// measured that a new non-optional attribute migrates lightweight **only** with a
    /// property default, and the assertions below are that claim, per column.
    @Test(
        "v3's new attributes arrive nil or at their defaults on a migrated row",
        .enabled(if: !SchemaV1Fixture.isRecording)
    )
    @MainActor
    func newColumnsCarryTheirDefaults() throws {
        let url = try SchemaV2Fixture.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let container = try FocusStore.makeContainer(kind: .temporary(url))
        let context = container.mainContext

        let settings = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.AppSettingsRecord>()).first
        )
        #expect(settings.sensingPaused == false)
        #expect(settings.idleThresholdSeconds == FocusSchemaV3.defaultIdleThresholdSeconds)
        #expect(settings.idleThresholdSeconds == 180)
        #expect(settings.corroborationTickSeconds == FocusSchemaV3.defaultCorroborationTickSeconds)
        #expect(settings.corroborationTickSeconds == 5)
        #expect(settings.launchContextOnSessionStart == false)
        #expect(settings.mediaSuppressionEnabled == true)
        // The v2 columns are untouched by the second stage.
        #expect(settings.ritualEnabled == true)
        #expect(settings.hotKeyKeyCode == FocusSchemaV3.defaultHotKeyKeyCode)

        // A session written under v2 carries none of the v3 runtime, and reads back as `nil`
        // rather than as a fabricated anchor — which is the difference between "this session
        // has no anchor" and "this session's anchor is zero seconds since boot".
        let session = FocusSchemaV3.FocusSessionRecord(
            startedAt: SchemaV2Fixture.timestamp,
            phaseRaw: "focus"
        )
        context.insert(session)
        try context.save()

        let stored = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.FocusSessionRecord>()).first
        )
        #expect(stored.phaseChangedAt == nil)
        #expect(stored.resumeToRaw == nil)
        #expect(stored.kindRaw == "openEnded")
        #expect(stored.plannedSeconds == nil)
        #expect(stored.deadlineAt == nil)
        #expect(stored.uptimeAnchorSeconds == nil)
        #expect(stored.bootIdentity == nil)
        #expect(stored.pauseCausesRaw == nil)
        #expect(stored.interruptionReasonRaw == nil)
        #expect(stored.restartPointNote == nil)
        #expect(stored.lastActiveBundleID == nil)
        #expect(stored.transitions.isEmpty)

        let event = FocusSchemaV3.ActivityEvent(
            at: SchemaV2Fixture.timestamp,
            kindRaw: "frontmostApplicationChanged"
        )
        context.insert(event)
        try context.save()
        let storedEvent = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.ActivityEvent>()).first
        )
        #expect(storedEvent.sessionID == nil)
        #expect(storedEvent.dwellSeconds == nil)
        #expect(storedEvent.displayID == nil)
        #expect(storedEvent.detail == nil)
    }

    /// Re-opening a store that is already at v3 must not run a stage again. The v1 → v2 stage
    /// is the dangerous one: if it re-ran, every launch would re-assert a priority the user
    /// had cleared.
    @Test(
        "reopening a store already at v3 re-runs neither stage",
        .enabled(if: !SchemaV1Fixture.isRecording)
    )
    @MainActor
    func reopeningReRunsNoStage() throws {
        let url = try SchemaV1Fixture.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let container = try FocusStore.makeContainer(kind: .temporary(url))
            let context = container.mainContext
            let pointers = try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>())
            #expect(pointers.count == 1)
            // Clear the priority, exactly as a user would.
            for pointer in pointers { context.delete(pointer) }
            // And add a v3-only row, so the second open has something of v3's to lose.
            context.insert(
                FocusSchemaV3.CapabilityRecord(
                    capabilityRaw: "microphoneActivity",
                    stateRaw: "available",
                    observedAt: SchemaV1Fixture.timestamp
                )
            )
            try context.save()
        }

        let reopened = try FocusStore.makeContainer(kind: .temporary(url))
        let context = reopened.mainContext

        let pointers = try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>())
        #expect(pointers.isEmpty, "a stage ran again and resurrected a cleared priority")

        let tasks = try context.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>())
        #expect(tasks.count == 1, "clearing a priority is not deleting it")
        #expect(tasks.first?.isActive == false)

        let capabilities = try context.fetch(FetchDescriptor<FocusSchemaV3.CapabilityRecord>())
        #expect(capabilities.count == 1)
        #expect(capabilities.first?.capabilityRaw == "microphoneActivity")
    }

    /// The committed v3 fixture itself: written by a v3 build, read back by this one.
    @Test(
        "the committed v3 fixture opens with its rows intact",
        .enabled(if: !SchemaV1Fixture.isRecording)
    )
    @MainActor
    func versionThreeFixtureRoundTrips() throws {
        let url = try SchemaV3Fixture.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let container = try FocusStore.makeContainer(kind: .temporary(url))
        let context = container.mainContext

        let session = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.FocusSessionRecord>()).first
        )
        #expect(session.id == SchemaV3Fixture.sessionID)
        #expect(session.startedAt == SchemaV3Fixture.timestamp)
        #expect(session.phaseRaw == SchemaV3Fixture.sessionPhaseRaw)
        #expect(session.phaseChangedAt == SchemaV3Fixture.timestamp)
        #expect(session.resumeToRaw == SchemaV3Fixture.sessionResumeToRaw)
        #expect(session.kindRaw == SchemaV3Fixture.sessionKindRaw)
        #expect(session.plannedSeconds == SchemaV3Fixture.sessionPlannedSeconds)
        #expect(session.uptimeAnchorSeconds == SchemaV3Fixture.sessionUptimeAnchorSeconds)
        #expect(session.bootIdentity == SchemaV3Fixture.sessionBootIdentity)
        // Two causes, sorted and comma-joined: a session paused for two reasons needs both
        // cleared, so both have to survive a reopen.
        #expect(session.pauseCausesRaw == SchemaV3Fixture.sessionPauseCausesRaw)

        #expect(session.transitions.count == 1)
        let transition = try #require(session.transitions.first)
        #expect(transition.id == SchemaV3Fixture.transitionID)
        #expect(transition.fromRaw == SchemaV3Fixture.transitionFromRaw)
        #expect(transition.toRaw == SchemaV3Fixture.transitionToRaw)
        #expect(transition.eventRaw == SchemaV3Fixture.transitionEventRaw)
        #expect(transition.reasonRaw == SchemaV3Fixture.transitionReasonRaw)
        #expect(transition.outcomeRaw == SchemaV3Fixture.transitionOutcomeRaw)
        #expect(transition.session?.id == SchemaV3Fixture.sessionID)

        let event = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.ActivityEvent>()).first
        )
        #expect(event.id == SchemaV3Fixture.eventID)
        #expect(event.kindRaw == SchemaV3Fixture.eventKindRaw)
        #expect(event.bundleID == SchemaV3Fixture.eventBundleID)
        #expect(event.sessionID == SchemaV3Fixture.sessionID)
        #expect(event.dwellSeconds == SchemaV3Fixture.eventDwellSeconds)
        #expect(event.displayID == SchemaV3Fixture.eventDisplayID)
        #expect(event.detail == nil)

        let sensitive = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.SensitiveAppEntry>()).first
        )
        #expect(sensitive.id == SchemaV3Fixture.sensitiveID)
        #expect(sensitive.bundleID == SchemaV3Fixture.sensitiveBundleID)
        #expect(sensitive.kindRaw == SchemaV3Fixture.sensitiveKindRaw)
        #expect(sensitive.isBuiltIn == true)

        let capability = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.CapabilityRecord>()).first
        )
        #expect(capability.id == SchemaV3Fixture.capabilityID)
        #expect(capability.capabilityRaw == SchemaV3Fixture.capabilityRaw)
        #expect(capability.stateRaw == SchemaV3Fixture.capabilityStateRaw)
        #expect(capability.educationShownAt == nil)

        let pointers = try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>())
        #expect(pointers.count == 1)
        #expect(pointers.first?.task?.id == SchemaV3Fixture.taskID)
    }

    @Test(
        "opening the v3 copy never touches the fixture in the bundle",
        .enabled(if: !SchemaV1Fixture.isRecording)
    )
    @MainActor
    func openingTheVersionThreeCopyDoesNotMutateTheFixture() throws {
        let source = try SchemaV3Fixture.url()
        let before = try Data(contentsOf: source)

        let url = try SchemaV3Fixture.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let container = try FocusStore.makeContainer(kind: .temporary(url))
        _ = try container.mainContext.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>())

        let after = try Data(contentsOf: source)
        #expect(before == after, "the v3 fixture test mutated its own fixture")
    }

    /// Records the v3 fixture in the source tree, so whichever epic bumps the schema next has
    /// a real source. Runs only under `FOCUS_FIXTURE_RECORD=1`.
    ///
    /// v3 is what `FocusStore` opens, so this one may use the ordinary container — unlike the
    /// v1 and v2 recorders, which have to pin their version or they would overwrite their own
    /// migration source with a newer file.
    @Test(
        "re-record the committed v3 fixture",
        .enabled(if: SchemaV1Fixture.isRecording)
    )
    @MainActor
    func recordVersionThreeFixture() throws {
        let staging = FileManager.default.temporaryDirectory
            .appending(path: "focus-fixture-v3-record-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let stagedStore = staging.appending(
            path: SchemaV3Fixture.storeName,
            directoryHint: .notDirectory
        )

        do {
            let container = try FocusStore.makeContainer(kind: .temporary(stagedStore))
            try SchemaV3Fixture.populate(container.mainContext)
        }
        // Container released: the store is closed and its sidecars are on disk.

        let destination = SchemaV3Fixture.recordDestination
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in FocusStore.storeFileNames(for: SchemaV3Fixture.storeName) {
            let from = staging.appending(path: name, directoryHint: .notDirectory)
            let to = destination.appending(path: name, directoryHint: .notDirectory)
            if FileManager.default.fileExists(atPath: to.path) {
                try FileManager.default.removeItem(at: to)
            }
            if FileManager.default.fileExists(atPath: from.path) {
                try FileManager.default.copyItem(at: from, to: to)
            }
        }

        print("RE-RECORDED SCHEMA V3 FIXTURE AT \(destination.path)")
        #expect(
            FileManager.default.fileExists(
                atPath: destination.appending(path: SchemaV3Fixture.storeName).path
            )
        )
    }
}
