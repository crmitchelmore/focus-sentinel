import AppKit
import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **A nudge is placed once; the display it was placed on is not** (focus-56y, U-1, R-81).
///
/// ## The defect these drive
///
/// `grep -rn didChangeScreenParametersNotification App/ Packages/` returned nothing anywhere.
/// Every reading the loop took of the panel was taken at the show and never again for an
/// accusation — `NudgeHost.accuse` at the guard below `panel.show(…)`, `ask` at the equivalent one
/// — so a rung was read once, counted delivered, and never revisited. A panel is deliberately
/// sticky (`hidesOnDeactivate` is `false`, R-89) precisely so that it waits for an answer, which
/// means it is still on screen when the display underneath it is replaced: undocking, a projector,
/// Sidecar, a resolution change.
///
/// Read in a clean clone at `b96b82c`: a top rung placed at 380 × 772 on 1920 × 1080, then the
/// display became 800 × 600. The window stayed 380 × 772 at an AppKit origin of
/// y = 600 − 30 − 772 = −202, and the captures showed only "Back to TextEdit", "This is relevant",
/// "Not this time" and half a Snooze label. The three snooze spans, Pause and Change priority were
/// off the bottom of the display — five of six actions unreachable, on the one rung that demands
/// an explicit choice and does not auto-dismiss.
///
/// ## What is real here and what is not
///
/// The panel is the shipping `NudgePanelController` with a real `NSPanel`, the layout is the
/// shipping layout, the reading is `DecisionSurfaceReachability`'s, and the notification is the
/// one AppKit posts — posted here rather than waited for, because this rig has one display and
/// cannot be made to grow a second, unplug it, or shrink to 800 × 600. The **display list** is
/// injected through `NudgePanelController.displays` and nothing else is. Posting the real
/// notification is deliberate: it puts the observation wiring itself under test, which a direct
/// call to the re-placement would leave unproven.
@Suite("A display change under a live nudge", .serialized)
@MainActor
struct NudgeHostDisplayChangeTests {
    static let subject = "com.chrismitchelmore.FocusDecoy"

    /// The desk. 1920 × 1080 with the menu bar taken off the top, which is what
    /// `NSScreen.visibleFrame` reports.
    static let desk = [
        DisplayGeometry(
            displayID: 1,
            screenIndex: 0,
            isPrimary: true,
            frame: ScreenRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: ScreenRect(x: 0, y: 0, width: 1920, height: 1055),
            backingScaleFactor: 2
        )
    ]

    /// The projector the bead names: 800 × 600, and the only display there is.
    static let projector = [
        DisplayGeometry(
            displayID: 2,
            screenIndex: 0,
            isPrimary: true,
            frame: ScreenRect(x: 0, y: 0, width: 800, height: 600),
            visibleFrame: ScreenRect(x: 0, y: 0, width: 800, height: 575),
            backingScaleFactor: 1
        )
    ]

    /// A laptop screen. Smaller than the desk in both axes and a different shape, so a panel
    /// placed for the desk has to move — but big enough to hold a question with its three answers
    /// in reach, which is what makes it the *surviving* case rather than the stranded one.
    static let laptop = [
        DisplayGeometry(
            displayID: 4,
            screenIndex: 0,
            isPrimary: true,
            frame: ScreenRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: ScreenRect(x: 0, y: 0, width: 1440, height: 875),
            backingScaleFactor: 2
        )
    ]

    /// A display that cannot hold a panel `height` points tall, however it is placed: its usable
    /// height is one panel margin short of what the content needs.
    ///
    /// Derived from the panel's own measurement rather than written down, because the height of
    /// the shipping accusation at the shipping text size is not this suite's business to know —
    /// what it needs is a display too small for whatever that turns out to be.
    static func displayTooSmall(for height: Double) -> [DisplayGeometry] {
        let usable = height + NudgePanelController.edgeMargin
        return [
            DisplayGeometry(
                displayID: 3,
                screenIndex: 0,
                isPrimary: true,
                frame: ScreenRect(x: 0, y: 0, width: 800, height: usable + 25),
                visibleFrame: ScreenRect(x: 0, y: 0, width: 800, height: usable),
                backingScaleFactor: 1
            )
        ]
    }

