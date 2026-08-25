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

    /// **The gate can close after the show, and the flag must not outlive it** (R-84, F-35).
    ///
    /// `fullScreenAuxiliaryFollowsThePresentationGate` above proves the flag is right *at every
    /// show*. This proves the harder half: that a panel which is **already on screen** when a
    /// presentation starts stops being eligible to join it. The panel is deliberately sticky —
    /// `hidesOnDeactivate` is `false`, so it waits for an answer — which is exactly why it can
    /// still be there when the space opens, and why P-130's measurement (a `.fullScreenAuxiliary`
    /// panel drawn plainly on top of a real full-screen space) is reachable without any second
    /// show ever happening.
    @Test("a panel already on screen loses the flag when a presentation claims the display")
    func withdrawingForAPresentationDropsTheFlag() {
        let controller = Self.controller()

        // The state the hazard needs: shown while the gate was clear, so it carries the flag,
        // and still on screen because nobody has answered it.
        controller.show(presentationIsClear: true)
        #expect(controller.properties.isFullScreenAuxiliary)
        #expect(controller.isVisible)
        #expect(controller.lastPresentationWasClear)

        // The presentation starts. No second show happens — this is the only thing that does.
        controller.withdrawForPresentation()

        #expect(
            !controller.properties.isFullScreenAuxiliary,
            "an on-screen panel kept the flag that lets it stomp a presentation"
        )
        #expect(!controller.isVisible, "the panel stayed on the display a presentation claimed")
        #expect(!controller.lastPresentationWasClear)

        // Everything else the base behaviour carries is untouched: withdrawing is not a reset.
        #expect(controller.properties.joinsAllSpaces)
        #expect(controller.properties.isStationary)
        #expect(controller.properties.ignoresCycle)
        #expect(controller.properties.isCorrect)
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

    // MARK: - The panel is the size it claims to be (focus-x7d)

    /// **What a nudge really says**, as the two values the shipping panels are built from.
    ///
    /// Deliberately *real* content rather than a placeholder: the defect this section exists to
    /// catch is a layout one, and a layout defect cannot be provoked by `EmptyView`. The strings
    /// are the ones the 19:26 live drive photographed, so the fixture and the frame agree.
    private static let queryPresentation = QueryPresentation(
        task: "Write the Q3 proposal for Acme",
        subject: "com.chrismitchelmore.FocusSentinel",
        reason: .noNegativeBasis,
        dwelled: .seconds(62)
    )

    private static let accusationPresentation = AccusationPresentation(
        rung: .panel,
        task: "Write the Q3 proposal for Acme",
        subject: "com.chrismitchelmore.FocusDecoy",
        dwelled: .seconds(180),
        returnTarget: "com.apple.TextEdit"
    )

    /// The shipped tolerance, read from the type under test rather than restated here — a test
    /// that carried its own copy could go green while the app used a looser one.
    private static let sizeTolerance = NudgePanelController.sizeTolerance
    /// An absolute ceiling on how much of the screen a nudge may take, independent of
    /// `contentSize`. Raising the constant cannot silence this half.
    private static let absoluteMaximumHeight: Double = 400

    /// **The assertion that would have caught focus-x7d**, and the reason it lives in the
    /// AppKit unit lane rather than anywhere else.
    ///
    /// A live drive at 19:26 measured the query panel at **380 × 2212** on a 1920 × 1080 screen.
    /// `screencapture -l <windowNumber>` read the window's *backing store* and showed the
    /// question rendering perfectly; `screencapture -R` at that same window's own coordinates
    /// showed a blank white slab, because the 190-point band the content occupies was somewhere
    /// in two thousand points of window the person could not see. Three existing proofs went
    /// green over it, and each was green for a different structural reason:
    ///
    /// * the live lane captured by window id, which proves a window **rendered**, never that a
    ///   person can **see** it;
    /// * `check-focus-steal.sh` asserts the panel *takes* nothing and never that it *shows*
    ///   anything;
    /// * the snapshot lane renders `QueryPanelView` standalone at a fixed size and never touches
    ///   an `NSPanel` at all.
    ///
    /// So the missing assertion is at the level of the window object, needs no grant of any
    /// kind, and is exactly this: **put the real content in, and the window is still the size it
    /// says it is.** `update(content:)` is the operation under test, because the hosting view is
    /// what drives the window's size and `update(content:)` is the only thing that changes it.
    @Test(
        "real nudge content never resizes the window",
        arguments: [true, false]
    )
    func realContentNeverResizesTheWindow(query: Bool) {
        let controller = Self.controller()

        if query {
            controller.update(content: QueryPanelView(presentation: Self.queryPresentation))
        } else {
            controller.update(
                content: AccusationPanelView(presentation: Self.accusationPresentation)
            )
        }

        let intended = NudgePanelController.contentSize
        let label = query ? "query" : "accusation"

        // The panel goes up exactly as a nudge does, and then **the run loop turns** — which is
        // the whole reason this defect survived three green proofs. Measured on the unfixed code:
        // the frame is a perfectly correct 380 × 190 the instant `update(content:)` and `show(…)`
        // return, and 380 × 1542 one turn later, when SwiftUI has been asked for its fitting
        // sizes and the window has resized itself to obey the `contentMinSize` they published. A
        // reading taken before that turn is a reading of the moment before the defect.
        controller.show(presentationIsClear: true)
        defer { controller.hide() }
        Self.settle()

        let frame = controller.frame

        #expect(
            abs(frame.width - Double(intended.width)) <= Self.sizeTolerance,
            """
            the \(label) panel settled at \(frame.width)pt wide, not \(intended.width)pt: \
            SwiftUI's fitting size is driving the window
            """
        )
        #expect(
            abs(frame.height - Double(intended.height)) <= Self.sizeTolerance,
            """
            the \(label) panel settled at \(frame.height)pt tall, not \(intended.height)pt: \
            the content band is somewhere the person cannot see it (focus-x7d)
            """
        )
        // The same fact without reference to the constant, so raising `contentSize` to make a
        // failure go away is not a route through this test.
        #expect(frame.height <= Self.absoluteMaximumHeight)

        // The window's own refusal, not just its current value: a window whose minimum is two
        // thousand points is a window that will grow again at the next provocation.
        #expect(controller.panel.contentMinSize.height <= Self.absoluteMaximumHeight)

        // The single reading a caller takes before it writes "asked" into a ledger.
        #expect(controller.isPresentedAtIntendedSize)
    }

    /// **One turn of the run loop**, which is where the defect lives.
    ///
    /// Grant-free and headless: no window server access, no screen recording, nothing this
    /// process has to be trusted for. It is simply the interval between "the app showed the
    /// nudge" and "a person looked at it", which is the interval every earlier proof skipped.
    /// `CFRunLoopRunInMode` rather than `RunLoop.run(until:)` because the latter needs a `Date`,
    /// and R-26 bans a bare `Date()` outside `DateProvider` — correctly, and this is not a
    /// question about the time of day. An interval is the honest argument: run the loop for
    /// three tenths of a second and give AppKit its turn.
    private static func settle() {
        CFRunLoopRunInMode(.defaultMode, 0.3, false)
    }

    /// The content is not merely *somewhere* in a right-sized window — it fills it.
    ///
    /// The window could be 380 × 190 with the hosting view laid out at 380 × 2212 inside it and
    /// the person would see the same blank slab, one clip rectangle further down. This asserts
    /// the view AppKit actually draws is the size of the content rect.
    @Test("the hosting view fills the panel rather than overflowing it")
    func hostingViewFillsThePanel() {
        let controller = Self.controller()
        controller.update(content: QueryPanelView(presentation: Self.queryPresentation))
        controller.show(presentationIsClear: true)
        defer { controller.hide() }
        Self.settle()

        guard let content = controller.panel.contentView else { return }
        let bounds = controller.panel.contentRect(forFrameRect: controller.panel.frame)

        #expect(abs(content.frame.width - bounds.width) <= Self.sizeTolerance)
        #expect(abs(content.frame.height - bounds.height) <= Self.sizeTolerance)
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
