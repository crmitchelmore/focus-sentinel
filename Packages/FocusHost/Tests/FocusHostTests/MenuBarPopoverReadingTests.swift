import AppKit
import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **The popover as a decision surface, measured on screen** (focus-5yu, focus-vpu, U-1).
///
/// ## Why these are here and not in `FocusUITests`
///
/// `MenuBarPopoverLayoutTests` folds the layout invariant over the whole space — five contents,
/// two priority lengths, two text sizes, two appearances — with no window server, because that
/// is the only way to reach `accessibilityLarge` and a long priority in one pass. What it cannot
/// do is open a popover: `NSPopover.show(…)` does nothing unless the application is active, and
/// `FocusUITests` deliberately never activates its process.
///
/// So this suite is the other half, and it is the half the defect actually lived in: the real
/// `NSPopover`, placed by AppKit on a real display, read through the shipping
/// `decisionSurfaceReading(of:)` — and then the same reading joined to the ledger, which is where
/// an unreadable popover used to spend an accusation.
/// The rig these measurements are taken on, at file scope because it is data: a suite annotated
/// `@MainActor` cannot hand its own statics to `@Test(arguments:)`.
enum PopoverRig {
    /// A display that can hold almost nothing, injected so the popover has to clamp and scroll.
    /// The rig's own display is 1080 points tall; nothing about a real Mac produces this, which
    /// is exactly why it is a parameter of the controller rather than a reading it takes.
    static let shortDisplay = DisplayGeometry(
        displayID: 99,
        screenIndex: 0,
        isPrimary: true,
        frame: ScreenRect(x: 0, y: 0, width: 1920, height: 400),
        visibleFrame: ScreenRect(x: 0, y: 89, width: 1920, height: 300),
        backingScaleFactor: 2
    )

    static let shortPriority = "Write the Q3 proposal"

    /// The longest priority the validator permits, which is any length: `IntentValidator` bounds
    /// the sentence from below only, and this one is what the popover's ideal width used to be.
    static let longPriority = ([shortPriority] + Array(
        repeating: "and send the finance summary to the board before the review", count: 4
    )).joined(separator: " ")

    static func query() -> QueryPresentation {
        QueryPresentation(
            task: shortPriority,
            subject: NudgeSubject.named("com.example.Reader", runningName: "Reader")!,
            reason: .noNegativeBasis,
            dwelled: .seconds(120)
        )
    }

    static func accusation() -> AccusationPresentation {
        AccusationPresentation(
            rung: .panel,
            task: shortPriority,
            subject: NudgeSubject.named("com.example.Reader", runningName: "Reader"),
            dwelled: .seconds(600),
            returnTarget: "Pages",
            hasOpenSession: true
        )
    }

    /// The popover carrying **both** nudges at once — the state nothing in the repository drew,
    /// and the tallest thing this surface can be. `NudgeHost` says in as many words that a badge
    /// question waiting behind a click does not hold the slot, so an accusation can be live while
    /// one pends.
    static func carryingBoth(priority: String) -> MenuBarPresentation {
        MenuBarPresentation(
            status: .unrelated,
            priorityIntent: priority,
            elapsed: .seconds(1_505),
            pendingQuery: query(),
            pendingAccusation: accusation(),
            rung: .panel,
            rungSurface: .popoverBadge,
            band: .medium
        )
    }

}

@Suite("The popover, measured on screen", .serialized)
@MainActor
struct MenuBarPopoverReadingTests {
    // MARK: - The size, on the real popover

