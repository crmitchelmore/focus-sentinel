import Foundation

/// **One judgement, as the nudge sees it.**
///
/// e04 produces a `VerdictSnapshot` for the inspector; this carries that plus the three things
/// the inspector had no use for and a question does: the `ClassificationOutcome` itself, the
/// named route to `uncertain`, and the subject the classification was actually **about**.
///
/// The last of those is P-140's finding made structural. `noNegativeBasis` — 32 of the corpus's
/// 72 uncertain verdicts — produces an explanation with no subject clause at all, because there
/// was no rule, no seed and no context item to name. What there *was* is the application in
/// front of the person, and `QuerySubject.derive(judgedSubject:explanation:)` is the only route
/// from either to a nameable subject. An activation carrying none (`gc-0011`, `gc-0139`) is
/// therefore unaskable rather than asked about under an invented name.
public struct NudgeJudgement: Sendable, Equatable {
    /// The verdict, its source, its confidence and its band.
    public let outcome: ClassificationOutcome
    /// Which named route to `uncertain` the engine took, when it took one. `nil` for a decided
    /// verdict — and for an `uncertain` one that arrived without a reason, which is itself
    /// unaskable, because a question needs one.
    public let uncertainty: UncertaintyReason?
    /// The bundle identifier or normalised origin the classification was about. `nil` for an
    /// unbundled process (e03's P-83 measured six in ninety-two).
    public let subject: String?
    /// How long the person has been with this subject, monotonic.
    public let dwelled: Duration
    /// What the app believes, as a surface would draw it — status, stage, band, drift,
    /// eligibility and explanation.
    public let snapshot: VerdictSnapshot
    /// Which engine said so.
    public let stamp: EngineStamp

    public init(
        outcome: ClassificationOutcome,
        uncertainty: UncertaintyReason?,
        subject: String?,
        dwelled: Duration,
        snapshot: VerdictSnapshot,
        stamp: EngineStamp
    ) {
        self.outcome = outcome
        self.uncertainty = uncertainty
        self.subject = subject
        self.dwelled = dwelled
        self.snapshot = snapshot
        self.stamp = stamp
    }

    public var verdict: Verdict { outcome.verdict }
    public var drift: DriftState { snapshot.drift }
    public var status: FocusStatus { snapshot.status }
    public var explanation: Explanation { snapshot.explanation }
    public var eligibility: InterventionEligibility { snapshot.eligibility }

    /// Whether the person has been here long enough for a **question**.
    ///
    /// `InterventionPolicy.queryDwellThreshold` is half `RelevancePolicy.sustainedDriftThreshold`
    /// — a question may come at half the dwell an accusation needs, because it is cheaper, but
    /// never instantly. A question the moment somebody opens an application is a question about
    /// a keystroke, not about their work.
    public var dwellSatisfied: Bool { dwelled >= InterventionPolicy.queryDwellThreshold }
}

/// **What the world is doing**, at the moment the app is deciding whether to speak.
///
/// Every field is a value produced by the package that owns it — e03's sensing types, e02's
/// calendar, e01's clock. Nothing here is fetched: the nudge module decides *whether to speak*
/// and has no business reaching for a sensing API, and `check-boundaries.sh` proves on the
/// object that it could not (R-96k).
public struct NudgeSurroundings: Sendable, Equatable {
    /// **The one thing the person has committed to, and the only statement of it** (focus-zrs).
    ///
    /// It was a `Bool`, and the identifier every receipt, rule and budget key was written against
    /// came from a *second*, live read of `PriorityStore` inside `NudgeHost`. Nothing enforced
    /// that the two agreed, and the projection this `Bool` was built from is deliberately seeded
    /// with the last good value when the store refuses a read — so the app could pass gate 1 on
    /// one commitment and key the whole interruption to `nil`. See `ActiveCommitment`.
    ///
    /// The gate and the key are now the same optional. `hasActivePriority` is derived from it and
    /// is not stored, so there is no second value to disagree with.
    public let commitment: ActiveCommitment?
    /// Gate 1, derived. There is exactly one fact behind it.
    public var hasActivePriority: Bool { commitment != nil }
    /// F-119's one global switch.
    public let sensingPaused: Bool
    /// e03's `SensitivityGate` answer, already made. The subject is never named through it.
    public let sensitivity: SensitiveScreenDecision
    public let phase: SessionPhase
    public let idle: IdleReading
    /// The person's own idle threshold, from settings.
    public let idleThresholdSeconds: Double
    public let media: MediaActivity
    public let mediaSuppressionEnabled: Bool
    public let presentation: PresentationState
    /// Whether the system menu bar is actually on screen. P-131 measured that it is not during
    /// a full-screen space, while our own status item stays *listed* — which is why this is a
    /// separate reading and not inferred from `presentation`.
    public let menuBarVisible: Bool
    public let quietHours: QuietHours
    /// The wall clock, from an injected `DateProvider`. Quiet hours are the only gate that
    /// reads it.
    public let now: Date
    /// The person's own calendar. Never `Calendar.current`.
    public let calendar: Calendar
    /// A reading of the injected `MonotonicClock`. Every cooldown, dwell and escalation is
    /// measured on this and never on the wall clock.
    public let monotonic: Duration

