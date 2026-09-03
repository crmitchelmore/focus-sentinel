import Foundation
import Testing

@testable import FocusCore

/// **A stored title-token rule still decodes, and says it is retired** (e07a, PD-1).
///
/// The shipped `.titleToken` scope was authorable for three epics and could never match: nothing
/// in the shipping app produces a title token. e07a withdraws the affordance and retires the
/// scope — not the case, because a stored row written under it must still decode. A row this
/// build cannot read is a row silently dropped, which is the defect `ContextItemKind.unknown`
/// exists to prevent on the other side of the same pane.
///
/// Red before this round: `PriorityRuleScope` had no `isRetired`, so nothing distinguished a
/// title-token row from a live one and the pane drew it with its verdict controls armed.
@Suite("A retired rule scope")
struct RetiredRuleScopeTests {
    @Test("a stored title-token row still decodes, as a rule of a retired scope")
    func aStoredTitleTokenRowDecodes() throws {
        let stored = FocusSchemaV3.RelevanceRule(
            scopeRaw: "titleToken",
            subject: "invoice",
            verdictRaw: "relevant",
            createdAt: Date(timeIntervalSince1970: 1_767_225_600)
        )
        let value = try #require(PriorityRuleValue(stored), "a stored title-token row was dropped")
        #expect(value.scope == .titleToken)
        #expect(value.scope.isRetired)
        #expect(value.subject == "invoice")
        #expect(value.verdict == .relevant)
    }

    /// The retirement is exactly one scope, named — a fold over the vocabulary rather than a
    /// list, so a second retirement (or an accidental one) is a diff in this line.
    @Test("exactly the title-token scope is retired")
    func exactlyTheTitleTokenScopeIsRetired() {
        let retired = PriorityRuleScope.allCases.filter(\.isRetired)
        #expect(retired == [.titleToken])
        // The retired scope keeps its raw value, so a stored row's `scopeRaw` still round-trips.
        #expect(PriorityRuleScope(rawValue: "titleToken") == .titleToken)
        #expect(PriorityRuleScope.titleToken.rawValue == "titleToken")
    }
}
