import FocusClassify
import FocusCore
import Foundation

/// The values every nudge lane holds still, so that three lanes measure one behaviour.
///
/// Nothing here is a threshold about a person — those are all in `InterventionPolicy`, which is
/// the one place a nudge number may be written down (R-95, lint R-96j). These are the fixed
/// surroundings a replay supplies so that the *only* things varying between fixtures are the ones
/// the fixture is about.
public enum NudgeLane {
    /// The idle threshold the replays use, and how idle a step that declares `isUserIdle` is.
    ///
    /// Both live in `EvaluationPolicy` rather than here, because that is the harness tree's
    /// `RelevancePolicy`: the one file in which a number may be written down, and the one place a
    /// reviewer looks for one (R-70f, extended to this lane).
    public static var idleThresholdSeconds: Double { EvaluationPolicy.nudgeIdleThresholdSeconds }
    public static var idleSeconds: Double { EvaluationPolicy.nudgeIdleSeconds }

    /// Midnight UTC on 1 January 2026 — `EvaluationPolicy.ruleEpochSecondsSince1970`, reused so
    /// the wall clock a quiet-hours gate reads and the wall clock a rule was created at are the
    /// same instant in every lane.
    public static var referenceDate: Date {
        Date(timeIntervalSince1970: EvaluationPolicy.ruleEpochSecondsSince1970)
    }

    /// A person's own calendar, pinned. Never `Calendar.current`: a harness whose day boundary
    /// moved with the machine's time zone would produce a different report in two places.
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .gmt
        return calendar
    }

    /// A `SensitiveScreenDecision` for a subject, produced by **e03's own gate** rather than
    /// constructed here.
    ///
    /// `ClearedActivation`'s initialiser is `fileprivate` and `SensitivityGate.evaluate(_:)` is
    /// its only producer, which is exactly the property gate 3 of the suppression stack rests on:
    /// the nudge lane cannot manufacture a cleared activation, so a fixture that reaches gate 3
    /// reaches it through the type that owns it (goal §3.E.31).
    public static func sensitivity(of subject: String?) -> SensitiveScreenDecision {
        SensitivityGate().evaluate(
            FrontmostActivation(
                bundleIdentifier: subject,
                localizedName: subject,
                pid: EvaluationPolicy.nudgeLanePID,
                at: referenceDate
            )
        )
    }

    /// A full-screen space, as `PresentationQuorum` would report one: three signals agreeing.
    public static let presenting = PresentationState(
        signals: PresentationSignals(
            frontmostWindowFillsAScreen: true,
            presentationOptionsSayFullScreen: true,
            menuBarHidden: true
        ),
        isUserExcluded: false,
        isPresenting: true
    )

    /// The commitment every replayed day is run under. Fixed, because a replay that keyed its
    /// receipts to a fresh identifier on every run would not be a replay.
    public static let replayedCommitmentID = UUID(
        uuidString: "5E1F0C1A-0000-4000-8000-000000000005"
    )!
    public static let replayedCommitmentIntent = "the replayed day's one commitment"

    /// The surroundings one replayed observation happens in.
    ///
    /// Every field is a value produced by the package that owns it. Nothing here is fetched: the
    /// nudge module decides *whether to speak* and has no business reaching for a sensing API,
    /// and `check-boundaries.sh` proves on the object that it could not (R-96k).
    public static func surroundings(
        subject: String?,
        hasActivePriority: Bool,
        phase: SessionPhase,
        isUserIdle: Bool,
        presentation: Bool,
        menuBarVisible: Bool,
        monotonic: Duration
    ) -> NudgeSurroundings {
        NudgeSurroundings(
            // The replayed day's one commitment, named so the fixture drives the same gate the
            // app does — gate 1 is `commitment != nil` and there is no second reading (focus-zrs).
            commitment: hasActivePriority
                ? ActiveCommitment(id: replayedCommitmentID, intent: replayedCommitmentIntent)
                : nil,
            sensingPaused: false,
            sensitivity: sensitivity(of: subject),
            phase: phase,
            idle: IdleReading(
                hardwareSeconds: isUserIdle ? idleSeconds : 0,
                sessionSeconds: isUserIdle ? idleSeconds : 0
            ),
            idleThresholdSeconds: idleThresholdSeconds,
            media: .idle,
            mediaSuppressionEnabled: true,
            presentation: presentation ? presenting : .notPresenting,
            menuBarVisible: menuBarVisible,
            quietHours: .off,
            now: referenceDate,
            calendar: calendar,
            monotonic: monotonic
        )
    }
}

