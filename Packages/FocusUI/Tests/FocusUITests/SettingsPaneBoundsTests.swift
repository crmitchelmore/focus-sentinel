import AppKit
import FocusCore
import SwiftUI
import Testing

@testable import FocusUI

/// **The Settings panes, measured** (focus-nu6).
///
/// A surface lens reported that the Privacy pane could not be read at the shipping text size on
/// any display at any window width, and the source agreed with it: both panes carried a note
/// recording that their `ScrollView` had been **deleted on purpose** so that `ImageRenderer` would
/// produce a picture. The window's only size commitment was `minWidth: 460, minHeight: 520` — two
/// floors and no ceiling — so a column measuring 2 699 points opened a window 2 699 points tall.
///
/// These are the two readings that defect needed somebody to take, and neither of them is a
/// picture:
///
/// 1. how tall each pane's column really is, at both text sizes, through the same
///    `sizeThatFits(in:)` the nudge panel commits its own height with;
/// 2. whether the pane a person actually gets stays inside a display and scrolls when it cannot.
///
/// The first one is what makes the second worth having: if the columns were short, the container
/// would never be exercised and every assertion below would be vacuous.
@Suite("The Settings panes are readable on a display", .serialized)
@MainActor
struct SettingsPaneBoundsTests {
    static let storeURL = URL(filePath: "/Users/example/Library/Application Support/Focus.store")

    /// A 13-inch laptop, which is the display this defect is worst on and the one most people
    /// have. Passed in rather than read from `NSScreen`, so the reading is the same on the
    /// machine that runs the gate and the machine that reads the report.
    static let laptop = DisplayGeometry(
        displayID: 1,
        screenIndex: 0,
        isPrimary: true,
        frame: ScreenRect(x: 0, y: 0, width: 1470, height: 956),
        visibleFrame: ScreenRect(x: 0, y: 0, width: 1470, height: 918),
        backingScaleFactor: 2
    )

    static var ceiling: Double {
        ShellSurfaceBounds.settingsCeiling(screens: [Self.laptop]) ?? .greatestFiniteMagnitude
    }

    static func conditioned(_ view: some View, textScale: ShellTextScale) -> AnyView {
        AnyView(
            view
                .appearanceTraits(.light)
                .shellTextScale(textScale)
        )
    }

    static func height(_ view: some View, textScale: ShellTextScale) -> Double {
        NSHostingController(rootView: Self.conditioned(view, textScale: textScale))
            .sizeThatFits(
                in: CGSize(
                    width: ShellSurfaceBounds.settingsWidth,
                    height: CGFloat.greatestFiniteMagnitude
                )
            )
            .height
    }

    static func scrolls(_ view: some View, textScale: ShellTextScale, atHeight height: Double) -> Bool {
        let controller = NSHostingController(rootView: Self.conditioned(view, textScale: textScale))
        controller.view.frame = NSRect(
            x: 0,
            y: 0,
            width: ShellSurfaceBounds.settingsWidth,
            height: height
        )
        controller.view.layoutSubtreeIfNeeded()
        var found = false
        func walk(_ view: NSView) {
            if view is NSScrollView { found = true }
            view.subviews.forEach(walk)
        }
        walk(controller.view)
        return found
    }

    /// Each pane twice: the column it draws, and the pane a person is actually handed.
    static var panes: [(name: String, column: AnyView, pane: AnyView)] {
        [
            (
                "privacy",
                AnyView(PrivacySettingsView(storeURL: Self.storeURL).content),
                AnyView(PrivacySettingsView(storeURL: Self.storeURL, screens: [Self.laptop]))
            ),
            (
                "intervention",
                AnyView(InterventionSettingsView(settings: .init()).content),
                AnyView(InterventionSettingsView(settings: .init(), screens: [Self.laptop]))
            )
        ]
    }

    // MARK: - The defect, as a number

