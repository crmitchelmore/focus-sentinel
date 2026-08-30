import AppKit
import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **A badge question that was really read leaves a receipt** (focus-gmr, U-1).
///
/// ## The defect, as it was measured
///
/// With reduced interruption on — which macOS Reduce Motion forces (focus-w7v), and which the
/// `silentVisual` deck and any running microphone reach by the other two doors — a question is
/// routed to `.popoverBadge`. The person clicks the status item, `popoverPresented()` counts the
/// delivery, and the question is genuinely on screen and genuinely read. Then the popover closes,
/// because an `NSPopover` with `.transient` behaviour is shut by the next click anywhere, and the
/// person takes a break.
///
/// Measured on the shipping loop: `QueryLedger` receipts for the priority = **0**. The
/// `InterventionRecord` stayed `delivered` with `outcome = nil` for ever, and the next uncertain
/// judgement about the same subject asked the same question again — because gate 11 reads the
/// ledger and the ledger had nothing. U-1's *never asked twice* held for the panel and was broken
/// for the entire quiet route.
///
/// The mechanism was `badgeReadability(of:)`, which is `guard menuBar.isPopoverShown`: for the
/// panel a second reading is worth taking, because a sticky panel can go out of reach while it is
/// still up; for a transient popover there is no second state to look at. Demanding one demanded
/// evidence the surface is structurally incapable of producing.
@Suite("A badge question that was read is written down", .serialized)
@MainActor
struct NudgeHostBadgeReceiptTests {
    static let subject = "com.chrismitchelmore.FocusOtherApp"