/// The ledger key R-78 commits: `(priorityID, subjectKind, subject)`.
///
/// *Priority*, not session — U-1 says "for this task". Changing the priority legitimately re-opens
/// every question, because a new commitment makes old answers irrelevant; a revision bump on the
/// same priority does not, which is why the priority half of this key is an **identity** and not
/// the priority's prose.
public struct AskedQuestionKey: Sendable, Equatable, Hashable {
    public let priorityID: UUID
    public let subjectKind: RuleSubjectKind
    public let subject: String

    public init(priorityID: UUID, subjectKind: RuleSubjectKind, subject: String) {
        self.priorityID = priorityID
        self.subjectKind = subjectKind
        self.subject = subject
    }
}

/// What the app already held about a subject **before** it opened its mouth.
///
/// This is what `nudge.queryOnDecidableCount == 0` is measured against: *"the app failing to read
/// its own notes, when U-1's entire bargain is that implicit derivation buys silence"* (R-94).
/// Three sources, and the third needs a sentence of its own.
///
/// * **The context pack**, app and domain items only. Attaching an application to a priority *is*
///   saying "expect this"; a file item and a keyword item are excluded for the same reason R-56.1
///   excludes them from the negative basis — neither can ever be *absent*, so neither decides
///   anything.
/// * **A rule at any authority whose verdict is decisive.** A rule whose verdict is `uncertain`
///   is F-130's "ask each time", which is the person asking to be asked; counting it here would
///   make the honouring of their own instruction a defect.
/// * **A decisive seed** — `AppRuleDisposition.seedStage == .seedRule`, which is one row in the
///   whole shipped table — **unless the seed-override guard stood it down.** The guard is the only
///   route by which a decisive seed yields `uncertain`, and it fires when the priority's own words
///   name the seeded application (R-64: *"a bundled default may never accuse somebody of being
///   distracted by the exact thing they wrote down"*). A question there is the app declining to
///   apply its own opinion because the person outranks it, which is the affordance working rather
///   than a note it failed to read — so it is excluded by the `uncertaintyReason` the guard leaves
///   behind, which is a fact carried in the judgement rather than a second copy of the guard.
public struct DecidableSubjects: Sendable, Equatable {
    public let contextPack: Set<String>
    public let decisiveRules: Set<String>

    public init(contextPack: [CorpusContextItem], rules: [CorpusRule]) {
        self.contextPack = Set(
            contextPack
                .filter { $0.kind == .app || $0.kind == .domain }
                .map(\.value)
        )
        self.decisiveRules = Set(
            rules
                .filter { $0.verdict == .relevant || $0.verdict == .unrelated }
                .map(\.subject)
        )
    }

    /// Whether the app already held a decisive answer about this subject.
    public func decides(_ subject: String, uncertainty: UncertaintyReason?) -> Bool {
        if contextPack.contains(subject) || decisiveRules.contains(subject) { return true }
        guard let seed = RelevanceSeed.disposition(for: subject),
              seed.seedStage == .seedRule
        else { return false }
        // The seed-override guard's fingerprint. See the type note.
        return uncertainty != .mixedUseApplication
    }
}

/// One judgement, as the nudge lane saw it.
public struct NudgeObservation: Sendable, Equatable {
    public let decision: NudgeDecision
    /// The ledger key the question was, or would have been, remembered under.
    public let key: AskedQuestionKey?

