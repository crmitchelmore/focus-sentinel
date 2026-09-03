import Foundation

/// A context item the user has just produced, before it has been stored.
///
/// The draft carries no identifier and no timestamp on purpose. Identity and `addedAt` are
/// stamped by whoever owns the store and the injected clock — which is what keeps every
/// timestamp in the programme reproducible and keeps a bare `Date()` out of `FocusUI`
/// entirely (R-26).
public struct ContextItemDraft: Sendable, Equatable, Hashable {
    public var kind: ContextItemKind
    /// The normalised subject: a bundle identifier, a `scheme://host[:port]` origin, a
    /// lowercased keyword, or the file's path at the moment it was added.
    public var value: String
    /// What the chip shows.
    public var displayName: String
    /// A security-scoped bookmark, for file drafts only.
    public var bookmark: Data?

    public init(kind: ContextItemKind, value: String, displayName: String, bookmark: Data? = nil) {
        self.kind = kind
        self.value = value
        self.displayName = displayName
        self.bookmark = bookmark
    }

    // MARK: - The four kinds, built correctly

    /// An application. The bundle identifier is the subject; the name is for the eye.
    public static func app(bundleID: String, displayName: String) -> ContextItemDraft? {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return ContextItemDraft(
            kind: .app,
            value: trimmed,
            displayName: name.isEmpty ? trimmed : name
        )
    }

    /// A web origin. **Returns `nil` when the URL has no origin**, which is what keeps a
    /// path, a query or a credential from ever reaching the store: there is no route from a
    /// full URL to a stored value that does not pass through the normaliser (SC-3).
    public static func domain(from url: URL) -> ContextItemDraft? {
        guard let origin = OriginNormalizer.normalize(url) else { return nil }
        return domain(origin: origin)
    }

    public static func domain(origin: String) -> ContextItemDraft? {
        guard let normalised = OriginNormalizer.normalize(origin) else { return nil }
        return ContextItemDraft(
            kind: .domain,
            value: normalised,
            displayName: ContextItemValue.displayName(forOrigin: normalised)
        )
    }

    /// A keyword. Trimmed and lowercased: "Proposal" and "proposal" are the same keyword and
    /// two chips saying so is clutter.
    public static func keyword(_ text: String) -> ContextItemDraft? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        return ContextItemDraft(kind: .keyword, value: trimmed, displayName: trimmed)
    }

    /// A file, held as a security-scoped bookmark (R-22).
    ///
    /// The bookmark is made here, at the moment the user chose the file, because that is the
    /// only moment the app is certain it can reach it. A bookmark that cannot be made leaves
    /// `bookmark == nil`, and the chip then renders as *missing* with a Locate… action rather
    /// than pretending the path alone is a durable handle — a path is not a file.
    public static func file(url: URL) -> ContextItemDraft {
        ContextItemDraft(
            kind: .file,
            value: url.path(percentEncoded: false),
            displayName: url.lastPathComponent,
            bookmark: try? SecurityScopedBookmark.create(for: url)
        )
    }
}

/// Everything the cockpit can *do*, as a protocol.
///
/// The cockpit renders a `CockpitState` and calls one of these verbs; it never opens a store,
/// never sees a `@Model` class and never learns which implementation it was handed.
/// `App/PriorityHost.swift` is the only type that implements it — it owns the `ModelContext`,
/// calls `PriorityStore` (and therefore registers every mutation on the undo journal), and
/// projects the result back into a new `CockpitState`. `FocusUITests` supply a recording
/// double, which is what makes every surface in the package testable with no container.
///
/// **Nothing here throws.** A store failure is a fact the user has to be told about, not an
/// exception a view can meaningfully catch: the host records it and the next `CockpitState`
/// reports it. A view that could `try?` a mutation would be a view that could swallow one.
@MainActor
public protocol PriorityActing: AnyObject {
    /// Capture a sentence and make it the one thing. The primary user action.
    func setPriority(intent: String, doneWhen: String?)

    /// Edit the intent in place. Bumps the task's revision.
    func editIntent(taskID: UUID, to intent: String)

    /// Set or clear the definition of done (F-08).
    func editDoneWhen(taskID: UUID, to doneWhen: String?)

    /// Set or clear the timebox, in seconds (F-12).
    func setTimebox(taskID: UUID, seconds: Int?)

    /// "Work on this again" (F-15): re-point the pointer at an existing task, restoring its
    /// stored context pack by construction rather than by copying.
    func activate(taskID: UUID)