    public init(
        commitment: ActiveCommitment?,
        sensingPaused: Bool = false,
        sensitivity: SensitiveScreenDecision,
        phase: SessionPhase = .focus,
        idle: IdleReading = IdleReading(hardwareSeconds: 0, sessionSeconds: 0),
        idleThresholdSeconds: Double,
        media: MediaActivity = .idle,
        mediaSuppressionEnabled: Bool = true,
        presentation: PresentationState = .notPresenting,
        menuBarVisible: Bool = true,
        quietHours: QuietHours = .off,
        now: Date,
        calendar: Calendar,
        monotonic: Duration
    ) {
        self.commitment = commitment
        self.sensingPaused = sensingPaused
        self.sensitivity = sensitivity
        self.phase = phase
        self.idle = idle
        self.idleThresholdSeconds = idleThresholdSeconds
        self.media = media
        self.mediaSuppressionEnabled = mediaSuppressionEnabled
        self.presentation = presentation
        self.menuBarVisible = menuBarVisible
        self.quietHours = quietHours
        self.now = now
        self.calendar = calendar
        self.monotonic = monotonic
    }

    /// Whether the person is away, by e03's pessimistic hardware source and their own threshold.
    public var isUserIdle: Bool { idle.isIdle(threshold: idleThresholdSeconds) }
}

/// **What the app remembers.**
///
/// Three different lifetimes live here on purpose, and confusing them is how a cap becomes
/// fiction:
///
/// * `budget` is rebuilt from persisted `InterventionRecord` rows on one local day, so the caps
///   survive a relaunch and cannot be cleared by quitting;
/// * `fatigue`, `snoozes`, `correctedSubjects`, `slot` and `ladder` are **session** state, held
///   in memory, because a backoff or a snooze that survived a relaunch would have outlived the
///   situation it was for;
/// * `hasAsked` is the **immutable receipt** — never the rule. The rule an answer writes is
///   deletable by design (R-86 gives every learned chip a remove affordance, F-93 an undo), and
///   an invariant U-1 states absolutely cannot rest on a record one click removes (R-78).
public struct NudgeMemory: Sendable, Equatable {
    /// One open interruption at a time (R-84a).
    public let slot: InterruptionSlot
    /// The day's spend, from `InterventionLog.budget(on:priorityID:)`.
    public let budget: InterruptionBudget
    /// The session's cooldowns and runs.
    public let fatigue: FatigueState
    public let snoozes: SnoozeBook
    /// Subjects a "this is relevant" correction has taken out of the accusable set.
    public let correctedSubjects: Set<String>
    /// Gate 11: whether this exact question has already been asked **and settled** for this
    /// priority. **Read from the ledger, never from the rules store** — and read through
    /// `QueryLedger.isSettled(…)`, which looks at the receipt's *outcome*.
    ///
    /// The outcome is the whole of it (focus-qds). A receipt is written whenever a question
    /// reached somebody, including when the world ended it — a break, a session, a new
    /// commitment — and an expiry is not an answer. Gate 11 is the promise about answers, so a
    /// question the person never answered is still askable however many times it has been
    /// written down.
    public let hasAsked: Bool
    /// Where the ladder has got to.
    public let ladder: LadderMachine