    public var expectation: NudgeExpectation { NudgeExpectation.observed(decision) }
}

/// **The nudge loop's world, replayed** — one object, three lanes (T143, T144).
///
/// The corpus lane, the sequence lane and the realistic-day lane all drive *this*, so a number in
/// the report cannot come from a second implementation of the decision. What differs between the
/// lanes is only what they hold still:
///
/// | lane | ledger | budget, cooldown, backoff | why |
/// |---|---|---|---|
/// | corpus, pass A | fresh per case | not enforced | each case is an independent claim, exactly as every other corpus expectation is |
/// | corpus, pass B | **one ledger, id order** | not enforced | 165 committed cases are not one person's day; this pass measures volume and proves never-ask-twice |
/// | sequences, days | one of each | **enforced** | a day *is* a day, and the caps are the whole point |
///
/// Nothing in here reads a clock. Every reading arrives as a `Duration` a fixture supplied, which
/// is what makes a replay exact rather than approximately right (R-96i: there is no timer anywhere
/// in the nudge module, and none here either).
public struct NudgeWorld: Sendable, Equatable {
    /// Whether the caps, cooldowns and backoffs bind. `false` for the corpus lane, which is a set
    /// of independent claims rather than a working day.
    public let enforcesFatigue: Bool

    public private(set) var ledger: Set<AskedQuestionKey> = []

    /// The day's spend, **per priority and in total**.
    ///
    /// Three counters rather than one `InterruptionBudget`, because the shipped budget is not a
    /// value that accumulates: `InterventionLog.budget(on:priorityID:)` computes it by predicate
    /// over stored rows, and its per-priority term is scoped to *the priority that is active
    /// now*. A harness that carried one running count would charge a new commitment for the
    /// questions asked under the old one — which is exactly the defect `dailyQueryCapAllPriorities`
    /// exists to close, and it would have hidden it.
    public private(set) var queriesByPriority: [UUID: Int] = [:]
    public private(set) var queriesAllPrioritiesToday = 0
    public private(set) var accusationsToday = 0
    public private(set) var interruptionsToday = 0
    /// Which priority the counts above are read against.
    public private(set) var activePriorityID: UUID?

    /// The budget as the log would compute it for the active priority.
    public var budget: InterruptionBudget {
        InterruptionBudget(
            queriesForPriorityToday: activePriorityID.flatMap { queriesByPriority[$0] } ?? 0,
            queriesAllPrioritiesToday: queriesAllPrioritiesToday,
            accusationsToday: accusationsToday,
            interruptionsToday: interruptionsToday
        )
    }
    public private(set) var fatigue: FatigueState = .fresh
    public private(set) var ladder = LadderMachine()
    public private(set) var slot: InterruptionSlot = .open
    public private(set) var snoozes: SnoozeBook = .none
    public private(set) var correctedSubjects: Set<String> = []
    public private(set) var counters: InterventionCounters = .empty

    /// The ledger key of the question currently on screen, so that its ending writes its receipt
    /// under the same key the asking used (R-84a).
    private var openQueryKey: AskedQuestionKey?

    /// **The question this world is holding — identity, not ownership** (focus-k42, U-2).
    ///
    /// `resolveQuery(…)` read `slot.openQuery`, which is the same conflation `resolveAccusation`
    /// below was repaired for and the same one `NudgeHost.slot` was carrying: it made *which
    /// question this is* and *whether the screen is occupied* one value. They are not one value
    /// once a badge question stops occupying the screen, and a replay that kept them so would
    /// model a question nobody could ever answer.
    private var openQueryWarrant: QueryWarrant?

