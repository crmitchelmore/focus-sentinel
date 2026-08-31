import Foundation

/// **One thing the app said, priced** (focus-d6r).
///
/// The unit `InterruptionBudget` moves by, and the reason the budget has no other mover. A charge
/// exists for a **sentence** — a question or an accusation somebody was actually made — and for
/// nothing else, so there is no value in the programme that means *"take a unit of the person's
/// day and say nothing for it"*.
///
/// `init?(_:priorityID:)` below is where that is decided, once, from
/// `InterventionEvent.spendsTheInterruptionCap`. A rung the ladder delivered to the glyph makes no
/// charge at all rather than a smaller one: it accuses nobody, asks nobody anything, and R-87
/// keeps it on through a snooze precisely because it is a **state** and not a sentence.
public struct InterruptionCharge: Sendable, Equatable, Hashable {
    /// Which kind of sentence it was. There is no third case, and that is the whole design: every
    /// charge lands in one of the two per-kind counters as well as in the shared one.
    public let kind: InterruptionKind
    /// The commitment it was made under, for the per-priority query cap. `nil` for a charge made
    /// with no priority active, which the per-priority term then never counts.
    public let priorityID: UUID?

    /// A sentence, priced. Total by construction: there is no way to spell a charge that says
    /// nothing.
    public init(_ kind: InterruptionKind, priorityID: UUID? = nil) {
        self.kind = kind
        self.priorityID = priorityID
    }

    /// **The one derivation from a recorded event, and it answers `nil` for a rung that speaks to
    /// nobody** (focus-ndh, focus-d6r).
    ///
    /// Asked of `spendsTheInterruptionCap` rather than of `spendsBudget`, which is the line that
    /// charged the glyph: a delivered ambient rung is a delivery — it is written down, the
    /// Intervention pane draws it, `deferredRungShare` counts it — and it is not an interruption.
    public init?(_ event: InterventionEvent, priorityID: UUID? = nil) {
        guard event.spendsTheInterruptionCap else { return nil }
        self.init(event.kind, priorityID: priorityID)
    }
}

/// **What the day has already cost the person**, and what is left.
///
/// Every count comes from persisted `InterventionRecord` rows keyed by `localDayKey` (R-79), so
/// the caps survive a relaunch and this type is a pure function of stored rows. Nothing here
/// reads a clock: `FatigueState` owns the cooldowns and the backoffs, and `FatigueController`
/// (T130) conjoins the two.
///
/// ## Three limits, not one
///
/// Queries and accusations are **different in kind and identical in cost** to the person. A
/// person asked ten questions has been interrupted ten times, whatever the app calls them. So
/// each kind keeps its own cap *and* both draw on one shared daily budget (R-83) —
/// `dailyInterruptionCap` is deliberately **less than** `dailyQueryCap + dailyAccusationCap`,
/// because two budgets that cannot both be exhausted are not sharing anything.
///
/// ## The last unit belongs to the accusation
///
/// `reservedAccusationUnits` is the one rule in this file that is not arithmetic. Running out of
/// budget on *questions* and therefore being unable to say "you are off task" is the failure that
/// defeats the product, so a query may never spend the last unit of the shared budget —
/// and `InterruptionBudgetTests` asserts that over the whole grid rather than at one point.
///
/// ## **The floor: a budget spent on nothing cannot be written down** (focus-d6r)
///
/// `PerceptibleChange` made *"charged for something nobody saw"* unrepresentable. This is the
/// same move on the other side of the road, and it closes the same family:
///
/// * **`interruptionsToday` is computed, not stored.** It is `queriesAllPrioritiesToday +
///   accusationsToday` and there is no field it could disagree with them in. The state the bead
///   measured — *eight interruptions, nought accusations, nought questions, `permits` false on
///   both kinds* — is not a bug in an arithmetic any more; it is a value with no spelling.
/// * **The memberwise initialiser is private and `spending(_:)` is the only mover** (R-96r, and
///   `check-forbidden.sh` pins the construction site the way R-96p pins `PerceptibleChange`'s).
///   Every producer in the programme folds `InterruptionCharge`s, and a charge exists only for a
///   sentence. Three separate summations used to answer *"what did that rung cost?"* —
///   `InterventionLog.budget`, this file's `spending(_:)`, and `NudgeWorld.recordAccusation` —
///   and they gave three different answers, which is exactly how focus-ndh's repair reached one
///   of them and not the other two.
///
/// What is deliberately **not** made unrepresentable is a day on which the app has spoken its
/// six accusations and must now be quiet. That is the policy, working. The floor this file holds
/// is the other one: *no reachable budget refuses an accusation without the app having made
/// one*, and with the two clauses above it is a consequence of the arithmetic rather than a
/// thing to remember. `InterruptionBudgetTests.theFloorHoldsOverEveryReachableDay` folds it over
/// the closed spending algebra rather than asserting it at a point.
public struct InterruptionBudget: Sendable, Equatable, Hashable {
    /// Questions already asked **for this priority**, today, in the user's own calendar.
    public let queriesForPriorityToday: Int
    /// Questions already asked today across **every** priority. The number a person feels: a
    /// per-priority cap is not a cap on anybody's day, because three priorities in one day
    /// would otherwise license three times as many questions.
    public let queriesAllPrioritiesToday: Int
    /// Accusation rungs that **accused somebody** today. A deferred rung spends nothing (R-81),
    /// and neither does an ambient one, which accuses nobody (focus-ndh).
    public let accusationsToday: Int

