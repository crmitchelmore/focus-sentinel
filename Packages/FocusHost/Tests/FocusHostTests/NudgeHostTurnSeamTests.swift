import AppKit
import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **A change undone inside the same turn was never a change** (focus-my0, U-1).
///
/// ## What was measured, and why every earlier proof was green for it
///
/// `NudgeHost.closeSurfaces(endingAnyQuestionAs:)` runs three statements in **one synchronous
/// main-actor call stack**: end the open question, hide the panel, forget the open rung. With a
/// badge question pending and a glyph rung standing invisibly under it — the state
/// `PerceptibleChange` itself calls *"the ordinary state of every Reduce Motion user and everybody
/// on a call"* — taking a break did this:
///
/// 1. the question cleared, the presentation rebuilt, and the item's mark fell `waiting` →
///    `noticing`;
/// 2. the redraw assigned the image, fired `onGlyphWritten`, and all three of the charging
///    invariant's conjuncts were satisfied — **receipt issued, charge taken**;
/// 3. two statements later the rung was forgotten and the item went back to `unmarked`.
///
/// AppKit composites nothing between statement 1 and statement 3. Measured on the shipping loop:
/// `writesDuringTeardown=2`, `chargesDelta=1`, `markAfter=unmarked`, one row reading
/// `accusation/delivered/menuBar/ignored`, one of the day's eight interruptions spent, a cooldown
/// armed — **nobody having clicked anything**. The record said the app delivered an accusation
/// and the person ignored it.
///
/// Every conjunct of `PerceptibleChange.proven(on:from:to:)` was true. The item really was written
/// to, it really was not saying `noticing` before, and at the instant the reading was taken it
/// really was saying `noticing`. What was false is the thing the reading stood in for: that a
/// person could have seen it. This is the charging invariant satisfied **formally while its
/// purpose is defeated**, and no fold over `SurfaceObservation` pairs can catch it, because the
/// pair really does show a change — it is *when* the second half was taken that is wrong.
///
/// ## Why this suite is parameterised over the exits rather than written about the break
///
/// Five entry points take the surfaces down in one call stack, and repairing the one the bead
/// names is the method this epic has now used four times: fix the instance, leave the shape. The
/// repair is in the type — `PerceptibleChange` will not accept a reading that was not taken at a
/// `SurfaceTurn`'s seam — so this drives every exit that shares the shape and asserts one thing
/// of all of them.
@Suite("A change undone in the same turn is not a perceptible change", .serialized)
@MainActor
struct NudgeHostTurnSeamTests {
    /// **Every way the world takes the surfaces down inside one synchronous call stack.**
    ///
    /// Four of them reach `closeSurfaces(endingAnyQuestionAs:)` — two of those through
    /// `clearSessionState()` — and the fifth, `hideOverlays()`, is the same three statements
    /// written out by hand. That is the whole point of parameterising: the fix must not be five
    /// fixes, so the proof must not be one drive.
    enum Exit: String, CaseIterable, Sendable, CustomStringConvertible {
        /// The bead's own drive: the session left `.focus` because somebody took a break.
        case tookABreak
        case endedTheSession
        case changedPriority
        case quit
        /// F-81's command, which does not go through `closeSurfaces(…)` and does the same thing.
        case askedForTheScreenBack

        var description: String { rawValue }

        @MainActor
        func taken(by host: NudgeHost) {
            switch self {
            case .tookABreak: host.phaseLeftFocus()
            case .endedTheSession: host.sessionEnded()
            case .changedPriority: host.priorityChanged()
            case .quit: host.applicationWillTerminate()
            case .askedForTheScreenBack: host.hideOverlays()
            }
        }
    }

    /// Two applications with names of their own, so a drawn sentence can be told from a key.
    static let drifted = "com.example.Browser"
    static let asked = "com.chrismitchelmore.FocusOtherApp"

    /// Accusation rows in the store, as `disposition/surface/outcome`.
    static func accusationRows(_ fixture: NudgeHostFixture) throws -> [String] {
        try fixture.interventions()
            .filter { $0.kind == .accusation }
            .map { "\($0.dispositionRaw)/\($0.surfaceRaw)/\($0.outcomeRaw ?? "none")" }
            .sorted()
    }

