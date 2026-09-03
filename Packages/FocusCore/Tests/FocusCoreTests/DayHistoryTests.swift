import Foundation
import SwiftData
import Testing

@testable import FocusCore

/// History, and the one thing nothing else in this app can do: say *you were wrong to stay
/// quiet* (focus-tee.5).
///
/// The five claims the epic's S3 names, each with the failure it is written against:
///
///  * **D1** — a day with **no interruption at all** still yields rows carrying the correction.
///    A ledger that only had rows where the app had already spoken would make the correction
///    reachable only on days it did not matter.
///  * **D2** — the affordance is offered or **withdrawn with a stated reason**, folded over all
///    four states a priority can be in. A deleted priority is never promoted to a global rule
///    (R-88).
///  * **D3** — a correction is **never a re-ask**. The query ledger is byte-identical before and
///    after, and the type that writes the rule holds no reference through which it could be.
///  * **D4** — the log is **never edited**. A correction appends; it does not rewrite the day.
///  * **D5** — the rule is **byte-identical** to one an in-the-moment correction writes, but for
///    its identifier and its timestamp.
@Suite("History")
struct DayHistoryTests {
    static let reference = Date(timeIntervalSince1970: 1_767_225_600)
    static let decoy = "com.chrismitchelmore.FocusDecoy"
    static let decoy2 = "com.chrismitchelmore.FocusDecoy2"
    static let origin = "https://news.example"

    static var london: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    /// Everything History reads, over one store.
    @MainActor
    struct World {
        let container: ModelContainer
        let context: ModelContext
        let clock: FixedDateProvider
        let priorities: PriorityStore
        let events: ActivityEventStore
        let log: InterventionLog
        let ledger: QueryLedger
        let sessions: SessionStore
        let calendar: Calendar

        init(now: Date = DayHistoryTests.reference) throws {
            container = try FocusStore.makeContainer(kind: .inMemory)
            context = container.mainContext
            clock = FixedDateProvider(now: now)
            calendar = DayHistoryTests.london
            priorities = PriorityStore(context: context, dateProvider: clock)
            events = ActivityEventStore(context: context, dateProvider: clock)
            log = InterventionLog(context: context, dateProvider: clock, calendar: calendar)
            ledger = QueryLedger(context: context, dateProvider: clock)
            sessions = SessionStore(
                context: context,
                dateProvider: clock,
                uptimeClock: TestUptimeClock(),
                bootIdentity: "test"
            )
        }

        var today: LocalDay { LocalDay.containing(clock.now, calendar: calendar) }

        func history() throws -> DayHistory {
            try DayHistory.build(
                day: today,
                log: log,
                ledger: ledger,
                events: events,
                sessions: sessions,
                priorities: priorities,
                calendar: calendar
            )
        }
    }

    // MARK: - D1

    /// **A day on which the app said nothing at all still has rows to correct.**
    ///
    /// Red before this shipped: `DayHistory` did not exist, and every other surface in the app
    /// is built from rows the app writes when it *speaks*. A ledger of those alone would show a
    /// perfectly quiet day as an empty page — and the one judgement a person most wants to
    /// disagree with is the one the app made silently.
    @Test("a day with no interruption at all still yields correctable rows")
    @MainActor
    func aSilentDayStillYieldsRows() throws {
        let world = try World()
        _ = try world.priorities.setPriority(intent: "Write the quarterly proposal")
        for (index, bundleID) in [Self.decoy, Self.decoy2].enumerated() {
            _ = try world.events.append(
                kind: .frontmostApplicationChanged,
                bundleID: bundleID,
                dwellSeconds: 240,
                at: world.clock.now.addingTimeInterval(Double(index) * 60)
            )
        }

        // Nothing was said: no accusation, no question.
        #expect(try world.log.all().isEmpty)
        #expect(try world.ledger.count() == 0)

        let history = try world.history()
        let silences = history.entries.compactMap { entry -> HistorySilence? in
            if case .silence(let value) = entry { return value }
            return nil
        }
        #expect(silences.count == 2)
        #expect(silences.allSatisfy { $0.correction.isOffered })
        #expect(Set(silences.map(\.subject)) == [Self.decoy, Self.decoy2])
        // And the ledger is not vacuously "all silences": there is nothing else in it.
        #expect(history.countsByKind["intervention"] == 0)
        #expect(history.countsByKind["question"] == 0)
    }

