import Foundation
import SwiftData
import Testing

@testable import FocusCore

/// The known contents of the committed **v7** store fixture.
///
/// Recorded with the same `FOCUS_FIXTURE_RECORD=1` mechanism the v1, v2 and v3 fixtures use, and
/// for the same reason: whichever epic bumps the schema next needs a genuine v7 artefact to
/// migrate from, rather than one written by whatever the schema happens to be on the day the
/// test runs. The review of the e09 plan asked for exactly this and named the gap — v4, v5 and
/// v6 have none, so the chain has only ever been proved from v3 down.
///
/// **v4, v5 and v6 are still missing and are not recorded here.** Each would need a plan pinned
/// to that version — a `SchemaV4OnlyPlan` and two more, in the shape of `SchemaV1OnlyPlan` —
/// because `FocusStore` would migrate the file on the way out and write a v7 store into a
/// directory named for an older one. That is real work with no reader today: nothing migrates
/// *from* v4, v5 or v6 except through the v1 and v3 fixtures that already cross those stages.
/// The v7 fixture is cheap for the opposite reason — v7 is what `FocusStore` opens — and it is
/// the one a future epic will actually need.
///
/// It deliberately carries an `InterventionRecord` with the v7 column **set**, so a later
/// version can tell a stored explanation from an absent one across its own stage.
enum SchemaV7Fixture {
    static let subdirectory = "Resources/SchemaV7"
    static let storeName = FocusStore.storeFileName

    static let taskID = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
    static let recordID = UUID(uuidString: "70707070-7070-4070-8070-707070707070")!
    static let questionID = UUID(uuidString: "71717171-7171-4171-8171-717171717171")!
    static let settingsID = UUID(uuidString: "72727272-7272-4272-8272-727272727272")!

    /// 2026-01-01T00:00:00Z — the same reference instant every other fixture uses.
    static let timestamp = Date(timeIntervalSince1970: 1_767_225_600)

    static let taskIntent = "Say what the app did, and why"
    static let localDayKey = "2026-01-01"
    static let recordSubject = "https://news.example"
    static let recordExplanationKinds: [ExplanationClauseKind] = [.userRule, .sustainedDwell]
    static let questionSubject = "com.chrismitchelmore.FocusDecoy2"
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
            "the committed v7 store fixture is not in the test bundle"
        )
    }

    static func copyToTemporaryDirectory() throws -> URL {
        let source = try url()
        let sourceDirectory = source.deletingLastPathComponent()
        let destinationDirectory = FileManager.default.temporaryDirectory
            .appending(path: "focus-fixture-v7-\(UUID().uuidString)", directoryHint: .isDirectory)
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

    /// Insert the known rows into a v7 context. Used when re-recording and when reading back.
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

        let record = FocusSchemaV7.InterventionRecord(
            id: recordID,
            at: timestamp,
            localDayKey: localDayKey,
            kindRaw: InterruptionKind.accusation.rawValue,
            rungRaw: LadderRung.Kind.panel.rawValue,
            subject: recordSubject,
            subjectKindRaw: RuleSubjectKind.domain.rawValue,
            priorityID: taskID,
            surfaceRaw: NudgeSurface.panel.rawValue,
            dispositionRaw: InterventionDisposition.delivered.rawValue,
            outcomeRaw: InterventionOutcome.corrected.rawValue
        )
        record.explanationKinds = recordExplanationKinds
        context.insert(record)

        context.insert(
            FocusSchemaV4.AskedQuestion(
                id: questionID,
                priorityID: taskID,
                subjectKindRaw: RuleSubjectKind.app.rawValue,
                subject: questionSubject,
                reasonRaw: QueryableUncertainty.noNegativeBasis.rawValue,
                askedAt: timestamp,
                outcomeRaw: AskedQuestionOutcome.answeredRelevant.rawValue,
                answeredAt: timestamp
            )
        )

        context.insert(
            FocusSchemaV3.AppSettingsRecord(
                id: settingsID,
                appearancePreferenceRaw: appearancePreferenceRaw,
                schemaTouchedAt: timestamp
            )
        )
        try context.save()
    }
}

/// The v6 → v7 migration, and the one column it exists for (focus-tee.3).
///
/// **What this suite owns that no earlier one can**: the plan's tip — how long the chain is now
/// — and the *narrower* additive invariant. v4, v5 and v6 each assert "re-declares none" about
/// themselves and each of those readings is still true; v7 is the first version since v2 that
/// re-declares anything, so the claim it can honestly make is the one below: **exactly one class
/// re-declared, named, and the delta is exactly one property.** That is a stronger statement
/// than "additive", not a weaker one — it says which class and how much.
@Suite("Schema v7 migration")
struct MigrationV7Tests {
    static let timestamp = Date(timeIntervalSince1970: 1_767_225_600)

