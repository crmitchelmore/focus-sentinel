import AppKit
import FocusCore
import FocusUI
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// **The four wires `startNudgeLoop()` makes, driven rather than looked at** (focus-22m).
///
/// ## The defect these drive
///
/// Four no-op mutations in the composition root survived the entire lane — 1 547 tests, three
/// lints, and an application that still built — because the wires were asserted to **exist**
/// rather than to **work**:
///
/// | | wire | what the mutation was | what it cost |
/// |---|---|---|---|
/// | S1 | `menuBar.onPopoverDidShow` | a non-nil no-op | no badge question is ever delivered, counted or written, and U-1's *"repeat-asking is a defect"* fires on every badge-routed question |
/// | S2 | `nudgeHost.onCorrection` | `{ _ in }` | R-86's *"one click becomes one write"* writes nothing, on every panel click |
/// | S3 | `FocusCommandCenter.shared.observe` | `{ _ in }` | F-145's key equivalents reach the cockpit and not the loop |
/// | S4 | `nudgeHost.currentSessionID` | `{ nil }` | `NudgeHost` returns early on `nil`, so "Not this time" silently stops working |
///
/// `CompositionRootTests.thePopoverWireReachesTheLoop` asserted `!= nil`, which a no-op closure
/// satisfies. `MenuBarPopoverTests` and `NudgeHostQuestionTests` install closures of **their
/// own**, so the shipping wire was never run by anything. `CompositionRootTests` calls
/// `root.perform(_:)` directly rather than through `onCorrection`.
///
/// So the rule every test below keeps: **drive the real closure and observe the effect at the far
/// end.** Never assert non-nil. Never install a closure of its own.
///
/// The one substitution is `nudgeHost.surroundings`, which is the sensing boundary — the single
/// place a test process must not reach through to live `NSWorkspace` state. Everything else is
/// the shipping object: the real panel, the real status item, the real stores.
@Suite("The composition root's wires, driven", .serialized)
@MainActor
struct CompositionRootWireTests {
    static let subject = NudgeHostFixture.decoy

