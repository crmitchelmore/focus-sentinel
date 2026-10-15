import FocusCore
import Foundation
import Observation
import SwiftData
import os

/// The one implementation of `PriorityActing`, and the only bridge between SwiftData and the
/// cockpit.
///
/// e01 kept `FocusUI` free of SwiftData and e02 does not relax it (R-24). The rule has one
/// enforcement point and this is it: the host owns the `ModelContext`, calls `PriorityStore`
/// — and therefore registers every mutation on the undo journal — and projects the result
/// back into a plain `CockpitState` value. `FocusUI` renders that value and calls back through
/// the protocol; it never sees a `@Model` class, never opens a store, and is therefore
/// snapshot-testable with no container at all.
///
/// ## Why every verb is non-throwing
///
/// `PriorityActing` declares no `throws`, deliberately. A store failure is a fact the user has
/// to be **told** about, not an exception a view can meaningfully catch: a `try?` inside a
/// button's action is a swallowed failure with a green checkmark on top. So every call here
/// catches, records the failure, and the next `CockpitState` reports `storeIsReady == false`
/// — the same honest degraded state the shell already draws when the store would not open.
///
/// ## What is *not* undoable, on purpose
///
/// Two writes here go straight to the context rather than through `PriorityStore`: stamping
/// the ritual's local-day key, and re-creating a stale file bookmark. Neither is something a
/// person did, so neither belongs in the Edit menu — an "Undo" that put back a bookmark
/// pointing at a file's old path would be undoing housekeeping the user never asked for.
@Observable
@MainActor
final class PriorityHost: PriorityActing {
    /// Everything the cockpit draws. Rebuilt from the store after every mutation.
    private(set) var state: CockpitState

    /// Facts about the rest of the app that the store knows nothing about.
    struct Environment: Sendable, Equatable {
        var status: FocusStatus
        /// Whether the on-disk store opened. **Not** whether writing is working — see
        /// `CockpitState.storeOpened` (focus-tzj.4).
        var storeOpened: Bool
        var isObservingActivity: Bool
        /// The session the person is in, projected by `SessionHost`. `nil` when there is none.
        var session: SessionSnapshot?
        //
        // **`sessionElapsedSeconds` and `lastActiveBundleID` used to be here, and were read by
        // nobody** (focus-zrs). `refresh()` builds `CockpitState` without them, and the window
        // gets both from `AppComposition` directly — `sessionElapsedSeconds` from the wall clock
        // at the moment the connection is built, `lastActiveBundleID` from
        // `sensingHost.lastForeignBundleIdentifier`. Two copies of two facts, written on every
        // corroboration tick from three call sites, that nothing anywhere consulted: a second
        // representation with no reader is still a second representation, and the next person to
        // need one of these would have found two.
        //
        /// What the observer graph is doing, including when the answer is "nothing".
        var sensing: SensingSummary = .inactive
        /// What this Mac lets the app do, as the probe last read it.
        var capabilities: CapabilityMatrix = CapabilityMatrix()
        /// What the relevance engine last concluded, or `nil` when it has concluded nothing.
        ///
        /// Carried through the environment rather than read by a view, for the same reason
        /// everything else here is: `FocusUI` renders values and never learns which
        /// implementation produced them.
        var verdict: VerdictSnapshot?
        /// **Whether the footer is making the one-time launch-at-login offer** (D-12,
        /// focus-odz.4), and **whether the first-run explanation is on screen** (focus-odz.7).
        ///
        /// Carried through the environment rather than composed on to `CockpitState` afterwards,
        /// and the reason is a measured one. `AppComposition` is a plain `final class`: writing a
        /// property on it invalidates no SwiftUI body, so a state the root patched on to the
        /// projection after `refresh()` had built it reached the window on whatever redraw
        /// happened next — and when the decision was *"take the sheet down"*, the next redraw is
        /// the one the dismissal was supposed to cause. Measured: the self-check's cockpit lane
        /// hung for twenty-eight minutes at `NSApp.terminate` with the first-run sheet still
        /// attached, because nothing had told the window to stop drawing it.
        ///
        /// Through the environment, both are inside the value `refresh()` compares and assigns,
        /// so a change to either is a change to `state` and the window redraws for it.
        var showsLaunchAtLoginOffer: Bool = false
        var showsFirstRunExplanation: Bool = false
        /// **The person's calendar, as busy blocks** (focus-cal). `.unread` unless the person
        /// switched the calendar on in Privacy and macOS said yes — and an unread calendar
        /// refuses no timebox and draws nothing beside the control.
        var calendarAgenda: CalendarAgenda = .unread
    }

