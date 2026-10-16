import Foundation

/// What the shipping app can actually observe, named once (focus-6ji4).
///
/// The opt-in Accessibility reader now supplies the active browser page and its origin.
/// Site rules and chips can therefore match when that reading is enabled and available.
public enum ShippingObservation {
    /// Whether anything in the shipping app reads which site a browser is showing.
    public static let readsBrowserSite = true
}

extension PriorityRuleScope {
    /// Whether the shipping app can observe this scope's subject, so a rule of it can match.
    public var isObserved: Bool {
        switch self {
        case .app, .session: true
        case .domain: ShippingObservation.readsBrowserSite
        // An item-form title-token row (issue #24) is matched against the selected item the
        // Accessibility reader produces; a word-shaped one is retired, which
        // `PriorityRuleValue.isRetired` — not this — answers.
        case .titleToken: true
        }
    }
}

extension ContextItemKind {
    /// Whether the shipping app can observe this kind, so a context item of it does something.
    ///
    /// A file is `true` although the engine cannot see which file is open: a file item is
    /// opened when a session starts, which is a thing it does. A site is neither matched nor
    /// opened automatically; it is matched against the observed browser origin.
    public var isObserved: Bool {
        switch self {
        case .app, .keyword, .file: true
        case .domain: ShippingObservation.readsBrowserSite
        case .unknown: false
        }
    }
}
