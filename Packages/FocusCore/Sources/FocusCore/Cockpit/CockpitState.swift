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

    public init(
        status: FocusStatus,
        storeIsReady: Bool,
        isObservingActivity: Bool,
        priority: PrioritySnapshot? = nil,
        recent: [RecentPriority] = [],
        pendingHandoff: HandoffRequest? = nil,
        showsRitualPrompt: Bool = false
    ) {
        self.status = status
        self.storeIsReady = storeIsReady
        self.isObservingActivity = isObservingActivity
        self.priority = priority
        self.recent = recent
        self.pendingHandoff = pendingHandoff
        self.showsRitualPrompt = showsRitualPrompt
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
