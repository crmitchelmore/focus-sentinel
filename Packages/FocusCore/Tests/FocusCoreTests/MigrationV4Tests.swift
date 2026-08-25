import Foundation
import SwiftData
import Testing

@testable import FocusCore

/// The v3 → v4 migration, the whole chain from v1, and the exhaustive decoders every stored
/// raw value is read through (R-79, R-49, F-139).
///
/// The chain is the claim that matters. A user who has not opened this app since e01 crosses
/// **three** stages on their next launch, and nothing they wrote may be lost on the way — and
/// that is asserted against the **committed** v1 and v3 stores, bytes those builds actually
/// wrote, rather than against fixtures synthesised by today's code, which would prove nothing
/// of the kind.
@Suite("Schema v4 migration")
struct MigrationV4Tests {
    static let priorityID = UUID(uuidString: "12341234-1234-4123-8123-123412341234")!
    static let timestamp = Date(timeIntervalSince1970: 1_767_225_600)

    @Test("the plan declares four schemas and exactly three stages")
    func planShape() {
        #expect(FocusSchemaV4.versionIdentifier == Schema.Version(4, 0, 0))
        #expect(FocusMigrationPlan.schemas.count == 4)
        #expect(FocusMigrationPlan.schemas[0] is FocusSchemaV1.Type)
        #expect(FocusMigrationPlan.schemas[1] is FocusSchemaV2.Type)
        #expect(FocusMigrationPlan.schemas[2] is FocusSchemaV3.Type)
        #expect(FocusMigrationPlan.schemas[3] is FocusSchemaV4.Type)
        #expect(FocusMigrationPlan.stages.count == 3)

        // v1, v2 and v3 are migration sources and must stay exactly as they shipped. A source
        // you have edited is not a source.
        #expect(FocusSchemaV1.models.count == 5)
        #expect(FocusSchemaV2.models.count == 7)
        #expect(FocusSchemaV3.models.count == 10)
    }

