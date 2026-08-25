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

    /// A panel-shaped size for the placement fixtures: the committed width and a height in the
    /// band the real panels measure at. Placement is a pure function of whatever size it is
    /// handed, and the *height* is now content's to decide, so pinning these fixtures to a
    /// constant here keeps them about placement rather than about sizing.
    private static let placementSize = CGSize(
        width: NudgePanelController.contentWidth,
        height: 262
    )

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
            size: Self.placementSize,
            focusedWindowQuartzBounds: nil,
            screens: [Self.primary, Self.secondary]
        )
        let visible = Self.primary.visibleFrame

        #expect(placement.minX >= visible.minX)
        #expect(placement.minY >= visible.minY)
        #expect(placement.maxX <= visible.maxX)
        #expect(placement.maxY <= visible.maxY)
        #expect(placement.width == Double(Self.placementSize.width))
        #expect(placement.height == Double(Self.placementSize.height))
    }

    @Test("it follows the focused window onto a secondary display")
    func followsTheFocusedWindow() {
        // Quartz coordinates, origin at the top left of the primary — the flip is
        // `DisplayMapper`'s, and this is the fixture that proves the panel goes through it
        // rather than assuming display zero.
        let onSecondary = ScreenRect(x: 2100, y: 200, width: 800, height: 600)
        let placement = NudgePanelController.placement(
            size: Self.placementSize,
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
            size: Self.placementSize,
            focusedWindowQuartzBounds: offCanvas,
            screens: [Self.primary, Self.secondary]
        )

        #expect(placement.minX >= Self.primary.visibleFrame.minX)
        #expect(placement.maxY <= Self.primary.visibleFrame.maxY)
    }

    @Test("with no displays at all there is nowhere to put it, and it says so")
    func noDisplays() {
        let placement = NudgePanelController.placement(
            size: Self.placementSize,
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
            size: Self.placementSize,
            focusedWindowQuartzBounds: nil,
            screens: [tiny]
        )

        #expect(placement.width <= tiny.visibleFrame.width)
        #expect(placement.height <= tiny.visibleFrame.height)
        #expect(placement.minX >= tiny.visibleFrame.minX)
        #expect(placement.minY >= tiny.visibleFrame.minY)
    }

    // MARK: - The panel is the size of its content, and every action is reachable

    /// **What a nudge really says**, as the three values the shipping panels are built from.
    ///
    /// Deliberately *real* content rather than a placeholder: the defects this section exists to
    /// catch are layout ones, and a layout defect cannot be provoked by `EmptyView`. The strings
    /// are the ones the live drives photographed, so the fixture and the frame agree.
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

    /// Rung 3. The rung that asks for an explicit choice and does not auto-dismiss — so a
    /// clipped action here is an action the person is being *required* to reach and cannot.
    private static let recommitmentPresentation = AccusationPresentation(
        rung: .recommitment,
        task: "Write the Q3 proposal for Acme",
        subject: "com.chrismitchelmore.FocusDecoy",
        dwelled: .seconds(600),
        returnTarget: "com.apple.TextEdit"
    )

    /// The shipped tolerance, read from the type under test rather than restated here — a test
    /// that carried its own copy could go green while the app used a looser one.
    private static let sizeTolerance = NudgePanelController.sizeTolerance

    /// One cell of the cross product this epic's invariant is asserted over.
    struct PanelCase {
        let name: String
        let scale: ShellTextScale
        let offered: [String]
        let content: AnyView
    }

    static func cases() -> [PanelCase] {
        [SnapshotTypeSize.standard, .accessibilityLarge].flatMap { size -> [PanelCase] in
            let scale = size.textScale
            return [
                PanelCase(
                    name: "query.\(size.rawValue)",
                    scale: scale,
                    offered: queryPresentation.offeredAnswerIdentifiers,
                    content: AnyView(
                        QueryPanelView(presentation: queryPresentation).shellTextScale(scale)
                    )
                ),
                PanelCase(
                    name: "accusation.\(size.rawValue)",
                    scale: scale,
                    offered: accusationPresentation.offeredActionIdentifiers,
                    content: AnyView(
                        AccusationPanelView(presentation: accusationPresentation)
                            .shellTextScale(scale)
                    )
                ),
                PanelCase(
                    name: "recommitment.\(size.rawValue)",
                    scale: scale,
                    offered: recommitmentPresentation.offeredActionIdentifiers,
                    content: AnyView(
                        AccusationPanelView(presentation: recommitmentPresentation)
                            .shellTextScale(scale)
                    )
                )
            ]
        }
    }

    /// **THE assertion of this epic, over the whole cross product** (focus-vpu, focus-kby).
    ///
    /// `{query, accusation, recommitment} × {standard, accessibilityLarge}`, on the real window,
    /// with the real views and the compiled String Catalog, after the run loop has turned. The
    /// claim is not that the frame equals a constant — that claim passed a panel at y = −1186 and
    /// passed a panel whose Pause row was below the clip. It is that **every action the
    /// presentation says it is offering is somewhere a person can click**.
    ///
    /// Three things are asserted together and each catches a different way of failing:
    ///
    /// * the reading itself, which subsumes off-screen, oversize and clipping;
    /// * a real AppKit `hitTest` at the centre of every action, which is the question a mouse
    ///   asks;
    /// * the window's own height against the content's measured height, so a panel that is
    ///   reachable *because* the content was silently truncated is still a failure.
    @Test("every offered action is reachable, at both text sizes, on all three panels")
    func everyOfferedActionIsReachable() throws {
        for panelCase in Self.cases() {
            let controller = Self.controller()
            controller.update(content: panelCase.content)
            controller.show(presentationIsClear: true)
            defer { controller.hide() }
            Self.settle()

            let reading = controller.decisionSurfaceReading(offering: panelCase.offered)
            let frame = controller.frame

            // Printed, because the driver asked for the measured size of every combination and a
            // number that only exists inside an assertion is a number nobody read.
            print(
                "PANEL \(panelCase.name): \(frame.width) x \(frame.height) at "
                    + "(\(frame.x), \(frame.y)) — offered \(panelCase.offered.count), "
                    + "\(reading.summary)"
            )

            #expect(
                reading.everyActionIsReachable,
                "\(panelCase.name): \(reading.summary) in a \(frame.width) x \(frame.height) panel"
            )
            #expect(
                controller.hitTestsEveryAction(offering: panelCase.offered),
                "\(panelCase.name): a click at the centre of an offered action hits nothing"
            )
            #expect(reading.isVisible)
            #expect(reading.isWhollyOnAScreen)

            // The width is the commitment.
            #expect(abs(frame.width - NudgePanelController.contentWidth) <= Self.sizeTolerance)
            // The height is measured, never constant: the six cells must not all be one number.
            #expect(frame.height > 0)
            #expect(
                frame.height
                    <= NudgePanelController.maximumContentHeight(
                        screens: NudgePanelController.currentScreens()
                    ) + Self.sizeTolerance
            )
            // …and the window really is the size of the view inside it, rather than a right-sized
            // window with an overflowing hosting view clipped one rectangle further down.
            let content = try #require(controller.panel.contentView)
            let bounds = controller.panel.contentRect(forFrameRect: controller.panel.frame)
            #expect(abs(content.frame.width - bounds.width) <= Self.sizeTolerance)
            #expect(abs(content.frame.height - bounds.height) <= Self.sizeTolerance)
        }
    }

    /// **A constant height is what broke this, so a constant height must be visibly wrong.**
    ///
    /// The six cells wrap to genuinely different heights — the accusation at the largest
    /// accessibility text size is hundreds of points taller than the query at the default one —
    /// and a panel that answered one number for all of them would be the round-1 defect back.
    @Test("the panel is a different height for content of different heights")
    func theHeightIsMeasuredRatherThanDeclared() {
        var heights: [String: Double] = [:]
        for panelCase in Self.cases() {
            let controller = Self.controller()
            controller.update(content: panelCase.content)
            controller.show(presentationIsClear: true)
            defer { controller.hide() }
            Self.settle()
            heights[panelCase.name] = controller.frame.height
        }

        #expect(Set(heights.values).count > 1, "every panel is the same height: \(heights)")
        // The accessibility size is the same content in a bigger typeface. It cannot be shorter.
        for panel in ["query", "accusation", "recommitment"] {
            let standard = heights["\(panel).standard"] ?? 0
            let large = heights["\(panel).accessibilityLarge"] ?? 0
            #expect(large > standard, "\(panel) did not grow with its text: \(heights)")
        }
    }

    /// **The window never grows on its own again** (focus-x7d).
    ///
    /// The original defect was a window that was the right size when `show(…)` returned and 1542
    /// points tall one turn of the run loop later, because an `NSHostingView` used as a
    /// `contentView` publishes SwiftUI's own min/ideal/max sizes and the window resizes to obey
    /// them. The measurement is the panel's now, so the size the show sets is the size that
    /// survives the turn.
    @Test("the size a show sets is the size that survives the run loop")
    func theSizeSurvivesTheTurn() {
        let controller = Self.controller()
        controller.update(content: QueryPanelView(presentation: Self.queryPresentation))
        controller.show(presentationIsClear: true)
        defer { controller.hide() }

        let atShow = controller.frame
        Self.settle()
        let afterTheTurn = controller.frame

        #expect(abs(afterTheTurn.width - atShow.width) <= Self.sizeTolerance)
        #expect(abs(afterTheTurn.height - atShow.height) <= Self.sizeTolerance)
        // The window's own refusal, not just its current value: a window whose minimum is two
        // thousand points is a window that will grow again at the next provocation.
        #expect(
            controller.panel.contentMinSize.height
                <= NudgePanelController.absoluteMaximumHeight + Self.sizeTolerance
        )
    }

    /// **The off-screen half of the predicate, on the real window.**
    ///
    /// The original live measurement was y = −1186: right size, right content, nowhere a person
    /// could look. A panel moved off every display fails the reading with nothing else wrong with
    /// it, which is exactly the case a size comparison waved through.
    @Test("a panel moved off every display is not a decision surface")
    func aPanelOffScreenIsNotADecisionSurface() {
        let controller = Self.controller()
        controller.update(content: QueryPanelView(presentation: Self.queryPresentation))
        controller.show(presentationIsClear: true)
        defer { controller.hide() }
        Self.settle()

        let offered = Self.queryPresentation.offeredAnswerIdentifiers
        #expect(controller.decisionSurfaceReading(offering: offered).everyActionIsReachable)

        controller.panel.setFrameOrigin(NSPoint(x: 0, y: -1186))
        let reading = controller.decisionSurfaceReading(offering: offered)

        #expect(!reading.everyActionIsReachable)
        #expect(!reading.isWhollyOnAScreen)
        #expect(reading.isVisible)
        #expect(reading.unreachableActions.isEmpty)
    }

    /// A hidden panel is not a decision surface either, and it is a different failure from an
    /// off-screen one — which is why the reading names both rather than answering one `false`.
    @Test("a hidden panel is not a decision surface")
    func aHiddenPanelIsNotADecisionSurface() {
        let controller = Self.controller()
        controller.update(content: QueryPanelView(presentation: Self.queryPresentation))
        controller.show(presentationIsClear: true)
        Self.settle()
        controller.hide()

        let reading = controller.decisionSurfaceReading(
            offering: Self.queryPresentation.offeredAnswerIdentifiers
        )
        #expect(!reading.isVisible)
        #expect(!reading.everyActionIsReachable)
    }

    /// An action the panel is not offering is not required to be anywhere: the accusation
    /// withdraws "Back to …" when there is nowhere to return to (R-88), and a panel failed for a
    /// button it deliberately did not draw would make the invariant unsatisfiable.
    @Test("only the actions the presentation offers are required to be reachable")
    func onlyOfferedActionsAreRequired() {
        let noAnchor = AccusationPresentation(
            rung: .panel,
            task: "Write the Q3 proposal for Acme",
            subject: "com.chrismitchelmore.FocusDecoy",
            dwelled: .seconds(180)
        )
        let controller = Self.controller()
        controller.update(content: AccusationPanelView(presentation: noAnchor))
        controller.show(presentationIsClear: true)
        defer { controller.hide() }
        Self.settle()

        #expect(!noAnchor.offeredActionIdentifiers.contains(CorrectionAction.returnToTask.rawValue))
        #expect(
            controller.decisionSurfaceReading(
                offering: noAnchor.offeredActionIdentifiers
            ).everyActionIsReachable
        )
        // …and an action that really is not drawn is reported as unreported rather than passed.
        let reading = controller.decisionSurfaceReading(
            offering: AccusationPresentation.actionOrder.map(\.rawValue)
        )
        #expect(reading.unreportedActions == [CorrectionAction.returnToTask.rawValue])
        #expect(!reading.everyActionIsReachable)
    }

    /// **Overflow adapts the layout; it never clips** (focus-vpu).
    ///
    /// Content taller than the ceiling gets a scroll view rather than a clip rectangle — and,
    /// because an action a person has to scroll to is not an action in reach, the reading says so
    /// rather than passing a panel whose last button is below the fold. That is the whole
    /// difference between this and the shape it replaces: the previous fix laid 404 points of
    /// content into 190 points of window and reported success.
    @Test("content taller than the ceiling scrolls, and is not counted as reachable")
    func overflowScrollsRatherThanClipping() {
        // A policy nobody would write, which is the point: the panel must behave when the
        // content is pathological, not only when it is the fixture. The snooze spans are read
        // from `InterventionPolicy` by the shipping app and are injectable here, so twenty of
        // them at the largest text size is a real layout rather than a contrived view.
        let enormous = AccusationPresentation(
            rung: .recommitment,
            task: "Write the Q3 proposal for Acme",
            subject: "com.chrismitchelmore.FocusDecoy",
            dwelled: .seconds(600),
            returnTarget: "com.apple.TextEdit",
            snoozeDurations: (1...20).map { Duration.seconds($0 * 60) }
        )
        let controller = Self.controller()
        controller.update(
            content: AccusationPanelView(presentation: enormous)
                .shellTextScale(.accessibilityLarge)
        )
        controller.show(presentationIsClear: true)
        defer { controller.hide() }
        Self.settle()

        let ceiling = NudgePanelController.maximumContentHeight(
            screens: NudgePanelController.currentScreens()
        )
        let frame = controller.frame
        print("PANEL overflow: \(frame.width) x \(frame.height), ceiling \(ceiling)")

        // Clamped, and still on its display: a panel that grew to its content here would be the
        // 2212-point window again.
        #expect(abs(frame.height - ceiling) <= Self.sizeTolerance)
        let reading = controller.decisionSurfaceReading(offering: enormous.offeredActionIdentifiers)
        #expect(reading.isWhollyOnAScreen)

        // And the honest reading: the actions are down there somewhere, and this is not a surface
        // a question may be counted as delivered on.
        #expect(!reading.everyActionIsReachable)
        #expect(!reading.unreachableActions.isEmpty)
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
