import Foundation
import SwiftData
import Testing

@testable import FocusCore

/// The v5 → v6 migration, and the three facts the shell had nowhere to remember (focus-odz.4,
/// focus-odz.6, focus-odz.7).
///
/// **The claim this suite exists for is the one that cannot be made any other way**: a store the
/// app has never opened is owed a first-run explanation, and a store carried forward from an
/// earlier version is not. Those two are indistinguishable by the absence of a row, so the stage
/// writes the distinction down — and the only way to hold that is to open a **committed fixture**
/// of an older store and a **new** store and read the difference.
///
/// Every assertion about persistence closes and reopens a store on disk, for `MigrationV5Tests`'
/// reason: a round trip that never crosses a container boundary cannot tell a stored fact from a
/// remembered one.
@Suite("Schema v6 migration")
struct MigrationV6Tests {
    static let timestamp = Date(timeIntervalSince1970: 1_767_225_600)

    /// A writable directory holding a store this test owns.
    static func temporaryStoreURL() -> URL {
        let directory = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            .appending(path: "focus-v6-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: FocusStore.storeFileName, directoryHint: .notDirectory)
    }

    /// **The plan's tip**, which the newest version's suite owns: the older ones assert their own
    /// link and nothing about how long the chain has become.
    @Test("the plan's newest schema is v6, and it is the fifth stage")
    func planShape() {
        #expect(FocusSchemaV6.versionIdentifier == Schema.Version(6, 0, 0))
        #expect(FocusMigrationPlan.schemas.count == 6)
        #expect(FocusMigrationPlan.schemas[5] is FocusSchemaV6.Type)
        #expect(FocusMigrationPlan.stages.count == 5)
        #expect(FocusStore.schema.version == Schema.Version(6, 0, 0))
    }

    /// **v6 adds one entity and re-declares none**, which is what keeps every existing call site
    /// fetching the entity it already knew.
    @Test("v6 is v5's thirteen models plus exactly one")
    func versionSixIsAdditive() {
        #expect(FocusSchemaV6.models.count == 14)

        let names = Set(FocusSchemaV6.models.map { String(describing: $0) })
        let priorNames = Set(FocusSchemaV5.models.map { String(describing: $0) })
        #expect(names.isSuperset(of: priorNames), "v6 dropped an entity v5 had")
        #expect(names.subtracting(priorNames) == ["ShellStateRecord"])

        for model in FocusSchemaV5.models {
            #expect(
                FocusSchemaV6.models.contains(where: { $0 == model }),
                "\(model) was re-declared rather than reused"
            )
        }
    }

