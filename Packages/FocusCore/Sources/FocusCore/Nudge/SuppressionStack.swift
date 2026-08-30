import Foundation

/// Which kind of interruption is being considered.
///
/// Two kinds, and they are different in kind and identical in cost to the person — which is
/// exactly why they keep separate caps *and* draw on one shared budget (R-83). Declared here,
/// with the stack, because **gate 11 of R-84 is kind-dependent**: never-ask-twice applies to a
/// question and an accusation passes straight through it, so the stack cannot be evaluated
/// without knowing which is being asked for.
public enum InterruptionKind: String, Sendable, CaseIterable, Codable, Hashable {
    /// "Is *{subject}* part of *{task}*?" — U-1's affordance, whose cheapest answer teaches the
    /// app. Cheap, but still an interruption: a person asked ten questions has been interrupted
    /// ten times.
    case query
    /// "Still working on *{task}*?" — the two-rung ladder, reserved for `unrelated`.
    case accusation
}

/// Every reason the app has for staying quiet, **in the order R-84 evaluates them**.
///
/// The order is part of the contract, not a presentation choice: the reason a surface is told
/// is the *first* reason that applied, which is the one a person would give. "I said nothing
/// because you have no priority set" and "I said nothing because I had already asked you about
/// this" are both true of the same moment, and only one of them is the answer.
///
/// Twelve cases. Gate 11 — `alreadyAsked` — is the one adversarial review added (finding 3):
/// never-ask-twice is an explicit, ordered, **named** suppression consulted before a warrant is
/// constructed, not an emergent property of the cascade that a rule deletion could dissolve. It
/// reads the immutable receipt, never the rule.
public enum NudgeSuppressionReason: String, Sendable, CaseIterable, Codable, Hashable {
    /// Gate 1 (e04). There is nothing to be off-task *from*.
    case noActivePriority
    /// Gate 2 (e03, F-119). The one global pause switch is on, or sensing is off. A pause is
    /// not a boolean handlers consult — it detaches every observer — and nothing downstream of
    /// it can speak.
    case sensingPaused
    /// Gate 3 (e03, F-118). A sensitive application is frontmost.
    ///
    /// **The subject is never named in any record**, because e03's gate suppressed the
    /// activation before the engine ever saw it. That is also why `noEvidence` is unaskable:
    /// "we did not look" must never become "tell us what you were doing."
    case sensitiveApplication
    /// Gate 4 (e03, F-99). The session is on a break, a deliberate detour, paused, interrupted
    /// or complete. `SessionPhase.permitsIntervention` is `.focus` alone.
    case sessionPhaseForbids
    /// Gate 5 (e03, F-32). No hardware input for longer than the user's idle threshold.
    case userIdle
    /// Gate 6 (e03, F-36). A microphone or camera is running: the person is on a call, and a
    /// panel over a call is a panel everybody else can see.
    case mediaInUse
    /// Gate 7 (e03, F-35). A presentation or full-screen space is up.
    ///
    /// For the panel and for a question this is a **suppression**. For the silent ambient rung
    /// it is a **deferral** instead (R-81): the menu bar is hidden, so the rung is undeliverable
    /// rather than unwanted, and an undeliverable rung must not advance the ladder or spend a
    /// cap. `SuppressionStack.evaluate(…)` returns `.deferred` for exactly that cell.
    case presentationActive
    /// Gate 8 (e05, R-85). The person's own quiet hours. Not the system Focus, which this app
    /// makes no claim to read (P-137).
    case quietHours
    /// Gate 9 (e05, U-2). One open interruption at a time, **symmetrically**: whatever is
    /// already on screen keeps the slot, and whatever arrives second waits. The gate below is
    /// `guard !interruptionInFlight` for both kinds, with no arm that reads `kind`.
    ///
    /// It used to say that a mandate offered against an open query closed the query as
    /// `declined` and took the slot, and that the reverse never happened. That asymmetry was
    /// preemption, U-2 deleted it, and roughly eleven defects across seven repair rounds had
    /// lived in it. An accusation withheld here is **not lost**: no delivery is recorded and the
    /// escalation clock does not start, so the same rung is offered again on the next judgement.
    case interruptionInFlight
    /// Gate 10 (e05, R-83). A cap, a cooldown or a backoff. Queries and accusations keep
    /// separate caps *and* draw on one shared daily budget whose last unit is reserved for an
    /// accusation.
    case budgetExhausted
    /// Gate 11 (e05, R-78). **Queries only.** The immutable receipt says this exact question
    /// was already asked for this priority — and it stays true after the rule that answer wrote
    /// has been deleted, because removing a learned chip means "that is not a fact about my
    /// work", never "ask me again".
    case alreadyAsked
    /// Gate 12 (e04 R-55 / e05 R-76). The verdict itself does not authorise this kind of
    /// interruption. The one gate whose detail lives in a type rather than in this enum:
    /// `InterventionEligibility.decide(…)` for an accusation, `QueryEligibility.decide(…)` for
    /// a question, each returning *before* it reads anything else.
    case verdictDoesNotAuthorise

