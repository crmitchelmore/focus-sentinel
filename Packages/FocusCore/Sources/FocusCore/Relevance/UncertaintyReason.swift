import Foundation

/// Why the engine declined to decide.
///
/// `uncertain` is the app's most important answer and it must never be a shrug: every route
/// to it is named, counted in `evaluation.json`'s `byUncertaintyReason`, and rendered through
/// a typed explanation clause. A reason that cannot be named is a route nobody can audit.
///
/// Each case names the adversarial family (R-68) it is the mechanism for, so a fixture that
/// asserts `uncertain` asserts it *for a reason* rather than by coincidence.
public enum UncertaintyReason: String, Sendable, CaseIterable, Codable, Hashable {
    /// The priority carries too few content tokens to be judged at all — *"stuff"*, *"work"*,
    /// *"catch up"*, the empty priority. Family 8, and condition 1 of the negative basis.
    case insufficientPriorityEvidence
    /// There is nothing to write a rule *about*: the activation carried no bundle identifier
    /// (e03's P-83 measured six unbundled processes in ninety-two). Family 7.
    case noIdentifiableSubject
    /// Neither side of the comparison is English at or above the language-confidence floor,
    /// and `NLEmbedding` is `nil` for every other language on this OS (P-111). Family 4.
    case languageNotSupported
    /// Two rules at the same authority *and* the same subject kind disagree. Never resolved
    /// by recency and never resolved to `unrelated`. Family 9.
    case conflictingRules
    /// A bundled `askEachTime` default: a browser, a chat client, a media player — an
    /// application about which nothing general is evidence about *this* priority. Family 1.
    case mixedUseApplication
    /// **R-56.1.** The priority names no application or site the engine could find this one
    /// absent from, so the absence is an absence of *instrument* rather than of relevance.
    /// Family 11 — the family that guards the false accusation rather than the false decline.
    case noNegativeBasis
    /// The snapshot was built against a different priority revision than the evidence was
    /// captured for, so every judgement about the old wording is stale. Family 10.
    ///
    /// A distinct reason rather than folding into `noEvidence`: "I have evidence but it is
    /// about a sentence you have since rewritten" and "I have no evidence" are different
    /// facts, and a metric that could not tell them apart would hide a cache bug.
    case staleSnapshot
    /// Nothing was observed at all — a private-browsing window with no origin and no title, an
    /// activation e03's sensitivity gate suppressed before the engine saw it. Families 5 and 6.
    ///
    /// **"We did not look" must never become "you are distracted."** That inversion would turn
    /// a privacy feature into an accusation, which is the one failure this whole epic exists to
    /// prevent.
    case noEvidence
}

/// Why the app is staying silent.
///
/// A first-class answer, because a surface that can say *why* it said nothing is a surface a
/// person can trust. Every case is a rung of `InterventionEligibility.decide(…)`'s guard
/// sequence, in the order that function evaluates them (R-55), and each has its own String
/// Catalog key — a lint asserts the bijection (R-70m).
public enum SuppressionReason: String, Sendable, CaseIterable, Codable, Hashable {
    /// Nothing to say: the context supports the priority.
    case verdictRelevant
    /// **Standing condition 6**, and the only route an `uncertain` verdict has. Whatever the
    /// band, the dwell, the rung or the phase.
    case verdictUncertain
    /// `.low` never mandates (R-56), which is what stops the similarity signal nudging alone.
    case evidenceBandTooLow
    /// Drift has not been sustained past the effective threshold (R-60).
    case withinGracePeriod
    /// The engine already said this about this subject recently (R-60).
    case withinMandateCooldown
    /// The session is on a break, a deliberate detour, paused, interrupted or complete —
    /// e03's `SessionPhase.permitsIntervention` is `.focus` alone.
    case sessionPhaseForbids
    /// `FocusStatus.permitsIntervention` is `unrelated` alone.
    case statusForbids
    /// The person is away from the keyboard, by the longer silence either of e03's two idle
    /// sources can testify to (focus-7az).
    case userIdle
    /// There is nothing to be off-task *from*.
    case noActivePriority

    /// The String Catalog key for the sentence a surface draws when it stayed silent.
    public var copyKey: String {
        switch self {
        case .verdictRelevant: "suppression.reason.verdictRelevant"
        case .verdictUncertain: "suppression.reason.verdictUncertain"
        case .evidenceBandTooLow: "suppression.reason.evidenceBandTooLow"
        case .withinGracePeriod: "suppression.reason.withinGracePeriod"
        case .withinMandateCooldown: "suppression.reason.withinMandateCooldown"
        case .sessionPhaseForbids: "suppression.reason.sessionPhaseForbids"
        case .statusForbids: "suppression.reason.statusForbids"
        case .userIdle: "suppression.reason.userIdle"
        case .noActivePriority: "suppression.reason.noActivePriority"
        }
    }

    public var copyResource: LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(copyKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }
}
