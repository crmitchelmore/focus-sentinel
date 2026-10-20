import AppKit
import FocusCore
import FocusUI
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// **Every correction, in both states the app supports** (focus-rdw).
///
/// ## The quadrant that had no coverage
///
/// No open session is a *supported default working state*, not an edge. The code says so twice
/// — *"No open session is not a break: the person can be working with no session started"*, and
/// `phase: session?.phase ?? .focus` at both `judge(in:)` and `nudgeSurroundings()` — and there
/// is no auto-start anywhere: `startSession(` has exactly two shipping call sites and both are
/// clicks. So the ladder climbs and the panel appears with only a priority set.
///
/// In that state *"Not this time"* wrote nothing (`apply(_:…)` returned early on the missing
/// session identifier) and *"Pause"* threw `noOpenSession` into a swallowed `catch` whose
/// comment read *"which the surfaces already prevent"* — and this surface did not prevent it.
/// `resolve(_:snoozeDuration:)` went on regardless: it completed the row as `.corrected`, spent
/// fatigue, de-escalated the ladder and hid the panel. The person excused the app, the log
/// recorded a correction, nothing was learned, and the next mandate accused them about the very
/// thing they had just excused.
///
/// Every existing test that resolves a correction installs a session first — and until
/// `NudgeHostFixture` was given one, they did the opposite and asserted on it anyway. So this
/// suite is the cross product, driven through the shipping composition root: **what each action
/// is offered as, and what each action writes**, in both states.
///
/// The expected offer is read off `NudgeHost.openRungPresentation` — the value the surfaces are
/// actually drawn from — rather than recomputed here, because a test that derived its own list
/// would agree with itself instead of with the app.
@Suite("Every accusation action does what it promises, with and without a session", .serialized)
@MainActor
struct CorrectionTotalityTests {
    static let subject = NudgeHostFixture.decoy

    /// What one cell of the cross product claims.
    struct Promise {
        /// Whether a surface may offer this action in this state at all.
        let isOffered: Bool
        /// The row the intervention log must end up holding for this click, or `nil` when the
        /// click must write no outcome at all.
        let outcome: InterventionOutcome?
        /// The domain write, named so a failure says which one did not happen.
        let write: Write

        enum Write {
            /// A persisted `RuleAuthority.task` rule for the subject.
            case persistedRule
            /// A session-lived rule in the box, keyed on this session and priority.
            case sessionRule
            /// A running snooze for the subject.
            case snooze
            /// The person's own pause, on e03's machine (focus-mwm). It was
            /// `.command(.pauseSession)` — a send down a channel only the cockpit answers — and
            /// this suite hid that by registering a handler of its own, which is a cockpit the
            /// person did not have open.
            case pausedTheSession
            /// e02's quick-capture confirm surface, shown. `CorrectionAction.changePriority` is
            /// documented as opening it and did not: it sent `.newPriority` to the cockpit.
            case openedTheCaptureSurface
            /// Nothing at all — which is a promise as much as any other.
            case nothing
        }
    }

    /// **The table, and it is the specification.** One row per action per state, and the two
    /// session-scoped actions are the only cells that differ between the columns.
    static func promise(for action: CorrectionAction, sessionOpen: Bool) -> Promise {
        switch action {
        case .thisIsRelevant:
            Promise(isOffered: true, outcome: .corrected, write: .persistedRule)
        case .notThisTime:
            sessionOpen
                ? Promise(isOffered: true, outcome: .corrected, write: .sessionRule)
                : Promise(isOffered: false, outcome: nil, write: .nothing)
        case .snooze:
            Promise(isOffered: true, outcome: .snoozed, write: .snooze)
        case .changePriority:
            Promise(
                isOffered: true,
                outcome: .priorityChanged,
                write: .openedTheCaptureSurface
            )
        case .pause:
            sessionOpen
                ? Promise(isOffered: true, outcome: .pausedSession, write: .pausedTheSession)
                : Promise(isOffered: false, outcome: nil, write: .nothing)
        case .returnToTask:
            // Never offered in this harness and for a reason that is not about sessions: the
            // loop has been fed nothing but `unrelated`, so it has remembered no anchor, and a
            // "back to work" button with nowhere to go is a button that lies (R-88).
            Promise(isOffered: false, outcome: .returned, write: .nothing)
        case .dismiss:
            // The named "Continue with this priority" action is also available when Escape or
            // the close affordance is not an obvious choice. It closes the reminder and writes
            // no priority, rule or session changes (D-07).
            Promise(isOffered: true, outcome: .dismissed, write: .nothing)
        }
    }

