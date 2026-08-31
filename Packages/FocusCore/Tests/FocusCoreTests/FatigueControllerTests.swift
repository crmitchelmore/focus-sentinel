import Foundation
import Testing

@testable import FocusCore

/// **A person asked ten questions has been interrupted ten times** (R-83, F-63).
///
/// The suite the whole fatigue ruling rests on: both cooldowns, all four caps, the shared budget
/// binding before either per-kind cap, the reserved unit that a question may never spend, both
/// backoffs, and the one refusal that outranks every other — a correction, which removes the
/// subject from the accusable set entirely rather than deferring it.
@Suite("Fatigue controller")
struct FatigueControllerTests {
    static let decoy = "com.chrismitchelmore.FocusDecoy"
    static let other = "com.apple.Safari"

    /// A day on which nothing has been said and a session in which nothing has been ignored.
    static func decide(
        kind: InterruptionKind,
        subject: String? = FatigueControllerTests.decoy,
        rung: LadderRung.Kind? = nil,
        budget: InterruptionBudget = .empty,
        fatigue: FatigueState = .fresh,
        snoozes: SnoozeBook = .none,
        corrected: Set<String> = [],
        now: Duration = .seconds(10_000)
    ) -> FatigueDecision {
        FatigueController.decide(
            kind: kind,
            subject: subject,
            rung: rung,
            budget: budget,
            fatigue: fatigue,
            snoozes: snoozes,
            correctedSubjects: corrected,
            now: now
        )
    }

    // MARK: - The baseline

    @Test("an empty day permits both kinds")
    func anEmptyDayPermitsBoth() {
        #expect(Self.decide(kind: .query) == .permitted)
        #expect(Self.decide(kind: .accusation, rung: .ambient) == .permitted)
    }

    @Test("permits(…) and decide(…) never disagree")
    func theBoolAgreesWithTheReason() {
        for kind in InterruptionKind.allCases {
            for queries in 0...6 {
                for accusations in 0...7 {
                    let budget = BudgetDay.spending(
                        queries: queries, accusations: accusations
                    )
                    let decision = Self.decide(kind: kind, rung: .panel, budget: budget)
                    let permits = FatigueController.permits(
                        kind: kind,
                        subject: Self.decoy,
                        rung: .panel,
                        budget: budget,
                        fatigue: .fresh,
                        now: .seconds(10_000)
                    )
                    #expect(decision.isPermitted == permits)
                }
            }
        }
    }

    // MARK: - The two cooldowns

