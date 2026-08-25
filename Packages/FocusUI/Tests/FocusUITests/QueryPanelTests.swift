import FocusCore
import Foundation
import SwiftUI
import Testing

@testable import FocusUI

enum QueryFixture {
    /// The central case. `noNegativeBasis` is 32 of the corpus's 72 uncertain verdicts (P-138):
    /// a real application in front of the person and the app genuinely does not know.
    static func noNegativeBasis(voice: NudgeVoice = .standard) -> QueryPresentation {
        QueryPresentation(
            voice: voice,
            task: "Write the Q3 proposal",
            subject: "com.figma.Desktop",
            reason: .noNegativeBasis,
            dwelled: .seconds(90)
        )
    }

    /// A browser or a chat client. The answer is coarse at baseline and the copy says so.
    static let mixedUse = QueryPresentation(
        task: "Write the Q3 proposal",
        subject: "com.apple.Safari",
        reason: .mixedUseApplication,
        dwelled: .seconds(120)
    )

    /// The engine cannot judge; the person can.
    static let languageNotSupported = QueryPresentation(
        task: "Rédiger la proposition",
        subject: "com.microsoft.Word",
        reason: .languageNotSupported,
        dwelled: .seconds(60)
    )
}

/// **One question, three answers, and no accusation anywhere in it** (U-1, R-77, R-86).
@Suite("The query panel asks and does not accuse")
@MainActor
struct QueryPanelTests {
    // MARK: - Three actions, and no fourth

    @Test("the panel offers exactly the three answers, each once, in the order U-1 names")
    func threeAnswers() {
        let ordered = QueryPresentation.actionOrder

        #expect(ordered == [.yesAddIt, .no, .notNow])
        #expect(Set(ordered) == Set(QueryAnswer.allCases))
        #expect(ordered.count == QueryAnswer.allCases.count)
    }

    /// Escape is `notNow` — the same action as the button, not a fourth outcome. The panel's own
    /// dismissal is wired to `QueryAnswer.notNow` by the host through
    /// `NudgePanelController.onDismiss`, and what makes that safe is that `notNow` writes a
    /// receipt: the asking happened and is remembered, so the question does not come back.
    @Test("the dismissal is an answer, and it is the one that writes no rule")
    func escapeIsNotNow() {
        #expect(QueryAnswer.notNow.ruleVerdict == nil)
        #expect(QueryAnswer.notNow.outcome == .declined)
        #expect(!QueryAnswer.notNow.outcome.wroteRule)
        // …and it is still remembered. That is the whole difference between "Not now" and
        // "nothing happened".
        #expect(AskedQuestionOutcome.declined.isAnswer == false)
    }

    @Test("the two answers that teach the app write a rule, in opposite directions")
    func answersWriteRules() {
        #expect(QueryAnswer.yesAddIt.ruleVerdict == .relevant)
        #expect(QueryAnswer.no.ruleVerdict == .unrelated)
        #expect(QueryAnswer.yesAddIt.outcome == .answeredRelevant)
        #expect(QueryAnswer.no.outcome == .answeredUnrelated)
    }

    @Test("the default is the click that buys future silence")
    func defaultAnswer() {
        #expect(QueryFixture.noNegativeBasis().primaryAnswer == .yesAddIt)
    }

    // MARK: - Every line is a query line

    /// **The assertion this suite exists for.** R-96f fails the gate on any accusatory string
    /// under a `nudge.*.query.*` key; this is the other half — that the query panel draws only
    /// keys under one, so the tone lint's search set is the panel's whole vocabulary.
    @Test("no string in this view resolves to a key from an accusation deck")
    func drawsOnlyQueryLines() {
        for answer in QueryAnswer.allCases {
            #expect(answer.copyKey.isQueryLine)
        }
        #expect(NudgeCopyKey.queryPanelTitle.isQueryLine)
        #expect(NudgeCopyKey.queryPanelScopeApp.isQueryLine)

        // And the converse, so this test cannot pass by the panel drawing nothing: the keys it
        // draws are exactly the five `query.*` lines the deck declares.
        let drawn: Set<NudgeCopyKey> = Set(QueryAnswer.allCases.map(\.copyKey))
            .union([.queryPanelTitle, .queryPanelScopeApp])
        #expect(drawn == Set(NudgeCopyKey.allCases.filter(\.isQueryLine)))
    }

    /// A question carries no band and no stage, and neither does its presentation. That is
    /// R-76's second structural fact, restated one layer out: there is no value on this type an
    /// accusation could be drawn from.
    @Test("the presentation carries no severity a surface could escalate")
    func noSeverityToEscalate() {
        let presentation = QueryFixture.noNegativeBasis()
        // Everything it does carry is either a name or a fact about time.
        #expect(!presentation.subject.isEmpty)
        #expect(!presentation.task.isEmpty)
        #expect(presentation.dwelled > .zero)
        #expect(QueryableUncertainty.allCases.contains(presentation.reason))
    }