    /// Every question this world actually delivered, in order — the numerator of every query
    /// metric and the thing `repeatQueryCount` is counted over.
    public private(set) var deliveredQueries: [AskedQuestionKey] = []
    /// The subject of every delivered question, in the same order, for the ground-truth join.
    public private(set) var deliveredQuerySubjects: [String] = []
    /// Deliveries whose key was already in the ledger. **A defect's gate is zero** (R-94).
    public private(set) var repeatQueries = 0
    /// Questions asked about a subject the app had already been told about decisively.
    public private(set) var queriesOnDecidable = 0
    /// Questions produced from an uncertainty R-77 marks unaskable. Unreachable by construction —
    /// `QueryableUncertainty` has three cases and `UncertaintyReason.queryable` is the only route
    /// into it — and counted anyway, because an invariant nobody counts is an invariant nobody
    /// notices losing.
    public private(set) var queriesOnUnaskable = 0
    /// Mandates the nudge lane was handed. The numerator of `accusationFalsePositiveRate` is a
    /// subset of these.
    public private(set) var mandatesSeen = 0
    /// Accusations produced from an `uncertain` verdict. Structurally impossible (R-76's four
    /// facts); asserted as a number as well as a type.
    public private(set) var accusationsFromQuery = 0
    /// Rungs delivered above the ambient one whose predecessor was **not** a delivered rung one
    /// rank below. R-81, as arithmetic rather than as a promise.
    public private(set) var escalationsFromDeferred = 0
    /// Delivered accusation rungs, in order, for the day-level counts.
    public private(set) var deliveredAccusations = 0

    public init(enforcesFatigue: Bool) {
        self.enforcesFatigue = enforcesFatigue
    }

    // MARK: - Deciding

    /// **Decide once**, through the shipping decider and nothing else.
    ///
    /// - Parameters:
    ///   - judgement: what the engine concluded, as the nudge sees it.
    ///   - surroundings: what the world was doing.
    ///   - preferences: the person's deck and their notification authorisation.
    ///   - priorityID: the ledger's priority half. `nil` means there is no priority, and gate 1
    ///     will have suppressed the interruption anyway.
    ///   - decidable: what the app already held about this subject, for `queryOnDecidableCount`.
    @discardableResult
    public mutating func decide(
        _ judgement: NudgeJudgement,
        surroundings: NudgeSurroundings,
        preferences: NudgePreferences = NudgePreferences(),
        priorityID: UUID?,
        decidable: DecidableSubjects
    ) -> NudgeObservation {
        let subject = NudgeDecider.querySubject(for: judgement)
        let key = priorityID.flatMap { id in
            subject.map {
                AskedQuestionKey(priorityID: id, subjectKind: $0.kind, subject: $0.identifier)
            }
        }

        activePriorityID = priorityID

        let memory = NudgeMemory(
            slot: slot,
            budget: enforcesFatigue ? budget : .empty,
            fatigue: enforcesFatigue ? fatigue : .fresh,
            snoozes: snoozes,
            correctedSubjects: correctedSubjects,
            // Gate 11 reads the **immutable receipt**, never the rule — which is the whole of
            // R-78 and the reason deleting a learned rule does not re-open the question.
            hasAsked: key.map { ledger.contains($0) } ?? false,
            ladder: ladder
        )

        if judgement.eligibility.mandate != nil { mandatesSeen += 1 }

        let decision = NudgeDecider.decide(
            judgement,
            surroundings: surroundings,
            memory: memory,
            preferences: preferences
        )

        if judgement.verdict == .uncertain, decision.rung != nil { accusationsFromQuery += 1 }

        record(
            decision,
            judgement: judgement,
            key: key,
            decidable: decidable,
            now: surroundings.monotonic
        )
        return NudgeObservation(decision: decision, key: key)
    }

    // MARK: - Recording what happened

    private mutating func record(
        _ decision: NudgeDecision,
        judgement: NudgeJudgement,
        key: AskedQuestionKey?,
        decidable: DecidableSubjects,
        now: Duration
    ) {
        switch decision {
        case .accuse(let rung, let route):
            recordAccusation(rung: rung, route: route, now: now)
        case .ask(let warrant, let route):
            recordQuery(
                warrant: warrant,
                route: route,
                key: key,
                uncertainty: judgement.uncertainty,
                decidable: decidable,
                now: now
            )
        case .silent(let silence):
            counters.record(
                InterventionEvent(
                    kind: judgement.eligibility.mandate == nil ? .query : .accusation,
                    subject: judgement.subject ?? "",
                    disposition: .suppressed,
                    suppressionReason: silence.reason
                )
            )
        case .deferred(let reason):
            counters.record(
                InterventionEvent(
                    kind: judgement.eligibility.mandate == nil ? .query : .accusation,
                    subject: judgement.subject ?? "",
                    disposition: .deferred,
                    deferralReason: reason
                )
            )
        }
    }

