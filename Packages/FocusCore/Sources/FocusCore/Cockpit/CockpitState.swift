import Foundation

/// The active priority, as a value.
///
/// Everything the cockpit needs to draw the one thing the user is doing, and nothing the
/// store needs to save it. `FocusUI` renders this; it never opens a `ModelContext` (R-24),
/// which is what lets every surface in the package be snapshot-tested with no container.
public struct PrioritySnapshot: Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    /// The user's own sentence. Drawn verbatim, at the hero role, and never routed through a
    /// String Catalog — it is data, not prose.
    public var intent: String
    /// The definition of done (F-08). Optional at capture and optional forever.
    public var doneWhen: String?
    public var createdAt: Date
    public var lastActivatedAt: Date?
    /// The timebox in seconds, or `nil` for none (F-12).
    public var timeboxSeconds: Int?
    public var startedAt: Date?
    /// Where the timebox has got to, computed from an injected wall clock by whoever built
    /// this value — never from a clock the view reads.
    public var timebox: TimeboxState
    public var contextItems: [ContextItemValue]
    public var rules: [PriorityRuleValue]
    /// What the deterministic validator makes of the stored sentence, so the cockpit can
    /// offer to refine a priority that was captured in a hurry (F-18).
    public var assessment: IntentAssessment

    public init(
        id: UUID,
        intent: String,
        doneWhen: String? = nil,
        createdAt: Date,
        lastActivatedAt: Date? = nil,
        timeboxSeconds: Int? = nil,
        startedAt: Date? = nil,
        timebox: TimeboxState = .none,
        contextItems: [ContextItemValue] = [],
        rules: [PriorityRuleValue] = [],
        assessment: IntentAssessment = .notAssessable
    ) {
        self.id = id
        self.intent = intent
        self.doneWhen = doneWhen
        self.createdAt = createdAt
        self.lastActivatedAt = lastActivatedAt
        self.timeboxSeconds = timeboxSeconds
        self.startedAt = startedAt
        self.timebox = timebox
        self.contextItems = contextItems
        self.rules = rules
        self.assessment = assessment
    }

    /// Project a stored task.
    ///
    /// The context items and rules are passed in rather than read off the relationship,
    /// because a file item's availability is a fact about the disk and resolving a bookmark
    /// per chip inside a projection would make drawing the cockpit a file-system operation.
    /// The caller resolves; this assembles.
    public init(
        _ task: FocusSchemaV3.PriorityTask,
        now: Date,
        contextItems: [ContextItemValue],
        rules: [PriorityRuleValue],
        assessment: IntentAssessment
    ) {
        self.init(
            id: task.id,
            intent: task.intent,
            doneWhen: task.doneWhen,
            createdAt: task.createdAt,
            lastActivatedAt: task.lastActivatedAt,
            timeboxSeconds: task.timeboxSeconds,
            startedAt: task.startedAt,
            timebox: TimeboxState.state(for: task, now: now),
            contextItems: contextItems,
            rules: rules,
            assessment: assessment
        )
    }

    /// The file attachments, in chip order — what Quick Look previews (F-95).
    public var fileItems: [ContextItemValue] {
        contextItems.filter { $0.kind == .file }
    }
}

/// One row of the history (F-15).
///
/// Deliberately thin: an intent, its definition of done and how much context came with it.
/// There is no learned profile and no search here, and there is no backlog — a previous
/// commitment becomes the current one by re-pointing at it, not by being queued.
public struct RecentPriority: Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public var intent: String
    public var doneWhen: String?
    /// How many context items travel with it. The pack returns by construction when the task
    /// is re-activated, so this number is a promise the store keeps rather than a summary.
    public var contextItemCount: Int
    public var lastActivatedAt: Date?
    public var completedAt: Date?
    /// Whether this row is the one the `ActivePriority` pointer currently names.
    public var isActive: Bool

    public init(
        id: UUID,
        intent: String,
        doneWhen: String? = nil,
        contextItemCount: Int = 0,
        lastActivatedAt: Date? = nil,
        completedAt: Date? = nil,
        isActive: Bool = false
    ) {
        self.id = id
        self.intent = intent
        self.doneWhen = doneWhen
        self.contextItemCount = contextItemCount
        self.lastActivatedAt = lastActivatedAt
        self.completedAt = completedAt
        self.isActive = isActive
    }

    /// Project a stored task. `isActive` is read from the pointer, which is the single source
    /// of truth — `PriorityTask` has no `isActive` column (R-18).
    public init(_ task: FocusSchemaV3.PriorityTask) {
        self.init(
            id: task.id,
            intent: task.intent,
            doneWhen: task.doneWhen,
            contextItemCount: task.contextItems.count,
            lastActivatedAt: task.lastActivatedAt,
            completedAt: task.completedAt,
            isActive: task.isActive
        )
    }
}

