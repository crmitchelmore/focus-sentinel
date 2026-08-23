import Foundation

/// Authorisation to interrupt a person.
///
/// There is no public initialiser, no internal one, and no memberwise one outside this file:
/// the memberwise initialiser is `fileprivate`, and this file contains exactly one function
/// that calls it. A lint asserts `InterventionMandate(` appears in exactly one source file in
/// the shipping graph (R-70b), so *moving* the producer is a deliberate, reviewed act rather
/// than a quiet one.
///
/// Every surface that can interrupt — e05's ladder, the notch companion, the notification rung
/// — takes one of these. Not a `Verdict`, not a `ClassificationOutcome`, not a `Bool`.
/// **An uncertain verdict therefore cannot reach an intervention, because no value carrying
/// one can be turned into a parameter such a surface accepts.** That is the guarantee; the
/// 4 320-combination cross-product in `InterventionInvariantTests` is a check on the
/// guarantee, not the guarantee itself (R-55, standing condition 6).
public struct InterventionMandate: Sendable, Equatable, Hashable {
    /// The bundle identifier or normalised origin the drift is about.
    ///
    /// Empty **only** when `isMixed` is true: drift that accumulated across several subjects
    /// has no single one to name, and inventing one would be the app misnaming what somebody
    /// was doing. A surface must read `isMixed` first.
    public let subject: String
    /// True when drift accumulated across several unrelated subjects, so a surface says
    /// "several unrelated apps" rather than misnaming one of them.
    public let isMixed: Bool
    public let band: EvidenceBand
    public let stage: CascadeStage
    /// How long drift has been sustained, monotonic.
    public let sustainedFor: Duration
    public let explanation: Explanation
    public let stamp: EngineStamp

    fileprivate init(
        subject: String,
        isMixed: Bool,
        band: EvidenceBand,
        stage: CascadeStage,
        sustainedFor: Duration,
        explanation: Explanation,
        stamp: EngineStamp
    ) {
        self.subject = subject
        self.isMixed = isMixed
        self.band = band
        self.stage = stage
        self.sustainedFor = sustainedFor
        self.explanation = explanation
        self.stamp = stamp
    }
}

/// Whether the app may interrupt, and if not, why not.
///
/// The `.suppressed` case is as much a first-class answer as the other one: a surface that can
/// say *why* it stayed silent is a surface a person can trust, and e05 receives
/// `SuppressionReason` for exactly that.
public enum InterventionEligibility: Sendable, Equatable, Hashable {
    case mandated(InterventionMandate)
    case suppressed(SuppressionReason)

    /// The mandate, when there is one. `nil` is the commonest and safest answer.
    public var mandate: InterventionMandate? {
        switch self {
        case .mandated(let mandate): mandate
        case .suppressed: nil
        }
    }

    /// Why the app stayed silent, when it did.
    public var suppressionReason: SuppressionReason? {
        switch self {
        case .mandated: nil
        case .suppressed(let reason): reason
        }
    }

    public var isMandated: Bool { mandate != nil }

    /// **The one and only route from a judgement to an authorisation.**
    ///
    /// Note the shape of the `switch` below: `.relevant` and `.uncertain` return *before any
    /// other input is read*. There is no code path in which a band, a dwell, a rung or a
    /// session phase can rescue them, because the function has already returned. That is what
    /// standing condition 6 means as a fact about the code rather than as a promise about it.
    ///
    /// The remaining guards are conjunctive and ordered, and the order is part of the
    /// contract: the reason a surface is told is the *first* reason that applied, which is the
    /// one a person would give. `ClassificationOutcome.confidence` is not read here at all.
    public static func decide(
        outcome: ClassificationOutcome,
        drift: DriftState,
        phase: SessionPhase,
        status: FocusStatus,
        isUserIdle: Bool,
        hasActivePriority: Bool,
        explanation: Explanation,
        stamp: EngineStamp
    ) -> InterventionEligibility {
        switch outcome.verdict {
        case .relevant: return .suppressed(.verdictRelevant)
        case .uncertain: return .suppressed(.verdictUncertain)
        case .unrelated: break
        }

        guard hasActivePriority else { return .suppressed(.noActivePriority) }
        guard !isUserIdle else { return .suppressed(.userIdle) }
        guard phase.permitsIntervention else { return .suppressed(.sessionPhaseForbids) }
        guard status.permitsIntervention else { return .suppressed(.statusForbids) }
        guard outcome.band >= RelevancePolicy.interventionBandFloor else {
            return .suppressed(.evidenceBandTooLow)
        }

        switch drift {
        case .aligned, .grace:
            return .suppressed(.withinGracePeriod)
        case .cooldown:
            return .suppressed(.withinMandateCooldown)
        case .sustained(let subject, let accumulated, let isMixed):
            return .mandated(
                InterventionMandate(
                    subject: subject.identifier ?? "",
                    isMixed: isMixed || subject.isMixed,
                    band: outcome.band,
                    stage: explanation.stage,
                    sustainedFor: accumulated,
                    explanation: explanation,
                    stamp: stamp
                )
            )
        }
    }
}
