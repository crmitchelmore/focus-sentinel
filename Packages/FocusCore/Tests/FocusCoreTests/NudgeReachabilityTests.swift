import Foundation
import Testing

@testable import FocusCore

/// **Can the app's own sequence of events actually reach the states the policy promises?**
/// (focus-yxb)
///
/// Every other suite here drives a reducer directly, which is the right way to test a reducer and
/// the wrong way to learn whether a *product* behaviour happens. `LadderMachineTests` folds
/// `.rungIgnored` in `ignoredAccusationBackoff` times in a row; `FatigueControllerTests` folds
/// `.accusationResolved(.ignored)` the same number of times. Both pass, and neither sequence is
/// one `NudgeHost` can produce: `.rungIgnored` is emitted only by `resolve(_:)`, for the single
/// non-de-escalating `CorrectionAction` there is — `.dismiss` — and a dismissal takes the rung
/// down, so the next one needs another *delivery*.
///
/// So this suite drives what the host drives — drift, glyph, escalation, panel, dismiss, repeat —
/// and asks which promised states are on the other side of it. It exists because the reasoning
/// recorded beside `ignoredAccusationBackoff` was wrong in a way no test could catch: it argued
/// from `LadderMachine` alone about a constant with **two consumers whose runs are scoped
/// differently**, and the two answers are different.
@Suite("What the loop's own sequence can actually reach")
struct NudgeReachabilityTests {
    /// One round of the whole interaction, for one drift subject: the mandate arrives, the glyph
    /// goes out, `escalationDwell` passes, the panel goes out, and the person dismisses it.
    ///
    /// The two `reduce` calls at the end are exactly what `NudgeHost.resolve(_:)` performs for a
    /// `.dismiss`: the ladder is told the rung went unanswered, and the fatigue controller is told
    /// the accusation resolved as `.dismissed`.
    @discardableResult
    private static func driftAndDismiss(
        subject: String,
        ladder: inout LadderMachine,
        fatigue: inout FatigueController,
        at: inout Duration
    ) -> (entry: LadderRung.Kind, escalated: LadderRung.Kind)? {
        ladder.reduce(.mandate(LadderMachineTests.mandate(subject: subject)), now: at)

        guard let entry = ladder.offer(at: at, budgetPermits: true) else { return nil }
        ladder.reduce(.delivery(.delivered(.menuBar)), now: at)
        at = at + RelevancePolicy.escalationDwell

        guard let escalated = ladder.offer(at: at, budgetPermits: true) else { return nil }
        ladder.reduce(.delivery(.delivered(.panel)), now: at)

        ladder.reduce(.rungIgnored, now: at)
        fatigue.reduce(.accusationResolved(.dismissed), now: at)

        at = at + RelevancePolicy.mandateCooldown
        return (entry.kind, escalated.kind)
    }

    /// **The backoff is reachable, and this is the sequence that reaches it.**
    ///
    /// Two dismissals about two *different* subjects, with a full climb between them, which is a
    /// perfectly ordinary afternoon. `FatigueController`'s run is a fact about the session and
    /// nothing but an answered accusation resets it, so it carries across the subject change —
    /// and the hold it sets is what the suppression stack reads.
    ///
    /// This is the claim the constant's justification should have made and did not. It also shows
    /// the old rationale was false rather than merely unlucky: a backoff of 3 would have tripped
    /// here too, on a third subject.
    @Test("two dismissed nudges in a session hold the ladder at the glyph")
    func theBackoffIsReachable() {
        var ladder = LadderMachine()
        var fatigue = FatigueController()
        var at = Duration.seconds(0)

        for round in 1...InterventionPolicy.ignoredAccusationBackoff {
            let rungs = Self.driftAndDismiss(
                subject: "com.example.decoy\(round)", ladder: &ladder, fatigue: &fatigue, at: &at
            )
            #expect(rungs?.entry == .ambient, "round \(round) did not start at the glyph")
            #expect(rungs?.escalated == .panel, "round \(round) did not reach the panel")

            let isLast = round == InterventionPolicy.ignoredAccusationBackoff
            #expect(
                fatigue.state.isHeldAtAmbient(now: at) == isLast,
                """
                after \(round) dismissed nudge(s) the session hold was \
                \(fatigue.state.isHeldAtAmbient(now: at)), expected \(isLast)
                """
            )
        }