/// What the observer graph is doing right now, as a value the cockpit can draw.
///
/// ## Why this exists, and why every field is a fact rather than a mood
///
/// The shell e01 shipped drew one line — "sensing unavailable" — whatever was happening
/// underneath it, which meant the app said the same thing while watching as it said while
/// switched off. That is the failure this type exists to make impossible: a surface that
/// implies the app is watching when it is not is worse than a surface that says nothing, and a
/// surface that implies it is *not* watching when it is would be worse still.
///
/// So the summary carries the two things a person actually needs — **whether anything is
/// attached** (`liveObserverCount`, which is zero after `pause()` because the switch detaches
/// rather than sets a flag) and **whether they asked for it to stop** (`isPausedByUser`) — and
/// then the handful of signals the app is entitled to say it has. There is nothing here a nudge
/// could quote: `MediaActivity` has no member that asserts a meeting, and no field below names
/// an application, a window or a document.
///
/// It carries **no clock**. Every figure is a value somebody else read at a moment they chose,
/// which is what makes each of these snapshot-testable at a fixed instant.
public struct SensingSummary: Sendable, Equatable, Hashable {
    /// Whether the observer graph is attached right now.
    public var isObserving: Bool

    /// Whether the person has the global switch off (F-119). Distinct from `isObserving`,
    /// deliberately: "you turned it off" and "this Mac cannot do it" are different facts and
    /// the surface has to be able to say which one it means.
    public var isPausedByUser: Bool

    /// Every notification observer the graph holds. `n → 0 → n` across pause and resume.
    public var liveObserverCount: Int

    /// How many activations named the application that was already frontmost (probe P-82).
    /// Reported rather than hidden: it is the debounce doing its job.
    public var redundantActivations: Int

    /// What the Mac itself is doing, reduced from seven possibly-silent inputs.
    public var lifecycle: SystemLifecycle

    /// Whether the person is away from the keyboard, by the **hardware** idle source.
    public var isUserIdle: Bool

    /// Whether a microphone is running somewhere. The camera half is pinned `false` on every
    /// Mac in v1 and the surface says so rather than implying the app watches it.
    public var media: MediaActivity

    /// Whether `cameraActivity` is held off rather than absent — the distinction between "no
    /// camera on this Mac" and "camera activity is not used in this version".
    public var cameraReason: CameraUnavailableReason

    /// The presentation quorum's verdict, and its three inputs, so the surface can show its
    /// working even when the answer is no.
    public var presentation: PresentationState

    /// Whether the frontmost application's window is on a display that is not the primary one
    /// (F-34). Recorded in e03 and acted on by nobody.
    public var isOnSecondaryDisplay: Bool

    public init(
        isObserving: Bool = false,
        isPausedByUser: Bool = false,
        liveObserverCount: Int = 0,
        redundantActivations: Int = 0,
        lifecycle: SystemLifecycle = .active,
        isUserIdle: Bool = false,
        media: MediaActivity = .idle,
        cameraReason: CameraUnavailableReason = .noDevices,
        presentation: PresentationState = .notPresenting,
        isOnSecondaryDisplay: Bool = false
    ) {
        self.isObserving = isObserving
        self.isPausedByUser = isPausedByUser
        self.liveObserverCount = liveObserverCount
        self.redundantActivations = redundantActivations
        self.lifecycle = lifecycle
        self.isUserIdle = isUserIdle
        self.media = media
        self.cameraReason = cameraReason
        self.presentation = presentation
        self.isOnSecondaryDisplay = isOnSecondaryDisplay
    }

    /// Nothing is attached and nobody asked for it to be. The honest first value, and what a
    /// cockpit with no host renders.
    public static let inactive = SensingSummary()

    /// Whether the graph is genuinely watching: attached, with observers on it.
    ///
    /// Both halves, because either alone can lie. `isObserving` says the graph believes it
    /// attached; `liveObserverCount` says the platform actually gave it tokens. A surface that
    /// trusted only the first would claim to be watching on a Mac where every registration
    /// silently failed.
    public var isWatching: Bool { isObserving && liveObserverCount > 0 }
}

