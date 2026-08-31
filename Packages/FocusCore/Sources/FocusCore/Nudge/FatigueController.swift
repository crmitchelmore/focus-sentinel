import Foundation

/// **Why gate 10 said not now**, in the words a person would use.
///
/// R-84's stack reports one reason per silence — `NudgeSuppressionReason.budgetExhausted` for
/// every one of these — because "the tenth gate closed" is the sentence a surface draws. This
/// type is the *detail* underneath it: the log keeps it, the settings pane's caps-as-usage row
/// reads it, and a person who asks "why did it not say anything?" gets the true answer rather
/// than the category. Four cases are arithmetic; two are the person's own instructions, and
/// those come first.
public enum FatigueRefusal: Sendable, Equatable, Hashable {
    /// **The person already told us this is real work.** "This is relevant" writes a durable
    /// task-authority rule (R-78), which removes the subject from the accusable set entirely —
    /// so this refusal is a backstop for the moment between the click and the next
    /// classification, and it is checked first because a correction **suppresses harder than an
    /// ignore** (R-83). The rule is the mechanism; this is the guarantee that nothing gets
    /// through the gap.
    case corrected(subject: String)
    /// The person snoozed this subject. Subject-scoped, in memory, with a visible countdown —
    /// and never applied to the ambient rung, because the glyph goes on telling the truth
    /// (R-87, F-146).
    case snoozed(subject: String, remaining: Duration)
    /// The person stopped answering, so the app stopped asking.
    ///
    /// Two unanswered questions suspend questions for `InterventionPolicy.backoffSpan`. Two
    /// unanswered questions is the point at which the app is talking to itself.
    case backedOff(until: Duration?)
    /// The ladder is held at the ambient rung, so nothing above it may be delivered. Not
    /// silence: the glyph is still on screen and still true.
    ///
    /// **It carries `until`, because it now has one** (focus-845). This was a case with no
    /// payload beside a twin that had always carried one, and the missing payload was the
    /// missing expiry: two ignored rungs held the ladder for the rest of the session. A person
    /// who asks "why did it go quiet?" can now be told when it stops, which is the same answer
    /// `backedOff` has always been able to give.
    case heldAtAmbient(until: Duration?)
    /// Too soon after the last one of this kind. `queryCooldown` for a question — asserted equal
    /// to `RelevancePolicy.lookBackSpan`, so a question and a look-back agree on what "just now"
    /// means — and e04's own `mandateCooldown` for an accusation, unchanged.
    case cooldown(remaining: Duration)
    /// A daily cap, named so a surface can say *which*. "You have had four questions about this
    /// task today" and "you have had five questions today" are different sentences and a person
    /// deserves the true one.
    case cap(InterruptionLimit)
}

/// Whether the person may be interrupted once more, and if not, why not.
public enum FatigueDecision: Sendable, Equatable, Hashable {
    case permitted
    case refused(FatigueRefusal)

    public var isPermitted: Bool { self == .permitted }

    public var refusal: FatigueRefusal? {
        switch self {
        case .permitted: nil
        case .refused(let refusal): refusal
        }
    }

    /// The reason R-84's stack reports for this answer. Gate 10 owns every refusal here.
    public var suppressionReason: NudgeSuppressionReason? {
        isPermitted ? nil : .budgetExhausted
    }
}

/// What moves the fatigue state.
///
/// Deliberately **not** the same vocabulary as `LadderEvent`. A ladder cares about rungs and an
/// interruption budget cares about kinds, and one event type covering both would be a type that
/// had to be filtered at every call site.
public enum FatigueEvent: Sendable, Equatable, Hashable {
    /// An interruption of this kind reached somebody. **Only a delivery starts a cooldown** —
    /// a deferred rung nobody could see and a suppressed one the app chose not to make both
    /// leave this state untouched (R-81).
    case delivered(InterruptionKind)
    /// A question is over. `AskedQuestionOutcome.isAnswer` is what decides whether the run of
    /// unanswered questions continues or ends.
    case queryResolved(AskedQuestionOutcome)
    /// A delivered accusation rung is over.
    case accusationResolved(InterventionOutcome)
    /// The session ended. Both runs die with it, and so does the ladder's hold — which is
    /// exactly what "for the rest of the session" means.
    case sessionEnded
}

