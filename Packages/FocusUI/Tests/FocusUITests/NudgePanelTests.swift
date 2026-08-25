import AppKit
import FocusCore
import Foundation
import SwiftUI
import Testing

@testable import FocusUI

/// **The highest-risk object in the programme, asserted on the real window** (R-89, T133).
///
/// Not on a mock. Every claim in R-89 is a claim about an `NSPanel` AppKit built, and a test
/// against a stand-in would prove that the stand-in was configured correctly. The panel is
/// constructed, shown and hidden inside the test process, which holds no grant of any kind —
/// which is the point: all four of R-89's focus readings are grant-free, and that is why they
/// can be a T1 criterion at all (SC-5).
///
/// The one property no instrument here can reach — that a person **typing** while the panel is
/// up keeps their keystrokes — needs a synthesised key event and therefore an Accessibility
/// grant, so it is the live lane's frame 17 and never a close condition (§4.9, R-97.2).
@Suite("The nudge panel takes nothing")
@MainActor
struct NudgePanelTests {
    /// AppKit will not build a window before the application object exists. Touching
    /// `NSApplication.shared` is what creates it in a test process; it is deliberately **not**
    /// activated, because an active test process would make every focus reading below vacuous.
    private static func application() -> NSApplication {
        NSApplication.shared
    }

    private static func controller() -> NudgePanelController {
        _ = application()
        return NudgePanelController()
    }

    // MARK: - R-89's six properties, on the real window object

    @Test("the panel is non-activating, key-capable, never main, and never hides on deactivate")
    func sixLoadBearingProperties() {
        let properties = Self.controller().properties

        #expect(properties.isNonActivating)
        #expect(properties.canBecomeKey)
        #expect(!properties.canBecomeMain)
        #expect(properties.becomesKeyOnlyIfNeeded)
        #expect(!properties.hidesOnDeactivate)
        #expect(properties.isCorrect)
    }

    @Test("the base collection behaviour joins all spaces, stays put and is never cycled to")
    func baseCollectionBehaviour() {
        let properties = Self.controller().properties

        #expect(properties.joinsAllSpaces)
        #expect(properties.isStationary)
        #expect(properties.ignoresCycle)
    }

    // MARK: - R-84: `.fullScreenAuxiliary` is conditional, and that is active code

    /// P-130 measured a `.fullScreenAuxiliary` panel drawn plainly on top of a real full-screen
    /// space, and the captured frame was read. The window server will not protect a
    /// presentation for us, so the flag is applied by the show path and only when the gate has
    /// already cleared.
    @Test("the full-screen-auxiliary flag follows the presentation gate, in both directions")
    func fullScreenAuxiliaryFollowsThePresentationGate() {
        let controller = Self.controller()

        controller.show(presentationIsClear: false)
        #expect(!controller.properties.isFullScreenAuxiliary)
        #expect(!controller.lastPresentationWasClear)
        controller.hide()

        controller.show(presentationIsClear: true)
        #expect(controller.properties.isFullScreenAuxiliary)
        #expect(controller.lastPresentationWasClear)
        controller.hide()

        // Back again: a panel that acquired the flag once and kept it would stomp the next
        // presentation, which is the failure P-130 photographed.
        controller.show(presentationIsClear: false)
        #expect(!controller.properties.isFullScreenAuxiliary)
        controller.hide()
    }