    /// Interruptions of both kinds delivered today — the shared budget's consumption.
    ///
    /// **Computed, and that is the floor** (focus-d6r). It was a stored fourth field summed by a
    /// separate pass over the same rows, and the pass disagreed with the other two: it charged
    /// every delivered row, so a day of glyph landings drove this to `dailyInterruptionCap` with
    /// both per-kind counters still at nought, and `remaining(for:)` — which conjoins the shared
    /// cap into **both** kinds — then refused every question and every accusation for the rest of
    /// the day. Derived from the two counters, that day cannot be represented: the app cannot
    /// have been interrupted by more sentences than it made.
    public var interruptionsToday: Int { queriesAllPrioritiesToday + accusationsToday }

    /// **The only initialiser, and it is private.** See `spending(_:)` and `spent(_:underPriority:)`.
    private init(
        queriesForPriorityToday: Int,
        queriesAllPrioritiesToday: Int,
        accusationsToday: Int
    ) {
        self.queriesForPriorityToday = queriesForPriorityToday
        self.queriesAllPrioritiesToday = queriesAllPrioritiesToday
        self.accusationsToday = accusationsToday
    }

    /// A day on which the app has said nothing yet.
    public static let empty = InterruptionBudget(
        queriesForPriorityToday: 0,
        queriesAllPrioritiesToday: 0,
        accusationsToday: 0
    )

    /// Units of the shared budget still unspent, never below zero.
    public var sharedRemaining: Int {
        max(0, InterventionPolicy.dailyInterruptionCap - interruptionsToday)
    }

    /// Units of the shared budget a **question** may still spend.
    ///
    /// The reserved units are subtracted here and nowhere else, so there is exactly one place
    /// the rule lives and exactly one place it could be got wrong.
    public var sharedRemainingForQueries: Int {
        max(0, sharedRemaining - InterventionPolicy.reservedAccusationUnits)
    }

    /// How many more interruptions of this kind the caps allow today.
    ///
    /// The **minimum** of every cap that applies, because a conjunction of limits is exactly
    /// what a budget is: a question is allowed only while its per-priority cap, its day cap and
    /// the shared budget all still have room.
    public func remaining(for kind: InterruptionKind) -> Int {
        switch kind {
        case .query:
            return min(
                max(0, InterventionPolicy.dailyQueryCap - queriesForPriorityToday),
                max(
                    0,
                    InterventionPolicy.dailyQueryCapAllPriorities - queriesAllPrioritiesToday
                ),
                sharedRemainingForQueries
            )
        case .accusation:
            return min(
                max(0, InterventionPolicy.dailyAccusationCap - accusationsToday),
                sharedRemaining
            )
        }
    }