/// **The fatigue controller: separate caps, one shared budget, one reserved unit** (R-83, F-63).
///
/// A pure function over four values and a clock reading — the day's spend
/// (`InterruptionBudget`, rebuilt from persisted `InterventionRecord` rows so the caps survive a
/// relaunch), the session's fatigue (`FatigueState`, deliberately *not* persisted, because a
/// backoff that survived a relaunch would be a backoff that outlived the situation it was for),
/// the snooze book, and the subjects the person has already corrected.
///
/// ## A question is an interruption
///
/// The whole of R-83 rests on one sentence: **a person asked ten questions has been interrupted
/// ten times**, whatever the app calls them. So the two kinds keep their own caps *and* draw on
/// one shared daily budget that is deliberately smaller than their sum — `dailyInterruptionCap`
/// (8) is less than `dailyQueryCap` (4) + `dailyAccusationCap` (6) — because two budgets that
/// cannot both be exhausted are not sharing anything.
///
/// ## The last unit belongs to the accusation
///
/// `reservedAccusationUnits` is the one rule here that is not arithmetic. Running out of budget
/// on *questions* and therefore being unable to say "you are off task" is the failure that
/// defeats the product. `InterruptionBudget.sharedRemainingForQueries` is where that subtraction
/// lives — once, in one place — and this type never repeats it.
///
/// ## The order the refusals are checked in
///
/// Corrected → snoozed → backoff → cooldown → cap. The two the **person** authored come first,
/// because the honest answer to "why was it quiet?" is "because you told it to be", and an
/// arithmetic reason offered ahead of an instruction would be the app taking credit for
/// restraint the person imposed on it. The three that follow are ordered longest-lived first.
public struct FatigueController: Sendable, Equatable {
    /// The session's fatigue. The day's spend is a separate value, read from the log.
    public private(set) var state: FatigueState

    public init(state: FatigueState = .fresh) {
        self.state = state
    }

    // MARK: - The decision

    /// **May the app interrupt once more?**
    ///
    /// - Parameters:
    ///   - kind: a question or an accusation. They are different in kind and identical in cost.
    ///   - subject: what it would be about, for the snooze and correction checks. `nil` for a
    ///     mixed accusation, which names nobody and can therefore be neither snoozed nor
    ///     corrected — offering "this is relevant" over "several unrelated apps" would write a
    ///     rule about something the person never pointed at.
    ///   - rung: the accusation rung being considered, or `nil` for a question. Read twice: the
    ///     ambient rung is never snoozed (R-87) and is the one rung a held ladder may still
    ///     show (R-83).
    ///   - budget: the day's spend, from `InterventionLog.budget(on:priorityID:)`.
    ///   - fatigue: the session's cooldowns and runs.
    ///   - snoozes: what is snoozed and until when.
    ///   - correctedSubjects: subjects a `thisIsRelevant` correction has taken out of the
    ///     accusable set this session.
    ///   - now: a reading of the injected monotonic clock.
    public static func decide(
        kind: InterruptionKind,
        subject: String?,
        rung: LadderRung.Kind? = nil,
        budget: InterruptionBudget,
        fatigue: FatigueState,
        snoozes: SnoozeBook = .none,
        correctedSubjects: Set<String> = [],
        now: Duration
    ) -> FatigueDecision {
        // 1 — the person said this is real work. A correction suppresses harder than an ignore,
        // because it removes the subject from the accusable set entirely rather than deferring
        // it, and the backoff never has to see it again.
        if let subject, correctedSubjects.contains(subject) {
            return .refused(.corrected(subject: subject))
        }

        // 2 — the person snoozed it. The ambient rung is exempt: a person who snoozed a panel
        // asked for quiet, not for a lie. A question has no rung, and `.panel` is what one
        // renders on, so it is asked about a snoozed subject exactly as an accusation is not:
        // snoozing Safari means "stop talking to me about Safari", and the kind of sentence the
        // app was about to say does not change what the person asked for.
        if let subject, snoozes.suppresses(rung: rung ?? .panel, subject: subject, at: now) {
            let remaining = snoozes.snooze(for: subject)?.remaining(at: now) ?? .zero
            return .refused(.snoozed(subject: subject, remaining: remaining))
        }

        // 3 — the person stopped answering.
        switch kind {
        case .query:
            if fatigue.isBackedOff(.query, now: now) {
                return .refused(.backedOff(until: fatigue.queriesSuspendedUntil))
            }
        case .accusation:
            // The accusation backoff does not silence the ladder; it holds it at the ambient
            // rung, which is the one channel the person has not objected to.
            if fatigue.isHeldAtAmbient(now: now), rung != .ambient {
                return .refused(.heldAtAmbient(until: fatigue.accusationsHeldUntil))
            }
        }

        // 4 — too soon after the last one of this kind.
        guard fatigue.cooledDown(kind, now: now) else {
            return .refused(.cooldown(remaining: remainingCooldown(kind, fatigue: fatigue, now: now)))
        }

        // 5 — the caps, and the reserved unit inside them.
        //
        // **A rung is refused only by a cap it can spend** (focus-2yy, focus-d6r). Gates 1, 2 and
        // 3 above all exempt the ambient rung by name — a correction is subject-scoped, a snooze
        // is asked as `rung ?? .panel` precisely so that it never takes the glyph, and the
        // ignored-accusation hold answers `rung != .ambient` with the comment *"the accusation
        // backoff does not silence the ladder; it holds it at the ambient rung, which is the one
        // channel the person has not objected to"*. This gate exempted nothing, so once the day's
        // accusations were spent the glyph was refused too. Measured, six accusations spent and
        // fatigue fresh:
        //
        //     rung=ambient accuses=false spendsAccusationCap=false
        //       decision=refused(cap(dailyAccusationCap))
        //
        // A rung that spends neither cap being refused by one is the status item going dark for
        // the rest of a working day, which is F-146's *"the state is always legible"* broken by
        // arithmetic and is exactly what gates 2 and 3 were written to prevent. `NudgeDecider`
        // already states the intended rule one line above the call: *"the fatigue controller's
        // answer depends on the rung — a held ladder still shows the glyph, and a snooze never
        // touches it."*
        //
        // Asked through `InterruptionCharge`, which is the single derivation of *"did this speak
        // to anybody?"*, rather than through a second copy of the predicate: a rule with two
        // homes is a rule that can be moved in one of them, which is the whole of focus-d6r.
        let charge = InterruptionCharge(
            InterventionEvent(
                kind: kind,
                rung: rung,
                subject: subject ?? "",
                disposition: .delivered
            )
        )
        if charge != nil, let limit = budget.bindingLimit(for: kind) {
            return .refused(.cap(limit))
        }

        return .permitted
    }