    public init(
        slot: InterruptionSlot = .open,
        budget: InterruptionBudget = .empty,
        fatigue: FatigueState = .fresh,
        snoozes: SnoozeBook = .none,
        correctedSubjects: Set<String> = [],
        hasAsked: Bool = false,
        ladder: LadderMachine = LadderMachine()
    ) {
        self.slot = slot
        self.budget = budget
        self.fatigue = fatigue
        self.snoozes = snoozes
        self.correctedSubjects = correctedSubjects
        self.hasAsked = hasAsked
        self.ladder = ladder
    }
}

extension NudgeMemory {
    /// **Read the two stores once**, and hand `decide(…)` the values they hold.
    ///
    /// This is the seam the plan names when it says the decider takes the ledger and the log:
    /// the stores are read *here*, and `decide(…)` stays a pure function of stored rows plus a
    /// clock reading (R-83). Keeping the read on this side of the line is what lets every
    /// fixture — the corpus, the sequences, the realistic days — drive the decider with no store
    /// at all and still be measuring the shipping decision.
    ///
    /// - Parameters:
    ///   - subject: what a question would be about, from
    ///     `NudgeDecider.querySubject(for:)`. Gate 11 is consulted **before** a warrant is
    ///     constructed, so the ledger key has to be derivable without one.
    ///   - priorityID: the active priority. `nil` leaves `hasAsked` false, which is the honest
    ///     answer when there is none — and gate 1 will have suppressed the interruption anyway.
    @MainActor
    public static func reading(
        ledger: QueryLedger,
        log: InterventionLog,
        priorityID: UUID?,
        subject: QuerySubject?,
        slot: InterruptionSlot = .open,
        fatigue: FatigueState = .fresh,
        snoozes: SnoozeBook = .none,
        correctedSubjects: Set<String> = [],
        ladder: LadderMachine = LadderMachine()
    ) throws -> NudgeMemory {
        var hasAsked = false
        if let priorityID, let subject {
            // **Settled, not merely written down** (focus-qds, U-1). The receipt left behind by
            // a question the world interrupted records that the asking happened; it is not an
            // answer, and gate 11 is the promise about answers.
            hasAsked = try ledger.isSettled(
                priorityID: priorityID,
                subjectKind: subject.kind,
                subject: subject.identifier
            )
        }

        return NudgeMemory(
            slot: slot,
            budget: try log.budget(on: log.today, priorityID: priorityID),
            fatigue: fatigue,
            snoozes: snoozes,
            correctedSubjects: correctedSubjects,
            hasAsked: hasAsked,
            ladder: ladder
        )
    }
}

/// **What the person set** — two things, both of them chosen deliberately in a settings pane.
///
/// It carried a third, the notification authorisation, and that was never something the person
/// *set* here (focus-wy0): it was a reading taken from the system and handed to `SurfaceRouter`,
/// which since U-2 did not read it. A preferences value holding a fact nobody chose and nothing
/// consulted is the shape a stale copy hides in — which is exactly what focus-zrs found the last
/// time this field existed as a copy.
public struct NudgePreferences: Sendable, Equatable {
    /// One of the five static decks. `silentVisual` is a routing deck, not a copy deck.
    public let voice: NudgeVoice
    /// F-148's flag, forced on by `accessibilityDisplayShouldReduceMotion`.
    public let reducedInterruption: Bool

    public init(
        voice: NudgeVoice = .standard,
        reducedInterruption: Bool = false
    ) {
        self.voice = voice
        self.reducedInterruption = reducedInterruption
    }
}

