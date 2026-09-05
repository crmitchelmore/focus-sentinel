import Foundation
import Testing

@testable import FocusCore

/// **A decision surface whose Pause button is below the fold is not a decision surface**
/// (focus-vpu, focus-kby).
///
/// ## The predicate this replaces
///
/// `isPresentedAtIntendedSize` asked whether the window's frame equalled a constant. It was the
/// wrong question in both directions, and each direction shipped a defect:
///
/// * a live drive measured the query panel at 380 × 2212 at y = **−1186** — off screen as well as
///   oversized — and a size comparison cannot see where a window is;
/// * the fix pinned the window to a constant 380 × 190 without shrinking or scrolling the
///   content, so an accusation needing 237 points was laid out into 190 and clipped: at the
///   default text size the title was cut through its first line and **Pause** and **Change
///   priority** were below the clip and unreachable — and `isPresentedAtIntendedSize` returned
///   `true` for every clipped case, because the frame really was the constant.
///
/// One predicate subsumes all three failures: the surface is visible, its frame lies inside a
/// display's visible frame, and **every** offered action has a non-empty frame inside the content
/// the person can see. These are its fixtures; `NudgePanelTests` runs the same predicate against
/// the real window with the real views at both text sizes.
@Suite("Every offered action is reachable, or the surface is not one")
struct DecisionSurfaceReachabilityTests {
    static let screen = DisplayGeometry(
        displayID: 1,
        screenIndex: 0,
        isPrimary: true,
        frame: ScreenRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: ScreenRect(x: 0, y: 60, width: 1920, height: 995),
        backingScaleFactor: 2
    )

    /// A panel in the top trailing corner, 380 wide and 262 tall — the wrapped height of the
    /// recommitment rung at the standard text size.
    static let panelFrame = ScreenRect(x: 1516, y: 769, width: 380, height: 262)
    static let contentBounds = ScreenRect(x: 0, y: 0, width: 380, height: 262)

    static let offered = ["returnToTask", "thisIsRelevant", "notThisTime", "snooze", "pause", "changePriority"]

    /// Six rows stacked down the content, all inside it. The shape a panel sized to its content
    /// actually produces.
    static var everyActionLaidOut: [ActionHitTarget] {
        offered.enumerated().map { index, identifier in
            ActionHitTarget(
                identifier: identifier,
                frame: ScreenRect(
                    x: 16,
                    y: 80 + Double(index) * 30,
                    width: 348,
                    height: 24
                )
            )
        }
    }

    static func evaluate(
        isVisible: Bool = true,
        surfaceFrame: ScreenRect = Self.panelFrame,
        screens: [DisplayGeometry] = [Self.screen],
        contentBounds: ScreenRect = Self.contentBounds,
        targets: [ActionHitTarget] = Self.everyActionLaidOut,
        offering: [String] = Self.offered
    ) -> DecisionSurfaceReading {
        DecisionSurfaceReachability.evaluate(
            isVisible: isVisible,
            surfaceFrame: surfaceFrame,
            screens: screens,
            contentBounds: contentBounds,
            actionTargets: targets,
            offering: offering
        )
    }

    @Test("a panel on a display with every action laid out inside it is reachable")
    func theGoodCase() {
        let reading = Self.evaluate()

        #expect(reading.everyActionIsReachable)
        #expect(reading.isVisible)
        #expect(reading.isWhollyOnAScreen)
        #expect(reading.unreportedActions.isEmpty)
        #expect(reading.unreachableActions.isEmpty)
        #expect(reading.summary == "every offered action is reachable")
    }

    // MARK: - The three defects, one fixture each

    /// **focus-vpu, read on screen.** The window is exactly the size it claims; two actions are
    /// laid out past the bottom of it. This is the case the constant-size check called healthy.
    @Test("an action below the fold makes the surface unreachable even at the agreed size")
    func clippedActionsAreUnreachable() {
        // 190pt of window, six rows ending at 260: the last three fall off the bottom.
        let clipped = ScreenRect(x: 0, y: 0, width: 380, height: 190)
        let reading = Self.evaluate(
            surfaceFrame: ScreenRect(x: 1516, y: 841, width: 380, height: 190),
            contentBounds: clipped
        )

        #expect(!reading.everyActionIsReachable)
        #expect(reading.unreachableActions == ["snooze", "pause", "changePriority"])
        #expect(reading.isVisible)
        #expect(reading.isWhollyOnAScreen)
        #expect(reading.summary.contains("pause"))
    }

