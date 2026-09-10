import Foundation

/// A complete, working `RuleStore` held entirely in memory.
///
/// This is not a stand-in for the SwiftData-backed store that e02 adds — it is the store
/// that rule *logic* is tested against, so that a rule-engine test never has to stand up a
/// `ModelContainer` to ask "what happens when two rules disagree". It is an `actor`
/// because rule reads happen from the classification path and writes from the UI, and the
/// two must not race.
public actor InMemoryRuleStore: RuleStore {
    private var storage: [UUID: RelevanceRuleValue] = [:]

    public init(rules: [RelevanceRuleValue] = []) {
        for rule in rules {
            storage[rule.id] = rule
        }
    }

    public func allRules() async throws -> [RelevanceRuleValue] {
        storage.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    public func rule(for key: RuleMatchKey) async throws -> RelevanceRuleValue? {
        try await allRules().last { $0.matchKey == key }
    }

    public func upsert(_ rule: RelevanceRuleValue) async throws {
        // "Upsert" is by match key, not by identifier: re-deciding about the same subject
        // replaces the old decision rather than accumulating a second contradictory rule.
        for (id, existing) in storage where existing.matchKey == rule.matchKey && id != rule.id {
            storage[id] = nil
        }
        storage[rule.id] = rule
    }

    public func delete(id: UUID) async throws {
        guard storage[id] != nil else { throw RuleStoreError.notFound(id) }
        storage[id] = nil
    }

    public func clearSessionRules() async throws {
        for (id, rule) in storage where rule.scope == .session {
            storage[id] = nil
        }
    }
}