/// **Why the app said nothing**, at three levels of detail.
///
/// `reason` is the sentence a surface draws: the **first** gate of R-84's ordered stack that
/// closed, which is the reason a person would give. The other two are the detail a log, a
/// judgment inspector and an evaluation report need — because "the verdict did not authorise
/// it" is true of a confident `relevant`, of an unaskable `noEvidence` and of an `unrelated`
/// still inside its grace period, and those are three different facts about somebody's day.
public struct NudgeSilence: Sendable, Equatable, Hashable {
    /// The first gate that closed.
    public let reason: NudgeSuppressionReason
    /// The question's own eligibility answer, when a question was considered.
    public let query: QueryWithholdingReason?
    /// e04's own answer, when an accusation was considered.
    public let accusation: SuppressionReason?
    /// **The ladder's own answer, when the ladder had nothing to climb to** (focus-628).
    ///
    /// The third of three, and the one that did not exist: a ladder with nothing to offer
    /// arrived here as `.budgetExhausted` whether a cap had closed, a dwell had not elapsed, the
    /// ladder had topped out or it was held at the ambient rung. Four facts reported as one, and
    /// the report was wrong for three of them.
    public let ladder: LadderSilence?

    public init(
        reason: NudgeSuppressionReason,
        query: QueryWithholdingReason? = nil,
        accusation: SuppressionReason? = nil,
        ladder: LadderSilence? = nil
    ) {
        self.reason = reason
        self.query = query
        self.accusation = accusation
        self.ladder = ladder
    }
}

/// **What the app is going to do about one judgement.** Four answers, and no fifth.
///
/// The `deferred` case is spelled with the same word `RungDelivery.deferred` uses rather than
/// the Swift keyword, so one vocabulary covers the decision and the delivery it becomes.
public enum NudgeDecision: Sendable, Equatable {
    /// Say "you are off task", at this rung, on this surface.
    ///
    /// It used to carry a `preempting:` question — the one closed as `declined` to make room.
    /// U-2 deleted the mechanism: an accusation offered against an open question is now
    /// **withheld**, so there is never a displaced question to name.
    case accuse(rung: LadderRung, route: SurfaceRoute)
    /// Ask "is this part of it?", on this surface.
    case ask(QueryWarrant, SurfaceRoute)
    /// Say nothing, and this is why.
    case silent(NudgeSilence)
    /// The app would have spoken and could not be seen. **Does not advance the ladder, does not
    /// spend either cap, does not start the escalation clock** (R-81).
    case deferred(DeferralReason)

    /// A silence with only its first gate named — the common shape at a call site.
    public static func silent(_ reason: NudgeSuppressionReason) -> NudgeDecision {
        .silent(NudgeSilence(reason: reason))
    }

    public var rung: LadderRung? {
        switch self {
        case .accuse(let rung, _): rung
        case .ask, .silent, .deferred: nil
        }
    }

    public var warrant: QueryWarrant? {
        switch self {
        case .ask(let warrant, _): warrant
        case .accuse, .silent, .deferred: nil
        }
    }

    public var route: SurfaceRoute? {
        switch self {
        case .accuse(_, let route), .ask(_, let route): route
        case .silent, .deferred: nil
        }
    }

    public var silence: NudgeSilence? {
        switch self {
        case .silent(let silence): silence
        case .accuse, .ask, .deferred: nil
        }
    }

    public var deferralReason: DeferralReason? {
        switch self {
        case .deferred(let reason): reason
        case .accuse, .ask, .silent: nil
        }
    }

    /// Which kind of interruption this is, or `nil` when it is none.
    public var kind: InterruptionKind? {
        switch self {
        case .accuse: .accusation
        case .ask: .query
        case .silent, .deferred: nil
        }
    }

    /// Whether the app is about to say something a person could see.
    public var isSpeaking: Bool { kind != nil }
}

