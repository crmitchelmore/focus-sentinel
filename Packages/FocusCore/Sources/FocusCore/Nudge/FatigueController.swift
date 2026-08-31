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

    /// **The closed set of refusals, without their payloads** (focus-uru).
    ///
    /// `FatigueRefusal` carries a subject, a remaining duration, an expiry and a limit, so it
    /// cannot be `CaseIterable` itself — and for six rounds that meant the one vocabulary in this
    /// programme with no way to be folded over was also the one accumulating defects. The other
    /// two answers to *"why did the app go quiet?"* are `CaseIterable` and one of them,
    /// `InterruptionLimit`, was folded against the ambient rung last round and has none.
    ///
    /// This is the fold-able shape: `allCases` is what `FatigueVocabularyTests` walks, so a
    /// seventh refusal added above cannot reach a person without a witness row driving the state
    /// that produces it.
    public enum Kind: String, Sendable, CaseIterable, Codable, Hashable {
        case corrected
        case snoozed
        case backedOff
        case heldAtAmbient
        case cooldown
        case cap

        /// **What this refusal is about, and therefore which rungs it may silence** (focus-uru).
        ///
        /// Gates 1, 2, 3 and — since focus-2yy — 5 of `FatigueController.decide(…)` each grew
        /// their own bespoke exemption for the ambient rung, spelled four different ways: a
        /// correction is subject-scoped, a snooze is asked as `rung ?? .panel`, the hold answers
        /// `rung != .ambient`, and the caps ask `InterruptionCharge`. Gate 4 sits between the
        /// third and the fifth and had none, so **the one channel that is supposed to survive
        /// everything was muted for 600 s at a time by a cooldown belonging to the rung that
        /// speaks.** Measured, before this property existed:
        ///
        ///     rung=ambient, gap=60s → refused(cooldown(remaining: 540s))
        ///
        /// Five of the six are about the app speaking, and the sixth is the reason the sixth
        /// exists:
        ///
        /// * **`corrected` is legibility, and it is the only one.** The person clicked *"this is
        ///   relevant"*. There is no longer anything to be off task about, so the glyph must
        ///   **stop** marking them — a mark that survived a correction would be the app arguing
        ///   with an instruction it was just given. This is also why gate 10 of
        ///   `SuppressionStack` does not classify: if it did, it would pass the glyph over this.
        /// * `snoozed` is R-87's own sentence — *"never applied to the ambient rung, because the
        ///   glyph goes on telling the truth"*.
        /// * `backedOff` is questions only, and a question always speaks.
        /// * `heldAtAmbient` names the exemption in its own case name: the hold *is* the ladder
        ///   standing at the rung this subject exempts.
        /// * `cooldown` is a minimum gap between **sentences**. The glyph makes none, spends
        ///   neither cap, and costs a person nothing to have been shown twice.
        /// * `cap` is focus-2yy's ruling, restated where the other five are: *a rung is refused
        ///   only by a cap it can spend*.
        ///
        /// **Never `.theSurfaceBeingOnScreen`.** `FatigueDecision` has two cases and no third, on
        /// purpose: a deferral is the suppression stack's answer to give, and this controller
        /// answers gate 10 with a `Bool`. `FatigueVocabularyTests` holds that over `allCases`.
        public var subject: SilenceSubject {
            switch self {
            case .corrected: .anythingToBeLegibleAbout
            case .snoozed, .backedOff, .heldAtAmbient, .cooldown, .cap: .theAppSpeaking
            }
        }
    }

    /// Which refusal this is, payload discarded.
    public var kind: Kind {
        switch self {
        case .corrected: .corrected
        case .snoozed: .snoozed
        case .backedOff: .backedOff
        case .heldAtAmbient: .heldAtAmbient
        case .cooldown: .cooldown
        case .cap: .cap
        }
    }

    /// What this refusal is about — `kind.subject`, forwarded so a call site reads as one thing.
    public var subject: SilenceSubject { kind.subject }
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
    /// **An interruption reached somebody and cost them something.**
    ///
    /// Only a delivery starts a cooldown — a deferred rung nobody could see and a suppressed one
    /// the app chose not to make both leave this state untouched (R-81).
    ///
    /// **It carries the charge rather than the kind** (focus-uru). It was `.delivered(kind)`, and
    /// at both of its production call sites the line above it derived an `InterruptionCharge`
    /// from the delivered event — the single derivation of *"did this speak to anybody?"* — and
    /// then folded this reducer **unconditionally on the next line**:
    ///
    ///     if let charge = InterruptionCharge(event, priorityID: …) { charges.append(charge) }
    ///     fatigue = FatigueController.reduce(fatigue, event: .delivered(.accusation), now: now)
    ///
    /// So a glyph landing spent no cap and armed a 600-second cooldown, and the cooldown is a
    /// spend: it is the gap the app keeps between sentences, and the glyph makes none. That is
    /// the same half-treatment `PerceptibleChange` closed for the ledger and `InterruptionCharge`
    /// closed for the caps, surviving one line below each of them. Taking the charge makes the
    /// pair one decision — there is no charge for a rung that spoke to nobody, so there is no way
    /// to spell the event either.
    case delivered(InterruptionCharge)
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
///
/// ## Which rungs each refusal applies to
///
/// **Not decided here, and not five times over** (focus-uru). `candidates(…)` below asks only
/// *does this refusal apply to this moment?*; `FatigueRefusal.Kind.subject` answers *does it
/// apply to this rung?*, once, in an exhaustive switch a seventh refusal cannot skip. Four of the
/// five gates used to carry their own spelling of that rule and the fifth carried none, which is
/// how a cooldown between **sentences** came to mute the one channel that makes none.
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
    ///   - rung: the accusation rung being considered, or `nil` for a question. **Read once, at
    ///     the end, through `FatigueRefusal.Kind.subject`** (focus-uru): a refusal about the app
    ///     speaking passes over a rung that says nothing — the snooze exemption of R-87, the
    ///     held ladder of R-83, the caps of focus-2yy and this round's cooldown are all that one
    ///     ruling — and a refusal about there being anything to be legible about, which is
    ///     `corrected` alone, stops every rung.
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
        // **Every refusal is asked the same two questions: does it apply, and is it about a rung
        // like this one?** (focus-uru).
        //
        // It used to be five hand-written early returns, and four of them grew their own bespoke
        // exemption for the ambient rung, spelled four different ways: gate 1 is subject-scoped,
        // gate 2 asked `rung ?? .panel` so a snooze could never take the glyph, gate 3 answered
        // `rung != .ambient`, and gate 5 asked `InterruptionCharge`. **Gate 4 sat between the
        // third and the fifth with none**, so the one channel that is supposed to survive
        // everything was muted for `mandateCooldown` at a time by a cooldown belonging to the
        // rung that speaks. Measured before this fold:
        //
        //     rung=ambient, gap=60s → refused(cooldown(remaining: 540s))
        //
        // Two rounds swept this closed set by reading the gates in prose and each missed the same
        // one. It is not swept by reading now: `FatigueRefusal.Kind.subject` is an exhaustive
        // switch, so a seventh refusal does not compile until it has been ruled on, and the
        // ruling is applied here rather than at five separate sites.
        //
        // The order is the one this type has always kept — corrected, snoozed, backoff, cooldown,
        // cap — because the honest answer to "why was it quiet?" is the first that applied.
        for refusal in candidates(
            kind: kind,
            subject: subject,
            budget: budget,
            fatigue: fatigue,
            snoozes: snoozes,
            correctedSubjects: correctedSubjects,
            now: now
        ) where refusal.subject.silences(rung) {
            return .refused(refusal)
        }

        return .permitted
    }

    /// **Every refusal that applies right now, in evaluation order and before the rung is read.**
    ///
    /// Split out so the two questions stay separate: *does this refusal apply to this moment?* is
    /// arithmetic about the day and the session, and *does it apply to this rung?* is
    /// `SilenceSubject`'s single ruling. Mixing them is what produced four different spellings of
    /// one exemption and one gate with none.
    ///
    /// Eager rather than lazy: all five are pure functions of values already in hand, and an
    /// order that is a property of this array is an order a reader can check.
    static func candidates(
        kind: InterruptionKind,
        subject: String?,
        budget: InterruptionBudget,
        fatigue: FatigueState,
        snoozes: SnoozeBook,
        correctedSubjects: Set<String>,
        now: Duration
    ) -> [FatigueRefusal] {
        var refusals: [FatigueRefusal] = []

        // 1 — the person said this is real work. A correction suppresses harder than an ignore,
        // because it removes the subject from the accusable set entirely rather than deferring
        // it, and the backoff never has to see it again. **The one refusal here whose subject is
        // legibility**: a subject the person has just called real work is a subject the glyph
        // must stop marking.
        if let subject, correctedSubjects.contains(subject) {
            refusals.append(.corrected(subject: subject))
        }

        // 2 — the person snoozed it. Asked of the **subject** alone now, not of
        // `suppresses(rung: rung ?? .panel, …)`: snoozing Safari means "stop talking to me about
        // Safari", the kind of sentence the app was about to say does not change what the person
        // asked for, and R-87's *"never applied to the ambient rung"* is the ruling above rather
        // than an argument threaded through a defaulted parameter.
        if let subject, snoozes.suppresses(subject: subject, at: now) {
            let remaining = snoozes.snooze(for: subject)?.remaining(at: now) ?? .zero
            refusals.append(.snoozed(subject: subject, remaining: remaining))
        }

        // 3 — the person stopped answering. Two shapes, because a question is suspended outright
        // and an accusation ladder is *held at the rung below*, which is a fact about the ladder
        // rather than a veto here (`FatigueState.isBackedOff(.accusation, …)` answers `false` and
        // says so).
        switch kind {
        case .query:
            if fatigue.isBackedOff(.query, now: now) {
                refusals.append(.backedOff(until: fatigue.queriesSuspendedUntil))
            }
        case .accusation:
            if fatigue.isHeldAtAmbient(now: now) {
                refusals.append(.heldAtAmbient(until: fatigue.accusationsHeldUntil))
            }
        }

        // 4 — too soon after the last one of this kind. **The gate this round is about.** A
        // cooldown is a minimum gap between *sentences*; the glyph makes none, spends neither
        // cap, and costs a person nothing to have been shown twice — so it is `.theAppSpeaking`
        // like the three around it, and the ruling above is what applies it.
        if !fatigue.cooledDown(kind, now: now) {
            refusals.append(.cooldown(remaining: remainingCooldown(kind, fatigue: fatigue, now: now)))
        }

        // 5 — the caps, and the reserved unit inside them. **A rung is refused only by a cap it
        // can spend** (focus-2yy, focus-d6r), which is now the same sentence as gates 2, 3 and 4
        // rather than a fifth spelling of it.
        //
        // The `InterruptionCharge` this gate used to construct is gone from here, and nothing is
        // lost: `InterruptionCharge(_ event:)` answers `nil` exactly when
        // `InterventionEvent.spendsTheInterruptionCap` is `false`, which for a delivery is
        // `kind == .query || rung?.makesAnAccusation ?? true` — the predicate
        // `SilenceSubject.ruling(for:)` reads. The rule kept its single home and moved up a
        // level, where it now covers five gates instead of one.
        if let limit = budget.bindingLimit(for: kind) {
            refusals.append(.cap(limit))
        }

        return refusals
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
        case .delivered(let charge):
            // Switched over the charge's kind, exhaustively — a `where` clause and a catch-all
            // would put the accusation on the arm that also catches whatever a third kind turned
            // out to be.
            switch charge.kind {
            case .query:
                return FatigueState(
                    lastQueryAt: now,
                    lastAccusationAt: state.lastAccusationAt,
                    consecutiveUnansweredQueries: state.consecutiveUnansweredQueries,
                    consecutiveIgnoredAccusations: state.consecutiveIgnoredAccusations,
                    queriesSuspendedUntil: state.queriesSuspendedUntil,
                    accusationsHeldUntil: state.accusationsHeldUntil
                )
            case .accusation:
                return FatigueState(
                    lastQueryAt: state.lastQueryAt,
                    lastAccusationAt: now,
                    consecutiveUnansweredQueries: state.consecutiveUnansweredQueries,
                    consecutiveIgnoredAccusations: state.consecutiveIgnoredAccusations,
                    queriesSuspendedUntil: state.queriesSuspendedUntil,
                    accusationsHeldUntil: state.accusationsHeldUntil
                )
            }

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