    /// The same answer as a `Bool`, for `SuppressionStack.evaluate(…)`'s gate 10.
    ///
    /// A `Bool` is the right shape *there* and the wrong shape everywhere else: the stack
    /// reports one reason per silence and gate 10's reason is `budgetExhausted`, so the detail
    /// travels on `decide(…)`'s answer to the log rather than through the stack.
    public static func permits(
        kind: InterruptionKind,
        subject: String?,
        rung: LadderRung.Kind? = nil,
        budget: InterruptionBudget,
        fatigue: FatigueState,
        snoozes: SnoozeBook = .none,
        correctedSubjects: Set<String> = [],
        now: Duration
    ) -> Bool {
        decide(
            kind: kind,
            subject: subject,
            rung: rung,
            budget: budget,
            fatigue: fatigue,
            snoozes: snoozes,
            correctedSubjects: correctedSubjects,
            now: now
        ).isPermitted
    }

    /// How much of this kind's cooldown is left. `.zero` once it has expired.
    static func remainingCooldown(
        _ kind: InterruptionKind,
        fatigue: FatigueState,
        now: Duration
    ) -> Duration {
        let last: Duration?
        switch kind {
        case .query: last = fatigue.lastQueryAt
        case .accusation: last = fatigue.lastAccusationAt
        }
        guard let last else { return .zero }
        let elapsed = now - last
        let span = FatigueState.cooldown(for: kind)
        return elapsed >= span ? .zero : span - elapsed
    }

    // MARK: - The reducer

    /// Fold one event in and return the new fatigue state.
    ///
    /// Pure, on an injected monotonic reading, with no timer anywhere (R-96i) — which is what
    /// makes the backoff fixtures exact assertions rather than flaky ones.
    @discardableResult
    public mutating func reduce(_ event: FatigueEvent, now: Duration) -> FatigueState {
        state = Self.reduce(state, event: event, now: now)
        return state
    }

    /// The reducer as a free function, so a replay can fold a transcript without holding an
    /// instance and two runs can be compared value to value.
    public static func reduce(
        _ state: FatigueState,
        event: FatigueEvent,
        now: Duration
    ) -> FatigueState {
        switch event {
        case .delivered(.query):
            return FatigueState(
                lastQueryAt: now,
                lastAccusationAt: state.lastAccusationAt,
                consecutiveUnansweredQueries: state.consecutiveUnansweredQueries,
                consecutiveIgnoredAccusations: state.consecutiveIgnoredAccusations,
                queriesSuspendedUntil: state.queriesSuspendedUntil,
                accusationsHeldUntil: state.accusationsHeldUntil
            )

        case .delivered(.accusation):
            return FatigueState(
                lastQueryAt: state.lastQueryAt,
                lastAccusationAt: now,
                consecutiveUnansweredQueries: state.consecutiveUnansweredQueries,
                consecutiveIgnoredAccusations: state.consecutiveIgnoredAccusations,
                queriesSuspendedUntil: state.queriesSuspendedUntil,
                accusationsHeldUntil: state.accusationsHeldUntil
            )

        case .queryResolved(let outcome):
            return resolvingQuery(state, answered: outcome.isAnswer, now: now)

        case .accusationResolved(let outcome):
            return resolvingAccusation(state, unanswered: outcome.isUnanswered, now: now)

        case .sessionEnded:
            // The hold is "for the rest of the session" and the runs are runs within one, so
            // both die here. The day's caps do not: those are rows in a store, and a person
            // cannot clear them by finishing a session.
            return .fresh
        }
    }

