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

        controller.show(presentationIsClear: false, announcement: "")
        #expect(!controller.properties.isFullScreenAuxiliary)
        #expect(!controller.lastPresentationWasClear)
        controller.hide()

        controller.show(presentationIsClear: true, announcement: "")
        #expect(controller.properties.isFullScreenAuxiliary)
        #expect(controller.lastPresentationWasClear)
        controller.hide()

        // Back again: a panel that acquired the flag once and kept it would stomp the next
        // presentation, which is the failure P-130 photographed.
        controller.show(presentationIsClear: false, announcement: "")
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
        controller.show(presentationIsClear: true, announcement: "")
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

        let after = controller.show(presentationIsClear: true, announcement: "")
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

        // **The conjunction, in three values** (focus-rxc).
        //
        // This was `#expect(after.tookNothing(comparedTo: before))`, and it went red whenever
        // `NSWorkspace.frontmostApplication` answered `nil` at either end — a property of the
        // machine, measured in one gate run in six under contention. The guard inside
        // `tookNothing` is right to refuse a proof from an unmade measurement; a `Bool` simply had
        // no value left but `false` to refuse it with, so "could not measure" arrived as "the
        // panel stole focus".
        //
        // Readings 2, 3 and 4 are asserted above and are always available, so nothing is lost:
        // an unreadable frontmost costs this probe reading 1 and no more.
        let outcome = after.focusVerdict(comparedTo: before)
        if let banner = outcome.banner { print(banner) }
        #expect(!outcome.isBroken, "\(outcome.summary)")
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

    /// **A reading that could not be taken is not a reading that did not move** (focus-2vi).
    ///
    /// `NSWorkspace.shared.frontmostApplication` returns `nil` while the front is moving between
    /// two applications. `nil == nil` is `true`, so both conjunctions used to be satisfied by a
    /// pair in which reading 1 was never taken at either end — the strongest claim this epic
    /// makes, resting on a measurement nobody made. Every cell of {taken, not taken} × {taken,
    /// not taken} is below, so the guard cannot be half-applied.
    @Test("neither conjunction can be satisfied by a reading 1 that was never taken")
    func aMissingFrontmostReadingIsNotAnUnchangedOne() {
        func readings(_ frontmost: String?, visible: Bool) -> NudgePanelController.FocusReadings {
            NudgePanelController.FocusReadings(
                frontmostBundleIdentifier: frontmost,
                applicationIsActive: false,
                panelIsKey: false,
                applicationKeyWindowIsNil: true,
                panelIsVisible: visible
            )
        }

        let takenBefore = readings("com.example.Decoy", visible: false)
        let takenAfter = readings("com.example.Decoy", visible: true)
        let missingBefore = readings(nil, visible: false)
        let missingAfter = readings(nil, visible: true)

        #expect(takenBefore.frontmostWasRead)
        #expect(!missingBefore.frontmostWasRead)

        // taken / taken — the only cell that may make a claim.
        #expect(takenAfter.tookNothing(comparedTo: takenBefore))
        #expect(takenAfter.changedNothing(comparedTo: takenBefore))

        // The three cells in which reading 1 is missing at one end or both.
        #expect(!missingAfter.tookNothing(comparedTo: missingBefore))
        #expect(!missingAfter.changedNothing(comparedTo: missingBefore))
        #expect(!missingAfter.tookNothing(comparedTo: takenBefore))
        #expect(!missingAfter.changedNothing(comparedTo: takenBefore))
        #expect(!takenAfter.tookNothing(comparedTo: missingBefore))
        #expect(!takenAfter.changedNothing(comparedTo: missingBefore))
    }

    /// **The same cross product, in the three values the situation actually has** (focus-rxc).
    ///
    /// The suite above is right about what must not be *claimed* and says nothing about what a
    /// run should therefore **cost**. Every one of its three missing-reading cells returns
    /// `false`, and `false` is the defect's value — so the gate reported a `nil` from
    /// `NSWorkspace` as the panel stealing focus, in one run of six under contention.
    ///
    /// So the same sixteen-cell grid, judged by `focusVerdict`: the three cells where reading 1
    /// is missing must read **NOT TAKEN**, and — this is the half that keeps the repair from
    /// being a way to go quiet — a real theft must still read **broken**, including when reading
    /// 1 is missing at the same time. A missing reading 1 costs the probe reading 1. It does not
    /// buy an amnesty on readings 2, 3 and 4.
    @Test("an unreadable frontmost reads NOT TAKEN, and never hides a theft")
    func anUnreadableFrontmostReadsNotTaken() {
        func readings(
            _ frontmost: String?,
            active: Bool = false,
            key: Bool = false,
            keyWindowIsNil: Bool = true
        ) -> NudgePanelController.FocusReadings {
            NudgePanelController.FocusReadings(
                frontmostBundleIdentifier: frontmost,
                applicationIsActive: active,
                panelIsKey: key,
                applicationKeyWindowIsNil: keyWindowIsNil,
                panelIsVisible: true
            )
        }

        let taken = readings("com.example.Decoy")
        let missing = readings(nil)

        // The one cell that may make a claim.
        #expect(taken.focusVerdict(comparedTo: taken) == .holds)
        #expect(taken.changeVerdict(comparedTo: taken) == .holds)

        // The three in which reading 1 is missing at one end or both: not a failure, and not a
        // measurement either.
        for (after, before) in [(missing, missing), (missing, taken), (taken, missing)] {
            let outcome = after.focusVerdict(comparedTo: before)
            #expect(
                outcome == .notTaken(.frontmostApplicationUnavailable),
                "an unreadable frontmost was reported as \(outcome.summary)"
            )
            #expect(!outcome.isBroken, "a property of NSWorkspace failed the gate")
            #expect(after.changeVerdict(comparedTo: before).obstacle == .frontmostApplicationUnavailable)
        }

        // **The half that keeps this honest.** Readings 2, 3 and 4 are always available, so a
        // theft is still a theft while reading 1 is missing.
        for stolen in [
            readings(nil, active: true),
            readings(nil, key: true),
            readings(nil, keyWindowIsNil: false)
        ] {
            #expect(
                stolen.focusVerdict(comparedTo: missing).isBroken,
                "an unreadable frontmost bought an amnesty on a focus theft"
            )
        }

        // And a front that really moved is broken, not merely unproven.
        #expect(readings("com.example.Other").focusVerdict(comparedTo: taken).isBroken)
    }

    /// The serialised form the gate reads. A missing reading 1 is `null` — never `""`, which is
    /// a value and printed as `got: ('', '')` in the failure that named this defect.
    @Test("a missing reading 1 serialises as null rather than as an empty application")
    func aMissingFrontmostReadingSerialisesAsNotTaken() {
        let missing = NudgePanelController.FocusReadings(
            frontmostBundleIdentifier: nil,
            applicationIsActive: false,
            panelIsKey: false,
            applicationKeyWindowIsNil: true,
            panelIsVisible: true
        )
        let taken = NudgePanelController.FocusReadings(
            frontmostBundleIdentifier: "com.example.Decoy",
            applicationIsActive: false,
            panelIsKey: false,
            applicationKeyWindowIsNil: true,
            panelIsVisible: true
        )

        #expect(missing.dictionary["frontmostBundleIdentifier"] is NSNull)
        #expect(missing.dictionary["frontmostWasRead"] as? Bool == false)
        #expect(taken.dictionary["frontmostBundleIdentifier"] as? String == "com.example.Decoy")
        #expect(taken.dictionary["frontmostWasRead"] as? Bool == true)
    }

    @Test("the panel really appears, so a green reading is not a reading about nothing")
    func showingActuallyShows() {
        let controller = Self.controller()
        #expect(!controller.isVisible)

        let after = controller.show(presentationIsClear: true, announcement: "")
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
    /// **Both halves, and the panel draws the name** (focus-ebv). `returnTarget` is a display
    /// name too — it always was, which is how "Back to Pages" came to sit three lines under
    /// "com.apple.Safari" — so the fixtures below name applications rather than filing them.
    private static let sentinel = NudgeSubject.named(
        "com.chrismitchelmore.FocusSentinel",
        runningName: "Focus Sentinel"
    )!
    private static let decoy = NudgeSubject.named(
        "com.chrismitchelmore.FocusDecoy",
        runningName: "Focus Decoy"
    )!

    private static let queryPresentation = QueryPresentation(
        task: "Write the Q3 proposal for Acme",
        subject: sentinel,
        reason: .noNegativeBasis,
        dwelled: .seconds(62)
    )

    private static let accusationPresentation = AccusationPresentation(
        rung: .panel,
        task: "Write the Q3 proposal for Acme",
        subject: decoy,
        dwelled: .seconds(180),
        returnTarget: "TextEdit",
        hasOpenSession: true
    )

    /// The shipped tolerance, read from the type under test rather than restated here — a test
    /// that carried its own copy could go green while the app used a looser one.
    private static let sizeTolerance = NudgePanelController.sizeTolerance

    /// One cell of the cross product this epic's invariant is asserted over.
    struct PanelCase {
        let name: String
        let scale: ShellTextScale
        let offered: [String]
        /// The surface, **split the way the shipping controller splits it** (focus-din): the text
        /// size goes through `modified(_:)` so the measurement and all three renderings are in one
        /// environment, and the panel that is measured here is the panel that ships.
        let content: DecisionSurfaceLayout
        /// What the panel is carrying, so a case cannot be added without saying (focus-v0u).
        let showing: NudgePanelKind
    }

    static func cases() -> [PanelCase] {
        [SnapshotTypeSize.standard, .accessibilityLarge].flatMap { size -> [PanelCase] in
            let scale = size.textScale
            return [
                PanelCase(
                    name: "query.\(size.rawValue)",
                    scale: scale,
                    offered: queryPresentation.offeredAnswerIdentifiers,
                    content: QueryPanelView(presentation: queryPresentation)
                        .surfaceLayout
                        .modified { $0.shellTextScale(scale) },
                    showing: .question
                ),
                PanelCase(
                    name: "accusation.\(size.rawValue)",
                    scale: scale,
                    offered: accusationPresentation.offeredActionIdentifiers,
                    content: AccusationPanelView(presentation: accusationPresentation)
                        .surfaceLayout
                        .modified { $0.shellTextScale(scale) },
                    showing: .accusation
                )
            ]
        }
    }

    /// **THE assertion of this epic, over the whole cross product** (focus-vpu, focus-kby).
    ///
    /// `{query, accusation} × {standard, accessibilityLarge}`, on the real window,
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
            controller.update(showing: panelCase.showing, layout: panelCase.content)
            controller.show(presentationIsClear: true, announcement: "")
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

            // **Through the verdict, not the Bool** (focus-rxc). This panel's displays are the
            // live `NSScreen.screens`, and `isWhollyOnAScreen` is false with none attached —
            // which is a property of the machine, not of the panel. A headless run reads NOT
            // TAKEN and stays green; a panel that really is unreachable is still red.
            let verdict = DecisionSurfaceReachability.verdict(
                reading,
                screens: NudgePanelController.currentScreens()
            )
            if let banner = verdict.banner { print(banner) }
            #expect(
                !verdict.isBroken,
                "\(panelCase.name): \(verdict.summary) in a \(frame.width) x \(frame.height) panel"
            )
            #expect(
                controller.hitTestsEveryAction(offering: panelCase.offered),
                "\(panelCase.name): a click at the centre of an offered action hits nothing"
            )
            #expect(reading.isVisible)

            // The width is the commitment.
            #expect(abs(frame.width - NudgePanelController.contentWidth) <= Self.sizeTolerance)
            // The height is measured, never constant: the six cells must not all be one number.
            #expect(frame.height > 0)
            let ceiling = NudgePanelController.maximumContentHeight(
                screens: NudgePanelController.currentScreens()
            )
            #expect(frame.height <= ceiling + Self.sizeTolerance)
            // **And the ceiling itself, not only the panel against it** (focus-ocs). Comparing a
            // panel to a number the panel's own controller computed is green for a controller
            // that returned four thousand: the third instance of the shape the gate found in
            // `check-focus-steal.sh`. The limit is bounded here by the committed constant and by
            // what the display can hold with the panel's margins out.
            #expect(ceiling <= NudgePanelController.absoluteMaximumHeight + Self.sizeTolerance)
            if let display = DisplayMapper.primaryScreen(
                in: NudgePanelController.currentScreens()
            ) {
                let reserved = NudgePanelController.edgeMargin * 2
                #expect(
                    ceiling <= display.visibleFrame.height - reserved + Self.sizeTolerance,
                    "the panel's ceiling is taller than the display can hold: \(ceiling) > \(display.visibleFrame.height) - \(reserved)"
                )
            }
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
            controller.update(showing: panelCase.showing, layout: panelCase.content)
            controller.show(presentationIsClear: true, announcement: "")
            defer { controller.hide() }
            Self.settle()
            heights[panelCase.name] = controller.frame.height
        }

        #expect(Set(heights.values).count > 1, "every panel is the same height: \(heights)")
        // The accessibility size is the same content in a bigger typeface. It cannot be shorter.
        for panel in ["query", "accusation"] {
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
        controller.update(showing: .question, content: QueryPanelView(presentation: Self.queryPresentation))
        controller.show(presentationIsClear: true, announcement: "")
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
        controller.update(showing: .question, content: QueryPanelView(presentation: Self.queryPresentation))
        controller.show(presentationIsClear: true, announcement: "")
        defer { controller.hide() }
        Self.settle()

        let offered = Self.queryPresentation.offeredAnswerIdentifiers
        let onADisplay = DecisionSurfaceReachability.verdict(
            controller.decisionSurfaceReading(offering: offered),
            screens: NudgePanelController.currentScreens()
        )
        if let banner = onADisplay.banner { print(banner) }
        #expect(!onADisplay.isBroken, "\(onADisplay.summary)")

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
        controller.update(showing: .question, content: QueryPanelView(presentation: Self.queryPresentation))
        controller.show(presentationIsClear: true, announcement: "")
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
            subject: Self.decoy,
            dwelled: .seconds(180),
            hasOpenSession: true
        )
        let controller = Self.controller()
        controller.update(showing: .accusation, content: AccusationPanelView(presentation: noAnchor))
        controller.show(presentationIsClear: true, announcement: "")
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
    /// ## Why the reading alone was not this assertion
    ///
    /// This test used to assert `!everyActionIsReachable`, `!unreachableActions.isEmpty` and
    /// `!hitTestsEveryAction`, and every one of those is **equally true of a clipped panel**.
    /// A mutation that turned the scroll decision off — `let scrolls = measured.height > …`
    /// replaced by `false` — reinstated the clip rectangle and left the suite green, because
    /// nothing here could tell "the person can scroll to Pause" apart from "Pause is gone
    /// forever". The design rests on exactly that difference.
    ///
    /// So it is measured. The panel really has a scroll view; its document really is taller than
    /// the visible area; and the two actions the live drive found below the clip — Pause and
    /// Change priority — really do come into reach when it is scrolled to the bottom. A clipped
    /// panel has no scroll view to find and no position at which those actions exist.
    ///
    /// The un-scrolled reading is still asserted, and still says no: an action a person has to
    /// scroll to is not an action in reach at the moment the app is deciding whether the
    /// question was asked.
    @Test("content taller than the ceiling scrolls to its actions rather than clipping them")
    func overflowScrollsRatherThanClipping() {
        // A policy nobody would write, which is the point: the panel must behave when the
        // content is pathological, not only when it is the fixture. The snooze spans are read
        // from `InterventionPolicy` by the shipping app and are injectable here, so twenty of
        // them at the largest text size is a real layout rather than a contrived view.
        let enormous = AccusationPresentation(
            rung: .panel,
            task: "Write the Q3 proposal for Acme",
            subject: Self.decoy,
            dwelled: .seconds(600),
            returnTarget: "TextEdit",
            hasOpenSession: true,
            snoozeDurations: (1...20).map { Duration.seconds($0 * 60) }
        )
        let controller = Self.controller()
        controller.update(
            showing: .accusation,
            layout: AccusationPanelView(presentation: enormous)
                .surfaceLayout
                .modified { $0.shellTextScale(.accessibilityLarge) }
        )
        controller.show(presentationIsClear: true, announcement: "")
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
        // Not asserted as a `Bool`: with no display attached there is no screen for the panel to
        // be wholly on, and that is the machine's property rather than the panel's (focus-rxc).
        let onADisplay: ProbeOutcome = NudgePanelController.currentScreens().isEmpty
            ? .notTaken(.noDisplayAttached)
            : (reading.isWhollyOnAScreen ? .holds : .broken("the clamped panel left its display"))
        if let banner = onADisplay.banner { print(banner) }
        #expect(!onADisplay.isBroken, "\(onADisplay.summary)")

        // And the honest reading: the actions are down there somewhere, and this is not a surface
        // a question may be counted as delivered on.
        #expect(!reading.everyActionIsReachable)
        #expect(!reading.unreachableActions.isEmpty)
        // The second instrument agrees: a click where those actions are lands on nothing,
        // because they are not in the window at all.
        #expect(!controller.hitTestsEveryAction(offering: enormous.offeredActionIdentifiers))

        // --- scrolled, not clipped ------------------------------------------------------
        //
        // The two rows the live drive read below the clip. Under a clip they are gone; under a
        // scroll view they are one gesture away, and that is the whole distinction.
        let pause = CorrectionAction.pause.rawValue
        let changePriority = CorrectionAction.changePriority.rawValue
        #expect(reading.unreachableActions.contains(pause))
        #expect(reading.unreachableActions.contains(changePriority))

        let scrollViews = Self.scrollViews(in: controller.panel.contentView)
        #expect(
            scrollViews.count == 1,
            "the overflowing panel has no scroll view: its content is clipped, not scrolled"
        )
        guard let scroll = scrollViews.first, let document = scroll.documentView else { return }
        let visible = scroll.contentView.bounds.height
        #expect(
            document.frame.height > visible + Self.sizeTolerance,
            "the document is not taller than the visible area, so nothing was scrollable"
        )

        // Scroll to the bottom, the way a person would, and read again.
        scroll.contentView.scroll(to: NSPoint(x: 0, y: document.frame.height - visible))
        scroll.reflectScrolledClipView(scroll.contentView)
        Self.settle()

        let scrolled = controller.decisionSurfaceReading(
            offering: enormous.offeredActionIdentifiers
        )
        #expect(
            !scrolled.unreachableActions.contains(pause),
            "Pause never comes into reach, so the panel clipped it rather than scrolling to it"
        )
        #expect(
            !scrolled.unreachableActions.contains(changePriority),
            "Change priority never comes into reach: the content is clipped, not scrolled"
        )
        #expect(!scrolled.unreportedActions.contains(pause))
        #expect(!scrolled.unreportedActions.contains(changePriority))
    }

    /// **A reading of the previous nudge is not a reading of this one** (focus-kby).
    ///
    /// The frames come from a SwiftUI preference, and a preference is delivered when its value
    /// *changes*. Put a content in the panel that publishes no action frames at all and nothing
    /// is delivered — so the controller is still holding the last nudge's frames, which describe
    /// a layout nobody is looking at any more. Under default-deny the honest answer for one is
    /// "no frames", which reads as unreachable rather than as reachable-because-it-used-to-be.
    ///
    /// Measured on this toolchain: SwiftUI does deliver the empty value in that case, so the
    /// frames are cleared even without the generation check. The check is what holds if it ever
    /// does not — and `framesStampedWithAnotherLayoutAreRefused` below drives exactly that state
    /// rather than assuming it cannot happen.
    @Test("a new content that reports no frames does not inherit the last nudge's")
    func framesFromAReplacedLayoutAreRefused() {
        let presentation = AccusationPresentation(
            rung: .panel,
            task: "Write the Q3 proposal for Acme",
            subject: Self.decoy,
            dwelled: .seconds(600),
            returnTarget: "TextEdit",
            hasOpenSession: true
        )
        let offered = presentation.offeredActionIdentifiers
        let controller = Self.controller()
        controller.update(showing: .accusation, content: AccusationPanelView(presentation: presentation))
        controller.show(presentationIsClear: true, announcement: "")
        defer { controller.hide() }
        Self.settle()

        // The layout reported every action, and the reading is a reading of this layout.
        let onTheNudge = controller.decisionSurfaceReading(offering: offered)
        #expect(onTheNudge.unreportedActions.isEmpty)
        let verdict = DecisionSurfaceReachability.verdict(
            onTheNudge,
            screens: NudgePanelController.currentScreens()
        )
        if let banner = verdict.banner { print(banner) }
        #expect(!verdict.isBroken, "\(verdict.summary)")

        // Now something with no action targets in it at all.
        controller.update(
            showing: .accusation,
            undivided: Text(verbatim: "an interstitial with nothing to click")
        )

        let afterwards = controller.decisionSurfaceReading(offering: offered)
        #expect(
            afterwards.unreportedActions.sorted() == offered.sorted(),
            "the panel answered for a layout it had already replaced"
        )
        #expect(!afterwards.everyActionIsReachable)
        #expect(!controller.hitTestsEveryAction(offering: offered))
    }

    /// **Frames stamped with a layout the panel is not on are refused** (focus-kby).
    ///
    /// The state the generation exists for, produced directly: a content that publishes a
    /// perfectly ordinary action frame carrying somebody else's layout number. That is what a
    /// deferred preference delivery looks like from the controller's side — a non-empty set
    /// describing a layout it has already replaced — and it is the one shape the *replaced
    /// content* test above cannot manufacture, because SwiftUI happens to deliver the empty
    /// value promptly on this toolchain.
    ///
    /// Without the generation check the panel answers "reachable" for a button that is not in
    /// the window at all.
    @Test("frames stamped with another layout are refused rather than believed")
    func framesStampedWithAnotherLayoutAreRefused() {
        let controller = Self.controller()
        controller.update(showing: .accusation, undivided: StaleFrameReporter())
        controller.show(presentationIsClear: true, announcement: "")
        defer { controller.hide() }
        Self.settle()

        let reading = controller.decisionSurfaceReading(offering: [StaleFrameReporter.identifier])

        #expect(
            reading.unreportedActions == [StaleFrameReporter.identifier],
            "the panel believed a frame belonging to a layout it is not showing"
        )
        #expect(reading.unreachableActions.isEmpty)
        #expect(!reading.everyActionIsReachable)
        #expect(!controller.hitTestsEveryAction(offering: [StaleFrameReporter.identifier]))
    }

    /// Every `NSScrollView` in a view tree. SwiftUI's `ScrollView` is backed by one, and its
    /// presence is the only thing that distinguishes a panel that scrolls from a panel that
    /// clips.
    private static func scrollViews(in view: NSView?) -> [NSScrollView] {
        guard let view else { return [] }
        var found: [NSScrollView] = []
        if let scroll = view as? NSScrollView { found.append(scroll) }
        for subview in view.subviews { found += scrollViews(in: subview) }
        return found
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

        controller.show(presentationIsClear: true, announcement: "")
        // The same route AppKit takes for the Escape key on a panel whose content holds first
        // responder — which is why it is `cancelOperation(_:)` and not a key handler in a view.
        controller.panel.cancelOperation(nil)
        controller.hide()

        #expect(dismissals == 1)
    }
}

/// A content that publishes one action frame stamped with a layout number no panel will ever
/// be on.
///
/// It reports the preference directly rather than through `nudgeActionTarget(_:)`, because the
/// modifier reads the *current* generation out of the environment and the whole point here is a
/// frame that carries another one. The frame itself is ordinary: 100 x 20, well inside the
/// content, exactly where a real button would be.
private struct StaleFrameReporter: View {
    static let identifier = CorrectionAction.pause.rawValue
    static let staleGeneration = 999_999

    var body: some View {
        Color.clear
            .frame(width: 200, height: 100)
            .preference(
                key: NudgeActionFramesKey.self,
                value: NudgeActionFrameSet(
                    generation: Self.staleGeneration,
                    frames: [Self.identifier: CGRect(x: 16, y: 20, width: 100, height: 20)]
                )
            )
    }
}