    /// Whether the caps permit one more interruption of this kind today.
    ///
    /// Caps only. Cooldowns and backoffs are `FatigueState`'s, and the two are conjoined by
    /// `FatigueController` — kept apart because one is a fact about the day and the other is a
    /// fact about the last few minutes, and mixing them would make a relaunch reset a backoff.
    public func permits(_ kind: InterruptionKind) -> Bool {
        remaining(for: kind) > 0
    }

    /// Which cap is the binding one, for a surface that has to say why it stayed quiet.
    public func bindingLimit(for kind: InterruptionKind) -> InterruptionLimit? {
        guard !permits(kind) else { return nil }
        switch kind {
        case .query:
            if queriesForPriorityToday >= InterventionPolicy.dailyQueryCap {
                return .dailyQueryCap
            }
            if queriesAllPrioritiesToday >= InterventionPolicy.dailyQueryCapAllPriorities {
                return .dailyQueryCapAllPriorities
            }
            return sharedRemaining > 0 ? .reservedForAccusation : .dailyInterruptionCap
        case .accusation:
            if accusationsToday >= InterventionPolicy.dailyAccusationCap {
                return .dailyAccusationCap
            }
            return .dailyInterruptionCap
        }
    }

    /// **Whether the app has said anything at all today.**
    ///
    /// The reading the floor is stated in. A day that has not spoken and cannot must not exist,
    /// and since `interruptionsToday` is derived from these two counters it cannot: silence is
    /// bought only with sentences.
    public var hasSpokenToday: Bool { interruptionsToday > 0 }

    /// The budget after one interruption of this kind has been **delivered** to the active
    /// priority.
    ///
    /// Only a delivery spends: a deferred rung nobody could see, a suppressed one the app chose
    /// not to make, and an ambient rung that accuses nobody all leave this value untouched
    /// (R-81, focus-ndh).
    public func spending(_ kind: InterruptionKind) -> InterruptionBudget {
        spending(kind, forActivePriority: true)
    }

    /// The budget after one recorded charge, read against the priority the caps are being summed
    /// for.
    ///
    /// The per-priority term counts only a question asked under **this** commitment: a budget
    /// summed under one key from rows written under another is a cap that silently stops
    /// applying, and `nil` is the honest answer when there is no priority at all.
    public func spending(_ charge: InterruptionCharge, underPriority active: UUID?) -> InterruptionBudget {
        spending(
            charge.kind,
            forActivePriority: active != nil && charge.priorityID == active
        )
    }

    /// **The one mover.** Every producer in the programme reaches the counters through here, so
    /// the shared total and the two per-kind totals cannot be moved apart.
    private func spending(
        _ kind: InterruptionKind,
        forActivePriority: Bool
    ) -> InterruptionBudget {
        switch kind {
        case .query:
            InterruptionBudget(
                queriesForPriorityToday: queriesForPriorityToday + (forActivePriority ? 1 : 0),
                queriesAllPrioritiesToday: queriesAllPrioritiesToday + 1,
                accusationsToday: accusationsToday
            )
        case .accusation:
            InterruptionBudget(
                queriesForPriorityToday: queriesForPriorityToday,
                queriesAllPrioritiesToday: queriesAllPrioritiesToday,
                accusationsToday: accusationsToday + 1
            )
        }
    }

    /// A whole day's charges, folded — what `InterventionLog.budget(on:priorityID:)` and the
    /// replay's `NudgeWorld` both build with, so the lane that lives a day and the lane that
    /// measures one cannot price a rung differently.
    public static func spent(
        _ charges: some Sequence<InterruptionCharge>,
        underPriority active: UUID?
    ) -> InterruptionBudget {
        charges.reduce(.empty) { $0.spending($1, underPriority: active) }
    }

