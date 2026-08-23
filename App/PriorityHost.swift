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
    }

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
            isObservingActivity: environment.isObservingActivity
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

        do {
            let activeTask = try store.activeTask()
            priority = activeTask.map { task in
                PrioritySnapshot(
                    task,
                    now: now,
                    contextItems: contextValues(for: task),
                    rules: ruleValues(for: task),
                    assessment: IntentValidator.assess(task.intent, locale: locale)
                )
            }
            recent = try store.recentTasks(limit: Self.historyLimit).map(RecentPriority.init)
        } catch {
            record(error)
        }

        state = CockpitState(
            status: environment.status,
            storeIsReady: environment.storeIsReady && writeFailure == nil,
            isObservingActivity: environment.isObservingActivity,
            priority: priority,
            recent: recent,
            pendingHandoff: pendingHandoff,
            showsRitualPrompt: shouldPromptRitual()
        )
    }

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
