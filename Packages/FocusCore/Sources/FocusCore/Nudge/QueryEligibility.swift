import Foundation

/// **Authorisation to ask a person one question.** The mirror image of `InterventionMandate`,
/// and deliberately not its sibling.
///
/// e04 made an accusation unconstructible from an `uncertain` verdict by giving
/// `InterventionMandate` a `fileprivate` initialiser and exactly one producer whose `switch`
/// returns before it reads anything else. U-1 adds the other half: a *question*, carried by
/// this type, produced by exactly one function, whose `switch` returns before it reads
/// anything else when the verdict is `relevant` **or** `unrelated`.
///
/// ## Why a query cannot escalate into an accusation
///
/// Four independent structural facts (R-76), each sufficient on its own:
///
/// 1. `QueryWarrant` and `InterventionMandate` share **no protocol, no supertype and no
///    conformance**, are declared in different files, and each has a `fileprivate`
///    initialiser with exactly one producer. `check-forbidden.sh` asserts that no source file
///    names both constructors (R-96b) and that no shared-authorisation protocol exists
///    (R-96d).
/// 2. This type **declares no `band` and no `stage`**. The accusation ladder requires both.
///    An adapter could not be written without inventing evidence, and inventing evidence is
///    visible in a diff.
/// 3. `LadderRung` — the accusation's unit of escalation — has exactly **one** initialiser,
///    and it takes an `InterventionMandate`. There is no overload taking a `QueryWarrant`, a
///    `Verdict` or a `Bool`, and R-96c pins the rung's construction to one file that names
///    `InterventionMandate` and does not name `QueryWarrant`.
/// 4. The ladder's escalation counter advances only on a **delivered accusation rung**
///    (R-81). A query delivery is recorded in a different type, counted in a different
///    column, and is not an input to the ladder's reducer at all.
///
/// `nudge.accusationsFromQuery == 0` asserts the same invariant as a number, so the
/// evaluation report and the type system say the same thing.
public struct QueryWarrant: Sendable, Equatable, Hashable {
    /// What the question is about. One nameable subject, never "several apps" — a mixed drift
    /// state withholds with `.noSingleSubject` rather than asking an unanswerable question.
    public let subject: QuerySubject
    /// Which of the three answerable uncertainties produced it (R-77). A `QueryableUncertainty`
    /// rather than an `UncertaintyReason`, so a warrant built from `noEvidence` is not merely
    /// forbidden — there is no value of this field that could carry it.
    public let reason: QueryableUncertainty
    /// How long the person has been with this subject, monotonic. Carried so a surface can say
    /// so and so the record is honest; it is **not** a threshold, and this type performs no
    /// comparison on it.
    public let dwelled: Duration
    /// Why the engine declined to decide. The question's own evidence trail, and — through
    /// `QuerySubject.derive(judgedSubject:explanation:)` — the reason a correction can never
    /// name a subject the judgement did not use.
    public let explanation: Explanation
    /// Which engine said so.
    public let stamp: EngineStamp

    /// **Fileprivate on purpose**, with exactly one caller, in this file. A lint asserts
    /// `QueryWarrant(` appears in exactly one source file in the shipping graph (R-96a), so
    /// moving the producer is a deliberate, reviewed act rather than a quiet one.
    fileprivate init(
        subject: QuerySubject,
        reason: QueryableUncertainty,
        dwelled: Duration,
        explanation: Explanation,
        stamp: EngineStamp
    ) {
        self.subject = subject
        self.reason = reason
        self.dwelled = dwelled
        self.explanation = explanation
        self.stamp = stamp
    }
}