    /// A question is over.
    ///
    /// An **answer** ends the run outright and lifts any suspension: the person is talking to
    /// the app again, and continuing to hold their questions would be punishing them for having
    /// engaged. Anything else — "Not now", Escape, an expiry, a surface that went out of reach —
    /// extends it, and at
    /// `ignoredQueryBackoff` the app stops asking for `backoffSpan`.
    private static func resolvingQuery(
        _ state: FatigueState,
        answered: Bool,
        now: Duration
    ) -> FatigueState {
        guard !answered else {
            return FatigueState(
                lastQueryAt: state.lastQueryAt,
                lastAccusationAt: state.lastAccusationAt,
                consecutiveUnansweredQueries: 0,
                consecutiveIgnoredAccusations: state.consecutiveIgnoredAccusations,
                queriesSuspendedUntil: nil,
                accusationsHeldUntil: state.accusationsHeldUntil
            )
        }

        let run = state.consecutiveUnansweredQueries + 1
        let trips = run >= InterventionPolicy.ignoredQueryBackoff

        // Arming the backoff **closes the run**. The counter is a run of two unanswered
        // questions; once the hour has been imposed, the next hour must be earned by another
        // two rather than by a single one an hour later.
        return FatigueState(
            lastQueryAt: state.lastQueryAt,
            lastAccusationAt: state.lastAccusationAt,
            consecutiveUnansweredQueries: trips ? 0 : run,
            consecutiveIgnoredAccusations: state.consecutiveIgnoredAccusations,
            queriesSuspendedUntil: trips
                ? now + InterventionPolicy.backoffSpan
                : state.queriesSuspendedUntil,
            accusationsHeldUntil: state.accusationsHeldUntil
        )
    }

    /// A delivered accusation rung is over.
    ///
    /// Anything the person actually did — a correction, a snooze, a pause, a return, a priority
    /// change — ends the run. A dismissal and an ignore extend it, and at
    /// `ignoredAccusationBackoff` the ladder is held at `.ambient` for
    /// `InterventionPolicy.backoffSpan`.
    ///
    /// **This is the consumer of that constant that can actually reach it** (focus-yxb). The run
    /// is a fact about the session and survives a change of drift subject, so two dismissals
    /// about two different things trip it — measured, driving the loop's own sequence, in
    /// `NudgeReachabilityTests`. `LadderMachine`'s run is scoped to one subject and cannot pass
    /// one from anything the host can do, so this hold is the one a person actually meets.
    ///
    /// **The hold lasts an hour and then lifts** (focus-845). It used to last "for the rest of
    /// the session", which was R-83 read literally and, since U-2 cut the ladder to two rungs, a
    /// mute rather than a backoff: the panel is the only rung that says anything, so two
    /// dismissals ended the speaking product for the day. The previous round verified only that
    /// the constant *fires*; the consequence of firing was the defect. The twin below it,
    /// `resolvingQuery(_:answered:now:)`, trips at the same count of 2 and has always bounded
    /// itself — this now reads the same span, so there is one policy rather than two postures.
    ///
    /// **The hold is still not lifted by a later correction.** A person who ignored two rungs and
    /// then corrected the third subject has told the app two things, and the quieter of them is
    /// the one that stands — for the hour it was granted, and no longer.
    private static func resolvingAccusation(
        _ state: FatigueState,
        unanswered: Bool,
        now: Duration
    ) -> FatigueState {
        guard unanswered else {
            return FatigueState(
                lastQueryAt: state.lastQueryAt,
                lastAccusationAt: state.lastAccusationAt,
                consecutiveUnansweredQueries: state.consecutiveUnansweredQueries,
                consecutiveIgnoredAccusations: 0,
                queriesSuspendedUntil: state.queriesSuspendedUntil,
                accusationsHeldUntil: state.accusationsHeldUntil
            )
        }

        let run = state.consecutiveIgnoredAccusations + 1
        let trips = run >= InterventionPolicy.ignoredAccusationBackoff

        return FatigueState(
            lastQueryAt: state.lastQueryAt,
            lastAccusationAt: state.lastAccusationAt,
            consecutiveUnansweredQueries: state.consecutiveUnansweredQueries,
            consecutiveIgnoredAccusations: trips ? 0 : run,
            queriesSuspendedUntil: state.queriesSuspendedUntil,
            // **The hold is armed with an expiry, exactly as its twin above is** (focus-845).
            // A run that trips while a hold is already running extends it from *now*, because
            // two more dismissals inside the hour are two more refusals to engage — the same
            // reading the query side gives its own `trips ? now + span` branch.
            accusationsHeldUntil: trips
                ? now + InterventionPolicy.backoffSpan
                : state.accusationsHeldUntil
        )
    }
}
