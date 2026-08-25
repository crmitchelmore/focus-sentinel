import Foundation
import SwiftData
import Testing

@testable import FocusCore

/// **Never twice**, and the reason the receipt rather than the rule is what holds it (R-78,
/// U-1).
@Suite("Query ledger")
struct QueryLedgerTests {
    static let instant = Date(timeIntervalSince1970: 1_767_225_600)   // 2026-01-01T00:00:00Z
    static let decoy2 = "com.chrismitchelmore.FocusDecoy2"

    static var londonCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    /// A container, a priority row, and a ledger over both.
    ///
    /// The **container is returned as well as the context**, and every caller binds it. A
    /// `ModelContainer` that goes out of scope resets its context and destroys every live model
    /// instance with it — which crashes on the next property read, several lines away from the
    /// line that dropped it.
    @MainActor
    static func makeLedger() throws -> (
        ledger: QueryLedger,
        context: ModelContext,
        task: FocusSchemaV3.PriorityTask,
        container: ModelContainer
    ) {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        let task = FocusSchemaV3.PriorityTask(
            intent: "Write the Q3 proposal", createdAt: instant
        )
        context.insert(task)
        try context.save()
        return (
            QueryLedger(context: context, dateProvider: FixedDateProvider(now: instant)),
            context,
            task,
            container
        )
    }

