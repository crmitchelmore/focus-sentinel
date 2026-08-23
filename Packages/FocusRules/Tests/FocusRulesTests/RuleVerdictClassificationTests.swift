import FocusCore
import Foundation
import Testing

@testable import FocusRules

/// The stored-judgement → runtime-verdict mapping, asserted where the extension now lives
/// (R-53). It travelled here from `FocusClassifyTests.SeamTests`.
@Suite("Rule verdict as a classification verdict")
struct RuleVerdictClassificationTests {
    @Test("a user's explicit uncertain rule stays uncertain")
    func userUncertaintyIsPreserved() {
        #expect(RuleVerdict.relevant.classificationVerdict == .relevant)
        #expect(RuleVerdict.unrelated.classificationVerdict == .unrelated)
        #expect(RuleVerdict.uncertain.classificationVerdict == .uncertain)
    }

    /// The mapping is total and injective, so no stored judgement can be lost or merged into
    /// another on the way to the engine. Written over `allCases` rather than as three
    /// assertions so that a fourth rule verdict fails here instead of decoding to whatever
    /// case a `default` happened to name.
    @Test("the mapping is total and injective over every stored judgement")
    func mappingIsTotalAndInjective() {
        let mapped = RuleVerdict.allCases.map(\.classificationVerdict)
        #expect(mapped.count == RuleVerdict.allCases.count)
        #expect(Set(mapped).count == RuleVerdict.allCases.count)
        #expect(Set(mapped.map(\.rawValue)) == Set(RuleVerdict.allCases.map(\.rawValue)))
    }
}