    /// Everything a rule snapshot is built from, as one comparable value (R-65).
    ///
    /// The engine's snapshot must be rebuilt when — and **only** when — the active priority
    /// changes, its `revision` changes, a rule is written, or a context item is added or
    /// removed. Those four facts are exactly the four fields below, so comparing this value is
    /// what keeps the store read on the four things a person did rather than on the
    /// five-second corroboration tick — which is the whole point of pre-fetching in the first
    /// place, and the thing `SwiftDataRuleStore`'s own doc comment worries about.
    ///
    /// `revision` is here and not on `PrioritySnapshot` because the cockpit has no use for it:
    /// it is the staleness component of e06's verdict-cache key (F-53) and the thing that makes
    /// an edited sentence invalidate every judgement about the old wording.
    struct SnapshotKey: Sendable, Equatable {
        var priorityID: UUID?
        var revision: Int = 0
        var contextItems: [ContextItemValue] = []
        var rules: [PriorityRuleValue] = []
    }

    /// The four facts as they last stood.
    private(set) var snapshotKey = SnapshotKey()

    /// **`PriorityStore.mutationCount` as of the last history fetch**, or `nil` before there has
    /// been one (focus-tzj.2). See `refresh()`.
    private var historyRevision: Int?

    /// **The one thing the person has committed to — this object's single statement of it**
    /// (focus-zrs).
    ///
    /// This host held the active priority in two places that anything outside could read, and the
    /// nudge lane read one of them while keying its writes to a third:
    ///
    /// | reading | what used it |
    /// |---|---|
    /// | `state.priority?.id` | `AppComposition.nudgeSurroundings()`, i.e. **gate 1** |
    /// | `snapshotKey.priorityID` | `AppComposition.noticeLifecycleTransitions()` |
    /// | `PriorityStore.activeTask()`, opened again inside `NudgeHost` | **every receipt, rule
    ///   and budget key the interruption wrote** |
    ///
    /// All three are now one: `refresh()` fetches once and builds the projection, the snapshot key
    /// **and** this from the same `activeTask`, and the two consumers above read this. The third
    /// is gone — `NudgeHost` has no `PriorityStore` read of the active task at all; the commitment
    /// travels to it as a value on `NudgeSurroundings`.
    ///
    /// `commitmentDisagreements` below is the reading that says so, rather than this comment.
    private(set) var activeCommitment: ActiveCommitment?

    /// Called when — and only when — `snapshotKey` actually moved.
    ///
    /// The composition root wires it to `RelevanceHost.invalidateSnapshot()`. It is deliberately
    /// not called from `update(environment:)`: the environment carries the status, the session
    /// and the capability matrix, none of which a judgement is built from, and firing on those
    /// would put a SwiftData fetch on every tick.
    var onSnapshotInvalidated: (() -> Void)?

    /// **The projection changed**, in any of its fields — fired after `state` is reassigned, so an
    /// observer reads the new value (focus-u6de). Broader than `onSnapshotInvalidated`, which is
    /// the engine's and fires only for the four facts the snapshot key carries: a definition of
    /// done or a timebox changes the state and not the key, and the walkthrough's tour reads
    /// those. The cockpit itself does not need this; it observes `state` directly.
    var onStateChanged: (() -> Void)?

    private let context: ModelContext
    private let store: PriorityStore
    private let dateProvider: any DateProvider
    private let calendar: Calendar
    private let locale: Locale
    private let logger = Logger(
        subsystem: FocusStore.bundleIdentifier,
        category: "PriorityHost"
    )

    /// The window's undo manager, once a window exists to have one.
    ///
    /// Deliberately **not** a settable property named `undoManager`: `check-forbidden.sh` bans
    /// every `.undoManager =` assignment in the repository so that SwiftData's own
    /// `ModelContext.undoManager` — which probe P-48 measured mis-restoring an activation swap
    /// and crashing on a constraint-merged insert — cannot be reintroduced by accident. The
    /// journal this hands the manager to is `PriorityStore`'s (R-19).
    private var undo: UndoManager?

