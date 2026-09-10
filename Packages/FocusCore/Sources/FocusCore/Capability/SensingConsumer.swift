import Foundation

/// Which part of the app is asking. Ten of them, named once here.
///
/// A capability on its own is not enough to decide anything: "the microphone signal is
/// unavailable" means one thing to the suppression rule that wanted it and something else
/// entirely to the analytics that merely counted it. The fallback table is indexed by *both*,
/// which is what makes it an artefact a test can prove total rather than a sentence.
public enum SensingConsumer: String, Sendable, CaseIterable, Codable, Hashable {
    /// The event stream's record of what was frontmost when.
    case activationTimeline
    /// How long the user stayed with each application.
    case dwellAttribution
    /// F-34's promise that work on a secondary display is not judged as drift.
    case displayFairness
    /// F-35's rule that the app stands down during a presentation.
    case presentationSuppression
    /// F-36's rule that a running microphone stands the app down.
    case mediaSuppression
    /// Pausing the session when the screen locks or the Mac sleeps.
    case lifecyclePause
    /// Pausing the session when the person is not at the keyboard.
    case idlePause
    /// e04's relevance engine.
    case classification
    /// e05's escalation ladder.
    case nudgeLadder
    /// The local, on-device summaries the user can look at.
    case analytics

    /// Which tier of the charter's promises this consumer serves.
    ///
    /// It exists for one assertion, and the assertion is the charter's own tenet: **no T1
    /// consumer's fallback for a `.denied` capability may be `.featureAbsent`.** A tier-1
    /// promise that evaporates when a permission is refused was never a tier-1 promise; it was
    /// a tier-1 promise *conditional on a grant*, which is the thing this programme exists not
    /// to ship.
    public var tier: ConsumerTier {
        switch self {
        case .activationTimeline, .dwellAttribution, .lifecyclePause, .idlePause,
             .classification, .nudgeLadder:
            .t1
        case .displayFairness, .presentationSuppression, .mediaSuppression:
            .t2
        case .analytics:
            .t3
        }
    }
}

/// How central a consumer is to what the app promises.
public enum ConsumerTier: String, Sendable, CaseIterable, Codable, Hashable {
    /// The product does not work without it.
    case t1
    /// It makes the product good.
    case t2
    /// It is a nicety.
    case t3
}