    /// **The state the bead is about**: a question waiting behind the click, holding the item at
    /// `waiting`, and an ambient rung standing under it that the item has never mentioned.
    ///
    /// `#require`d rather than assumed, because a fixture that failed to reach it would prove the
    /// invariant about a state nobody drove — which is how three rounds of this defect stayed
    /// green.
    static func aRungNobodyHasSeen(under fixture: NudgeHostFixture) throws {
        fixture.workspace.runningNames[Self.drifted] = "Browser"
        fixture.workspace.runningNames[Self.asked] = "Other App"

        // Reduced interruption is on: what macOS Reduce Motion forces, and what everybody on a
        // call is in. It is what routes the question to the badge.
        fixture.host.choose(reducedInterruption: true)
        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.asked))
        NudgeHostFixture.settle()
        try #require(fixture.host.pendingPopoverQuery != nil, "no question reached the badge")
        try #require(
            fixture.menuBar.markOnTheItem == .waiting,
            "the badge did not hold the item at waiting, so this drives nothing"
        )

        // Sustained drift into a different application: the ambient rung lands on the glyph, and
        // the item goes on saying `waiting`, so it says nothing about the rung at all.
        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.drifted))
        NudgeHostFixture.settle()
        try #require(
            fixture.host.landedRungSurface == .menuBar,
            "the rung did not reach the glyph, so this drives nothing"
        )
        try #require(
            fixture.menuBar.markOnTheItem == .waiting,
            "the item mentioned the rung before the teardown, so this drives nothing"
        )
        try #require(
            fixture.host.chargesPaidFor.isEmpty,
            "something was charged before the exit, so the delta below means nothing"
        )
    }

    @Test(
        "no exit charges for a mark that was put up and taken down in one call stack",
        arguments: Exit.allCases
    )
    func anExitChargesNothingForAMarkNobodySaw(exit: Exit) throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try fixture.wireMenuBarToTheLoop()
        try Self.aRungNobodyHasSeen(under: fixture)

        let writesBefore = fixture.menuBar.glyphWriteCount
        let budgetBefore = fixture.host.todaysUsage().interruptionsToday

        exit.taken(by: fixture.host)
        NudgeHostFixture.settle()

        let writesDuringTeardown = fixture.menuBar.glyphWriteCount - writesBefore

        // **Non-vacuity, and it is the whole drive.** The defect needs the item to be written to
        // during the teardown — that write is what satisfied conjunct 1 — so an exit that wrote
        // nothing would pass every assertion below while driving none of this.
        try #require(
            writesDuringTeardown > 0,
            "\(exit): the item was never written during the teardown, so this proves nothing"
        )
        #expect(
            fixture.menuBar.markOnTheItem == .unmarked,
            """
            \(exit): the item is still drawing \(fixture.menuBar.markOnTheItem.rawValue) after \
            the exit, so the mark was not undone and this is not the measured state
            """
        )
        #expect(
            fixture.host.chargesPaidFor.isEmpty,
            """
            \(exit): \(writesDuringTeardown) write(s) during the teardown bought \
            \(fixture.host.chargesPaidFor.count) receipt(s) for a mark that was never composited \
            — \(fixture.host.chargesPaidFor.map(\.channel.rawValue))
            """
        )
        #expect(
            fixture.host.todaysUsage().interruptionsToday == budgetBefore,
            """
            \(exit): the day lost an interruption to a nudge nobody saw — \
            \(budgetBefore) -> \(fixture.host.todaysUsage().interruptionsToday)
            """
        )

        // **And the record does not say the person ignored anything.** The row this used to write
        // was `accusation/delivered/menuBar/ignored`: a delivery nobody was shown, completed with
        // the outcome `InterventionPolicy.ignoredAccusationBackoff` is named for, on a day when
        // nobody clicked anything.
        let rows = try Self.accusationRows(fixture)
        #expect(
            rows == ["unopened/menuBar/none"],
            """
            \(exit): the record says the app delivered an accusation and the person ignored it — \
            \(rows)
            """
        )
        // A rung nobody saw is still a thing the app did, and it still has a row (focus-sq7):
        // "charge nothing" must not be reachable by making the landing invisible to the record.
        #expect(try fixture.host.deliveredRowsToday() == fixture.host.chargesPaidFor.count)
        #expect(
            fixture.host.proofsOfferedOutsideATurn == 0,
            "\(exit): a proof was offered with no turn open, so its seam is somebody else's event"
        )
    }

    /// **And the seam still charges for what survives the turn** (focus-my0).
    ///
    /// The other side of the fence, and it is not optional: *"prove nothing was charged"* is
    /// satisfied perfectly by a loop that charges nothing ever, which is the failure the whole of
    /// U-1 is about. So the same state, ended the way a person ends it — the popover is opened,
    /// the question is answered, and the item is left drawing the rung's own mark — must charge
    /// exactly twice, and the charge must land before the call that caused it returns.
    @Test("a mark the turn leaves standing is charged, synchronously, before the call returns")
    func aMarkThatSurvivesTheTurnIsCharged() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try fixture.wireMenuBarToTheLoop()
        try Self.aRungNobodyHasSeen(under: fixture)

        let opened = try MenuBarStage.open(
            fixture.menuBar,
            showing: NudgeHostFixture.menuBarPresentation(of: fixture.host)
        )
        guard MenuBarStage.taken(opened) else { return }
        NudgeHostFixture.settle()
        fixture.host.answer(.notNow)

        // **No `settle()` above this line.** The seam is the end of the outermost call into the
        // host, not the next pass of the runloop: a charge a test has to wait for is a charge a
        // test can miss, and the self-check reads these numbers straight after the drive.
        #expect(
            fixture.menuBar.markOnTheItem == .noticing,
            "the question was answered and the item never fell to the rung's own mark"
        )
        #expect(
            fixture.host.chargesPaidFor.count == 2,
            """
            the popover showed the question and the item then said what the rung needed it to \
            say, and \(fixture.host.chargesPaidFor.count) receipt(s) were issued — \
            \(fixture.host.chargesPaidFor.map(\.channel.rawValue))
            """
        )
        #expect(
            fixture.host.chargesPaidFor.map(\.channel) == [.popoverContents, .menuBarItem],
            "the two receipts are not the two surfaces the person was actually shown"
        )
        // One interruption, not two: the question was an interruption and the ambient glyph is
        // not one (focus-ndh, focus-d6r). The receipt count and the cap are different arithmetics
        // over the same rows, and both have to be right.
        #expect(fixture.host.todaysUsage().interruptionsToday == 1)
        #expect(try fixture.host.deliveredRowsToday() == fixture.host.chargesPaidFor.count)
        #expect(fixture.host.proofsOfferedOutsideATurn == 0)
    }
}