    /// A recorder standing where the cockpit stands: the command centre's one handler.
    ///
    /// **It is a column of the fold now, not scaffolding** (focus-mwm). Installing one
    /// unconditionally is what made this suite green for a defect it drives directly: with a
    /// handler registered, every `send` lands, so `.pause` and `.changePriority` looked like they
    /// worked — and the state the person is actually in when a nudge panel is up is the *other*
    /// one. `CockpitView` registers this on `.onAppear` and unregisters it on `.onDisappear`, so
    /// "no handler" is precisely "the cockpit window is closed".
    @MainActor
    final class CommandSink {
        private(set) var commands: [PriorityCommand] = []
        func install() {
            FocusCommandCenter.shared.register { [self] command in commands.append(command) }
        }
        func remove() { FocusCommandCenter.shared.unregister() }
    }

    /// **Both states of the session and both states of the window**, spelled out because the
    /// test framework's `arguments:` takes two collections and this fold has three axes.
    nonisolated static let states: [(sessionOpen: Bool, cockpitIsOpen: Bool)] = [
        (sessionOpen: true, cockpitIsOpen: true),
        (sessionOpen: true, cockpitIsOpen: false),
        (sessionOpen: false, cockpitIsOpen: true),
        (sessionOpen: false, cockpitIsOpen: false)
    ]

    /// **The cross product**, driven through the composition root the application ships.
    ///
    /// Three axes and a two-axis table, and that is the claim: **the window is not one of the
    /// things a correction's promise depends on.** A nudge panel appears by construction while
    /// the person is working in another application, so the cockpit being closed is the common
    /// case for every click made on one — and `promise(for:sessionOpen:)` does not take
    /// `cockpitIsOpen`, so a write that only happens in one column fails here by name.
    @Test(
        "each correction is offered only where it can write, and writes exactly that",
        arguments: CorrectionAction.allCases, Self.states
    )
    func eachCorrectionKeepsItsPromise(
        _ action: CorrectionAction,
        state: (sessionOpen: Bool, cockpitIsOpen: Bool)
    ) throws {
        let sessionOpen = state.sessionOpen
        let cockpitIsOpen = state.cockpitIsOpen
        let clock = FixedMonotonicClock()
        let (root, priorityID) = try CompositionRootWireTests.joinedRoot(clock: clock)
        let sink = CommandSink()
        if cockpitIsOpen { sink.install() }
        defer {
            sink.remove()
            root.quickCapturePanel.hide()
            CompositionRootWireTests.tearDown(root)
        }
        #expect(FocusCommandCenter.shared.isConnected == cockpitIsOpen)

        if sessionOpen {
            root.sessionActions.startSession(kind: .openEnded, plannedSeconds: nil, deadlineAt: nil)
            try #require(root.sessionHost.snapshot != nil, "no session was opened")
        }
        // The state under test, asserted rather than assumed: the "no session" column is the
        // app's default, and a harness that had quietly opened one would be running the same
        // column twice.
        #expect((root.sessionHost.snapshot != nil) == sessionOpen)

        let rung = CompositionRootWireTests.escalateToARung(root, clock: clock)
        try #require(rung != nil, "the ladder never reached a rung, so there is nothing to answer")

        let promise = Self.promise(for: action, sessionOpen: sessionOpen)
        let log = InterventionLog(
            context: root.modelContainer.mainContext,
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference),
            calendar: NudgeHostFixture.londonCalendar
        )

