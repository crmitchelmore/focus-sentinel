import Foundation
import Testing

@testable import FocusCore

/// The three limits, the shared budget, and the unit a question may never spend (R-83, F-63,
/// F-107).
@Suite("Interruption budget")
struct InterruptionBudgetTests {
    static func budget(
        queriesForPriority: Int = 0,
        queriesAllPriorities: Int = 0,
        accusations: Int = 0,
        interruptions: Int = 0
    ) -> InterruptionBudget {
        InterruptionBudget(
            queriesForPriorityToday: queriesForPriority,
            queriesAllPrioritiesToday: queriesAllPriorities,
            accusationsToday: accusations,
            interruptionsToday: interruptions
        )
    }

    @Test("an empty day permits both kinds, up to their caps")
    func emptyDay() {
        let empty = InterruptionBudget.empty
        #expect(empty.permits(.query))
        #expect(empty.permits(.accusation))
        #expect(empty.remaining(for: .query) == InterventionPolicy.dailyQueryCap)
        #expect(empty.remaining(for: .accusation) == InterventionPolicy.dailyAccusationCap)
        #expect(empty.sharedRemaining == InterventionPolicy.dailyInterruptionCap)
        #expect(empty.bindingLimit(for: .query) == nil)
        #expect(empty.bindingLimit(for: .accusation) == nil)
    }

    // MARK: - The reserved unit

