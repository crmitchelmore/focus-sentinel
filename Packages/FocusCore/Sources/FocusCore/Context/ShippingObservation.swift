import Foundation

/// What the shipping app can actually observe, named once (focus-6ji4).
///
/// The vocabulary is wider than the observation. `PriorityRuleScope.domain` and
/// `ContextItemKind.domain` are live in the engine — `RuleCascade` compares them against
/// `evidence.origin` — but nothing in the shipping graph supplies an origin:
/// `RelevanceHost` judges with `ClassificationInput(bundleIdentifier:)` alone. A site rule or a
/// site chip therefore can never match, and offering to make one is a control wired to nothing.
///
/// This is not a retirement. `PriorityRuleScope.titleToken` is retired because the product
/// gave the idea up; a site is still in scope (PD-1 keeps the normalised origin) and is waiting
/// on an origin producer. So the authoring surfaces read *this* fact rather than `isRetired`,
/// the engine keeps reading stored rows as it always has, and the day an origin producer ships
/// is one line here.
public enum ShippingObservation {
    /// Whether anything in the shipping app reads which site a browser is showing.
    public static let readsBrowserSite = false
}

extension PriorityRuleScope {
    /// Whether the shipping app can observe this scope's subject, so a rule of it can match.
    public var isObserved: Bool {
        switch self {
        case .app, .session: true
        case .domain: ShippingObservation.readsBrowserSite
        case .titleToken: false
        }
    }
}

extension ContextItemKind {
    /// Whether the shipping app can observe this kind, so a context item of it does something.
    ///
    /// A file is `true` although the engine cannot see which file is open: a file item is
    /// opened when a session starts, which is a thing it does. A site is neither matched nor
    /// opened in this version.
    public var isObserved: Bool {
        switch self {
        case .app, .keyword, .file: true
        case .domain: ShippingObservation.readsBrowserSite
        case .unknown: false
        }
    }
}
