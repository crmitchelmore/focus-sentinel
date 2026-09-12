import FocusCore
import FocusSensing
import Foundation
import Observation
import SwiftData
import os

/// The one bridge between the session runtime and the surfaces that drive it.
///
/// The same shape as `PriorityHost`, and for the same reasons (R-24): this owns the
/// `ModelContext`, calls `SessionStore` — and therefore registers every *user-initiated*
/// mutation on the undo journal — and projects the result into a plain `SessionSnapshot` that
/// `FocusUI` renders. The UI never sees a `@Model` class, never opens a store, and never learns
/// which implementation it was handed.
///
/// ## Why every verb is non-throwing
///
/// A store failure is a fact the person has to be **told** about, not an exception a view can
/// meaningfully catch: a `try?` inside a button's action is a swallowed failure with a green
/// checkmark on top. So every call here catches, records the failure, and the next projection
/// reports it.
///
/// ## Why a rejected transition is silent
///
/// `SessionMachine` returns rejections as values rather than throwing them, and a rejection
/// means what the person asked for was already true — pressing Resume on a session that is not
/// paused, or Break on one that is already on one. The host records the rejection for the
/// self-check to report and the UI does nothing, because there is nothing to tell them.
///
/// The one rejection that *is* worth surfacing is `notPausedForThatCause`, and it is surfaced
/// before it happens rather than after: `SessionSnapshot.userMayResume` is false while a cause
/// the person cannot clear is still held, so the Resume control is disabled with a named
/// explanation instead of doing nothing when pressed.
@Observable
@MainActor
final class SessionHost: SessionActing {
    /// The session as the cockpit draws it. `nil` when there is none.
    private(set) var snapshot: SessionSnapshot?

    /// The last rejection the machine returned, for the self-check and the Privacy surface.
    /// Not drawn: a rejected transition means the person's intent was already satisfied.
    private(set) var lastRejection: SessionRejection?

    /// Whether the store refused a write since the last successful one.
    private(set) var writeFailure: String?

    private let context: ModelContext
    private let store: SessionStore
    private let priorities: PriorityStore
    private let events: ActivityEventStore
    private let launcher: SessionLauncher
    private let dateProvider: any DateProvider
    private let logger = Logger(subsystem: FocusStore.bundleIdentifier, category: "SessionHost")

    /// The observer graph, so that the one pause switch drives one stored value and one
    /// detachment. Held weakly: the composition root owns both, and a cycle between two objects
    /// that live for the whole process is a leak nobody would ever notice.
    weak var sensing: SensingHost?

    /// Called after the projection has been rebuilt, so the composition root can push the new
    /// session into the value the cockpit draws.
    ///
    /// A hook rather than the host reaching for `AppComposition`: this object knows about the
    /// store and the launcher and nothing else, and the wiring belongs where every other
    /// concrete choice in this app is made.
    var onChange: (() -> Void)?

    /// The window's undo manager, once a window exists to have one.
    private var undo: UndoManager?

    /// The manager this journal is registering on, for the shell-wire lane to read.
    ///
    /// `PriorityHost` publishes the same fact for the same reason: the cockpit scene adopts into
    /// **both** journals with one call, and a scene that reached one and not the other is a scene
    /// with a half-working ⌘Z — which is a thing to assert rather than to assume (focus-cp2).
    var journalUndoManager: UndoManager? { undo }

    init(
        context: ModelContext,
        events: ActivityEventStore,
        dateProvider: any DateProvider,
        uptimeClock: any UptimeClock,
        bootIdentity: String,
        launcher: SessionLauncher = SessionLauncher()
    ) {
        self.context = context
        self.events = events
        self.dateProvider = dateProvider
        self.launcher = launcher
        self.store = SessionStore(
            context: context,
            dateProvider: dateProvider,
            uptimeClock: uptimeClock,
            bootIdentity: bootIdentity
        )
        self.priorities = PriorityStore(context: context, dateProvider: dateProvider)
        refresh()
    }

    // MARK: - Wiring

    /// Adopt the window's undo manager, so ⌘Z drives the journal for the operations a person
    /// actually performed. System-driven pauses never reach it.
    func adoptUndoManager(_ manager: UndoManager?) {
        undo = manager
    }

    /// The store, for the self-check's two-launch reconciliation proof.
    var sessionStore: SessionStore { store }

    // MARK: - Restoration (F-97)

    /// Reconcile whatever was running when the app last stopped, **before the first frame**.
    ///
    /// `startedAt` is never rewritten — not here, not anywhere — and no timer is started,
    /// because there is none to start. What may change is the phase, and only in the two cases
    /// the reconciler names: a different boot identity, and more than fifteen minutes since the
    /// last phase change.
    @discardableResult
    /// How many sessions this store has ever finished — the signal the launch-at-login offer
    /// waits for (D-12, focus-odz.4). Straight through to the store, because the host holds the
    /// open session and this is a question about the history behind it.
    func finishedSessionCount() throws -> Int {
        try store.finishedSessionCount()
    }

