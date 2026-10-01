import FocusCore

/// **One thing the tour asks the person to do in the real app, and can do for them**
/// (focus-u6de).
///
/// Every step of the tour is one of these. The step points at the control, tells the person
/// what to do, and watches the app's state for it to have been done; the *Do it for me* button
/// performs the same thing through the hosts, for somebody who would rather watch. A closed
/// vocabulary for the reason every other vocabulary in this package is one: `FocusHost`
/// performs these, `FocusUI` draws them, and `WalkthroughTests` holds that every one has a page,
/// an instruction, a sentence for afterwards and at least one anchor.
///
/// Every action is **reversible or harmless**, and `finishDemo` is the reversal: the demo
/// priority is a real task (it stays in Recent, honestly), the demo session is a real session
/// that finishing completes, and the two demo nudges are drawn on a panel of their own whose
/// buttons write nothing.
public enum WalkthroughAction: String, Sendable, CaseIterable, Hashable, Identifiable {
    /// Set a priority: type one, or let the tour set "Try Focus Sentinel".
    case setDemoPriority
    /// Write its definition of done.
    case setDemoDoneWhen
    /// Give it a timebox; the tour chooses 25 minutes.
    case setDemoTimebox
    /// Start a session on it.
    case startDemoSession
    /// Put something on its desk; the tour adds Notes and a keyword.
    case addDemoDesk
    /// Add a rule; the tour marks Notes as related.
    case addDemoRule
    /// See an accusation, drawn on the tour's own panel whose buttons only close it.
    case showDemoNudge
    /// See a question, on the same panel.
    case showDemoQuestion
    /// Open the menu-bar popover.
    case openMenuBar
    /// Open Settings on the Privacy pane.
    case openPrivacySettings
    /// Complete the demo session and put back the priority that was there before.
    case finishDemo

    public var id: String { rawValue }

    /// The page this action belongs to, whose title the panel draws over it.
    public var page: WalkthroughPage {
        switch self {
        case .setDemoPriority, .setDemoDoneWhen: .priority
        case .setDemoTimebox, .startDemoSession: .time
        case .addDemoDesk, .addDemoRule: .desk
        case .showDemoNudge, .showDemoQuestion: .nudges
        case .openMenuBar: .menuBar
        case .openPrivacySettings, .finishDemo: .settings
        }
    }

    /// What the panel asks the person to do.
    public var instructionKey: ShellStringKey {
        switch self {
        case .setDemoPriority: .walkthroughStepSetPriority
        case .setDemoDoneWhen: .walkthroughStepDoneWhen
        case .setDemoTimebox: .walkthroughStepTimebox
        case .startDemoSession: .walkthroughStepStartSession
        case .addDemoDesk: .walkthroughStepDesk
        case .addDemoRule: .walkthroughStepRules
        case .showDemoNudge: .walkthroughStepNudge
        case .showDemoQuestion: .walkthroughStepQuestion
        case .openMenuBar: .walkthroughStepMenuBar
        case .openPrivacySettings: .walkthroughStepSettings
        case .finishDemo: .walkthroughStepFinish
        }
    }

    /// What the panel says once it has been done: what changed, and what a real one does.
    /// `nil` for `finishDemo`, which closes the panel.
    public var doneKey: ShellStringKey? {
        switch self {
        case .setDemoPriority: .walkthroughDoneSetPriority
        case .setDemoDoneWhen: .walkthroughDoneDoneWhen
        case .setDemoTimebox: .walkthroughDoneTimebox
        case .startDemoSession: .walkthroughDoneStartSession
        case .addDemoDesk: .walkthroughDoneDesk
        case .addDemoRule: .walkthroughDoneRules
        case .showDemoNudge: .walkthroughDoneNudge
        case .showDemoQuestion: .walkthroughDoneQuestion
        case .openMenuBar: .walkthroughDoneMenuBar
        case .openPrivacySettings: .walkthroughDoneSettings
        case .finishDemo: nil
        }
    }

    /// The controls this step points at, most specific first. The tour uses the first one that
    /// is on screen: the capture field when it is open, else the button that opens it; the
    /// context pack when Details is open, else the Details tab. Empty for the steps whose subject
    /// is not a cockpit control — the demo nudge, the menu bar, the finish.
    public var anchors: [WalkthroughAnchor] {
        switch self {
        case .setDemoPriority: [.captureField, .changePriorityButton]
        case .setDemoDoneWhen: [.doneWhenField]
        case .setDemoTimebox: [.timeboxControl]
        case .startDemoSession: [.sessionControls]
        case .addDemoDesk: [.contextPack, .detailsTab]
        case .addDemoRule: [.rules, .detailsTab]
        case .showDemoNudge, .showDemoQuestion, .openMenuBar, .finishDemo: []
        case .openPrivacySettings: [.openSettingsButton]
        }
    }

    /// Whether the tour performs this itself on arriving at the step, rather than waiting for
    /// the person: the two demo nudges, which exist to be looked at.
    public var performsOnArrival: Bool {
        switch self {
        case .showDemoNudge, .showDemoQuestion: true
        default: false
        }
    }

    /// The label of the button that performs the step for the person.
    public var fallbackTitleKey: ShellStringKey? {
        switch self {
        case .showDemoNudge, .showDemoQuestion: .walkthroughShowItAgain
        case .finishDemo: .walkthroughActionFinishDemo
        default: .walkthroughDoItForMe
        }
    }

    /// The steps the tour walks, in order.
    public static let steps: [WalkthroughAction] = allCases

    /// The step the tour opens on.
    public static let firstStep: WalkthroughAction = steps[0]

    public var nextStep: WalkthroughAction? {
        guard let index = Self.steps.firstIndex(of: self), index + 1 < Self.steps.count else { return nil }
        return Self.steps[index + 1]
    }

    public var previousStep: WalkthroughAction? {
        guard let index = Self.steps.firstIndex(of: self), index > 0 else { return nil }
        return Self.steps[index - 1]
    }

    /// Where this step sits, counted from one.
    public var ordinal: Int { (Self.steps.firstIndex(of: self) ?? 0) + 1 }
}

extension WalkthroughPage {
    /// The steps that belong to this page, in tour order. The first page has none: it is the
    /// privacy statement, read before anything is touched.
    public var actions: [WalkthroughAction] {
        WalkthroughAction.steps.filter { $0.page == self }
    }
}

/// **The demo priority's words**, resolved here so `FocusUI` is the package that names the keys
/// (focus-u6de). `FocusHost` stores them as a task's intent and definition of done, exactly as it
/// stores a sentence a person typed.
public enum WalkthroughDemo {
    public static var intent: String { ShellStrings.string(.walkthroughDemoIntent) }
    public static var doneWhen: String { ShellStrings.string(.walkthroughDemoDoneWhen) }
}