    /// Fold a delivered or deferred accusation rung into the ladder, the budget and the counters.
    ///
    /// **Only a delivery spends anything.** A deferral advances no rung, starts no escalation
    /// clock and costs no unit (R-81), and the ladder is told `.delivery(.deferred(_:))` rather
    /// than simply not told — the machine's own empty branch is what makes the invariant
    /// arithmetic instead of a check somebody has to remember.
    private mutating func recordAccusation(
        rung: LadderRung,
        route: SurfaceRoute,
        now: Duration
    ) {
        // Where the ladder stood before this rung, so an escalation that followed a rung nobody
        // saw is countable rather than merely impossible.
        let standing = ladder.state.rung?.kind.rank

        ladder.reduce(.mandate(rung.mandate), now: now)
        ladder.offer(at: now, budgetPermits: true)

        // Switched over the **route**, which has exactly two cases, rather than over the delivery
        // it becomes, which has three. `SurfaceRoute.delivery` is the one sanctioned bridge and it
        // never produces `.suppressed` — a suppression is decided by the stack, before a route is
        // asked for — so an exhaustive switch there would carry a branch no run can reach.
        switch route {
        case .surface(let surface):
            if rung.kind.rank > 0, standing != rung.kind.rank - 1 { escalationsFromDeferred += 1 }
            ladder.reduce(.delivery(route.delivery), now: now)
            accusationsToday += 1
            interruptionsToday += 1
            fatigue = FatigueController.reduce(fatigue, event: .delivered(.accusation), now: now)
            // **Only a surface with something to press occupies the slot** (focus-k42, U-2), the
            // same rule `NudgeHost` applies. A glyph or a badge is a delivery and not an
            // occupation: nothing can take an ambient rung down, so a glyph that held the slot
            // would withhold every question for the rest of the replayed day.
            if surface.offersACorrection {
                slot = InterruptionSlot(holder: .accusation(rung))
            }
            deliveredAccusations += 1
            counters.record(
                InterventionEvent(
                    kind: .accusation,
                    rung: rung.kind,
                    subject: rung.subject ?? "",
                    surface: surface,
                    disposition: .delivered
                )
            )

        case .unavailable(let reason):
            ladder.reduce(.delivery(route.delivery), now: now)
            counters.record(
                InterventionEvent(
                    kind: .accusation,
                    rung: rung.kind,
                    subject: rung.subject ?? "",
                    disposition: .deferred,
                    deferralReason: reason
                )
            )
        }
    }