    /// Where this gate sits in R-84's stack, counting from one — derived from `allCases`, so
    /// the declaration order *is* the evaluation order and no numeric literal appears (R-96j).
    public var gateNumber: Int {
        (Self.allCases.firstIndex(of: self) ?? Self.allCases.count) + 1
    }

    /// Whether this gate applies to both kinds of interruption or to questions alone.
    public var appliesTo: Set<InterruptionKind> {
        self == .alreadyAsked ? [.query] : [.query, .accusation]
    }

    /// The String Catalog key for the sentence a surface draws when it stayed quiet.
    /// `check-strings.sh` asserts the bijection with `nudge.suppressed.*` (R-96l).
    public var copyKey: String {
        switch self {
        case .noActivePriority: "nudge.suppressed.noActivePriority"
        case .sensingPaused: "nudge.suppressed.sensingPaused"
        case .sensitiveApplication: "nudge.suppressed.sensitiveApplication"
        case .sessionPhaseForbids: "nudge.suppressed.sessionPhaseForbids"
        case .userIdle: "nudge.suppressed.userIdle"
        case .mediaInUse: "nudge.suppressed.mediaInUse"
        case .presentationActive: "nudge.suppressed.presentationActive"
        case .quietHours: "nudge.suppressed.quietHours"
        case .interruptionInFlight: "nudge.suppressed.interruptionInFlight"
        case .budgetExhausted: "nudge.suppressed.budgetExhausted"
        case .alreadyAsked: "nudge.suppressed.alreadyAsked"
        case .verdictDoesNotAuthorise: "nudge.suppressed.verdictDoesNotAuthorise"
        }
    }

    public var copyResource: LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(copyKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }
}

/// What the stack concluded.
///
/// Three answers rather than an optional reason, because R-81 needs the middle one: a rung
/// nobody could see is **deferred**, not suppressed, and the difference decides whether the
/// ladder advances and whether a cap is spent. An `Optional<NudgeSuppressionReason>` would have
/// collapsed the two, and the collapse is invisible at a call site.
public enum SuppressionOutcome: Sendable, Equatable, Hashable {
    /// Every gate cleared. The app may speak.
    case permitted
    /// The app chose not to speak, and this is the **first** reason that applied.
    case suppressed(NudgeSuppressionReason)
    /// The app would have spoken and could not be seen. Does not advance the ladder, does not
    /// spend a cap, does not start the escalation clock.
    case deferred(DeferralReason)

    public var isPermitted: Bool { self == .permitted }

    public var suppressionReason: NudgeSuppressionReason? {
        switch self {
        case .suppressed(let reason): reason
        case .permitted, .deferred: nil
        }
    }

    public var deferralReason: DeferralReason? {
        switch self {
        case .deferred(let reason): reason
        case .permitted, .suppressed: nil
        }
    }
}

