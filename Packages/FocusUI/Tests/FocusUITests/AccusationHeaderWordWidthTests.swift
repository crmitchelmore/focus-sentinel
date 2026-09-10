import AppKit
import FocusCore
import Foundation
import SwiftUI
import Testing

@testable import FocusUI

/// **The accusation panel's header asks for a word, not a sentence** (focus-6pr.5).
///
/// ## The defect
///
/// Found while fixing focus-0q4, which laid the *popover's own rows* out under the rule "a column
/// is never narrower than its longest word" and left the one surface drawn inside the popover
/// that is not one of those rows. `AccusationPanelView.header` is `badge · title · dismiss`:
/// inside the 300-point popover at `accessibilityLarge` the title column is narrower than its
/// longest word, and the committed picture reads `propo / sal` and `waitin / g`.
///
/// ## Why a plain `ViewThatFits` was not the fix, and this is
///
/// The bead deferred the obvious repair for a stated reason: the header is drawn at **380**
/// points on the panel too, `ViewThatFits` measures a candidate's *ideal* width, and the ideal
/// width of a wrapping `Text` is its whole single-line width — so the header would have stacked at
/// standard size for any task sentence past about thirty characters and moved every accusation
/// baseline for a row that fits perfectly well.
///
/// So the row candidate's title carries `.frame(idealWidth: <its longest word>, maxWidth:
/// .infinity)`. Its **ideal** is the word, which is the question the rule asks; its **maximum** is
/// the row, which is what pushes the dismissal to the trailing edge. And the `Spacer` that used to
/// do that job is gone, because a `Spacer`'s ideal width is infinite: a `ViewThatFits` measuring a
/// row containing one rejects it at every width and stacks always — the same regression, reached
/// from the other side.
///
/// ## What this suite measures, and what it leaves to the picture
///
/// It measures the number `ViewThatFits` really decides on — `fittingSize`, SwiftUI's own layout,
/// not an addition of design tokens. A first draft of this fold *did* add up the tokens, was 56
/// points wrong, and printed green over the very picture the bead was filed on.
///
/// What it cannot see is the largest text size: `@Environment` resolves inside a `body`, so a view
/// value built for measurement outside one reads the standard scale. That half is the re-recorded
/// `menuBarPopover.*.accessibilityLarge` baselines, read by eye — which is where the defect was
/// found and where focus-0q4 left the same half.
@Suite("The accusation header asks for its longest word, not its whole sentence")
@MainActor
struct AccusationHeaderWordWidthTests {
    /// Task sentences of very different lengths whose longest words are also different, so the
    /// two hypotheses — "the ideal tracks the word" and "the ideal tracks the sentence" — predict
    /// visibly different numbers.
    static let tasks: [String] = [
        "Ship",
        "Write the Q3 proposal",
        "Write the enormously long quarterly proposal for the board review meeting"
    ]

    /// **The assertion, and it is the repair stated as a number.** The row asks for its longest
    /// word plus a constant — the badge chip, the dismissal and the two gaps — and that constant
    /// does not move when the sentence grows by fifty characters.
    ///
    /// Before the repair the row's ideal width was the whole sentence plus the same constant, so
    /// the three cells below differed by hundreds of points rather than by the width of a word.
    @Test(
        "the header row's ideal width is its longest word plus a constant, not its sentence",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func theRowAsksForAWordAndNotASentence() {
        var furniture: [CGFloat] = []
        var measured = 0
        for task in Self.tasks {
            let presentation = AccusationFixture.rungTwo().withTask(task)
            let word = AccusationPanelView.headerTitleLongestWordWidth(
                presentation: presentation,
                scale: .standard
            )
            let row = AccusationPanelView.headerRowIdealWidth(presentation: presentation)
            measured += 1
            #expect(
                row >= word,
                "the row asks for \(row) points and its longest word alone is \(word)"
            )
            furniture.append(row - word)
        }
        // The constant is constant. One point of slack, because a hosting controller rounds.
        let spread = (furniture.max() ?? 0) - (furniture.min() ?? 0)
        #expect(
            spread <= 1,
            """
            the row's furniture measured \(furniture) across sentences of \
            \(Self.tasks.map(\.count)) characters — a spread of \(spread) points means the ideal \
            is tracking the sentence, and the header will stack wherever a task is long
            """
        )
        #expect(measured == Self.tasks.count)
        // And the fold is over sentences that really are different: a spread of zero would be
        // trivially satisfied by three copies of one string.
        #expect(Set(Self.tasks.map(\.count)).count == Self.tasks.count)
    }

    /// **The other half, and the one the bead was afraid of.** The row must still fit the panel it
    /// was designed at — 380 points, standard size — for the longest task the estate draws. A
    /// header that stacked there would move every accusation baseline for a column that fits.
    @Test(
        "the header still fits the panel it was designed at, for every sentence the estate draws",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func theRowSurvivesWhereItAlwaysFitted() {
        let available = CGFloat(NudgePanelController.contentWidth) - DesignTokens.decisionRuleInset
        for task in Self.tasks {
            let presentation = AccusationFixture.rungTwo().withTask(task)
            let row = AccusationPanelView.headerRowIdealWidth(presentation: presentation)
            #expect(
                row <= available,
                """
                the header asks for \(row) points inside a \(available)-point panel for \
                "\(task)" — it would stack at standard size and move every accusation baseline
                """
            )
        }
    }
}

extension AccusationPresentation {
    /// The same accusation about a different sentence. Test-only: the panel decides nothing, so a
    /// fixture that varies one field is varying the only thing this measurement is about.
    func withTask(_ task: String) -> AccusationPresentation {
        AccusationPresentation(
            rung: rung,
            voice: voice,
            task: task,
            subject: subject,
            dwelled: dwelled,
            returnTarget: returnTarget,
            snoozeRemaining: snoozeRemaining,
            hasOpenSession: hasOpenSession
        )
    }
}
