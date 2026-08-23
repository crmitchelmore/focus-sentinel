import Foundation

/// What a relevance rule is *about* — the vocabulary the cockpit's rules pane offers.
///
/// The raw values are the strings `FocusSchemaV3.RelevanceRule.scopeRaw` stores, which are
/// also `FocusRules.RuleScope`'s raw values. The vocabulary is declared **here**, in the
/// package both sides depend on, for a boundary reason: `FocusUI` may not import `FocusRules`
/// (R-14), and a rules pane that cannot name a scope is a pane that cannot author a rule.
/// `PriorityStore` already writes rules as raw strings for exactly the same reason.
///
/// `FocusRulesTests` asserts the two vocabularies are the same set of strings, so they cannot
/// drift apart silently.
public enum PriorityRuleScope: String, Sendable, CaseIterable, Hashable, Identifiable {
    /// A whole application, identified by bundle identifier.
    case app
    /// A web origin, normalised to `scheme://host[:port]` — never a full URL (SC-3).
    case domain
    /// A single token drawn from a window or tab title.
    case titleToken
    /// A rule that lasts only until this priority is completed.
    case session

    public var id: String { rawValue }

    /// The SF Symbol the rules pane draws beside a rule of this scope. Distinct silhouettes,
    /// for the same reason the context chips have them: under "Differentiate without colour"
    /// the shape is what tells one row from another.
    public var symbolName: String {
        switch self {
        case .app: "app.badge"
        case .domain: "globe"
        case .titleToken: "text.magnifyingglass"
        case .session: "hourglass"
        }
    }
}

/// What the user asserted about a subject.
///
/// A stored human judgement, deliberately distinct from a classifier's runtime guess. Raw
/// values match `FocusRules.RuleVerdict`.
public enum PriorityRuleVerdict: String, Sendable, CaseIterable, Hashable, Identifiable {
    /// The subject supports the current priority.
    case relevant
    /// The subject does not support it.
    case unrelated
    /// The user explicitly declined to decide. Never treated as `unrelated`.
    case uncertain

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .relevant: "checkmark.circle"
        case .unrelated: "minus.circle"
        case .uncertain: "questionmark.circle"
        }
    }
}

/// One rule, as the cockpit draws it.
///
/// The persistent representation is `FocusSchemaV3.RelevanceRule`; this is the value the
/// cockpit renders and `PriorityActing` names, so `FocusUI` never touches a `@Model` class.
public struct PriorityRuleValue: Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public var scope: PriorityRuleScope
    /// The normalised subject: a bundle identifier, an origin, or a lowercased token.
    public var subject: String
    public var verdict: PriorityRuleVerdict
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        scope: PriorityRuleScope,
        subject: String,
        verdict: PriorityRuleVerdict,
        createdAt: Date
    ) {
        self.id = id
        self.scope = scope
        self.subject = subject
        self.verdict = verdict
        self.createdAt = createdAt
    }

    /// Project a stored row.
    ///
    /// Fails — rather than guessing — when the stored scope or verdict is a string this build
    /// does not know. A rule written by a later version is then *not shown* in the pane, which
    /// is honest; it is never rewritten and never deleted, so it survives the round trip.
    public init?(_ rule: FocusSchemaV3.RelevanceRule) {
        guard let scope = PriorityRuleScope(rawValue: rule.scopeRaw),
              let verdict = PriorityRuleVerdict(rawValue: rule.verdictRaw)
        else { return nil }
        self.init(
            id: rule.id,
            scope: scope,
            subject: rule.subject,
            verdict: verdict,
            createdAt: rule.createdAt
        )
    }
}