    private var environment: Environment
    /// The handoff waiting for a human decision. Its presence opens the confirmation sheet and
    /// does nothing else whatsoever (F-142).
    private var pendingHandoff: HandoffRequest?
    /// Whether the store refused a write since the last successful one.
    private var writeFailure: String?
    /// **Whether the person has been told the store did not open** (focus-tzj.4). Latched: a
    /// store that did not open does not open later in the same launch, and asking twice about
    /// one fact would be the app arguing with somebody who has already answered.
    private var storeFailureAcknowledged = false

    /// Where the store the app tried to open lives, for the sheet that says it did not.
    ///
    /// Handed in by the composition root rather than assumed (focus-k2in): a launch given a
    /// fixture store that failed to open must name the fixture, not the person's own file.
    let storeLocation: String

    init(
        context: ModelContext,
        dateProvider: any DateProvider,
        calendar: Calendar,
        locale: Locale,
        environment: Environment,
        storeLocation: String = FocusStore.applicationSupportURL.path(percentEncoded: false)
    ) {
        self.context = context
        self.store = PriorityStore(context: context, dateProvider: dateProvider)
        self.dateProvider = dateProvider
        self.calendar = calendar
        self.locale = locale
        self.environment = environment
        self.storeLocation = storeLocation
        self.state = CockpitState(
            status: environment.status,
            storeOpened: environment.storeOpened,
            storeLocation: storeLocation,
            isObservingActivity: environment.isObservingActivity,
            session: environment.session,
            sensing: environment.sensing,
            capabilities: environment.capabilities
        )
        refresh()
    }

    // MARK: - Wiring

    /// Adopt the window's undo manager, so ⌘Z in the Edit menu drives the journal.
    ///
    /// SwiftUI hands this out through `@Environment(\.undoManager)`, which is `nil` until a
    /// window exists. Probe P-50 measured that registering on it makes the *system* Edit menu
    /// read `Undo Change Priority`, enabled — with no menu code of our own.
    func adoptUndoManager(_ manager: UndoManager?) {
        undo = manager
    }

    /// The undo manager the journal is registering on, for the self-check to read.
    var journalUndoManager: UndoManager? { undo }

    /// Update the facts the store knows nothing about (the status badge, whether anything is
    /// being observed, whether the store opened at all).
    func update(environment: Environment) {
        self.environment = environment
        refresh()
    }

    // MARK: - Handoff (F-142)

    /// Take delivery of a `focus://` URL.
    ///
    /// The parse is a pure function with hard bounds (R-23) and its only non-rejection outcome
    /// is `.confirm`. All this does with a confirmable request is **show it**: there is no
    /// route from here to a mutation that does not pass through a person pressing Replace.
    func receive(_ url: URL) {
        switch HandoffRequest.parse(url) {
        case .confirm(let request):
            pendingHandoff = request
            refresh()
        case .rejected(let rejection):
            // Logged rather than drawn: a rejected URL never reached a surface, so there is
            // nothing on screen for a message to belong to, and inventing a modal for a
            // malformed script argument would be a worse interruption than the script was.
            logger.notice("rejected a focus:// URL: \(String(describing: rejection), privacy: .public)")
        }
    }

    // MARK: - PriorityActing

    func setPriority(intent: String, doneWhen: String?) {
        // **Refused until the person has been told** (focus-tzj.4). With no store, a captured
        // priority goes into an in-memory container that is thrown away when the process ends —
        // so the app stops taking commitments it cannot keep until it has said so and been
        // answered. `CockpitState.capturingIsRefused` is the one derivation; the sheet the
        // cockpit draws is the other consumer of it.
        guard !state.capturingIsRefused else { return }
        perform { store in
            _ = try store.setPriority(intent: intent, doneWhen: doneWhen, undo: self.undo)
        }
    }

