import Foundation

/// What became of one thing the app said.
///
/// Four, and the two in the middle are the two different ways of not reaching somebody. R-81's is
/// **deferred**: a rung nobody could see, which does not advance the ladder, does not spend either
/// cap and does not start the escalation clock — counted in its own column so the number is
/// *visible* rather than inferred. `deferredRungShare` is reported and ungated: a rising one means
/// the presentation gate is over-firing, which is a signal for e08.
///
/// **`unopened` is the other one, and it was missing** (focus-sq7). A nudge routed to the popover
/// badge reaches a surface and then waits behind a click. If nobody makes that click it was
/// correctly not delivered — nobody saw it — and it was also not deferred, because it was not
/// refused a surface: it reached one and waited. With no case for it, such a nudge wrote **no row
/// at all**, and a day on which the app raised its top rung and nobody ever looked was
/// indistinguishable in the record from a day on which the ladder never left the glyph. That
/// absence is exactly what would have revealed focus-2xw in the wild — nothing in the menu bar was
/// inviting the click — and it is the signal a maintainer needs to see it come back.
public enum InterventionDisposition: String, Sendable, CaseIterable, Codable, Hashable {
    /// It reached a surface a person could see.
    case delivered
    /// The surface exists but could not be seen now.
    case deferred
    /// **It reached a surface and waited behind a click nobody made** (focus-sq7).
    ///
    /// The badge, for both kinds of nudge. Not `deferred`: `DeferralReason.noSurfaceAvailable`
    /// would be a false statement about a surface the nudge did reach, and
    /// `NudgeHostSlotOwnershipTests` reads `deferredCount` as a proxy for *"the route offered
    /// nothing"* — writing this as a deferral would corrupt that reading as well as the record.
    ///
    /// It spends nothing. `spendsBudget` is `disposition == .delivered` and stays that way: an
    /// invitation nobody opened is an attempt, not an interruption, and charging for one is the
    /// whole of focus-xix.
    case unopened
    /// The app chose not to speak (R-84).
    case suppressed
}

/// What the person did about it.
///
/// **There is no causal field here and there is nowhere to put one.** Per the Court's downgrade
/// of F-107, e05 ships counters and nothing else: no "effectiveness" score, no claim that an
/// intervention *helped*, and — per D-01 — no streak and no score to defend. The counters exist
/// because R-83's controller needs them and R-94's gate reads them; e09 renders them.
///
/// What the app is allowed to record beside these is the verdict transition that immediately
/// followed, as a fact rather than as a conclusion.
public enum InterventionOutcome: String, Sendable, CaseIterable, Codable, Hashable {
    /// Escape, or the close button. Writes nothing, and that is allowed (D-07).
    case dismissed
    /// "This is relevant" — a durable task-authority rule. **Suppresses harder than an
    /// ignore**, because it removes the subject from the accusable set entirely.
    case corrected
    /// Snoozed for one of `InterventionPolicy.snoozeDurations`.
    case snoozed
    /// One click back to the stored work application.
    case returned
    /// The session was paused through e03's own machine.
    case pausedSession
    /// e02's confirm surface was opened and a new priority was set.
    case priorityChanged
    /// A question was answered — which one is in `originatingAnswer`.
    case answered
    /// Nothing happened at all. Counted, because
    /// `InterventionPolicy.ignoredQueryBackoff` and `ignoredAccusationBackoff` are what stop
    /// the app talking to itself.
    case ignored

    /// Whether this outcome ends the ladder (R-80). Only a dismissal and an ignore do not: the
    /// person closed a window or did nothing, and neither is them telling the app anything.
    public var deEscalates: Bool {
        switch self {
        case .corrected, .snoozed, .returned, .pausedSession, .priorityChanged, .answered: true
        case .dismissed, .ignored: false
        }
    }

    /// Whether this outcome counts towards a backoff.
    public var isUnanswered: Bool {
        switch self {
        case .dismissed, .ignored: true
        case .corrected, .snoozed, .returned, .pausedSession, .priorityChanged, .answered: false
        }
    }
}

