import Foundation
import Testing

@testable import FocusCore

/// The four dispositions and the one opinion this app ships (R-64, F-130, F-171).
@Suite("Per-app dispositions and the seed table")
struct RelevanceSeedTests {
    /// **Acceptance criterion 12.** The mapping is the identity on `allCases`, so a
    /// disposition cannot be lost on the way to the store or invented on the way back — and
    /// that is what makes "no schema change" a fact rather than a hope.
    @Test("the four dispositions round-trip through the stored vocabulary, totally")
    func dispositionsRoundTrip() {
        for disposition in AppRuleDisposition.allCases {
            #expect(AppRuleDisposition(ruleVerdict: disposition.ruleVerdict) == disposition)
        }

        // And in the other direction: every stored judgement, plus its absence, is a
        // disposition. Four verdict states, four dispositions, no overlap.
        let states: [PriorityRuleVerdict?] = [.relevant, .unrelated, .uncertain, nil]
        let mapped = states.map(AppRuleDisposition.init(ruleVerdict:))
        #expect(Set(mapped) == Set(AppRuleDisposition.allCases))
        #expect(mapped.count == AppRuleDisposition.allCases.count)
    }

    /// "Interpret by context" is the *absence of a row*, which is why it costs no schema
    /// change. `askEachTime` is not absence — it is a decision to say nothing, and it stores.
    @Test("only interpretByContext is the absence of a row")
    func onlyInterpretByContextIsAbsence() {
        #expect(AppRuleDisposition.interpretByContext.ruleVerdict == nil)
        #expect(AppRuleDisposition.askEachTime.ruleVerdict == .uncertain)
        #expect(AppRuleDisposition.alwaysRelevant.ruleVerdict == .relevant)
        #expect(AppRuleDisposition.alwaysDistracting.ruleVerdict == .unrelated)

        #expect(!AppRuleDisposition.interpretByContext.isDecisive)
        for disposition in AppRuleDisposition.allCases where disposition != .interpretByContext {
            #expect(disposition.isDecisive)
        }
    }

    /// The two seed rungs, and why there are two: a decisive default must out-rank the
    /// heuristic, an `ask each time` default must not.
    @Test("a decisive seed answers above the heuristic and an ask-each-time seed below it")
    func seedStagesSitEitherSideOfTheHeuristic() {
        #expect(AppRuleDisposition.alwaysDistracting.seedStage == .seedRule)
        #expect(AppRuleDisposition.alwaysRelevant.seedStage == .seedRule)
        #expect(AppRuleDisposition.askEachTime.seedStage == .seedFallback)
        #expect(AppRuleDisposition.interpretByContext.seedStage == nil)

        #expect(CascadeStage.seedRule < CascadeStage.heuristic)
        #expect(CascadeStage.heuristic < CascadeStage.seedFallback)
    }

    @Test("every disposition carries its own copy key and its own glyph")
    func everyDispositionHasCopyAndAGlyph() {
        let keys = AppRuleDisposition.allCases.map(\.labelKey)
        let symbols = AppRuleDisposition.allCases.map(\.symbolName)
        #expect(Set(keys).count == keys.count)
        #expect(Set(symbols).count == symbols.count)
        for disposition in AppRuleDisposition.allCases {
            #expect(disposition.labelKey == "rule.disposition.\(disposition.rawValue)")
        }
    }

    // MARK: - The seed table

    /// **The single most important assertion about the table**: the app ships exactly one
    /// opinion, it is the one the Court ordered, and it is the only row that could cause a
    /// nudge without the person having said anything.
    @Test("exactly one seed is decisive, and it is iPhone Mirroring")
    func exactlyOneDecisiveSeed() {
        let decisive = RelevanceSeed.decisiveSeeds
        #expect(decisive.count == 1)
        #expect(decisive["com.apple.ScreenContinuity"] == .alwaysDistracting)
        #expect(RelevanceSeed.disposition(for: "com.apple.ScreenContinuity") == .alwaysDistracting)
    }

    /// No seed asserts that something *is* the work, because the app cannot know that about
    /// an application it has never been told about.
    @Test("no seed is alwaysRelevant, and no seed is interpretByContext")
    func noSeedAssertsRelevance() {
        for (identifier, disposition) in RelevanceSeed.defaults {
            #expect(disposition != .alwaysRelevant, "\(identifier) claims to be the work")
            #expect(
                disposition != .interpretByContext,
                "\(identifier) stores the absence of a row, which is not a row"
            )
        }
    }

    /// The safety property of the whole table: every row but one declines, and declining
    /// suppresses. So the seed list is a net *reduction* in false nudges.
    @Test("every other seed declines to decide")
    func everyOtherSeedDeclines() {
        let fallbacks = RelevanceSeed.fallbackSeeds
        #expect(fallbacks.count == RelevanceSeed.defaults.count - 1)
        for (_, disposition) in fallbacks {
            #expect(disposition == .askEachTime)
            #expect(disposition.ruleVerdict == .uncertain)
        }
    }

    /// No social network, no game and no video site is shipped as `alwaysDistracting` — the
    /// absence is a ruling, so it is asserted rather than left to inspection.
    @Test("the table ships no accusation about a social, gaming or video application")
    func noAccusationsAreShipped() {
        let neverDecisive = [
            "com.apple.Safari", "com.google.Chrome", "com.spotify.client", "com.apple.TV",
            "com.hnc.Discord", "com.apple.Music", "com.apple.MobileSMS"
        ]
        for identifier in neverDecisive {
            #expect(RelevanceSeed.disposition(for: identifier) == .askEachTime)
        }

        // And nothing this app has never measured has an opinion attached to it at all.
        for identifier in ["com.microsoft.Excel", "com.apple.dt.Xcode", "com.figma.Desktop",
                           "com.google.ios.youtube", "com.apple.Preview"] {
            #expect(
                RelevanceSeed.disposition(for: identifier) == nil,
                "\(identifier) has a shipped opinion it did not earn"
            )
        }
    }

    @Test("every seed key is a syntactically valid reverse-DNS identifier, and unique")
    func seedKeysAreWellFormed() {
        for identifier in RelevanceSeed.defaults.keys {
            let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
            let hasEmptyComponent = parts.filter(\.isEmpty).isEmpty == false
            #expect(parts.count >= 2, "\(identifier) is not reverse-DNS")
            #expect(!hasEmptyComponent, "\(identifier) has an empty component")
            #expect(!identifier.contains(" "), "\(identifier) contains whitespace")
            #expect(identifier == identifier.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        // A dictionary cannot hold a duplicate key, so the assertion that matters is that the
        // table is the size the review of it assumed.
        #expect(RelevanceSeed.defaults.count == 18)
    }

    /// Matching is exact: two applications whose identifiers share a prefix are two different
    /// applications, and a seed that guessed between them would be an opinion nobody measured.
    @Test("seed matching is exact, never a prefix")
    func seedMatchingIsExact() {
        #expect(RelevanceSeed.disposition(for: "com.apple.SafariTechnologyPreview") == nil)
        #expect(RelevanceSeed.disposition(for: "com.apple.Safari.WebApp") == nil)
        #expect(RelevanceSeed.disposition(for: "com.apple.safari") == nil, "matching is case-exact")
    }
}
