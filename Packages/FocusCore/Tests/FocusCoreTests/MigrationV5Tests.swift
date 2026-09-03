import Foundation
import SwiftData
import Testing

@testable import FocusCore

/// The v4 → v5 migration, and the row the Intervention pane's three settings had never had
/// (focus-z7g, focus-40i).
///
/// **Every assertion about persistence here closes and reopens a store on disk.** That is not
/// belt-and-braces: the defect this schema exists to end survived because its only proof set a
/// value and read it back **in the same process**, which a plain in-memory property satisfies
/// perfectly. A round-trip that never crosses a container boundary cannot tell a stored setting
/// from a remembered one, so none of these do.
@Suite("Schema v5 migration")
struct MigrationV5Tests {
    static let timestamp = Date(timeIntervalSince1970: 1_767_225_600)
    static let window = QuietHoursWindow(startMinuteOfDay: 22 * 60, endMinuteOfDay: 7 * 60)

    /// A writable directory holding a store this test owns.
    static func temporaryStoreURL() -> URL {
        let directory = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            .appending(path: "focus-v5-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: FocusStore.storeFileName, directoryHint: .notDirectory)
    }

    /// v5's own link in the chain. The plan's **tip** — the count of schemas and stages, and the
    /// version `FocusStore` opens at — moved to `MigrationV6Tests` with the version that owns it;
    /// what stays here is that v5 is still the fifth link, which is what every assertion below
    /// about a v5 row rests on.
    @Test("v5 is the fifth link in the chain")
    func planShape() {
        #expect(FocusSchemaV5.versionIdentifier == Schema.Version(5, 0, 0))
        #expect(FocusMigrationPlan.schemas.count >= 5)
        #expect(FocusMigrationPlan.schemas[4] is FocusSchemaV5.Type)
    }

    /// **v5 adds one entity and re-declares none**, which is what makes the stage lightweight
    /// honestly rather than by assertion.
    @Test("v5 is v4's twelve models plus exactly one")
    func versionFiveIsAdditive() {
        #expect(FocusSchemaV5.models.count == 13)

        let names = Set(FocusSchemaV5.models.map { String(describing: $0) })
        let priorNames = Set(FocusSchemaV4.models.map { String(describing: $0) })
        #expect(names.isSuperset(of: priorNames), "v5 dropped an entity v4 had")
        #expect(names.subtracting(priorNames) == ["NudgePreferencesRecord"])

        for model in FocusSchemaV4.models {
            #expect(
                FocusSchemaV5.models.contains(where: { $0 == model }),
                "\(model) was re-declared rather than reused"
            )
        }
    }