        // **What the surfaces offer**, read off the value they are drawn from.
        let presentation = try #require(
            root.nudgeHost.openRungPresentation,
            "the open rung published no presentation, so no surface can offer anything"
        )
        #expect(
            presentation.offeredActions.contains(action) == promise.isOffered,
            """
            \(action) offered=\(presentation.offeredActions.contains(action)) \
            with sessionOpen=\(sessionOpen); the table says \(promise.isOffered)
            """
        )
        #expect(presentation.hasOpenSession == sessionOpen)

        let rulesBefore = try CompositionRootWireTests.rules(in: root, taskID: priorityID).count
        let outcomesBefore = try log.all().compactMap(\.outcome).count

        root.nudgeHost.resolve(action, snoozeDuration: InterventionPolicy.snoozeDurations.first)

        // **The write, by name.**
        let rulesAfter = try CompositionRootWireTests.rules(in: root, taskID: priorityID)
        let sessionRules = root.sessionHost.sessionRules(forPriority: priorityID)
        let snoozes = root.nudgeHost.activeSnoozes()

        switch promise.write {
        case .persistedRule:
            #expect(rulesAfter.count == rulesBefore + 1, "\(action) wrote no rule")
            #expect(rulesAfter.contains { $0.subject == Self.subject })
        case .sessionRule:
            #expect(sessionRules.count == 1, "\(action) wrote no session rule")
            #expect(sessionRules.first?.subject == Self.subject)
        case .snooze:
            #expect(snoozes.contains { $0.subject.identifier == Self.subject })
        case .pausedTheSession:
            // The session itself, not a command about one. `.paused` is the phase a `.user`
            // pause leaves it in, and only a `.user` resume lifts it.
            #expect(
                root.sessionHost.snapshot?.phase == .paused,
                "\(action) did not pause the session (cockpitIsOpen=\(cockpitIsOpen))"
            )
        case .openedTheCaptureSurface:
            #expect(
                root.quickCapturePanel.isVisible,
                "\(action) did not open the capture surface (cockpitIsOpen=\(cockpitIsOpen))"
            )
        case .nothing:
            #expect(rulesAfter.count == rulesBefore, "\(action) wrote a rule it does not promise")
            #expect(sessionRules.isEmpty, "\(action) wrote a session rule it does not promise")
            #expect(snoozes.isEmpty, "\(action) wrote a snooze it does not promise")
            #expect(!root.quickCapturePanel.isVisible, "\(action) opened a surface it does not promise")
        }
        // **No correction routes anything through the cockpit's buffer any more** (focus-mwm).
        // The two that did are the two this table now names by their real destination, and a
        // command sent from here with the window shut would be a command stored for ever.
        #expect(sink.commands.isEmpty, "\(action) sent a command down a channel a window owns")
        if action == .dismiss {
            #expect(
                root.priorityHost.state.priority?.id == priorityID,
                "continuing with this priority changed or cleared it"
            )
        }

        // **And what it recorded**, which is the half that was false: the refused actions used to
        // complete their row as `.corrected` while writing nothing at all.
        let outcomes = try log.all().compactMap(\.outcome)
        if let expected = promise.outcome {
            #expect(outcomes.count == outcomesBefore + 1, "\(action) recorded no outcome")
            #expect(outcomes.contains(expected), "\(action) did not record \(expected)")
        } else {
            #expect(
                outcomes.count == outcomesBefore,
                """
                \(action) recorded an outcome with no session to write in: the log says the \
                person corrected something the app never learned
                """
            )
        }
    }

    /// **A refused click leaves the nudge on the screen.**
    ///
    /// The defect was not a dropped click, it was a click that *looked obeyed*: the panel went
    /// away, so the person had every reason to believe the app had understood them. Nothing may
    /// come down for a correction the loop refused.
    @Test("a correction the loop refuses takes nothing off the screen")
    func aRefusedCorrectionLeavesTheRungStanding() throws {
        let clock = FixedMonotonicClock()
        let (root, _) = try CompositionRootWireTests.joinedRoot(clock: clock)
        defer { CompositionRootWireTests.tearDown(root) }

        try #require(root.sessionHost.snapshot == nil, "this is the no-session column")
        let rung = CompositionRootWireTests.escalateToARung(root, clock: clock)
        try #require(rung != nil)

        for action in CorrectionAction.allCases where action.requiresOpenSession {
            root.nudgeHost.resolve(action, snoozeDuration: nil)
            #expect(
                root.nudgeHost.currentRung == rung,
                "\(action) de-escalated the ladder for a write that never happened"
            )
            #expect(
                root.nudgeHost.openRungPresentation != nil,
                "\(action) forgot the rung the person is still looking at"
            )
        }
        // The invariant the loop keeps about itself: nothing is left drawn that it has forgotten.
        #expect(root.nudgeHost.orphanedNudgeSurfaces.isEmpty)
    }
}