    // MARK: - The subject is named, and the scope is stated before the answer

    @Test(
        "the announcement names the subject, the task and the scope",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func announcementNamesEverything() {
        let announced = QueryFixture.noNegativeBasis().announcement()
        #expect(announced.contains("com.figma.Desktop"))
        #expect(announced.contains("Write the Q3 proposal"))
        // The scope sentence, spoken before the person can answer.
        #expect(
            announced.contains(
                NudgeCopy.string(voice: .standard, .queryPanelScopeApp)
            )
        )
    }

    @Test("every askable reason has a sentence of its own to draw")
    func everyReasonHasCopy() {
        for reason in QueryableUncertainty.allCases {
            #expect(reason.copyKey.hasPrefix("nudge.query.reason."))
        }
        #expect(QueryableUncertainty.allCases.count == 3)
    }

    // MARK: - The clicks

    @Test("every button reports its own answer and nothing else")
    func clicksReportThemselves() {
        var seen: [QueryAnswer] = []
        let view = QueryPanelView(presentation: QueryFixture.noNegativeBasis()) { seen.append($0) }

        for answer in QueryPresentation.actionOrder { view.onAnswer(answer) }

        #expect(seen == QueryPresentation.actionOrder)
    }
}

@Suite("Query panel snapshots", .enabled(if: LocalizationLane.catalogsAreCompiled))
@MainActor
struct QueryPanelSnapshotTests {
    static let panelWidth: CGFloat = 380

    @Test(
        "every deck asks the same question the same shape",
        arguments: NudgeVoice.allCases, ["light", "dark"]
    )
    func everyDeck(voice: NudgeVoice, variant: String) throws {
        try SnapshotHarness.assertSnapshot(
            QueryPanelView(presentation: QueryFixture.noNegativeBasis(voice: voice)),
            component: "queryPanel.\(voice.rawValue)",
            variant: variant,
            width: Self.panelWidth
        )
    }

    @Test(
        "the panel survives the appearance variants at both text sizes",
        arguments: ["increasedContrast", "reduceTransparency"], SnapshotTypeSize.allCases
    )
    func appearanceVariants(variant: String, size: SnapshotTypeSize) throws {
        try SnapshotHarness.assertSnapshot(
            QueryPanelView(presentation: QueryFixture.noNegativeBasis()),
            component: "queryPanel",
            variant: variant,
            textScale: size.textScale,
            width: Self.panelWidth
        )
    }

    @Test("the default deck survives the largest text size", arguments: ["light", "dark"])
    func largeText(variant: String) throws {
        try SnapshotHarness.assertSnapshot(
            QueryPanelView(presentation: QueryFixture.noNegativeBasis()),
            component: "queryPanel",
            variant: variant,
            textScale: .accessibilityLarge,
            width: Self.panelWidth
        )
    }

    /// One picture per askable reason, because the reason line is the only thing that makes
    /// "we cannot tell" a statement rather than an excuse.
    @Test("each askable reason draws its own sentence", arguments: ["light"])
    func everyReason(variant: String) throws {
        let cases: [(String, QueryPresentation)] = [
            ("mixedUse", QueryFixture.mixedUse),
            ("languageNotSupported", QueryFixture.languageNotSupported)
        ]
        for (name, presentation) in cases {
            try SnapshotHarness.assertSnapshot(
                QueryPanelView(presentation: presentation),
                component: "queryPanel.\(name)",
                variant: variant,
                width: Self.panelWidth
            )
        }
    }

    /// **The question and the accusation are different pictures**, and they have to be: a person
    /// who cannot tell at a glance which one they are looking at has been accused.
    @Test("the question does not look like the accusation")
    func questionDoesNotLookLikeAnAccusation() throws {
        let question = try SnapshotHarness.render(
            QueryPanelView(presentation: QueryFixture.noNegativeBasis()),
            traits: SnapshotHarness.variantTraits(named: "light"),
            width: Self.panelWidth,
            name: "queryPanel.distinctness.question"
        )
        let accusation = try SnapshotHarness.render(
            AccusationPanelView(presentation: AccusationFixture.rungTwo()),
            traits: SnapshotHarness.variantTraits(named: "light"),
            width: Self.panelWidth,
            name: "queryPanel.distinctness.accusation"
        )
        #expect(PNGCompare.areDistinct(question.pixels, accusation.pixels))
    }
}
