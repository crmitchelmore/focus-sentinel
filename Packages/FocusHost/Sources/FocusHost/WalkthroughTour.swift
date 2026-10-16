import AppKit
import FocusCore
import FocusUI
import Foundation
import os

/// **The tour, on the real app** (focus-u6de).
///
/// ## What it is
///
/// The walkthrough's first page is a sheet that says what the app watches. Its Continue button
/// opens this: a floating panel (`WalkthroughPanelController`) that walks eleven steps, and on
/// each one moves beside the control the step is about, outlines it, and asks the person to do
/// the thing there — type the priority, press Start, configure its context. The app's own state says when
/// it has been done; a *Do it for me* button does it through the same hosts for anybody who
/// would rather watch. This object is the only thing that performs those actions, and it
/// performs them through the hosts the cockpit's own controls call, so a demo is the product
/// rather than a picture of it.
///
/// ## How a step knows it was done
///
/// Every mutation in this app ends in `AppComposition.refreshCockpit()`, the popover reports
/// showing through `MenuBarController.onPopoverDidShow`, and the Settings window reports drawing
/// through `noteSettingsRendering`. All three call `noticeChange()` here while the tour runs,
/// and `noticeChange()` compares the state now with the reading taken when the step was entered.
/// No timer, no polling: the readings the app already produces are the readings the tour takes.
///
/// ## What it touches, and how it puts it back
///
/// * The demo priority is a **real task**, set by the person or by *Do it for me*. It appears in
///   Recent, and finishing does not delete it — there is no delete, and a task that vanished
///   from Recent would be the app editing history. Finishing re-activates the priority that was
///   active before the tour, or clears if there was none.
/// * The demo session is a **real session** on the demo task, started only if no session was
///   running, and completed by finishing.
/// * The desk items and the rule belong to the demo task and stay with it.
/// * The two demo nudges are drawn on a **panel of this object's own** — a second
///   `NudgePanelController`, never the nudge loop's — with presentations built here from a demo
///   subject. Their buttons only hide the panel: nothing reaches `NudgeHost.resolve`, no rule is
///   written, no receipt is kept, no budget is charged.
///
/// Closing the panel by any route is *Finish the demo*: a tour abandoned halfway still puts the
/// person's own priority back.
@MainActor
final class WalkthroughTour {
    private let logger = Logger(subsystem: FocusStore.bundleIdentifier, category: "WalkthroughTour")

    private let priorityHost: PriorityHost
    private let sessionHost: SessionHost
    private let menuBar: MenuBarController
    private let anchors: WalkthroughAnchorRegistry
    private let traits: () -> AppearanceTraits
    private let voice: () -> NudgeVoice
    private let openSettings: (SettingsTab) -> Void
    private let cockpitWindow: () -> NSWindow?

    /// The floating panel, built on first use so a launch that never presses Continue never
    /// builds a window for it.
    private(set) lazy var panel: WalkthroughPanelController = {
        let controller = WalkthroughPanelController(traits: traits())
        controller.onAction = { [weak self] action in self?.perform(action) }
        controller.onNavigate = { [weak self] step in self?.go(to: step) }
        controller.onClose = { [weak self] in self?.finish(closingPanel: false) }
        return controller
    }()

    /// The demo nudges' own panel. Never the nudge loop's: see the type's documentation.
    private(set) lazy var demoPanel: NudgePanelController = {
        let controller = NudgePanelController(traits: traits())
        controller.onDismiss = { [weak self, weak controller] in
            controller?.hide()
            self?.noticeChange()
        }
        return controller
    }()

    private(set) var previousPriorityID: UUID?
    private(set) var demoTaskID: UUID?
    private(set) var startedDemoSession = false
    private(set) var isRunning = false
    private(set) var step: WalkthroughAction = .firstStep
    /// Every action performed through the fallback, in order — a trace for a bug report.
    private(set) var performedActions: [WalkthroughAction] = []
    /// The steps the app's state has said were done.
    private(set) var done: Set<WalkthroughAction> = []