    func setPriority(intent: String, doneWhen: String?, keepingContextOf taskID: UUID) {
        guard !state.capturingIsRefused else { return }
        // The desk to copy is read from the state the cockpit drew, not re-fetched: what the
        // person saw is what they asked to keep. A `taskID` that is not the current priority
        // has nothing on screen to keep, so it falls back to a plain set rather than copying
        // somebody else's desk.
        let desk = state.priority.flatMap { $0.id == taskID ? $0 : nil }
        perform { store in
            let newID = try store.setPriority(intent: intent, doneWhen: doneWhen, undo: self.undo)
            guard let desk else { return }
            // The copies carry no undo of their own: undoing the set re-points the pointer at
            // the previous task, and the new task keeps its desk for the day it is activated
            // again — the same shape as a task that was set, filled and then put down.
            for item in desk.contextItems {
                _ = try store.addContextItem(
                    taskID: newID,
                    kindRaw: item.kind.rawValue,
                    value: item.value,
                    displayName: item.displayName,
                    bookmark: item.bookmark
                )
            }
            for rule in desk.rules where !rule.isRetired {
                _ = try store.addRule(
                    taskID: newID,
                    scopeRaw: rule.scope.rawValue,
                    subject: rule.subject,
                    verdictRaw: rule.verdict.rawValue
                )
            }
        }
    }

    func editIntent(taskID: UUID, to intent: String) {
        perform { store in
            try store.editIntent(taskID: taskID, to: intent, undo: self.undo)
        }
    }

    func editDoneWhen(taskID: UUID, to doneWhen: String?) {
        perform { store in
            try store.editDoneWhen(taskID: taskID, to: doneWhen, undo: self.undo)
        }
    }

    /// **A focus block may not be scheduled into a meeting** (focus-cal).
    ///
    /// The control already greys out the presets that would collide, but the refusal lives here
    /// too: the control's outlook was built on the last refresh, and the command palette and the
    /// walkthrough's *Do it for me* reach this method without the control. Checked against the
    /// agenda at the instant of the write, which is the instant `setTimebox` stamps as the start.
    func setTimebox(taskID: UUID, seconds: Int?) {
        let outlook = environment.calendarAgenda.outlook(at: dateProvider.now)
        if let refusal = outlook.refusal(forTimeboxSeconds: seconds) {
            // The kind only: when a person's meetings are is theirs, not the log's.
            let kind = switch refusal {
            case .duringMeeting: "during a meeting"
            case .runsIntoMeeting: "runs into a meeting"
            }
            logger.info("refused a timebox: \(kind, privacy: .public)")
            refresh()
            return
        }
        perform { store in
            try store.setTimebox(taskID: taskID, seconds: seconds, undo: self.undo)
        }
    }

    func activate(taskID: UUID) {
        perform { store in
            try store.activate(taskID: taskID, undo: self.undo)
        }
    }

    func complete(taskID: UUID, shipped: String?, restartPoint: String?) {
        perform { store in
            try store.complete(
                taskID: taskID,
                shipped: shipped,
                restartPoint: restartPoint,
                undo: self.undo
            )
        }
    }

    func clear() {
        perform { store in
            try store.clearPriority(undo: self.undo)
        }
    }

    func addContext(taskID: UUID, item: ContextItemDraft) {
        perform { store in
            _ = try store.addContextItem(
                taskID: taskID,
                kindRaw: item.kind.rawValue,
                value: item.value,
                displayName: item.displayName,
                bookmark: item.bookmark,
                undo: self.undo
            )
        }
    }

    func removeContext(id: UUID) {
        perform { store in
            try store.removeContextItem(id: id, undo: self.undo)
        }
    }

    func addRule(
        taskID: UUID,
        scope: PriorityRuleScope,
        subject: String,
        verdict: PriorityRuleVerdict
    ) {
        perform { store in
            _ = try store.addRule(
                taskID: taskID,
                scopeRaw: scope.rawValue,
                subject: subject,
                verdictRaw: verdict.rawValue,
                undo: self.undo
            )
        }
    }

    /// Give a rule the query ledger already committed its place in the undo journal (R-78, F-93).
    ///
    /// "Yes, add it" writes its rule and its immutable receipt in **one** transaction, inside
    /// `QueryLedger.answer(…)`, because R-78 forbids an interval in which the app has learned the
    /// answer but forgotten the asking. That transaction is not this store's, so the rule arrives
    /// already persisted and unjournalled. Calling `addRule(…)` for the undo would insert a
    /// duplicate under a fresh identifier; this registers the inverse alone and refreshes the
    /// projection so the learned chip and the Rules-pane row appear.
    func registerLearnedRuleUndo(id: UUID) {
        perform { store in
            store.registerCommittedRuleUndo(id: id, undo: self.undo)
        }
    }

