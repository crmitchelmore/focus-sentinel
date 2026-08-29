import Foundation
import Testing

@testable import FocusCore

/// **One open interruption at a time, and whoever got there first keeps it** (R-84a as amended by
/// U-2).
///
/// The asymmetry this suite used to assert — an accusation always admitted, closing an open
/// question as `declined` — is gone. Seven repair rounds found roughly eleven defects inside that
/// one interaction and the user ruled the mechanism out rather than patching the eleventh. What is
/// asserted here now is the rule that replaced it: **an accusation offered against an open question
/// is withheld, and waits.**
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
        #expect(asked.slot?.isOpen == false)

        let accused = InterruptionSlot.open.offering(Self.rung())
        #expect(accused.slot?.openAccusation == Self.rung())
    }

    // MARK: - Neither displaces the other

    /// **An accusation offered against an open question waits** (U-2).
    ///
    /// This is the single most important line of the scope cut. The question keeps the screen, the
    /// accusation is withheld as `interruptionInFlight`, and nothing about the question is written,
    /// settled or forgotten — the person finishes answering the cheap teaching question, and the
    /// accusation arrives on the next judgement.
    @Test("an accusation offered against an open question is withheld, and the question stands")
    func accusationWaitsForAQuestion() throws {
        let held = try #require(InterruptionSlot.open.offering(Self.warrant()).slot)
        #expect(held.openQuery != nil)

        let outcome = held.offering(Self.rung())
        #expect(
            outcome.slot == nil,
            "an accusation took the slot from an open question: preemption is supposed to be gone"
        )
        #expect(outcome.withholdingReason == .interruptionInFlight)

        // The question is exactly where it was — not closed, not declined, not expired.
        #expect(held.openQuery == Self.warrant())
        #expect(held.openAccusation == nil)

        // …against every rung, not just the panel.
        for kind in LadderRung.Kind.allCases {
            #expect(
                held.offering(Self.rung(kind: kind)).withholdingReason == .interruptionInFlight,
                "the \(kind.rawValue) rung displaced an open question"
            )
        }
    }

    /// The direction that was already withheld, and still is.
    @Test("a question offered against a live accusation is withheld")
    func questionNeverPreemptsAnAccusation() throws {
        let held = try #require(InterruptionSlot.open.offering(Self.rung()).slot)

        let outcome = held.offering(Self.warrant())
        #expect(outcome.slot == nil, "a question took the slot from an accusation")
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
    /// `LadderMachine`'s question, not the slot's — the same mandate simply moved up a rung.
    @Test("an accusation replaces an accusation, which is the ladder escalating")
    func accusationReplacesAccusation() throws {
        let held = try #require(
            InterruptionSlot.open.offering(Self.rung(kind: .ambient)).slot
        )
        let escalated = held.offering(Self.rung(kind: .panel))
        #expect(escalated.slot?.openAccusation?.kind == .panel)
        #expect(escalated.withholdingReason == nil)
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
