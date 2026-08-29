import FocusCore
import Foundation
import SwiftUI
import Testing

@testable import FocusUI

/// **The nudge surfaces are legible in dark mode, and a blank render can never pass** (focus-pq8).
///
/// ## The defect, and why every lane was green over it
///
/// `DesignTokens.Palette` mixes two kinds of colour and only one of them follows the injected
/// traits:
///
/// * `primaryText` is SwiftUI's `.primary` and `secondaryText` is `.secondary`, which resolve
///   against the environment's `colorScheme` — and `appearanceTraits(_:)` sets that. Under `.dark`
///   they go **white**.
/// * `windowBackground` and `separator` are `Color(nsColor:)` wrappers around AppKit dynamic
///   system colours, which resolve against `NSAppearance.current` and have never heard of the
///   injected traits. In a test process — and in any window whose `NSAppearance` was not set —
///   they stay **light**.
///
/// So the dark render is white text on a white background. `queryPanel.neutral.dark.standard.png`
/// is a committed baseline in which the only visible object is the blue "Yes, add it" capsule; the
/// question, both explanatory lines and the other two answers are all there, all white, all
/// invisible.
///
/// The snapshot lane could not see it. A baseline is whatever the code drew on the day it was
/// recorded, so a blank render was recorded as a blank baseline and every run since has compared
/// blank against blank and passed. `PNGCompare.areDistinct` did not help either: dark and light
/// *are* different pictures — the dark one has lost its text, which is precisely the difference.
///
/// ## What is asserted instead
///
/// Ink, against the same component's own light render. A panel that says the same words in dark
/// mode must draw about as much of them, and 0.29 units of ink against 4.52 is not a colour
/// scheme — it is a blank page. The threshold is a **fraction of the light render** rather than an
/// absolute figure, because the components differ enormously in how much they draw and an absolute
/// floor would either miss the small ones or fail the sparse ones.
@Suite("The nudge surfaces are legible in dark mode", .enabled(if: LocalizationLane.catalogsAreCompiled))
@MainActor
struct DarkModeLegibilityTests {
    static let panelWidth: CGFloat = 380

    /// A dark render must carry at least this share of its light counterpart's ink.
    ///
    /// Generous on purpose: dark and light genuinely differ, and a shell is allowed to draw a
    /// hairline separator in one and not the other. What it may not do is lose its sentences.
    /// Measured on the unfixed tree the three nudge surfaces scored 0.24 (queryPanel, 7127 ink
    /// pixels against 29151), 0.18 (accusationPanel, 35080 against 195505) and 0.12
    /// (menuBarPopover, 11056 against 92502) — what survives in each is the accent-coloured
    /// buttons and nothing else.
    static let minimumShareOfLightInk = 0.5

    /// Render one view twice, and report both ink counts.
    static func inkInBothSchemes(
        _ content: some View,
        width: CGFloat?,
        name: String
    ) throws -> (light: Int, dark: Int) {
        let light = try SnapshotHarness.render(
            content, traits: .light, width: width, name: "\(name).legibility.light"
        )
        let dark = try SnapshotHarness.render(
            content, traits: .dark, width: width, name: "\(name).legibility.dark"
        )
        return (PNGCompare.inkPixels(light.pixels), PNGCompare.inkPixels(dark.pixels))
    }

    static func expectLegible(_ label: String, _ ink: (light: Int, dark: Int)) {
        let share = ink.light == 0 ? 0 : Double(ink.dark) / Double(ink.light)
        #expect(ink.light > 0, "\(label): the light render drew nothing, so the test proves nothing")
        #expect(
            share >= Self.minimumShareOfLightInk,
            """
            \(label) is not legible in dark mode: the dark render carries \(ink.dark) ink pixels \
            against the light render's \(ink.light) — a share of \
            \(String(format: "%.2f", share)), below the required \(Self.minimumShareOfLightInk). \
            White text on a white background draws nothing but its accent-coloured buttons.
            """
        )
    }

    @Test("the question panel draws its question in dark mode")
    func queryPanelIsLegibleInDark() throws {
        Self.expectLegible(
            "queryPanel",
            try Self.inkInBothSchemes(
                QueryPanelView(presentation: QueryFixture.noNegativeBasis()),
                width: Self.panelWidth,
                name: "queryPanel"
            )
        )
    }

    @Test("the accusation panel draws its sentence in dark mode")
    func accusationPanelIsLegibleInDark() throws {
        Self.expectLegible(
            "accusationPanel",
            try Self.inkInBothSchemes(
                AccusationPanelView(presentation: AccusationFixture.rungTwo()) { _, _ in },
                width: Self.panelWidth,
                name: "accusationPanel"
            )
        )
    }

    @Test("the menu-bar popover draws its rows in dark mode")
    func menuBarPopoverIsLegibleInDark() throws {
        Self.expectLegible(
            "menuBarPopover",
            try Self.inkInBothSchemes(
                MenuBarPopoverView(presentation: MenuBarFixture.presentation()),
                width: 300,
                name: "menuBarPopover"
            )
        )
    }
}