    func changeRule(id: UUID, verdict: PriorityRuleVerdict) {
        perform { store in
            try store.changeRule(id: id, verdictRaw: verdict.rawValue, undo: self.undo)
        }
    }

    func removeRule(id: UUID) {
        perform { store in
            try store.removeRule(id: id, undo: self.undo)
        }
    }

    /// Accept an incoming handoff. **Only ever reached from the confirmation sheet's Replace
    /// button** — `receive(_:)` above stores the request and draws it, and nothing else in the
    /// app calls this.
    func acceptHandoff(_ request: HandoffRequest) {
        // The same refusal as `setPriority`, for the same reason and by the same reading: a
        // handoff is a new commitment that arrived through a URL rather than through the field.
        guard !state.capturingIsRefused else { return }
        pendingHandoff = nil
        perform { store in
            _ = try store.setPriority(
                intent: request.task,
                doneWhen: request.doneWhen,
                undo: self.undo
            )
        }
    }

    func cancelHandoff() {
        guard pendingHandoff != nil else { return }
        pendingHandoff = nil
        refresh()
    }

    /// **The person read the sheet and pressed its button** (focus-tzj.4).
    ///
    /// It changes nothing about the store, because there is nothing to change. What it changes
    /// is what the app is entitled to assume: from here on, a priority captured into a container
    /// that will not survive quit is captured by somebody who has been told that.
    func acknowledgeStoreFailure() {
        guard !storeFailureAcknowledged else { return }
        storeFailureAcknowledged = true
        refresh()
    }

    /// Record that today's ritual has been answered **or** dismissed. The same write for both,
    /// which is what makes "it asks once" true rather than aspirational (F-19).
    func dismissRitual() {
        let today = LocalDay.today(calendar: calendar, dateProvider: dateProvider)
        do {
            let now = dateProvider.now
            // Reuse the one sanctioned creator of the settings row rather than writing a
            // second one here. Passing the preference the store already holds makes this a
            // no-op on that column and an upsert on the row.
            let row = try FocusStore.setAppearancePreference(
                FocusStore.appearancePreference(in: context),
                in: context,
                now: now
            )
            row.lastRitualLocalDay = DailyRitualGate.dayKeyAfterPrompting(today)
            try context.save()
            writeFailure = nil
        } catch {
            record(error)
        }
        refresh()
    }

    // MARK: - Mutating, once

    /// Every verb funnels through here: run it, remember what went wrong if anything did, and
    /// rebuild the state the cockpit draws.
    private func perform(_ body: (PriorityStore) throws -> Void) {
        do {
            try body(store)
            writeFailure = nil
        } catch {
            record(error)
        }
        refresh()
    }

