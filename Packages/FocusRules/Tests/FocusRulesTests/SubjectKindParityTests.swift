import FocusCore
import Foundation
import Testing

@testable import FocusRules

/// Three vocabularies now name the same thing, and none of them may drift (R-72.1).
///
/// `RuleScope` is what a row stores. `PriorityRuleScope` is what the cockpit offers, declared
/// in `FocusCore` because `FocusUI` may not import this package. `RuleSubjectKind` is the
/// cascade's inner precedence axis, declared in `FocusCore` for the same reason — and it is
/// exactly `RuleScope` **minus** `.session`, because a `.session` row carries no subject kind
/// at all and e04 declines to infer one from the shape of a string (R-72.3).
@Suite("Subject-kind parity")
struct SubjectKindParityTests {
    @Test("RuleSubjectKind ∪ {session} is exactly RuleScope, in both directions")
    func subjectKindPlusSessionIsRuleScope() {
        let subjectKinds = Set(RuleSubjectKind.allCases.map(\.rawValue))
        let scopes = Set(RuleScope.allCases.map(\.rawValue))

        #expect(subjectKinds.union(["session"]) == scopes)
        #expect(scopes.subtracting(subjectKinds) == ["session"])
        #expect(subjectKinds == ["app", "domain", "titleToken"])
    }

    /// The scope a stored row carries maps onto a subject kind for every case except the one
    /// that has none. A fourth non-session scope added to `RuleScope` without a matching
    /// subject kind fails here rather than reaching the cascade with no narrowness.
    @Test("every non-session RuleScope has a subject kind of the same name")
    func everyNonSessionScopeHasASubjectKind() {
        for scope in RuleScope.allCases where scope != .session {
            let kind = RuleSubjectKind(rawValue: scope.rawValue)
            #expect(kind != nil, "no RuleSubjectKind for RuleScope.\(scope.rawValue)")
        }
        #expect(RuleSubjectKind(rawValue: RuleScope.session.rawValue) == nil)
    }

    /// The cockpit's vocabulary is the stored one, still. e02's parity assertion in the other
    /// direction is re-stated here beside the new axis, so all three sets are compared in one
    /// place rather than in two suites that could each be right about a different pair.
    @Test("PriorityRuleScope and RuleScope are still the same set of strings")
    func cockpitVocabularyMatchesTheStoredOne() {
        #expect(
            Set(PriorityRuleScope.allCases.map(\.rawValue)) == Set(RuleScope.allCases.map(\.rawValue))
        )
        #expect(
            Set(PriorityRuleVerdict.allCases.map(\.rawValue)) == Set(RuleVerdict.allCases.map(\.rawValue))
        )
    }
}