    func restore() -> RestoredSession? {
        var restored: RestoredSession?
        do {
            restored = try store.restore()
            writeFailure = nil
        } catch {
            record(error)
        }
        refresh()
        return restored
    }

    // MARK: - The verbs

    /// Begin a session on the active priority, and — if the person switched it on — open its
    /// context pack.
    func startSession(kind: SessionKind = .openEnded, plannedSeconds: Int? = nil, deadlineAt: Date? = nil) {
        perform {
            let task = try priorities.activeTask()
            try store.start(
                taskID: task?.id,
                kind: kind,
                plannedSeconds: plannedSeconds,
                deadlineAt: deadlineAt,
                undo: undo
            )
            launchContext(for: task)
        }
    }

    func pauseSession() {
        apply(.paused(cause: .user))
    }

    /// The person's resume.
    ///
    /// One `resumed(cause:)` per cause the person is entitled to lift — their own pause, and
    /// the `.relaunch` or `.systemRestart` a restoration raised (focus-mmty). The machine takes
    /// one cause per event and moves the phase only when the set is empty, so a session that
    /// was paused by the person *and* then survived a reboot takes two events here and lands
    /// once, on its `resumeTo`. With no snapshot to read, the plain `.user` resume is sent so
    /// the machine can answer with its own rejection.
    func resumeSession() {
        let causes = snapshot?.causesTheUserMayClear ?? []
        for cause in causes.isEmpty ? [.user] : causes {
            apply(.resumed(cause: cause))
        }
    }

    func startDetour(reason: DetourReason = .user) {
        apply(.detourStarted(reason: reason))
    }

    func endDetour() {
        apply(.detourEnded)
    }

    /// Take a break.
    ///
    /// A break may be started **only from focus** (R-45). The UI does the two steps in one
    /// click and the machine records two transitions, which is what makes the timeline honest
    /// about what happened: you ended a detour, then you took a break.
    func startBreak(reason: BreakReason = .user) {
        if snapshot?.phase == .intentionalDetour {
            apply(.detourEnded)
        }
        apply(.breakStarted(reason: reason))
    }

    func endBreak() {
        apply(.breakEnded)
    }

    /// Stop the session and capture why (F-101).
    ///
    /// Every field is optional and Complete is enabled with all of them empty: reflection is
    /// offered, never extracted. The last-active context is the frontmost application's bundle
    /// identifier and **nothing else** — never a window title, never a document.
    func interruptSession(reason: InterruptionReason = .user, note: String? = nil) {
        perform {
            // The frontmost application's bundle identifier, read straight off `NSWorkspace` —
            // no window read, no Accessibility call, no grant (probe P-79). A bundle identifier
            // and nothing else: the sheet resolves it to a name and an icon for the eye, and
            // the store keeps only the identifier.
            let transition = try store.interrupt(
                reason: reason,
                note: note,
                lastActiveBundleID: WorkspaceActivityObserver.frontmostPayload()?.bundleIdentifier,
                undo: undo
            )
            lastRejection = transition.rejection
        }
    }

    func completeSession() {
        perform {
            lastRejection = try store.complete(undo: undo).rejection
        }
    }

    /// F-119's one switch, bound identically to the menu bar, the cockpit and (in e09) the
    /// notch — because it is one stored value and one detachment, not a boolean each surface
    /// keeps its own copy of.
    func setSensingPaused(_ paused: Bool) {
        perform {
            try FocusStore.setSensingPaused(paused, in: context, now: dateProvider.now)
            guard let sensing else { return }
            sensing.update(settings: FocusStore.sensingSettings(in: context))
            if paused { sensing.pause() } else { sensing.resume() }
        }
    }

    // MARK: - Applying, once

    private func apply(_ event: SessionEvent) {
        perform {
            let rejection = try store.apply(event, undo: undo).rejection
            lastRejection = rejection
            // **When this session last came back from a break** (F-67, focus-2w1).
            //
            // Recorded here rather than read off the snapshot, because the snapshot cannot say
            // it: it carries the phase and not the event that produced it, and a session enters
            // `focus` from a break, from a detour and from being started. Only the machine
            // accepting `breakEnded` is the fact the cue is about, so the moment is taken where
            // the machine answers — and never when it refused, which is why the rejection is
            // read first.
            if event.kind == .breakEnded, rejection == nil {
                breakEndedAt = dateProvider.now
            }
        }
    }

    /// When this session last came back from a break, or `nil` if it never has.
    ///
    /// Cleared with the session rather than kept: a break that ended inside a session which has
    /// since finished is history, and `RestartCue` says so by its own rule as well. Both, because
    /// one of them is a fact about the host's memory and the other is a fact about the phase, and
    /// a cue that survived into the *next* session would be the app asking somebody to go back to
    /// something they finished.
    private(set) var breakEndedAt: Date?