    /// **The reading taken when the current step was entered**, which is what "done" is measured
    /// against: a priority that was already set before the step is not the person setting one.
    private var baseline = Baseline()
    private struct Baseline {
        var priorityID: UUID?
        var doneWhen: String?
        var timeboxSeconds: Int?
        var sessionStartedAt: Date?
        var contextCount = 0
        var ruleCount = 0
        var popoverShown = false
        var settingsRendered = false
        var demoPanelShown = false
        var demoPanelClosed = false
    }

    private var windowObservers: [NSObjectProtocol] = []

    /// The demo priority's words. Catalog strings, resolved by `FocusUI`, so they read in the
    /// person's language.
    static var demoIntent: String { WalkthroughDemo.intent }
    static var demoDoneWhen: String { WalkthroughDemo.doneWhen }
    /// The app the demo desk names. Notes ships on every Mac.
    static let demoAppBundleID = "com.apple.Notes"
    static let demoAppName = "Notes"
    static let demoKeyword = "focus"
    /// The app the demo nudges are about: something plausibly off-task on every Mac.
    static let demoDistractionBundleID = "com.apple.MobileSMS"
    static let demoDistractionName = "Messages"
    /// The demo timebox: the first preset, in seconds.
    static let demoTimeboxSeconds = 25 * 60
    /// How long the demo nudges say the person has dwelled.
    static let demoDwell: Duration = .seconds(5 * 60)

    init(
        priorityHost: PriorityHost,
        sessionHost: SessionHost,
        menuBar: MenuBarController,
        anchors: WalkthroughAnchorRegistry = .shared,
        traits: @escaping () -> AppearanceTraits,
        voice: @escaping () -> NudgeVoice,
        openSettings: @escaping (SettingsTab) -> Void,
        cockpitWindow: @escaping () -> NSWindow? = { WalkthroughTour.findCockpitWindow() }
    ) {
        self.priorityHost = priorityHost
        self.sessionHost = sessionHost
        self.menuBar = menuBar
        self.anchors = anchors
        self.traits = traits
        self.voice = voice
        self.openSettings = openSettings
        self.cockpitWindow = cockpitWindow
    }

    /// The cockpit's window, by the identifier SwiftUI gives a `Window(id:)` scene.
    static func findCockpitWindow() -> NSWindow? {
        NSApp?.windows.first { $0.identifier?.rawValue == ShellWindow.cockpit.id && $0.isVisible }
    }

    // MARK: - Running

    /// Open the tour on its first step, remembering what to put back. Idempotent while running.
    func start() {
        if !isRunning {
            previousPriorityID = priorityHost.state.priority?.id
            demoTaskID = nil
            startedDemoSession = false
            performedActions = []
            done = []
            isRunning = true
            lastDrawn = nil
            anchors.onChange = { [weak self] in self?.reanchor() }
            observeWindow()
            panel.update(traits: traits())
            panel.show()
            enter(.firstStep)
        } else {
            present()
        }
    }

    /// Back or Next: leave the current step, arrive at another.
    func go(to step: WalkthroughAction) {
        guard isRunning else { return }
        enter(step)
    }

    /// Arrive at a step: take the baseline reading, perform what performs on arrival, and draw.
    private func enter(_ step: WalkthroughAction) {
        self.step = step
        baseline = Baseline(
            priorityID: priorityHost.state.priority?.id,
            doneWhen: priorityHost.state.priority?.doneWhen,
            timeboxSeconds: priorityHost.state.priority?.timeboxSeconds,
            sessionStartedAt: liveSession?.startedAt,
            contextCount: priorityHost.state.priority?.contextItems.count ?? 0,
            ruleCount: priorityHost.state.priority?.rules.count ?? 0
        )
        if step.performsOnArrival, !done.contains(step) {
            perform(step)
        }
        present()
    }

    /// What the panel was last drawn for, so a refresh that changed nothing the panel shows
    /// does not move it: the cockpit refreshes every five seconds, and a panel the person had
    /// dragged aside that snapped back on every tick would be a panel fighting them.
    private var lastDrawn: Drawing?
    private struct Drawing: Equatable {
        var step: WalkthroughAction
        var target: CGRect?
        var isDone: Bool
    }

