import AppKit
import FocusCore
import FocusUI
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// A registrar that offers nothing to the platform.
///
/// A test process must not take ⌥Space away from whoever is using this Mac, and `start()` is
/// the only path that registers one. `HotKeySpec.refusal` is `HotKeySpec`'s own subject and is
/// proved in `HotKeySpecTests`; nothing here needs a real registration.
@MainActor
final class InertHotKeyRegistrar: HotKeyRegistering {
    private(set) var offered: [HotKeySpec] = []
    var availability: HotKeyAvailability = .available
    var registeredSpec: HotKeySpec?

    @discardableResult
    func register(
        _ spec: HotKeySpec,
        handler: @escaping @MainActor @Sendable () -> Void
    ) -> HotKeyRegistration {
        offered.append(spec)
        registeredSpec = spec
        return .registered
    }

    func unregister() {
        registeredSpec = nil
    }
}

/// **The composition root, run rather than read** (R-78, R-84a, R-86).
///
/// Everything here used to be a source scan. `compositionRootWritesNoDuplicateRule` looked for
/// the *words* `outcome.ruleAwaitingPersistence` and `registerLearnedRuleUndo(` in
/// `App/AppComposition.swift`; `compositionRootWiresTheLoop` looked for the words
/// `relevanceHost.onJudgement` and `nudgeHost.consider(`. A scan for spelling cannot see
/// behaviour: the duplicate-learned-rule defect it was written for wrote two rows while every
/// substring it looked for was present and correct.
///
/// These build the real root over an in-memory store and count the rows.
@Suite("The composition root, run", .serialized)
@MainActor
struct CompositionRootTests {
    static func root() -> AppComposition {
        AppComposition(
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference),
            monotonicClock: FixedMonotonicClock(),
            calendar: NudgeHostFixture.londonCalendar,
            locale: Locale(identifier: "en_GB"),
            hotKeyRegistrar: InertHotKeyRegistrar(),
            storeKind: .inMemory,
            notificationCentre: SilentNotificationCentre()
        )
    }

    /// The warrant a real question carries, so the scope under test is built the way the
    /// shipping path builds it — `CorrectionScope.from(_:)` and nothing else.
    static func warrant(subject: String) -> QueryWarrant {
        let judgement = NudgeHostFixture.uncertainJudgement(subject: subject)
        guard case .ask(let warrant, _) = NudgeDecider.decide(
            judgement,
            surroundings: NudgeHostFixture.surroundings(monotonic: .seconds(10_000)),
            memory: NudgeMemory(),
            preferences: NudgePreferences()
        ) else {
            fatalError("the decider did not ask about \(subject)")
        }
        return warrant
    }

    static func rules(in context: ModelContext, taskID: UUID) throws -> [FocusSchemaV3.RelevanceRule] {
        try context.fetch(FetchDescriptor<FocusSchemaV3.RelevanceRule>())
            .filter { $0.task?.id == taskID }
    }

    // MARK: - One answer, one rule (R-78, §3.B.9, §3.B.13)

    /// **The duplicate-learned-rule regression, as rows in a store.**
    ///
    /// `QueryLedger.answer(…)` commits the rule *and* the immutable receipt as one transaction.
    /// The root used to match `.ruleAndReceipt` alongside `.rule` in one `case` and hand the
    /// bound rule straight to `addRule(…)`, so a real "Yes, add it" wrote the learned rule twice:
    /// once inside the ledger's transaction under `rule.id`, and once again under a fresh
    /// identifier. Two chips in the context row, two rows in the Rules pane, and a ⌘Z that
    /// removed only the second of them.
    @Test("an answered question leaves exactly one rule, and it is the ledger's own")
    func oneAnswerWritesOneRule() throws {
        let root = Self.root()
        defer { root.stop() }
        let context = root.modelContainer.mainContext
        let priorities = PriorityStore(
            context: context,
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference)
        )
        let taskID = try priorities.setPriority(intent: "Write the Q3 proposal for Acme")
        let task = try priorities.task(id: taskID)

        let manager = UndoManager()
        root.adoptUndoManager(manager)

        // The ledger's own atomic pair — the exact value a real "Yes, add it" produces.
        let ledger = QueryLedger(
            context: context,
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference)
        )
        let outcome = try ledger.answer(
            .yesAddIt,
            priorityID: taskID,
            task: task,
            scope: CorrectionScope.from(Self.warrant(subject: "com.example.Reader")),
            reason: .noNegativeBasis
        )
        guard case .ruleAndReceipt = outcome else {
            Issue.record("the ledger did not commit the atomic pair: \(outcome)")
            return
        }
        #expect(try Self.rules(in: context, taskID: taskID).count == 1)

        // The root performs the outcome. The row is already written, so the only thing still
        // owed is the undo the ledger's transaction had no journal to register with.
        root.perform(outcome)

        #expect(
            try Self.rules(in: context, taskID: taskID).count == 1,
            "the root wrote the ledger's rule a second time under a fresh identifier"
        )
        #expect(manager.canUndo, "R-86's yes row lost its ⌘Z")
    }

    /// The other direction, and the reason the first is not simply "never insert": a correction
    /// made on an **accusation** panel has been written by nobody, so the root is the write.
    @Test("a correction nobody has written is written exactly once, with its undo")
    func anUnwrittenCorrectionIsInserted() throws {
        let root = Self.root()
        defer { root.stop() }
        let context = root.modelContainer.mainContext
        let priorities = PriorityStore(
            context: context,
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference)
        )
        let taskID = try priorities.setPriority(intent: "Write the Q3 proposal for Acme")
        root.refreshCockpit()

        let manager = UndoManager()
        root.adoptUndoManager(manager)

        let outcome = CorrectionAction.thisIsRelevant.outcome(
            scope: CorrectionScope.from(Self.warrant(subject: "com.example.Reader")),
            at: NudgeHostFixture.reference
        )
        guard case .rule = outcome else {
            Issue.record("'this is relevant' did not produce a rule: \(outcome)")
            return
        }
        root.perform(outcome)

        let written = try Self.rules(in: context, taskID: taskID)
        #expect(written.count == 1)
        #expect(written.first?.subject == "com.example.Reader")
        #expect(manager.canUndo)
    }

    // MARK: - The verdict stream really is a stream

    /// **The loop, joined.** A judgement published by the relevance host reaches the nudge loop
    /// and is decided — which is a thing that either happens or does not, rather than a pair of
    /// substrings in a file.
    @Test("a judgement published by the relevance host reaches the nudge loop")
    func theVerdictStreamDrivesTheLoop() throws {
        let root = Self.root()
        defer {
            root.stop()
            root.menuBar.remove()
        }

        // The nudge half of `start()`, without the global hot key and the observer graph — both
        // of which are the machine's, not this test's.
        root.startNudgeLoop()
        try #require(root.relevanceHost.onJudgement != nil, "the stream has no subscriber")

        let before = root.nudgeHost.decisionCount
        root.relevanceHost.onJudgement?(
            NudgeHostFixture.uncertainJudgement(subject: "com.example.Reader")
        )

        #expect(
            root.nudgeHost.decisionCount == before + 1,
            "the verdict stream is not joined to the nudge loop"
        )
    }

    // The badge wire used to be asserted here, as `root.menuBar.onPopoverDidShow != nil`. A
    // non-nil no-op satisfies that, and every other suite that opened a popover installed a
    // closure of its own — so the shipping wire was never run by anything and its deletion cost
    // nothing. It is driven at its far end in `CompositionRootWireTests`, along with the other
    // three wires that had the same shape of defect (focus-22m).

    // MARK: - The relevance host publishes, and nothing acts back into it

    /// e04's "this host publishes; nothing acts" survives in the direction that matters: the
    /// acting cannot reach back into the judging. The executable form of that is a sequence
    /// assertion — by the time the subscriber runs, the judgement is already made and stored, so
    /// there is nothing left for a subscriber to influence.
    @Test("the relevance host publishes a judgement it has already made")
    func theRelevanceHostPublishesAfterJudging() throws {
        let root = Self.root()
        defer { root.stop() }
        let context = root.modelContainer.mainContext
        let priorities = PriorityStore(
            context: context,
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference)
        )
        try priorities.setPriority(intent: "Write the Q3 proposal for Acme")
        root.relevanceHost.invalidateSnapshot()

        var published: [NudgeJudgement] = []
        var verdictWhenPublished: [VerdictSnapshot?] = []
        root.relevanceHost.onJudgement = { judgement in
            published.append(judgement)
            verdictWhenPublished.append(root.relevanceHost.verdict)
        }

        root.relevanceHost.observe(
            JudgeableSubject(bundleIdentifier: "com.example.Reader", isSuppressed: false),
            phase: .focus,
            isUserIdle: false
        )

        try #require(published.count == 1, "one observation produced \(published.count) judgements")
        // The verdict the host holds at the moment it publishes is the judgement's own: the
        // judging is finished before the acting starts.
        #expect(verdictWhenPublished.first ?? nil == published.first?.snapshot)
        #expect(root.relevanceHost.judgementCount == 1)
    }
}