/// **The one place it is all conjoined** (R-76, R-83, R-84, U-1).
///
/// Nothing else in the app decides whether to speak. The two authorisations, the twelve-gate
/// suppression stack, the fatigue controller, the ladder and the surface router all meet here
/// and nowhere else, which is what makes U-1's posture a single readable function rather than a
/// property somebody has to assemble from five call sites:
///
/// | verdict | what happens |
/// |---|---|
/// | `relevant`, confidently derived | **silence** — and it is the only thing that buys silence |
/// | `uncertain` | **a question**, if the question is answerable, unasked and affordable |
/// | `unrelated` | **the ladder**, one rung at a time |
///
/// ## The accusation is considered first, and that is still R-84a
///
/// *"You are off task"* outranks *"is this part of it?"*, so a live mandate takes the path
/// before the query affordance is even consulted. What it no longer does is take the screen off
/// a question that is already on it: under U-2 an accusation offered against an open question is
/// withheld as `interruptionInFlight` and **waits**. The rung is not spent by waiting — no
/// delivery is recorded, the escalation clock does not start, and the next judgement offers the
/// same rung again.
///
/// ## An uncertain verdict cannot reach `.accuse`, and not because of a check
///
/// `.accuse` carries a `LadderRung`. A rung has exactly one initialiser and it takes an
/// `InterventionMandate`, which e04's sole producer returns `.suppressed(.verdictUncertain)`
/// before building. There is no value this function could construct from an `uncertain`
/// judgement that `.accuse` would accept — so the invariant is a fact about the types, and
/// `NudgeDeciderTests`' truth table plus `nudge.accusationsFromQuery == 0` are checks on it
/// rather than the thing itself (R-76).
public struct NudgeDecider: Sendable {
    /// **Decide once.**
    ///
    /// Pure: every input is a value, and the only clock is the reading on `surroundings`. That
    /// is what makes the sequence and realistic-day fixtures exact assertions rather than flaky
    /// ones, and there is no timer anywhere in this module for a lint to have to find (R-96i).
    public static func decide(
        _ judgement: NudgeJudgement,
        surroundings: NudgeSurroundings,
        memory: NudgeMemory,
        preferences: NudgePreferences
    ) -> NudgeDecision {
        if let mandate = judgement.eligibility.mandate {
            return accuse(
                mandate: mandate,
                judgement: judgement,
                surroundings: surroundings,
                memory: memory,
                preferences: preferences
            )
        }
        return ask(
            judgement: judgement,
            surroundings: surroundings,
            memory: memory,
            preferences: preferences
        )
    }

    /// The subject a question about this judgement would be about, or `nil` when there is none.
    ///
    /// Exposed because gate 11 is consulted **before** a warrant is constructed: a host has to
    /// be able to key the ledger on `(priorityID, subjectKind, subject)` without first producing
    /// the very thing that gate exists to prevent.
    public static func querySubject(for judgement: NudgeJudgement) -> QuerySubject? {
        QuerySubject.derive(
            judgedSubject: judgement.subject,
            explanation: judgement.explanation
        )
    }

    // MARK: - The accusation

