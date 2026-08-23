import Foundation

/// What the classifier is asked to judge.
///
/// Everything here is already **normalised evidence**, never raw captured content: a bundle
/// identifier, a `scheme://host` origin with no path and no query, and a small set of
/// lowercased title tokens. Nothing in this type can carry a document's contents, a URL's
/// query string or a screenshot, and that is deliberate — it is the type-level half of the
/// privacy guarantee.
///
/// `origin` and `titleTokens` are **plumbed and exercised by the golden corpus, and empty in
/// every shipping code path in e04** (F-03 is baseline-only). e07 turns them on by supplying a
/// capability probe and a reader; nothing in this type changes when it does.
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
