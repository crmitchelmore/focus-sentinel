import Foundation
import Testing

@testable import FocusCore

/// The three limits, the shared budget, and the unit a question may never spend (R-83, F-63,
/// F-107).
@Suite("Interruption budget")
struct InterruptionBudgetTests {
    /// **A day's spend, folded from charges** (focus-d6r).
    ///
    /// There is no `interruptions:` parameter and there cannot be one: `interruptionsToday` is
    /// derived from the two per-kind counters, so a suite can no longer state a day in which the
    /// shared budget is spent and nothing was said. Half this suite used to do exactly that —
    /// see `theReserveHoldsOverEveryReachableDay` below, which was folded over `interruptions:`
    /// alone and therefore proved the reserve over states the app cannot reach while leaving it
    /// unproved over the states it can.
    static func budget(
        queriesForPriority: Int = 0,
        queriesAllPriorities: Int = 0,
        accusations: Int = 0
    ) -> InterruptionBudget {
        BudgetDay.spending(
            queries: queriesForPriority,
            otherPriorityQueries: max(0, queriesAllPriorities - queriesForPriority),
            accusations: accusations
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
    /// Folded over the whole **reachable** grid rather than at one point — and the word
    /// *reachable* is focus-d6r's correction. This fold used to walk `interruptions:` from nought
    /// to the cap with both per-kind counters held at nought, so every cell of it was a day on
    /// which the shared budget had been spent and the app had said nothing: the state
    /// `InterruptionBudget` no longer has a spelling for, and the state focus-d6r's defect
    /// actually produced. The reserve was proved over ten days the app cannot have and left
    /// unproved over every day it can.
    @Test("a query can never spend the reserved unit, on any day the app can have had")
    func theReserveHoldsOverEveryReachableDay() {
        let cap = InterventionPolicy.dailyInterruptionCap
        var cells = 0
        var refusedCells = 0
        for questions in 0...cap {
            for accusations in 0...cap where questions + accusations <= cap {
                let budget = Self.budget(
                    queriesForPriority: questions,
                    queriesAllPriorities: questions,
                    accusations: accusations
                )
                cells += 1
                #expect(
                    budget.interruptionsToday == questions + accusations,
                    "the shared total and the sentences it is made of disagree"
                )
                #expect(
                    budget.sharedRemainingForQueries
                        == max(0, budget.sharedRemaining - InterventionPolicy.reservedAccusationUnits)
                )
                #expect(
                    budget.sharedRemainingForQueries <= budget.sharedRemaining,
                    """
                    a query had more shared headroom than an accusation after \(questions) \
                    question(s) and \(accusations) accusation(s)
                    """
                )
                if budget.sharedRemaining <= InterventionPolicy.reservedAccusationUnits {
                    refusedCells += 1
                    #expect(
                        !budget.permits(.query),
                        """
                        a query was permitted with only the reserve left, after \(questions) \
                        question(s) and \(accusations) accusation(s)
                        """
                    )
                }
            }
        }
        // Non-vacuity, both ways: the fold must have covered cells on each side of the reserve.
        #expect(cells > 0)
        #expect(refusedCells > 0, "no cell in the fold ever reached the reserve")
        #expect(refusedCells < cells, "every cell was at the reserve, so nothing was compared")
    }

    // MARK: - The floor (focus-d6r)

    /// **No day the app can reach refuses an accusation without the app having made one.**
    ///
    /// The other side of `PerceptibleChange`'s road. That type made *"charged for something
    /// nobody saw"* unrepresentable; this asserts the consequence of `interruptionsToday` being
    /// derived rather than stored — that silence is bought only with sentences.
    ///
    /// Driven over the **closed spending algebra** rather than over a scenario: start from
    /// `.empty`, and at every state take every move the caps still permit, to a fixed point. That
    /// is every budget the app can ever be in, exhaustively, and the assertion is made in each
    /// one. A day of glyph landings is absent from the walk for the reason that matters: a glyph
    /// landing makes no `InterruptionCharge`, so it is not a move.
    ///
    /// Before focus-d6r the equivalent state was reachable in the store in eight steps and the
    /// walk would have found it immediately: `interruptionsToday == 8`, `accusationsToday == 0`,
    /// `permits(.accusation) == false`.
    @Test("no reachable day refuses an accusation without the app having made one")
    func theFloorHoldsOverEveryReachableDay() {
        var seen: Set<InterruptionBudget> = [.empty]
        var frontier: [InterruptionBudget] = [.empty]
        var silenced = 0

        while let budget = frontier.popLast() {
            if !budget.permits(.accusation) {
                silenced += 1
                #expect(
                    budget.accusationsToday > 0,
                    """
                    the app cannot accuse anybody and has accused nobody: \
                    \(budget.queriesAllPrioritiesToday) question(s), \
                    \(budget.accusationsToday) accusation(s), \
                    \(budget.interruptionsToday) interruption(s), bound by \
                    \(String(describing: budget.bindingLimit(for: .accusation)))
                    """
                )
                #expect(
                    budget.hasSpokenToday,
                    "the app was silenced for the day without having said anything at all"
                )
            }
            // Every unit of the shared budget is a sentence, in every state, by construction.
            #expect(
                budget.interruptionsToday
                    == budget.queriesAllPrioritiesToday + budget.accusationsToday
            )
            for kind in InterruptionKind.allCases where budget.permits(kind) {
                for underThisPriority in [true, false] {
                    let next = budget.spending(
                        InterruptionCharge(
                            kind,
                            priorityID: underThisPriority
                                ? BudgetDay.priority : BudgetDay.otherPriority
                        ),
                        underPriority: BudgetDay.priority
                    )
                    if seen.insert(next).inserted { frontier.append(next) }
                }
            }
        }

        // Non-vacuity: the walk must have reached days on which the app really is quiet, or the
        // implication above has nothing to imply about.
        #expect(silenced > 0, "no reachable day ever refused an accusation, so this proves nothing")
        #expect(seen.count > 1, "the walk never left the empty day")
        // And the walk really does end where the shared cap says it does.
        #expect(
            seen.map(\.interruptionsToday).max() == InterventionPolicy.dailyInterruptionCap,
            "the reachable days run past the shared cap"
        )
    }

    /// **The load-bearing cell: one unit left, both offered, the accusation takes it.**
    @Test("with one unit of the shared budget left, the accusation wins and the query loses")
    func withOneUnitLeftTheAccusationWins() {
        // Seven of the eight spent, on three questions and four accusations — a day the app
        // can actually have had, rather than seven units taken by nothing. Neither per-kind cap
        // is at its own limit, so the shared budget is unambiguously the one that binds.
        let oneLeft = Self.budget(
            queriesForPriority: 3, queriesAllPriorities: 3, accusations: 4
        )
        #expect(
            oneLeft.interruptionsToday == InterventionPolicy.dailyInterruptionCap
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
            #expect(
                Self.budget(queriesForPriority: asked, queriesAllPriorities: asked)
                    .permits(.query)
            )
        }
        let full = Self.budget(
            queriesForPriority: InterventionPolicy.dailyQueryCap,
            queriesAllPriorities: InterventionPolicy.dailyQueryCap
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
            queriesAllPriorities: InterventionPolicy.dailyQueryCapAllPriorities
        )
        #expect(day.queriesForPriorityToday < InterventionPolicy.dailyQueryCap)
        #expect(!day.permits(.query), "a third priority bought itself extra questions")
        #expect(day.bindingLimit(for: .query) == .dailyQueryCapAllPriorities)
        #expect(day.permits(.accusation))
    }

    @Test("the accusation cap bites at six")
    func accusationCap() {
        let full = Self.budget(accusations: InterventionPolicy.dailyAccusationCap)
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
            accusations: 4
        )
        #expect(contended.interruptionsToday == InterventionPolicy.dailyInterruptionCap)
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
            queriesForPriority: 4, queriesAllPriorities: 5, accusations: 3
        )
        #expect(spent.interruptionsToday == InterventionPolicy.dailyInterruptionCap)
        #expect(spent.startingNewDay() == .empty)
    }

    // MARK: - FatigueState

    @Test("a fresh session has said nothing and permits both kinds")
    func freshFatigue() {
        let fresh = FatigueState.fresh
        #expect(fresh.permits(.query, now: .zero))
        #expect(fresh.permits(.accusation, now: .zero))
        #expect(!fresh.hasReachedQueryBackoff)
        #expect(fresh.accusationsHeldUntil == nil)
        #expect(!fresh.isHeldAtAmbient(now: .zero))
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
            queriesSuspendedUntil: .seconds(100) + InterventionPolicy.backoffSpan
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
    ///
    /// **The hold is read from `isHeldAtAmbient(now:)`, and from nothing else** (focus-yxb).
    /// This used to assert `hasReachedAccusationBackoff` beside it, on a state built by passing
    /// the threshold straight into the initialiser — a state `FatigueController` never writes,
    /// because it zeroes the run at the moment it trips. The predicate was `false` for every
    /// state the producer can build, so the assertion held only because the test supplied its own
    /// input. The reachable version of this claim lives in `NudgeReachabilityTests`.
    @Test("an ignored-accusation hold keeps the glyph rather than silencing it")
    func accusationBackoffHoldsRatherThanSilences() {
        let ignored = FatigueState(accusationsHeldUntil: .seconds(20_000))
        #expect(ignored.isHeldAtAmbient(now: .seconds(10_000)))
        // Not a veto: the glyph still tells the truth.
        #expect(!ignored.isBackedOff(.accusation, now: .seconds(10_000)))
        #expect(ignored.permits(.accusation, now: .seconds(10_000)))

        // …and it is a hold rather than a mute, so it ends (focus-845).
        #expect(!ignored.isHeldAtAmbient(now: .seconds(20_000)))
    }
}