    /// The committed **v3** fixture, opened by today's store: every prior row intact and the
    /// new table present and empty — not missing, which is what a failed stage looks like.
    @Test(
        "the committed v3 fixture opens under v5 with the preferences table present and empty",
        .enabled(if: !SchemaV1Fixture.isRecording)
    )
    @MainActor
    func versionThreeFixtureOpensUnderVersionFive() throws {
        let url = try SchemaV3Fixture.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let container = try FocusStore.makeContainer(kind: .temporary(url))
        let context = container.mainContext

        let task = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>()).first
        )
        #expect(task.id == SchemaV3Fixture.taskID)

        let settings = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.AppSettingsRecord>()).first
        )
        #expect(settings.appearancePreference == .dark)

        #expect(try context.fetch(FetchDescriptor<FocusSchemaV5.NudgePreferencesRecord>()).isEmpty)
        // …and a store with no row answers the shipped defaults rather than nothing.
        #expect(FocusStore.interventionPreferences(in: context) == .defaults)
    }

    /// The whole chain, in one open: a **v1** file across all four stages, with the active
    /// priority the custom stage carries still there at the end of it.
    @Test(
        "the committed v1 fixture migrates through all four stages to v5",
        .enabled(if: !SchemaV1Fixture.isRecording)
    )
    @MainActor
    func versionOneFixtureMigratesThroughFourStages() throws {
        let url = try SchemaV1Fixture.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let container = try FocusStore.makeContainer(kind: .temporary(url))
        let context = container.mainContext

        let pointers = try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>())
        #expect(pointers.count == 1, "the active priority did not survive the four-stage chain")
        #expect(pointers.first?.task?.id == SchemaV1Fixture.taskID)

        #expect(try context.fetch(FetchDescriptor<FocusSchemaV5.NudgePreferencesRecord>()).isEmpty)
    }

    /// **The claim the whole schema exists for**: what a person set is still set after the
    /// process that set it is gone.
    @Test("all three preferences survive closing and reopening the store")
    @MainActor
    func preferencesSurviveAReopen() throws {
        let url = Self.temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let container = try FocusStore.makeContainer(kind: .temporary(url))
            try FocusStore.setInterventionPreferences(
                InterventionPreferences(
                    voice: .warm,
                    reducedInterruption: true,
                    quietHours: Self.window
                ),
                in: container.mainContext,
                now: Self.timestamp
            )
        }

        let reopened = try FocusStore.makeContainer(kind: .temporary(url))
        let read = FocusStore.interventionPreferences(in: reopened.mainContext)
        #expect(read.voice == .warm)
        #expect(read.reducedInterruption == true)
        #expect(read.quietHours == Self.window)
    }

    /// Each named verb writes its own field and leaves the other two exactly as they were —
    /// across a reopen, because a partial write is only visible once the reader is a new one.
    @Test("each named verb writes its own field and no other")
    @MainActor
    func namedVerbsAreNarrow() throws {
        let url = Self.temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let container = try FocusStore.makeContainer(kind: .temporary(url))
            let context = container.mainContext
            try FocusStore.setNudgeVoice(.direct, in: context, now: Self.timestamp)
            try FocusStore.setReducedInterruption(true, in: context, now: Self.timestamp)
            try FocusStore.setQuietHours(Self.window, in: context, now: Self.timestamp)
        }

        do {
            let container = try FocusStore.makeContainer(kind: .temporary(url))
            let context = container.mainContext
            let read = FocusStore.interventionPreferences(in: context)
            #expect(read.voice == .direct)
            #expect(read.reducedInterruption == true)
            #expect(read.quietHours == Self.window)

            // Turning the window off must not un-choose the deck or the flag.
            try FocusStore.setQuietHours(nil, in: context, now: Self.timestamp)
        }

        let reopened = try FocusStore.makeContainer(kind: .temporary(url))
        let read = FocusStore.interventionPreferences(in: reopened.mainContext)
        #expect(read.quietHours == nil)
        #expect(read.voice == .direct)
        #expect(read.reducedInterruption == true)
    }

    /// The row is a singleton by convention, and many writes must not make many rows.
    @Test("repeated writes reuse one row")
    @MainActor
    func writesReuseOneRow() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        for voice in NudgeVoice.allCases {
            try FocusStore.setNudgeVoice(voice, in: context, now: Self.timestamp)
        }

        let rows = try context.fetch(FetchDescriptor<FocusSchemaV5.NudgePreferencesRecord>())
        #expect(rows.count == 1)
        #expect(rows.first?.voice == NudgeVoice.allCases.last)
    }

    /// A window with one boundary is not half a window — the app would have to invent the
    /// other — so a row holding one is read as no window at all.
    @Test("a half-written window reads as no window")
    @MainActor
    func halfWrittenWindowIsNoWindow() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        let row = FocusSchemaV5.NudgePreferencesRecord(touchedAt: Self.timestamp)
        row.quietHoursStartMinuteOfDay = Self.window.startMinuteOfDay
        context.insert(row)
        try context.save()

        #expect(row.quietHours == nil)
        #expect(FocusStore.interventionPreferences(in: context).quietHours == nil)
    }

    /// Every deck round-trips through its raw value, and a raw value this build cannot read
    /// makes the app speak in its default voice rather than crash or reinterpret a deck.
    @Test("the voice decodes exhaustively", arguments: NudgeVoice.allCases)
    func voiceDecodes(_ voice: NudgeVoice) {
        #expect(NudgeVoice.decode(voice.rawValue) == voice)
    }

    @Test("an unreadable voice decodes to the shipped deck")
    func unreadableVoiceDecodes() {
        #expect(NudgeVoice.decode("") == .standard)
        #expect(NudgeVoice.decode("shouty") == .standard)
    }
}
