import FocusCore
import Foundation
import Testing

@testable import FocusRules

@Suite("Rule model")
struct RuleModelTests {
    @Test("RuleScope raw values are stable strings")
    func ruleScopeRawValues() {
        #expect(RuleScope.allCases.count == 4)
        #expect(RuleScope.app.rawValue == "app")
        #expect(RuleScope.domain.rawValue == "domain")
        #expect(RuleScope.titleToken.rawValue == "titleToken")
        #expect(RuleScope.session.rawValue == "session")
        #expect(RuleScope(rawValue: "domain") == .domain)
    }

    @Test("RuleVerdict raw values are stable strings and include an explicit uncertain")
    func ruleVerdictRawValues() {
        #expect(RuleVerdict.allCases.count == 3)
        #expect(RuleVerdict.relevant.rawValue == "relevant")
        #expect(RuleVerdict.unrelated.rawValue == "unrelated")
        #expect(RuleVerdict.uncertain.rawValue == "uncertain")
        // `uncertain` must be its own case and must never be folded into `unrelated`:
        // declining to decide is not the same as deciding against.
        #expect(RuleVerdict.uncertain != RuleVerdict.unrelated)
    }

    @Test("RelevanceRuleValue round-trips through raw values")
    func ruleValueRoundTripsThroughRawValues() throws {
        for scope in RuleScope.allCases {
            for verdict in RuleVerdict.allCases {
                let rule = RelevanceRuleValue(
                    scope: scope,
                    subject: "example.com",
                    verdict: verdict,
                    createdAt: FixedDateProvider.reference.now
                )
                let data = try JSONEncoder().encode(rule)
                let decoded = try JSONDecoder().decode(RelevanceRuleValue.self, from: data)

                #expect(decoded == rule)
                #expect(decoded.scope.rawValue == scope.rawValue)
                #expect(decoded.verdict.rawValue == verdict.rawValue)
            }
        }
    }

    @Test("a rule created from an injected clock carries that clock's instant")
    func ruleUsesInjectedClock() {
        let clock = FixedDateProvider.reference
        let rule = RelevanceRuleValue(
            scope: .app,
            subject: "com.apple.Safari",
            verdict: .unrelated,
            dateProvider: clock
        )

        #expect(rule.createdAt == clock.now)
    }

    @Test("match key identifies a rule by scope and subject only")
    func matchKeyIgnoresIdentityAndVerdict() {
        let a = RelevanceRuleValue(
            scope: .domain,
            subject: "news.example",
            verdict: .unrelated,
            createdAt: FixedDateProvider.reference.now
        )
        let b = RelevanceRuleValue(
            scope: .domain,
            subject: "news.example",
            verdict: .relevant,
            createdAt: FixedDateProvider.reference.now.addingTimeInterval(60)
        )

        #expect(a.matchKey == b.matchKey)
        #expect(a.id != b.id)
        #expect(a != b)
    }
}

@Suite("InMemoryRuleStore")
struct InMemoryRuleStoreTests {
    private func rule(
        _ scope: RuleScope,
        _ subject: String,
        _ verdict: RuleVerdict,
        offset: TimeInterval = 0
    ) -> RelevanceRuleValue {
        RelevanceRuleValue(
            scope: scope,
            subject: subject,
            verdict: verdict,
            createdAt: FixedDateProvider.reference.now.addingTimeInterval(offset)
        )
    }

    @Test("an empty store has no rules and finds nothing")
    func emptyStore() async throws {
        let store = InMemoryRuleStore()
        #expect(try await store.allRules().isEmpty)
        #expect(try await store.rule(for: RuleMatchKey(scope: .app, subject: "x")) == nil)
    }

    @Test("upsert inserts, then replaces by match key rather than accumulating")
    func upsertReplacesByMatchKey() async throws {
        let store = InMemoryRuleStore()
        let first = rule(.domain, "news.example", .unrelated, offset: 0)
        try await store.upsert(first)
        #expect(try await store.allRules().count == 1)

        let reconsidered = rule(.domain, "news.example", .relevant, offset: 60)
        try await store.upsert(reconsidered)

        let all = try await store.allRules()
        #expect(all.count == 1)
        #expect(all.first?.verdict == .relevant)
        #expect(try await store.rule(for: reconsidered.matchKey)?.id == reconsidered.id)
    }

    @Test("rules come back oldest first")
    func rulesAreOrderedOldestFirst() async throws {
        let store = InMemoryRuleStore()
        let older = rule(.app, "com.apple.Safari", .unrelated, offset: 0)
        let newer = rule(.app, "com.apple.Mail", .relevant, offset: 120)
        try await store.upsert(newer)
        try await store.upsert(older)

        #expect(try await store.allRules().map(\.id) == [older.id, newer.id])
    }

    @Test("delete removes the rule and reports a missing one")
    func deleteRemovesAndReports() async throws {
        let store = InMemoryRuleStore()
        let only = rule(.titleToken, "invoice", .relevant)
        try await store.upsert(only)
        try await store.delete(id: only.id)
        #expect(try await store.allRules().isEmpty)

        await #expect(throws: RuleStoreError.notFound(only.id)) {
            try await store.delete(id: only.id)
        }
    }

    @Test("clearing session rules leaves durable rules alone")
    func clearSessionRulesIsScoped() async throws {
        let store = InMemoryRuleStore()
        let durable = rule(.app, "com.apple.Mail", .relevant, offset: 0)
        let ephemeral = rule(.session, "com.apple.Music", .relevant, offset: 30)
        try await store.upsert(durable)
        try await store.upsert(ephemeral)

        try await store.clearSessionRules()

        #expect(try await store.allRules().map(\.id) == [durable.id])
    }

    /// The seam, not the implementation: everything above is reached through the
    /// `RuleStore` protocol, which is what e02 and e04 will actually be written against.
    @Test("the store is usable purely through the RuleStore protocol")
    func usableThroughTheProtocol() async throws {
        let store: any RuleStore = InMemoryRuleStore()
        let value = rule(.domain, "docs.example", .relevant)
        try await store.upsert(value)
        #expect(try await store.rule(for: value.matchKey)?.verdict == .relevant)
    }
}
