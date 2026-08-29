import AppKit
import FocusCore
import FocusUI
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// **The loop is told when the world it was speaking about ends** (focus-d0a, U-1).
///
/// ## The defect these drive
///
/// `NudgeHost.sessionEnded()`, `phaseLeftFocus()` and `priorityChanged()` had three definitions
/// and **zero production callers**. `grep -rn` across `Packages/*/Sources` and `App` found the
/// names only inside a test, so nothing in the shipping graph ever told the loop that the session
/// had ended, that the phase had left focus, or that the person had committed to something else.
/// A question put up at ten in the morning was still on screen, still holding the one interruption
/// slot and still answerable, eight simulated hours and a different priority later.
///
/// Every test here drives a **shipping verb** — the cockpit's own mutation host, the session
/// host every menu item and button already calls — and reads the far end: the panel, the ledger,
/// the interruption slot. None of them calls `sessionEnded()`, `phaseLeftFocus()` or
/// `priorityChanged()`, which is the whole point: those were never the thing that was missing.
@Suite("The loop is told when the world ends", .serialized)
@MainActor
struct CompositionRootLifecycleTests {
    static let subject = "com.example.Reader"

    /// A root with its hosts joined, a commitment made, and the lifecycle baseline taken.
    ///
    /// The surroundings closure is replaced because it is the sensing boundary — the one place a
    /// test process must not reach through to real `NSWorkspace` state. Every other wire below is
    /// the shipping one.
    static func rootWithAPriority(
        intent: String = "Write the Q3 proposal for Acme",
        clock: FixedMonotonicClock = FixedMonotonicClock()
    ) throws -> (root: AppComposition, priorityID: UUID) {
        // The root is built here rather than through `CompositionRootTests.root()` because
        // these suites need to move the monotonic clock: a question re-asked after a break has
        // to step over `queryCooldown`, or what the loop is refusing is the cooldown rather
        // than the gate under test.
        let root = AppComposition(
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference),
            monotonicClock: clock,
            calendar: NudgeHostFixture.londonCalendar,
            locale: Locale(identifier: "en_GB"),
            hotKeyRegistrar: InertHotKeyRegistrar(),
            storeKind: .inMemory,
            notificationCentre: SilentNotificationCentre()
        )
        root.joinHosts()
        let priorities = PriorityStore(
            context: root.modelContainer.mainContext,
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference)
        )
        let priorityID = try priorities.setPriority(intent: intent)
        // The surroundings read the same clock the host does, so a test that advances time
        // advances it everywhere rather than in half the graph.
        let commitment = ActiveCommitment(id: priorityID, intent: intent)
        root.nudgeHost.surroundings = {
            NudgeHostFixture.surroundings(monotonic: clock.elapsed, commitment: commitment)
        }
        // The baseline reading: from here, anything the watch reports is a change a person made.
        root.refreshCockpit()
        return (root, priorityID)
    }

    static func ledger(_ root: AppComposition) -> QueryLedger {
        QueryLedger(
            context: root.modelContainer.mainContext,
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference)
        )
    }

    /// Put a real question on the real panel, through the real verdict stream.
    static func askAQuestion(
        _ root: AppComposition,
        expectedDeliveries: Int = 1
    ) throws {
        root.relevanceHost.onJudgement?(
            NudgeHostFixture.uncertainJudgement(subject: Self.subject)
        )
        NudgeHostFixture.settle()
        try #require(root.nudgePanel.isVisible, "the loop did not put a question on the panel")
        try #require(root.nudgeHost.deliveredCount == expectedDeliveries)
    }

    static func tearDown(_ root: AppComposition) {
        root.nudgeHost.hideOverlays()
        root.nudgePanel.hide()
        root.menuBar.closePopover()
        root.menuBar.remove()
        root.stop()
    }

    // MARK: - A different commitment

    /// **A new commitment ends the question asked about the old one** — through the cockpit's own
    /// `setPriority`, which is what the quick-capture panel and the handoff sheet both call.
    @Test("committing to a new priority ends the question asked under the old one")
    func aNewCommitmentEndsTheOpenQuestion() throws {
        let (root, asked) = try Self.rootWithAPriority()
        defer { Self.tearDown(root) }
        try Self.askAQuestion(root)

        root.cockpitActions.setPriority(intent: "Review the Acme contract", doneWhen: nil)

        #expect(
            !root.nudgePanel.isVisible,
            "a question about a commitment the person has left was left on screen to be answered"
        )
        #expect(
            root.nudgeHost.slot.isOpen,
            "the abandoned question is still holding the one interruption slot"
        )
        // The asking is written down against the commitment it was about — and the new
        // commitment inherits nothing (focus-lmo).
        let ledger = Self.ledger(root)
        #expect(try ledger.receipts(priorityID: asked).count == 1)
        #expect(
            try ledger.receipts(priorityID: asked).first?.outcome == .expired,
            "the ending was recorded as something the person did"
        )
        // **And it is not settled** (focus-qds, U-1). Nobody answered it: the world moved on.
        // A receipt is immutable and gate 11 reads it, so settling here would mean the person
        // never gets asked about this subject again for the commitment they had — an answer the
        // app wrote on their behalf because they changed their mind about what to work on.
        #expect(
            !(try ledger.isSettled(priorityID: asked, subjectKind: .app, subject: Self.subject)),
            "changing priority answered a question the person never answered"
        )
    }

    // MARK: - The session

    @Test("completing the session ends the question it was asked in")
    func aCompletedSessionEndsTheOpenQuestion() throws {
        let (root, asked) = try Self.rootWithAPriority()
        defer { Self.tearDown(root) }

        root.sessionActions.startSession(kind: .openEnded, plannedSeconds: nil, deadlineAt: nil)
        try #require(root.sessionHost.snapshot != nil, "no session was opened")
        try Self.askAQuestion(root)

        root.sessionActions.completeSession()

        #expect(
            !root.nudgePanel.isVisible,
            "a question outlived the session it was asked in"
        )
        #expect(root.nudgeHost.slot.isOpen)
        #expect(try Self.ledger(root).receipts(priorityID: asked).count == 1)
    }

    @Test("the phase leaving focus ends the question")
    func aPhaseLeavingFocusEndsTheOpenQuestion() throws {
        let (root, asked) = try Self.rootWithAPriority()
        defer { Self.tearDown(root) }

        root.sessionActions.startSession(kind: .openEnded, plannedSeconds: nil, deadlineAt: nil)
        try #require(root.sessionHost.snapshot?.phase == .focus)
        try Self.askAQuestion(root)

        root.sessionActions.startBreak(reason: .user)

        try #require(root.sessionHost.snapshot?.phase == .onBreak, "the session never left focus")
        #expect(
            !root.nudgePanel.isVisible,
            "a question asked during focus was left up for a person who has gone on a break"
        )
        #expect(try Self.ledger(root).receipts(priorityID: asked).count == 1)
    }

    // MARK: - focus-qds · a break is not an answer

    /// **The regression this epic introduced, driven through the running loop.**
    ///
    /// Wiring `sessionEnded()`, `phaseLeftFocus()` and `priorityChanged()` gave the expiry path
    /// its first callers — which is exactly why it is worth this test. Before the wiring the
    /// channel was unreachable; after it, *taking a break* is the ordinary way a question ends.
    /// If an expiry settled the question, one lunch would permanently answer it: the receipt is
    /// immutable, `isSettled(…)` is gate 11, and gate 11 is consulted before a warrant is even
    /// constructed.
    ///
    /// So: ask, break, come back, and be asked again. Mutate
    /// `AskedQuestionOutcome.settlesTheQuestion` or `QuestionEnding.settlesTheQuestion` to
    /// `true` for `.expired` and the person is never asked about this subject again.
    @Test("a question open when a break starts is asked again when the person comes back")
    func aBreakLeavesTheQuestionAskable() throws {
        let clock = FixedMonotonicClock()
        let (root, asked) = try Self.rootWithAPriority(clock: clock)
        defer { Self.tearDown(root) }

        root.sessionActions.startSession(kind: .openEnded, plannedSeconds: nil, deadlineAt: nil)
        try #require(root.sessionHost.snapshot?.phase == .focus)
        try Self.askAQuestion(root)

        root.sessionActions.startBreak(reason: .user)
        try #require(root.sessionHost.snapshot?.phase == .onBreak)
        try #require(!root.nudgePanel.isVisible)

        // The asking is on file — it happened, and the record of the day says so…
        let ledger = Self.ledger(root)
        #expect(try ledger.receipts(priorityID: asked).count == 1)
        #expect(try ledger.receipts(priorityID: asked).first?.outcome == .expired)
        // …and gate 11 does not treat it as an answer.
        #expect(
            !(try ledger.isSettled(priorityID: asked, subjectKind: .app, subject: Self.subject)),
            "going on a break answered a question the person never answered"
        )

        // Back to work. The cooldown a question owes the person passes — nothing about the
        // day's caps changes, so what is left standing between the person and a second asking
        // is gate 11 and gate 11 alone — and the same judgement arrives again.
        root.sessionActions.endBreak()
        try #require(root.sessionHost.snapshot?.phase == .focus)
        clock.advance(by: InterventionPolicy.queryCooldown + .seconds(1))

        try Self.askAQuestion(root, expectedDeliveries: 2)
        #expect(
            root.nudgePanel.isVisible,
            "the app had spent its one chance to ask, and never asked again"
        )
    }

    /// The other side of the same ruling, through the same loop: **an answered question is never
    /// re-asked.** Without this the fix above could be "never settle anything", which is the
    /// defect U-1 calls repeat-asking.
    @Test("an answered question is never asked again, break or no break")
    func anAnsweredQuestionIsNeverAskedAgain() throws {
        let (root, asked) = try Self.rootWithAPriority()
        defer { Self.tearDown(root) }

        root.sessionActions.startSession(kind: .openEnded, plannedSeconds: nil, deadlineAt: nil)
        try Self.askAQuestion(root)

        root.nudgeHost.answer(.yesAddIt)
        NudgeHostFixture.settle()

        let ledger = Self.ledger(root)
        #expect(try ledger.isSettled(priorityID: asked, subjectKind: .app, subject: Self.subject))

        // A break afterwards changes nothing, and neither does coming back to the same subject.
        root.sessionActions.startBreak(reason: .user)
        root.sessionActions.endBreak()
        root.relevanceHost.onJudgement?(
            NudgeHostFixture.uncertainJudgement(subject: Self.subject)
        )
        NudgeHostFixture.settle()

        #expect(
            !root.nudgePanel.isVisible,
            "a question the person answered was asked a second time"
        )
        #expect(try ledger.isSettled(priorityID: asked, subjectKind: .app, subject: Self.subject))
    }

    // MARK: - The control

    /// The other half of every assertion above: an ordinary tick with nothing happening leaves
    /// the question exactly where it was. Without this, a loop that simply tore every question
    /// down on every refresh would satisfy all three.
    @Test("an ordinary refresh with nothing changed leaves the question up")
    func anOrdinaryRefreshIsNotATransition() throws {
        let (root, asked) = try Self.rootWithAPriority()
        defer { Self.tearDown(root) }
        try Self.askAQuestion(root)

        root.refreshCockpit()
        root.refreshCockpit()

        #expect(root.nudgePanel.isVisible, "an ordinary refresh took a live question off screen")
        #expect(
            try Self.ledger(root).receipts(priorityID: asked).isEmpty,
            "an ordinary refresh spent the question's single licensed asking"
        )
    }
}