    /// Ask the question, and put it in front of the person by opening the popover on it.
    static func askAndRead(_ fixture: NudgeHostFixture) throws {
        try fixture.wireMenuBarToTheLoop()
        fixture.host.choose(reducedInterruption: true)
        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        try #require(
            fixture.host.pendingPopoverQuery != nil,
            "the question did not reach the badge, so this drives nothing"
        )
        try MenuBarStage.open(
            fixture.menuBar,
            showing: NudgeHostFixture.menuBarPresentation(of: fixture.host)
        )
        NudgeHostFixture.settle()
        try #require(
            fixture.menuBar.isDrawing(.query),
            "the popover is not showing the question, so it was never delivered"
        )
    }

    /// **The whole bead, driven.** Read, closed, break — and the record says all three happened.
    @Test("a question read in the popover, closed, and left behind is recorded and not re-asked")
    func aReadBadgeQuestionLeavesAReceipt() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try Self.askAndRead(fixture)

        try #require(
            fixture.host.todaysUsage().queriesForPriorityToday == 1,
            "the question was not charged, so there is nothing to be dishonest about"
        )

        // The popover shuts on the next click anywhere — that is what `.transient` means — and
        // then the person takes a break.
        fixture.menuBar.closePopover()
        NudgeHostFixture.settle()
        try #require(!fixture.menuBar.isPopoverShown)
        fixture.host.phaseLeftFocus()
        NudgeHostFixture.settle()

        // 1. The ledger remembers the asking. Measured at zero before this round.
        let receipts = try fixture.receipts()
        #expect(
            receipts.count == 1,
            "a question the person opened the popover onto and read left no receipt at all"
        )
        #expect(receipts.first?.subject == Self.subject)
        // 2. And it is an *unanswered* asking, so the question comes back if the world raises it
        //    again (focus-qds). An expiry is not an answer.
        #expect(receipts.first?.outcome == .expired)
        #expect(receipts.first?.outcome.settlesTheQuestion == false)

        // 3. The delivered row is no longer stranded: it says what became of the interruption.
        let row = try #require(
            try fixture.interventions().first {
                $0.kind == .query && $0.surface == .popoverBadge
            },
            "no delivered badge row for the question"
        )
        #expect(
            row.outcome == .ignored,
            "the row still says the app interrupted somebody and never says how it turned out"
        )
    }

    /// **The asking counts against the day, which is the half a missing receipt under-counted.**
    ///
    /// `QueryLedger.askedCount(…)` is the reading the fatigue controller and the pane draw, and
    /// the badge is exactly the surface it was built to protect.
    @Test("the day's asked count sees a badge question that was read")
    func theAskedCountSeesTheBadgeQuestion() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try Self.askAndRead(fixture)

        fixture.menuBar.closePopover()
        fixture.host.phaseLeftFocus()
        NudgeHostFixture.settle()

        let asked = try fixture.ledger.askedCount(
            priorityID: fixture.priorityID,
            on: fixture.log.today,
            calendar: NudgeHostFixture.londonCalendar
        )
        #expect(asked == 1, "askedCount under-counts the surface it was built to protect")
    }

    /// **The negative control, and it is the rule this must not have weakened.**
    ///
    /// A badge question nobody ever opened is still written down as nothing at all: the reading
    /// at the ask was never proven, so there is no proof to lean on and the question stays
    /// askable with an empty ledger. Without this, "trust the reading at the ask" could be
    /// satisfied by trusting an ask that proved nothing — which is the burn U-1 forbids.
    @Test("a badge question nobody opened is still written down as nothing")
    func anUnopenedBadgeQuestionIsStillUnwritten() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try fixture.wireMenuBarToTheLoop()
        fixture.host.choose(reducedInterruption: true)

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        try #require(fixture.host.pendingPopoverQuery != nil)
        try #require(!fixture.menuBar.isPopoverShown, "the popover opened without anybody clicking")

        fixture.host.phaseLeftFocus()
        NudgeHostFixture.settle()

        #expect(
            try fixture.receipts().isEmpty,
            "a receipt was written about a question nobody was ever shown"
        )
        #expect(
            try fixture.interventions().allSatisfy {
                $0.dispositionRaw != InterventionDisposition.delivered.rawValue
            },
            "an invitation nobody opened was charged"
        )
    }

    /// **Quit is an exit, and it was the one exit the loop had never heard of** (focus-gmr's
    /// lesser finding).
    ///
    /// An unopened badge invitation at quit wrote no `unopened` row: a day on which the app
    /// raised its top rung and the person quit without ever looking read exactly like a day the
    /// ladder never left the glyph — which is precisely the signal that would have shown this
    /// whole class of defect in the wild.
    @Test("quitting with an unopened invitation on the badge writes the row it owes")
    func quittingRecordsTheUnopenedInvitation() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try fixture.wireMenuBarToTheLoop()
        fixture.host.choose(reducedInterruption: true)

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        try #require(fixture.host.pendingPopoverQuery != nil)
        try #require(!fixture.menuBar.isPopoverShown)
        try #require(
            try fixture.interventions().isEmpty,
            "an invitation nobody opened was written down before the quit"
        )

        fixture.host.applicationWillTerminate()
        NudgeHostFixture.settle()

        let rows = try fixture.interventions()
        #expect(rows.count == 1, "quitting left the invitation unrecorded")
        #expect(rows.first?.disposition == .unopened)
        #expect(rows.first?.kind == .query)
        #expect(rows.first?.surface == .popoverBadge)
        // It spends nothing: `spendsBudget` is `disposition == .delivered`, and nobody looked.
        #expect(fixture.host.todaysUsage().interruptionsToday == 0)
        // And it stays askable — quitting is not an answer.
        #expect(try fixture.receipts().isEmpty)
    }

    /// The other half of the same exit: a rung standing on the glyph at quit is let go of, and
    /// its row says what became of it.
    @Test("quitting with a delivered glyph rung completes its row")
    func quittingCompletesADeliveredRung() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try fixture.wireMenuBarToTheLoop()

        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        try #require(fixture.host.landedRungSurface == .menuBar)
        let delivered = try #require(
            try fixture.interventions().first {
                $0.dispositionRaw == InterventionDisposition.delivered.rawValue
            },
            "the glyph rung was never delivered, so this drives nothing"
        )
        try #require(delivered.outcome == nil)

        fixture.host.applicationWillTerminate()
        NudgeHostFixture.settle()

        #expect(
            try fixture.interventions().first { $0.id == delivered.id }?.outcome == .ignored,
            "the rung's row still says the app interrupted somebody and never says how it ended"
        )
        #expect(fixture.host.landedRungSurface == nil, "the rung outlived the application")
    }
}