    /// **The rule in this file that is not arithmetic.** Running out of budget on questions and
    /// therefore being unable to say "you are off task" is the failure that defeats the
    /// product, so a query may never spend the last unit of the shared budget.
    ///
    /// Asserted over the whole grid rather than at one point: for **every** reachable
    /// consumption of the shared budget, the accusation's headroom is at least the query's, and
    /// the query's is at least `reservedAccusationUnits` smaller than the raw remainder.
    @Test("a query can never spend the reserved unit, at any point in the day")
    func queryNeverSpendsTheReservedUnit() {
        let cap = InterventionPolicy.dailyInterruptionCap
        for spent in 0...(cap + 2) {
            let budget = Self.budget(interruptions: spent)
            #expect(
                budget.sharedRemainingForQueries
                    == max(0, budget.sharedRemaining - InterventionPolicy.reservedAccusationUnits)
            )
            #expect(
                budget.sharedRemainingForQueries <= budget.sharedRemaining,
                "a query had more shared headroom than an accusation at \(spent) spent"
            )
            if budget.sharedRemaining <= InterventionPolicy.reservedAccusationUnits {
                #expect(
                    !budget.permits(.query),
                    "a query was permitted with only the reserve left, at \(spent) spent"
                )
            }
        }
    }

    /// **The load-bearing cell: one unit left, both offered, the accusation takes it.**
    @Test("with one unit of the shared budget left, the accusation wins and the query loses")
    func withOneUnitLeftTheAccusationWins() {
        let oneLeft = Self.budget(
            interruptions: InterventionPolicy.dailyInterruptionCap
                - InterventionPolicy.reservedAccusationUnits
        )
        #expect(oneLeft.sharedRemaining == InterventionPolicy.reservedAccusationUnits)
        #expect(oneLeft.permits(.accusation), "the accusation could not spend its own reserve")
        #expect(!oneLeft.permits(.query), "a query spent the accusation's reserve")
        #expect(oneLeft.bindingLimit(for: .query) == .reservedForAccusation)

        // And after the accusation takes it, nothing more is delivered today.
        let spent = oneLeft.spending(.accusation)
        #expect(spent.sharedRemaining == 0)
        #expect(!spent.permits(.accusation))
        #expect(!spent.permits(.query))
        #expect(spent.bindingLimit(for: .accusation) == .dailyInterruptionCap)
    }

    // MARK: - The three caps

    @Test("the per-priority query cap bites at four")
    func perPriorityQueryCap() {
        for asked in 0..<InterventionPolicy.dailyQueryCap {
            #expect(Self.budget(queriesForPriority: asked, interruptions: asked).permits(.query))
        }
        let full = Self.budget(
            queriesForPriority: InterventionPolicy.dailyQueryCap,
            queriesAllPriorities: InterventionPolicy.dailyQueryCap,
            interruptions: InterventionPolicy.dailyQueryCap
        )
        #expect(!full.permits(.query))
        #expect(full.bindingLimit(for: .query) == .dailyQueryCap)
        // …and the accusation is untouched by the question's cap.
        #expect(full.permits(.accusation))
    }

    /// **The cap adversarial review added.** A per-priority cap is not a cap on anybody's day:
    /// three priorities in one day would license twelve questions under `dailyQueryCap` alone.
    /// Here the current priority has been asked about only twice — well under its own cap — and
    /// the day cap is what stops the fifth question.
    @Test("the all-priorities day cap bites even when the current priority has room")
    func allPrioritiesDayCap() {
        let day = Self.budget(
            queriesForPriority: 2,
            queriesAllPriorities: InterventionPolicy.dailyQueryCapAllPriorities,
            interruptions: InterventionPolicy.dailyQueryCapAllPriorities
        )
        #expect(day.queriesForPriorityToday < InterventionPolicy.dailyQueryCap)
        #expect(!day.permits(.query), "a third priority bought itself extra questions")
        #expect(day.bindingLimit(for: .query) == .dailyQueryCapAllPriorities)
        #expect(day.permits(.accusation))
    }

    @Test("the accusation cap bites at six")
    func accusationCap() {
        let full = Self.budget(
            accusations: InterventionPolicy.dailyAccusationCap,
            interruptions: InterventionPolicy.dailyAccusationCap
        )
        #expect(!full.permits(.accusation))
        #expect(full.bindingLimit(for: .accusation) == .dailyAccusationCap)
    }

    /// The shared budget must bite **before** both per-kind caps are exhausted, or "shared" is
    /// a word with no consequence. Four questions plus six accusations is ten; the day allows
    /// eight.
    @Test("the shared budget binds before the two per-kind caps do")
    func sharedBudgetBindsFirst() {
        #expect(
            InterventionPolicy.dailyInterruptionCap
                < InterventionPolicy.dailyQueryCap + InterventionPolicy.dailyAccusationCap
        )

        // Four questions and four accusations: both per-kind caps still have room, and the
        // shared budget is what stops the ninth interruption.
        let contended = Self.budget(
            queriesForPriority: InterventionPolicy.dailyQueryCap,
            queriesAllPriorities: InterventionPolicy.dailyQueryCap,
            accusations: 4,
            interruptions: InterventionPolicy.dailyInterruptionCap
        )
        #expect(contended.accusationsToday < InterventionPolicy.dailyAccusationCap)
        #expect(!contended.permits(.accusation))
        #expect(contended.bindingLimit(for: .accusation) == .dailyInterruptionCap)
    }

    // MARK: - Spending

    /// Only a **delivery** spends. A deferred rung nobody could see and a suppressed one the
    /// app chose not to make leave the budget untouched (R-81) — which is why spending is an
    /// explicit call on this value rather than a side effect of offering.
    @Test("a query spends one query unit and one shared unit; an accusation spends its own")
    func spendingIsExplicitAndPerKind() {
        let afterQuery = InterruptionBudget.empty.spending(.query)
        #expect(afterQuery.queriesForPriorityToday == 1)
        #expect(afterQuery.queriesAllPrioritiesToday == 1)
        #expect(afterQuery.accusationsToday == 0)
        #expect(afterQuery.interruptionsToday == 1)

        let afterAccusation = InterruptionBudget.empty.spending(.accusation)
        #expect(afterAccusation.queriesForPriorityToday == 0)
        #expect(afterAccusation.queriesAllPrioritiesToday == 0)
        #expect(afterAccusation.accusationsToday == 1)
        #expect(afterAccusation.interruptionsToday == 1)
    }

    /// A day of alternating interruptions runs out at exactly the shared cap, never past it.
    @Test("no sequence of offers ever delivers more than the shared cap")
    func theSharedCapIsNeverExceeded() {
        var budget = InterruptionBudget.empty
        var delivered = 0
        for step in 0..<20 {
            let kind: InterruptionKind = step.isMultiple(of: 2) ? .query : .accusation
            guard budget.permits(kind) else { continue }
            budget = budget.spending(kind)
            delivered += 1
        }
        #expect(delivered == InterventionPolicy.dailyInterruptionCap)
        #expect(budget.interruptionsToday == InterventionPolicy.dailyInterruptionCap)
        // The reserve did its job: the questions stopped before the accusations did.
        #expect(
            budget.queriesAllPrioritiesToday <= InterventionPolicy.dailyQueryCapAllPriorities
        )
    }

    @Test("a new day starts empty")
    func newDayStartsEmpty() {
        let spent = Self.budget(
            queriesForPriority: 4, queriesAllPriorities: 5, accusations: 3, interruptions: 8
        )
        #expect(spent.startingNewDay() == .empty)
    }

    // MARK: - FatigueState

    @Test("a fresh session has said nothing and permits both kinds")
    func freshFatigue() {
        let fresh = FatigueState.fresh
        #expect(fresh.permits(.query, now: .zero))
        #expect(fresh.permits(.accusation, now: .zero))
        #expect(!fresh.hasReachedQueryBackoff)
        #expect(!fresh.hasReachedAccusationBackoff)
        #expect(!fresh.accusationsHeldAtAmbient)
    }

    /// The two cooldowns are different numbers with different owners: e05's for a question,
    /// **e04's unchanged** for an accusation. The ladder adds proportionality above the
    /// engine's cooldown and never loosens it.
    @Test("each kind keeps its own cooldown, and the accusation's is still e04's")
    func perKindCooldowns() {
        #expect(FatigueState.cooldown(for: .query) == InterventionPolicy.queryCooldown)
        #expect(FatigueState.cooldown(for: .accusation) == RelevancePolicy.mandateCooldown)
        #expect(FatigueState.cooldown(for: .query) < FatigueState.cooldown(for: .accusation))

        let spoke = FatigueState(lastQueryAt: .seconds(100), lastAccusationAt: .seconds(100))
        #expect(!spoke.cooledDown(.query, now: .seconds(279)))
        #expect(spoke.cooledDown(.query, now: .seconds(280)))
        #expect(!spoke.cooledDown(.accusation, now: .seconds(699)))
        #expect(spoke.cooledDown(.accusation, now: .seconds(700)))
    }

    /// **Two unanswered questions is the point at which the app is talking to itself.**
    @Test("two declined questions reach the backoff, and the backoff runs for an hour")
    func queryBackoff() {
        let once = FatigueState(consecutiveUnansweredQueries: 1)
        #expect(!once.hasReachedQueryBackoff)

        let twice = FatigueState(
            consecutiveUnansweredQueries: InterventionPolicy.ignoredQueryBackoff,
            queriesSuspendedUntil: .seconds(100) + InterventionPolicy.queryBackoffSpan
        )
        #expect(twice.hasReachedQueryBackoff)
        #expect(twice.isBackedOff(.query, now: .seconds(3600)))
        #expect(!twice.permits(.query, now: .seconds(3600)))
        #expect(!twice.isBackedOff(.query, now: .seconds(3700)))
        #expect(twice.permits(.query, now: .seconds(3700)))

        // …and the accusation is not suspended by the question's backoff.
        #expect(twice.permits(.accusation, now: .seconds(3600)))
    }

    /// The accusation backoff does **not** silence the ladder — it holds it at the ambient
    /// rung, because going fully silent would lose the one channel the person has not objected
    /// to (F-63, F-146).
    @Test("three ignored rungs hold the ladder at ambient rather than silencing it")
    func accusationBackoffHoldsRatherThanSilences() {
        let ignored = FatigueState(
            consecutiveIgnoredAccusations: InterventionPolicy.ignoredAccusationBackoff,
            accusationsHeldAtAmbient: true
        )
        #expect(ignored.hasReachedAccusationBackoff)
        #expect(ignored.accusationsHeldAtAmbient)
        // Not a veto: the glyph still tells the truth.
        #expect(!ignored.isBackedOff(.accusation, now: .seconds(10_000)))
        #expect(ignored.permits(.accusation, now: .seconds(10_000)))
    }
}
