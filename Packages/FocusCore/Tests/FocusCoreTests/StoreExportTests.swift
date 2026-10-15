import Foundation
import SwiftData
import Testing

@testable import FocusCore

/// **The export, and the two directions it has to be checked in** (F-110, focus-ix9).
///
/// The e09 plan's §8.1 names the defect these tests exist not to be: *"asserting the absence of a
/// shipped feature"*. "The export contains no window titles" is true because no column in this
/// store can hold one — green for ever, and a proof of nothing. So the absence half is a **poison
/// test**: a title-shaped sentinel is written into every `String` column of every entity, through
/// the raw `@Model` classes and past every facade, and the assertion is that no excluded column's
/// sentinel appears in any byte of the output. And the presence half is asserted just as hard:
/// every field the manifest promises is a field the bytes actually carry.
@Suite("Store export")
@MainActor
struct StoreExportTests {
    static let reference = Date(timeIntervalSince1970: 1_767_225_600)

    /// The one string this suite plants, in every column that can hold a string.
    ///
    /// Shaped like the things that must never leave: a window title with a document name in it, a
    /// full URL with a path and a query, an absolute POSIX path, and a sentence with spaces. If
    /// any of it can reach an output byte through a column the registry excludes, it will.
    static let poison = "POISON /Users/someone/Secret Plans.key ?q=1 — Untitled Document"

    /// Seed a store through the raw classes, bypassing every store facade, with the sentinel in
    /// every `String` column and a plausible value where a decoder has to be able to read one.
    static func seedPoisoned(_ context: ModelContext) throws {
        let task = FocusSchemaV3.PriorityTask(
            intent: poison,
            doneWhen: poison,
            createdAt: reference,
            shipped: poison,
            restartPoint: poison
        )
        // **Every optional carries a value**, because `JSONEncoder` omits a `nil` and a row full
        // of them would make "the manifest promised this field and the bytes have it" green for
        // fields the exporter never wrote.
        task.completedAt = reference
        task.lastActivatedAt = reference
        task.startedAt = reference
        task.timeboxSeconds = 1_500
        context.insert(task)

        let item = FocusSchemaV3.ContextItem(
            kindRaw: "keyword",
            value: poison,
            displayName: poison,
            bookmark: Data(poison.utf8),
            addedAt: reference
        )
        item.task = task
        context.insert(item)

        let rule = FocusSchemaV3.RelevanceRule(
            scopeRaw: PriorityRuleScope.app.rawValue,
            subject: "com.example.Poison",
            verdictRaw: PriorityRuleVerdict.relevant.rawValue,
            createdAt: reference
        )
        rule.task = task
        context.insert(rule)

        let session = FocusSchemaV3.FocusSessionRecord(
            taskID: task.id,
            startedAt: reference,
            phaseRaw: SessionPhase.focus.rawValue
        )
        session.restartPointNote = poison
        session.lastActiveBundleID = poison
        session.bootIdentity = poison
        session.uptimeAnchorSeconds = 4_242
        session.resumeToRaw = poison
        session.pauseCausesRaw = poison
        session.interruptionReasonRaw = poison
        session.endedAt = reference
        session.phaseChangedAt = reference
        session.plannedSeconds = 1_500
        session.deadlineAt = reference
        context.insert(session)

        let transition = FocusSchemaV3.SessionTransitionRecord(
            at: reference,
            fromRaw: SessionPhase.focus.rawValue,
            toRaw: SessionPhase.onBreak.rawValue,
            eventRaw: SessionEventKind.breakStarted.rawValue,
            reasonRaw: poison
        )
        transition.session = session
        context.insert(transition)

        let event = FocusSchemaV3.ActivityEvent(
            at: reference,
            kindRaw: ActivityEventKind.frontmostApplicationChanged.rawValue,
            bundleID: poison,
            sessionID: session.id,
            dwellSeconds: 12,
            displayID: 424_242
        )
        context.insert(event)

        // A second observation, because one row cannot carry both shapes of detail: the column
        // holds tokens **or** a measurement, so two rows are what it takes to see both fields.
        let measured = FocusSchemaV3.ActivityEvent(
            at: reference,
            kindRaw: ActivityEventKind.frontmostApplicationChanged.rawValue,
            bundleID: poison,
            detail: NormalisedDetail.measurement(MeasurementKind.allCases[0], 7).storedValue,
            sessionID: session.id,
            dwellSeconds: 3,
            displayID: 424_242
        )
        context.insert(measured)

        let tokenised = FocusSchemaV3.ActivityEvent(
            at: reference,
            kindRaw: ActivityEventKind.frontmostApplicationChanged.rawValue,
            bundleID: poison,
            detail: NormalisedDetail.tokens([DetailToken.allCases[0]]).storedValue,
            sessionID: session.id,
            dwellSeconds: 4,
            displayID: 424_242
        )
        context.insert(tokenised)

        let record = FocusSchemaV7.InterventionRecord(
            at: reference,
            localDayKey: "2026-01-01",
            kindRaw: InterruptionKind.accusation.rawValue,
            rungRaw: LadderRung.Kind.panel.rawValue,
            subject: poison,
            subjectKindRaw: RuleSubjectKind.app.rawValue,
            priorityID: task.id,
            surfaceRaw: NudgeSurface.panel.rawValue,
            dispositionRaw: InterventionDisposition.delivered.rawValue,
            outcomeRaw: InterventionOutcome.corrected.rawValue
        )
        record.originatingAnswerRaw = QueryAnswer.yesAddIt.rawValue
        record.explanationKindsRaw = ExplanationClauseKind.userRule.rawValue
        context.insert(record)

        context.insert(
            FocusSchemaV4.AskedQuestion(
                priorityID: task.id,
                subjectKindRaw: RuleSubjectKind.app.rawValue,
                subject: poison,
                reasonRaw: QueryableUncertainty.noNegativeBasis.rawValue,
                askedAt: reference,
                outcomeRaw: AskedQuestionOutcome.answeredRelevant.rawValue,
                answeredAt: reference
            )
        )
        try context.save()
    }

