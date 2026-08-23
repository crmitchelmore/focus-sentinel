import FocusCore
import SwiftUI
import Testing

@testable import FocusUI

/// F-147, proved in pixels rather than promised in prose.
///
/// The promise is about the **priority hero**, which is why RD-07 put this row in e02 rather
/// than e01: *"a 180-character priority at the largest text size wraps, and is not truncated"*.
/// A promise like that cannot be kept by a `lineLimit(nil)` somebody remembered to write; it is
/// kept by an assertion that fails when somebody forgets.
///
/// The shape of every assertion here is the same, and it is deliberately about **height**:
///
/// * text that grew has to make the render **strictly taller**. A view that clipped instead
///   would render at the same height with fewer words in it, which is invisible to a colour
///   comparison and glaring to this one;
/// * a long sentence has to be strictly taller than a short one at the same size, which is
///   what proves the hero is wrapping rather than truncating to one line.
///
/// macOS has **no injectable Dynamic Type** — measured in e01: an injected `dynamicTypeSize` of
/// `.accessibility5` renders a paragraph at exactly the same pixel height as `.large` and
/// leaves `@ScaledMetric` untouched. `ShellTextScale` is the substitute the whole shell is
/// built on, and it is what the running app is handed too, so these renders are the app's own
/// text path and not a test-only imitation.
@Suite("Dynamic text resilience", .enabled(if: LocalizationLane.catalogsAreCompiled))
@MainActor
struct DynamicTextResilienceTests {
    /// The 180-character priority F-147 names, at the largest scale, against both controls.
    @Test("a 180-character priority wraps instead of truncating")
    func longPriorityWrapsAtTheLargestTextSize() throws {
        #expect(PriorityFixture.longIntent.count == 180)

        let longStandard = try render(
            PriorityHeroView(intent: PriorityFixture.longIntent),
            textScale: .standard,
            name: "hero.long.standard"
        )
        let longLarge = try render(
            PriorityHeroView(intent: PriorityFixture.longIntent),
            textScale: .accessibilityLarge,
            name: "hero.long.accessibilityLarge"
        )
        let shortLarge = try render(
            PriorityHeroView(intent: "Ship it"),
            textScale: .accessibilityLarge,
            name: "hero.short.accessibilityLarge"
        )

        // Growing the text grew the picture: nothing is pinned to a fixed height and quietly
        // clipping.
        #expect(
            longLarge.height > longStandard.height,
            "the hero did not grow at the largest text size (\(longStandard.height) → \(longLarge.height))"
        )
        // And the long sentence takes more lines than the short one at the same size, which is
        // what wrapping means and what truncation would hide.
        #expect(
            longLarge.height > shortLarge.height,
            "a 180-character priority is no taller than 'Ship it' at the same scale (\(shortLarge.height) vs \(longLarge.height))"
        )
    }

    /// The same promise, through the whole cockpit rather than the hero alone.
    ///
    /// The header is a `ViewThatFits` that drops the status badge onto a second line before the
    /// hero yields any width (R-27), so a cockpit carrying a long priority has to be taller
    /// than one carrying a short one — at both text sizes.
    @Test("the cockpit grows around a long priority at both text sizes")
    func cockpitGrowsAroundALongPriority() throws {
        for size in SnapshotTypeSize.allCases {
            let short = try render(
                CockpitView(state: PriorityFixture.cockpit(intent: "Ship it")),
                textScale: size.textScale,
                name: "cockpit.short.\(size.rawValue)"
            )
            let long = try render(
                CockpitView(state: PriorityFixture.cockpit(intent: PriorityFixture.longIntent)),
                textScale: size.textScale,
                name: "cockpit.long.\(size.rawValue)"
            )
            #expect(
                long.height > short.height,
                "the cockpit did not grow around a 180-character priority at \(size.rawValue) (\(short.height) → \(long.height))"
            )
        }
    }

    /// No surface may claim to honour the text scale and then ignore it.
    ///
    /// A component whose render is exactly the same height at both scales is not scaling — and
    /// that is a defect whether it happens because a font was hardcoded or because a frame was.
    @Test(
        "every priority surface honours the text scale it claims",
        arguments: PriorityComponent.allCases
    )
    func everySurfaceHonoursTheTextScale(component: PriorityComponent) throws {
        let standard = try SnapshotHarness.render(
            component.view,
            traits: .light,
            textScale: .standard,
            width: component.width,
            name: "\(component.rawValue).growth.standard"
        )
        let large = try SnapshotHarness.render(
            component.view,
            traits: .light,
            textScale: .accessibilityLarge,
            width: component.width,
            name: "\(component.rawValue).growth.accessibilityLarge"
        )

        #expect(
            large.height > standard.height,
            "\(component.rawValue) did not grow at the largest text size (\(standard.height) → \(large.height))"
        )
    }

    /// The hero is the largest role, and it is used exactly once — asserted structurally by
    /// `TypeHierarchyTests`. This is the same fact in pixels: the hero's own render has to be
    /// taller than the same sentence drawn at the next-largest role.
    @Test("the hero draws larger than the largest other role")
    func heroDrawsLargerThanEveryOtherRole() throws {
        let hero = try render(
            PriorityHeroView(intent: PriorityFixture.intent),
            textScale: .standard,
            name: "hero.role.priorityHero"
        )
        let largeTitle = try render(
            Text(verbatim: PriorityFixture.intent)
                .font(DesignTokens.font(.largeTitle))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true),
            textScale: .standard,
            name: "hero.role.largeTitle"
        )

        #expect(
            hero.height > largeTitle.height,
            "the priority hero is no taller than largeTitle (\(largeTitle.height) vs \(hero.height))"
        )
    }

    // MARK: -

    private func render(
        _ content: some View,
        textScale: ShellTextScale,
        name: String
    ) throws -> Snapshot {
        try SnapshotHarness.render(
            content,
            traits: .light,
            textScale: textScale,
            width: 520,
            name: name
        )
    }
}
