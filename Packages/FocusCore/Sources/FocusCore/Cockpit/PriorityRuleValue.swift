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
    /// A single token drawn from a window or tab title. **Retired** (e07a, PD-1): nothing in
    /// the shipping app produces a title token — the one shipping producer passes application
    /// identity only, and under PD-1 the AX-title depth dial is parked with a named blocker — so a
    /// rule of this scope is a promise the product does not keep. The case stays so a stored row
    /// still decodes; `isRetired` is what the rules pane and the snapshot builder read.
    ///
    /// **Except a selected item** (issue #24): a subject in `SelectedItem`'s `<bundle>::<label>`
    /// form is read again, through Accessibility and only with the person's opt-in, so a row in
    /// that form is live: `PriorityRuleValue.isRetired` is `false` for it.
    case titleToken
    /// A rule that lasts only until this priority is completed.
    case session

    public var id: String { rawValue }

    /// **Whether this scope is one the app no longer reads** (e07a).
    ///
    /// A retired scope is decodable, drawable and deletable, and nothing else: the rules pane
    /// withdraws it from the authoring vocabulary and draws a stored row read-only with the
    /// words *no longer read*, and `RuleSnapshotBuilder` skips and counts the row rather than
    /// promoting it to a rung it could never match. Deleting the case instead would make a
    /// stored row undecodable, which is a row silently dropped — the thing `ContextItemKind
    /// .unknown` exists to prevent on the other side of the same pane.
    public var isRetired: Bool {
        switch self {
        case .titleToken: true
        case .app, .domain, .session: false
        }
    }

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
    /// **Whether this row is one the app no longer reads** (e07a, narrowed by issue #24).
    ///
    /// The scope alone used to answer this. Since the Accessibility reader landed, a
    /// `.titleToken` row naming a `SelectedItem` (`<bundle>::<label>`) is live — the cascade
    /// matches it — and only the word-shaped legacy row is retired. Read this, not
    /// `scope.isRetired`, wherever a stored row is drawn or copied.
    public var isRetired: Bool {
        scope.isRetired && !SelectedItem.isItemSubject(subject)
    }

    /// Whether this row names an item selected inside an application rather than a whole
    /// application, site or word.
    public var isSelectedItem: Bool {
        scope == .titleToken && SelectedItem.isItemSubject(subject)
    }

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