    /// **v4 adds two entities and re-declares none.** That is what makes the stage lightweight
    /// honestly rather than by assertion: there is no attribute to carry, no column removed and
    /// no rename, so every existing call site keeps fetching the entity it already knew.
    @Test("v4 is v3's ten models plus exactly two")
    func versionFourIsAdditive() {
        #expect(FocusSchemaV4.models.count == 12)

        let names = Set(FocusSchemaV4.models.map { String(describing: $0) })
        let priorNames = Set(FocusSchemaV3.models.map { String(describing: $0) })
        #expect(names.isSuperset(of: priorNames), "v4 dropped an entity v3 had")
        #expect(names.subtracting(priorNames) == ["AskedQuestion", "InterventionRecord"])

        // The same classes, not copies of them: a re-declared model would fork the type and
        // leave two identical declarations for a reviewer to keep in step by hand.
        for model in FocusSchemaV3.models {
            #expect(
                FocusSchemaV4.models.contains(where: { $0 == model }),
                "\(model) was re-declared rather than reused"
            )
        }
    }

    /// The committed **v3** fixture, opened by today's store: one lightweight stage, every row
    /// intact, and the two new tables present and empty — not missing, which is what a failed
    /// stage would look like.
    @Test(
        "the committed v3 fixture opens under v4 with every prior entity intact",
        .enabled(if: !SchemaV1Fixture.isRecording)
    )
    @MainActor
    func versionThreeFixtureOpensUnderVersionFour() throws {
        let url = try SchemaV3Fixture.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let container = try FocusStore.makeContainer(kind: .temporary(url))
        let context = container.mainContext

        let task = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>()).first
        )
        #expect(task.id == SchemaV3Fixture.taskID)
        #expect(task.intent == SchemaV3Fixture.taskIntent)
        #expect(task.isActive == true)

        let session = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.FocusSessionRecord>()).first
        )
        #expect(session.id == SchemaV3Fixture.sessionID)
        #expect(session.phaseRaw == SchemaV3Fixture.sessionPhaseRaw)
        #expect(session.uptimeAnchorSeconds == SchemaV3Fixture.sessionUptimeAnchorSeconds)
        #expect(session.bootIdentity == SchemaV3Fixture.sessionBootIdentity)
        #expect(session.pauseCausesRaw == SchemaV3Fixture.sessionPauseCausesRaw)
        #expect(session.transitions.count == 1)
        #expect(session.transitions.first?.id == SchemaV3Fixture.transitionID)

        let event = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.ActivityEvent>()).first
        )
        #expect(event.id == SchemaV3Fixture.eventID)
        #expect(event.dwellSeconds == SchemaV3Fixture.eventDwellSeconds)
        #expect(event.displayID == SchemaV3Fixture.eventDisplayID)

        let sensitive = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.SensitiveAppEntry>()).first
        )
        #expect(sensitive.bundleID == SchemaV3Fixture.sensitiveBundleID)
        #expect(sensitive.isBuiltIn == true)

        let capability = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.CapabilityRecord>()).first
        )
        #expect(capability.capabilityRaw == SchemaV3Fixture.capabilityRaw)

        let settings = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.AppSettingsRecord>()).first
        )
        #expect(settings.id == SchemaV3Fixture.settingsID)
        #expect(settings.appearancePreference == .dark)

        let pointers = try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>())
        #expect(pointers.count == 1)
        #expect(pointers.first?.task?.id == SchemaV3Fixture.taskID)

        // The two v4 tables: present and empty.
        #expect(try context.fetch(FetchDescriptor<FocusSchemaV4.AskedQuestion>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FocusSchemaV4.InterventionRecord>()).isEmpty)
    }

    /// The whole chain, in one open: a **v1** file across all three stages.
    @Test(
        "the committed v1 fixture migrates through all three stages to v4",
        .enabled(if: !SchemaV1Fixture.isRecording)
    )
    @MainActor
    func versionOneFixtureMigratesThroughThreeStages() throws {
        let url = try SchemaV1Fixture.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let container = try FocusStore.makeContainer(kind: .temporary(url))
        let context = container.mainContext

        let task = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>()).first
        )
        #expect(task.id == SchemaV1Fixture.taskID)
        #expect(task.intent == SchemaV1Fixture.taskIntent)

        // The v1 → v2 stage's whole reason for being custom, surviving two further stages.
        let pointers = try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>())
        #expect(pointers.count == 1, "the active priority did not survive the three-stage chain")
        #expect(pointers.first?.task?.id == SchemaV1Fixture.taskID)

        #expect(try context.fetch(FetchDescriptor<FocusSchemaV4.AskedQuestion>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FocusSchemaV4.InterventionRecord>()).isEmpty)
    }

    /// Re-opening a store already at v4 must not run a stage again. The v1 → v2 stage is the
    /// dangerous one: if it re-ran, every launch would re-assert a priority the user had
    /// cleared — and now it would also have to leave the two new tables alone.
    @Test(
        "reopening a store already at v4 re-runs no stage and keeps the new rows",
        .enabled(if: !SchemaV1Fixture.isRecording)
    )
    @MainActor
    func reopeningReRunsNoStage() throws {
        let url = try SchemaV3Fixture.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let container = try FocusStore.makeContainer(kind: .temporary(url))
            let context = container.mainContext
            context.insert(Self.receipt())
            context.insert(Self.record())
            try context.save()
        }

        let reopened = try FocusStore.makeContainer(kind: .temporary(url))
        let context = reopened.mainContext

        let receipts = try context.fetch(FetchDescriptor<FocusSchemaV4.AskedQuestion>())
        #expect(receipts.count == 1)
        #expect(receipts.first?.priorityID == Self.priorityID)
        #expect(receipts.first?.outcome == .answeredRelevant)

        let records = try context.fetch(FetchDescriptor<FocusSchemaV4.InterventionRecord>())
        #expect(records.count == 1)
        #expect(records.first?.kind == .accusation)
        #expect(records.first?.disposition == .delivered)

        // …and v3's rows are exactly where they were.
        #expect(try context.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>()).count == 1)
    }

    /// The two new entities round-trip through a real container, with every typed accessor
    /// reading back what it wrote.
    @Test("the receipt and the record round-trip through the store")
    @MainActor
    func newEntitiesRoundTrip() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        context.insert(Self.receipt())
        context.insert(Self.record())
        try context.save()

        let receipt = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV4.AskedQuestion>()).first
        )
        #expect(receipt.priorityID == Self.priorityID)
        #expect(receipt.subject == "com.chrismitchelmore.FocusDecoy2")
        #expect(receipt.subjectKind == .app)
        #expect(receipt.reason == .noNegativeBasis)
        #expect(receipt.outcome == .answeredRelevant)
        #expect(receipt.askedAt == Self.timestamp)
        #expect(receipt.answeredAt == Self.timestamp)

        let record = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV4.InterventionRecord>()).first
        )
        #expect(record.localDayKey == "2026-01-01")
        #expect(record.kind == .accusation)
        #expect(record.rung == .panel)
        #expect(record.surface == .panel)
        #expect(record.disposition == .delivered)
        #expect(record.outcome == .corrected)
        #expect(record.originatingAnswer == nil)
        #expect(record.spendsBudget)

        // Every enum-backed field persists as its **string** raw value, so reordering a Swift
        // enum can never silently reinterpret a stored row (e01's R-05).
        #expect(record.kindRaw == "accusation")
        #expect(record.rungRaw == "panel")
        #expect(record.dispositionRaw == "delivered")
        #expect(receipt.outcomeRaw == "answeredRelevant")
    }

    /// A deferral and a suppression reached no surface, and the record says so rather than
    /// inventing one somebody saw.
    @Test("a record with no surface reads back as no surface, not as the menu bar")
    @MainActor
    func absentSurfaceStaysAbsent() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        let deferred = FocusSchemaV4.InterventionRecord(
            at: Self.timestamp,
            localDayKey: "2026-01-01",
            kindRaw: InterruptionKind.accusation.rawValue,
            rungRaw: LadderRung.Kind.ambient.rawValue,
            subject: "com.chrismitchelmore.FocusDecoy",
            subjectKindRaw: RuleSubjectKind.app.rawValue,
            surfaceRaw: "",
            dispositionRaw: InterventionDisposition.deferred.rawValue
        )
        context.insert(deferred)
        try context.save()

        let stored = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV4.InterventionRecord>()).first
        )
        #expect(stored.surface == nil)
        #expect(stored.disposition == .deferred)
        #expect(!stored.spendsBudget, "a deferred rung spent a cap")

        // …and setting it back to nil keeps the column empty rather than writing "nil".
        stored.surface = .panel
        #expect(stored.surfaceRaw == "panel")
        stored.surface = nil
        #expect(stored.surfaceRaw.isEmpty)
    }

    // MARK: - The decoders

    /// **Every decoder is total over its enum's `allCases`.** A round trip through the raw
    /// value has to be the identity, or a stored row means something other than what wrote it.
    @Test("every raw-value decoder round-trips every case of its enum")
    func decodersAreTotal() {
        for value in RuleSubjectKind.allCases {
            #expect(RuleSubjectKind.decode(value.rawValue) == value)
        }
        for value in QueryableUncertainty.allCases {
            #expect(QueryableUncertainty.decode(value.rawValue) == value)
        }
        for value in AskedQuestionOutcome.allCases {
            #expect(AskedQuestionOutcome.decode(value.rawValue) == value)
        }
        for value in InterruptionKind.allCases {
            #expect(InterruptionKind.decode(value.rawValue) == value)
        }
        for value in LadderRung.Kind.allCases {
            #expect(LadderRung.Kind.decode(value.rawValue) == value)
        }
        for value in NudgeSurface.allCases {
            #expect(NudgeSurface.decode(value.rawValue) == value)
        }
        for value in InterventionDisposition.allCases {
            #expect(InterventionDisposition.decode(value.rawValue) == value)
        }
        for value in InterventionOutcome.allCases {
            #expect(InterventionOutcome.decode(value.rawValue) == value)
        }
        for value in QueryAnswer.allCases {
            #expect(QueryAnswer.decode(value.rawValue) == value)
        }
    }

    /// **An unreadable raw value decodes to a stated default rather than trapping** — and every
    /// default is chosen to make the app quieter rather than louder, except the one that is
    /// deliberately the other way round.
    @Test("an unreadable raw value decodes to its stated default")
    func unreadableValuesDecodeToTheirDefaults() {
        for raw in ["", "  ", "🙂", "somethingAFutureBuildKnew", "TRUE", "0"] {
            #expect(RuleSubjectKind.decode(raw) == .app)
            #expect(QueryableUncertainty.decode(raw) == .noNegativeBasis)
            // Still asked, so still never asked again.
            #expect(AskedQuestionOutcome.decode(raw) == .declined)
            // Spends the shared budget *and* the accusation cap: an unreadable row can never
            // buy the app extra questions.
            #expect(InterruptionKind.decode(raw) == .accusation)
            #expect(LadderRung.Kind.decode(raw) == .ambient)
            #expect(NudgeSurface.decode(raw) == .menuBar)
            // The one default that goes the other way: a row this build cannot read still
            // happened to somebody, and counting it cannot make the app chattier.
            #expect(InterventionDisposition.decode(raw) == .delivered)
            #expect(InterventionOutcome.decode(raw) == .ignored)
            #expect(QueryAnswer.decode(raw) == .notNow)
        }
    }

    /// A row written by a build that knew a case this one does not reads back as the default
    /// through the model's own accessor, not only through the free function.
    @Test("a stored row carrying an unknown case reads back at its default")
    @MainActor
    func unknownStoredCaseReadsBackAtItsDefault() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        let record = FocusSchemaV4.InterventionRecord(
            at: Self.timestamp,
            localDayKey: "2026-01-01",
            kindRaw: "notchPulse",                   // e08's, hypothetically
            rungRaw: "notch",
            subject: "com.chrismitchelmore.FocusDecoy",
            subjectKindRaw: "windowGroup",
            surfaceRaw: "notch",
            dispositionRaw: "swallowed",
            outcomeRaw: "glanced",
            originatingAnswerRaw: "maybe"
        )
        context.insert(record)
        try context.save()

        let stored = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV4.InterventionRecord>()).first
        )
        #expect(stored.kind == .accusation)
        #expect(stored.rung == .ambient)
        #expect(stored.subjectKind == .app)
        #expect(stored.surface == .menuBar)
        #expect(stored.disposition == .delivered)
        #expect(stored.outcome == .ignored)
        #expect(stored.originatingAnswer == .notNow)

        // The stored strings are untouched: a build that does not understand a value must not
        // rewrite it into one it does, or the newer build's data is gone.
        #expect(stored.kindRaw == "notchPulse")
        #expect(stored.rungRaw == "notch")
        #expect(stored.dispositionRaw == "swallowed")
    }

    // MARK: - Fixtures

    static func receipt() -> FocusSchemaV4.AskedQuestion {
        FocusSchemaV4.AskedQuestion(
            priorityID: priorityID,
            subjectKindRaw: RuleSubjectKind.app.rawValue,
            subject: "com.chrismitchelmore.FocusDecoy2",
            reasonRaw: QueryableUncertainty.noNegativeBasis.rawValue,
            askedAt: timestamp,
            outcomeRaw: AskedQuestionOutcome.answeredRelevant.rawValue,
            answeredAt: timestamp
        )
    }

    static func record() -> FocusSchemaV4.InterventionRecord {
        FocusSchemaV4.InterventionRecord(
            at: timestamp,
            localDayKey: "2026-01-01",
            kindRaw: InterruptionKind.accusation.rawValue,
            rungRaw: LadderRung.Kind.panel.rawValue,
            subject: "com.chrismitchelmore.FocusDecoy",
            subjectKindRaw: RuleSubjectKind.app.rawValue,
            priorityID: priorityID,
            surfaceRaw: NudgeSurface.panel.rawValue,
            dispositionRaw: InterventionDisposition.delivered.rawValue,
            outcomeRaw: InterventionOutcome.corrected.rawValue
        )
    }
}