    private mutating func recordQuery(
        warrant: QueryWarrant,
        route: SurfaceRoute,
        key: AskedQuestionKey?,
        uncertainty: UncertaintyReason?,
        decidable: DecidableSubjects,
        now: Duration
    ) {
        if uncertainty?.queryable == nil { queriesOnUnaskable += 1 }
        if decidable.decides(warrant.subject.identifier, uncertainty: uncertainty) {
            queriesOnDecidable += 1
        }

        switch route {
        case .surface(let surface):
            if let key {
                if ledger.contains(key) { repeatQueries += 1 }
                deliveredQueries.append(key)
                ledger.insert(key)
                openQueryKey = key
            }
            deliveredQuerySubjects.append(warrant.subject.identifier)
            if let priorityID = activePriorityID {
                queriesByPriority[priorityID, default: 0] += 1
            }
            queriesAllPrioritiesToday += 1
            interruptionsToday += 1
            fatigue = FatigueController.reduce(fatigue, event: .delivered(.query), now: now)
            // **The same rule the accusation branch above applies, applied to the question**
            // (focus-k42, U-2). A question on the badge is an invitation behind a click: it is a
            // delivery and not an occupation, and a badge that held the slot would withhold every
            // accusation for the rest of the replayed day — which is precisely the shape the host
            // was carrying. Identity is `openQueryWarrant`, kept unconditionally just below.
            openQueryWarrant = warrant
            if surface.offersACorrection {
                slot = InterruptionSlot(holder: .query(warrant))
            }
            counters.record(
                InterventionEvent(
                    kind: .query,
                    subject: warrant.subject.identifier,
                    surface: surface,
                    disposition: .delivered,
                    queryReason: warrant.reason
                )
            )

        case .unavailable(let reason):
            counters.record(
                InterventionEvent(
                    kind: .query,
                    subject: warrant.subject.identifier,
                    disposition: .deferred,
                    deferralReason: reason,
                    queryReason: warrant.reason
                )
            )
        }
    }

    // MARK: - What the person did

    /// Resolve the question currently on screen.
    ///
    /// "Yes, add it" takes the subject out of the accusable set entirely — a correction suppresses
    /// harder than an ignore, which is U-1's whole thesis: implicit derivation, improved by one
    /// click, is what buys silence (R-83).
    public mutating func resolveQuery(_ answer: QueryAnswer, now: Duration) {
        guard let warrant = openQueryWarrant else { return }
        slot = slot.released()
        openQueryKey = nil
        openQueryWarrant = nil
        fatigue = FatigueController.reduce(
            fatigue, event: .queryResolved(answer.outcome), now: now
        )
        if answer == .yesAddIt { correctedSubjects.insert(warrant.subject.identifier) }
        counters.record(
            InterventionEvent(
                kind: .query,
                subject: warrant.subject.identifier,
                disposition: .delivered,
                outcome: answer.interventionOutcome,
                queryReason: warrant.reason,
                originatingAnswer: answer
            )
        )
    }

    /// Resolve the accusation rung currently on screen.
    ///
    /// Anything the person actually **did** — a correction, a snooze, a pause, a return, a
    /// priority change — de-escalates the ladder totally and immediately (R-80). A dismissal and
    /// an ignore do not: they extend the run that `ignoredAccusationBackoff` counts, and at two
    /// the ladder drops back to the ambient rung and holds there for the rest of the session.
    ///
    /// **The rung comes from the ladder, not from the slot** (focus-k42, U-2). This opened
    /// `guard let rung = slot.openAccusation else { return }`, which was the same conflation of
    /// *which rung this is* with *whether the screen is occupied* that the host was carrying: once
    /// a glyph stopped holding the interruption slot, resolving an ambient rung became a silent
    /// no-op — no de-escalation, no ignore counted, no row written. R-80's "de-escalation is total
    /// and re-entry is at the bottom" then failed on the commonest rung there is, because the
    /// ladder was never told the person had answered.
    public mutating func resolveAccusation(_ outcome: InterventionOutcome, now: Duration) {
        guard let rung = ladder.state.rung else { return }
        slot = slot.released()
        fatigue = FatigueController.reduce(
            fatigue, event: .accusationResolved(outcome), now: now
        )
        if outcome.isUnanswered {
            ladder.reduce(.rungIgnored, now: now)
        } else {
            ladder.reduce(.deEscalated(Self.deEscalation(for: outcome)), now: now)
        }
        if outcome == .corrected, let subject = rung.subject {
            correctedSubjects.insert(subject)
        }
        if outcome == .snoozed, let subject = rung.subject, let span = InterventionPolicy.snoozeDurations.first {
            snoozes = snoozes.adding(SnoozeState(subject: subject, until: now + span))
        }
        counters.record(
            InterventionEvent(
                kind: .accusation,
                rung: rung.kind,
                subject: rung.subject ?? "",
                disposition: .delivered,
                outcome: outcome
            )
        )
    }