    /// Finish it (F-22). Both reflection fields are optional and completion never waits for
    /// them.
    func complete(taskID: UUID, shipped: String?, restartPoint: String?)

    /// Put the priority down without completing or deleting anything.
    func clear()

    /// Add one item to the context pack (F-09).
    func addContext(taskID: UUID, item: ContextItemDraft)

    /// Remove one item. Never called automatically — a missing file stays on the board.
    func removeContext(id: UUID)

    /// Author a rule scoped to this priority (F-11).
    func addRule(
        taskID: UUID,
        scope: PriorityRuleScope,
        subject: String,
        verdict: PriorityRuleVerdict
    )

    /// Change your mind about a rule, keeping its identity and its place in the list.
    func changeRule(id: UUID, verdict: PriorityRuleVerdict)

    func removeRule(id: UUID)

    /// Accept an incoming `focus://` handoff — **only** ever called from the confirmation
    /// sheet's Replace button (F-142).
    func acceptHandoff(_ request: HandoffRequest)

    /// Dismiss the pending handoff without changing anything.
    func cancelHandoff()

    /// Record that today's ritual has been answered or dismissed, so it asks once (F-19).
    func dismissRitual()

    /// **The person has been told the store did not open** (focus-tzj.4).
    ///
    /// Called from the one button on the sheet the cockpit shows when `storeOpened` is `false`,
    /// and from nowhere else. It changes nothing about the store — there is nothing to change —
    /// and it lifts `CockpitState.capturingIsRefused`, which is what stops a day's work being
    /// captured into a container that evaporates at quit without anybody having said so.
    ///
    /// A verb on the host rather than a `@State` in the view, because the refusal is the host's:
    /// a rule enforced only by the surface that draws it is a rule the next surface will not
    /// have.
    func acknowledgeStoreFailure()
}

/// Everything the session surfaces can *do*, as a sibling protocol.
///
/// Deliberately a **second** protocol rather than ten more verbs on `PriorityActing`. A
/// priority and a session are different objects with different lifetimes — a task can span many
/// sessions and a session can outlive the priority it was started on — and the two hosts that
/// implement these are two objects for the same reason. A cockpit handed one and not the other
/// renders the half it can drive and disables the half it cannot, which is what the snapshot
/// lane does.
///
/// Same three rules as `PriorityActing`, and they matter more here rather than less:
///
/// * **Nothing throws.** A store failure is a fact the person has to be told, not an exception
///   a button's action can meaningfully catch.
/// * **Nothing returns.** The result of every verb is the next `CockpitState`, so a surface
///   cannot come to depend on a value the store might not have written.
/// * **A rejected transition is silent.** `SessionMachine` returns rejections as values, and a
///   rejection means what the person asked for was already true. The one rejection worth
///   surfacing — `notPausedForThatCause` — is surfaced *before* it happens rather than after:
///   `SessionSnapshot.userMayResume` is false while a cause the person cannot clear is still
///   held, so Resume is disabled with a named explanation instead of doing nothing when
///   pressed.
///
/// `setSensingPaused` lives here rather than on a third protocol because F-119's switch is one
/// stored value driving one detachment, and pausing sensing also drives a session pause with
/// cause `.globalPause`. Two surfaces for it would be two opinions about one row.
@MainActor
public protocol SessionActing: AnyObject {
    /// Begin a session on the active priority. Starting is not an event on an existing state —
    /// it creates one, in `.focus`.
    func startSession(kind: SessionKind, plannedSeconds: Int?, deadlineAt: Date?)

    /// The person's own pause. Sends `paused(cause: .user)`, and only a `.user` resume lifts it.
    func pauseSession()

    /// The person's own resume. Sends `resumed(cause: .user)` — which the machine rejects
    /// `notPausedForThatCause` if the pause belongs to the screen lock or the global switch.
    func resumeSession()

    func startDetour(reason: DetourReason)

    func endDetour()

    /// Take a break. A break may be started **only from focus**, so a surface that offers it
    /// during a detour ends the detour first and the machine records two transitions — which is
    /// what keeps the timeline honest about what actually happened.
    func startBreak(reason: BreakReason)

    func endBreak()

    /// Stop the session and capture why (F-101). Every field is optional and Complete is
    /// enabled with all of them empty: reflection is offered, never extracted.
    func interruptSession(reason: InterruptionReason, note: String?)

    func completeSession()

    /// F-119's one global switch, bound identically to every surface that shows it.
    func setSensingPaused(_ paused: Bool)
}