    /// Every verb funnels through here: run it, remember what went wrong if anything did, and
    /// rebuild the value the cockpit draws.
    private func perform(_ body: () throws -> Void) {
        do {
            try body()
            writeFailure = nil
        } catch SessionStoreError.noOpenSession {
            // Not a failure: the person pressed a session control while no session was open,
            // which the surfaces already prevent and which is nothing to tell them about.
            lastRejection = nil
        } catch {
            record(error)
        }
        refresh()
    }

    private func record(_ error: any Error) {
        writeFailure = error.localizedDescription
        logger.error("the session store refused a write: \(error.localizedDescription, privacy: .public)")
    }

    /// Rebuild the projection from the store.
    func refresh() {
        let previous = snapshot?.sessionID
        do {
            snapshot = try store.openSnapshot()
        } catch {
            record(error)
        }
        // A different session — or none — has nothing to do with the break the last one took.
        if snapshot?.sessionID != previous { breakEndedAt = nil }
        expireSessionRules(previouslyOpen: previous)
        onChange?()
    }

    // MARK: - Session-lived rules (R-72.2)

    /// The only owner of `RuleAuthority.session`.
    ///
    /// In memory, never persisted, and cleared here. **The one writer is `NudgeHost`**, which
    /// inserts a rule when somebody presses the panel's *"not now"* correction; e04 supplied the
    /// shape and the lifetime that makes it safe. A session rule that survived a relaunch would
    /// be a session rule that outlived its session, and giving the value no persistence to reach
    /// is what makes that unrepresentable rather than unlikely.
    let sessionRuleBox = SessionRuleBox()

    /// Every session rule that applies to the open session and the given priority.
    ///
    /// Empty when no session is open, which is the honest answer: a rule scoped to "this focus
    /// session" has nothing to be scoped to when there is not one.
    ///
    /// The priority is *declared* here before it is used, which is the second half of R-72.2's
    /// lifetime contract: this is the only path on which the box is read, the snapshot is rebuilt
    /// on exactly the four events that change the priority, so noting it here is what turns "the
    /// rule dies when the priority changes" into a clear rather than a hide. A rule the person
    /// wrote under an earlier priority must not come back when they switch back to it — the
    /// *"not now"* it recorded answered a question they have since left.
    func sessionRules(forPriority priorityID: UUID?) -> [ScopedRuleValue] {
        guard let sessionID = snapshot?.sessionID else { return [] }
        sessionRuleBox.setActivePriority(priorityID, forSession: sessionID)
        return sessionRuleBox.rules(forSession: sessionID, priorityID: priorityID)
    }

    /// Drop the session's rules the moment the session they belonged to stops being the open
    /// one — whether it ended, was interrupted, or was replaced by a new one.
    ///
    /// Called from `refresh()`, which is the transition handler every verb on this host already
    /// funnels through, so there is no phase change that can happen without passing here. The
    /// other two halves of the lifetime contract are owned elsewhere: a **priority** change is
    /// cleared on the read path above, where the change is observable, and a process exit takes
    /// an in-memory store with it by definition.
    private func expireSessionRules(previouslyOpen: UUID?) {
        guard let previouslyOpen, previouslyOpen != snapshot?.sessionID else { return }
        sessionRuleBox.clear(sessionID: previouslyOpen)
    }

    // MARK: - The launcher (F-169)

    /// Open the priority's context pack, if the person switched it on.
    ///
    /// **Off by default**, open-only, and one event per attempt so they can see what it did. It
    /// never hides and never quits another application: the seam it talks through has no such
    /// member.
    private func launchContext(for task: FocusSchemaV3.PriorityTask?) {
        guard let task else { return }
        let settings = FocusStore.sensingSettings(in: context)
        guard settings.launchContextOnSessionStart else { return }

        let items = task.contextItems
            .sorted { $0.addedAt < $1.addedAt }
            .map { ContextItemValue($0) }

        for attempt in launcher.launch(items, isEnabled: true) {
            record(attempt)
        }
    }

    /// One event per launch attempt, so the person can see exactly what the app opened — and
    /// what it declined to.
    ///
    /// The row carries a bundle identifier where the item had one and a closed-vocabulary token
    /// for the outcome. A `.file` item's *path* is deliberately not on it: only normalised
    /// evidence reaches the store, and there is no way to put a path in a `NormalisedDetail`.
    private func record(_ attempt: LaunchAttempt) {
        do {
            try events.append(
                kind: .contextChanged,
                bundleID: attempt.kind == .app ? bundleID(of: attempt) : nil,
                detail: .tokens([attempt.outcome == .opened ? .launchAttempted : .launchSkipped]),
                sessionID: snapshot?.sessionID
            )
        } catch {
            logger.error("the event store refused a launch row: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func bundleID(of attempt: LaunchAttempt) -> String? {
        guard let task = try? priorities.activeTask() else { return nil }
        return task.contextItems.first { $0.id == attempt.itemID }?.value
    }
}