/// Everything the cockpit draws, as one value.
///
/// The view is handed this by the app's composition root; it never reaches for a sensing,
/// classification or persistence type of its own. That one-way rule is what keeps `FocusUI`
/// free of any dependency on `FocusSensing`, `FocusClassify`, `FocusRules` and SwiftData —
/// and therefore what makes the privacy posture checkable from the dependency graph rather
/// than by reading code.
///
/// It lives in `FocusCore` from e02 onward, because the app's `PriorityHost` builds it and
/// `PriorityActing` — the protocol the cockpit calls back through — is declared beside it.
public struct CockpitState: Sendable, Equatable, Hashable {
    /// What the app currently believes about the user's context.
    public var status: FocusStatus
    /// Whether the local data store opened.
    public var storeIsReady: Bool
    /// Whether any activity source is actually running.
    public var isObservingActivity: Bool
    /// The one thing, or `nil` when nothing has been committed to yet.
    public var priority: PrioritySnapshot?
    /// Previous commitments, newest first (F-15).
    public var recent: [RecentPriority]
    /// An incoming `focus://` handoff awaiting a human decision (F-142).
    ///
    /// Its presence opens the confirmation sheet and **nothing else**. There is no code path
    /// from a URL to a store mutation that does not pass through a person pressing Replace.
    public var pendingHandoff: HandoffRequest?
    /// Whether the daily ritual banner should be shown (F-19). A banner, never a modal.
    public var showsRitualPrompt: Bool

    /// The session the person is in, or `nil` when there is none.
    ///
    /// `nil` is a real answer rather than a missing one: sensing runs whether or not a session
    /// does, and the cockpit offers to start one instead of drawing an empty timer.
    public var session: SessionSnapshot?

    /// What the observer graph is doing. Drawn plainly, including when the answer is "nothing".
    public var sensing: SensingSummary

    /// What the relevance engine last concluded, or `nil` when it has concluded nothing.
    ///
    /// `nil` is the honest default and it renders as "nothing judged yet", never as a verdict:
    /// an app that drew `relevant` before it had looked at anything would be inventing a
    /// judgement, in exactly the way `CockpitState.ready` refuses to (its status is `paused`
    /// for the same reason).
    ///
    /// **This is the judgement the app acts on, not a copy of it.** e05's ladder is raised off
    /// the same eligibility the inspector draws here (focus-lmy).
    public var verdict: VerdictSnapshot?

    /// What the app currently believes about all twelve capabilities.
    ///
    /// Carried on the cockpit value rather than read from a probe by the view, for the same
    /// reason everything else here is: `FocusUI` renders values and never learns which
    /// implementation produced them. The Privacy pane draws the whole table from this; the
    /// cockpit draws only the rows that are *not* available, because a list of things that work
    /// is noise on the surface a person came to for one sentence.
    public var capabilities: CapabilityMatrix

    public init(
        status: FocusStatus,
        storeIsReady: Bool,
        isObservingActivity: Bool,
        priority: PrioritySnapshot? = nil,
        recent: [RecentPriority] = [],
        pendingHandoff: HandoffRequest? = nil,
        showsRitualPrompt: Bool = false,
        session: SessionSnapshot? = nil,
        sensing: SensingSummary = .inactive,
        verdict: VerdictSnapshot? = nil,
        capabilities: CapabilityMatrix = CapabilityMatrix()
    ) {
        self.status = status
        self.storeIsReady = storeIsReady
        self.isObservingActivity = isObservingActivity
        self.priority = priority
        self.recent = recent
        self.pendingHandoff = pendingHandoff
        self.showsRitualPrompt = showsRitualPrompt
        self.session = session
        self.sensing = sensing
        self.verdict = verdict
        self.capabilities = capabilities
    }

    /// The capabilities the surface has something to say about, in `Capability.allCases`
    /// order.
    ///
    /// Everything that is not `.available`. A capability that works needs no explanation, and
    /// listing it would bury the ones that do not.
    public var reducedCapabilities: [(capability: Capability, state: CapabilityState)] {
        capabilities.allStates.filter { !$0.state.isUsable }
    }

    /// Whether there is a current commitment at all.
    public var hasPriority: Bool { priority != nil }

    /// The store is open, nothing is being observed yet, and nothing has been committed to.
    ///
    /// `paused` is the honest answer, not a stand-in: the app has observed nothing and so has
    /// judged nothing. Showing `relevant` or `unrelated` here would be inventing a verdict.
    public static let ready = CockpitState(
        status: .paused,
        storeIsReady: true,
        isObservingActivity: false
    )

    /// The degraded state: the store could not be opened, so nothing will be saved.
    public static let storeUnavailable = CockpitState(
        status: .paused,
        storeIsReady: false,
        isObservingActivity: false
    )
}
