import Foundation
import Testing

@testable import FocusCore

/// **The fourth answer to "why did the app go quiet?", folded** (focus-628, focus-50m,
/// focus-1ua).
///
/// ## What this suite is, and which measurement asked for it
///
/// This programme has measured its own method: a closed set folded over with a completeness
/// check and a stated vacuity guard produced **zero** defects; a closed set swept by reading
/// prose produced **four**. `NudgeSuppressionReason` and `FatigueRefusal.Kind` were folded and
/// each declares a `SilenceSubject`. `LadderMachine` was the third answer to the same question
/// and was in neither: it was not `CaseIterable`, it declared no subject, and **it silenced by
/// arithmetic** — `candidate(at:budgetPermits:)` answered `nil` and `NudgeDecider.accuse(…)`
/// turned that `nil` into `.silent(.budgetExhausted)`, taking with it the one channel R-87, F-63
/// and F-146 all exempt by name.
///
/// `LadderSilence` is that vocabulary. This is one row per case, each **driving the state that
/// produces it** through the reducer rather than constructing the case by hand — because a
/// vocabulary whose cases are asserted about but never produced is exactly the
/// declared-and-unreachable shape the round is about.
///
/// ## The completeness check
///
/// `Table.rows` is keyed by `LadderSilence` and `everySilenceIsDriven` fails when a case is
/// added without a row, when a row's state cannot be reached, and when the vocabulary is empty.
///
/// ## The vacuity guard, stated
///
/// A table of five rows all saying "silent, retains nothing" would be green for an app that
/// never marks anybody, and a table all saying "retains the mark" would be green for one that
/// re-marks through a dwell and therefore never climbs. So the fold asserts **both** answers
/// occur, and it asserts that the two facts `retainsTheAmbientRung` is derived from vary
/// independently: `noLiveMandate` refuses the climb and retains nothing (its subject stops every
/// rung), `escalationDwell` passes the rung that says nothing and retains nothing (the ladder is
/// pacing itself, and the rung it delivered is still standing). Neither conjunct is carrying the
/// answer alone.
@Suite("The ladder's silence is a vocabulary with a subject")
struct LadderSilenceTests {
    static let stamp = EngineStamp.current

    /// A real mandate, built through e04's one producer. There is no other way to obtain one,
    /// which is the point.
    static func mandate(_ subject: String = "com.chrismitchelmore.FocusDecoy") -> InterventionMandate {
        let explanation = Explanation.make(
            stage: .heuristic,
            band: .medium,
            clauses: [.sustainedDwell(seconds: 120)],
            stamp: stamp
        )
        let eligibility = InterventionEligibility.decide(
            outcome: ClassificationOutcome(
                verdict: .unrelated, source: .heuristic, confidence: 1, band: .medium
            ),
            drift: .sustained(subject: .single(subject), accumulated: .seconds(120), isMixed: false),
            phase: .focus,
            status: .unrelated,
            isUserIdle: false,
            hasActivePriority: true,
            explanation: explanation,
            stamp: stamp
        )
        guard let mandate = eligibility.mandate else {
            fatalError("e04's producer refused to mandate on inputs that must mandate")
        }
        return mandate
    }

    /// One row: the machine in the state that produces this silence, and the reading to take.
    struct Row {
        let machine: LadderMachine
        let at: Duration
        let budgetPermits: Bool
        let subject: SilenceSubject
        let refusesTheClimb: Bool
        let retainsTheAmbientRung: Bool
        /// What `LadderMachine.retainedRung` answers in this state — read separately from
        /// `retainsTheAmbientRung`, so that "the ladder had nothing to give" and "the silence
        /// declined to give it" cannot pass for one another.
        let retainedRung: LadderRung.Kind?
    }

    /// A ladder standing on a delivered ambient rung at `t = 0`.
    static func engagedAtAmbient() -> LadderMachine {
        var machine = LadderMachine()
        machine.reduce(.mandate(mandate()), now: .seconds(0))
        machine.offer(at: .seconds(0), budgetPermits: true)
        machine.reduce(.delivery(.delivered(.menuBar)), now: .seconds(0))
        return machine
    }