    static func poisonedStore() throws -> (ModelContainer, ModelContext) {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        try seedPoisoned(context)
        return (container, context)
    }

    // MARK: - The poison test

    /// **No excluded column's value reaches the bytes.**
    ///
    /// The four columns the registry excludes for a reason other than "it is a relationship" each
    /// carry a distinguishable value, and each is looked for in the output separately: a single
    /// "the sentinel is absent" reading would go green the moment one column stopped being
    /// planted.
    @Test("no excluded column reaches a single byte of the export")
    func noExcludedColumnIsExported() throws {
        let (container, context) = try Self.poisonedStore()
        _ = container

        let data = try StoreExport.json(in: context, generatedAt: Self.reference)
        let text = try #require(String(data: data, encoding: .utf8))

        // `ContextItem.bookmark` — a security-scoped handle, planted as the sentinel's bytes.
        #expect(!text.contains(Data(Self.poison.utf8).base64EncodedString()))
        // `FocusSessionRecord.bootIdentity` and `uptimeAnchorSeconds` — a machine fingerprint.
        #expect(!text.contains("bootIdentity"))
        #expect(!text.contains("4242"))
        #expect(!text.contains("uptimeAnchor"))
        // `ActivityEvent.displayID` — a number about this Mac's hardware arrangement.
        #expect(!text.contains("displayID"))
        #expect(!text.contains("424242"))
    }