    /// **The width the product draws is the width the constant names**, at either priority
    /// length, in either appearance.
    ///
    /// Every committed `menuBarPopover.*.png` baseline is rendered at a width the *test* supplies,
    /// so no picture of this surface could ever show its width being wrong — the same shape as
    /// asserting a drawn row against the constant that filled it. This reads the number off the
    /// popover AppKit is showing, having supplied nothing.
    @Test(
        "the popover on screen is the width it committed to, whatever the priority",
        arguments: [PopoverRig.shortPriority, PopoverRig.longPriority],
        [AppearanceTraits.light, AppearanceTraits.dark]
    )
    func theShownPopoverIsTheCommittedWidth(priority: String, traits: AppearanceTraits) throws {
        let controller = MenuBarController(traits: traits)
        defer {
            controller.closePopover()
            controller.remove()
            MenuBarStage.restoreActivationPolicy()
        }
        let opened = try MenuBarStage.open(controller, showing: PopoverRig.carryingBoth(priority: priority))
        guard MenuBarStage.taken(opened) else { return }
        NudgeHostFixture.settle()

        #expect(
            Double(controller.currentPopoverLayout.size.width)
                == MenuBarController.popoverContentWidth
        )
        // …and the popover really is that wide, rather than having been asked politely. The
        // window is wider than its content by the border AppKit draws around it.
        #expect(controller.popoverFrame.width >= MenuBarController.popoverContentWidth)
        #expect(
            controller.popoverFrame.width
                < MenuBarController.popoverContentWidth + MenuBarController.popoverEdgeMargin * 2
        )
        // The measurement that started this bead: unmeasured, this popover stood 483 points above
        // the top of the display with a 21-character priority and 2755 with a long one.
        let reading = controller.decisionSurfaceReading(of: .accusation)
        // **Not a `Bool`** (focus-rxc): the popover is judged against the live `NSScreen.screens`,
        // and with none attached there is no display for it to be wholly on — a property of the
        // machine, which used to arrive as "the popover is off screen".
        let onADisplay: ProbeOutcome = NudgePanelController.currentScreens().isEmpty
            ? .notTaken(.noDisplayAttached)
            : (reading.isWhollyOnAScreen ? .holds : .broken(reading.summary))
        if let banner = onADisplay.banner { print(banner) }
        #expect(
            !onADisplay.isBroken,
            """
            \(onADisplay.summary): the popover is at \(controller.popoverFrame), \
            its item at \(controller.buttonFrame as Any)
            """
        )
    }

    /// **Both nudges at once, on the real popover: the question is the decision** (e07a,
    /// focus-cxb, focus-6pr.4).
    ///
    /// ## Red before
    ///
    /// This asserted that *each* is a decision surface in its own right — `!verdict.isBroken` and
    /// `!offeredIdentifiers(of: nudge).isEmpty` for both kinds — and it was the shipping half of
    /// the disagreement this round closed. e07a had already ruled the other way in the layout: a
    /// popover carrying both pins the **question**, because U-1 licenses the interruption for the
    /// question's cheap answer and U-2 makes the accusation wait behind one, and pinning both
    /// needed over 815 points against a 911-point ceiling. So the accusation's corrections scroll
    /// with the context and are not the shelf, while this suite went on asserting they were the
    /// decision — which is how `NudgeHost` came to charge a rung nobody could answer.
    ///
    /// The reading is still taken per kind, and it is still a reading of the real popover. What
    /// changed is which of the three standings each kind is held to.
    @Test("a popover carrying an accusation and a question is a decision surface for the question")
    func bothNudgesAtOnceArePinnedForTheQuestion() throws {
        let controller = MenuBarController()
        defer {
            controller.closePopover()
            controller.remove()
            MenuBarStage.restoreActivationPolicy()
        }
        let opened = try MenuBarStage.open(
            controller,
            showing: PopoverRig.carryingBoth(priority: PopoverRig.shortPriority)
        )
        guard MenuBarStage.taken(opened) else { return }
        NudgeHostFixture.settle()

        // The question: the pinned decision, and a surface a person could answer on.
        let question = controller.decisionSurfaceReading(of: .query)
        let verdict = DecisionSurfaceReachability.verdict(
            question,
            screens: NudgePanelController.currentScreens()
        )
        if let banner = verdict.banner { print(banner) }
        #expect(
            !verdict.isBroken,
            """
            query: \(verdict.summary) — the popover is at \(controller.popoverFrame), \
            laid out at \(controller.currentPopoverLayout)
            """
        )
        #expect(!controller.offeredIdentifiers(of: .query).isEmpty)

        // The accusation: drawn, in the same popover, offering nothing — and therefore
        // `notOffered` rather than a decision surface that happens to be empty. The two are read
        // off the same window, so this is not a claim about a different popover.
        #expect(controller.isDrawing(.accusation))
        #expect(
            controller.offeredIdentifiers(of: .accusation).isEmpty,
            "the accusation claims a pinned decision beside a question"
        )
        #expect(controller.isDrawnBesideThePinnedDecision(.accusation))
        #expect(!controller.isDrawnBesideThePinnedDecision(.query))
        let accusation = controller.decisionSurfaceReading(of: .accusation)
        #expect(
            accusation.standing != .reachable,
            "an accusation offering nothing read as one every action of which is reachable"
        )
        // Guarded by the question's own reading, because the two share one geometry and where
        // AppKit drops a popover is a property of the machine.
        if question.standing == .reachable {
            #expect(
                accusation.standing == .notOffered,
                "the accusation beside a pinned question read as \(accusation.summary)"
            )
        }
    }

    /// The long priority, on the real popover, held to the honest claim rather than to a number
    /// this machine happens to produce: it is the committed width, every action it offers is
    /// **drawn**, and if the content is too tall for this display then the reading says so
    /// instead of passing.
    @Test("the longest priority does not change the surface, only what has to scroll")
    func theLongestPriorityIsStillASurface() throws {
        let controller = MenuBarController()
        defer {
            controller.closePopover()
            controller.remove()
            MenuBarStage.restoreActivationPolicy()
        }
        let opened = try MenuBarStage.open(
            controller,
            showing: PopoverRig.carryingBoth(priority: PopoverRig.longPriority)
        )
        guard MenuBarStage.taken(opened) else { return }
        NudgeHostFixture.settle()

        // **The question's reading, because this rig carries both** (focus-6pr.4). The
        // accusation beside a pinned question offers nothing, so a reading of it would be
        // `notOffered` whatever the priority did to the layout — which is a true statement about
        // the ruling and no statement at all about the longest sentence a person can commit to.
        let reading = controller.decisionSurfaceReading(of: .query)
        #expect(
            Double(controller.currentPopoverLayout.size.width)
                == MenuBarController.popoverContentWidth
        )
        #expect(reading.unreportedActions.isEmpty, "an answer was drawn nowhere at all")
        if !controller.currentPopoverLayout.scrolls {
            let verdict = DecisionSurfaceReachability.verdict(
                reading,
                screens: NudgePanelController.currentScreens()
            )
            if let banner = verdict.banner { print(banner) }
            #expect(!verdict.isBroken, "\(verdict.summary)")
        }
    }

    // MARK: - And an unreadable popover spends nothing

    /// **The charge, joined to the reading** — the half `deliverPendingBadgeRung()` never had.
    ///
    /// The badge counted a rung delivered on `popover.isShown && presentation.isCarrying(nudge)`,
    /// so a popover whose corrections were off the bottom of the display spent one of the day's
    /// six accusations, one of its eight interruptions and armed the 600-second cooldown. This
    /// drives exactly that: the same climb to the badge that
    /// `NudgeHostBadgeAccusationTests.openingThePopoverCountsTheBadgeRung` charges on a readable
    /// popover, with a display too short to hold the corrections.
    ///
    /// The display is injected rather than the content being made enormous, because the invariant
    /// is about the surface being **readable**, not about any particular sentence: any content
    /// taller than the display it is shown on is the same defect.
    @Test("a badge rung whose corrections are out of reach is not charged")
    func anUnreadableBadgeRungSpendsNothing() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try fixture.wireMenuBarToTheLoop()
        fixture.menuBar.displays = { [PopoverRig.shortDisplay] }

        NudgeHostBadgeAccusationTests.climbToTheBadge(fixture, via: .reducedInterruption)
        let deliveredBeforeTheClick = fixture.host.deliveredCount
        try #require(fixture.host.todaysUsage().accusationsToday == 0)

        let opened = try MenuBarStage.open(
            fixture.menuBar,
            showing: NudgeHostFixture.menuBarPresentation(of: fixture.host)
        )
        guard MenuBarStage.taken(opened) else { return }
        NudgeHostFixture.settle()

        // The popover is open and it is carrying the rung — the whole of the old reading.
        #expect(fixture.menuBar.isDrawing(.accusation))
        // And it is not a surface anybody could decide on: the corrections are laid out below
        // what a 300-point display can show.
        let reading = fixture.menuBar.decisionSurfaceReading(of: .accusation)
        #expect(!reading.everyActionIsReachable)
        #expect(
            !reading.unreachableActions.isEmpty,
            "the corrections were reported as drawn nowhere rather than as out of reach"
        )

        #expect(
            fixture.host.deliveredCount == deliveredBeforeTheClick,
            "a rung nobody could answer was counted as delivered"
        )
        #expect(
            fixture.host.todaysUsage().accusationsToday == 0,
            "an unreadable popover spent one of the day's six accusations"
        )
        let badgeRows = try fixture.interventions().filter { $0.surface == .popoverBadge }
        #expect(
            !badgeRows.contains { $0.disposition == .delivered },
            "a delivery was written for a popover whose corrections were off the display"
        )
    }
}
