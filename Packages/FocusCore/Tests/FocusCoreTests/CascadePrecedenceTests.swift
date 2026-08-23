import Foundation
import Testing

@testable import FocusCore

/// The ladder is a product contract (R-54). These are the assertions that stop it drifting
/// between the runtime, the explanation builder, the Settings pane and the copy.
@Suite("Cascade precedence")
struct CascadePrecedenceTests {
    @Test("the nine ranks are 0…8, each exactly once, with no gaps and no fractions")
    func ranksAreAStrictTotalOrder() {
        let ranks = CascadeStage.allCases.map(\.rank)
        #expect(ranks == Array(0..<CascadeStage.allCases.count))
        #expect(Set(ranks).count == ranks.count)
        #expect(ranks == [0, 1, 2, 3, 4, 5, 6, 7, 8])
    }

    @Test("the declared ladder is nine rungs and the executable ladder is eight")
    func threeLengthsAreDistinct() {
        #expect(CascadeStage.allCases.count == 9)
        #expect(CascadePrecedence.rungs.count == 9)
        #expect(CascadePrecedence.executableRungs.count == 8)
    }

    @Test("the ladder covers every stage exactly once, in allCases order")
    func ladderCoversEveryStageInOrder() {
        #expect(CascadePrecedence.rungs.map(\.stage) == CascadeStage.allCases)
        #expect(CascadePrecedence.rungs.map(\.rank) == CascadeStage.allCases.map(\.rank))

        for stage in CascadeStage.allCases {
            #expect(CascadePrecedence.rung(for: stage)?.stage == stage)
        }
    }

    /// `executableRungs` is a *filter* of the one list, not a second list. If it were written
    /// out separately, the two could disagree — which is the drift this whole ruling exists to
    /// prevent.
    @Test("executableRungs is rungs.filter(isExecutable) and preserves rank order")
    func executableRungsIsAFilter() {
        #expect(CascadePrecedence.executableRungs == CascadePrecedence.rungs.filter(\.isExecutable))
        #expect(CascadePrecedence.executableRungs.map(\.rank).sorted() == CascadePrecedence.executableRungs.map(\.rank))
    }

    /// e06 flips one flag. Until it does, the model is *not in the sequence the cascade walks*
    /// rather than skipped by a special case, and no classification in this build can report it.
    @Test("onDeviceModel is the only non-executable rung, and sits below every rule and the heuristic")
    func theModelIsDeclaredAndUnreachable() {
        let notExecutable = CascadePrecedence.rungs.filter { !$0.isExecutable }
        #expect(notExecutable.map(\.stage) == [.onDeviceModel])
        #expect(!CascadePrecedence.executableRungs.contains { $0.stage == .onDeviceModel })

        for stage in [CascadeStage.sessionRule, .taskRule, .globalRule, .contextPack, .seedRule, .heuristic] {
            #expect(stage < CascadeStage.onDeviceModel, "\(stage) must bind harder than the model")
        }
        #expect(CascadeStage.onDeviceModel.rank == 6)
        #expect(CascadeStage.seedFallback.rank == 7)
        #expect(CascadeStage.unresolved.rank == 8)
    }

    @Test("a decisive seed out-ranks the heuristic and an ask-each-time seed does not")
    func theTwoSeedRungsSitEitherSideOfTheHeuristic() {
        #expect(CascadeStage.seedRule < CascadeStage.heuristic)
        #expect(CascadeStage.heuristic < CascadeStage.seedFallback)
    }

    @Test("every rung carries both copy keys, and they are distinct and well-formed")
    func everyRungHasCopy() {
        var settingsKeys: Set<String> = []
        var explanationKeys: Set<String> = []

        for rung in CascadePrecedence.rungs {
            #expect(rung.settingsCopyKey == "cascade.rung.\(rung.stage.rawValue)")
            #expect(rung.explanationKey == "explanation.stage.\(rung.stage.rawValue)")
            settingsKeys.insert(rung.settingsCopyKey)
            explanationKeys.insert(rung.explanationKey)
        }

        #expect(settingsKeys.count == CascadePrecedence.rungs.count)
        #expect(explanationKeys.count == CascadePrecedence.rungs.count)
        #expect(!CascadePrecedence.unavailableCaptionKey.isEmpty)
        #expect(!CascadePrecedence.headingKey.isEmpty)
        #expect(!CascadePrecedence.footnoteKey.isEmpty)
    }