    /// What AppKit posts when a display is added, removed, or changes resolution.
    static func theDisplayConfigurationChanges() {
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: NSApp
        )
        NudgeHostFixture.settle()
    }

    /// Drive the ladder to the top rung, which since U-2 is the panel — the one the bead is
    /// about.
    ///
    /// The ambient rung is the menu-bar glyph and raises no window, so reaching the panel rung
    /// means climbing the whole ladder: one delivery, then `escalationDwell` of continued drift,
    /// then the next. Each turn is an ordinary corroboration tick, which is the cadence the
    /// shipping loop runs at, and every rung is delivered by the shipping loop rather than
    /// installed by the test.
    ///
    /// The top rung is `LadderRung.Kind.panel`: a nudge that does not
    /// auto-dismiss, routed to the panel because this fixture's notification centre answers
    /// `denied` — which is the ordinary state of a Mac nobody has granted notifications on.
    @discardableResult
    static func escalateToTheRecommitment(_ fixture: NudgeHostFixture) -> LadderRung.Kind? {
        for _ in 0..<6 {
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: subject))
            NudgeHostFixture.settle()
            if fixture.host.currentRung == .panel, fixture.panel.isVisible {
                return fixture.host.currentRung
            }
            fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }
        return fixture.panel.isVisible ? fixture.host.currentRung : nil
    }

    // MARK: - The panel follows the display

    /// **The nudge moves onto the display that is actually there.**
    ///
    /// The bead's own geometry, in both axes. On the desk the panel is placed at the top trailing
    /// corner of a 1920 × 1055 visible frame — around x = 1516, y = 700-odd. Neither coordinate
    /// exists on an 800 × 575 one. Without the observation the window stays exactly where it was
    /// and `isWhollyOnAScreen` goes false, which is the reading that says a person is being asked
    /// to choose on a surface that is not on their screen.
    @Test("a panel placed on a desk display is re-placed when the display becomes a projector")
    func thePanelIsRePlacedOntoTheDisplayThatIsThere() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        fixture.panel.displays = { Self.desk }

        let rung = Self.escalateToTheRecommitment(fixture)
        #expect(rung == .panel, "the ladder never reached the panel rung")
        #expect(fixture.panel.isVisible)

        let onTheDesk = fixture.panel.frame
        #expect(
            fixture.panel
                .decisionSurfaceReading(offering: fixture.host.openRungPanelActions)
                .everyActionIsReachable
        )
        let delivered = try fixture.interventions()
            .filter { $0.dispositionRaw == InterventionDisposition.delivered.rawValue }
        #expect(!delivered.isEmpty)

        // The desk display is unplugged and the projector is the only one left.
        fixture.panel.displays = { Self.projector }
        Self.theDisplayConfigurationChanges()

        // The panel is still up — a rung that demands an explicit choice does not auto-dismiss —
        // and it is now somewhere a person can reach.
        #expect(fixture.panel.isVisible, "the nudge was withdrawn from a display that could hold it")
        let onTheProjector = fixture.panel.frame
        #expect(
            onTheProjector.y != onTheDesk.y || onTheProjector.x != onTheDesk.x,
            "the panel did not move: it is still placed for a display that is no longer there"
        )

        let reading = fixture.panel.decisionSurfaceReading(
            offering: fixture.host.openRungPanelActions
        )
        #expect(
            reading.isWhollyOnAScreen,
            "the panel is off the display the person is looking at: \(reading.summary)"
        )
        #expect(
            reading.everyActionIsReachable,
            "an action went out of reach when the display changed: \(reading.summary)"
        )

        // Nothing was taken back, because nothing needed to be.
        #expect(try fixture.interventions().allSatisfy {
            $0.dispositionRaw != InterventionDisposition.deferred.rawValue
        })
        #expect(fixture.host.currentRung == rung)
    }

    // MARK: - A display that cannot hold it takes the delivery back

    /// **A rung the new display cannot hold is un-delivered, and offered again** (R-81, U-1).
    ///
    /// Re-placing is the repair that matters to the person and it is what happens above. This is
    /// the other half: a display with less usable height than the nudge needs, where re-placement
    /// puts the actions behind a scroll rather than in reach. R-81 says a rung nobody could see
    /// does not advance the ladder, and it does not stop saying so one minute after the show —
    /// so the panel goes, the ladder is put back where it stood, the withdrawal is written down
    /// as a deferral, and the same rung is offered again rather than the app escalating past it.
    @Test("a rung stranded by a display change is withdrawn, un-delivered and offered again")
    func aStrandedRungIsUnDeliveredRatherThanCountedAsSeen() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        fixture.panel.displays = { Self.desk }

        let rung = Self.escalateToTheRecommitment(fixture)
        #expect(rung == .panel)
        #expect(fixture.panel.isVisible)
        let engagedRung = fixture.host.ladder.state.rung
        #expect(engagedRung != nil, "the ladder is not engaged, so there is no delivery to take back")
        let deferralsBefore = try fixture.interventions()
            .count { $0.dispositionRaw == InterventionDisposition.deferred.rawValue }
        let spendBefore = try fixture.log.budget(
            on: fixture.log.today, priorityID: fixture.priorityID
        )
        #expect(spendBefore.accusationsToday >= 1, "nothing was ever charged to the budget")

        // A display that cannot hold this panel however it is placed.
        let needed = fixture.panel.contentSize.height
        fixture.panel.displays = { Self.displayTooSmall(for: needed) }
        Self.theDisplayConfigurationChanges()

        #expect(
            !fixture.panel.isVisible,
            "a panel whose corrections are out of reach was left up for somebody to not answer"
        )
        let deferralsAfter = try fixture.interventions()
            .count { $0.dispositionRaw == InterventionDisposition.deferred.rawValue }
        #expect(
            deferralsAfter == deferralsBefore + 1,
            "the withdrawal was not written down as a deferral"
        )
        #expect(fixture.host.deferredCount >= 1)

        // **And it stops spending the day's budget** (focus-mfc, R-81). Un-delivering from the
        // ladder stops the escalation clock; this is the other half. `spendsBudget` is
        // `disposition == .delivered`, so a stranded rung left as a delivery goes on charging the
        // interruption cap for something nobody saw — and under U-1 the budget is what decides
        // whether the app may speak again at all.
        let spendAfter = try fixture.log.budget(
            on: fixture.log.today, priorityID: fixture.priorityID
        )
        #expect(
            spendAfter.accusationsToday == spendBefore.accusationsToday - 1,
            "a rung nobody saw is still charged to the day's accusation cap"
        )
        #expect(
            spendAfter.interruptionsToday == spendBefore.interruptionsToday - 1,
            "a rung nobody saw is still charged to the shared interruption cap"
        )

        // The ladder is standing where it was before the delivery — so the escalation clock is
        // not running, and the next judgement offers **this same rung** rather than the one above.
        #expect(
            fixture.host.ladder.state.rung != engagedRung,
            "the ladder is still engaged at a rung nobody could answer, so it will escalate past it"
        )
        let offeredAgain = fixture.host.ladder.candidate(
            at: fixture.clock.elapsed,
            budgetPermits: true
        )
        #expect(
            offeredAgain?.kind == engagedRung?.kind,
            """
            the ladder does not offer the stranded rung again \
            (\(String(describing: offeredAgain?.kind)) rather than \(String(describing: engagedRung?.kind)))
            """
        )
    }

    // MARK: - The question's single licensed interruption is not spent on a lost surface

    /// **A question stranded by a display change stays askable** (U-1, focus-kby).
    ///
    /// Every receipt in `QueryLedger` is immutable and `hasAsked(…)` is gate 11 of the suppression
    /// stack, so a receipt written about a question the person never got to answer does not merely
    /// mis-record history — it silences that subject for the life of the priority. U-1 licenses
    /// the interruption precisely because it is one cheap click that teaches the app; spending it
    /// on a panel that has just been left on a display nobody is looking at is the app burning its
    /// licence.
    @Test("a question stranded by a display change writes no receipt and is asked again")
    func aStrandedQuestionIsUnAskedRatherThanBurned() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        fixture.panel.displays = { Self.desk }

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        #expect(fixture.host.deliveredCount == 1)
        #expect(fixture.panel.isVisible)
        #expect(
            try fixture.log.budget(
                on: fixture.log.today, priorityID: fixture.priorityID
            ).queriesForPriorityToday == 1
        )

        let needed = fixture.panel.contentSize.height
        fixture.panel.displays = { Self.displayTooSmall(for: needed) }
        Self.theDisplayConfigurationChanges()

        #expect(!fixture.panel.isVisible, "the question was left on a surface nobody could answer")

        // Nothing was written, and gate 11 will not suppress the question next time.
        #expect(
            try fixture.receipts().isEmpty,
            "a receipt was written about a question the display took away"
        )
        #expect(
            !(try fixture.ledger.isSettled(
                priorityID: fixture.priorityID,
                subjectKind: .app,
                subject: Self.subject
            )),
            "gate 11 would now silence a subject the person was never able to answer about"
        )
        // …and the slot was given back, so the next judgement is not withheld against a surface
        // that is not there any more.
        #expect(fixture.host.pendingPopoverQuery == nil)
        #expect(fixture.host.slot.isOpen)

        let rows = try fixture.interventions()
        #expect(rows.contains { $0.dispositionRaw == InterventionDisposition.deferred.rawValue })
        // …and it is off the budget as well as off the screen (focus-mfc): a question the person
        // never got to answer must not be the reason the app stays quiet for the rest of the day.
        #expect(
            try fixture.log.budget(
                on: fixture.log.today, priorityID: fixture.priorityID
            ).queriesForPriorityToday == 0,
            "a question nobody could answer is still charged to the day's query cap"
        )
    }

    // MARK: - …and a question the new display can hold is left alone

    /// **The question branch's other half, and the one nothing exercised** (focus-22m, S9).
    ///
    /// Every case above ends with the question being taken away. That leaves the branch's
    /// **guard** — `guard currentReadability() != .readable else { return }` — unexercised: with
    /// it deleted, every one of those tests still passes, and a question that merely *moved* onto
    /// a display which can hold it perfectly well would be un-asked, deferred and taken off the
    /// screen the person is looking at. That is the loop destroying its own licensed interruption
    /// because a projector was plugged in.
    ///
    /// The last two lines are the ones that matter: the question is still there, and it is still
    /// answerable. An un-asked question has no warrant left, so `answer(_:)` returns without
    /// writing, and the receipt count says so.
    @Test("a question the new display can hold is moved, not un-asked")
    func aQuestionTheNewDisplayCanHoldSurvives() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        fixture.panel.displays = { Self.desk }

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        #expect(fixture.host.deliveredCount == 1)
        #expect(fixture.panel.isVisible)
        let onTheDesk = fixture.panel.frame
        let deferralsBefore = try fixture.interventions()
            .count { $0.dispositionRaw == InterventionDisposition.deferred.rawValue }

        // The desk display is unplugged and the laptop screen is the only one left. It is a
        // different size and a different shape, so the panel really does have to be re-placed.
        fixture.panel.displays = { Self.laptop }
        Self.theDisplayConfigurationChanges()

        #expect(
            fixture.panel.isVisible,
            "a question was withdrawn from a display that could hold it perfectly well"
        )
        let onTheLaptop = fixture.panel.frame
        #expect(
            onTheLaptop.x != onTheDesk.x || onTheLaptop.y != onTheDesk.y,
            "the panel did not move: it is still placed for a display that is no longer there"
        )
        let reading = fixture.panel.decisionSurfaceReading(
            offering: QueryPresentation.actionOrder.map(\.rawValue)
        )
        #expect(
            reading.everyActionIsReachable,
            "the fixture did not build a display that can hold the question: \(reading.summary)"
        )

        // Nothing was taken back, because nothing needed to be: no deferral, and the asking is
        // still charged to the day exactly once.
        #expect(
            try fixture.interventions()
                .count { $0.dispositionRaw == InterventionDisposition.deferred.rawValue }
                == deferralsBefore,
            "a question that simply moved was written down as a deferral"
        )
        #expect(fixture.host.deferredCount == 0)
        #expect(
            try fixture.log.budget(
                on: fixture.log.today, priorityID: fixture.priorityID
            ).queriesForPriorityToday == 1
        )

        // And the whole point: it is still the open question, and the person can still answer it.
        #expect(fixture.host.deliveredCount == 1, "the question was delivered a second time")
        fixture.host.answer(.yesAddIt)
        #expect(
            try fixture.receipts().count == 1,
            "the question was un-asked behind the person's back, so their answer wrote nothing"
        )
    }

    // MARK: - The observation costs nothing when there is nothing up

    /// A display change with no nudge on screen is not an event. Beside the three above because
    /// an observer that re-laid-out an invisible panel would replace the frames the *next*
    /// reading is taken from — which is the defect `framesFromAReplacedLayoutAreRefused` names,
    /// arrived at from the other side.
    @Test("a display change with nothing on screen writes nothing and shows nothing")
    func aDisplayChangeWithNoNudgeUpIsNotAnEvent() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        fixture.panel.displays = { Self.desk }

        Self.theDisplayConfigurationChanges()

        #expect(!fixture.panel.isVisible)
        #expect(try fixture.interventions().isEmpty)
        #expect(fixture.host.deferredCount == 0)
        #expect(fixture.host.deliveredCount == 0)
    }
}