/// **One thing the app said**, as a value.
///
/// The shape `InterventionRecord` persists (R-79) and the shape `InterventionCounters`
/// aggregates. It is deliberately a record of what the **app** did, kept apart from e04's
/// `ActivityEventStore`, which records what the *person and the machine* did: mixing them would
/// make F-115's retention policy delete the app's own accountability alongside the
/// observations, and would make the daily-cap predicate a scan over the largest table in the
/// store.
public struct InterventionEvent: Sendable, Equatable, Hashable {
    public let kind: InterruptionKind
    /// The rung, for an accusation. `nil` for a question, which has no ladder.
    public let rung: LadderRung.Kind?
    /// The subject it was about. Empty only for a mixed accusation, which names nobody.
    public let subject: String
    /// The surface that took it. `nil` when it was deferred or suppressed and reached none.
    public let surface: NudgeSurface?
    public let disposition: InterventionDisposition
    /// What the person did. `nil` while it is still on screen.
    public let outcome: InterventionOutcome?
    /// Why it could not be seen, for a deferral.
    public let deferralReason: DeferralReason?
    /// Why the app stayed quiet, for a suppression.
    public let suppressionReason: NudgeSuppressionReason?
    /// Which answerable uncertainty produced it, for a question.
    public let queryReason: QueryableUncertainty?
    /// Which click wrote the rule this record's verdict rests on, when one did.
    ///
    /// The field that keeps R-78's distinction visible in the data: a later `unrelated` verdict
    /// sourced from a rule the person wrote by answering "No" is a *user-authored* verdict, not
    /// a query that escalated, and the Rules pane and the judgment inspector can both show them
    /// exactly what their click did.
    public let originatingAnswer: QueryAnswer?

    public init(
        kind: InterruptionKind,
        rung: LadderRung.Kind? = nil,
        subject: String,
        surface: NudgeSurface? = nil,
        disposition: InterventionDisposition,
        outcome: InterventionOutcome? = nil,
        deferralReason: DeferralReason? = nil,
        suppressionReason: NudgeSuppressionReason? = nil,
        queryReason: QueryableUncertainty? = nil,
        originatingAnswer: QueryAnswer? = nil
    ) {
        self.kind = kind
        self.rung = rung
        self.subject = subject
        self.surface = surface
        self.disposition = disposition
        self.outcome = outcome
        self.deferralReason = deferralReason
        self.suppressionReason = suppressionReason
        self.queryReason = queryReason
        self.originatingAnswer = originatingAnswer
    }

    /// Whether this event spends a cap. **Only a delivery does** (R-81, R-83).
    public var spendsBudget: Bool { disposition == .delivered }

    /// **Whether this event spends one of the day's six ACCUSATIONS** (focus-ndh, R-83).
    ///
    /// Not the same question as `spendsBudget`, and the difference is one rung. Both kinds cost
    /// the person an interruption — *"a person asked ten questions has been interrupted ten
    /// times"* — so `dailyInterruptionCap` is spent by everything delivered and this changes
    /// none of that. `dailyAccusationCap` is a cap on **accusations**, and the ambient rung makes
    /// none: `LadderRung.Kind.ambient.makesAnAccusation` is `false` by the ladder's own
    /// derivation, `NudgeSurface.menuBar.offersAnAnswer` is `false` because there is nothing on a
    /// glyph to answer, and R-87 keeps it on through a snooze precisely because it is a *state*
    /// and not a sentence.
    ///
    /// Measured before this line existed: seven drifts seven hundred seconds apart produced six
    /// ambient rows, `accusationsToday` 6 of 6, the query budget squeezed from four remaining to
    /// one, and decision 7 `silent(budgetExhausted)`. The panel rung — the only rung that carries
    /// a sentence, a subject and the whole correction economy — could not be raised for the rest
    /// of that day and was never raised at all. R-80's escalation story was unreachable on any
    /// day that drifts more than six times, which is an ordinary day.
    ///
    /// Said in the vocabulary the ladder already has rather than in a new one: the row keeps
    /// `kind == .accusation` and keeps its `rung` column, so the ambient rung stays visible in
    /// the record (focus-sq7) and the Intervention pane goes on drawing it. What changed is which
    /// cap the sum lands in.
    ///
    /// A row with **no** rung named is not a ladder rung at all — a notification response, an
    /// older row — and an accusation-kind row that names no rung is charged as one, because
    /// silently exempting it would be a way to spend nothing by writing nothing down.
    public var spendsTheAccusationCap: Bool {
        guard spendsBudget, kind == .accusation else { return false }
        return rung?.makesAnAccusation ?? true
    }
}