    /// **The whole point of the custom stage.**
    ///
    /// A committed **v3** fixture is a store an earlier build really wrote. Opened by today's
    /// build it runs three lightweight stages and then this one, and comes out with the row
    /// already stamped: the explanation is not owed to somebody who has been using the app.
    @Test(
        "a store carried forward from an earlier version is never owed the first-run explanation",
        .enabled(if: !SchemaV1Fixture.isRecording)
    )
    @MainActor
    func migratedStoresOweNoFirstRunScreen() throws {
        let url = try SchemaV3Fixture.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let container = try FocusStore.makeContainer(kind: .temporary(url))
        let context = container.mainContext

        // Everything the earlier version wrote is still there — a stage that lost the store would
        // satisfy the claim below by accident.
        let task = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>()).first
        )
        #expect(task.id == SchemaV3Fixture.taskID)

        let state = FocusStore.shellState(in: context)
        #expect(state.firstRunExplanationShownAt != nil)
        #expect(!state.owesFirstRunExplanation)
        // The other two are genuinely things that have never happened for an upgrading store, and
        // are left alone: pretending otherwise would withhold a feature rather than protect
        // anybody from a screen.
        #expect(state.launchAtLoginOfferedAt == nil)
        #expect(state.openWindowsAtLastQuit == nil)
    }

    /// The other half, and the reading is only worth anything beside the one above: a store this
    /// build creates has run no stage, holds no row, and **is** owed the explanation.
    @Test("a store this build created is owed the first-run explanation exactly once")
    @MainActor
    func freshStoresOweTheFirstRunScreen() throws {
        let url = Self.temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let container = try FocusStore.makeContainer(kind: .temporary(url))
            let context = container.mainContext
            #expect(FocusStore.shellStateRow(in: context) == nil, "a fresh store ran a stage")
            #expect(FocusStore.shellState(in: context) == .neverUsed)
            #expect(FocusStore.shellState(in: context).owesFirstRunExplanation)

            try FocusStore.recordFirstRunExplanationShown(in: context, now: Self.timestamp)
        }

        // Reopened — a different container, which is the only reader that can tell a stored fact
        // from a remembered one.
        let reopened = try FocusStore.makeContainer(kind: .temporary(url))
        let state = FocusStore.shellState(in: reopened.mainContext)
        #expect(state.firstRunExplanationShownAt == Self.timestamp)
        #expect(!state.owesFirstRunExplanation)
    }

    /// The stamp answers *"has it been shown?"*, so a second showing must not move it to the one
    /// day it must be impossible for it to be.
    @Test("recording the explanation twice does not move the date")
    @MainActor
    func theStampIsNeverRewritten() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        try FocusStore.recordFirstRunExplanationShown(in: context, now: Self.timestamp)
        try FocusStore.recordFirstRunExplanationShown(
            in: context,
            now: Self.timestamp.addingTimeInterval(86_400)
        )
        #expect(FocusStore.shellState(in: context).firstRunExplanationShownAt == Self.timestamp)
    }

    /// The same rule for the offer: D-12 says it is made once, so the date is the record of the
    /// once and not of the last time.
    @Test("recording the launch-at-login offer twice does not move the date")
    @MainActor
    func theOfferStampIsNeverRewritten() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        #expect(!FocusStore.shellState(in: context).hasOfferedLaunchAtLogin)
        try FocusStore.recordLaunchAtLoginOffered(in: context, now: Self.timestamp)
        try FocusStore.recordLaunchAtLoginOffered(
            in: context,
            now: Self.timestamp.addingTimeInterval(3_600)
        )
        let state = FocusStore.shellState(in: context)
        #expect(state.launchAtLoginOfferedAt == Self.timestamp)
        #expect(state.hasOfferedLaunchAtLogin)
    }

    /// **"Nothing recorded" and "everything was closed" are two different facts**, and the app
    /// acts differently on them: the first leaves the scene graph alone, the second is a person
    /// who had shut every window.
    @Test("an unrecorded window list and an empty one survive a reopen as different values")
    @MainActor
    func theWindowListDistinguishesAbsenceFromEmptiness() throws {
        let url = Self.temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let container = try FocusStore.makeContainer(kind: .temporary(url))
            #expect(FocusStore.shellState(in: container.mainContext).openWindowsAtLastQuit == nil)
            try FocusStore.recordOpenWindows([], in: container.mainContext, now: Self.timestamp)
        }
        do {
            let container = try FocusStore.makeContainer(kind: .temporary(url))
            #expect(FocusStore.shellState(in: container.mainContext).openWindowsAtLastQuit == [])
            try FocusStore.recordOpenWindows(
                ["help", "cockpit"],
                in: container.mainContext,
                now: Self.timestamp
            )
        }

        let reopened = try FocusStore.makeContainer(kind: .temporary(url))
        // Sorted on the way in, so the stored order is a fact about the set rather than about the
        // order AppKit happened to list the windows in.
        #expect(
            FocusStore.shellState(in: reopened.mainContext).openWindowsAtLastQuit
                == ["cockpit", "help"]
        )
    }

    /// Each named verb writes its own field and leaves the other two exactly as they were, which
    /// is only visible once the reader is a new one.
    @Test("each named verb writes its own field and no other")
    @MainActor
    func namedVerbsAreNarrow() throws {
        let url = Self.temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            // The container is held in a local, never used as a temporary: a `ModelContext` read
            // off a container nobody retains outlives the thing that owns its coordinator.
            let container = try FocusStore.makeContainer(kind: .temporary(url))
            let context = container.mainContext
            try FocusStore.recordFirstRunExplanationShown(in: context, now: Self.timestamp)
            try FocusStore.recordLaunchAtLoginOffered(in: context, now: Self.timestamp)
            try FocusStore.recordOpenWindows(["cockpit"], in: context, now: Self.timestamp)
        }

        let reopened = try FocusStore.makeContainer(kind: .temporary(url))
        let context = reopened.mainContext
        var state = FocusStore.shellState(in: context)
        #expect(state.firstRunExplanationShownAt == Self.timestamp)
        #expect(state.launchAtLoginOfferedAt == Self.timestamp)
        #expect(state.openWindowsAtLastQuit == ["cockpit"])

        // Recording a different window list must not un-show the explanation or un-make the offer.
        try FocusStore.recordOpenWindows(["cockpit", "help"], in: context, now: Self.timestamp)
        state = FocusStore.shellState(in: context)
        #expect(state.openWindowsAtLastQuit == ["cockpit", "help"])
        #expect(state.firstRunExplanationShownAt == Self.timestamp)
        #expect(state.launchAtLoginOfferedAt == Self.timestamp)
    }

    /// The row is a singleton by convention, and many writes must not make many rows.
    @Test("repeated writes reuse one row")
    @MainActor
    func writesReuseOneRow() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        for identifier in ["cockpit", "help", "cockpit"] {
            try FocusStore.recordOpenWindows([identifier], in: context, now: Self.timestamp)
        }

        let rows = try context.fetch(FetchDescriptor<FocusSchemaV6.ShellStateRecord>())
        #expect(rows.count == 1)
        #expect(rows.first?.openWindowsAtLastQuit == ["cockpit"])
    }

    /// The whole chain, in one open: a **v1** file across all five stages, with the active
    /// priority the first custom stage carries still there and the last custom stage's row written.
    @Test(
        "the committed v1 fixture migrates through all five stages to v6",
        .enabled(if: !SchemaV1Fixture.isRecording)
    )
    @MainActor
    func versionOneFixtureMigratesThroughFiveStages() throws {
        let url = try SchemaV1Fixture.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let container = try FocusStore.makeContainer(kind: .temporary(url))
        let context = container.mainContext

        let pointers = try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>())
        #expect(pointers.count == 1, "the active priority did not survive the five-stage chain")
        #expect(pointers.first?.task?.id == SchemaV1Fixture.taskID)

        #expect(!FocusStore.shellState(in: context).owesFirstRunExplanation)
    }
}
