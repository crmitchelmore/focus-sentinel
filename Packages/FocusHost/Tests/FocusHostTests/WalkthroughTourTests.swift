import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **The tour does its demonstrations on the real hosts, reads its steps done off the real
/// state, and puts the person's own priority back** (focus-u6de).
///
/// Driven through the composition root the way the cockpit's own controls are, so what these
/// hold is the product: a demo priority is a task in the store, a demo session is a session on
/// it, a step is done when the state says so and not when a button was pressed, and finishing
/// restores what was active before. The two demo nudges are drawn on the tour's own panel, so
/// the nudge loop's ledger and ladder are read here as untouched.
@Suite("The walkthrough's tour", .serialized)
@MainActor
struct WalkthroughTourTests {
    @Test("starting the tour remembers the active priority, and finishing puts it back")
    func finishingRestoresThePriority() throws {
        let (root, priorityID) = try CompositionRootWireTests.joinedRoot(clock: FixedMonotonicClock())
        defer { CompositionRootWireTests.tearDown(root) }
        #expect(root.cockpitState.priority?.id == priorityID)

        let tour = root.walkthroughTour
        tour.start()
        #expect(tour.isRunning)
        #expect(tour.step == .setDemoPriority)
        #expect(tour.previousPriorityID == priorityID)

        tour.perform(.setDemoPriority)
        let demoID = try #require(tour.demoTaskID)
        #expect(demoID != priorityID)
        #expect(root.cockpitState.priority?.id == demoID)
        #expect(root.cockpitState.priority?.intent == WalkthroughTour.demoIntent)

        tour.perform(.finishDemo)
        #expect(!tour.isRunning)
        #expect(root.cockpitState.priority?.id == priorityID, "the person's own priority was not put back")
        // The demo task stays in Recent, honestly: there is no delete, and a task that vanished
        // would be the app editing history.
        #expect(root.cockpitState.recent.contains { $0.id == demoID })
    }

    @Test("with nothing active before, finishing clears the demo priority")
    func finishingClearsWhenNothingWasActive() {
        let root = CompositionRootWireTests.root(clock: FixedMonotonicClock())
        defer { CompositionRootWireTests.tearDown(root) }
        root.joinHosts()
        #expect(root.cockpitState.priority == nil)

        let tour = root.walkthroughTour
        tour.start()
        #expect(tour.previousPriorityID == nil)
        tour.perform(.setDemoPriority)
        #expect(root.cockpitState.priority != nil)
        tour.perform(.finishDemo)
        #expect(root.cockpitState.priority == nil)
    }

    /// **A step is done when the state says so.** The person's own typing through the priority
    /// host — not the tour's button — is what marks the priority step done, and a priority that
    /// was already set when the step was entered does not count.
    @Test("the person doing the step themselves marks it done, and the baseline is what was there on arrival")
    func thePersonsOwnActionCounts() throws {
        let (root, _) = try CompositionRootWireTests.joinedRoot(clock: FixedMonotonicClock())
        defer { CompositionRootWireTests.tearDown(root) }
        let tour = root.walkthroughTour
        tour.start()
        // Arrived with a priority already set: not done.
        #expect(!tour.done.contains(.setDemoPriority))

        // What the cockpit's capture field does.
        root.priorityHost.setPriority(intent: "Write the report", doneWhen: nil)
        #expect(tour.done.contains(.setDemoPriority), "the refresh did not reach the tour")
        #expect(tour.performedActions.isEmpty, "the person's action was counted as the tour's")

        tour.go(to: .setDemoDoneWhen)
        #expect(tour.step == .setDemoDoneWhen)
        #expect(!tour.done.contains(.setDemoDoneWhen))
        let taskID = try #require(root.cockpitState.priority?.id)
        root.priorityHost.editDoneWhen(taskID: taskID, to: "Sent to the team")
        #expect(tour.done.contains(.setDemoDoneWhen))

        tour.go(to: .setDemoTimebox)
        root.priorityHost.setTimebox(taskID: taskID, seconds: 50 * 60)
        #expect(tour.done.contains(.setDemoTimebox))

        tour.go(to: .startDemoSession)
        root.sessionHost.startSession(kind: .countdown, plannedSeconds: 50 * 60, deadlineAt: nil)
        #expect(tour.done.contains(.startDemoSession))
        #expect(!tour.startedDemoSession, "the person's session was taken for the tour's")

        tour.finish(closingPanel: true)
        // The person's own session is theirs: finishing does not complete it.
        #expect(root.sessionHost.snapshot?.phase.isTerminal == false)
    }

