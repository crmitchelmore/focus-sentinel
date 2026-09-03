import AppKit
import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **The outcome is written onto the intervention it happened to** (focus-xix, focus-7w3, R-79).
///
/// ## The defect
///
/// `NudgeHost` held **one** `openRecordID` — *"the log row for whatever is on screen, so the
/// person's answer can complete it"* — on the assumption that this loop can only be holding one
/// row at a time. That assumption was true while every delivered nudge occupied the interruption
/// slot. The badge ended it: neither a badge question nor a badge rung
/// `holdsTheInterruptionSlot`, so both can be **delivered and open at the same moment, in the
/// same popover, side by side**. The single field then named whichever of the two was written
/// last.
///
/// So the person answered the question and the *accusation's* row was completed `answered`, with
/// the question's row left open for ever; or they pressed "this is relevant" on the accusation
/// and the *question's* row was completed `corrected`. Both are the falsified row focus-7w3 was
/// about — an outcome recorded against an intervention nobody performed it on — reached through a
/// door that opened when the badge grew its correction economy.
///
/// ## The repair, and why it is structural
///
/// The row lives **on** the value that owns the interruption: `OpenQuestion.recordID` and
/// `OpenRung.recordID`. There is no shared field left for two open nudges to fight over, and no
/// caller can ask for "the open row" because the loop no longer offers one — `complete(_:)`'s
/// unnamed form is gone.
///
/// ## What this drives
///
/// The shipping loop with the shipping wires: `NudgeHostFixture.wireMenuBarToTheLoop()` installs
/// the same three connections `AppComposition.startNudgeLoop()` does, and the popover is opened by
/// clicking a real `NSStatusItem`. Both nudges are therefore genuinely delivered — which is the
/// only state in which the defect exists at all.
@Suite("Each open interruption completes its own row", .serialized)
@MainActor
struct NudgeHostOpenRecordTests {
    static let decoy = NudgeHostFixture.decoy
    static let other = "com.chrismitchelmore.FocusOtherApp"

    /// **Which of the two was delivered last**, which is the only thing the old shared field
    /// could tell you.
    ///
    /// Both orders are driven for both assertions, because the defect is invisible from one of
    /// them: with the question written last, answering the question completed the right row *by
    /// accident* and only the correction was wrong. A proof written to one order is a proof
    /// written to the case somebody happened to hold — which is how this class of defect keeps
    /// surviving.
    enum Order: String, CaseIterable, Sendable {
        /// The ladder climbs, the person opens the popover onto the rung, and the question
        /// arrives into a popover that is already up.
        case rungThenQuestion
        /// The question reaches the badge, the person opens the popover onto it, and the ladder
        /// climbs behind it.
        case questionThenRung
    }