/// **The one ordered suppression stack**, and both authorisations pass through it.
///
/// Under U-1 the app speaks more, so suppression correctness matters *more*, not less. Gates
/// 1–8 are shipped code from e01–e04 and this function **wires** them: it consumes
/// `SensitiveScreenDecision`, `SessionPhase`, `IdleReading`, `MediaActivity` and
/// `PresentationState` as values produced by the packages that own them, and re-implements
/// none of them. `SuppressionStackTests` asserts each of gates 3–7 is reached through its
/// existing type rather than through a copy, and `check-boundaries.sh` proves on the object
/// that this module could not have gone and fetched them itself (R-96k).
public enum SuppressionStack {
    /// Evaluate the twelve gates in order and return the first answer that is not "permitted".
    ///
    /// - Parameters:
    ///   - kind: which interruption is being considered. Gate 11 is kind-dependent and nothing
    ///     else is.
    ///   - rung: the accusation rung being considered, or `nil` for a question. Read by gate 7
    ///     alone: the silent ambient rung is **deferred** under a presentation rather than
    ///     suppressed, because the menu bar is hidden and the rung is undeliverable rather than
    ///     unwanted (R-81, P-131).
    ///   - hasActivePriority: gate 1.
    ///   - sensingPaused: gate 2 — `AppSettingsRecord.sensingPaused`, F-119's one switch.
    ///   - sensitivity: gate 3 — e03's `SensitivityGate.evaluate(_:)` answer, already made.
    ///   - phase: gate 4 — e03's `SessionPhase`, read through `permitsIntervention`.
    ///   - idle: gate 5 — e03's `IdleReading`, read through `isIdle(threshold:)`.
    ///   - idleThresholdSeconds: the user's own threshold, from settings.
    ///   - media: gate 6 — e03's `MediaActivity`, read through `suppressesIntervention`.
    ///   - mediaSuppressionEnabled: the user's own switch. Off means a running microphone does
    ///     not suppress; the reading is still taken, it is simply not acted on.
    ///   - presentation: gate 7 — e03's `PresentationState`, read through `suppressesOverlays`.
    ///   - quietHours: gate 8 — e05's own window, default off.
    ///   - now: the wall clock, from an injected `DateProvider`. Quiet hours are the only gate
    ///     that reads it.
    ///   - calendar: the user's calendar, injected. Never `Calendar.current`.
    ///   - interruptionInFlight: gate 9.
    ///   - budgetPermits: gate 10 — the caps, the cooldown and the backoff, already computed.
    ///   - hasAsked: gate 11 — the **immutable receipt**, never the rule. Ignored entirely for
    ///     an accusation.
    ///   - verdictAuthorises: gate 12 — whether the kind's own eligibility produced an
    ///     authorisation. `InterventionEligibility` for an accusation, `QueryEligibility` for a
    ///     question; this function never inspects a verdict itself.
    public static func evaluate(
        kind: InterruptionKind,
        rung: LadderRung.Kind?,
        hasActivePriority: Bool,
        sensingPaused: Bool,
        sensitivity: SensitiveScreenDecision,
        phase: SessionPhase,
        idle: IdleReading,
        idleThresholdSeconds: Double,
        media: MediaActivity,
        mediaSuppressionEnabled: Bool,
        presentation: PresentationState,
        quietHours: QuietHours,
        now: Date,
        calendar: Calendar,
        interruptionInFlight: Bool,
        budgetPermits: Bool,
        hasAsked: Bool,
        verdictAuthorises: Bool
    ) -> SuppressionOutcome {
        // 1 — no active priority (e04).
        guard hasActivePriority else { return .suppressed(.noActivePriority) }

        // 2 — the global pause switch (e03, F-119).
        guard !sensingPaused else { return .suppressed(.sensingPaused) }

        // 3 — a sensitive application (e03, F-118). Read through e03's own decision type, so
        // the subject is never named here — the activation was suppressed before the engine
        // saw it, and this function never learns what it was.
        guard sensitivity.clearedActivation != nil else {
            return .suppressed(.sensitiveApplication)
        }

        // 4 — the session phase (e03, F-99). `.focus` alone.
        guard phase.permitsIntervention else { return .suppressed(.sessionPhaseForbids) }

        // 5 — the person is away (e03, F-32), by the hardware idle source and their threshold.
        guard !idle.isIdle(threshold: idleThresholdSeconds) else {
            return .suppressed(.userIdle)
        }

        // 6 — a microphone or camera is running (e03, F-36), if the user left that switch on.
        if mediaSuppressionEnabled, media.suppressesIntervention {
            return .suppressed(.mediaInUse)
        }

        // 7 — a presentation (e03, F-35). The one gate whose answer depends on the rung: the
        // silent ambient rung is DEFERRED, because the menu bar is hidden and nobody could have
        // seen it (P-131) — an undeliverable rung is not a delivered rung (R-81).
        if presentation.suppressesOverlays {
            if kind == .accusation, rung == .ambient {
                return .deferred(.menuBarHidden)
            }
            return .suppressed(.presentationActive)
        }

        // 8 — quiet hours (e05, R-85). Both kinds. Default off.
        guard !quietHours.isQuiet(at: now, calendar: calendar) else {
            return .suppressed(.quietHours)
        }

        // 9 — one open interruption at a time, symmetrically (e05, U-2). No arm reads `kind`:
        // whatever is on screen keeps the slot and whatever arrives second waits.
        guard !interruptionInFlight else { return .suppressed(.interruptionInFlight) }

        // 10 — the caps, the cooldown and the backoff (e05, R-83).
        guard budgetPermits else { return .suppressed(.budgetExhausted) }

        // 11 — never twice (e05, R-78). Queries only; an accusation passes straight through.
        if kind == .query, hasAsked { return .suppressed(.alreadyAsked) }

        // 12 — the verdict gate (e04 R-55 / e05 R-76).
        guard verdictAuthorises else { return .suppressed(.verdictDoesNotAuthorise) }

        return .permitted
    }
}
