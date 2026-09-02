import Foundation
import Testing

@testable import FocusCore

/// **The second closed set that was swept by reading, folded** (focus-w3z, focus-1ua).
///
/// ## What was true before this suite
///
/// `QueryWithholdingReason` has twelve cases and is `CaseIterable`, and **nothing folded over
/// it.** `QueryInvariantTests` proves the raw values are distinct and stable, counts
/// `allCases.count == 12`, and drives about six of the twelve by hand through its cross-product.
/// So a reason could be *declared and unproducible* — a silence nobody can reach — or produced by
/// the wrong gate, and only a hand-written spot test would have noticed. This programme has
/// measured the difference the method makes: the folded vocabularies produced zero defects and
/// the unfolded ones produced four.
///
/// And the type's own doc made a claim about itself that was false: *"the declaration order is
/// R-84's evaluation order"*. `decide(…)` produced `noSingleSubject` at **two** positions —
/// `drift.isMixed` before `withinDwellGrace` and `QuerySubject.derive(…)` after it — so the
/// declaration was not a total order at all and no reading could have made the sentence true.
/// The two producers are adjacent now, and this suite is what checks the claim rather than
/// restating it.
///
/// ## The shape of the fold, and why it proves the order as well as the production
///
/// One row per case, in declaration order. For case *i* the world has **every gate from *i*
/// onwards closed** and every gate before it open; the answer must be case *i*. That single
/// arrangement carries three assertions at once:
///
/// * the case is **producible** — something drives it, so a declared-and-unreachable silence
///   fails here rather than shipping;
/// * it is produced by **its own** gate, not by a neighbour;
/// * it **outranks** every case below it, which is the order claim, checked pairwise across the
///   whole vocabulary rather than asserted in prose.
///
/// ## The completeness check
///
/// `allCases` is the space and the fold walks it; a case added without an opener fails to
/// compile in `World.closing(_:)`, and a case added without a row is caught by the count.
///
/// ## The vacuity guard, stated
///
/// A fold whose every world withheld would satisfy every row above by never warranting anything,
/// so the fully open world is asserted to **warrant a question** — and the fold asserts that it
/// really did close each gate one at a time by requiring twelve distinct answers.
@Suite("Every silence the question path can answer with")
struct QueryWithholdingTests {
    static let stamp = EngineStamp.current
    static let subject = "com.apple.Safari"

    static var explanation: Explanation {
        Explanation.make(
            stage: .heuristic,
            band: .medium,
            clauses: [.noNegativeBasis, .insufficientEvidence(reason: .noNegativeBasis)],
            stamp: stamp
        )
    }

    /// Everything `decide(…)` reads, with every gate **open**: the one world that warrants.
    struct World {
        var verdict: Verdict = .uncertain
        var hasActivePriority = true
        var isUserIdle = false
        var phase: SessionPhase = .focus
        var status: FocusStatus = .uncertain
        var interruptionInFlight = false
        var budgetPermits = true
        var hasAsked = false
        var uncertainty: UncertaintyReason? = .noNegativeBasis
        var drift: DriftState = .sustained(
            subject: .single(QueryWithholdingTests.subject),
            accumulated: .seconds(60),
            isMixed: false
        )
        var judgedSubject: String? = QueryWithholdingTests.subject
        var dwellSatisfied = true

        /// Shut one gate. **Exhaustive**, so a thirteenth reason does not compile until somebody
        /// has said what world produces it — which is the whole difference between a folded
        /// vocabulary and a counted one.
        func closing(_ reason: QueryWithholdingReason) -> World {
            var world = self
            switch reason {
            case .verdictRelevant: world.verdict = .relevant
            case .verdictUnrelated: world.verdict = .unrelated
            case .noActivePriority: world.hasActivePriority = false
            case .userIdle: world.isUserIdle = true
            case .sessionPhaseForbids: world.phase = .paused
            case .statusForbids: world.status = .relevant
            case .interruptionInFlight: world.interruptionInFlight = true
            case .budgetExhausted: world.budgetPermits = false
            case .alreadyAsked: world.hasAsked = true
            case .reasonNotAskable: world.uncertainty = .noEvidence
            case .noSingleSubject:
                world.drift = .sustained(subject: .mixed, accumulated: .seconds(60), isMixed: true)
            case .withinDwellGrace: world.dwellSatisfied = false
            }
            return world
        }

