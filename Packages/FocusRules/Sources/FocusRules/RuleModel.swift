import FocusCore
import Foundation

/// What a rule is *about*.
///
/// A rule always names the kind of thing it matches, so that a stored rule can never be
/// ambiguous about whether "figma" meant an application, a website or a word in a window
/// title. Raw values are strings and are persisted as strings: reordering this enum can
/// never silently reinterpret a stored row.
public enum RuleScope: String, Sendable, CaseIterable, Codable, Hashable {
    /// A whole application, identified by bundle identifier.
    case app
    /// A web origin, already normalised to scheme + host (never a full URL, never a path).
    case domain
    /// A single token drawn from a window or tab title.
    case titleToken
    /// The rule applies only for the duration of the current focus session.
    case session
}

/// What the user asserted about the subject.
///
/// This is a *stored human judgement*, deliberately distinct from a classifier's runtime
/// `Verdict`: one is evidence, the other is an inference. Keeping them as separate types
/// stops a later epic from quietly treating a guess as a user decision.
public enum RuleVerdict: String, Sendable, CaseIterable, Codable, Hashable {
    /// The subject supports the current priority.
    case relevant
    /// The subject does not support the current priority.
    case unrelated
    /// The user explicitly declined to decide. Never treated as `unrelated`.
    case uncertain
}

/// A single stored rule, as a value.
///
/// The persistent representation lives in `FocusSchemaV3.RelevanceRule`; this is the
/// in-memory shape that rules are read and written as, so that rule logic never has to
/// touch a `@Model` class or a `ModelContext`.
public struct RelevanceRuleValue: Sendable, Equatable, Hashable, Codable, Identifiable {
    public let id: UUID
    public var scope: RuleScope
    /// The normalised subject: a bundle identifier, a `scheme://host` origin, or a single
    /// lowercased title token, depending on `scope`.
    public var subject: String
    public var verdict: RuleVerdict
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        scope: RuleScope,
        subject: String,
        verdict: RuleVerdict,
        createdAt: Date
    ) {
        self.id = id
        self.scope = scope
        self.subject = subject
        self.verdict = verdict
        self.createdAt = createdAt
    }

    /// Create a rule stamped from an injected wall clock rather than from `Date()`.
    ///
    /// Rule creation is user-visible (the Privacy and rule-management surfaces order by
    /// it), so it goes through `FocusCore.DateProvider` like every other timestamp in this
    /// programme. That is what keeps a test that asserts on rule ordering deterministic.
    public init(
        id: UUID = UUID(),
        scope: RuleScope,
        subject: String,
        verdict: RuleVerdict,
        dateProvider: some DateProvider
    ) {
        self.init(
            id: id,
            scope: scope,
            subject: subject,
            verdict: verdict,
            createdAt: dateProvider.now
        )
    }

    /// The key a lookup uses. Two rules with the same scope and subject are the same rule,
    /// regardless of when they were made or what they concluded.
    public var matchKey: RuleMatchKey {
        RuleMatchKey(scope: scope, subject: subject)
    }
}

/// The identity of a rule for lookup purposes: scope plus subject.
public struct RuleMatchKey: Sendable, Equatable, Hashable, Codable {
    public let scope: RuleScope
    public let subject: String

    public init(scope: RuleScope, subject: String) {
        self.scope = scope
        self.subject = subject
    }
}

/// Errors a rule store may report. Declared now so callers written in later epics do not
/// have to invent an error type each.
public enum RuleStoreError: Error, Sendable, Equatable {
    /// No rule exists for the given identifier.
    case notFound(UUID)
    /// A rule already exists for that scope and subject.
    case duplicate(RuleMatchKey)
}

/// The storage seam for rules.
///
/// e02 and e04 supply the SwiftData-backed implementation; the shape is fixed now so that
/// nothing written against it has to change when the implementation lands. It is
/// deliberately CRUD-shaped and deliberately synchronous-looking through `async`: rule
/// reads happen on the main actor path during classification and must not block it.
public protocol RuleStore: Sendable {
    /// Every stored rule, in a stable order (oldest first).
    func allRules() async throws -> [RelevanceRuleValue]
    /// The rule matching a scope and subject, if one exists.
    func rule(for key: RuleMatchKey) async throws -> RelevanceRuleValue?
    /// Insert a rule, or replace the existing rule with the same `matchKey`.
    func upsert(_ rule: RelevanceRuleValue) async throws
    /// Remove a rule by identifier. Throws `RuleStoreError.notFound` if absent.
    func delete(id: UUID) async throws
    /// Remove every rule whose scope is `.session`. Called when a session ends.
    func clearSessionRules() async throws
}