    @Test("the behaviour table itself never carries the flag unless the gate cleared")
    func behaviourTable() {
        #expect(!NudgePanel.baseCollectionBehavior.contains(.fullScreenAuxiliary))
        #expect(
            !NudgePanel.collectionBehavior(presentationIsClear: false)
                .contains(.fullScreenAuxiliary)
        )
        #expect(
            NudgePanel.collectionBehavior(presentationIsClear: true)
                .contains(.fullScreenAuxiliary)
        )
        // Everything the base behaviour carries survives the union, in both directions.
        for behaviour in [
            NudgePanel.collectionBehavior(presentationIsClear: false),
            NudgePanel.collectionBehavior(presentationIsClear: true)
        ] {
            #expect(behaviour.contains(.canJoinAllSpaces))
            #expect(behaviour.contains(.stationary))
            #expect(behaviour.contains(.ignoresCycle))
        }
    }

    // MARK: - R-89's four focus readings, after a real show

    /// **The assertion the whole epic rests on.**
    ///
    /// Reading 1 alone is what an earlier draft of the gate asserted, and P-139 measured a real
    /// focus theft it cannot see: `makeKeyAndOrderFront(nil)` on this style mask flips
    /// `NSApp.isActive` to `true` and installs a key window **while the frontmost application
    /// never moves**. Readings 2–4 are the ones that catch it, and none of them needs a grant.
    @Test("showing the panel changes none of the four grant-free focus readings")
    func showingTakesNothing() throws {
        let controller = Self.controller()

        let after = controller.show(presentationIsClear: true)
        defer { controller.hide() }

        let before = try #require(controller.readingsBeforeShow)

        // 1 — the coarse theft a person would see.
        #expect(after.frontmostBundleIdentifier == before.frontmostBundleIdentifier)
        // 2 — the activation P-139 measured, which reading 1 is blind to.
        #expect(!after.applicationIsActive)
        // 3 — the key window that would take the keyboard if the app were ever activated.
        #expect(!after.panelIsKey)
        // 4 — the same fact from the application's side.
        #expect(after.applicationKeyWindowIsNil)

        #expect(after.tookNothing(comparedTo: before))
    }

    /// `tookNothing(comparedTo:)` is the conjunction, and it must fail on **each** of the four
    /// readings independently — otherwise a gate built on it could go green over three of them.
    @Test("the conjunction fails on each reading on its own")
    func conjunctionIsATrueConjunction() {
        let before = NudgePanelController.FocusReadings(
            frontmostBundleIdentifier: "com.example.Decoy",
            applicationIsActive: false,
            panelIsKey: false,
            applicationKeyWindowIsNil: true,
            panelIsVisible: false
        )
        let clean = NudgePanelController.FocusReadings(
            frontmostBundleIdentifier: "com.example.Decoy",
            applicationIsActive: false,
            panelIsKey: false,
            applicationKeyWindowIsNil: true,
            panelIsVisible: true
        )
        #expect(clean.tookNothing(comparedTo: before))

        let movedFrontmost = NudgePanelController.FocusReadings(
            frontmostBundleIdentifier: "com.example.Other",
            applicationIsActive: false,
            panelIsKey: false,
            applicationKeyWindowIsNil: true,
            panelIsVisible: true
        )
        let activated = NudgePanelController.FocusReadings(
            frontmostBundleIdentifier: "com.example.Decoy",
            applicationIsActive: true,
            panelIsKey: false,
            applicationKeyWindowIsNil: true,
            panelIsVisible: true
        )
        let becameKey = NudgePanelController.FocusReadings(
            frontmostBundleIdentifier: "com.example.Decoy",
            applicationIsActive: false,
            panelIsKey: true,
            applicationKeyWindowIsNil: true,
            panelIsVisible: true
        )
        let installedKeyWindow = NudgePanelController.FocusReadings(
            frontmostBundleIdentifier: "com.example.Decoy",
            applicationIsActive: false,
            panelIsKey: false,
            applicationKeyWindowIsNil: false,
            panelIsVisible: true
        )

        #expect(!movedFrontmost.tookNothing(comparedTo: before))
        #expect(!activated.tookNothing(comparedTo: before))
        #expect(!becameKey.tookNothing(comparedTo: before))
        #expect(!installedKeyWindow.tookNothing(comparedTo: before))
    }

    @Test("the panel really appears, so a green reading is not a reading about nothing")
    func showingActuallyShows() {
        let controller = Self.controller()
        #expect(!controller.isVisible)

        let after = controller.show(presentationIsClear: true)
        #expect(controller.isVisible)
        #expect(after.panelIsVisible)

        controller.hide()
        #expect(!controller.isVisible)
    }

    // MARK: - Placement, as a pure function over injected displays

    private static func display(
        index: Int,
        isPrimary: Bool,
        frame: ScreenRect,
        visibleFrame: ScreenRect
    ) -> DisplayGeometry {
        DisplayGeometry(
            displayID: index + 1,
            screenIndex: index,
            isPrimary: isPrimary,
            frame: frame,
            visibleFrame: visibleFrame,
            backingScaleFactor: 2
        )
    }

    private static let primary = display(
        index: 0,
        isPrimary: true,
        frame: ScreenRect(x: 0, y: 0, width: 1920, height: 1080),
        // The menu bar and the Dock, excluded — which is what makes "never over the menu bar" a
        // property of the arithmetic rather than a rule somebody has to remember.
        visibleFrame: ScreenRect(x: 0, y: 60, width: 1920, height: 995)
    )

    private static let secondary = display(
        index: 1,
        isPrimary: false,
        frame: ScreenRect(x: 1920, y: 0, width: 1440, height: 900),
        visibleFrame: ScreenRect(x: 1920, y: 0, width: 1440, height: 875)
    )

    @Test("the panel is placed inside the visible frame, never over the menu bar")
    func placedInsideVisibleFrame() {
        let placement = NudgePanelController.placement(
            size: NudgePanelController.contentSize,
            focusedWindowQuartzBounds: nil,
            screens: [Self.primary, Self.secondary]
        )
        let visible = Self.primary.visibleFrame

        #expect(placement.minX >= visible.minX)
        #expect(placement.minY >= visible.minY)
        #expect(placement.maxX <= visible.maxX)
        #expect(placement.maxY <= visible.maxY)
        #expect(placement.width == Double(NudgePanelController.contentSize.width))
        #expect(placement.height == Double(NudgePanelController.contentSize.height))
    }

    @Test("it follows the focused window onto a secondary display")
    func followsTheFocusedWindow() {
        // Quartz coordinates, origin at the top left of the primary — the flip is
        // `DisplayMapper`'s, and this is the fixture that proves the panel goes through it
        // rather than assuming display zero.
        let onSecondary = ScreenRect(x: 2100, y: 200, width: 800, height: 600)
        let placement = NudgePanelController.placement(
            size: NudgePanelController.contentSize,
            focusedWindowQuartzBounds: onSecondary,
            screens: [Self.primary, Self.secondary]
        )

        #expect(placement.minX >= Self.secondary.visibleFrame.minX)
        #expect(placement.maxX <= Self.secondary.visibleFrame.maxX)
    }

    @Test("a window on no display falls back to the primary rather than to nowhere")
    func windowOnNoDisplayFallsBackToPrimary() {
        let offCanvas = ScreenRect(x: -9000, y: -9000, width: 10, height: 10)
        let placement = NudgePanelController.placement(
            size: NudgePanelController.contentSize,
            focusedWindowQuartzBounds: offCanvas,
            screens: [Self.primary, Self.secondary]
        )

        #expect(placement.minX >= Self.primary.visibleFrame.minX)
        #expect(placement.maxY <= Self.primary.visibleFrame.maxY)
    }

    @Test("with no displays at all there is nowhere to put it, and it says so")
    func noDisplays() {
        let placement = NudgePanelController.placement(
            size: NudgePanelController.contentSize,
            focusedWindowQuartzBounds: nil,
            screens: []
        )
        #expect(placement == .zero)
    }

    @Test("a panel larger than the space is clamped to it rather than overflowing")
    func clampedToASmallDisplay() {
        let tiny = Self.display(
            index: 0,
            isPrimary: true,
            frame: ScreenRect(x: 0, y: 0, width: 200, height: 120),
            visibleFrame: ScreenRect(x: 0, y: 0, width: 200, height: 120)
        )
        let placement = NudgePanelController.placement(
            size: NudgePanelController.contentSize,
            focusedWindowQuartzBounds: nil,
            screens: [tiny]
        )

        #expect(placement.width <= tiny.visibleFrame.width)
        #expect(placement.height <= tiny.visibleFrame.height)
        #expect(placement.minX >= tiny.visibleFrame.minX)
        #expect(placement.minY >= tiny.visibleFrame.minY)
    }

    // MARK: - Escape

    @Test("Escape dismisses the panel, because every surface is dismissible (D-07)")
    func escapeDismisses() {
        _ = Self.application()
        let controller = NudgePanelController()
        var dismissals = 0
        controller.onDismiss = { dismissals += 1 }

        controller.show(presentationIsClear: true)
        // The same route AppKit takes for the Escape key on a panel whose content holds first
        // responder — which is why it is `cancelOperation(_:)` and not a key handler in a view.
        controller.panel.cancelOperation(nil)
        controller.hide()

        #expect(dismissals == 1)
    }
}
