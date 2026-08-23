import Foundation

/// **Who** said it, and how long it lasts. The outer precedence axis.
///
/// Ranks match `CascadeStage.sessionRule` / `.taskRule` / `.globalRule`, and
/// `CascadePrecedenceTests` asserts that correspondence rather than restating it.
///
/// ## Where each authority comes from, and when it dies (R-72.2)
///
/// | authority | produced from | lives until |
/// |---|---|---|
/// | `.global` | `FocusSchemaV3.RelevanceRule`, `task == nil` | the user deletes it |
/// | `.task` | the same row with `task != nil` | the priority is completed or deleted |
/// | `.session` | `SessionRuleBox` — in memory, never persisted | the session ends, the priority changes, or the process exits |
///
/// The session authority is **not** the shipped `RuleScope.session` case. That case is
/// mutually exclusive with `app`/`domain`/`titleToken`, so a row carrying it has no subject
/// kind at all — nothing in the row says whether its subject is a bundle identifier, an origin
/// or a title token, and the shipped tests plant one of each. e04 therefore **skips and counts**
/// such rows rather than inferring a kind from the shape of a string (R-72.3), and owns the
/// session lifetime in memory, where a rule that outlived its session is unrepresentable rather
/// than merely unlikely. No schema change (R-72).
public enum RuleAuthority: String, Sendable, CaseIterable, Codable, Hashable, Comparable {
    /// Lives until this focus session ends. Never persisted.
    case session
    /// Scoped to the current priority.
    case task
    /// Scoped to no priority.
    case global

    /// Where this authority sits in the ladder. Lower binds harder, exactly as
    /// `CascadeStage.rank` does, and derived the same way so the two cannot drift.
    public var rank: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }

    /// The cascade rung a rule of this authority answers at.
    public var stage: CascadeStage {
        switch self {
        case .session: .sessionRule
        case .task: .taskRule
        case .global: .globalRule
        }
    }

    /// The String Catalog key for this authority's label.
    public var labelKey: String {
        switch self {
        case .session: "rule.authority.session"
        case .task: "rule.authority.task"
        case .global: "rule.authority.global"
        }
    }

    public var labelResource: LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(labelKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }

    public static func < (lhs: RuleAuthority, rhs: RuleAuthority) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// **What** it is about. The inner precedence axis, applied within one authority rung.
///
/// Exactly `RuleScope` minus `.session`, and the raw strings are the same three, so
/// `FocusRulesTests.SubjectKindParityTests` can assert
/// `RuleSubjectKind ∪ {session} == RuleScope` in both directions and the vocabularies cannot
/// drift apart.
///
/// **Narrower wins**: a `docs.google.com` rule beats a `com.apple.Safari` rule at the same
/// authority, because the user who wrote the narrower rule meant it as the exception. So a
/// *lower* rank is a *narrower* subject, in the same direction as every other rank in this
/// package.
public enum RuleSubjectKind: String, Sendable, CaseIterable, Codable, Hashable, Comparable {
    /// One document or topic. Empty in e04; e07 fills it.
    case titleToken
    /// One site — a normalised `scheme://host[:port]`.
    case domain
    /// One application, i.e. everything inside it.
    case app

    /// Narrowness order. Lower is narrower and therefore wins.
    public var rank: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }

    public static func < (lhs: RuleSubjectKind, rhs: RuleSubjectKind) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// The only rule shape the cascade consumes.
///
/// Both precedence axes are stored **on the value**, so a rule's authority is a property of
/// the rule and never of the array it happened to arrive in. That is what makes
/// `RuleSnapshot.rules` one sorted array rather than three parallel ones — three arrays would
/// encode the authority order a second time, in the order somebody wrote the fields, and
/// R-54's whole ruling is that `CascadePrecedence` is the only place a rung order is written
/// down.
///
/// `verdict` is `PriorityRuleVerdict` rather than `FocusRules.RuleVerdict` because `FocusCore`
/// may import no sibling package (the R-14 matrix). `PriorityRuleVerdict` is the mirror this
/// package already ships for exactly that reason, its raw values are `RuleVerdict`'s, and
/// `FocusRulesTests` already asserts the two vocabularies are the same set of strings.
/// The cockpit's verdict vocabulary gains `Codable` here rather than in its own file.
///
/// It is a string-raw enum, so the conformance is synthesised and encodes as exactly the raw
/// value a rule row already stores. The reason it is needed is `ScopedRuleValue` below: a
/// corpus case is a snapshot plus an input, and a snapshot that cannot be decoded from JSON is
/// a corpus that cannot be committed. Declared beside the type that needs it, so that e02's
/// cockpit vocabulary is not edited by an epic that only reads it.
extension PriorityRuleVerdict: Codable {}

public struct ScopedRuleValue: Sendable, Equatable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let authority: RuleAuthority
    public let subjectKind: RuleSubjectKind
    /// The normalised subject: a bundle identifier, a `scheme://host` origin, or a single
    /// lowercased title token, according to `subjectKind`.
    public let subject: String
    public let verdict: PriorityRuleVerdict
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        authority: RuleAuthority,
        subjectKind: RuleSubjectKind,
        subject: String,
        verdict: PriorityRuleVerdict,
        createdAt: Date
    ) {
        self.id = id
        self.authority = authority
        self.subjectKind = subjectKind
        self.subject = subject
        self.verdict = verdict
        self.createdAt = createdAt
    }

    /// The total order a `RuleSnapshot` sorts by: authority, then narrowness, then age, then
    /// identity. Total, so two builds of the same inputs are `==` and a replay is exact.
    public static func precedes(_ lhs: ScopedRuleValue, _ rhs: ScopedRuleValue) -> Bool {
        if lhs.authority != rhs.authority { return lhs.authority < rhs.authority }
        if lhs.subjectKind != rhs.subjectKind { return lhs.subjectKind < rhs.subjectKind }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