    /// A file-backed container, so a "relaunch" can be simulated by dropping the first one and
    /// opening the same bytes again.
    @MainActor
    static func makeFileLedger() throws -> (url: URL, container: ModelContainer) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "focus-ledger-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: FocusStore.storeFileName, directoryHint: .notDirectory)
        return (url, try FocusStore.makeContainer(kind: .temporary(url)))
    }

    static let scope = QueryLedgerTests.appScope(decoy2)

    /// A scope through the sanctioned route: a real warrant, from its one producer.
    static func appScope(_ subject: String) -> CorrectionScope {
        let stamp = EngineStamp.current
        let explanation = Explanation.make(
            stage: .heuristic, band: .low, clauses: [.noNegativeBasis], stamp: stamp
        )
        let eligibility = QueryEligibility.decide(
            outcome: ClassificationOutcome(
                verdict: .uncertain, source: .heuristic, confidence: 0, band: .low
            ),
            uncertainty: .noNegativeBasis,
            drift: .sustained(subject: .single(subject), accumulated: .seconds(60), isMixed: false),
            dwelled: .seconds(60),
            dwellSatisfied: true,
            phase: .focus,
            status: .uncertain,
            isUserIdle: false,
            hasActivePriority: true,
            hasAsked: false,
            budgetPermits: true,
            interruptionInFlight: false,
            judgedSubject: subject,
            explanation: explanation,
            stamp: stamp
        )
        guard let warrant = eligibility.warrant else {
            fatalError("the query producer refused to warrant on inputs that must warrant")
        }
        return CorrectionScope.from(warrant)
    }

    // MARK: - The atomic pair

    /// **One transaction, two records.** The rule the person can see and reverse, and the
    /// receipt they cannot.
    @Test("answering yes writes the rule and the receipt together")
    @MainActor
    func yesWritesBothRecords() throws {
        let (ledger, context, task, container) = try Self.makeLedger()
        // The container must outlive the test body: dropping it resets the context
        // and destroys every live model instance with it.
        defer { withExtendedLifetime(container) {} }

        let outcome = try ledger.answer(
            .yesAddIt,
            priorityID: task.id,
            task: task,
            scope: Self.scope,
            reason: .noNegativeBasis
        )
        #expect(outcome.isAtomicPair)

        let rules = try context.fetch(FetchDescriptor<FocusSchemaV3.RelevanceRule>())
        #expect(rules.count == 1)
        #expect(rules.first?.subject == Self.decoy2)
        #expect(rules.first?.verdictRaw == "relevant")
        #expect(rules.first?.scopeRaw == "app")
        #expect(rules.first?.task?.id == task.id, "the rule is scoped to the priority")

        let receipt = try #require(
            try ledger.receipt(priorityID: task.id, subjectKind: .app, subject: Self.decoy2)
        )
        #expect(receipt.outcome == .answeredRelevant)
        #expect(receipt.reason == .noNegativeBasis)
        #expect(receipt.answeredAt == Self.instant)
        #expect(try ledger.hasAsked(priorityID: task.id, subjectKind: .app, subject: Self.decoy2))
    }

    /// "No" writes the same pair, with the rule's verdict reversed. The *next* appearance of
    /// this subject is `unrelated` because **the user said so** — a user-authored rule
    /// producing an independent verdict, not a query escalating.
    @Test("answering no writes the same pair with the verdict reversed")
    @MainActor
    func noWritesBothRecords() throws {
        let (ledger, context, task, container) = try Self.makeLedger()
        // The container must outlive the test body: dropping it resets the context
        // and destroys every live model instance with it.
        defer { withExtendedLifetime(container) {} }

        _ = try ledger.answer(
            .no, priorityID: task.id, task: task, scope: Self.scope, reason: .noNegativeBasis
        )

        let rule = try #require(
            try context.fetch(FetchDescriptor<FocusSchemaV3.RelevanceRule>()).first
        )
        #expect(rule.verdictRaw == "unrelated")
        let receipt = try #require(
            try ledger.receipt(priorityID: task.id, subjectKind: .app, subject: Self.decoy2)
        )
        #expect(receipt.outcome == .answeredUnrelated)
    }

    /// **"Not now" writes no rule** — there is no answer to record — and the asking is still
    /// remembered, so a declined question is not re-asked after a relaunch.
    @Test("not now writes only the receipt")
    @MainActor
    func notNowWritesOnlyTheReceipt() throws {
        let (ledger, context, task, container) = try Self.makeLedger()
        // The container must outlive the test body: dropping it resets the context
        // and destroys every live model instance with it.
        defer { withExtendedLifetime(container) {} }

        let outcome = try ledger.answer(
            .notNow, priorityID: task.id, task: task, scope: Self.scope, reason: .noNegativeBasis
        )
        #expect(outcome == .receiptOnly(.declined))
        #expect(!outcome.isAtomicPair)
        #expect(try context.fetch(FetchDescriptor<FocusSchemaV3.RelevanceRule>()).isEmpty)

        let receipt = try #require(
            try ledger.receipt(priorityID: task.id, subjectKind: .app, subject: Self.decoy2)
        )
        #expect(receipt.outcome == .declined)
        #expect(try ledger.hasAsked(priorityID: task.id, subjectKind: .app, subject: Self.decoy2))
    }

    /// **The atomicity test.** A failure injected between the two writes leaves **neither**
    /// row, so the app can never be in the state where it has learned the answer but forgotten
    /// the asking.
    @Test("a failure between the two writes leaves neither row")
    @MainActor
    func theTransactionIsAtomic() throws {
        struct Injected: Error {}

        let (ledger, context, task, container) = try Self.makeLedger()
        // The container must outlive the test body: dropping it resets the context
        // and destroys every live model instance with it.
        defer { withExtendedLifetime(container) {} }
        ledger.failureBetweenWrites = { throw Injected() }

        #expect(throws: Injected.self) {
            try ledger.answer(
                .yesAddIt, priorityID: task.id, task: task, scope: Self.scope,
                reason: .noNegativeBasis
            )
        }

        #expect(
            try context.fetch(FetchDescriptor<FocusSchemaV3.RelevanceRule>()).isEmpty,
            "the rule survived a torn transaction"
        )
        #expect(try ledger.count() == 0, "the receipt survived a torn transaction")
        #expect(
            try !ledger.hasAsked(priorityID: task.id, subjectKind: .app, subject: Self.decoy2),
            "the app remembered asking a question it never recorded an answer to"
        )

        // …and the same answer succeeds once the failure is removed, so the rollback left the
        // context usable rather than poisoned.
        ledger.failureBetweenWrites = nil
        _ = try ledger.answer(
            .yesAddIt, priorityID: task.id, task: task, scope: Self.scope,
            reason: .noNegativeBasis
        )
        #expect(try ledger.count() == 1)
        #expect(try context.fetch(FetchDescriptor<FocusSchemaV3.RelevanceRule>()).count == 1)
    }

    // MARK: - Never twice

    /// **Finding 3's sequence, in the unit lane.** Ask, answer "Yes", delete the learned rule,
    /// re-encounter the subject: the verdict is `uncertain` again and **there is still no
    /// question**, because `hasAsked` reads the receipt and the receipt is not deletable.
    ///
    /// Removing a learned chip means "that is not a fact about my work", never "ask me again".
    @Test("deleting the rule does not re-open the question")
    @MainActor
    func deletingTheRuleDoesNotReOpenTheQuestion() throws {
        let (ledger, context, task, container) = try Self.makeLedger()
        // The container must outlive the test body: dropping it resets the context
        // and destroys every live model instance with it.
        defer { withExtendedLifetime(container) {} }

        _ = try ledger.answer(
            .yesAddIt, priorityID: task.id, task: task, scope: Self.scope,
            reason: .noNegativeBasis
        )
        #expect(try context.fetch(FetchDescriptor<FocusSchemaV3.RelevanceRule>()).count == 1)

        // The person removes the learned chip. This is the supported affordance, not a hack.
        for rule in try context.fetch(FetchDescriptor<FocusSchemaV3.RelevanceRule>()) {
            context.delete(rule)
        }
        try context.save()
        #expect(try context.fetch(FetchDescriptor<FocusSchemaV3.RelevanceRule>()).isEmpty)

        // The subject is uncertain again — and still already asked.
        #expect(
            try ledger.hasAsked(priorityID: task.id, subjectKind: .app, subject: Self.decoy2),
            "deleting a rule dissolved the receipt, and the question would be asked again"
        )

        // And the eligibility that consults it withholds by name.
        let eligibility = QueryEligibility.decide(
            outcome: ClassificationOutcome(
                verdict: .uncertain, source: .heuristic, confidence: 0, band: .low
            ),
            uncertainty: .noNegativeBasis,
            drift: .sustained(
                subject: .single(Self.decoy2), accumulated: .seconds(60), isMixed: false
            ),
            dwelled: .seconds(60),
            dwellSatisfied: true,
            phase: .focus,
            status: .uncertain,
            isUserIdle: false,
            hasActivePriority: true,
            hasAsked: try ledger.hasAsked(
                priorityID: task.id, subjectKind: .app, subject: Self.decoy2
            ),
            budgetPermits: true,
            interruptionInFlight: false,
            judgedSubject: Self.decoy2,
            explanation: Explanation.make(
                stage: .heuristic, band: .low, clauses: [.noNegativeBasis],
                stamp: EngineStamp.current
            ),
            stamp: EngineStamp.current
        )
        #expect(eligibility.withholdingReason == .alreadyAsked)
        #expect(!eligibility.isWarranted)
    }

    /// **Across a relaunch.** The receipt is on disk, so a declined question does not come back
    /// when the app is opened again.
    @Test("a declined question is still declined after a relaunch")
    @MainActor
    func neverAskTwiceAcrossARelaunch() throws {
        let (url, container) = try Self.makeFileLedger()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let priorityID: UUID
        do {
            let context = container.mainContext
            let task = FocusSchemaV3.PriorityTask(
                intent: "Write the Q3 proposal", createdAt: Self.instant
            )
            context.insert(task)
            try context.save()
            priorityID = task.id

            let ledger = QueryLedger(
                context: context, dateProvider: FixedDateProvider(now: Self.instant)
            )
            _ = try ledger.answer(
                .notNow, priorityID: task.id, task: task, scope: Self.scope,
                reason: .noNegativeBasis
            )
        }

        // Relaunch: a new container over the same bytes.
        let reopened = try FocusStore.makeContainer(kind: .temporary(url))
        let ledger = QueryLedger(
            context: reopened.mainContext, dateProvider: FixedDateProvider(now: Self.instant)
        )
        #expect(
            try ledger.hasAsked(priorityID: priorityID, subjectKind: .app, subject: Self.decoy2),
            "a declined question came back after a relaunch"
        )
        #expect(try ledger.receipt(
            priorityID: priorityID, subjectKind: .app, subject: Self.decoy2
        )?.outcome == .declined)
    }

    /// The key is `(priorityID, subjectKind, subject)`, and each component is load-bearing.
    @Test("a different priority, subject or subject kind is a different question")
    @MainActor
    func theKeyIsAllThreeComponents() throws {
        let (ledger, _, task, container) = try Self.makeLedger()
        // The container must outlive the test body: dropping it resets the context
        // and destroys every live model instance with it.
        defer { withExtendedLifetime(container) {} }
        _ = try ledger.answer(
            .yesAddIt, priorityID: task.id, task: task, scope: Self.scope,
            reason: .noNegativeBasis
        )

        #expect(try ledger.hasAsked(priorityID: task.id, subjectKind: .app, subject: Self.decoy2))
        // A different priority: a new commitment makes old answers irrelevant, and that is
        // correct.
        #expect(try !ledger.hasAsked(
            priorityID: UUID(), subjectKind: .app, subject: Self.decoy2
        ))
        // A different subject.
        #expect(try !ledger.hasAsked(
            priorityID: task.id, subjectKind: .app, subject: "com.apple.Safari"
        ))
        // A different narrowness: e07 will ask about a site inside an app it already asked
        // about, and that is a different question.
        #expect(try !ledger.hasAsked(
            priorityID: task.id, subjectKind: .domain, subject: Self.decoy2
        ))
    }

    /// **A revision bump on the same priority id does not re-open a question.** Editing the
    /// wording of a commitment is not making a new one.
    @Test("editing the priority's wording does not re-open its questions")
    @MainActor
    func aRevisionBumpDoesNotReOpen() throws {
        let (ledger, context, task, container) = try Self.makeLedger()
        // The container must outlive the test body: dropping it resets the context
        // and destroys every live model instance with it.
        defer { withExtendedLifetime(container) {} }
        _ = try ledger.answer(
            .yesAddIt, priorityID: task.id, task: task, scope: Self.scope,
            reason: .noNegativeBasis
        )

        task.intent = "Write the Q3 proposal and send it"
        task.revision += 1
        try context.save()

        #expect(task.revision == 2)
        #expect(
            try ledger.hasAsked(priorityID: task.id, subjectKind: .app, subject: Self.decoy2),
            "an edit to the wording re-opened a question the person had answered"
        )
    }

    /// Gate 11 exists so a second receipt is never written. The ledger says so out loud when
    /// one is attempted, rather than quietly doing nothing.
    @Test("a second receipt for the same question is refused")
    @MainActor
    func aSecondReceiptIsRefused() throws {
        let (ledger, _, task, container) = try Self.makeLedger()
        // The container must outlive the test body: dropping it resets the context
        // and destroys every live model instance with it.
        defer { withExtendedLifetime(container) {} }
        _ = try ledger.answer(
            .yesAddIt, priorityID: task.id, task: task, scope: Self.scope,
            reason: .noNegativeBasis
        )

        #expect(throws: QueryLedgerError.alreadyAsked(subject: Self.decoy2)) {
            try ledger.answer(
                .no, priorityID: task.id, task: task, scope: Self.scope,
                reason: .noNegativeBasis
            )
        }
        #expect(throws: QueryLedgerError.alreadyAsked(subject: Self.decoy2)) {
            try ledger.record(
                priorityID: task.id, subjectKind: .app, subject: Self.decoy2,
                reason: .noNegativeBasis, outcome: .expired
            )
        }
        #expect(try ledger.count() == 1)
    }

    /// An answer that writes a rule needs a priority to scope it to, and the priority it is
    /// keyed on. A task-authority rule without a task is not a narrower rule, it is a global
    /// one; and a rule written under a different commitment from its receipt would leave the
    /// app able to learn an answer and forget the asking.
    @Test("a rule-writing answer refuses a missing or mismatched priority")
    @MainActor
    func ruleWritingAnswersNeedTheirPriority() throws {
        let (ledger, context, task, container) = try Self.makeLedger()
        // The container must outlive the test body: dropping it resets the context
        // and destroys every live model instance with it.
        defer { withExtendedLifetime(container) {} }

        #expect(throws: QueryLedgerError.noPriorityToScopeTo) {
            try ledger.answer(
                .yesAddIt, priorityID: task.id, task: nil, scope: Self.scope,
                reason: .noNegativeBasis
            )
        }

        let other = FocusSchemaV3.PriorityTask(intent: "Something else", createdAt: Self.instant)
        context.insert(other)
        try context.save()

        #expect(throws: QueryLedgerError.priorityMismatch) {
            try ledger.answer(
                .yesAddIt, priorityID: task.id, task: other, scope: Self.scope,
                reason: .noNegativeBasis
            )
        }

        #expect(try ledger.count() == 0)
        #expect(try context.fetch(FetchDescriptor<FocusSchemaV3.RelevanceRule>()).isEmpty)

        // "Not now" writes no rule, so it needs no priority row at all.
        _ = try ledger.answer(
            .notNow, priorityID: task.id, task: nil, scope: Self.scope,
            reason: .noNegativeBasis
        )
        #expect(try ledger.count() == 1)
    }

    /// `record(…)` is for outcomes with no answer in them. An outcome that writes a rule must
    /// go through `answer(…)`, or the two records would not be one transaction.
    @Test("record refuses an outcome that should have written a rule")
    @MainActor
    func recordRefusesAnAnswer() throws {
        let (ledger, _, task, container) = try Self.makeLedger()
        // The container must outlive the test body: dropping it resets the context
        // and destroys every live model instance with it.
        defer { withExtendedLifetime(container) {} }
        for outcome in AskedQuestionOutcome.allCases where outcome.wroteRule {
            #expect(throws: QueryLedgerError.noPriorityToScopeTo) {
                try ledger.record(
                    priorityID: task.id, subjectKind: .app, subject: Self.decoy2,
                    reason: .noNegativeBasis, outcome: outcome
                )
            }
        }
        #expect(try ledger.count() == 0)

        // …and it accepts the two that write none.
        try ledger.record(
            priorityID: task.id, subjectKind: .app, subject: Self.decoy2,
            reason: .noNegativeBasis, outcome: .expired
        )
        #expect(try ledger.receipt(
            priorityID: task.id, subjectKind: .app, subject: Self.decoy2
        )?.outcome == .expired)
    }

    // MARK: - Retention

    /// **Rows die with their priority, and with nothing else** (F-115/F-116).
    @Test("purging a priority removes its receipts and no others")
    @MainActor
    func purgingAPriority() throws {
        let (ledger, context, task, container) = try Self.makeLedger()
        // The container must outlive the test body: dropping it resets the context
        // and destroys every live model instance with it.
        defer { withExtendedLifetime(container) {} }
        let other = FocusSchemaV3.PriorityTask(intent: "Something else", createdAt: Self.instant)
        context.insert(other)
        try context.save()

        _ = try ledger.answer(
            .yesAddIt, priorityID: task.id, task: task, scope: Self.scope,
            reason: .noNegativeBasis
        )
        _ = try ledger.answer(
            .no, priorityID: other.id, task: other, scope: Self.scope,
            reason: .noNegativeBasis
        )
        #expect(try ledger.count() == 2)

        #expect(try ledger.purge(priorityID: task.id) == 1)
        #expect(try !ledger.hasAsked(priorityID: task.id, subjectKind: .app, subject: Self.decoy2))
        #expect(try ledger.hasAsked(priorityID: other.id, subjectKind: .app, subject: Self.decoy2))
        #expect(try ledger.count() == 1)

        // Purging a priority with no receipts is a no-op, not an error.
        #expect(try ledger.purge(priorityID: UUID()) == 0)
    }

    /// The completeness half: a receipt whose priority was deleted by a path that forgot to
    /// purge would outlive the commitment it was about.
    @Test("orphaned receipts are purged, and living ones are not")
    @MainActor
    func purgingOrphans() throws {
        let (ledger, context, task, container) = try Self.makeLedger()
        // The container must outlive the test body: dropping it resets the context
        // and destroys every live model instance with it.
        defer { withExtendedLifetime(container) {} }
        let other = FocusSchemaV3.PriorityTask(intent: "Something else", createdAt: Self.instant)
        context.insert(other)
        try context.save()

        _ = try ledger.answer(
            .yesAddIt, priorityID: task.id, task: task, scope: Self.scope,
            reason: .noNegativeBasis
        )
        _ = try ledger.answer(
            .no, priorityID: other.id, task: other, scope: Self.scope,
            reason: .noNegativeBasis
        )

        #expect(try ledger.purgeOrphans(livingPriorityIDs: [task.id]) == 1)
        #expect(try ledger.count() == 1)
        #expect(try ledger.hasAsked(priorityID: task.id, subjectKind: .app, subject: Self.decoy2))

        #expect(try ledger.purgeAll() == 1)
        #expect(try ledger.count() == 0)
    }

    @Test("the ledger's retention rides its priority's lifetime")
    @MainActor
    func retentionRule() {
        #expect(QueryLedger.retention == .withPriority)
    }

    /// What `dailyQueryCap` reads: questions asked for one priority on one **local** day, in
    /// the user's own calendar.
    @Test("the per-priority day count is a local day in the user's calendar")
    @MainActor
    func perPriorityDayCount() throws {
        let (ledger, _, task, container) = try Self.makeLedger()
        // The container must outlive the test body: dropping it resets the context
        // and destroys every live model instance with it.
        defer { withExtendedLifetime(container) {} }
        let calendar = Self.londonCalendar
        let today = LocalDay.containing(Self.instant, calendar: calendar)

        for subject in ["a.one", "a.two", "a.three"] {
            _ = try ledger.answer(
                .yesAddIt, priorityID: task.id, task: task, scope: Self.appScope(subject),
                reason: .noNegativeBasis
            )
        }
        #expect(try ledger.askedCount(priorityID: task.id, on: today, calendar: calendar) == 3)

        // A question asked tomorrow does not count against today.
        try ledger.record(
            priorityID: task.id, subjectKind: .app, subject: "a.four",
            reason: .noNegativeBasis, outcome: .declined,
            askedAt: Self.instant.addingTimeInterval(86_400)
        )
        #expect(try ledger.askedCount(priorityID: task.id, on: today, calendar: calendar) == 3)
        #expect(try ledger.count() == 4)
    }
}