/// Why the app is not asking.
///
/// A first-class answer so that a call site has to say which silence it is handling rather than
/// reading a `Bool` — and, since focus-pzl, **only** that. It used to carry twelve String Catalog
/// keys under `nudge.withheld.*`, none of which any route could draw.
///
/// They were the third English rendering of one fact. `SuppressionReason` (e04, drawn) has nine
/// cases, `NudgeSuppressionReason` (e05) has twelve, and this has twelve; eight names appear in
/// all three. A person who is not being asked a question is, by construction, being left alone —
/// there is no surface on which *"I decided not to ask you something"* is a sentence worth the
/// interruption it would itself be, and if one is ever built it should draw the vocabulary the
/// verdict inspector already draws rather than a fourth copy.
///
/// The declaration order is R-84's evaluation order, restricted to the gates this function can
/// see, with the **verdict gate lifted to the front** — see `QueryEligibility.decide(…)`.
public enum QueryWithholdingReason: String, Sendable, CaseIterable, Codable, Hashable {
    /// The app is confident this is real work. **The only thing that buys silence** under U-1.
    case verdictRelevant
    /// This is an accusation's business, not a question's. e04's `InterventionEligibility`
    /// decides what happens next; nothing here widens or narrows it.
    case verdictUnrelated
    /// There is nothing to be off-task *from*.
    case noActivePriority
    /// The person is away from the keyboard, by e03's hardware idle source.
    case userIdle
    /// The session is on a break, a deliberate detour, paused, interrupted or complete.
    case sessionPhaseForbids
    /// The surface state and the verdict disagree — a question is asked while the app is
    /// showing `uncertain`, and never while it is showing paused or on a break.
    case statusForbids
    /// A mandate already owns the one interruption slot (R-84a). "You are off task" outranks
    /// "is this part of it?", and two panels on screen is the behaviour that makes people
    /// uninstall.
    case interruptionInFlight
    /// A cap, a cooldown or a backoff says not now (R-83). A person asked ten questions has
    /// been interrupted ten times.
    case budgetExhausted
    /// **Never twice.** The immutable receipt says this exact question was already asked for
    /// this priority — whether it was answered yes, answered no, or declined, and whether or
    /// not the rule that answer wrote still exists (R-78).
    case alreadyAsked
    /// The uncertainty has no answerable question in it (R-77): `noEvidence`,
    /// `noIdentifiableSubject`, `insufficientPriorityEvidence`, `conflictingRules` or
    /// `staleSnapshot`.
    case reasonNotAskable
    /// Drift accumulated across several subjects, or the activation named none. *"Is something
    /// part of your task?"* is not a question, so it is not asked.
    case noSingleSubject
    /// The person has only just arrived. A question may come at half the dwell an accusation
    /// needs, because it is cheaper — but never instantly (R-95, `queryDwellThreshold`).
    case withinDwellGrace

}

/// Whether the app may ask, and if not, why not.
///
/// The second, **weaker** eligibility U-1 creates. It sits beside `InterventionEligibility`
/// and shares nothing with it: no protocol, no supertype, no field the other needs.
public enum QueryEligibility: Sendable, Equatable, Hashable {
    case warranted(QueryWarrant)
    case withheld(QueryWithholdingReason)

    /// The warrant, when there is one. `nil` is the commonest and safest answer.
    public var warrant: QueryWarrant? {
        switch self {
        case .warranted(let warrant): warrant
        case .withheld: nil
        }
    }

    /// Why the app stayed quiet, when it did.
    public var withholdingReason: QueryWithholdingReason? {
        switch self {
        case .warranted: nil
        case .withheld(let reason): reason
        }
    }

    public var isWarranted: Bool { warrant != nil }