    /// A ladder standing on a delivered panel rung — the top of the ladder (U-2).
    static func engagedAtPanel() -> LadderMachine {
        var machine = engagedAtAmbient()
        let due = RelevancePolicy.escalationDwell
        machine.reduce(.mandate(mandate()), now: due)
        machine.offer(at: due, budgetPermits: true)
        machine.reduce(.delivery(.delivered(.panel)), now: due)
        return machine
    }

    /// A ladder held at the ambient rung by `InterventionPolicy.ignoredAccusationBackoff`
    /// unanswered rungs.
    static func heldAtAmbient() -> LadderMachine {
        var machine = engagedAtAmbient()
        for _ in 0..<InterventionPolicy.ignoredAccusationBackoff {
            machine.reduce(.rungIgnored, now: .seconds(0))
        }
        return machine
    }

    /// **The table.** Every expectation is a literal here and never the rule read back.
    static var rows: [LadderSilence: Row] {
        var idle = LadderMachine()
        idle.reduce(.tick(.seconds(0)), now: .seconds(0))

        let dwellNotYet = RelevancePolicy.escalationDwell - .seconds(1)
        let dwellDone = RelevancePolicy.escalationDwell

        return [
            .noLiveMandate: Row(
                machine: idle,
                at: .seconds(0),
                budgetPermits: true,
                subject: .anythingToBeLegibleAbout,
                refusesTheClimb: true,
                retainsTheAmbientRung: false,
                retainedRung: nil
            ),
            .escalationDwell: Row(
                machine: engagedAtAmbient(),
                at: dwellNotYet,
                budgetPermits: true,
                subject: .theAppSpeaking,
                refusesTheClimb: false,
                retainsTheAmbientRung: false,
                // **The ladder has one to hand over and the silence declines it.** The glyph it
                // is standing on says nothing, so `retainedRung` is not `nil` here — and the row
                // above says the mark is not owed anyway, because re-delivering it would restart
                // the very clock the dwell measures. Both halves are read, so a row cannot pass
                // by the machine having had nothing to give.
                retainedRung: .ambient
            ),
            .budgetRefused: Row(
                machine: engagedAtAmbient(),
                at: dwellDone,
                budgetPermits: false,
                subject: .theAppSpeaking,
                refusesTheClimb: true,
                retainsTheAmbientRung: true,
                retainedRung: .ambient
            ),
            .toppedOut: Row(
                machine: engagedAtPanel(),
                at: dwellDone + RelevancePolicy.escalationDwell,
                budgetPermits: true,
                subject: .theAppSpeaking,
                refusesTheClimb: false,
                retainsTheAmbientRung: false,
                // A rung that SPEAKS is standing, so there is nothing to fall back to: taking a
                // sentence off the screen to replace it with a mark would be a climb-down.
                retainedRung: nil
            ),
            .heldAtAmbient: Row(
                machine: heldAtAmbient(),
                at: .seconds(60),
                budgetPermits: true,
                subject: .theAppSpeaking,
                refusesTheClimb: true,
                retainsTheAmbientRung: true,
                retainedRung: .ambient
            )
        ]
    }