    @Test("a question keeps queryCooldown, which is the look-back span")
    func theQueryCooldown() {
        #expect(InterventionPolicy.queryCooldown == RelevancePolicy.lookBackSpan)

        let fatigue = FatigueState(lastQueryAt: .seconds(0))
        let span = InterventionPolicy.queryCooldown

        #expect(Self.decide(kind: .query, fatigue: fatigue, now: span - .seconds(1))
            == .refused(.cooldown(remaining: .seconds(1))))
        #expect(Self.decide(kind: .query, fatigue: fatigue, now: span) == .permitted)
    }

    @Test("an accusation keeps e04's own mandateCooldown, unchanged")
    func theAccusationCooldown() {
        let fatigue = FatigueState(lastAccusationAt: .seconds(0))
        let span = RelevancePolicy.mandateCooldown

        #expect(FatigueState.cooldown(for: .accusation) == RelevancePolicy.mandateCooldown)
        #expect(Self.decide(kind: .accusation, rung: .panel, fatigue: fatigue, now: span - .seconds(1))
            == .refused(.cooldown(remaining: .seconds(1))))
        #expect(Self.decide(kind: .accusation, rung: .panel, fatigue: fatigue, now: span) == .permitted)
    }

    @Test("the two cooldowns are independent: a question does not delay an accusation")
    func theCooldownsAreIndependent() {
        let fatigue = FatigueState(lastQueryAt: .seconds(10_000))
        #expect(Self.decide(kind: .query, fatigue: fatigue, now: .seconds(10_010)).refusal != nil)
        #expect(Self.decide(kind: .accusation, rung: .panel, fatigue: fatigue, now: .seconds(10_010))
            == .permitted)
    }

    // MARK: - The four caps

    @Test("the per-priority query cap bites first when it is the binding one")
    func thePerPriorityQueryCap() {
        let budget = BudgetDay.spending(queries: InterventionPolicy.dailyQueryCap)
        #expect(Self.decide(kind: .query, budget: budget) == .refused(.cap(.dailyQueryCap)))
        #expect(Self.decide(kind: .accusation, rung: .panel, budget: budget) == .permitted)
    }

    @Test("the all-priorities day cap bites even when this priority has asked almost nothing")
    func theDayCapIsADayCap() {
        // One question for this priority, five across the day: a per-priority cap alone would
        // license three more. The number a person feels is questions-per-day.
        let budget = BudgetDay.spending(
            queries: 1,
            otherPriorityQueries: InterventionPolicy.dailyQueryCapAllPriorities - 1
        )
        #expect(budget.remaining(for: .query) == 0)
        #expect(Self.decide(kind: .query, budget: budget)
            == .refused(.cap(.dailyQueryCapAllPriorities)))
    }

    @Test("the accusation cap bites at six")
    func theAccusationCap() {
        let budget = BudgetDay.spending(accusations: InterventionPolicy.dailyAccusationCap)
        #expect(Self.decide(kind: .accusation, rung: .panel, budget: budget)
            == .refused(.cap(.dailyAccusationCap)))
    }

    @Test("the shared budget binds before either per-kind cap does")
    func theSharedBudgetBindsFirst() {
        // Four questions and four accusations: neither per-kind cap has been reached, and the
        // shared budget is spent. Two budgets that cannot both be exhausted are not sharing
        // anything, which is why dailyInterruptionCap is deliberately less than 4 + 6.
        let budget = BudgetDay.spending(
            queries: 2, otherPriorityQueries: 2, accusations: 4
        )
        #expect(budget.interruptionsToday == InterventionPolicy.dailyInterruptionCap)
        #expect(budget.queriesForPriorityToday < InterventionPolicy.dailyQueryCap)
        #expect(budget.accusationsToday < InterventionPolicy.dailyAccusationCap)

        #expect(Self.decide(kind: .query, budget: budget)
            == .refused(.cap(.dailyInterruptionCap)))
        #expect(Self.decide(kind: .accusation, rung: .panel, budget: budget)
            == .refused(.cap(.dailyInterruptionCap)))
    }

    // MARK: - The reserved unit

    @Test("with one unit left and both offered, the accusation takes it")
    func theLastUnitBelongsToTheAccusation() {
        let budget = BudgetDay.spending(queries: 2, accusations: 5)
        #expect(budget.sharedRemaining == InterventionPolicy.reservedAccusationUnits)

        #expect(Self.decide(kind: .accusation, rung: .panel, budget: budget) == .permitted)
        #expect(Self.decide(kind: .query, budget: budget)
            == .refused(.cap(.reservedForAccusation)))
    }

    @Test("a question can never spend the last unit, at any mix of the day's spend")
    func theReservedUnitIsNeverSpendableByAQuestion() {
        for queries in 0...InterventionPolicy.dailyInterruptionCap {
            for accusations in 0...InterventionPolicy.dailyInterruptionCap {
                let spent = queries + accusations
                guard spent <= InterventionPolicy.dailyInterruptionCap else { continue }
                let budget = BudgetDay.spending(
                    otherPriorityQueries: queries, accusations: accusations
                )
                let left = InterventionPolicy.dailyInterruptionCap - spent
                if left <= InterventionPolicy.reservedAccusationUnits {
                    #expect(
                        Self.decide(kind: .query, budget: budget).isPermitted == false,
                        "a question was permitted with \(left) unit(s) left"
                    )
                }
            }
        }
    }

    // MARK: - The two backoffs

    @Test("two unanswered questions suspend questions for an hour")
    func theQueryBackoff() {
        var controller = FatigueController()

        for _ in 0..<(InterventionPolicy.ignoredQueryBackoff - 1) {
            controller.reduce(.queryResolved(.declined), now: .seconds(0))
            #expect(controller.state.queriesSuspendedUntil == nil)
        }

        controller.reduce(.queryResolved(.declined), now: .seconds(100))
        let until = Duration.seconds(100) + InterventionPolicy.backoffSpan
        #expect(controller.state.queriesSuspendedUntil == until)

        #expect(Self.decide(kind: .query, fatigue: controller.state, now: until - .seconds(1))
            == .refused(.backedOff(until: until)))
        #expect(Self.decide(kind: .query, fatigue: controller.state, now: until) == .permitted)

        // An accusation is untouched: the two kinds keep separate backoffs as well as separate
        // caps.
        #expect(Self.decide(
            kind: .accusation, rung: .panel, fatigue: controller.state, now: .seconds(200)
        ) == .permitted)
    }

    @Test("an answer ends the run and lifts the suspension outright")
    func anAnswerEndsTheRun() {
        var controller = FatigueController()
        controller.reduce(.queryResolved(.declined), now: .seconds(0))
        controller.reduce(.queryResolved(.declined), now: .seconds(0))
        #expect(controller.state.queriesSuspendedUntil != nil)

        controller.reduce(.queryResolved(.answeredRelevant), now: .seconds(10))

        #expect(controller.state.queriesSuspendedUntil == nil)
        #expect(controller.state.consecutiveUnansweredQueries == 0)
        #expect(Self.decide(kind: .query, fatigue: controller.state, now: .seconds(20)) == .permitted)
    }

    @Test("arming the backoff closes the run, so the next hour must be earned by another two")
    func armingTheBackoffClosesTheRun() {
        var controller = FatigueController()
        for _ in 0..<InterventionPolicy.ignoredQueryBackoff {
            controller.reduce(.queryResolved(.declined), now: .seconds(0))
        }
        #expect(controller.state.consecutiveUnansweredQueries == 0)

        let lifted = InterventionPolicy.backoffSpan
        controller.reduce(.queryResolved(.declined), now: lifted)
        #expect(controller.state.consecutiveUnansweredQueries == 1)
        #expect(controller.state.queriesSuspendedUntil == lifted)   // the old one, expired
        #expect(Self.decide(kind: .query, fatigue: controller.state, now: lifted) == .permitted)
    }

    @Test("an expired question counts as unanswered, an answered one does not")
    func whatCountsAsUnanswered() {
        for outcome in AskedQuestionOutcome.allCases {
            var controller = FatigueController()
            controller.reduce(.queryResolved(outcome), now: .seconds(0))
            #expect(
                (controller.state.consecutiveUnansweredQueries == 1) == !outcome.isAnswer,
                "\(outcome)"
            )
        }
    }

    @Test("two ignored rungs hold the ladder at ambient, and the glyph still gets through")
    func theAccusationBackoff() {
        var controller = FatigueController()

        for _ in 0..<(InterventionPolicy.ignoredAccusationBackoff - 1) {
            controller.reduce(.accusationResolved(.ignored), now: .seconds(0))
            #expect(controller.state.accusationsHeldUntil == nil)
        }
        controller.reduce(.accusationResolved(.ignored), now: .seconds(0))
        let until = Duration.seconds(0) + InterventionPolicy.backoffSpan
        #expect(controller.state.accusationsHeldUntil == until)

        let inside = until - .seconds(1)

        // Held is not silent. F-146's whole point is that the state is always legible, and the
        // ambient rung is the one channel the person has not objected to.
        #expect(Self.decide(
            kind: .accusation, rung: .ambient, fatigue: controller.state, now: inside
        ) == .permitted)
        #expect(Self.decide(
            kind: .accusation, rung: .panel, fatigue: controller.state, now: inside
        ) == .refused(.heldAtAmbient(until: until)))

        // And a question is not held by an accusation's backoff.
        #expect(Self.decide(kind: .query, fatigue: controller.state, now: inside) == .permitted)
    }

    /// **The half nobody wrote, and the reason the hold was a mute** (focus-845).
    ///
    /// `theAccusationBackoff` above proved the constant *fires* and stopped there — and the
    /// consequence of firing was the defect: `accusationsHeldAtAmbient` was a `Bool` that only
    /// `.sessionEnded` could clear, so two dismissals silenced the panel — since U-2 the only
    /// rung that says anything — for the rest of the session. A trip with no expiry is not a
    /// backoff. This drives the clock across the boundary, which is the assertion the previous
    /// round could not have passed at any value of the span.
    @Test("the accusation hold expires on the same span the question backoff uses")
    func theAccusationHoldExpires() {
        var controller = FatigueController()
        for _ in 0..<InterventionPolicy.ignoredAccusationBackoff {
            controller.reduce(.accusationResolved(.ignored), now: .seconds(100))
        }

        let until = Duration.seconds(100) + InterventionPolicy.backoffSpan
        #expect(controller.state.accusationsHeldUntil == until)
        #expect(controller.state.isHeldAtAmbient(now: until - .seconds(1)))

        // One second before: the panel rung is still refused, and the refusal now says when it
        // lifts, exactly as its twin `.backedOff(until:)` always has.
        #expect(Self.decide(
            kind: .accusation, rung: .panel, fatigue: controller.state, now: until - .seconds(1)
        ) == .refused(.heldAtAmbient(until: until)))

        // At the instant it lifts, and thereafter: the app may speak again.
        #expect(!controller.state.isHeldAtAmbient(now: until))
        #expect(Self.decide(
            kind: .accusation, rung: .panel, fatigue: controller.state, now: until
        ) == .permitted)
        #expect(Self.decide(
            kind: .accusation, rung: .panel, fatigue: controller.state,
            now: until + .seconds(10_000)
        ) == .permitted)

        // The two backoffs are one policy, not two postures: both trip at a run of two and both
        // last the same hour.
        #expect(InterventionPolicy.ignoredAccusationBackoff
            == InterventionPolicy.ignoredQueryBackoff)
    }

    /// A hold that trips again inside its own hour is extended from **now**, not left to expire
    /// on the older instant — two more dismissals inside the hour are two more refusals to
    /// engage. The query side has always read its own `trips ? now + span` branch this way.
    @Test("a second trip inside the hour extends the hold from the new instant")
    func aSecondTripExtendsTheHold() {
        var controller = FatigueController()
        for _ in 0..<InterventionPolicy.ignoredAccusationBackoff {
            controller.reduce(.accusationResolved(.ignored), now: .seconds(0))
        }
        #expect(controller.state.accusationsHeldUntil == InterventionPolicy.backoffSpan)

        // The trip zeroed the run, so the next hold has to be earned by another two.
        #expect(controller.state.consecutiveIgnoredAccusations == 0)
        controller.reduce(.accusationResolved(.ignored), now: .seconds(600))
        #expect(controller.state.accusationsHeldUntil == InterventionPolicy.backoffSpan)
        controller.reduce(.accusationResolved(.ignored), now: .seconds(900))
        #expect(
            controller.state.accusationsHeldUntil
                == .seconds(900) + InterventionPolicy.backoffSpan
        )
    }

    /// Asserted on the run **or** the hold, because with `ignoredAccusationBackoff == 2` (U-2)
    /// a second ignore does not merely lengthen the run — it completes it, which zeroes the
    /// counter and arms `accusationsHeldUntil`. Reading only the counter would call that
    /// "the person ended the run", which is the opposite of what happened.
    @Test("anything the person actually did ends the accusation run")
    func whatEndsTheAccusationRun() {
        for outcome in InterventionOutcome.allCases {
            var controller = FatigueController()
            controller.reduce(.accusationResolved(.ignored), now: .seconds(0))
            controller.reduce(.accusationResolved(outcome), now: .seconds(0))

            let stillIgnoring = controller.state.consecutiveIgnoredAccusations > 0
                || controller.state.isHeldAtAmbient(now: .seconds(0))
            #expect(stillIgnoring == outcome.isUnanswered, "\(outcome)")
        }
    }

    @Test("the session ends and both runs die with it, caps excepted")
    func theSessionEndsTheBackoffs() {
        var controller = FatigueController()
        controller.reduce(.queryResolved(.declined), now: .seconds(0))
        controller.reduce(.queryResolved(.declined), now: .seconds(0))
        for _ in 0..<InterventionPolicy.ignoredAccusationBackoff {
            controller.reduce(.accusationResolved(.ignored), now: .seconds(0))
        }
        #expect(controller.state != .fresh)

        controller.reduce(.sessionEnded, now: .seconds(500))
        #expect(controller.state == .fresh)

        // The day's caps are rows in a store. A person cannot clear them by ending a session.
        let spent = BudgetDay.spending(queries: InterventionPolicy.dailyQueryCap)
        #expect(Self.decide(kind: .query, budget: spent, fatigue: controller.state)
            == .refused(.cap(.dailyQueryCap)))
    }

    // MARK: - Deliveries, and only deliveries, start a cooldown

    @Test("only a delivery starts a cooldown")
    func onlyADeliveryStartsACooldown() {
        var controller = FatigueController()
        #expect(controller.state.lastQueryAt == nil)

        // A question always speaks, so its charge is **stated**. An accusation's is **derived**
        // from the rung it landed on and nothing else will do (R-96u, focus-uru): stating one
        // here would be the seam this suite is about being crossed inside its own proof.
        controller.reduce(.delivered(InterruptionCharge(.query)), now: .seconds(300))
        #expect(controller.state.lastQueryAt == .seconds(300))
        #expect(controller.state.lastAccusationAt == nil)

        let spoken = InterventionEvent(
            kind: .accusation,
            rung: .panel,
            subject: Self.decoy,
            surface: .panel,
            disposition: .delivered
        )
        let charge = InterruptionCharge(spoken)
        #expect(charge != nil, "a panel rung that reached somebody derived no charge")
        if let charge { controller.reduce(.delivered(charge), now: .seconds(400)) }
        #expect(controller.state.lastAccusationAt == .seconds(400))
        #expect(controller.state.lastQueryAt == .seconds(300))
    }

    // MARK: - The correction, which suppresses harder than an ignore

    @Test("a correction removes the subject from the accusable set entirely")
    func aCorrectionSuppressesHardest() {
        let corrected: Set<String> = [Self.decoy]

        #expect(Self.decide(kind: .accusation, rung: .ambient, corrected: corrected)
            == .refused(.corrected(subject: Self.decoy)))
        #expect(Self.decide(kind: .accusation, rung: .panel, corrected: corrected)
            == .refused(.corrected(subject: Self.decoy)))
        #expect(Self.decide(kind: .query, corrected: corrected)
            == .refused(.corrected(subject: Self.decoy)))

        // Another subject is untouched: a correction is about a thing, not about the guardian.
        #expect(Self.decide(kind: .accusation, subject: Self.other, rung: .panel, corrected: corrected)
            == .permitted)
    }

    @Test("a correction outranks every other refusal, including the ambient rung's exemption")
    func aCorrectionOutranksEverything() {
        var controller = FatigueController()
        for _ in 0..<InterventionPolicy.ignoredAccusationBackoff {
            controller.reduce(.accusationResolved(.ignored), now: .seconds(0))
        }
        // Held at ambient WOULD let the glyph through; a correction does not.
        #expect(Self.decide(
            kind: .accusation,
            rung: .ambient,
            fatigue: controller.state,
            corrected: [Self.decoy]
        ) == .refused(.corrected(subject: Self.decoy)))
    }

    @Test("a mixed accusation names nobody, so it can be neither corrected nor snoozed")
    func aMixedAccusationHasNoSubjectToSuppress() {
        let snoozes = SnoozeBook([
            SnoozeState.starting(subject: Self.decoy, for: .seconds(600), now: .seconds(0))
        ])
        #expect(Self.decide(
            kind: .accusation, subject: nil, rung: .panel,
            snoozes: snoozes, corrected: [Self.decoy], now: .seconds(10)
        ) == .permitted)
    }

    // MARK: - The snooze

    @Test("a snooze stops the panel and never stops the glyph")
    func aSnoozeSparesTheAmbientRung() {
        let snoozes = SnoozeBook([
            SnoozeState.starting(subject: Self.decoy, for: .seconds(600), now: .seconds(0))
        ])

        #expect(Self.decide(kind: .accusation, rung: .panel, snoozes: snoozes, now: .seconds(10))
            == .refused(.snoozed(subject: Self.decoy, remaining: .seconds(590))))
        #expect(Self.decide(kind: .accusation, rung: .ambient, snoozes: snoozes, now: .seconds(10))
            == .permitted)

        // A question about a snoozed subject is a sentence about the snoozed subject.
        #expect(Self.decide(kind: .query, snoozes: snoozes, now: .seconds(10)).refusal != nil)

        // And it lifts.
        #expect(Self.decide(kind: .accusation, rung: .panel, snoozes: snoozes, now: .seconds(600))
            == .permitted)
    }

    @Test("a snooze is about its subject and nothing else")
    func aSnoozeIsSubjectScoped() {
        let snoozes = SnoozeBook([
            SnoozeState.starting(subject: Self.decoy, for: .seconds(600), now: .seconds(0))
        ])
        #expect(Self.decide(
            kind: .accusation, subject: Self.other, rung: .panel, snoozes: snoozes, now: .seconds(10)
        ) == .permitted)
    }

    // MARK: - The order the refusals are reported in

    @Test("the reported refusal is the first that applied, in the person's own order")
    func theFirstRefusalIsReported() {
        let snoozes = SnoozeBook([
            SnoozeState.starting(subject: Self.decoy, for: .seconds(600), now: .seconds(0))
        ])
        let exhausted = BudgetDay.spending(
            queries: InterventionPolicy.dailyQueryCap,
            otherPriorityQueries: InterventionPolicy.dailyQueryCapAllPriorities
                - InterventionPolicy.dailyQueryCap,
            accusations: InterventionPolicy.dailyAccusationCap
        )
        let tired = FatigueState(
            lastQueryAt: .seconds(10),
            lastAccusationAt: .seconds(10),
            consecutiveUnansweredQueries: 0,
            consecutiveIgnoredAccusations: 0,
            queriesSuspendedUntil: .seconds(100_000),
            accusationsHeldUntil: .seconds(100_000)
        )

        // Everything is closed at once. The person's own instructions are reported first.
        #expect(Self.decide(
            kind: .query, budget: exhausted, fatigue: tired,
            snoozes: snoozes, corrected: [Self.decoy], now: .seconds(20)
        ) == .refused(.corrected(subject: Self.decoy)))

        #expect(Self.decide(
            kind: .query, budget: exhausted, fatigue: tired, snoozes: snoozes, now: .seconds(20)
        ) == .refused(.snoozed(subject: Self.decoy, remaining: .seconds(580))))

        #expect(Self.decide(
            kind: .query, budget: exhausted, fatigue: tired, now: .seconds(20)
        ) == .refused(.backedOff(until: .seconds(100_000))))
    }

    @Test("every refusal reports gate 10, and a permission reports no gate at all")
    func everyRefusalIsGateTen() {
        #expect(FatigueDecision.permitted.suppressionReason == nil)
        #expect(FatigueDecision.refused(.heldAtAmbient(until: nil)).suppressionReason
            == .budgetExhausted)
        #expect(FatigueDecision.refused(.cap(.dailyQueryCap)).suppressionReason == .budgetExhausted)
        #expect(NudgeSuppressionReason.budgetExhausted.gateNumber == 10)
    }
}
