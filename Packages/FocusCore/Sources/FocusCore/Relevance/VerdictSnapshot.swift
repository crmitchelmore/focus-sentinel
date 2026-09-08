import Foundation

/// What the app currently believes about the person's context, as a value a surface can draw.
///
/// The verdict inspector (R-71) ships as a section at the foot of the **Privacy** pane —
/// beside the capability matrix e03 put there — rather than as a hidden developer window,
/// because a surface that shows a person exactly what the app concluded about them and why is
/// a *trust* surface and belongs where the other ones are.
///
/// `FocusUI` renders this without importing `FocusClassify`, which is only possible because
/// the whole vocabulary moved to `FocusCore` in T78 (R-53). It shows the status glyph and
/// label, the rung that decided, the band, the drift clock counting, the explanation clauses,
/// the suppression reason when suppressed, and the stamp key.
///
/// It shows **no number** from the similarity signal — `ExplanationClause` has no case that
/// could carry one — and **no raw evidence**, which is structurally impossible rather than
/// merely forbidden (R-57).
public struct VerdictSnapshot: Sendable, Equatable, Hashable {
    /// The five-case surface vocabulary, already carrying a glyph, a shape and a label.
    public let status: FocusStatus
    /// Which rung decided.
    public let stage: CascadeStage
    /// How much it had to go on. `nil` when the classification verdict is `uncertain`:
    /// declining to decide has no evidence to band. A paused/onBreak surface status overrides
    /// the classification label, but preserves its band (or its absence).
    public let band: EvidenceBand?
    /// Where the drift accumulator has got to. Drawn as a counting clock.
    public let drift: DriftState
    /// Whether the app may interrupt, and if not, why not.
    public let eligibility: InterventionEligibility
    /// Why it concluded what it concluded.
    public let explanation: Explanation
    /// Which engine said so — `EngineStamp.cacheKey`, so the pane and the evidence agree.
    public let stampKey: String

    public init(
        status: FocusStatus,
        stage: CascadeStage,
        band: EvidenceBand?,
        drift: DriftState,
        eligibility: InterventionEligibility,
        explanation: Explanation,
        stampKey: String
    ) {
        self.status = status
        self.stage = stage
        self.band = band
        self.drift = drift
        self.eligibility = eligibility
        self.explanation = explanation
        self.stampKey = stampKey
    }

    /// The rung that decided, with its copy — what the inspector's "decided by" row draws.
    public var rung: CascadeRung? { CascadePrecedence.rung(for: stage) }

    /// Whether the app is currently authorised to interrupt.
    ///
    /// Reported by the inspector **and acted on by e05's ladder**, off the same value. The
    /// inspector's sentence for this branch denied that for a whole epic (focus-lmy), so the
    /// two surfaces are worth naming together wherever this property is: it is not a debug
    /// readout of something inert.
    public var isMandated: Bool { eligibility.isMandated }
}