    /// **The control the poison test needs, or it is a test of an input that cannot fail.**
    ///
    /// The sentinel *is* in the file, many times over, through the columns the registry says are
    /// the person's own. A store seeded with nothing would satisfy the assertions above.
    @Test("the poison the export is allowed to carry is in the file, many times over")
    func theSeedIsNotVacuous() throws {
        let (container, context) = try Self.poisonedStore()
        _ = container

        let data = try StoreExport.json(in: context, generatedAt: Self.reference)
        let text = try #require(String(data: data, encoding: .utf8))
        let occurrences = text.components(separatedBy: Self.poison).count - 1
        #expect(
            occurrences >= 8,
            "the poison reached only \(occurrences) exported fields — the seed is not planting"
        )
    }

    // MARK: - The other direction

    /// **Every field the manifest promises is a field the bytes carry.**
    ///
    /// The inverse of the absence half, and the one that catches a manifest that documents a
    /// column the exporter quietly dropped.
    @Test("every promised field appears in the export")
    func everyPromisedFieldAppears() throws {
        let (container, context) = try Self.poisonedStore()
        _ = container

        let data = try StoreExport.json(in: context, generatedAt: Self.reference)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        for (entity, fields) in StoreExport.fields {
            let rows = try #require(object[entity] as? [[String: Any]], "no rows for \(entity)")
            #expect(!rows.isEmpty, "\(entity) exported no row, so nothing is proved")
            // The union across rows: the detail column holds tokens **or** a measurement, so no
            // single observation can carry every promised field and one row would under-report.
            let keys = rows.reduce(into: Set<String>()) { $0.formUnion($1.keys) }
            for field in fields {
                #expect(keys.contains(field), "\(entity) promised \(field) and dropped it")
            }
            let unpromised = keys.subtracting(fields).sorted()
            #expect(
                unpromised.isEmpty,
                "\(entity) exported a field the manifest never promised: \(unpromised)"
            )
        }
    }

    /// **The manifest is in the file and says what the file is.**
    @Test("the manifest names the format, the version and the schema")
    func theManifestDocumentsItself() throws {
        let (container, context) = try Self.poisonedStore()
        _ = container

        let document = try StoreExport.document(in: context, generatedAt: Self.reference)
        #expect(document.manifest.format == "focus-sentinel.data")
        #expect(document.manifest.version == StoreExport.formatVersion)
        #expect(document.manifest.generatedAt == Self.reference)
        #expect(document.manifest.schemaVersion == 11)
        #expect(document.manifest.fields == StoreExport.fields)
    }

    /// Two exports of an unchanged store are byte-identical.
    @Test("the export is deterministic")
    func theExportIsDeterministic() throws {
        let (container, context) = try Self.poisonedStore()
        _ = container

        let first = try StoreExport.json(in: context, generatedAt: Self.reference)
        let second = try StoreExport.json(in: context, generatedAt: Self.reference)
        #expect(first == second)
    }

    /// A row this build cannot interpret contributes nothing — not the raw string, not a
    /// placeholder. The same promise `ActivityEventStore.exported(_:)` makes, made again here
    /// because this is a different projection of the same column.
    @Test("an activity detail this build cannot read exports as nothing")
    func anUnreadableDetailExportsAsNothing() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        let event = FocusSchemaV3.ActivityEvent(
            at: Self.reference,
            kindRaw: ActivityEventKind.frontmostApplicationChanged.rawValue,
            bundleID: "com.example.App"
        )
        context.insert(event)
        try context.save()

        let document = try StoreExport.document(in: context, generatedAt: Self.reference)
        let row = try #require(document.activityEvents.first)
        #expect(row.tokens == nil)
        #expect(row.measurement == nil)
        #expect(row.measurementValue == nil)
    }

    /// A selected item's label is the name the person's work goes by (issue #24). The rule
    /// keeps working on this Mac; the export keeps the application and drops the name.
    @Test("an item rule exports its application and never its label")
    func anItemRuleExportsWithoutItsLabel() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        let item = try #require(
            SelectedItem(bundleIdentifier: "com.github.githubapp", label: "Secret acquisition plan")
        )
        let rule = FocusSchemaV3.RelevanceRule(
            scopeRaw: PriorityRuleScope.app.rawValue,
            subject: item.subject,
            verdictRaw: PriorityRuleVerdict.relevant.rawValue,
            createdAt: Self.reference
        )
        context.insert(rule)
        let plain = FocusSchemaV3.RelevanceRule(
            scopeRaw: PriorityRuleScope.app.rawValue,
            subject: "com.apple.Safari",
            verdictRaw: PriorityRuleVerdict.relevant.rawValue,
            createdAt: Self.reference
        )
        context.insert(plain)
        try context.save()

        let bytes = try StoreExport.json(in: context, generatedAt: Self.reference)
        let text = try #require(String(data: bytes, encoding: .utf8))
        #expect(!text.contains("Secret acquisition plan"))
        #expect(!text.contains("Secret"))

        let document = try StoreExport.document(in: context, generatedAt: Self.reference)
        let subjects = Set(document.rules.map(\.subject))
        #expect(subjects == ["com.github.githubapp::selected-item", "com.apple.Safari"])
    }
}
