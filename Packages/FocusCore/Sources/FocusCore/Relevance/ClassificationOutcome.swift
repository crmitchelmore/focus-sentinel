import Foundation

/// A verdict plus the reasoning trail a later epic needs.
///
/// Relocated from `FocusClassify` unchanged in e04 (R-53). It gains an evidence band in T80;
/// this file's job in T78 is to be the same type in a new place, so that if the move breaks
/// something the diff says only "these types moved".
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

    public init(verdict: Verdict, source: VerdictSource, confidence: Double) {
        self.verdict = verdict
        self.source = source
        self.confidence = min(max(confidence, 0), 1)
    }

    /// The failing-closed outcome: no evidence, no decision, no intervention.
    public static let undecided = ClassificationOutcome(
        verdict: .uncertain,
        source: .undecided,
        confidence: 0
    )
}
