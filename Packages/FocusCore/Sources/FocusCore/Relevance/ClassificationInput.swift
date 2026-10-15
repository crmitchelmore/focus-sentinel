import Foundation

/// What the classifier is asked to judge.
///
/// Everything here is already **normalised evidence**, never raw captured content: a bundle
/// identifier, a `scheme://host` origin with no path and no query, and a small set of
/// lowercased title tokens. Nothing in this type can carry a document's contents, a URL's
/// query string or a screenshot, and that is deliberate — it is the type-level half of the
/// privacy guarantee.
///
/// `origin` is **plumbed and exercised by the golden corpus, and empty in every shipping code
/// path** (F-03 is baseline-only). `selectedItem` is the one window-derived field a shipping
/// path fills (issue #24), and it is a `SelectedItem` — a label already reduced by
/// `SelectedItem.normalise`, never a raw title. `titleTokens` is filled from that label and from
/// nothing else (issue #27), so it too is empty unless the person switched the Accessibility ask
/// on.
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
    /// The item selected inside a mixed-use application, already reduced to a label
    /// (`SelectedItem`, issue #24). `nil` unless the person switched the Accessibility ask on,
    /// the grant is held, and the frontmost window names an item.
    public var selectedItem: SelectedItem?

    public init(
        priorityIntent: String = "",
        priorityDoneWhen: String? = nil,
        bundleIdentifier: String? = nil,
        origin: String? = nil,
        titleTokens: [String] = [],
        selectedItem: SelectedItem? = nil
    ) {
        self.priorityIntent = priorityIntent
        self.priorityDoneWhen = priorityDoneWhen
        self.bundleIdentifier = bundleIdentifier
        self.origin = origin
        self.titleTokens = titleTokens
        self.selectedItem = selectedItem
    }

    /// An input carrying no evidence at all. Classifying it must yield `.uncertain`.
    public static let empty = ClassificationInput()

    /// True when there is nothing at all to reason about.
    public var isEmpty: Bool {
        priorityIntent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && bundleIdentifier == nil
            && origin == nil
            && titleTokens.isEmpty
            && selectedItem == nil
    }
}
