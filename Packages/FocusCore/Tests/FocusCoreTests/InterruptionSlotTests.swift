import Foundation
import Testing

@testable import FocusCore

/// One open interruption at a time, and the accusation wins — in one direction only (R-84a).
@Suite("Interruption slot")
struct InterruptionSlotTests {
    static let stamp = EngineStamp.current

    static func explanation(_ clauses: [ExplanationClause], band: EvidenceBand) -> Explanation {
        Explanation.make(stage: .heuristic, band: band, clauses: clauses, stamp: stamp)
    }

    /// A real warrant, through its one producer. There is no other way to obtain one.
    static func warrant(subject: String = "com.chrismitchelmore.FocusDecoy2") -> QueryWarrant {
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
            explanation: explanation([.noNegativeBasis], band: .low),
            stamp: stamp
        )
        guard let warrant = eligibility.warrant else {
            fatalError("the query producer refused to warrant on inputs that must warrant")
        }
        return warrant
    }

    /// A real rung, through e04's one mandate producer and the ladder's one rung producer.
    static func rung(
        subject: String = "com.chrismitchelmore.FocusDecoy",
        kind: LadderRung.Kind = .panel
    ) -> LadderRung {
        let eligibility = InterventionEligibility.decide(
            outcome: ClassificationOutcome(
                verdict: .unrelated, source: .heuristic, confidence: 1, band: .medium
            ),
            drift: .sustained(subject: .single(subject), accumulated: .seconds(120), isMixed: false),
            phase: .focus,
            status: .unrelated,
            isUserIdle: false,
            hasActivePriority: true,
            explanation: explanation([.sustainedDwell(seconds: 120)], band: .medium),
            stamp: stamp
        )
        guard let mandate = eligibility.mandate else {
            fatalError("e04's producer refused to mandate on inputs that must mandate")
        }
        var rung = LadderRung.entry(for: mandate)
        while rung.kind != kind, let next = rung.escalated() { rung = next }
        return rung
    }

    // MARK: - An empty slot admits either

    @Test("an open slot admits a question and admits an accusation")
    func openSlotAdmitsEither() {
        #expect(InterruptionSlot.open.isOpen)
        #expect(InterruptionSlot.open.openQuery == nil)
        #expect(InterruptionSlot.open.openAccusation == nil)

        let asked = InterruptionSlot.open.offering(Self.warrant())
        #expect(asked.slot?.openQuery == Self.warrant())
        #expect(asked.preempted == nil)
        #expect(asked.slot?.isOpen == false)

        let accused = InterruptionSlot.open.offering(Self.rung())
        #expect(accused.slot?.openAccusation == Self.rung())
        #expect(accused.preempted == nil)
    }

    // MARK: - The asymmetry

    /// **An accusation takes the slot from a question, and the question is closed as
    /// `declined` rather than dropped.** Losing the asking because something more urgent
    /// happened would be exactly the bug never-ask-twice exists to prevent, and it would be
    /// invisible — the symptom is a question that comes back weeks later.
    @Test("an accusation preempts an open question and closes it as declined")
    func accusationPreemptsAQuestion() throws {
        let held = try #require(InterruptionSlot.open.offering(Self.warrant()).slot)
        #expect(held.openQuery != nil)

        let outcome = held.offering(Self.rung())
        let preempted = try #require(outcome.preempted, "the question was dropped, not closed")
        #expect(preempted.warrant == Self.warrant())
        #expect(
            preempted.outcome == .declined,
            "a preempted question must be remembered as declined so it is never asked again"
        )
        #expect(!preempted.outcome.wroteRule, "a preemption is not an answer and writes no rule")
        #expect(!preempted.outcome.isAnswer)

        let taken = try #require(outcome.slot)
        #expect(taken.openAccusation == Self.rung())
        #expect(taken.openQuery == nil)
        #expect(outcome.withholdingReason == nil)
    }

    /// **The reverse never happens.** There is no code path by which a question closes an
    /// accusation: "you are off task" outranks "is this part of it?", and a question about the
    /// very application somebody has drifted into would be the app arguing with itself.
    @Test("a question offered against a live accusation is withheld")
    func questionNeverPreemptsAnAccusation() throws {
        let held = try #require(InterruptionSlot.open.offering(Self.rung()).slot)

        let outcome = held.offering(Self.warrant())
        #expect(outcome.slot == nil, "a question took the slot from an accusation")
        #expect(outcome.preempted == nil)
        #expect(outcome.withholdingReason == .interruptionInFlight)

        // The accusation is exactly where it was.
        #expect(held.openAccusation == Self.rung())

        // …at every rung, not just the panel.
        for kind in LadderRung.Kind.allCases {
            let occupied = try #require(InterruptionSlot.open.offering(Self.rung(kind: kind)).slot)
            #expect(occupied.offering(Self.warrant()).withholdingReason == .interruptionInFlight)
        }
    }

    /// A second question over the first is the same failure as a panel over a nudge: two panels
    /// on screen at once is what makes people uninstall.
    @Test("a question offered against a live question is withheld")
    func questionNeverPreemptsAQuestion() throws {
        let held = try #require(InterruptionSlot.open.offering(Self.warrant()).slot)
        let outcome = held.offering(Self.warrant(subject: "com.apple.Safari"))
        #expect(outcome.withholdingReason == .interruptionInFlight)
        #expect(outcome.slot == nil)
        #expect(held.openQuery == Self.warrant())
    }

    /// An accusation replacing an accusation is the ladder escalating, and whether it *may* is
    /// `LadderMachine`'s question, not the slot's. Nothing is preempted, because nothing was
    /// closed — the same mandate simply moved up a rung.
    @Test("an accusation replaces an accusation with nothing preempted")
    func accusationReplacesAccusation() throws {
        let held = try #require(
            InterruptionSlot.open.offering(Self.rung(kind: .ambient)).slot
        )
        let escalated = held.offering(Self.rung(kind: .panel))
        #expect(escalated.preempted == nil, "an accusation was reported as a closed question")
        #expect(escalated.slot?.openAccusation?.kind == .panel)
    }

    @Test("releasing the slot opens it again for either kind")
    func releasing() throws {
        let held = try #require(InterruptionSlot.open.offering(Self.rung()).slot)
        #expect(!held.isOpen)
        let released = held.released()
        #expect(released.isOpen)
        #expect(released.offering(Self.warrant()).slot?.openQuery != nil)
    }

    // MARK: - The outcome vocabulary

    @Test("exactly two outcomes write a rule, and a decline is not one of them")
    func outcomeVocabulary() {
        #expect(AskedQuestionOutcome.allCases.count == 4)
        #expect(
            Set(AskedQuestionOutcome.allCases)
                == [.answeredRelevant, .answeredUnrelated, .declined, .expired]
        )
        #expect(AskedQuestionOutcome.allCases.filter(\.wroteRule).count == 2)
        #expect(AskedQuestionOutcome.answeredRelevant.wroteRule)
        #expect(AskedQuestionOutcome.answeredUnrelated.wroteRule)
        #expect(!AskedQuestionOutcome.declined.wroteRule)
        #expect(!AskedQuestionOutcome.expired.wroteRule)
        #expect(AskedQuestionOutcome.declined.isAnswer == false)
    }

    @Test("the outcome vocabulary round-trips through Codable on its raw value")
    func outcomeCodable() throws {
        for outcome in AskedQuestionOutcome.allCases {
            let data = try JSONEncoder().encode(outcome)
            #expect(String(decoding: data, as: UTF8.self) == "\"\(outcome.rawValue)\"")
            #expect(try JSONDecoder().decode(AskedQuestionOutcome.self, from: data) == outcome)
        }
    }
}
