import FocusRules
import Foundation

/// What the classifier is asked to judge.
///
/// Everything here is already **normalised evidence**, never raw captured content: a bundle
/// identifier, a `scheme://host` origin with no path and no query, and a small set of
/// lowercased title tokens. Nothing in this type can carry a document's contents, a URL's
/// query string or a screenshot, and that is deliberate — it is the type-level half of the
/// privacy guarantee.
public struct ClassificationInput: Sendable, Equatable, Hashable, Codable {
    /// The user's stated priority, as they wrote it. Empty when no priority is set.
    public var priorityIntent: String
    /// The user's own "done when" phrasing, if they gave one.
    public var priorityDoneWhen: String?
    /// Bundle identifier of the frontmost application, if known.
    public var bundleIdentifier: String?
    /// A normalised web origin (`scheme://host`) — never a full URL.
    public var origin: String?
    /// Lowercased tokens drawn from the window or tab title.
    public var titleTokens: [String]

    public init(
        priorityIntent: String = "",
        priorityDoneWhen: String? = nil,
        bundleIdentifier: String? = nil,
        origin: String? = nil,
        titleTokens: [String] = []
    ) {
        self.priorityIntent = priorityIntent
        self.priorityDoneWhen = priorityDoneWhen
        self.bundleIdentifier = bundleIdentifier
        self.origin = origin
        self.titleTokens = titleTokens
    }

    /// An input carrying no evidence at all. Classifying it must yield `.uncertain`.
    public static let empty = ClassificationInput()

    /// True when there is nothing at all to reason about.
    public var isEmpty: Bool {
        priorityIntent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && bundleIdentifier == nil
            && origin == nil
            && titleTokens.isEmpty
    }
}

/// The classifier's conclusion.
///
/// `uncertain` is a first-class case and is **intervention-suppressing**: when the answer
/// is `uncertain` the app does not nudge, does not warn and does not escalate. This is
/// standing condition 6, encoded at the type level from day one so that no later epic can
/// quietly treat "I don't know" as "you are off task". Every consumer must handle it
/// explicitly; there is deliberately no default and no `Bool` projection that would let a
/// call site collapse three cases into two.
public enum Verdict: String, Sendable, CaseIterable, Codable, Hashable {
    /// The observed context supports the current priority.
    case relevant
    /// The observed context does not support the current priority.
    case unrelated
    /// There is not enough evidence to say. **Suppresses intervention.**
    case uncertain

    /// Whether a verdict permits the app to interrupt the user.
    ///
    /// Only `unrelated` does. `relevant` has no reason to, and `uncertain` is forbidden to.
    public var permitsIntervention: Bool {
        switch self {
        case .unrelated: true
        case .relevant, .uncertain: false
        }
    }
}

/// Where a verdict came from. Recorded so that a later epic can tell a user-authored rule
/// from an inference, and so the verdict cache can be invalidated by source.
public enum VerdictSource: String, Sendable, CaseIterable, Codable, Hashable {
    /// A rule the user wrote.
    case userRule
    /// A deterministic heuristic.
    case heuristic
    /// The on-device language model (arrives in e06).
    case onDeviceModel
    /// No source could decide.
    case undecided
}

/// A verdict plus the reasoning trail a later epic needs.
public struct ClassificationOutcome: Sendable, Equatable, Hashable, Codable {
    public var verdict: Verdict
    public var source: VerdictSource
    /// 0…1. Never used to escalate an `uncertain` verdict into an intervention.
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

/// The classification seam.
///
/// e04 supplies the deterministic rule/heuristic engine and e06 the on-device model behind
/// this same protocol. Nothing above this seam ever learns which one answered, except
/// through `ClassificationOutcome.source`.
public protocol RelevanceClassifier: Sendable {
    func classify(_ input: ClassificationInput) -> ClassificationOutcome
}

/// The classifier e01 ships: it has no rule engine and no model, so it declines to decide.
///
/// This is not a stub standing in for a real implementation — it is the honest answer for a
/// build that has no evidence source yet, and it is the behaviour every later engine must
/// fall back to. Because `uncertain` suppresses intervention, an app running on this
/// classifier is guaranteed never to nudge, which is exactly the right failure mode.
public struct UndecidedClassifier: RelevanceClassifier {
    public init() {}

    public func classify(_ input: ClassificationInput) -> ClassificationOutcome {
        _ = input
        return .undecided
    }
}

extension RuleVerdict {
    /// The verdict a stored user rule implies. A user's explicit `uncertain` stays
    /// `uncertain` — declining to decide is preserved, never upgraded.
    public var classificationVerdict: Verdict {
        switch self {
        case .relevant: .relevant
        case .unrelated: .unrelated
        case .uncertain: .uncertain
        }
    }
}