    /// Get to the state the defect needs: a delivered badge accusation about the decoy **and** a
    /// delivered badge question about another application, both open, both in the popover.
    ///
    /// Everything here is the shipping loop. `wireMenuBarToTheLoop()` installs the same three
    /// connections `AppComposition.startNudgeLoop()` does, and the popover is opened by clicking a
    /// real `NSStatusItem` — which is the only way either nudge becomes a delivery at all.
    static func twoDeliveredBadgeNudges(_ fixture: NudgeHostFixture, order: Order) throws {
        fixture.host.choose(reducedInterruption: true)
        try fixture.wireMenuBarToTheLoop()

        func climb() {
            for _ in 0..<2 {
                fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.decoy))
                NudgeHostFixture.settle()
                fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
            }
        }
        func askAbout() {
            fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.other))
            NudgeHostFixture.settle()
        }

        switch order {
        case .rungThenQuestion:
            climb()
            try #require(fixture.host.pendingPopoverAccusation != nil, "the rung never reached the badge")
            try Self.openThePopover(fixture)
            askAbout()
        case .questionThenRung:
            askAbout()
            try #require(fixture.host.pendingPopoverQuery != nil, "the question never reached the badge")
            try Self.openThePopover(fixture)
            climb()
        }

        try #require(
            fixture.menuBar.isDrawing(.accusation),
            "the popover is not showing the rung, so it was never delivered"
        )
        try #require(
            fixture.menuBar.isDrawing(.query),
            "the popover is not showing the question, so it was never delivered"
        )
    }

    static func openThePopover(_ fixture: NudgeHostFixture) throws {
        let opened = try MenuBarStage.open(
            fixture.menuBar,
            showing: NudgeHostFixture.menuBarPresentation(of: fixture.host)
        )
        guard MenuBarStage.taken(opened) else { return }
        NudgeHostFixture.settle()
    }

    static func row(
        _ fixture: NudgeHostFixture,
        kind: InterruptionKind
    ) throws -> FocusSchemaV7.InterventionRecord {
        let rows = try fixture.interventions().filter { $0.kind == kind && $0.surface == .popoverBadge }
        return try #require(rows.first, "no delivered badge row of kind \(kind.rawValue)")
    }

    /// **Answering the question completes the question's row.**
    ///
    /// On the unfixed loop the accusation's row is the one that was written last, so it took the
    /// `.answered` outcome — a rung recorded as having been answered by a click nobody made on
    /// it, and a question whose row stays open for the life of the store.
    @Test(
        "answering the badge question completes its own row and not the accusation's",
        arguments: Order.allCases
    )
    func answeringTheQuestionCompletesTheQuestionsRow(order: Order) throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try Self.twoDeliveredBadgeNudges(fixture, order: order)

        fixture.host.answer(.yesAddIt)
        NudgeHostFixture.settle()

        let query = try Self.row(fixture, kind: .query)
        let accusation = try Self.row(fixture, kind: .accusation)
        #expect(query.outcome == .answered, "the question's own row was never completed")
        // **`nil`, and it stays `nil` because the rung is still open** (focus-ti4). The click
        // belonged to the question and must never be written onto the rung — that is what this
        // test is for — and the rung it was not written onto is still standing: `answer(_:)` used
        // to end in `closeSurfaces(endingAnyQuestionAs:)`, which forgot it, so this row briefly
        // read `.ignored` for an accusation the person had said nothing about. An answer ends the
        // question and nothing else.
        #expect(
            accusation.outcome == nil,
            """
            the accusation was recorded as \(String(describing: accusation.outcome)) by a click \
            on the question beside it
            """
        )
    }

    /// **Correcting the accusation completes the accusation's row.**
    ///
    /// The same defect in the other order: with the question delivered last, "this is relevant"
    /// pressed on the rung completed the *question's* row `corrected` — a receipt-shaped lie about
    /// an asking the person never answered.
    @Test(
        "correcting the badge accusation completes its own row and not the question's",
        arguments: Order.allCases
    )
    func correctingTheRungCompletesTheRungsRow(order: Order) throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try Self.twoDeliveredBadgeNudges(fixture, order: order)

        fixture.host.resolve(.thisIsRelevant, snoozeDuration: nil)
        NudgeHostFixture.settle()

        let query = try Self.row(fixture, kind: .query)
        let accusation = try Self.row(fixture, kind: .accusation)
        #expect(accusation.outcome == .corrected, "the rung's own row was never completed")
        #expect(
            query.outcome == nil,
            """
            the question was recorded as \(String(describing: query.outcome)) by a click on the \
            accusation beside it
            """
        )
    }

    /// **And each can be completed in turn**, which is what says the repair is two rows rather
    /// than one row that changed hands.
    @Test(
        "both badge nudges can be answered, and each completes its own row",
        arguments: Order.allCases
    )
    func bothCompleteInTurn(order: Order) throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try Self.twoDeliveredBadgeNudges(fixture, order: order)

        fixture.host.resolve(.thisIsRelevant, snoozeDuration: nil)
        NudgeHostFixture.settle()
        fixture.host.answer(.yesAddIt)
        NudgeHostFixture.settle()

        #expect(try Self.row(fixture, kind: .accusation).outcome == .corrected)
        #expect(try Self.row(fixture, kind: .query).outcome == .answered)
    }
}