    private static func accuse(
        mandate: InterventionMandate,
        judgement: NudgeJudgement,
        surroundings: NudgeSurroundings,
        memory: NudgeMemory,
        preferences: NudgePreferences
    ) -> NudgeDecision {
        var ladder = memory.ladder
        ladder.reduce(.mandate(mandate), now: surroundings.monotonic)

        // `budgetPermits: true` here, deliberately: the ladder is being asked *which* rung is
        // next, and the fatigue controller's answer depends on the rung — a held ladder still
        // shows the glyph, and a snooze never touches it. Asking in the other order would mean
        // checking a budget against a rung nobody had chosen yet.
        //
        // **And the answer is a silence with a subject now, not a `nil`** (focus-628, focus-50m).
        // A ladder with nothing to climb to used to arrive here as a bare `nil` and leave as
        // `.silent(.budgetExhausted)` — four different facts reported as one, and, because a
        // silence with no subject cannot be asked *which rungs it applies to*, a silence that
        // took the glyph with it. `SilenceSubject`'s whole rule is that a reason about the app
        // **speaking** passes a rung that says nothing; `LadderSilence` is that vocabulary and
        // `retainsTheAmbientRung` is where the rule is applied to it.
        var rung: LadderRung
        switch ladder.step(at: surroundings.monotonic, budgetPermits: true) {
        case .rung(let climbing):
            rung = climbing
        case .silent(let silence):
            guard silence.retainsTheAmbientRung, let retained = ladder.retainedRung else {
                // Gate 10's business — "a cap, a cooldown or a backoff" — and "not now" rather
                // than "not ever". The ladder's own reason travels on the silence so that the
                // report says which of the four it was.
                return .silent(
                    NudgeSilence(
                        reason: .budgetExhausted,
                        accusation: judgement.eligibility.suppressionReason,
                        ladder: silence
                    )
                )
            }
            rung = retained
        }

        var fatigue = FatigueController.decide(
            kind: .accusation,
            subject: rung.subject,
            rung: rung.kind,
            budget: memory.budget,
            fatigue: memory.fatigue,
            snoozes: memory.snoozes,
            correctedSubjects: memory.correctedSubjects,
            now: surroundings.monotonic
        )

        // **The refusal was read against the rung the ladder wanted to CLIMB to, and nobody asked
        // it about the rung that says nothing** (focus-628, focus-fzf, F-63, R-87).
        //
        // `FatigueController.decide(…)` already applies `SilenceSubject` — a refusal about the app
        // speaking passes the ambient rung — but it applies it to the rung it is *handed*, and the
        // ladder hands it an escalation. So a held or capped ladder standing at `.engaged(.ambient,
        // …)` had exactly one thing left to offer, the escalation, and when that was refused the
        // app went completely quiet: measured on the shipping composition root, the sixteen-drift
        // day showed the person nothing at all on eleven of them, with the glyph exempt by name in
        // every rule involved.
        //
        // Asking a second time is the whole repair, and it asks the same function the same way —
        // there is no second copy of the exemption here, only the rung the first reading never
        // mentioned. A refusal whose subject is `.anythingToBeLegibleAbout` (a correction) refuses
        // again and the app is silent, which is the ruling that case exists for.
        if case .refused(let refusal) = fatigue,
            rung.kind.makesAnAccusation,
            refusal.subject.ruling(for: .ambient) == .passes,
            let retained = ladder.retainedRung {
            rung = retained
            fatigue = FatigueController.decide(
                kind: .accusation,
                subject: rung.subject,
                rung: rung.kind,
                budget: memory.budget,
                fatigue: memory.fatigue,
                snoozes: memory.snoozes,
                correctedSubjects: memory.correctedSubjects,
                now: surroundings.monotonic
            )
        }

        // The slot, read through the type that owns the ruling rather than restated here. Since
        // U-2 an accusation is admitted against an empty slot and against another accusation, and
        // **withheld against an open question**. `InterruptionSlotTests` is where that is asserted.
        let slot = memory.slot.offering(rung)

        let outcome = SuppressionStack.evaluate(
            kind: .accusation,
            rung: rung.kind,
            hasActivePriority: surroundings.hasActivePriority,
            sensingPaused: surroundings.sensingPaused,
            sensitivity: surroundings.sensitivity,
            phase: surroundings.phase,
            idle: surroundings.idle,
            idleThresholdSeconds: surroundings.idleThresholdSeconds,
            media: surroundings.media,
            mediaSuppressionEnabled: surroundings.mediaSuppressionEnabled,
            presentation: surroundings.presentation,
            quietHours: surroundings.quietHours,
            now: surroundings.now,
            calendar: surroundings.calendar,
            interruptionInFlight: slot.slot == nil,
            budgetPermits: fatigue.isPermitted,
            // Gate 11 is queries only. An accusation passes straight through it, and passing
            // `false` here says so rather than relying on the stack to ignore the argument.
            hasAsked: false,
            // Gate 12, for an accusation, is e04's own producer — which has already run, and
            // whose answer is the mandate this function was handed.
            verdictAuthorises: true
        )

        switch outcome {
        case .suppressed(let reason):
            return .silent(NudgeSilence(reason: reason))
        case .deferred(let reason):
            return .deferred(reason)
        case .permitted:
            break
        }

        let route = SurfaceRouter.route(
            rung: rung.kind,
            presentation: surroundings.presentation,
            media: surroundings.media,
            reducedInterruption: preferences.reducedInterruption,
            menuBarVisible: surroundings.menuBarVisible,
            voice: preferences.voice
        )

        guard route.surface != nil else {
            // No surface can carry it in the state the app is actually in. A deferral, so
            // nothing advances and nothing is spent — and the question in the slot, if there is
            // one, is left exactly where it was, because nothing took its place.
            return .deferred(route.deferralReason ?? .noSurfaceAvailable)
        }

        return .accuse(rung: rung, route: route)
    }