    /// De-escalate for a reason that was not an answer to a rung — a phase change, a return, a
    /// priority change.
    public mutating func deEscalate(_ cause: LadderDeEscalation = .phaseLeftFocus, now: Duration) {
        ladder.reduce(.deEscalated(cause), now: now)
        slot = slot.released()
        openQueryKey = nil
        openQueryWarrant = nil
    }

    /// Which de-escalation an outcome is. Total over `InterventionOutcome`, so an outcome added
    /// later cannot silently become "some other kind of ending".
    static func deEscalation(for outcome: InterventionOutcome) -> LadderDeEscalation {
        switch outcome {
        case .corrected: .corrected
        case .snoozed: .snoozed
        case .returned: .returnedToTask
        case .pausedSession: .paused
        case .priorityChanged: .priorityChanged
        case .answered: .corrected
        case .dismissed, .ignored: .phaseLeftFocus
        }
    }

    /// **A relaunch.** The day's caps and every receipt survive; every session-lived thing does
    /// not (R-79, R-83).
    ///
    /// This is criterion 28 as a fixture step: a cap a person could clear by quitting is not a
    /// cap, and a backoff that survived a relaunch would be a backoff that outlived the situation
    /// it was for.
    public mutating func relaunch() {
        fatigue = .fresh
        ladder = LadderMachine()
        slot = .open
        openQueryKey = nil
        openQueryWarrant = nil
        snoozes = .none
        correctedSubjects = []
    }

    /// **The corpus's own step**: the next case is a different person on a different afternoon,
    /// and the only thing that carries between them is what was **asked**.
    ///
    /// The 165 committed cases are a set of independent claims, not one person's day — several of
    /// them are deliberately the same situation one second apart. Carrying a live interruption
    /// slot, a ladder or a cooldown between them would make every case after the first depend on
    /// the one before it, which is exactly what a golden corpus must not do. The ledger carries,
    /// because never-ask-twice is a property of the *subject and the priority* rather than of a
    /// session, and it is what `repeatQueryCount` and `queryVolumeRate` are measured over.
    public mutating func beginIndependentObservation() {
        slot = .open
        openQueryKey = nil
        openQueryWarrant = nil
        ladder = LadderMachine()
        fatigue = .fresh
        snoozes = .none
        correctedSubjects = []
    }

    /// **Forget every receipt.**
    ///
    /// Used only by the corpus's independent pass, where each case is its own claim and the
    /// question one case asks must not silence the next. It is deliberately *not* on the path any
    /// fixture or any host can reach: in the app a receipt is immutable and dies only with its
    /// priority (R-78, F-115/F-116), and a method that emptied the ledger for any other reason
    /// would be the one call that could re-open a question somebody has already answered.
    public mutating func forgetReceipts() {
        ledger = []
    }

    /// A new local day. Every count is read from stored rows by `localDayKey`, so a day boundary
    /// in the **user's own calendar** empties the budget and nothing else — the receipts stay,
    /// because a question answered yesterday is still answered.
    public mutating func startNewDay() {
        queriesByPriority = [:]
        queriesAllPrioritiesToday = 0
        accusationsToday = 0
        interruptionsToday = 0
    }

    /// A new priority. Every question legitimately re-opens, because a new commitment makes old
    /// answers irrelevant — and the ledger key carries the priority, so nothing has to be deleted
    /// for that to be true.
    public mutating func changePriority(now: Duration) {
        deEscalate(.priorityChanged, now: now)
        correctedSubjects = []
        snoozes = .none
    }
}

extension QueryAnswer {
    /// The outcome a delivered question's record carries once it has been answered.
    ///
    /// "Not now" is `dismissed` rather than an answer of its own: the receipt records that the
    /// asking happened, and the counters record that nobody answered it — which is exactly what
    /// `ignoredQueryBackoff` counts.
    var interventionOutcome: InterventionOutcome {
        switch self {
        case .yesAddIt, .no: .answered
        case .notNow: .dismissed
        }
    }
}