    /// The correspondence is asserted, not restated: `RuleAuthority` is a second vocabulary
    /// over the same first three rungs, and two vocabularies that agree by coincidence are two
    /// vocabularies that will one day disagree.
    @Test("RuleAuthority's three ranks equal the first three cascade stages'")
    func authorityRanksMatchTheLadder() {
        #expect(RuleAuthority.allCases.map(\.rank) == [0, 1, 2])
        #expect(RuleAuthority.session.rank == CascadeStage.sessionRule.rank)
        #expect(RuleAuthority.task.rank == CascadeStage.taskRule.rank)
        #expect(RuleAuthority.global.rank == CascadeStage.globalRule.rank)

        for authority in RuleAuthority.allCases {
            #expect(authority.stage.rank == authority.rank)
            #expect(CascadePrecedence.rung(for: authority.stage)?.isExecutable == true)
        }
    }

    @Test("a session rule out-ranks a task rule, which out-ranks a global one")
    func authorityIsOrdered() {
        #expect(RuleAuthority.session < RuleAuthority.task)
        #expect(RuleAuthority.task < RuleAuthority.global)
    }

    /// Narrower wins: the user who wrote the narrower rule meant it as the exception.
    @Test("subject kinds are ordered narrowest first")
    func subjectKindIsOrderedNarrowestFirst() {
        #expect(RuleSubjectKind.allCases.map(\.rank) == [0, 1, 2])
        #expect(RuleSubjectKind.titleToken < RuleSubjectKind.domain)
        #expect(RuleSubjectKind.domain < RuleSubjectKind.app)
    }

    @Test("the rule sort is a total order over authority, narrowness, age and identity")
    func scopedRuleSortIsTotal() {
        let early = Date(timeIntervalSince1970: 1_767_225_600)
        let late = early.addingTimeInterval(60)

        let sessionApp = ScopedRuleValue(
            authority: .session, subjectKind: .app,
            subject: "com.apple.Safari", verdict: .relevant, createdAt: late
        )
        let globalDomain = ScopedRuleValue(
            authority: .global, subjectKind: .domain,
            subject: "https://docs.example", verdict: .relevant, createdAt: early
        )
        let globalApp = ScopedRuleValue(
            authority: .global, subjectKind: .app,
            subject: "com.apple.Notes", verdict: .unrelated, createdAt: early
        )

        #expect(ScopedRuleValue.precedes(sessionApp, globalDomain))
        #expect(ScopedRuleValue.precedes(globalDomain, globalApp))
        #expect(!ScopedRuleValue.precedes(globalApp, globalDomain))

        // Antisymmetry and irreflexivity, which is what makes a sort of it deterministic.
        for rule in [sessionApp, globalDomain, globalApp] {
            #expect(!ScopedRuleValue.precedes(rule, rule))
        }
    }

    @Test("a scoped rule round-trips through Codable with both axes intact")
    func scopedRuleRoundTrips() throws {
        for authority in RuleAuthority.allCases {
            for kind in RuleSubjectKind.allCases {
                let rule = ScopedRuleValue(
                    authority: authority, subjectKind: kind,
                    subject: "com.example.app", verdict: .uncertain,
                    createdAt: Date(timeIntervalSince1970: 1_767_225_600)
                )
                let decoded = try JSONDecoder().decode(
                    ScopedRuleValue.self, from: JSONEncoder().encode(rule)
                )
                #expect(decoded == rule)
                #expect(decoded.authority == authority)
                #expect(decoded.subjectKind == kind)
            }
        }
    }
}