    static func temporaryStoreURL() -> URL {
        let directory = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            .appending(path: "focus-v7-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: FocusStore.storeFileName, directoryHint: .notDirectory)
    }

    @MainActor
    static func makeLog(now: Date = MigrationV7Tests.timestamp) throws
        -> (log: InterventionLog, container: ModelContainer) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let container = try FocusStore.makeContainer(kind: .inMemory)
        return (
            InterventionLog(
                context: container.mainContext,
                dateProvider: FixedDateProvider(now: now),
                calendar: calendar
            ),
            container
        )
    }

    /// v7's place in the plan. The **tip** — how long the chain is and what the store opens —
    /// moved to `MigrationV8Tests` when v8 arrived, for the reason it was here in the first
    /// place: the newest version's suite owns it, or two suites drift apart about it.
    @Test("v7 is the seventh schema and the sixth stage's destination")
    func planShape() {
        #expect(FocusSchemaV7.versionIdentifier == Schema.Version(7, 0, 0))
        #expect(FocusMigrationPlan.schemas[6] is FocusSchemaV7.Type)
    }

    /// **Exactly one class re-declared, and exactly one property of difference.**
    ///
    /// The narrower invariant, in place of the "re-declares none" one v4, v5 and v6 keep for
    /// themselves. Read from the SwiftData `Schema` on both sides rather than from a list
    /// written here, so a second column added to the re-declared class fails this without
    /// anybody remembering to update a number.
    @Test("v7 re-declares InterventionRecord, alone, and adds one optional property to it")
    func versionSevenReDeclaresExactlyOne() {
        #expect(FocusSchemaV7.models.count == FocusSchemaV6.models.count)

        let names = Set(FocusSchemaV7.models.map { String(describing: $0) })
        let priorNames = Set(FocusSchemaV6.models.map { String(describing: $0) })
        #expect(names == priorNames, "v7 changed the set of entities, not just one declaration")

        // The re-declared classes, by object identity rather than by name.
        let reused = FocusSchemaV6.models.filter { prior in
            FocusSchemaV7.models.contains { $0 == prior }
        }
        let reDeclared = FocusSchemaV6.models.filter { prior in
            !FocusSchemaV7.models.contains { $0 == prior }
        }
        #expect(reDeclared.count == 1, "v7 re-declared more than one class")
        #expect(reDeclared.map { String(describing: $0) } == ["InterventionRecord"])
        #expect(reused.count == FocusSchemaV6.models.count - 1)

        // And the delta on that one class is one property, whose name is the reason v7 exists.
        let before = Schema(versionedSchema: FocusSchemaV6.self)
        let after = Schema(versionedSchema: FocusSchemaV7.self)
        let beforeProperties = Set(
            before.entities.first { $0.name == "InterventionRecord" }?
                .properties.map(\.name) ?? []
        )
        let afterProperties = Set(
            after.entities.first { $0.name == "InterventionRecord" }?
                .properties.map(\.name) ?? []
        )
        #expect(!beforeProperties.isEmpty, "the v6 entity was not found — the reading is vacuous")
        #expect(afterProperties.subtracting(beforeProperties) == ["explanationKindsRaw"])
        #expect(
            beforeProperties.subtracting(afterProperties).isEmpty,
            "v7 removed a column, which no lightweight stage may do"
        )
    }

    /// The whole chain, in one open: a **v3** file across four stages into v7, with the new
    /// column arriving `nil` on a table that was empty and stays present.
    @Test(
        "the committed v3 fixture migrates through every stage to v7",
        .enabled(if: !SchemaV1Fixture.isRecording)
    )
    @MainActor
    func versionThreeFixtureMigratesToSeven() throws {
        let url = try SchemaV3Fixture.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let container = try FocusStore.makeContainer(kind: .temporary(url))
        let context = container.mainContext

        // Everything the earlier build wrote is still there: a stage that lost the store would
        // satisfy the claim below by accident.
        let task = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>()).first
        )
        #expect(task.id == SchemaV3Fixture.taskID)

        // The re-declared table is present and empty — not missing, which is what a failed
        // stage looks like.
        #expect(try context.fetch(FetchDescriptor<FocusSchemaV7.InterventionRecord>()).isEmpty)
    }

    /// **The committed v7 fixture reads back as itself**, including the column this version
    /// exists for. The artefact the next epic will migrate from is only worth having if
    /// something asserts what is in it.
    @Test(
        "the committed v7 fixture opens with its rows and its explanation kinds intact",
        .enabled(if: !SchemaV1Fixture.isRecording)
    )
    @MainActor
    func versionSevenFixtureReadsBack() throws {
        let url = try SchemaV7Fixture.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let container = try FocusStore.makeContainer(kind: .temporary(url))
        let context = container.mainContext

        let record = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV7.InterventionRecord>()).first
        )
        #expect(record.id == SchemaV7Fixture.recordID)
        #expect(record.subject == SchemaV7Fixture.recordSubject)
        // focus-tee.2's column, on a row a build really wrote: an origin stored as an origin.
        #expect(record.subjectKind == .domain)
        #expect(record.explanationKinds == SchemaV7Fixture.recordExplanationKinds)
        #expect(record.outcome == .corrected)

        let question = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV4.AskedQuestion>()).first
        )
        #expect(question.subject == SchemaV7Fixture.questionSubject)
        #expect(question.reason == .noNegativeBasis)
    }

    /// **"Not recorded" and "no clauses" are two different facts**, and only a reopen can tell a
    /// stored one from a remembered one.
    ///
    /// `nil` is every row written before v7 and every path that had no explanation to hand;
    /// `[]` would be a verdict that carried none. History says different things about them, so
    /// the encoding has to keep them apart — the same rule `openWindowsAtLastQuit` follows.
    @Test("an unrecorded explanation and an empty one survive a reopen as different values")
    @MainActor
    func absenceAndEmptinessAreDifferent() throws {
        let url = Self.temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let absent = UUID()
        let empty = UUID()
        let full = UUID()

        do {
            let container = try FocusStore.makeContainer(kind: .temporary(url))
            let context = container.mainContext
            for (id, kinds) in [
                (absent, [ExplanationClauseKind]?.none),
                (empty, []),
                (full, [.tokenOverlap, .similarityCorroborated])
            ] {
                let row = FocusSchemaV7.InterventionRecord(
                    id: id,
                    at: Self.timestamp,
                    localDayKey: "2026-01-01",
                    kindRaw: InterruptionKind.accusation.rawValue,
                    subject: "com.example.app",
                    subjectKindRaw: RuleSubjectKind.app.rawValue,
                    surfaceRaw: NudgeSurface.panel.rawValue,
                    dispositionRaw: InterventionDisposition.delivered.rawValue
                )
                row.explanationKinds = kinds
                context.insert(row)
            }
            try context.save()
        }

        let reopened = try FocusStore.makeContainer(kind: .temporary(url))
        let rows = try reopened.mainContext
            .fetch(FetchDescriptor<FocusSchemaV7.InterventionRecord>())
        func kinds(_ id: UUID) throws -> [ExplanationClauseKind]? {
            try #require(rows.first { $0.id == id }).explanationKinds
        }
        #expect(try kinds(absent) == nil)
        #expect(try kinds(empty) == [])
        #expect(try kinds(full) == [.tokenOverlap, .similarityCorroborated])
        // And the raw column keeps the distinction too, which is where it actually lives.
        #expect(try #require(rows.first { $0.id == absent }).explanationKindsRaw == nil)
        #expect(try #require(rows.first { $0.id == empty }).explanationKindsRaw == "")
    }

    /// **Every clause kind round-trips, and the fold is over the enum rather than a list.**
    ///
    /// A decoder written as a switch is a decoder that can lose a case in a rename. The fold
    /// asks the enum what its cases are, so a sixteenth added tomorrow fails here until its
    /// literal is written down.
    @Test("every explanation clause kind survives the column in both directions")
    @MainActor
    func everyClauseKindRoundTrips() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        let row = FocusSchemaV7.InterventionRecord(
            at: Self.timestamp,
            localDayKey: "2026-01-01",
            kindRaw: InterruptionKind.accusation.rawValue,
            subject: "com.example.app",
            subjectKindRaw: RuleSubjectKind.app.rawValue,
            surfaceRaw: NudgeSurface.panel.rawValue,
            dispositionRaw: InterventionDisposition.delivered.rawValue
        )
        row.explanationKinds = ExplanationClauseKind.allCases
        context.insert(row)
        try context.save()

        #expect(row.explanationKinds == ExplanationClauseKind.allCases)
        for kind in ExplanationClauseKind.allCases {
            #expect(
                ExplanationClauseKind.decodeIfKnown(kind.rawValue) == kind,
                "\(kind.rawValue) does not decode to itself"
            )
        }
        #expect(!ExplanationClauseKind.allCases.isEmpty)
    }

    /// **A clause kind this build has never heard of is dropped, not guessed.**
    ///
    /// Unlike every other raw column in this store there is no safe default: each kind is bound
    /// to one catalog key, so inventing a case for an unknown string would put a sentence in
    /// front of somebody that no build ever meant. The quiet answer is to say nothing about that
    /// clause and keep the ones this build does understand.
    @Test("an unreadable clause kind is dropped and the readable ones survive beside it")
    @MainActor
    func anUnknownClauseKindIsDropped() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        let row = FocusSchemaV7.InterventionRecord(
            at: Self.timestamp,
            localDayKey: "2026-01-01",
            kindRaw: InterruptionKind.accusation.rawValue,
            subject: "com.example.app",
            subjectKindRaw: RuleSubjectKind.app.rawValue,
            surfaceRaw: NudgeSurface.panel.rawValue,
            dispositionRaw: InterventionDisposition.delivered.rawValue,
            explanationKindsRaw: "userRule,notchResonance,sustainedDwell"
        )
        context.insert(row)
        try context.save()

        #expect(row.explanationKinds == [.userRule, .sustainedDwell])
        #expect(ExplanationClauseKind.decodeIfKnown("notchResonance") == nil)
    }

    /// The log writes the column, and the row it writes is the one the day filter returns.
    @Test("an event carrying clause kinds stores them and reads them back off the day")
    @MainActor
    func theLogWritesTheColumn() throws {
        let (log, container) = try Self.makeLog()
        _ = container

        let id = try log.record(
            InterventionEvent(
                kind: .accusation,
                rung: .panel,
                subject: "com.example.app",
                surface: .panel,
                disposition: .delivered,
                explanationKinds: [.userRule, .sustainedDwell]
            ),
            priorityID: UUID()
        )

        let row = try #require(try log.records(on: log.today).first { $0.id == id })
        #expect(row.explanationKinds == [.userRule, .sustainedDwell])

        // An event that carried none stores `nil` — the app did not record why, and the column
        // says so rather than claiming the verdict had no reasons.
        let silent = try log.record(
            InterventionEvent(
                kind: .accusation,
                rung: .ambient,
                subject: "com.example.app",
                surface: .menuBar,
                disposition: .delivered
            ),
            priorityID: UUID()
        )
        #expect(try #require(try log.all().first { $0.id == silent }).explanationKinds == nil)
    }

    /// Records the v7 fixture in the source tree, so whichever epic bumps the schema next has a
    /// real source. Runs only under `FOCUS_FIXTURE_RECORD=1`.
    ///
    /// v7 is what `FocusStore` opens, so this may use the ordinary container — unlike the v1 and
    /// v2 recorders, which have to pin their version or they would overwrite their own migration
    /// source with a newer file.
    @Test(
        "re-record the committed v7 fixture",
        .enabled(if: SchemaV1Fixture.isRecording)
    )
    @MainActor
    func recordVersionSevenFixture() throws {
        let staging = FileManager.default.temporaryDirectory
            .appending(
                path: "focus-fixture-v7-record-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let stagedStore = staging.appending(
            path: SchemaV7Fixture.storeName,
            directoryHint: .notDirectory
        )

        do {
            let container = try FocusStore.makeContainer(kind: .temporary(stagedStore))
            try SchemaV7Fixture.populate(container.mainContext)
        }
        // Container released: the store is closed and its sidecars are on disk.

        let destination = SchemaV7Fixture.recordDestination
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in FocusStore.storeFileNames(for: SchemaV7Fixture.storeName) {
            let from = staging.appending(path: name, directoryHint: .notDirectory)
            let to = destination.appending(path: name, directoryHint: .notDirectory)
            if FileManager.default.fileExists(atPath: to.path) {
                try FileManager.default.removeItem(at: to)
            }
            if FileManager.default.fileExists(atPath: from.path) {
                try FileManager.default.copyItem(at: from, to: to)
            }
        }

        print("RE-RECORDED SCHEMA V7 FIXTURE AT \(destination.path)")
        #expect(
            FileManager.default.fileExists(
                atPath: destination.appending(path: SchemaV7Fixture.storeName).path
            )
        )
    }
}
