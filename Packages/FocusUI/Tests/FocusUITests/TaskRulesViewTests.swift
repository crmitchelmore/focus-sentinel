import FocusCore
import Testing

@testable import FocusUI

/// **The rules pane offers only scopes the app reads** (e07a, PD-1).
///
/// `authorableScopes` was `[.app, .domain, .titleToken]` for three epics, and the third was a lie
/// in a button: nothing in the shipping app produces a title token, so a rule authored under it
/// could never match. The vocabulary is a fold over `PriorityRuleScope` now — every scope that is
/// neither a lifetime (`.session`) nor retired — so the day a scope retires it leaves this list
/// without anybody editing it. Red before this round on the first assertion.
@Suite("The rules pane's authoring vocabulary")
struct TaskRulesViewTests {
    /// focus-6ji4 withdrew `.domain` on the same argument while the shipping app reads no site:
    /// a site rule was stored and could never match. It returns with `ShippingObservation`.
    @Test("a retired or unobserved scope cannot be authored, and every live observed scope can")
    func authorableScopesAreTheLiveSubjectScopes() {
        #expect(!TaskRulesView.authorableScopes.contains(.titleToken))
        #expect(TaskRulesView.authorableScopes.contains(.domain) == ShippingObservation.readsBrowserSite)
        #expect(TaskRulesView.authorableScopes.contains(.app))
        for scope in PriorityRuleScope.allCases {
            let expected = scope != .session && !scope.isRetired && scope.isObserved
            #expect(
                TaskRulesView.authorableScopes.contains(scope) == expected,
                "\(scope) is \(expected ? "missing from" : "present in") the authoring vocabulary"
            )
        }
    }

    /// The retired scope still has a caption and a glyph, because a stored row of it is still
    /// drawn — kept, deletable, and captioned *no longer read*.
    @Test("a retired scope is still nameable, so a stored row of it can be drawn")
    func aRetiredScopeIsStillNameable() {
        #expect(TaskRulesView.scopeKey(.titleToken) == .priorityRulesScopeTitleToken)
        #expect(!PriorityRuleScope.titleToken.symbolName.isEmpty)
    }

    @Test("a stored rule the app cannot read is drawn inert, and one it can read is not")
    func inertRowsAreTheUnreadableOnes() {
        #expect(TaskRulesView.isInert(.titleToken))
        #expect(TaskRulesView.isInert(.domain) == !ShippingObservation.readsBrowserSite)
        #expect(!TaskRulesView.isInert(.app))
    }
}