    private func record(_ error: any Error) {
        writeFailure = error.localizedDescription
        logger.error("the priority store refused a write: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - Projection

    /// Rebuild `CockpitState` from the store.
    ///
    /// One pass: the active task (if any) with its resolved context pack, its rules and the
    /// validator's opinion of its sentence; the history; and the ritual's answer for today.
    func refresh() {
        let now = dateProvider.now
        // Seeded with what is already on screen: if the fetch throws, the honest thing is to
        // keep drawing the last state the store agreed to and report the failure through
        // `storeIsReady`, rather than to blank the window.
        var priority: PrioritySnapshot? = state.priority
        var recent: [RecentPriority] = state.recent
        // Seeded with what it already is, so a fetch that throws cannot be read as "the person
        // cleared their priority" — which would invalidate the engine's snapshot for a reason
        // that never happened. `nextCommitment` is seeded for exactly the same reason, and from
        // the same instant, so the three readings below cannot part company over a store failure
        // (focus-zrs) — which is precisely the divergence that produced this round's defect A.
        var nextKey = snapshotKey
        var nextCommitment = activeCommitment

        do {
            let activeTask = try store.activeTask()
            let items = activeTask.map(contextValues(for:)) ?? []
            let rules = activeTask.map(ruleValues(for:)) ?? []
            priority = activeTask.map { task in
                PrioritySnapshot(
                    task,
                    now: now,
                    contextItems: items,
                    rules: rules,
                    assessment: IntentValidator.assess(task.intent, locale: locale),
                    calendar: environment.calendarAgenda.outlook(at: now)
                )
            }
            // One fetch, three derivations. Every one of them takes its identifier from
            // `nextCommitment`, so there is nowhere for a second opinion to come from.
            nextCommitment = activeTask.map {
                ActiveCommitment(id: $0.id, intent: $0.intent)
            }
            nextKey = SnapshotKey(
                priorityID: nextCommitment?.id,
                revision: activeTask?.revision ?? 0,
                contextItems: items,
                rules: rules
            )
            // **The history is re-read when a priority row moved, and not once a tick**
            // (focus-tzj.2). `refresh()` runs on every accepted activation *and* on the
            // five-second corroboration tick, and this line fetched the store's whole
            // `PriorityTask` table each time to draw a list of eight that changes when somebody
            // captures, edits, activates or completes a commitment — a few times a day.
            //
            // Two conditions, because they catch different things and neither implies the other:
            // `PriorityStore.mutationCount` moves for any write in this process, **including an
            // undo**, which reaches no verb on this host and is exactly the case a
            // "set a flag in `perform`" version would miss; and the snapshot key moves when the
            // active commitment or its contents changed, which is when the *first* row of the
            // list is drawn differently. The seed is `historyRevision == nil`, so the first
            // refresh of a launch always reads.
            let revision = PriorityStore.mutationCount
            if historyRevision != revision || nextKey != snapshotKey {
                recent = try store.recentTasks(limit: Self.historyLimit).map(RecentPriority.init)
                // Assigned only after the fetch returned. A throw leaves it where it was, so the
                // next tick tries again rather than caching the absence of an answer.
                historyRevision = revision
            }
        } catch {
            record(error)
        }

        let next = CockpitState(
            status: environment.status,
            // **Two facts, told apart** (focus-tzj.4). This was one boolean:
            // `environment.storeIsReady && writeFailure == nil` — a store that never opened and
            // a write that was refused a second ago, OR-ed into one warning line. They are two
            // different things to say to somebody and only one of them costs a day's work.
            storeOpened: environment.storeOpened,
            lastWriteFailed: writeFailure != nil,
            storeFailureAcknowledged: storeFailureAcknowledged,
            storeLocation: storeLocation,
            isObservingActivity: environment.isObservingActivity,
            priority: priority,
            recent: recent,
            pendingHandoff: pendingHandoff,
            showsRitualPrompt: shouldPromptRitual(),
            session: environment.session,
            sensing: environment.sensing,
            verdict: environment.verdict,
            capabilities: environment.capabilities,
            showsLaunchAtLoginOffer: environment.showsLaunchAtLoginOffer,
            showsFirstRunExplanation: environment.showsFirstRunExplanation
        )

        activeCommitment = nextCommitment

        // Assigned only when it actually changed. From e03 this projection is rebuilt on the
        // five-second corroboration tick as well as on every mutation, and `@Observable` reports
        // a write rather than a difference — so an unconditional assignment would redraw the
        // window twelve times a minute to show the same picture.
        let stateChanged = next != state
        if stateChanged { state = next }

        // **Everything is assigned before anything is announced** (focus-zrs). The invalidation
        // used to fire *between* moving `snapshotKey` and assigning `state`, which left a window —
        // the whole of the callback — in which this object told two different stories about which
        // commitment was active. `AppComposition.noticeLifecycleTransitions()` carried a comment
        // explaining which of the two to read, which is the shape of every defect this round is
        // about: a rule for living with a disagreement rather than the removal of it. Closing the
        // window means an observer sees one consistent object however deeply it looks.
        //
        // The engine's snapshot is invalidated here rather than by each verb, so there is no
        // mutation that can change one of the four facts without passing this comparison —
        // including an undo, which does not go through a verb at all.
        if nextKey != snapshotKey {
            snapshotKey = nextKey
            onSnapshotInvalidated?()
        }
        if stateChanged { onStateChanged?() }
    }

    /// **Every way this host states the active commitment, and whether they agree** — and it is
    /// always empty (focus-zrs).
    ///
    /// A reading rather than a comment, for the reason `NudgeHost.orphanedNudgeSurfaces` is
    /// one: an invariant nobody can take a reading of is a belief. `refresh()` derives all three
    /// from one fetch and assigns them before it announces anything, so a non-empty answer means a
    /// second door to the active priority has been opened somewhere — which is the class this
    /// round exists to close, recurring.
    var commitmentDisagreements: [String] {
        var disagreements: [String] = []
        if snapshotKey.priorityID != activeCommitment?.id {
            disagreements.append(
                "snapshotKey.priorityID \(describe(snapshotKey.priorityID)) "
                    + "≠ activeCommitment \(describe(activeCommitment?.id))"
            )
        }
        if state.priority?.id != activeCommitment?.id {
            disagreements.append(
                "state.priority.id \(describe(state.priority?.id)) "
                    + "≠ activeCommitment \(describe(activeCommitment?.id))"
            )
        }
        if state.priority?.intent != activeCommitment?.intent {
            disagreements.append(
                "state.priority.intent ≠ activeCommitment.intent"
            )
        }
        return disagreements
    }

    private func describe(_ id: UUID?) -> String { id?.uuidString ?? "none" }

    /// How many previous commitments the history offers. F-15 is a recent list, not a backlog:
    /// a scrolling archive would be the second commitment F-02 exists to refuse.
    static let historyLimit = 8

    private func contextValues(for task: FocusSchemaV3.PriorityTask) -> [ContextItemValue] {
        task.contextItems
            .sorted { $0.addedAt < $1.addedAt }
            .map(resolvedValue(for:))
    }

    /// Decide one chip's availability, touching the disk only for file items.
    ///
    /// A stale bookmark is re-created and saved silently (R-22): the file moved, and the user
    /// should not have to care. A missing one leaves the chip in its *missing* state with a
    /// Locate… action — it is **never** removed, because deleting somebody's context when a
    /// disk is unplugged is a bug, not tidiness.
    private func resolvedValue(for item: FocusSchemaV3.ContextItem) -> ContextItemValue {
        guard item.kind == .file else { return ContextItemValue(item) }
        guard let bookmark = item.bookmark else {
            return ContextItemValue(item, availability: .missing)
        }

        switch SecurityScopedBookmark.resolve(bookmark) {
        case .resolved(let url, let isStale):
            if isStale { refreshBookmark(on: item, at: url) }
            return ContextItemValue(item, availability: .available)
        case .missing:
            return ContextItemValue(item, availability: .missing)
        case .failed(let error):
            logger.notice("a context bookmark would not resolve: \(error.localizedDescription, privacy: .public)")
            return ContextItemValue(item, availability: .missing)
        }
    }

    private func refreshBookmark(on item: FocusSchemaV3.ContextItem, at url: URL) {
        guard let fresh = try? SecurityScopedBookmark.create(for: url) else { return }
        item.bookmark = fresh
        item.value = url.path(percentEncoded: false)
        item.displayName = url.lastPathComponent
        // Housekeeping, not a user action: it goes straight to the context so it never lands
        // in the Edit menu.
        try? context.save()
    }

    /// The rules the pane can draw. A rule written by a later version — an unknown scope or
    /// verdict — is skipped rather than guessed at, and is never rewritten or deleted, so it
    /// survives the round trip intact.
    private func ruleValues(for task: FocusSchemaV3.PriorityTask) -> [PriorityRuleValue] {
        task.rules
            .sorted { $0.createdAt < $1.createdAt }
            .compactMap(PriorityRuleValue.init)
    }

    private func shouldPromptRitual() -> Bool {
        guard let row = FocusStore.settingsRow(in: context) else {
            // No settings row at all means the app has never stored anything, which is the
            // first launch — and the ritual is enabled by default.
            return true
        }
        return DailyRitualGate.shouldPrompt(
            lastRitualLocalDay: row.lastRitualLocalDay,
            today: LocalDay.today(calendar: calendar, dateProvider: dateProvider),
            isEnabled: row.ritualEnabled
        )
    }
}