    /// **The one and only route from a judgement to a question.**
    ///
    /// Note the shape of the `switch` below: `.relevant` and `.unrelated` return *before any
    /// other input is read*. There is no code path in which a band, a dwell, a reason or a
    /// ledger row can rescue them, because the function has already returned. That is the
    /// mirror image of e04's `InterventionEligibility.decide(…)`, in which `.relevant` and
    /// `.uncertain` return first, and together the two functions make U-1's posture a fact
    /// about the code rather than a promise about it: an `unrelated` verdict can no more
    /// produce a question than an `uncertain` one can produce an accusation.
    ///
    /// ## The band is never read
    ///
    /// `outcome.band` is not consulted anywhere in this function, and neither is
    /// `outcome.confidence`. An accusation needs `RelevancePolicy.interventionBandFloor`
    /// because it makes a claim about somebody; a question makes no claim at all — it says
    /// *we do not know* — so banding it would be pricing a confidence this function does not
    /// have. `QueryInvariantTests` asserts that moving the band never changes an answer.
    ///
    /// ## Why the verdict gate is first here and eleventh in `SuppressionStack`
    ///
    /// R-84's stack evaluates twelve gates in the order a person would give their reasons, and
    /// the verdict gate is the last of them. That ordering is owned by `SuppressionStack` and
    /// by the decider that runs it; every gate this function repeats is a **backstop**, so that
    /// a caller who forgot the stack still cannot produce a warrant it should not have. The one
    /// gate that may not be a backstop is the verdict, because its whole value is that it
    /// returns before anything else is read — so it is lifted to the front, and the rest follow
    /// in R-84's order.
    ///
    /// - Parameters:
    ///   - outcome: the judgement. Only `verdict` is read.
    ///   - uncertainty: which named route to `uncertain` the engine took, when it took one.
    ///     `nil` for a verdict that was decided, and for an `uncertain` verdict that arrived
    ///     without a reason — which is itself unaskable, because a question needs one.
    ///   - drift: e04's accumulator. Read for one thing only: whether the drift is `.mixed`,
    ///     in which case there is no single subject to ask about.
    ///   - dwelled: how long the person has been with this subject, monotonic. Carried onto
    ///     the warrant; never compared here.
    ///   - dwellSatisfied: whether `dwelled` has reached `InterventionPolicy.queryDwellThreshold`.
    ///     A precondition the caller evaluates, exactly as `isUserIdle` and `hasActivePriority`
    ///     are, so that every threshold in the nudge lives in one file (R-95, R-96j).
    ///   - hasAsked: the immutable receipt's answer for `(priorityID, subjectKind, subject)`.
    ///     **Read from the ledger, never from the rules store**: the rule an answer writes is
    ///     deletable by design, and an invariant U-1 states absolutely cannot rest on a record
    ///     one click removes (R-78).
    ///   - budgetPermits: whether the caps, the cooldown and the backoff allow a question now.
    ///   - interruptionInFlight: whether a mandate already owns the single interruption slot.
    ///   - judgedSubject: the bundle identifier or normalised origin the classification was
    ///     about. `nil` when the activation carried none, which is unaskable.
    ///   - explanation: the judgement's own reasoning, carried onto the warrant.
    ///   - stamp: which engine said so.
    public static func decide(
        outcome: ClassificationOutcome,
        uncertainty: UncertaintyReason?,
        drift: DriftState,
        dwelled: Duration,
        dwellSatisfied: Bool,
        phase: SessionPhase,
        status: FocusStatus,
        isUserIdle: Bool,
        hasActivePriority: Bool,
        hasAsked: Bool,
        budgetPermits: Bool,
        interruptionInFlight: Bool,
        judgedSubject: String?,
        explanation: Explanation,
        stamp: EngineStamp
    ) -> QueryEligibility {
        switch outcome.verdict {
        case .relevant: return .withheld(.verdictRelevant)
        case .unrelated: return .withheld(.verdictUnrelated)
        case .uncertain: break
        }

        guard hasActivePriority else { return .withheld(.noActivePriority) }
        guard !isUserIdle else { return .withheld(.userIdle) }
        guard phase.permitsIntervention else { return .withheld(.sessionPhaseForbids) }
        // A question is asked while the app is *showing* uncertainty. `permitsIntervention` is
        // deliberately not reused here: it is true for `unrelated` alone, which is the
        // accusation's gate and would be exactly the wrong one.
        guard status == .uncertain else { return .withheld(.statusForbids) }
        guard !interruptionInFlight else { return .withheld(.interruptionInFlight) }
        guard budgetPermits else { return .withheld(.budgetExhausted) }
        guard !hasAsked else { return .withheld(.alreadyAsked) }
        guard let reason = uncertainty?.queryable else { return .withheld(.reasonNotAskable) }
        guard !drift.isMixed else { return .withheld(.noSingleSubject) }
        guard dwellSatisfied else { return .withheld(.withinDwellGrace) }
        guard let subject = QuerySubject.derive(
            judgedSubject: judgedSubject,
            explanation: explanation
        ) else { return .withheld(.noSingleSubject) }

        return .warranted(
            QueryWarrant(
                subject: subject,
                reason: reason,
                dwelled: dwelled,
                explanation: explanation,
                stamp: stamp
            )
        )
    }
}