    /// Draw the current step beside its control, if the control is on screen.
    private func present() {
        panel.model.done = done
        let window = cockpitWindow()
        let target = step.anchors.lazy
            .compactMap { self.anchors.screenRect(of: $0, in: window) }
            .first ?? demoPanelTarget()
        let drawing = Drawing(step: step, target: target, isDone: done.contains(step))
        guard drawing != lastDrawn else { return }
        lastDrawn = drawing
        panel.present(step: step, target: target, beside: window)
    }

    /// The demo panel's own frame, for the two steps that point at it.
    private func demoPanelTarget() -> CGRect? {
        guard step.performsOnArrival, demoPanel.isVisible else { return nil }
        let frame = demoPanel.frame
        return CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }

    /// A control moved or came on screen: put the panel and the mark back beside it.
    private func reanchor() {
        guard isRunning else { return }
        present()
    }

    /// **Something in the app changed.** Called by the composition root after every mutation,
    /// by the popover when it shows, and by the Settings window when it draws. Reads the step's
    /// completion off the state, records it, and re-anchors.
    func noticeChange() {
        guard isRunning else { return }
        if isStepDone(step) {
            done.insert(step)
        }
        present()
    }

    /// The popover showed. One of the readings `noticeChange()` compares.
    func popoverShown() {
        baseline.popoverShown = true
        noticeChange()
    }

    /// The Settings window drew. One of the readings `noticeChange()` compares.
    func settingsRendered() {
        baseline.settingsRendered = true
        noticeChange()
    }

    /// Whether the app's state says the step was done since it was entered.
    private func isStepDone(_ step: WalkthroughAction) -> Bool {
        let priority = priorityHost.state.priority
        switch step {
        case .setDemoPriority:
            return priority != nil && priority?.id != baseline.priorityID
        case .setDemoDoneWhen:
            guard let doneWhen = priority?.doneWhen, !doneWhen.isEmpty else { return false }
            return doneWhen != baseline.doneWhen
        case .setDemoTimebox:
            return priority?.timeboxSeconds != nil && priority?.timeboxSeconds != baseline.timeboxSeconds
        case .startDemoSession:
            guard let session = liveSession else { return false }
            return session.startedAt != baseline.sessionStartedAt
        case .addDemoDesk:
            return (priority?.contextItems.count ?? 0) > baseline.contextCount
        case .addDemoRule:
            return (priority?.rules.count ?? 0) > baseline.ruleCount
        case .showDemoNudge, .showDemoQuestion:
            if demoPanel.isVisible { baseline.demoPanelShown = true }
            if baseline.demoPanelShown, !demoPanel.isVisible { baseline.demoPanelClosed = true }
            return baseline.demoPanelClosed
        case .openMenuBar:
            return baseline.popoverShown || menuBar.isPopoverShown
        case .openPrivacySettings:
            return baseline.settingsRendered
        case .finishDemo:
            return false
        }
    }

    private var liveSession: SessionSnapshot? {
        guard let session = sessionHost.snapshot, !session.phase.isTerminal else { return nil }
        return session
    }

    // MARK: - Doing it for them