    /// **The reading that makes the rest of this suite non-vacuous.**
    ///
    /// At the largest accessibility text size at least one Settings pane's column is taller than a
    /// 13-inch laptop can show. Before this round that column *was* the window, so this is the
    /// exact measurement of what a person could not reach.
    ///
    /// If both panes ever shrink below the ceiling this goes red — not because a short pane is a
    /// defect, but because the container below would then be proved by nothing and somebody has to
    /// know that.
    @Test("at the shipping text size a Settings pane is taller than a laptop display")
    func aPaneOverflowsALaptopDisplay() {
        let overflowing = Self.panes.filter { pane in
            Self.height(pane.column, textScale: .accessibilityLarge) > Self.ceiling
        }
        #expect(
            !overflowing.isEmpty,
            """
            no Settings pane exceeds \(Self.ceiling) points at accessibilityLarge, so every \
            assertion about clamping and scrolling below this one is vacuous — re-read them
            """
        )
    }

    // MARK: - The commitment

    @Test(
        "no Settings pane is ever taller than the display allows",
        arguments: ShellTextScale.allCases
    )
    func noPaneExceedsTheCeiling(textScale: ShellTextScale) {
        for pane in Self.panes {
            let committed = Self.height(pane.pane, textScale: textScale)
            #expect(
                committed <= Self.ceiling + SurfaceSizeCommitments.tolerance,
                """
                the \(pane.name) pane opens \(committed) points tall at \(textScale.rawValue) on a \
                display that can show \(Self.ceiling): its lower half is unreachable
                """
            )
        }
    }

    /// **Clamping without scrolling is clipping.** A pane whose column exceeds the ceiling must
    /// come back with a scroll view, or the capability table and the verdict inspector at the
    /// bottom of the Privacy pane are laid out and unreachable — which is exactly what shipped.
    @Test(
        "a Settings pane that had to be clamped scrolls instead of cutting off",
        arguments: ShellTextScale.allCases
    )
    func aClampedPaneScrolls(textScale: ShellTextScale) {
        for pane in Self.panes {
            let column = Self.height(pane.column, textScale: textScale)
            guard column > Self.ceiling + SurfaceSizeCommitments.tolerance else { continue }
            let committed = Self.height(pane.pane, textScale: textScale)
            // Through a local `Bool`: handing the macro the view itself puts a page of SwiftUI
            // reflection into the failure message and buries the two numbers that matter.
            let scrolls = Self.scrolls(pane.pane, textScale: textScale, atHeight: committed)
            #expect(
                scrolls,
                """
                the \(pane.name) pane cut \(column) points of content down to \(committed) at \
                \(textScale.rawValue) and drew no scroll view
                """
            )
        }
    }

    /// The width is committed, so growing text grows the height — which is the thing the ceiling
    /// and the scroll are there to handle — rather than the window growing sideways off the
    /// display.
    @Test("a Settings pane commits its width rather than growing sideways")
    func thePanesCommitTheirWidth() {
        for pane in Self.panes {
            let size = NSHostingController(
                rootView: Self.conditioned(pane.pane, textScale: .accessibilityLarge)
            )
            .sizeThatFits(in: CGSize(width: 4_000, height: CGFloat.greatestFiniteMagnitude))
            #expect(
                abs(Double(size.width) - ShellSurfaceBounds.settingsWidth)
                    <= SurfaceSizeCommitments.tolerance,
                "offered 4000 points the \(pane.name) pane took \(Double(size.width))"
            )
        }
    }

    /// A pane that fits must not acquire a scroll bar it has no use for, and must not open at the
    /// height of the display either.
    @Test("a pane that fits is drawn whole")
    func aPaneThatFitsIsDrawnWhole() {
        for pane in Self.panes {
            let column = Self.height(pane.column, textScale: .standard)
            guard column <= Self.ceiling else { continue }
            let committed = Self.height(pane.pane, textScale: .standard)
            #expect(
                abs(committed - column) <= SurfaceSizeCommitments.tolerance,
                "the \(pane.name) pane's \(column)-point column opened \(committed) points tall"
            )
            let scrolls = Self.scrolls(pane.pane, textScale: .standard, atHeight: committed)
            #expect(!scrolls, "the \(pane.name) pane fits and drew a scroll bar anyway")
        }
    }
}
