import FocusCore
import Foundation
import SwiftUI
import Testing

@testable import FocusUI

enum CascadeComponent: String, CaseIterable, Sendable {
    case cascadePrecedence

    var width: CGFloat? { 520 }

    @MainActor
    var view: AnyView {
        AnyView(CascadePrecedenceView())
    }
}

/// **The third reader of the ladder** (R-54).
///
/// `CascadePrecedence.rungs` is the only ordered list of rungs in the repository. The runtime
/// iterates it, the explanation builder switches over it, this pane renders it, and
/// `check-strings.sh` compares it to the copy. This suite is what makes the *third* reader
/// mechanically checked rather than merely intended: the rendered order is compared to the
/// ladder, so re-ordering the ladder without re-recording the baseline is a red gate.
@Suite("Cascade precedence snapshots", .enabled(if: LocalizationLane.catalogsAreCompiled))
@MainActor
struct CascadePrecedenceSnapshotTests {
    @Test(
        "the precedence pane matches its baseline in light and dark",
        arguments: CascadeComponent.allCases, VerdictAppearance.baselineVariants
    )
    func componentMatchesBaseline(component: CascadeComponent, variant: String) throws {
        for size in SnapshotTypeSize.allCases {
            try SnapshotHarness.assertSnapshot(
                component.view,
                component: component.rawValue,
                variant: variant,
                textScale: size.textScale,
                width: component.width
            )
        }
    }

    @Test("light and dark are different pictures", arguments: CascadeComponent.allCases)
    func lightAndDarkDiffer(component: CascadeComponent) throws {
        let light = try SnapshotHarness.render(
            component.view,
            traits: SnapshotHarness.variantTraits(named: "light"),
            width: component.width,
            name: "\(component.rawValue).distinctness.light"
        )
        let dark = try SnapshotHarness.render(
            component.view,
            traits: SnapshotHarness.variantTraits(named: "dark"),
            width: component.width,
            name: "\(component.rawValue).distinctness.dark"
        )
        #expect(PNGCompare.areDistinct(light.pixels, dark.pixels))
    }

    // MARK: - The pane holds no list of its own

    /// **The rendered order IS the ladder.**
    ///
    /// Not "matches the ladder" — is it. The view's `drawnRungs` returns
    /// `CascadePrecedence.rungs` itself, so there is no second list to drift, and this asserts
    /// the property the drawing depends on: all nine, in rank order, each rank once.
    @Test("the pane draws all nine rungs in rank order and holds no list of its own")
    func drawnOrderIsTheLadder() {
        let drawn = CascadePrecedenceView.drawnRungs
        #expect(drawn == CascadePrecedence.rungs)
        #expect(drawn.count == CascadeStage.allCases.count)
        #expect(drawn.map(\.rank) == Array(0..<drawn.count))
        #expect(drawn.map(\.stage) == CascadeStage.allCases)
    }

    /// The dimmed set is exactly the non-executable set — read from the ladder, so a rung that
    /// becomes executable in e06 stops being dimmed with no edit to the view.
    @Test("the dimmed rows are exactly the rungs this build cannot consult")
    func dimmedRowsAreTheUnavailableRungs() {
        #expect(
            CascadePrecedenceView.dimmedRungs == CascadePrecedence.rungs.filter { !$0.isExecutable }
        )
        #expect(CascadePrecedenceView.dimmedRungs.map(\.stage) == [.onDeviceModel])
        #expect(
            CascadePrecedence.executableRungs.count
                == CascadePrecedence.rungs.count - CascadePrecedenceView.dimmedRungs.count
        )
    }

    /// **The model is drawn, and it is drawn below every user rule and below the heuristic.**
    ///
    /// The placement is the contract this pane exists to show, so hiding the unavailable rung
    /// would remove the only thing a person could check. e06 supplies an implementation and
    /// flips one stored flag; it neither re-ranks the ladder nor renumbers anything.
    @Test("the unavailable model rung is drawn, below every rule rung and below the heuristic")
    func theModelIsDrawnInItsPlace() {
        let model = CascadePrecedence.rung(for: .onDeviceModel)
        #expect(model != nil)
        #expect(model?.isExecutable == false)
        #expect(CascadePrecedenceView.drawnRungs.contains { $0.stage == .onDeviceModel })

        for stage in [CascadeStage.sessionRule, .taskRule, .globalRule, .contextPack, .heuristic] {
            #expect(stage.rank < CascadeStage.onDeviceModel.rank, "\(stage.rawValue) outranked by the model")
        }
    }

    /// Every rung has copy, in the user's language, from `FocusCore`'s catalog.
    @Test(
        "every rung and both captions resolve to real text",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func everyRungIsNamed() {
        let names = CascadePrecedence.rungs.map { String(localized: $0.settingsCopyResource) }
        for (rung, name) in zip(CascadePrecedence.rungs, names) {
            #expect(!name.isEmpty)
            #expect(name != rung.settingsCopyKey, "\(rung.stage.rawValue) resolved to its own key")
        }
        #expect(Set(names).count == names.count, "two rungs read the same: \(names)")

        for resource in [
            CascadePrecedence.headingResource,
            CascadePrecedence.footnoteResource,
            CascadePrecedence.unavailableCaptionResource
        ] {
            #expect(!String(localized: resource).isEmpty)
        }
    }

    // MARK: - F-130's four dispositions, on the surface

    /// **The rule row's picker is the disposition vocabulary.**
    ///
    /// Three stored verdicts and one absence. The three the picker draws are exactly the
    /// decisive dispositions, in `allCases` order, and the fourth is the remove control —
    /// because `interpretByContext` is *no row at all*, which is what makes the four cost no
    /// schema change (R-64).
    @Test("the rule picker draws exactly the decisive dispositions, in order")
    func pickerIsTheDispositionVocabulary() {
        #expect(
            TaskRulesView.decisiveDispositions
                == [.alwaysRelevant, .alwaysDistracting, .askEachTime]
        )
        #expect(
            TaskRulesView.decisiveDispositions.map(TaskRulesView.verdict(of:))
                == [.relevant, .unrelated, .uncertain]
        )
        #expect(
            AppRuleDisposition.allCases.filter { !$0.isDecisive } == [.interpretByContext]
        )
        #expect(AppRuleDisposition.interpretByContext.ruleVerdict == nil)
    }

    /// The mapping is total and reversible in both directions, on the surface as well as in the
    /// store: nothing a person can choose is lost on the way down, and nothing comes back that
    /// they could not have chosen.
    @Test("every disposition round-trips through the stored verdict")
    func dispositionsRoundTrip() {
        for disposition in AppRuleDisposition.allCases {
            #expect(AppRuleDisposition(ruleVerdict: disposition.ruleVerdict) == disposition)
        }
        for verdict in PriorityRuleVerdict.allCases {
            #expect(AppRuleDisposition(ruleVerdict: verdict).ruleVerdict == verdict)
        }
    }

    /// Each disposition has a name of its own, so the row's tooltip can say which of the four
    /// a glyph means.
    @Test(
        "every disposition has copy of its own",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func everyDispositionIsNamed() {
        let names = AppRuleDisposition.allCases.map { String(localized: $0.labelResource) }
        for (disposition, name) in zip(AppRuleDisposition.allCases, names) {
            #expect(!name.isEmpty)
            #expect(name != disposition.labelKey, "\(disposition.rawValue) resolved to its own key")
        }
        #expect(Set(names).count == names.count, "two dispositions read the same: \(names)")
    }
}