    @Test("every silence the ladder can answer with is driven, and declares what it is about")
    func everySilenceIsDriven() {
        var driven: Set<LadderSilence> = []

        for silence in LadderSilence.allCases {
            guard let row = Self.rows[silence] else {
                Issue.record("\(silence.rawValue) has no row, so nothing drives the state it names")
                continue
            }

            let offer = row.machine.step(at: row.at, budgetPermits: row.budgetPermits)
            guard offer.silence == silence else {
                Issue.record(
                    """
                    \(silence.rawValue)'s row produced \
                    \(offer.silence?.rawValue ?? "a rung: \(offer.rung?.kind.rawValue ?? "?")") \
                    — the state this case names is not the state the row drives
                    """
                )
                continue
            }
            driven.insert(silence)

            #expect(offer.rung == nil, "\(silence.rawValue) answered a rung and a silence at once")
            #expect(silence.subject == row.subject, "\(silence.rawValue) is about the wrong thing")
            #expect(
                silence.refusesTheClimb == row.refusesTheClimb,
                "\(silence.rawValue) disagrees about whether it refused the climb"
            )
            #expect(
                silence.retainsTheAmbientRung == row.retainsTheAmbientRung,
                "\(silence.rawValue) disagrees about whether the mark is still owed"
            )
            #expect(
                row.machine.retainedRung?.kind == row.retainedRung,
                "\(silence.rawValue) offered the wrong fallback rung"
            )
            // The rule itself, applied to this row rather than restated: a silence that retains
            // the mark is one whose subject PASSES a rung that says nothing.
            #expect(
                silence.retainsTheAmbientRung
                    == (silence.refusesTheClimb && silence.subject.ruling(for: .ambient) == .passes),
                "\(silence.rawValue) is not the conjunction it says it is"
            )
        }

        // — the completeness check, self-referential —
        #expect(
            driven == Set(LadderSilence.allCases),
            """
            \(Set(LadderSilence.allCases).subtracting(driven).map(\.rawValue)) were never driven, \
            so the space this suite claims to fold over is larger than the fold
            """
        )
        #expect(!LadderSilence.allCases.isEmpty, "the space is empty, so the fold proves nothing")

        // — the vacuity guard, stated —
        #expect(
            LadderSilence.allCases.contains(where: { $0.retainsTheAmbientRung }),
            "no silence retains the mark: the app has stopped being legible"
        )
        #expect(
            LadderSilence.allCases.contains(where: { !$0.retainsTheAmbientRung }),
            "every silence retains the mark: a dwell would re-mark and the ladder would never climb"
        )
        // Both conjuncts carry a case on their own, so neither is decorative.
        #expect(
            LadderSilence.noLiveMandate.refusesTheClimb
                && !LadderSilence.noLiveMandate.retainsTheAmbientRung,
            "the subject stopped deciding anything: a silence about legibility retained the mark"
        )
        #expect(
            LadderSilence.escalationDwell.subject.ruling(for: .ambient) == .passes
                && !LadderSilence.escalationDwell.retainsTheAmbientRung,
            "the climb/pacing distinction stopped deciding anything: a dwell retained the mark"
        )
    }

    @Test("every state the ladder can be in is in the folded vocabulary")
    func everyStateHasAKind() {
        let driven: Set<LadderState.Kind> = [
            LadderMachine().state.kind,
            Self.engagedAtAmbient().state.kind,
            Self.heldAtAmbient().state.kind
        ]
        #expect(
            driven == Set(LadderState.Kind.allCases),
            """
            \(Set(LadderState.Kind.allCases).subtracting(driven).map(\.rawValue)) were never \
            reached, so a state could be added and left unproven
            """
        )
        #expect(!LadderState.Kind.allCases.isEmpty, "the space is empty, so the fold proves nothing")
    }

    /// **What the hold owes, and what it must not do about it** (focus-50m).
    ///
    /// The mark is delivered again on every live mandate — a mark naming an application the
    /// person left an hour ago is not the state being legible — and the delivery must not restart
    /// the climb, or the hold would last exactly one glyph.
    @Test("the hold delivers the mark it retains, and stays held while it does")
    func theHoldKeepsTheMarkAndTheHold() {
        var machine = Self.heldAtAmbient()
        let at = Duration.seconds(60)

        machine.reduce(.mandate(Self.mandate("com.example.Somewhere.Else")), now: at)
        guard let retained = machine.retainedRung else {
            Issue.record("the hold owed no mark at all")
            return
        }
        #expect(retained.kind == .ambient)
        #expect(
            retained.subject == "com.example.Somewhere.Else",
            "the mark named the application the person had already left"
        )

        machine.offer(retained)
        machine.reduce(.delivery(.delivered(.menuBar)), now: at)

        guard case .heldAtAmbient = machine.state else {
            Issue.record("delivering the retained mark restarted the climb: \(machine.state)")
            return
        }
        #expect(
            machine.step(at: at, budgetPermits: true).silence == .heldAtAmbient,
            "the hold had something above the ambient rung to offer"
        )
    }
}