        // Held is not silent (F-146): the glyph is still the channel the person has not objected
        // to, and only the panel is refused.
        #expect(
            FatigueController.decide(
                kind: .accusation, subject: "com.example.decoy1", rung: .ambient,
                budget: .empty, fatigue: fatigue.state, snoozes: .none,
                correctedSubjects: [], now: at
            ) == .permitted
        )
        #expect(
            FatigueController.decide(
                kind: .accusation, subject: "com.example.decoy1", rung: .panel,
                budget: .empty, fatigue: fatigue.state, snoozes: .none,
                correctedSubjects: [], now: at
            ) == .refused(.heldAtAmbient(until: fatigue.state.accusationsHeldUntil))
        )
    }

    /// **`LadderMachine`'s own run cannot pass one, in anything the host can do.**
    ///
    /// Two things close it off, and this drives both: a *different* subject sends `arrive(_:)`
    /// back to `.idle`, and the *same* subject has nothing above the panel for `candidate(…)` to
    /// offer. Either way there is never a second rung for the host to ignore, so
    /// `LadderState.heldAtAmbient` is not reachable from `NudgeHost`'s events and the ladder is
    /// quiet for that subject by arithmetic rather than by decision.
    ///
    /// It is asserted rather than repaired because it is **not** the whole picture: the replay
    /// model can script an ignored *ambient* rung — `seq-0023` in the evaluation corpus does
    /// exactly that — and two ignores of one subject reach the hold there. Whether a glyph the
    /// host offers no way to dismiss should be ignorable in the model is a question for the
    /// round that owns the corpus. What is pinned here is the divergence itself, so it cannot
    /// widen unnoticed.
    @Test("no drift the host can produce gives the ladder a second rung to ignore")
    func theLaddersOwnRunCannotPassOne() {
        var ladder = LadderMachine()
        var fatigue = FatigueController()
        var at = Duration.seconds(0)

        for round in 1...4 {
            Self.driftAndDismiss(
                subject: "com.example.decoy\(round)", ladder: &ladder, fatigue: &fatigue, at: &at
            )
            #expect(
                ladder.state.consecutiveIgnored == 1,
                """
                round \(round) left the ladder's run at \(ladder.state.consecutiveIgnored); \
                a subject change resets it, so it can only ever stand at one
                """
            )
            if case .heldAtAmbient = ladder.state {
                Issue.record(
                    """
                    round \(round): the ladder reached its own hold, which no host sequence \
                    could reach when this was written — re-read focus-yxb before relaxing the \
                    justification on ignoredAccusationBackoff
                    """
                )
            }
            // The same subject, however long it goes on, offers nothing more to ignore.
            #expect(
                ladder.candidate(at: at + .seconds(86_400), budgetPermits: true) == nil,
                "round \(round): the ladder offered a rung after its subject was ignored"
            )
        }
    }

    /// **The stored ignore count never stands at the threshold**, so nothing may ask it whether
    /// the hold is on.
    ///
    /// `FatigueController.resolvingAccusation(_:unanswered:now:)` writes `trips ? 0 : run`: the
    /// counter is *zeroed* by the trip and the hold is recorded in `accusationsHeldUntil`
    /// instead. `FatigueState.hasReachedAccusationBackoff` compared the counter against the
    /// constant and was therefore `false` for every state the controller can produce — a
    /// permanent negative, deleted in focus-yxb. This is the property that made it one.
    @Test("the ignored-accusation counter never reaches the constant it is compared against")
    func theStoredCountNeverStandsAtTheThreshold() {
        var fatigue = FatigueController()
        var at = Duration.seconds(0)

        for _ in 1...(InterventionPolicy.ignoredAccusationBackoff * 3) {
            fatigue.reduce(.accusationResolved(.dismissed), now: at)
            #expect(
                fatigue.state.consecutiveIgnoredAccusations
                    < InterventionPolicy.ignoredAccusationBackoff,
                """
                the stored run reached \(fatigue.state.consecutiveIgnoredAccusations); if it can \
                now stand at the threshold, a predicate comparing the two is worth having again
                """
            )
            at = at + RelevancePolicy.mandateCooldown
        }
        #expect(fatigue.state.isHeldAtAmbient(now: at))
    }
}