/// **Counters, and nothing else** (R-93, F-107).
///
/// Per kind, per rung, per surface, per disposition, per outcome, per query reason, per
/// suppression reason, per deferral reason. Every one of them is a count of something the app
/// did; not one of them is a judgement about the person, and there is no field in which such a
/// judgement could be stored.
public struct InterventionCounters: Sendable, Equatable, Hashable {
    public private(set) var byKind: [InterruptionKind: Int]
    /// Deliveries alone, per kind — what the daily caps read. Kept apart from `byKind` because
    /// a deferred rung is counted (so the share is visible) and spends nothing (R-81), and one
    /// dictionary could not say both.
    public private(set) var deliveredByKind: [InterruptionKind: Int]
    public private(set) var byRung: [LadderRung.Kind: Int]
    public private(set) var bySurface: [NudgeSurface: Int]
    public private(set) var byDisposition: [InterventionDisposition: Int]
    public private(set) var byOutcome: [InterventionOutcome: Int]
    public private(set) var byQueryReason: [QueryableUncertainty: Int]
    public private(set) var bySuppressionReason: [NudgeSuppressionReason: Int]
    public private(set) var byDeferralReason: [DeferralReason: Int]

    public init() {
        byKind = [:]
        deliveredByKind = [:]
        byRung = [:]
        bySurface = [:]
        byDisposition = [:]
        byOutcome = [:]
        byQueryReason = [:]
        bySuppressionReason = [:]
        byDeferralReason = [:]
    }

    public static let empty = InterventionCounters()

    /// Count one event. Every column it belongs in, and no column it does not.
    public mutating func record(_ event: InterventionEvent) {
        byKind[event.kind, default: 0] += 1
        byDisposition[event.disposition, default: 0] += 1
        if event.spendsBudget { deliveredByKind[event.kind, default: 0] += 1 }
        if let rung = event.rung { byRung[rung, default: 0] += 1 }
        if let surface = event.surface { bySurface[surface, default: 0] += 1 }
        if let outcome = event.outcome { byOutcome[outcome, default: 0] += 1 }
        if let reason = event.queryReason { byQueryReason[reason, default: 0] += 1 }
        if let reason = event.suppressionReason {
            bySuppressionReason[reason, default: 0] += 1
        }
        if let reason = event.deferralReason { byDeferralReason[reason, default: 0] += 1 }
    }

    /// The counters with one more event in them.
    public func recording(_ event: InterventionEvent) -> InterventionCounters {
        var copy = self
        copy.record(event)
        return copy
    }

    /// Every event counted, whatever became of it.
    public var total: Int { byDisposition.values.reduce(0, +) }

    /// Events of one disposition.
    public func count(_ disposition: InterventionDisposition) -> Int {
        byDisposition[disposition] ?? 0
    }

    /// Interruptions that actually reached somebody. The only ones that spend a cap.
    public var delivered: Int { count(.delivered) }

    /// Two counter sets added together.
    ///
    /// The evaluation lane reads three lanes — the corpus, the sequences and the realistic days —
    /// and reports one distribution over all of them. Adding the values is what makes that one
    /// number rather than three a reader has to add up by hand.
    public func merging(_ other: InterventionCounters) -> InterventionCounters {
        var merged = self
        merged.byKind.merge(other.byKind, uniquingKeysWith: +)
        merged.deliveredByKind.merge(other.deliveredByKind, uniquingKeysWith: +)
        merged.byRung.merge(other.byRung, uniquingKeysWith: +)
        merged.bySurface.merge(other.bySurface, uniquingKeysWith: +)
        merged.byDisposition.merge(other.byDisposition, uniquingKeysWith: +)
        merged.byOutcome.merge(other.byOutcome, uniquingKeysWith: +)
        merged.byQueryReason.merge(other.byQueryReason, uniquingKeysWith: +)
        merged.bySuppressionReason.merge(other.bySuppressionReason, uniquingKeysWith: +)
        merged.byDeferralReason.merge(other.byDeferralReason, uniquingKeysWith: +)
        return merged
    }

    /// **Reported, ungated.** A rising share means the presentation gate is over-firing.
    /// `.zero` when nothing has been said, rather than a division by nothing.
    public var deferredRungShare: Double {
        let all = total
        guard all > 0 else { return 0 }
        return Double(count(.deferred)) / Double(all)
    }

    /// Deliveries of one kind — what the daily caps read.
    public func delivered(_ kind: InterruptionKind) -> Int { deliveredByKind[kind] ?? 0 }

    /// Everything counted of one kind, whatever became of it.
    public func count(_ kind: InterruptionKind) -> Int { byKind[kind] ?? 0 }
}