    /// A new local day, with the per-priority count carried by whichever priority is active.
    ///
    /// Every count is derived from stored rows in practice; this exists so a replay can start a
    /// day without inventing a store.
    public func startingNewDay() -> InterruptionBudget { .empty }
}

/// Which cap is the one that bit.
///
/// Named rather than reported as a number, because "you have had four questions about this
/// task today" and "you have had five questions today" are different sentences and a person
/// deserves the true one.
public enum InterruptionLimit: String, Sendable, CaseIterable, Codable, Hashable {
    case dailyQueryCap
    case dailyQueryCapAllPriorities
    case dailyAccusationCap
    case dailyInterruptionCap
    /// The shared budget still has room, but the room left is the accusation's reserve.
    case reservedForAccusation
}

/// **How tired of being spoken to the person is**, on the monotonic clock.
///
/// A value, read by a pure reducer. The distinction from `InterruptionBudget` is deliberate and
/// load-bearing: a budget is a fact about the **day** and is rebuilt from persisted rows, while
/// fatigue is a fact about the **last few minutes and the current session** and is not
/// persisted. A backoff that survived a relaunch would be a backoff that outlived the situation
/// it was for; a cap that did not survive one would be a cap somebody could clear by quitting.
public struct FatigueState: Sendable, Equatable, Hashable {
    /// The monotonic reading at which the last question was delivered.
    public let lastQueryAt: Duration?
    /// The monotonic reading at which the last accusation rung was delivered.
    public let lastAccusationAt: Duration?
    /// Questions declined or dismissed without an answer, in a row. At
    /// `InterventionPolicy.ignoredQueryBackoff` the app stops asking: two unanswered questions
    /// is the point at which it is talking to itself.
    public let consecutiveUnansweredQueries: Int
    /// Delivered accusation rungs with no correction, snooze, pause or return, in a row. At
    /// `InterventionPolicy.ignoredAccusationBackoff` the ladder drops to `.ambient` and holds.
    ///
    /// **This is the run that can reach the backoff**, and the reason is its scope: it is a fact
    /// about the *session*, so a person who dismisses a nudge about one thing and then dismisses
    /// a nudge about another has ignored two. `LadderMachine`'s own count is scoped to a single
    /// drift subject and resets when the subject changes, so it cannot pass one from anything the
    /// host can do (focus-yxb).
    ///
    /// It is **zeroed by the trip**, not left standing at the threshold — see
    /// `FatigueController.resolvingAccusation(_:unanswered:now:)` — so `isHeldAtAmbient(now:)`
    /// below is the only honest way to ask whether the hold is on.
    public let consecutiveIgnoredAccusations: Int
    /// When the query backoff lifts, on the monotonic clock. `nil` when no backoff is running.
    public let queriesSuspendedUntil: Duration?
    /// **When the ladder stops being held at the ambient rung**, on the monotonic clock. `nil`
    /// when no hold is running.
    ///
    /// **It was a `Bool` and had no expiry at all** (focus-845). Nothing but `.sessionEnded`
    /// could clear it, so two dismissals held the ladder at the ambient rung for the rest of the
    /// session — and since U-2 the panel is the only rung that carries a sentence, so that was
    /// the speaking product muted by two clicks with no way back. Its twin
    /// `queriesSuspendedUntil` above trips at the same count and has always been bounded to
    /// `InterventionPolicy.backoffSpan`; this now reads the same constant, so the asymmetry is
    /// gone rather than merely documented.
    ///
    /// **Not full silence while it runs.** The glyph still tells the truth, because that is the
    /// one channel the person has not objected to and F-146's whole point is that the state is
    /// always legible.
    public let accusationsHeldUntil: Duration?