    /// **The y = −1186 case.** Right size, right content, nowhere a person could look.
    @Test("a surface off every display is unreachable however well laid out it is")
    func offScreenIsUnreachable() {
        let reading = Self.evaluate(
            surfaceFrame: ScreenRect(x: 1516, y: -1186, width: 380, height: 262)
        )

        #expect(!reading.everyActionIsReachable)
        #expect(!reading.isWhollyOnAScreen)
        // Nothing else is wrong with it, which is precisely why a check of the other terms
        // passed this window.
        #expect(reading.unreachableActions.isEmpty)
        #expect(reading.unreportedActions.isEmpty)
    }

    /// Half on, half off. A window whose bottom edge hangs below the visible frame has its
    /// bottom row of buttons under the Dock.
    @Test("a surface hanging off the edge of its display is unreachable")
    func partiallyOffScreenIsUnreachable() {
        let reading = Self.evaluate(
            surfaceFrame: ScreenRect(x: 1516, y: -10, width: 380, height: 262)
        )

        #expect(!reading.isWhollyOnAScreen)
        #expect(!reading.everyActionIsReachable)
    }

    @Test("a surface that is not on screen at all is unreachable")
    func invisibleIsUnreachable() {
        #expect(!Self.evaluate(isVisible: false).everyActionIsReachable)
    }

    @Test("with no displays there is nowhere for a surface to be reachable")
    func noDisplays() {
        #expect(!Self.evaluate(screens: []).everyActionIsReachable)
    }

    // MARK: - The actions themselves

    /// **The V06 case: the answers were ENTIRELY ABSENT.** An action that drew nothing reports no
    /// frame at all, which is a different defect from one that drew somewhere unreachable — and
    /// the reading names which.
    @Test("an offered action that drew nothing is reported as unreported, not as reachable")
    func anActionThatNeverDrewIsNotReachable() {
        let missing = Self.everyActionLaidOut.filter { $0.identifier != "pause" }
        let reading = Self.evaluate(targets: missing)

        #expect(!reading.everyActionIsReachable)
        #expect(reading.unreportedActions == ["pause"])
        #expect(reading.unreachableActions.isEmpty)
    }

    /// A zero-sized frame is a button a click cannot land on, whatever the layout thinks.
    @Test("an action laid out at zero size is unreachable")
    func aCollapsedActionIsUnreachable() {
        var targets = Self.everyActionLaidOut
        targets[0] = ActionHitTarget(
            identifier: "returnToTask",
            frame: ScreenRect(x: 16, y: 80, width: 0, height: 0)
        )
        let reading = Self.evaluate(targets: targets)

        #expect(!reading.everyActionIsReachable)
        #expect(reading.unreachableActions == ["returnToTask"])
    }

    /// An action reported but never offered is nobody's business: a presentation that withdraws
    /// "Back to …" because there is nowhere to return to must not be failed for the button it
    /// deliberately did not draw.
    @Test("only the actions actually offered are required to be reachable")
    func onlyOfferedActionsCount() {
        let withoutReturn = Self.offered.filter { $0 != "returnToTask" }
        let clipped = ScreenRect(x: 0, y: 0, width: 380, height: 110)
        // Only the first action fits in this content; asking for only that one passes.
        let reading = Self.evaluate(contentBounds: clipped, offering: ["returnToTask"])

        #expect(reading.everyActionIsReachable)
        #expect(Self.evaluate(offering: withoutReturn).everyActionIsReachable)
    }

    /// **A surface offering nothing is not a decision surface** (focus-6pr.4), and the two ways
    /// of not being one are two readings.
    ///
    /// ## Red before
    ///
    /// This test asserted `everyActionIsReachable` — `true` — for the first line below, on the
    /// argument that an empty offer is *"not unreachable either"*. That was the vacuity: every
    /// conjunct of the predicate is satisfied by a surface offering nothing, so "every one of no
    /// actions is reachable" answered yes, and `NudgeHost` charged a badge accusation on it in
    /// the state e07a's popover ruling creates — an accusation drawn beside a question, which is
    /// the pinned decision, with the accusation's corrections scrolling in the context. Nobody
    /// could press one of them; the app spent one of the day's six accusations and one of its
    /// eight interruptions for it.
    ///
    /// The half of the old ruling that was right is the second line, and it is why `standing`
    /// asks the geometry first: an empty offer must not wave a panel through from off the edge of
    /// the world, so a surface at y = −1186 offering nothing reads `unreadable` and not
    /// `notOffered`.
    @Test("an empty offer is not a decision surface, and is still held to the geometry")
    func anEmptyOfferIsNotADecisionSurface() {
        let offeringNothing = Self.evaluate(targets: [], offering: [])
        #expect(offeringNothing.standing == .notOffered)
        #expect(
            !offeringNothing.everyActionIsReachable,
            "a surface offering nothing was read as one every action of which is reachable"
        )
        #expect(offeringNothing.summary == "the surface is offering nothing to decide on")

