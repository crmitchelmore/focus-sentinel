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
        var storeIsReady: Bool
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

    init(
        context: ModelContext,
        dateProvider: any DateProvider,
        calendar: Calendar,
        locale: Locale,
        environment: Environment
    ) {
        self.context = context
        self.store = PriorityStore(context: context, dateProvider: dateProvider)
        self.dateProvider = dateProvider
        self.calendar = calendar
        self.locale = locale
        self.environment = environment
        self.state = CockpitState(
            status: environment.status,
            storeIsReady: environment.storeIsReady,
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
        perform { store in
            _ = try store.setPriority(intent: intent, doneWhen: doneWhen, undo: self.undo)
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

    func setTimebox(taskID: UUID, seconds: Int?) {
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
                    assessment: IntentValidator.assess(task.intent, locale: locale)
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
            recent = try store.recentTasks(limit: Self.historyLimit).map(RecentPriority.init)
        } catch {
            record(error)
        }

        let next = CockpitState(
            status: environment.status,
            storeIsReady: environment.storeIsReady && writeFailure == nil,
            isObservingActivity: environment.isObservingActivity,
            priority: priority,
            recent: recent,
            pendingHandoff: pendingHandoff,
            showsRitualPrompt: shouldPromptRitual(),
            session: environment.session,
            sensing: environment.sensing,
            verdict: environment.verdict,
            capabilities: environment.capabilities
        )

        activeCommitment = nextCommitment

        // Assigned only when it actually changed. From e03 this projection is rebuilt on the
        // five-second corroboration tick as well as on every mutation, and `@Observable` reports
        // a write rather than a difference — so an unconditional assignment would redraw the
        // window twelve times a minute to show the same picture.
        if next != state { state = next }

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
    }

    /// **Every way this host states the active commitment, and whether they agree** — and it is
    /// always empty (focus-zrs).
    ///
    /// A reading rather than a comment, for the reason `NudgeHost.orphanedQuestionSurfaces` is
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