    /// Perform a step through the hosts. The same call the person's own click would end in.
    func perform(_ action: WalkthroughAction) {
        guard isRunning else { return }
        switch action {
        case .setDemoPriority:
            priorityHost.setPriority(intent: Self.demoIntent, doneWhen: nil)
            demoTaskID = priorityHost.state.priority?.id
        case .setDemoDoneWhen:
            priorityHost.editDoneWhen(taskID: demoTask(), to: Self.demoDoneWhen)
        case .setDemoTimebox:
            priorityHost.setTimebox(taskID: demoTask(), seconds: Self.demoTimeboxSeconds)
        case .startDemoSession:
            _ = demoTask()
            // Only where no session is running: a person mid-session keeps theirs.
            if liveSession == nil {
                sessionHost.startSession(kind: .countdown, plannedSeconds: Self.demoTimeboxSeconds, deadlineAt: nil)
                startedDemoSession = true
            }
        case .addDemoDesk:
            let task = demoTask()
            priorityHost.addContext(
                taskID: task,
                item: ContextItemDraft(kind: .app, value: Self.demoAppBundleID, displayName: Self.demoAppName)
            )
            priorityHost.addContext(
                taskID: task,
                item: ContextItemDraft(kind: .keyword, value: Self.demoKeyword, displayName: Self.demoKeyword)
            )
        case .addDemoRule:
            priorityHost.addRule(taskID: demoTask(), scope: .app, subject: Self.demoAppBundleID, verdict: .relevant)
        case .showDemoNudge:
            baseline.demoPanelShown = false
            baseline.demoPanelClosed = false
            let presentation = AccusationPresentation(
                rung: .panel,
                voice: voice(),
                task: priorityHost.state.priority?.intent ?? Self.demoIntent,
                subject: NudgeSubject.named(Self.demoDistractionBundleID, runningName: Self.demoDistractionName),
                dwelled: Self.demoDwell,
                returnTarget: nil,
                snoozeRemaining: nil,
                hasOpenSession: liveSession != nil
            )
            let view = AccusationPanelView(presentation: presentation) { [weak self] _, _ in
                self?.demoPanel.hide()
                self?.noticeChange()
            }
            demoPanel.update(view, traits: traits())
            _ = demoPanel.show(presentationIsClear: true, announcement: presentation.announcement())
        case .showDemoQuestion:
            baseline.demoPanelShown = false
            baseline.demoPanelClosed = false
            guard let subject = NudgeSubject.named(Self.demoDistractionBundleID, runningName: Self.demoDistractionName) else {
                return
            }
            let presentation = QueryPresentation(
                voice: voice(),
                task: priorityHost.state.priority?.intent ?? Self.demoIntent,
                subject: subject,
                reason: .mixedUseApplication,
                dwelled: Self.demoDwell
            )
            let view = QueryPanelView(presentation: presentation) { [weak self] _ in
                self?.demoPanel.hide()
                self?.noticeChange()
            }
            demoPanel.update(view, traits: traits())
            _ = demoPanel.show(presentationIsClear: true, announcement: presentation.announcement())
        case .openMenuBar:
            if !menuBar.isPopoverShown { menuBar.togglePopover() }
            baseline.popoverShown = true
        case .openPrivacySettings:
            openSettings(.privacy)
        case .finishDemo:
            finish(closingPanel: true)
            return
        }
        performedActions.append(action)
        noticeChange()
    }

    /// End the demo: hide the demo nudge, complete the demo session, put back the priority that
    /// was there before, and take the panel down. Idempotent.
    func finish(closingPanel: Bool) {
        guard isRunning else { return }
        isRunning = false
        performedActions.append(.finishDemo)
        anchors.onChange = nil
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers = []
        demoPanel.hide()
        if startedDemoSession, liveSession != nil {
            sessionHost.completeSession()
        }
        if let previousPriorityID {
            priorityHost.activate(taskID: previousPriorityID)
        } else if demoTaskID != nil {
            priorityHost.clear()
        }
        if closingPanel {
            panel.hide()
        } else {
            panel.highlight.hide()
        }
    }

    /// The demo task, set if the person skipped the step that sets it and pressed *Do it for me*
    /// on a later one: every later step is about it.
    private func demoTask() -> UUID {
        if let current = priorityHost.state.priority?.id {
            if demoTaskID == nil { demoTaskID = current }
            return current
        }
        priorityHost.setPriority(intent: Self.demoIntent, doneWhen: nil)
        let id = priorityHost.state.priority?.id ?? UUID()
        demoTaskID = id
        return id
    }

    /// Follow the cockpit window: a mark that stayed where the control was is a mark on nothing.
    private func observeWindow() {
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers = []
        guard let window = cockpitWindow() else { return }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            let observer = NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reanchor() }
            }
            windowObservers.append(observer)
        }
    }
}
