import Foundation
import Testing
@testable import FocusCore

/// **A dial turned is a decision changed** (focus-exdi): each reducer that reads a constant is
/// shown reading the dial instead, with the shipped value as the control.
@Suite("Policy dials reach the reducers")
struct PolicyTuningsReachTheReducersTests {
    @Test("the daily interruption cap is the dial's, not the constant's")
    func budgetReadsTheDial() {
        let charges = (0..<InterventionPolicy.dailyInterruptionCap).map { _ in InterruptionCharge(.accusation) }
        let spent = InterruptionBudget.spent(charges, underPriority: nil)
        #expect(!spent.permits(.accusation), "the control: the shipped cap is exhausted")
        var wider = PolicyTunings.shipped
        wider.set(.dailyInterruptionCap, to: Double(InterventionPolicy.dailyInterruptionCap + 4))
        wider.set(.dailyAccusationCap, to: Double(InterventionPolicy.dailyInterruptionCap + 4))
        #expect(spent.permits(.accusation, tunings: wider), "a wider cap did not widen the budget")
        #expect(spent.remaining(for: .accusation, tunings: wider) == 4)
    }

    @Test("the question cooldown is the dial's")
    func fatigueReadsTheDial() {
        let state = FatigueState(
            lastQueryAt: .seconds(0), lastAccusationAt: nil,
            consecutiveUnansweredQueries: 0, consecutiveIgnoredAccusations: 0,
            queriesSuspendedUntil: nil, accusationsHeldUntil: nil
        )
        let justUnderShipped = InterventionPolicy.queryCooldown - .seconds(1)
        #expect(!state.cooledDown(.query, now: justUnderShipped), "the control")
        var shorter = PolicyTunings.shipped
        shorter.set(.queryCooldown, to: PolicyTuning.queryCooldown.range.lowerBound)
        #expect(state.cooledDown(.query, now: justUnderShipped, tunings: shorter))
    }

    @Test("the backoff span is the dial's")
    func backoffReadsTheDial() {
        // One unanswered question short of the backoff, then one more goes unanswered.
        let state = FatigueState(consecutiveUnansweredQueries: InterventionPolicy.ignoredQueryBackoff - 1)
        let shipped = FatigueController.reduce(state, event: .queryResolved(.expired), now: .seconds(0))
        #expect(shipped.queriesSuspendedUntil == InterventionPolicy.backoffSpan, "the control")
        var shorter = PolicyTunings.shipped
        shorter.set(.backoffSpan, to: PolicyTuning.backoffSpan.range.lowerBound)
        let tuned = FatigueController.reduce(state, event: .queryResolved(.expired), now: .seconds(0), tunings: shorter)
        #expect(tuned.queriesSuspendedUntil == .seconds(PolicyTuning.backoffSpan.range.lowerBound))
        // And a higher backoff count means this one does not trip at all.
        var patient = PolicyTunings.shipped
        patient.set(.ignoredQueryBackoff, to: Double(InterventionPolicy.ignoredQueryBackoff + 1))
        let untripped = FatigueController.reduce(state, event: .queryResolved(.expired), now: .seconds(0), tunings: patient)
        #expect(untripped.queriesSuspendedUntil == nil)
    }
}