        func decide() -> QueryEligibility {
            QueryEligibility.decide(
                outcome: ClassificationOutcome(
                    verdict: verdict, source: .heuristic, confidence: 0.5, band: .medium
                ),
                uncertainty: uncertainty,
                drift: drift,
                dwelled: .seconds(60),
                dwellSatisfied: dwellSatisfied,
                phase: phase,
                status: status,
                isUserIdle: isUserIdle,
                hasActivePriority: hasActivePriority,
                hasAsked: hasAsked,
                budgetPermits: budgetPermits,
                interruptionInFlight: interruptionInFlight,
                judgedSubject: judgedSubject,
                explanation: QueryWithholdingTests.explanation,
                stamp: QueryWithholdingTests.stamp
            )
        }
    }

    @Test("every reason is produced by its own gate, and outranks every reason below it")
    func everyReasonIsDrivenInDeclarationOrder() {
        let order = QueryWithholdingReason.allCases
        var produced: [QueryWithholdingReason] = []

        for (index, reason) in order.enumerated() {
            // Every gate from this one down, shut. Applied in reverse so that where two cases
            // share one input — the verdict is `relevant` **or** `unrelated`, never both — the
            // earlier-declared one is the one left standing, which is what "outranks" means for
            // a pair that cannot be closed together.
            var world = World()
            for later in order[index...].reversed() {
                world = world.closing(later)
            }

            guard let answer = world.decide().withholdingReason else {
                Issue.record(
                    "\(reason.rawValue): a world with every gate from it downwards shut warranted a question"
                )
                continue
            }
            #expect(
                answer == reason,
                """
                \(reason.rawValue) was expected to answer for a world with gates \
                \(order[index...].map(\.rawValue)) shut, and \(answer.rawValue) answered instead \
                — either it is unreachable, or the declaration order is not the evaluation order
                """
            )
            produced.append(answer)
        }

        // — the completeness check, self-referential —
        #expect(
            produced == order,
            """
            the fold produced \(produced.map(\.rawValue)) against a vocabulary of \
            \(order.map(\.rawValue)): a reason is declared and unproducible, or produced out of order
            """
        )
        #expect(!order.isEmpty, "the space is empty, so the fold proves nothing")
        #expect(
            Set(produced).count == order.count,
            "two rows produced the same reason, so a gate was never really shut"
        )

        // — the vacuity guard, stated —
        let open = World()
        #expect(
            open.decide().isWarranted,
            "the world with every gate open asked nothing, so every row above is satisfied by silence"
        )
    }

    /// **The second producer of `noSingleSubject`, which is the one the order claim tripped on**
    /// (focus-w3z).
    ///
    /// `drift.isMixed` is the first; `QuerySubject.derive(…)` finding nothing to name is this
    /// one. They are one question asked of two values, they are adjacent in `decide(…)` now, and
    /// the row above drives only the first — so this drives the second, with the drift explicitly
    /// **not** mixed so it cannot pass for its neighbour.
    @Test("a judgement with no subject to name is the second producer of noSingleSubject")
    func theOtherProducerOfNoSingleSubject() {
        var world = World()
        world.judgedSubject = nil
        #expect(!world.drift.isMixed, "the drift is mixed, so this row drives the other producer")
        #expect(world.decide().withholdingReason == .noSingleSubject)

        // And it outranks the dwell, which is what moving it above `dwellSatisfied` decided: a
        // judgement that is both inside the grace period and about nothing nameable is told the
        // more permanent of the two reasons.
        world.dwellSatisfied = false
        #expect(world.decide().withholdingReason == .noSingleSubject)
    }
}
