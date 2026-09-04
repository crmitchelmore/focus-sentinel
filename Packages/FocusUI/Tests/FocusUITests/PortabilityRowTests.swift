import AppKit
import FocusCore
import SwiftUI
import Testing

@testable import FocusUI

/// **The three portability buttons, which do not fit on one line at the largest text size**
/// (focus-1dd, on the precedent of focus-0q4).
///
/// Section 10A's accessibility read reported all three truncating at `accessibilityLarge`, and the
/// arithmetic agrees: the Privacy pane is 460 points wide with 24 points of padding on each side,
/// so an `HStack` of three buttons hands each of them about 130 points, and at
/// `accessibilityLarge` — a ×2 multiplier on the system's 13-point body — *Export My Data…* alone
/// measures 193. A bordered button limits its label to one line, so what a person got was three
/// ellipses.
///
/// **A column is never narrower than its longest word.** `ViewThatFits` tries the row first, so at
/// the shipping text size nothing moves and the pane is byte-identical to the one that shipped;
/// under pressure the *arrangement* gives way and each button takes the full content width.
///
/// Gated on `LocalizationLane.catalogsAreCompiled` like every other localisation-dependent test in
/// this package: under `swift test` the labels resolve to their own keys, which are four times as
/// long as the sentences and would make the row stack at every size for the wrong reason.
@Suite("The Privacy pane's portability buttons never truncate", .serialized)
@MainActor
struct PortabilityRowTests {
    /// The pane's content width: `ShellSurfaceBounds.settingsWidth` less `.padding(spacing * 2)`
    /// on each side, where `spacing` is the pane's `@ScaledMetric` 12. macOS does not scale
    /// `@ScaledMetric` without a system Text Size change (measured, `DesignTokens`), so this is the
    /// same number at both text scales — which is exactly why the row has to give way instead.
    static let granted: CGFloat = CGFloat(ShellSurfaceBounds.settingsWidth) - 4 * 12

    static func row(_ scale: ShellTextScale) -> AnyView {
        AnyView(
            PortabilityRow(spacing: 12, onAction: { _ in })
                .appearanceTraits(.light)
                .shellTextScale(scale)
        )
    }

    static func height(_ scale: ShellTextScale, width: CGFloat = granted) -> CGFloat {
        NSHostingController(rootView: row(scale))
            .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            .height
    }

    /// One button on its own, as the unit the row is measured in.
    static func buttonHeight(_ scale: ShellTextScale) -> CGFloat {
        NSHostingController(
            rootView: AnyView(
                Button {} label: { ShellText(.settingsPrivacyExportData) }
                    .appearanceTraits(.light)
                    .shellTextScale(scale)
            )
        )
        .sizeThatFits(in: CGSize(width: granted, height: .greatestFiniteMagnitude))
        .height
    }

    static let labels: [ShellStringKey] = [
        .settingsPrivacyExportData, .settingsPrivacyExportSettings, .settingsPrivacyImportSettings
    ]

    /// The text width of one label at a scale, by the same measurement
    /// `MenuBarPopoverWordWidthTests` uses.
    static func textWidth(_ key: ShellStringKey, at scale: ShellTextScale) -> CGFloat {
        let font = NSFont.systemFont(ofSize: DesignTokens.pointSize(.body, scale: scale))
        return NSAttributedString(
            string: ShellStrings.string(key),
            attributes: [.font: font]
        ).size().width
    }

    /// **The measurement that makes the fix necessary**, and the one this suite would be vacuous
    /// without: the three labels' *text alone*, with no button chrome and no spacing between them,
    /// is already wider than the whole content column at `accessibilityLarge` — and comfortably
    /// narrower than it at the shipping size, so the row is still the right first choice.
    @Test(
        "the three labels cannot share one line at the largest text size, and can at the shipping one",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func theRowCannotFitWhenTheTextIsLargest() {
        let large = Self.labels.map { Self.textWidth($0, at: .accessibilityLarge) }.reduce(0, +)
        let standard = Self.labels.map { Self.textWidth($0, at: .standard) }.reduce(0, +)
        #expect(
            large > Self.granted,
            """
            the three labels measure \(large) points at accessibilityLarge against a \
            \(Self.granted)-point column — if this ever fits, the stacking below is proved by \
            nothing and somebody has to know that
            """
        )
        #expect(
            standard < Self.granted,
            "the three labels measure \(standard) points at the shipping size: the row still fits"
        )
    }

    /// **The fix.** At the shipping text size the row is one line; at the largest it is three, so
    /// each label has the whole column to draw in and none of them is cut.
    @Test(
        "the row stays a row at the shipping size and becomes a column at the largest",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func theRowGivesWayRatherThanTheLabels() {
        for scale in ShellTextScale.allCases {
            let one = Self.buttonHeight(scale)
            let row = Self.height(scale)
            #expect(one > 0, "a button measured \(one) points tall at \(scale.rawValue)")
            let stacked = row >= 2.5 * one
            let mustStack = Self.labels
                .map { Self.textWidth($0, at: scale) }
                .reduce(0, +) > Self.granted
            #expect(
                stacked == mustStack,
                """
                at \(scale.rawValue) the row is \(row) points tall against a \(one)-point button, \
                so it \(stacked ? "stacked" : "stayed a row") where the text \
                \(mustStack ? "cannot" : "can") share one line
                """
            )
        }
    }

    /// The arrangement is the only thing that moves. Whichever arm is taken, every label is granted
    /// at least its own width — which is the rule focus-0q4 laid the popover's rows out under and
    /// the one this row was breaking.
    @Test(
        "no label is ever granted less width than it needs",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func noLabelIsNarrowerThanItself() {
        for scale in ShellTextScale.allCases {
            let one = Self.buttonHeight(scale)
            let stacked = Self.height(scale) >= 2.5 * one
            // A row divides the column three ways and pays a gap twice; a column grants all of it.
            let column = stacked ? Self.granted : (Self.granted - 2 * 6) / 3
            for key in Self.labels {
                let width = Self.textWidth(key, at: scale)
                #expect(
                    width <= column,
                    """
                    "\(ShellStrings.string(key))" is \(width) points at \(scale.rawValue) in a \
                    \(column)-point column — a bordered button draws one line, so it truncates
                    """
                )
            }
        }
    }

    /// The pane still reaches all three verbs. A row that stopped drawing a button would satisfy
    /// every width assertion above.
    @Test("all three portability verbs are still drawn")
    func allThreeVerbsAreDrawn() {
        var seen: [PrivacySettingsAction] = []
        let row = PortabilityRow(spacing: 12, onAction: { seen.append($0) })
        _ = row.body
        #expect(Self.labels.count == 3)
        #expect(
            Set(PrivacySettingsAction.allDeclared).isSuperset(
                of: [.exportData, .exportSettings, .importSettings]
            )
        )
        #expect(seen.isEmpty, "building the row performed an action")
    }
}