        let offTheWorld = Self.evaluate(
            surfaceFrame: ScreenRect(x: 1516, y: -1186, width: 380, height: 262),
            targets: [],
            offering: []
        )
        #expect(offTheWorld.standing == .unreadable)
        #expect(!offTheWorld.everyActionIsReachable)
    }

    /// **The three answers are three, and each one is reached** (focus-6pr.4).
    ///
    /// The vocabulary folded rather than sampled: a case joining or leaving
    /// `DecisionSurfaceStanding` fails here, and a fold that covered only two of the three would
    /// prove nothing about the one this round added.
    @Test("every standing a reading can have is produced by some reading")
    func everyStandingIsReached() {
        let readings: [DecisionSurfaceStanding: DecisionSurfaceReading] = [
            .reachable: Self.evaluate(),
            .notOffered: Self.evaluate(targets: [], offering: []),
            .unreadable: Self.evaluate(isVisible: false)
        ]
        for standing in DecisionSurfaceStanding.allCases {
            let reading = readings[standing]
            #expect(reading != nil, "no reading in this fold stands at \(standing.rawValue)")
            #expect(reading?.standing == standing)
        }
        #expect(DecisionSurfaceStanding.allCases.count == readings.count)
        // And the `Bool` is exactly the `reachable` arm, in both directions.
        for (standing, reading) in readings {
            #expect(reading.everyActionIsReachable == (standing == .reachable))
        }
    }

    /// **A content area of nothing contains nothing** — and the action inside it is a real one.
    ///
    /// The zero-sized action was doing all the work here. `frame.isEmpty || !contains(…)`
    /// short-circuits on an empty frame, so with a 0 × 0 button the containment test was never
    /// reached at all and `guard !outer.isEmpty else { return false }` could be replaced by
    /// `return true` with the suite still green. The action below is a perfectly ordinary
    /// 348 × 24 row; the *container* is what has collapsed, and a button cannot be inside a
    /// content area that has no area.
    @Test("a collapsed content area contains no action at all, however well drawn the action is")
    func aCollapsedContentAreaContainsNothing() {
        let realButton = ActionHitTarget(
            identifier: "pause",
            frame: ScreenRect(x: 16, y: 80, width: 348, height: 24)
        )
        #expect(!realButton.frame.isEmpty, "the fixture must not short-circuit on an empty frame")

        let reading = Self.evaluate(
            contentBounds: ScreenRect(x: 0, y: 0, width: 0, height: 0),
            targets: [realButton],
            offering: ["pause"]
        )

        #expect(!reading.everyActionIsReachable)
        #expect(reading.unreachableActions == ["pause"])

        // The zero-sized case still holds, and now says what it is about: an action that drew
        // nothing is out of reach whatever container it is in.
        let collapsedAction = Self.evaluate(
            targets: [
                ActionHitTarget(
                    identifier: "pause",
                    frame: ScreenRect(x: 16, y: 80, width: 0, height: 0)
                )
            ],
            offering: ["pause"]
        )
        #expect(collapsedAction.unreachableActions == ["pause"])
    }

    /// The same guard on the other side of the predicate: a display with no visible area is not a
    /// display a surface can be wholly on. It is the reading a screen list gives while the
    /// machine is waking, and answering "yes, it is on that one" would pass every panel on it.
    @Test("a display with no visible area holds no surface")
    func aCollapsedDisplayHoldsNothing() {
        let collapsed = DisplayGeometry(
            displayID: 1,
            screenIndex: 0,
            isPrimary: true,
            frame: ScreenRect(x: 0, y: 0, width: 0, height: 0),
            visibleFrame: ScreenRect(x: 0, y: 0, width: 0, height: 0),
            backingScaleFactor: 2
        )
        let reading = Self.evaluate(screens: [collapsed])

        #expect(!reading.isWhollyOnAScreen)
        #expect(!reading.everyActionIsReachable)
    }

    /// One point of tolerance, and not one point more: the defect this exists to catch overshot
    /// by two thousand points, and a fudge factor big enough to hide a button would be one big
    /// enough to hide the defect.
    @Test("the tolerance admits a rounding difference and not a clipped row")
    func toleranceIsRoundingOnly() {
        var targets = Self.everyActionLaidOut
        targets[0] = ActionHitTarget(
            identifier: "returnToTask",
            frame: ScreenRect(x: 16, y: 80, width: 348.4, height: 24)
        )
        #expect(Self.evaluate(targets: targets).everyActionIsReachable)

        targets[0] = ActionHitTarget(
            identifier: "returnToTask",
            frame: ScreenRect(x: 16, y: 80, width: 370, height: 24)
        )
        #expect(!Self.evaluate(targets: targets).everyActionIsReachable)
    }
}
