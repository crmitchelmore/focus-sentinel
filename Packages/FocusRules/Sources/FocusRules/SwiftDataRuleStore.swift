import FocusCore
import Foundation
import SwiftData

/// The durable `RuleStore` (F-11).
///
/// `InMemoryRuleStore` is not a stand-in for this — it is the store rule *logic* is tested
/// against, so that a rule-engine test never has to stand up a `ModelContainer` to ask what
/// happens when two rules disagree. This is the one that remembers.
///
/// ## Scoping
///
/// A rule is either **global** (`task == nil`, which is what e04's engine reads for every
/// priority) or scoped to exactly one priority, in which case it cascades away with that
/// priority. Identity for upsert purposes is therefore `(task, scope, subject)` and not
/// `(scope, subject)`: "Safari is unrelated *while I am writing the proposal*" and "Safari is
/// unrelated" are two different judgements, and collapsing them would silently promote a
/// scoped decision to a permanent one.
///
/// ## Why it is `@MainActor` rather than an actor
///
/// `ModelContext` is not `Sendable` and the container's `mainContext` is the one every other
/// surface in the app already holds. An `actor` here would have to own a second context, and
/// two contexts over one store is how a rule written in the cockpit fails to appear in the
/// rules pane until something reloads.
///
/// ## Rows this build cannot read
///
/// A rule whose stored `scopeRaw` or `verdictRaw` is not a value this build knows cannot be
/// applied — but it is **never deleted**, because it was written by a version that did know.
/// It is skipped by every read and counted by `unreadableRuleCount()`, so the drop is visible
/// rather than silent.
@MainActor
public final class SwiftDataRuleStore: RuleStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: - RuleStore

    /// Every stored rule this build can read, oldest first.
    public func allRules() async throws -> [RelevanceRuleValue] {
        try storedRules().compactMap(Self.value(of:))
    }

    public func rule(for key: RuleMatchKey) async throws -> RelevanceRuleValue? {
        try await allRules().last { $0.matchKey == key }
    }

    /// Insert a rule, or replace the one that already covers the same subject in the same
    /// scope **and the same task**. Defaults to a global rule.
    public func upsert(_ rule: RelevanceRuleValue) async throws {
        try await upsert(rule, taskID: nil)
    }

    public func delete(id: UUID) async throws {
        guard let stored = try storedRule(id: id) else { throw RuleStoreError.notFound(id) }
        context.delete(stored)
        try context.save()
    }

    /// Remove every `.session`-scoped rule. Called when a priority is completed.
    ///
    /// Scoped rules of other kinds are untouched, and so are global rules: ending a session is
    /// not a reason to forget that the user thinks a news site is unrelated.
    public func clearSessionRules() async throws {
        let scope = RuleScope.session.rawValue
        let descriptor = FetchDescriptor<FocusSchemaV2.RelevanceRule>(
            predicate: #Predicate { $0.scopeRaw == scope }
        )
        for stored in try context.fetch(descriptor) {
            context.delete(stored)
        }
        try context.save()
    }

    // MARK: - Scoping

    /// The rules scoped to one priority. `nil` asks for the global ones.
    public func rules(forTask taskID: UUID?) async throws -> [RelevanceRuleValue] {
        try storedRules()
            .filter { $0.task?.id == taskID }
            .compactMap(Self.value(of:))
    }

    /// The rules that apply to every priority.
    public func globalRules() async throws -> [RelevanceRuleValue] {
        try await rules(forTask: nil)
    }

    /// Insert or replace, in the given scope.
    public func upsert(_ rule: RelevanceRuleValue, taskID: UUID?) async throws {
        let task = try taskID.flatMap { try storedTask(id: $0) }
        if let taskID, task == nil { throw RuleStoreError.notFound(taskID) }

        // Re-deciding about the same subject replaces the old decision rather than
        // accumulating a second, contradictory one.
        for existing in try storedRules()
        where existing.id != rule.id
            && existing.task?.id == taskID
            && existing.scopeRaw == rule.scope.rawValue
            && existing.subject == rule.subject {
            context.delete(existing)
        }

        if let stored = try storedRule(id: rule.id) {
            stored.scopeRaw = rule.scope.rawValue
            stored.subject = rule.subject
            stored.verdictRaw = rule.verdict.rawValue
            stored.createdAt = rule.createdAt
            stored.task = task
        } else {
            context.insert(
                FocusSchemaV2.RelevanceRule(
                    id: rule.id,
                    scopeRaw: rule.scope.rawValue,
                    subject: rule.subject,
                    verdictRaw: rule.verdict.rawValue,
                    createdAt: rule.createdAt,
                    task: task
                )
            )
        }
        try context.save()
    }

    /// Which priority a rule is scoped to, or `nil` if it is global.
    public func taskID(forRule id: UUID) async throws -> UUID? {
        guard let stored = try storedRule(id: id) else { throw RuleStoreError.notFound(id) }
        return stored.task?.id
    }

    /// How many stored rows this build cannot interpret.
    ///
    /// A non-zero count is not an error — it is a store written by a newer version, read by an
    /// older one. It exists so the omission is visible in a test and in the Privacy pane
    /// rather than being a silent shortfall in a list.
    public func unreadableRuleCount() async throws -> Int {
        try storedRules().count { Self.value(of: $0) == nil }
    }

    // MARK: - Storage

    private func storedRules() throws -> [FocusSchemaV2.RelevanceRule] {
        let rules = try context.fetch(FetchDescriptor<FocusSchemaV2.RelevanceRule>())
        // Sorted in Swift so that the tie-break is a decision rather than whatever order the
        // store felt like returning — the same ordering `InMemoryRuleStore` promises.
        return rules.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt { return lhs.id.uuidString < rhs.id.uuidString }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func storedRule(id: UUID) throws -> FocusSchemaV2.RelevanceRule? {
        let descriptor = FetchDescriptor<FocusSchemaV2.RelevanceRule>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    private func storedTask(id: UUID) throws -> FocusSchemaV2.PriorityTask? {
        let descriptor = FetchDescriptor<FocusSchemaV2.PriorityTask>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    /// Decode a stored row. `nil` means this build does not know one of its vocabularies —
    /// which is a reason to skip the row, never a reason to delete it.
    private static func value(of stored: FocusSchemaV2.RelevanceRule) -> RelevanceRuleValue? {
        guard let scope = RuleScope(rawValue: stored.scopeRaw),
              let verdict = RuleVerdict(rawValue: stored.verdictRaw)
        else { return nil }

        return RelevanceRuleValue(
            id: stored.id,
            scope: scope,
            subject: stored.subject,
            verdict: verdict,
            createdAt: stored.createdAt
        )
    }
}
