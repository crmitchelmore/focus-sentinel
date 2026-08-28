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
        intent: String = "Write the Q3 proposal for Acme"
    ) throws -> (root: AppComposition, priorityID: UUID) {
        let root = CompositionRootTests.root()
        root.joinHosts()
        let priorities = PriorityStore(
            context: root.modelContainer.mainContext,
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference)
        )
        let priorityID = try priorities.setPriority(intent: intent)
        root.nudgeHost.surroundings = {
            NudgeHostFixture.surroundings(monotonic: .seconds(10_000))
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
    static func askAQuestion(_ root: AppComposition) throws {
        root.relevanceHost.onJudgement?(
            NudgeHostFixture.uncertainJudgement(subject: Self.subject)
        )
        NudgeHostFixture.settle()
        try #require(root.nudgePanel.isVisible, "the loop did not put a question on the panel")
        try #require(root.nudgeHost.deliveredCount == 1)
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
        // The asking is written down against the commitment it was about, so it does not come
        // back the next time the person returns to it — and the new commitment inherits nothing.
        let ledger = Self.ledger(root)
        #expect(try ledger.receipts(priorityID: asked).count == 1)
        #expect(
            try ledger.hasAsked(priorityID: asked, subjectKind: .app, subject: Self.subject)
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