    // MARK: - The question

    private static func ask(
        judgement: NudgeJudgement,
        surroundings: NudgeSurroundings,
        memory: NudgeMemory,
        preferences: NudgePreferences
    ) -> NudgeDecision {
        let subject = querySubject(for: judgement)

        let fatigue = FatigueController.decide(
            kind: .query,
            subject: subject?.identifier,
            rung: nil,
            budget: memory.budget,
            fatigue: memory.fatigue,
            snoozes: memory.snoozes,
            correctedSubjects: memory.correctedSubjects,
            now: surroundings.monotonic
        )

        // The slot's answer does not depend on which question is offered — anything already
        // holding it withholds — so it can be read before a warrant exists, which is what gate 9
        // needs.
        let interruptionInFlight = !memory.slot.isOpen

        let eligibility = QueryEligibility.decide(
            outcome: judgement.outcome,
            uncertainty: judgement.uncertainty,
            drift: judgement.drift,
            dwelled: judgement.dwelled,
            dwellSatisfied: judgement.dwellSatisfied,
            phase: surroundings.phase,
            status: judgement.status,
            isUserIdle: surroundings.isUserIdle,
            hasActivePriority: surroundings.hasActivePriority,
            hasAsked: memory.hasAsked,
            budgetPermits: fatigue.isPermitted,
            interruptionInFlight: interruptionInFlight,
            judgedSubject: judgement.subject,
            explanation: judgement.explanation,
            stamp: judgement.stamp
        )

        let withheld = eligibility.withholdingReason

        let outcome = SuppressionStack.evaluate(
            kind: .query,
            rung: nil,
            hasActivePriority: surroundings.hasActivePriority,
            sensingPaused: surroundings.sensingPaused,
            sensitivity: surroundings.sensitivity,
            phase: surroundings.phase,
            idle: surroundings.idle,
            idleThresholdSeconds: surroundings.idleThresholdSeconds,
            media: surroundings.media,
            mediaSuppressionEnabled: surroundings.mediaSuppressionEnabled,
            presentation: surroundings.presentation,
            quietHours: surroundings.quietHours,
            now: surroundings.now,
            calendar: surroundings.calendar,
            interruptionInFlight: interruptionInFlight,
            budgetPermits: fatigue.isPermitted,
            hasAsked: memory.hasAsked,
            verdictAuthorises: eligibility.isWarranted
        )

        switch outcome {
        case .suppressed(let reason):
            return .silent(
                NudgeSilence(
                    reason: reason,
                    query: withheld,
                    accusation: judgement.eligibility.suppressionReason
                )
            )
        case .deferred(let reason):
            return .deferred(reason)
        case .permitted:
            break
        }

        guard let warrant = eligibility.warrant else {
            // Unreachable while gate 12 reads `eligibility.isWarranted`, and handled rather than
            // asserted: a decider that trapped on a state it believed impossible would be a
            // crash in place of a silence, which is the least humane trade in the programme.
            return .silent(
                NudgeSilence(
                    reason: .verdictDoesNotAuthorise,
                    query: withheld,
                    accusation: judgement.eligibility.suppressionReason
                )
            )
        }

        let route = SurfaceRouter.routeQuery(
            presentation: surroundings.presentation,
            media: surroundings.media,
            reducedInterruption: preferences.reducedInterruption,
            menuBarVisible: surroundings.menuBarVisible,
            voice: preferences.voice
        )

        guard route.surface != nil else {
            return .deferred(route.deferralReason ?? .noSurfaceAvailable)
        }

        return .ask(warrant, route)
    }
}