    /// A root whose monotonic clock the test can advance, so the ladder can be climbed at a
    /// cadence the test chooses rather than however long the machine took.
    static func root(clock: FixedMonotonicClock) -> AppComposition {
        AppComposition(
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference),
            monotonicClock: clock,
            calendar: NudgeHostFixture.londonCalendar,
            locale: Locale(identifier: "en_GB"),
            hotKeyRegistrar: InertHotKeyRegistrar(),
            storeKind: .inMemory,
            notificationCentre: SilentNotificationCentre()
        )
    }

    /// Everything joined, a commitment made, and the world held still.
    static func joinedRoot(
        clock: FixedMonotonicClock
    ) throws -> (root: AppComposition, priorityID: UUID) {
        let root = Self.root(clock: clock)
        root.joinHosts()
        let priorities = PriorityStore(
            context: root.modelContainer.mainContext,
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference)
        )
        let priorityID = try priorities.setPriority(intent: "Write the Q3 proposal for Acme")
        root.nudgeHost.surroundings = { NudgeHostFixture.surroundings(monotonic: clock.elapsed) }
        root.refreshCockpit()
        return (root, priorityID)
    }

    static func tearDown(_ root: AppComposition) {
        root.nudgeHost.hideOverlays()
        root.nudgePanel.hide()
        root.menuBar.closePopover()
        root.menuBar.remove()
        root.stop()
    }

    static func rules(
        in root: AppComposition,
        taskID: UUID
    ) throws -> [FocusSchemaV3.RelevanceRule] {
        try root.modelContainer.mainContext
            .fetch(FetchDescriptor<FocusSchemaV3.RelevanceRule>())
            .filter { $0.task?.id == taskID }
    }

    /// Climb until the loop is standing on a rung, through the shipping verdict stream.
    @discardableResult
    static func escalateToARung(
        _ root: AppComposition,
        clock: FixedMonotonicClock
    ) -> LadderRung.Kind? {
        for _ in 0..<6 {
            root.relevanceHost.onJudgement?(
                NudgeHostFixture.unrelatedJudgement(subject: Self.subject)
            )
            NudgeHostFixture.settle()
            if root.nudgeHost.currentRung != nil { return root.nudgeHost.currentRung }
            clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }
        return root.nudgeHost.currentRung
    }

    // MARK: - S1 · the badge question is delivered when the popover opens

    /// **The popover wire, run.**
    ///
    /// `SurfaceRouter` sends a question to the badge on three ordinary conditions — the
    /// `silentVisual` deck, reduced interruption (forced on by Reduce Motion), and a live
    /// microphone or camera, which is to say anybody on a call. The popover opens only when a
    /// person clicks the status item, and the menu bar is the only object that knows the click
    /// happened. With this wire a no-op, that click reaches nobody: the question is never
    /// delivered, never counted, never written — and because it is never written, gate 11 never
    /// suppresses it, so the app asks the same question again and again for the life of the
    /// priority. That is U-1's *"repeat-asking is a defect"*, on every badge-routed question.
    ///
    /// The stage does **not** install a closure here. That is the whole difference between this
    /// and the assertion it replaces.
    @Test("the popover wire delivers a badge question when a person opens the popover")
    func thePopoverWireDeliversTheQuestion() throws {
        let clock = FixedMonotonicClock()
        let (root, priorityID) = try Self.joinedRoot(clock: clock)
        defer { Self.tearDown(root) }

        root.nudgeHost.preferences = NudgePreferences(
            voice: .standard, reducedInterruption: true
        )
        root.relevanceHost.onJudgement?(
            NudgeHostFixture.uncertainJudgement(subject: Self.subject)
        )
        NudgeHostFixture.settle()

        guard case .ask(_, .surface(.popoverBadge)) = root.nudgeHost.lastDecision else {
            Issue.record(
                "the question was not routed to the badge: \(String(describing: root.nudgeHost.lastDecision))"
            )
            return
        }
        // The invitation is up, and nothing has been delivered: nobody has looked yet.
        try #require(root.nudgeHost.pendingPopoverQuery != nil)
        try #require(root.nudgeHost.deliveredCount == 0)

        // The click. Nothing here wires `onPopoverDidShow` — the root already did, and that is
        // the closure under test.
        try MenuBarStage.open(
            root.menuBar,
            showing: root.menuBarPresentation(),
            install: false
        )

        #expect(root.menuBar.isShowingQuery)
        #expect(
            root.nudgeHost.deliveredCount == 1,
            "the popover opened on the question and nothing in the programme told the loop"
        )
        let log = InterventionLog(
            context: root.modelContainer.mainContext,
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference),
            calendar: NudgeHostFixture.londonCalendar
        )
        let rows = try log.all()
        #expect(rows.count == 1)
        #expect(rows.first?.disposition == .delivered)
        #expect(rows.first?.surface == .popoverBadge)
        #expect(try log.budget(on: log.today, priorityID: priorityID).queriesForPriorityToday == 1)
    }

    // MARK: - S2 · one click becomes one write

    /// **The correction wire, run** (R-86, F-93).
    ///
    /// `NudgeHost` calls `onCorrection` from three places — the query answer and both correction
    /// paths — which is every panel click that writes anything. The root's closure is what turns
    /// the decided outcome into a row through the rules store, and it is also what gives that row
    /// its ⌘Z. With the wire a no-op, "This is relevant" takes the nudge off the screen and
    /// teaches the app nothing at all.
    ///
    /// Driven through `resolve(_:snoozeDuration:)` — the function the panel's buttons call —
    /// rather than through `root.perform(_:)`, which is what the older test did and which skips
    /// the wire entirely.
    @Test("a correction on a live rung writes exactly one rule, with its undo")
    func theCorrectionWireWritesTheRule() throws {
        let clock = FixedMonotonicClock()
        let (root, priorityID) = try Self.joinedRoot(clock: clock)
        defer { Self.tearDown(root) }
        let manager = UndoManager()
        root.adoptUndoManager(manager)

        let rung = Self.escalateToARung(root, clock: clock)
        try #require(rung != nil, "the ladder never reached a rung, so there is nothing to correct")
        try #require(try Self.rules(in: root, taskID: priorityID).isEmpty)

        root.nudgeHost.resolve(.thisIsRelevant, snoozeDuration: nil)

        let written = try Self.rules(in: root, taskID: priorityID)
        #expect(
            written.count == 1,
            "one click on 'This is relevant' taught the app nothing: the correction wire is dead"
        )
        #expect(written.first?.subject == Self.subject)
        #expect(written.first?.verdictRaw == PriorityRuleVerdict.relevant.rawValue)
        #expect(manager.canUndo, "the correction landed without the ⌘Z F-93 promises")
    }

    /// The other correction the wire carries, and the one that goes to a different destination:
    /// an answered question is `.ruleAndReceipt`, already written by the ledger's own
    /// transaction, so what the root still owes is the undo the transaction had no journal to
    /// register with.
    @Test("an answered question reaches the root and gains its undo")
    func theCorrectionWireCarriesAnAnswer() throws {
        let clock = FixedMonotonicClock()
        let (root, priorityID) = try Self.joinedRoot(clock: clock)
        defer { Self.tearDown(root) }
        let manager = UndoManager()
        root.adoptUndoManager(manager)

        root.relevanceHost.onJudgement?(
            NudgeHostFixture.uncertainJudgement(subject: Self.subject)
        )
        NudgeHostFixture.settle()
        try #require(root.nudgePanel.isVisible)

        root.nudgeHost.answer(.yesAddIt)

        #expect(try Self.rules(in: root, taskID: priorityID).count == 1)
        #expect(manager.canUndo, "R-86's yes row lost its ⌘Z: the correction wire is dead")
    }

    // MARK: - S3 · every command reaches the loop as well as the cockpit

    /// **The command wire, run** (F-145, F-81).
    ///
    /// One queue, one order, two destinations: the cockpit answers the capture and session verbs
    /// and the loop answers the four nudge ones. `hideOverlays` is the one that can be read from
    /// outside without ambiguity — it takes every overlay off the screen and writes nothing at
    /// all, which is exactly what makes it a clean probe of whether the command arrived.
    @Test("a command sent through the command centre reaches the nudge loop")
    func theCommandWireReachesTheLoop() throws {
        let clock = FixedMonotonicClock()
        let (root, priorityID) = try Self.joinedRoot(clock: clock)
        defer { Self.tearDown(root) }

        root.relevanceHost.onJudgement?(
            NudgeHostFixture.uncertainJudgement(subject: Self.subject)
        )
        NudgeHostFixture.settle()
        try #require(root.nudgePanel.isVisible, "there is no overlay for the command to hide")

        FocusCommandCenter.shared.send(.hideOverlays)

        #expect(
            !root.nudgePanel.isVisible,
            "the View menu's Hide Overlays reaches the cockpit and not the loop"
        )
        #expect(root.nudgeHost.slot.isOpen)
        // F-81's other half: the person asked for their screen back, not to tell the app
        // anything, so nothing is written and the question is still askable.
        let ledger = QueryLedger(
            context: root.modelContainer.mainContext,
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference)
        )
        #expect(try ledger.receipts(priorityID: priorityID).isEmpty)
    }

    // MARK: - S4 · "Not this time" has a session to die with

    /// **The session-identifier wire, run** (R-72.2).
    ///
    /// A `.notThisTime` correction is a **session-lived** rule, and `NudgeHost.apply(_:…)`
    /// returns early when `currentSessionID` answers `nil`. With the wire returning `nil`, the
    /// button is still drawn, still clicked and still takes the nudge away — and the rule it
    /// promised is never written, so the very next classification accuses the person again about
    /// the thing they just excused. A silent failure with a visible affordance on top.
    @Test("'Not this time' writes a session rule the very next classification can read")
    func theSessionWireWritesTheSessionRule() throws {
        let clock = FixedMonotonicClock()
        let (root, priorityID) = try Self.joinedRoot(clock: clock)
        defer { Self.tearDown(root) }

        root.sessionActions.startSession(kind: .openEnded, plannedSeconds: nil, deadlineAt: nil)
        try #require(root.sessionHost.snapshot != nil, "no session was opened")

        let rung = Self.escalateToARung(root, clock: clock)
        try #require(rung != nil, "the ladder never reached a rung, so there is nothing to excuse")
        try #require(root.sessionHost.sessionRules(forPriority: priorityID).isEmpty)

        root.nudgeHost.resolve(.notThisTime, snoozeDuration: nil)

        let rules = root.sessionHost.sessionRules(forPriority: priorityID)
        #expect(
            rules.count == 1,
            "'Not this time' wrote nothing: the loop was never told which session it belongs to"
        )
        #expect(rules.first?.subject == Self.subject)
        #expect(rules.first?.verdict == .relevant)
        // It is the same box the relevance host reads through, so the rule is one the very next
        // classification consults rather than a second opinion (R-72.2).
        #expect(
            root.relevanceHost.sessionRules?(priorityID).count == 1,
            "the rule landed somewhere the engine does not read"
        )
    }
}