    @Test("the session step starts a countdown session on the demo task, and finishing completes it")
    func theSessionStepStartsAndFinishes() {
        let root = CompositionRootWireTests.root(clock: FixedMonotonicClock())
        defer { CompositionRootWireTests.tearDown(root) }
        root.joinHosts()
        let tour = root.walkthroughTour
        tour.start()

        // Skipping the priority step is allowed: a later step sets the demo task itself.
        tour.go(to: .setDemoTimebox)
        tour.perform(.setDemoTimebox)
        #expect(tour.demoTaskID != nil)
        #expect(root.cockpitState.priority?.timeboxSeconds == WalkthroughTour.demoTimeboxSeconds)
        #expect(tour.done.contains(.setDemoTimebox))

        tour.go(to: .startDemoSession)
        tour.perform(.startDemoSession)
        #expect(tour.startedDemoSession)
        #expect(root.sessionHost.snapshot?.phase.isTerminal == false)
        #expect(tour.done.contains(.startDemoSession))

        tour.perform(.finishDemo)
        // Completing puts the session down: the host holds no live snapshot afterwards, or a
        // terminal one. Either is "not running", which is what finishing promises.
        #expect(root.sessionHost.snapshot.map(\.phase.isTerminal) ?? true)
    }

    @Test("the desk and rule steps put an app, a keyword and a rule on the demo task")
    func theDeskStepsFurnishTheDemo() {
        let root = CompositionRootWireTests.root(clock: FixedMonotonicClock())
        defer { CompositionRootWireTests.tearDown(root) }
        root.joinHosts()
        let tour = root.walkthroughTour
        tour.start()
        tour.perform(.setDemoPriority)
        tour.go(to: .addDemoDesk)
        tour.perform(.addDemoDesk)
        tour.go(to: .addDemoRule)
        tour.perform(.addDemoRule)

        let priority = root.cockpitState.priority
        #expect(priority?.contextItems.contains { $0.kind == .app && $0.value == WalkthroughTour.demoAppBundleID } == true)
        #expect(priority?.contextItems.contains { $0.kind == .keyword && $0.value == WalkthroughTour.demoKeyword } == true)
        #expect(priority?.rules.contains { $0.subject == WalkthroughTour.demoAppBundleID && $0.verdict == .relevant } == true)
        #expect(tour.performedActions == [.setDemoPriority, .addDemoDesk, .addDemoRule])
        #expect(tour.done.isSuperset(of: [.setDemoPriority, .addDemoDesk, .addDemoRule]))
    }

    /// **The demo nudges write nothing, and show themselves.** Arriving at the step draws the
    /// nudge on the tour's own panel; the loop's panel is not the one that showed, the store holds
    /// no new rule afterwards, and closing the panel is what marks the step done.
    @Test("the demo nudges show on arrival, on the tour's own panel, and closing them is the step")
    func theDemoNudgesAreInert() throws {
        let (root, _) = try CompositionRootWireTests.joinedRoot(clock: FixedMonotonicClock())
        defer { CompositionRootWireTests.tearDown(root) }
        let tour = root.walkthroughTour
        tour.start()
        let rulesBefore = root.cockpitState.priority?.rules.count ?? 0

        tour.go(to: .showDemoNudge)
        #expect(tour.demoPanel.isVisible)
        #expect(!tour.done.contains(.showDemoNudge))
        tour.demoPanel.onDismiss?()
        #expect(!tour.demoPanel.isVisible)
        #expect(tour.done.contains(.showDemoNudge))

        tour.go(to: .showDemoQuestion)
        #expect(tour.demoPanel.isVisible)
        tour.demoPanel.onDismiss?()
        #expect(tour.done.contains(.showDemoQuestion))

        #expect(root.cockpitState.priority?.rules.count == rulesBefore)
        #expect(tour.performedActions == [.showDemoNudge, .showDemoQuestion])
        tour.perform(.finishDemo)
        #expect(!tour.demoPanel.isVisible)
    }

    @Test("the settings step is done when the Settings window reports drawing")
    func theSettingsStepReadsTheWindow() {
        let root = CompositionRootWireTests.root(clock: FixedMonotonicClock())
        defer { CompositionRootWireTests.tearDown(root) }
        root.joinHosts()
        let tour = root.walkthroughTour
        tour.start()
        tour.go(to: .openPrivacySettings)
        #expect(!tour.done.contains(.openPrivacySettings))
        tour.settingsRendered()
        #expect(tour.done.contains(.openPrivacySettings))
        tour.finish(closingPanel: true)
    }

    @Test("the cockpit connection's Continue sink starts the tour")
    func theConnectionStartsTheTour() {
        let root = CompositionRootWireTests.root(clock: FixedMonotonicClock())
        defer { CompositionRootWireTests.tearDown(root) }
        root.joinHosts()

        root.cockpitConnection().onWalkthroughContinued()
        #expect(root.walkthroughTour.isRunning)
        root.walkthroughTour.finish(closingPanel: true)
        #expect(!root.walkthroughTour.isRunning)
    }
}