    public init(
        lastQueryAt: Duration? = nil,
        lastAccusationAt: Duration? = nil,
        consecutiveUnansweredQueries: Int = 0,
        consecutiveIgnoredAccusations: Int = 0,
        queriesSuspendedUntil: Duration? = nil,
        accusationsHeldUntil: Duration? = nil
    ) {
        self.lastQueryAt = lastQueryAt
        self.lastAccusationAt = lastAccusationAt
        self.consecutiveUnansweredQueries = consecutiveUnansweredQueries
        self.consecutiveIgnoredAccusations = consecutiveIgnoredAccusations
        self.queriesSuspendedUntil = queriesSuspendedUntil
        self.accusationsHeldUntil = accusationsHeldUntil
    }

    /// A session in which nothing has been said yet.
    public static let fresh = FatigueState()

    /// The minimum gap this kind of interruption keeps.
    ///
    /// A question's is e05's `queryCooldown`, asserted equal to `RelevancePolicy.lookBackSpan`;
    /// an accusation's is **e04's own `mandateCooldown`, unchanged**. The ladder adds
    /// proportionality above the engine's cooldown and never loosens it.
    public static func cooldown(for kind: InterruptionKind) -> Duration {
        switch kind {
        case .query: InterventionPolicy.queryCooldown
        case .accusation: RelevancePolicy.mandateCooldown
        }
    }

    /// Whether enough time has passed since the last interruption of this kind.
    public func cooledDown(_ kind: InterruptionKind, now: Duration) -> Bool {
        let last: Duration?
        switch kind {
        case .query: last = lastQueryAt
        case .accusation: last = lastAccusationAt
        }
        guard let last else { return true }
        return now - last >= Self.cooldown(for: kind)
    }

    /// Whether this kind is currently suspended because the person stopped answering.
    public func isBackedOff(_ kind: InterruptionKind, now: Duration) -> Bool {
        switch kind {
        case .query:
            guard let until = queriesSuspendedUntil else { return false }
            return now < until
        case .accusation:
            // The accusation backoff does not silence the ladder; it holds it at the ambient
            // rung. That is the ladder's business (`LadderState.heldAtAmbient`), not a veto
            // here, so this answers `false` and `isHeldAtAmbient(now:)` is read instead.
            return false
        }
    }

    /// **Whether the ladder is held at the ambient rung right now** (focus-845).
    ///
    /// The twin of `isBackedOff(.query, now:)`, and it is a *function of the clock* for the
    /// reason that one is: a hold with no expiry is not a backoff, it is a mute. Reading the
    /// stored instant directly would put the comparison at the call site, which is where the
    /// missing expiry could hide again.
    public func isHeldAtAmbient(now: Duration) -> Bool {
        guard let until = accusationsHeldUntil else { return false }
        return now < until
    }

    /// Whether fatigue permits this kind now — cooldown and backoff together.
    public func permits(_ kind: InterruptionKind, now: Duration) -> Bool {
        cooledDown(kind, now: now) && !isBackedOff(kind, now: now)
    }

    /// Whether the unanswered-question count has reached the backoff threshold.
    public var hasReachedQueryBackoff: Bool {
        consecutiveUnansweredQueries >= InterventionPolicy.ignoredQueryBackoff
    }

    // **`hasReachedAccusationBackoff` is gone, and it was never once true** (focus-yxb).
    //
    // It read `consecutiveIgnoredAccusations >= ignoredAccusationBackoff`, and
    // `FatigueController.resolvingAccusation(…)` writes `trips ? 0 : run` — so the moment the run
    // reaches the threshold the counter is *zeroed* and the hold is recorded in
    // `accusationsHeldUntil` instead. The stored count therefore never exceeds
    // `backoff - 1`, and the predicate answered `false` for **every** state the controller can
    // produce. Nothing in the app read it; two tests did, and both hand-built a state by passing
    // the threshold straight into the initialiser — a value the producer never writes, so the
    // tests agreed with themselves.
    //
    // `hasReachedQueryBackoff` above is kept because it is not the same shape: the query run is
    // not zeroed on the trip, `queriesSuspendedUntil` is set beside it, and the count really can
    // stand at the threshold.
}