    /// The same subject observed twice in a row is one interval, and observed again after
    /// something else is two — otherwise a corroboration tick that re-reads the frontmost
    /// application would turn one visit into twelve rows.
    @Test("a run of the same subject is one row, and a return is a second")
    @MainActor
    func runsAreCollapsedAndReturnsAreNot() throws {
        let world = try World()
        _ = try world.priorities.setPriority(intent: "Write the quarterly proposal")
        // Distinct instants, because `ActivityEventStore.all()` orders by `(at, id)` and four
        // rows stamped at one instant read back in identifier order — which is a fact about
        // UUIDs, not about the day. A run is a run only if the store can say what came first.
        for (index, bundleID) in [
            Self.decoy, Self.decoy, Self.decoy, Self.decoy2, Self.decoy
        ].enumerated() {
            _ = try world.events.append(
                kind: .frontmostApplicationChanged,
                bundleID: bundleID,
                dwellSeconds: 60,
                at: world.clock.now.addingTimeInterval(Double(index) * 60)
            )
        }

        let silences = try world.history().entries.compactMap { entry -> HistorySilence? in
            if case .silence(let value) = entry { return value }
            return nil
        }
        #expect(silences.map(\.subject) == [Self.decoy, Self.decoy2, Self.decoy])
    }

    /// A subject the app *did* speak about has its own row and does not also get a silence row:
    /// the same interval drawn twice, once as an accusation and once as *"and here it said
    /// nothing"*, would be the ledger contradicting itself.
    @Test("a subject the app spoke about is not also drawn as a silence")
    @MainActor
    func aSpokenSubjectIsNotAlsoASilence() throws {
        let world = try World()
        let priorityID = try world.priorities.setPriority(intent: "Write the quarterly proposal")
        _ = try world.events.append(
            kind: .frontmostApplicationChanged,
            bundleID: Self.decoy,
            dwellSeconds: 60
        )
        _ = try world.log.record(
            InterventionEvent(
                kind: .accusation,
                rung: .panel,
                subject: Self.decoy,
                surface: .panel,
                disposition: .delivered,
                explanationKinds: [.userRule, .sustainedDwell]
            ),
            priorityID: priorityID
        )

        let history = try world.history()
        #expect(history.countsByKind["intervention"] == 1)
        #expect(history.countsByKind["silence"] == 0)

        // And the row carries the two facts nothing read before e09a.
        let intervention = try #require(
            history.entries.compactMap { entry -> HistoryIntervention? in
                if case .intervention(let value) = entry { return value }
                return nil
            }.first
        )
        #expect(intervention.explanationKinds == [.userRule, .sustainedDwell])
        #expect(intervention.subjectKind == .app)
    }

    /// A question is drawn with **the app's own reason for asking** and the person's own answer.
    /// `AskedQuestion.reasonRaw` is the one place the *why* was written down at the time, and
    /// until now nothing rendered it.
    @Test("a question is drawn with the reason the app asked and the answer the person gave")
    @MainActor
    func aQuestionCarriesItsReasonAndItsAnswer() throws {
        let world = try World()
        let priorityID = try world.priorities.setPriority(intent: "Write the quarterly proposal")
        _ = try world.ledger.record(
            priorityID: priorityID,
            subjectKind: .app,
            subject: Self.decoy2,
            reason: .mixedUseApplication,
            // `.declined` rather than an answer that writes a rule: an outcome that wrote one
            // would have to go through `answer(…)`, which is a transaction this test is not
            // about. What History draws is the receipt, and every outcome reaches it the same way.
            outcome: .declined,
            askedAt: world.clock.now
        )

        let question = try #require(
            try world.history().entries.compactMap { entry -> HistoryQuestion? in
                if case .question(let value) = entry { return value }
                return nil
            }.first
        )
        #expect(question.reason == .mixedUseApplication)
        #expect(question.outcome == .declined)
        #expect(question.subject == Self.decoy2)
    }

    // MARK: - D2

    /// **The affordance is offered, or withdrawn with a stated reason.** Folded over all four
    /// states a priority can be in, plus the two shapes of subject that have no correction.
    ///
    /// Mutation witness: make the deleted case fall back to `.global` — that is, return
    /// `.offered` for a priority no row exists for — and the third case goes red. A correction
    /// widened to every priority the person will ever have is the app writing a rule they never
    /// asked for (R-88).
    @Test("the correction is offered or withdrawn, over every state a row can be in")
    @MainActor
    func theAffordanceIsFoldedOverEveryState() throws {
        let world = try World()

        let alive = try world.priorities.setPriority(intent: "Write the quarterly proposal")
        let completed = try world.priorities.createTask(intent: "Send the invoices")
        try world.priorities.complete(taskID: completed, shipped: nil)
        let deleted = try world.priorities.createTask(intent: "A priority that will not last")
        try world.priorities.deleteTask(id: deleted)

        let cases: [(String, HistoryCorrectability, HistoryWithdrawal?)] = [
            (
                "an alive priority",
                DayHistory.correctability(
                    subject: Self.decoy, priorityID: alive, priorities: world.priorities
                ),
                nil
            ),
            (
                "a completed priority, whose rules still belong to it",
                DayHistory.correctability(
                    subject: Self.decoy, priorityID: completed, priorities: world.priorities
                ),
                nil
            ),
            (
                "a deleted priority",
                DayHistory.correctability(
                    subject: Self.decoy, priorityID: deleted, priorities: world.priorities
                ),
                .priorityDeleted
            ),
            (
                "no priority at all",
                DayHistory.correctability(
                    subject: Self.decoy, priorityID: nil, priorities: world.priorities
                ),
                .noPriority
            ),
            (
                "an origin subject",
                DayHistory.correctability(
                    subject: Self.origin, priorityID: alive, priorities: world.priorities
                ),
                .originSubject
            ),
            (
                "a row that names nobody",
                DayHistory.correctability(
                    subject: "", priorityID: alive, priorities: world.priorities
                ),
                .noSubject
            )
        ]

        for (description, correctability, expected) in cases {
            #expect(
                correctability.withdrawal == expected,
                "\(description): expected \(String(describing: expected))"
            )
        }
        // Non-vacuity: the fold produced both answers, and every withdrawal reason was reached.
        #expect(cases.contains { $0.1.isOffered })
        #expect(
            Set(cases.compactMap { $0.1.withdrawal })
                == Set(HistoryWithdrawal.allCases)
        )
    }

    /// **A deleted priority is refused at the moment of the write, not only at the moment of
    /// the draw.** History can be on screen while a priority is deleted in another window.
    @Test("a priority deleted while History was open refuses the write rather than widening it")
    @MainActor
    func aPriorityDeletedUnderTheSurfaceRefusesTheWrite() throws {
        let world = try World()
        let priorityID = try world.priorities.createTask(intent: "A priority that will not last")
        let correctability = DayHistory.correctability(
            subject: Self.decoy, priorityID: priorityID, priorities: world.priorities
        )
        #expect(correctability.isOffered)

        try world.priorities.deleteTask(id: priorityID)

        #expect(throws: HistoryCorrectionError.withdrawn(.priorityDeleted)) {
            try HistoryCorrection.markAsDistraction(
                correctability,
                priorities: world.priorities,
                at: world.clock.now
            )
        }
        // And nothing at all was written — never a global rule.
        #expect(try world.context.fetch(FetchDescriptor<FocusSchemaV3.RelevanceRule>()).isEmpty)
    }

    // MARK: - D3

    /// **A correction is never a re-ask.**
    ///
    /// The query ledger is read before and after and must be byte-identical: same count, same
    /// rows, same identifiers. A receipt written here would settle — or re-open — a question
    /// retroactively, and disagreeing with a silence is not permission to stop asking.
    @Test("correcting a silence leaves the query ledger byte-identical")
    @MainActor
    func aCorrectionWritesNoReceipt() throws {
        let world = try World()
        let priorityID = try world.priorities.setPriority(intent: "Write the quarterly proposal")
        // A receipt already on file, so "unchanged" is a statement about rows that exist.
        _ = try world.ledger.record(
            priorityID: priorityID,
            subjectKind: .app,
            subject: Self.decoy2,
            reason: .noNegativeBasis,
            outcome: .declined,
            askedAt: world.clock.now
        )

        let before = try world.ledger.all().map { ($0.id, $0.outcomeRaw, $0.answeredAt) }
        let beforeCount = try world.ledger.count()

        let correctability = DayHistory.correctability(
            subject: Self.decoy, priorityID: priorityID, priorities: world.priorities
        )
        _ = try HistoryCorrection.markAsDistraction(
            correctability,
            priorities: world.priorities,
            at: world.clock.now
        )

        let after = try world.ledger.all().map { ($0.id, $0.outcomeRaw, $0.answeredAt) }
        #expect(try world.ledger.count() == beforeCount)
        #expect(before.map(\.0) == after.map(\.0))
        #expect(before.map(\.1) == after.map(\.1))
        #expect(before.map(\.2) == after.map(\.2))
        // Non-vacuity: the correction did write something, so "the ledger did not move" is not
        // a statement about a function that did nothing.
        #expect(try world.context.fetch(FetchDescriptor<FocusSchemaV3.RelevanceRule>()).count == 1)
    }

    // MARK: - D4

    /// **The log is never edited.** A correction appends the person's disagreement as a rule;
    /// the record of what the app did is left exactly as it was.
    @Test("correcting a silence leaves every intervention row untouched")
    @MainActor
    func aCorrectionNeverEditsTheLog() throws {
        let world = try World()
        let priorityID = try world.priorities.setPriority(intent: "Write the quarterly proposal")
        let rowID = try world.log.record(
            InterventionEvent(
                kind: .accusation,
                rung: .panel,
                subject: Self.decoy2,
                surface: .panel,
                disposition: .delivered,
                outcome: .dismissed
            ),
            priorityID: priorityID
        )
        let before = try #require(try world.log.all().first { $0.id == rowID })
        let beforeFields = [
            before.subject, before.dispositionRaw, before.outcomeRaw ?? "",
            before.subjectKindRaw, before.surfaceRaw
        ]

        let correctability = DayHistory.correctability(
            subject: Self.decoy, priorityID: priorityID, priorities: world.priorities
        )
        _ = try HistoryCorrection.markAsDistraction(
            correctability,
            priorities: world.priorities,
            at: world.clock.now
        )

        let after = try #require(try world.log.all().first { $0.id == rowID })
        #expect(
            [
                after.subject, after.dispositionRaw, after.outcomeRaw ?? "",
                after.subjectKindRaw, after.surfaceRaw
            ] == beforeFields
        )
        #expect(try world.log.all().count == 1, "a correction added a row to the log")
    }

    // MARK: - D5

    /// **The rule is byte-identical to an in-the-moment correction's**, but for `id` and
    /// `createdAt`.
    ///
    /// Both sides go through `QueryAnswer.no.outcome(scope:at:id:)`, which is the point: there is
    /// one function that decides the shape of a correction's rule, and History does not get its
    /// own. The comparison is made on the value rather than on the row, so a future divergence in
    /// how either side *persists* it fails the store-side assertion below instead of hiding here.
    @Test("a correction from History is the same rule an in-the-moment one writes")
    @MainActor
    func theRuleIsIdenticalToAnInTheMomentCorrection() throws {
        let world = try World()
        let priorityID = try world.priorities.setPriority(intent: "Write the quarterly proposal")

        // The in-the-moment shape: the scope a real authorisation produces, built through the
        // one producer e05 ships — never a `CorrectionScope` this test made up, which would
        // compare History against itself.
        let liveScope = CorrectionScope.from(CorrectionScopeTests.warrant(subject: Self.decoy))

        let historyCorrectability = DayHistory.correctability(
            subject: Self.decoy, priorityID: priorityID, priorities: world.priorities
        )
        let historySubject = try #require({ () -> HistorySubject? in
            if case .offered(let subject, _) = historyCorrectability { return subject }
            return nil
        }())
        let historyScope = CorrectionScope.from(historySubject)

        #expect(liveScope == historyScope)

        let instant = world.clock.now
        let sharedID = UUID()
        let live = QueryAnswer.no.outcome(scope: liveScope, at: instant, id: sharedID)
        let history = HistoryCorrection.answer.outcome(
            scope: historyScope, at: instant, id: sharedID
        )
        #expect(live.persistedRule == history.persistedRule)
        #expect(history.persistedRule?.authority == .task)
        #expect(history.persistedRule?.verdict == .unrelated)

        // And the row it persists carries the same three columns.
        let ruleID = try HistoryCorrection.markAsDistraction(
            historyCorrectability,
            priorities: world.priorities,
            at: instant
        )
        let row = try #require(try world.priorities.rule(id: ruleID))
        #expect(row.scopeRaw == RuleSubjectKind.app.rawValue)
        #expect(row.subject == Self.decoy)
        #expect(row.verdictRaw == PriorityRuleVerdict.unrelated.rawValue)
        // Scoped to the priority the judgement ran under, never global (R-88).
        #expect(row.task?.id == priorityID)
    }

    /// The rule is scoped to the priority **that judgement ran under**, not to whichever one is
    /// active when the person opens History. That is the whole reason `HistorySilence` carries a
    /// priority identifier rather than the surface reading the live pointer.
    @Test("the rule is scoped to the priority the judgement ran under, not the current one")
    @MainActor
    func theRuleIsScopedToTheJudgementsPriority() throws {
        let world = try World()
        let judgedUnder = try world.priorities.setPriority(intent: "Write the quarterly proposal")
        let correctability = DayHistory.correctability(
            subject: Self.decoy, priorityID: judgedUnder, priorities: world.priorities
        )

        // The person moves on before opening History.
        let current = try world.priorities.setPriority(intent: "Read the review notes")
        #expect(try world.priorities.activeTask()?.id == current)

        let ruleID = try HistoryCorrection.markAsDistraction(
            correctability,
            priorities: world.priorities,
            at: world.clock.now
        )
        let row = try #require(try world.priorities.rule(id: ruleID))
        #expect(row.task?.id == judgedUnder)
        #expect(row.task?.id != current)
    }
}
