import Foundation

/// A verdict plus the reasoning trail a later epic needs.
///
/// Relocated from `FocusClassify` unchanged in e04 (R-53), then given the one thing the
/// intervention path is allowed to read: an ordinal `band`.
///
/// Two measures of strength travel on this value and exactly one of them is consulted when
/// the app decides whether to interrupt somebody. That asymmetry is the point (R-56):
/// `confidence` is a `Double` and cannot be, `band` is ordinal and is.
public struct ClassificationOutcome: Sendable, Equatable, Hashable, Codable {
    public var verdict: Verdict
    public var source: VerdictSource
    /// 0…1. Never used to escalate an `uncertain` verdict into an intervention.
    ///
    /// It survives for the seam's shape and for e06's model self-report, and it is
    /// **explicitly not consulted** by the one function that authorises an interruption
    /// (R-56). A number that could rescue a declined verdict is the collapse this programme
    /// exists to prevent.
    public var confidence: Double
    /// How much the engine had to go on, ordinally. **This** is what
    /// `InterventionEligibility.decide(…)` reads, and it must be at or above
    /// `RelevancePolicy.interventionBandFloor` before anything can interrupt.
    public var band: EvidenceBand

    /// `band` defaults to `.low` — the band that can never mandate — so that a caller who
    /// forgets it fails safe rather than failing loud. Every producer in the engine sets it
    /// explicitly from the committed band table.
    public init(
        verdict: Verdict,
        source: VerdictSource,
        confidence: Double,
        band: EvidenceBand = .low
    ) {
        self.verdict = verdict
        self.source = source
        self.confidence = min(max(confidence, 0), 1)
        self.band = band
    }

    /// The failing-closed outcome: no evidence, no decision, no intervention.
    public static let undecided = ClassificationOutcome(
        verdict: .uncertain,
        source: .undecided,
        confidence: 0,
        band: .low
    )
}
