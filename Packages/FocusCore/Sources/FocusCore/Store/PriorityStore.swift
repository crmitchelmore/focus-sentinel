import Foundation
import SwiftData

/// The name an undoable operation shows in the Edit menu.
///
/// The keys live in **`FocusCore`'s** String Catalog, because the store that registers them
/// lives here. They resolve against this package's own bundle, exactly as
/// `FocusStatus.shortLabel` does — and, exactly as there, a lookup under `swift test` returns
/// the key itself, because SwiftPM copies String Catalogs instead of compiling them. Tests
/// that assert on the rendered text are therefore gated on `LocalizationLane`.
public enum UndoActionName: String, Sendable, CaseIterable, Hashable {
    case setPriority = "undo.priority.set"
    case addPriority = "undo.priority.create"
    case changePriority = "undo.priority.change"
    case clearPriority = "undo.priority.clear"
    case completePriority = "undo.priority.complete"
    case deletePriority = "undo.priority.delete"
    case editIntent = "undo.intent.edit"
    case editDoneWhen = "undo.doneWhen.edit"
    case setTimebox = "undo.timebox.set"
    case addContext = "undo.context.add"
    case removeContext = "undo.context.remove"
    case addRule = "undo.rule.add"
    case changeRule = "undo.rule.change"
    case removeRule = "undo.rule.remove"

    /// The String Catalog key. Also what the catalog-completeness lint compares against.
    public var key: String { rawValue }

    /// The localised name, as `UndoManager.setActionName(_:)` wants it.
    public var localizedName: String {
        String(
            localized: String.LocalizationValue(rawValue),
            bundle: .module,
            comment: "Name of an undoable operation, shown in the Edit menu after Undo/Redo"
        )
    }
}

/// The single mutation facade for the priority model — and the home of the undo journal.
///
/// ## Why the journal is here and not in SwiftData
///
/// SwiftData ships `ModelContext.undoManager`, and it is **not** used. Probe P-48 measured
/// two failures that matter: an undo group containing "delete the old pointer, insert the new
/// one" undoes only the insert, leaving *no* active priority rather than the previous one;
/// and undoing an insert whose row had been merged by the unique constraint **crashed the
/// process**. Silently restoring the wrong state is worse than failing loudly, so
/// `ModelContext.undoManager` is never assigned and `scripts/check-forbidden.sh` fails the
/// gate on any assignment to it.
///
/// What ships instead is a domain-level journal. Every mutating method here:
///
/// 1. captures its inverse as **plain values** — identifiers, strings, dates — before
///    mutating, because a reference to a `@Model` that is about to be deleted is a trap;
/// 2. opens its own undo group and sets a localised action name, *inside* the facade, so the
///    identical code is correct in the app (`groupsByEvent == true`) and in a headless test
///    (`false`, where an unwrapped registration raises
///    `NSInternalInconsistencyException: … must begin a group before registering undo`);
/// 3. mutates, saves, and registers the inverse **through this same facade** — which is what
///    makes redo free: performing the inverse registers the original in its turn.
///
/// The class is `@MainActor` and the handler re-enters through `MainActor.assumeIsolated`
/// because under Swift 6 strict concurrency `registerUndo(withTarget:)` will not compile
/// otherwise (P-49).
///
/// ## Activation never provokes the unique constraint
///
/// `activate(taskID:undo:)` fetches the single `ActivePriority` row and **re-points** it. It
/// never inserts a second one: inserting a colliding row whose target already owns a pointer
/// is a process fatal error in SwiftData (P-46), and re-activating your current priority is
/// an ordinary thing for a person to do. The unique attribute stays as the store-level
/// backstop that keeps the invariant true even against a bug — not as a mechanism the app
/// relies on.
@MainActor
public final class PriorityStore {
    private let context: ModelContext
    private let dateProvider: any DateProvider

    /// The `RuleScope` raw value that completion clears.
    ///
    /// The scope vocabulary itself lives in `FocusRules`, which `FocusCore` may not import, so
    /// the store keeps the string — the same arrangement `RelevanceRule.scopeRaw` has had
    /// since v1.
    public static let sessionRuleScopeRaw = "session"

    public init(context: ModelContext, dateProvider: some DateProvider = SystemDateProvider()) {
        self.context = context
        self.dateProvider = dateProvider
    }

    // MARK: - Reads

    /// The active priority, or `nil` if there is none.
    ///
    /// One fetch of the pointer row, whose relationship resolves the task.
    public func activeTask() throws -> FocusSchemaV3.PriorityTask? {
        try activePointer()?.task
    }

    /// The single `ActivePriority` row, if one exists.
    public func activePointer() throws -> FocusSchemaV3.ActivePriority? {
        try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>()).first
    }

    /// How many pointer rows the store currently holds. Should only ever be `0` or `1`; a
    /// test asserts exactly that, rather than trusting it.
    public func activePointerCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<FocusSchemaV3.ActivePriority>())
    }

    public func task(id: UUID) throws -> FocusSchemaV3.PriorityTask? {
        let descriptor = FetchDescriptor<FocusSchemaV3.PriorityTask>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    /// The history, newest first (F-15).
    ///
    /// Ordered by `lastActivatedAt` descending, with never-activated tasks after the
    /// activated ones and `createdAt` breaking every tie. Sorted in Swift rather than by the
    /// store so that the ordering of `nil` is a decision rather than whatever SQLite felt
    /// like.
    public func recentTasks(limit: Int? = nil) throws -> [FocusSchemaV3.PriorityTask] {
        let all = try context.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>())
        let sorted = all.sorted { lhs, rhs in
            switch (lhs.lastActivatedAt, rhs.lastActivatedAt) {
            case let (left?, right?) where left != right:
                return left > right
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            default:
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
        guard let limit else { return sorted }
        return Array(sorted.prefix(limit))
    }

    public func contextItem(id: UUID) throws -> FocusSchemaV3.ContextItem? {
        let descriptor = FetchDescriptor<FocusSchemaV3.ContextItem>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    public func rule(id: UUID) throws -> FocusSchemaV3.RelevanceRule? {
        let descriptor = FetchDescriptor<FocusSchemaV3.RelevanceRule>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    // MARK: - The journal

    /// Open a group, name it, mutate, save, and register the inverse.
    ///
    /// The grouping lives here rather than at the call site so that every operation is
    /// correct in both undo lanes — see the type's documentation.
    private func journal<T>(
        _ name: UndoActionName,
        undo: UndoManager?,
        mutate: () throws -> T,
        inverse: @escaping @MainActor (PriorityStore, UndoManager?) -> Void
    ) throws -> T {
        undo?.beginUndoGrouping()
        defer { undo?.endUndoGrouping() }
        undo?.setActionName(name.localizedName)

        let result = try mutate()
        try context.save()

        undo?.registerUndo(withTarget: self) { store in
            // `UndoManager` runs a registered handler synchronously on the thread that called
            // `undo()`, and the only caller is the responder chain's Edit ▸ Undo, on main.
            MainActor.assumeIsolated {
                inverse(store, undo)
            }
        }
        return result
    }

    private func requireTask(_ id: UUID) throws -> FocusSchemaV3.PriorityTask {
        guard let task = try task(id: id) else { throw PriorityStoreError.taskNotFound(id) }
        return task
    }

    // MARK: - Priority lifecycle

    /// Capture a new priority and make it the active one — the primary user action.
    ///
    /// A single journal entry, deliberately: a person who types a sentence, presses Return and
    /// then presses ⌘Z expects one undo to take them back to where they were, not two.
    @discardableResult
    public func setPriority(
        intent: String,
        doneWhen: String? = nil,
        undo: UndoManager? = nil
    ) throws -> UUID {
        try setPriority(intent: intent, doneWhen: doneWhen, actionName: .setPriority, undo: undo)
    }

    @discardableResult
    private func setPriority(
        intent: String,
        doneWhen: String?,
        actionName: UndoActionName,
        undo: UndoManager?
    ) throws -> UUID {
        let trimmed = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PriorityStoreError.emptyIntent }

        let previous = try previousActivation()
        let now = dateProvider.now
        let newID = UUID()

        return try journal(
            actionName,
            undo: undo,
            mutate: {
                let task = FocusSchemaV3.PriorityTask(
                    id: newID,
                    intent: trimmed,
                    doneWhen: doneWhen,
                    createdAt: now,
                    lastActivatedAt: now
                )
                context.insert(task)
                try rePoint(to: task, at: now)
                return newID
            },
            inverse: { store, undo in
                try? store.undoSetPriority(
                    newTaskID: newID,
                    previous: previous,
                    actionName: actionName,
                    undo: undo
                )
            }
        )
    }

    /// The inverse of `setPriority`: remove the task that was created and put the previous
    /// activation back exactly as it was.
    private func undoSetPriority(
        newTaskID: UUID,
        previous: Activation?,
        actionName: UndoActionName,
        undo: UndoManager?
    ) throws {
        let snapshot = try TaskSnapshot(task: requireTask(newTaskID), wasActive: true)

        try journal(
            actionName,
            undo: undo,
            mutate: {
                if let task = try task(id: newTaskID) { context.delete(task) }
                try restoreActivation(previous)
            },
            inverse: { store, undo in
                try? store.restoreTask(snapshot, actionName: actionName, undo: undo)
            }
        )
    }

    /// Create a task **without** activating it.
    ///
    /// Used by the handoff and history paths, which create a row and then decide separately
    /// whether it becomes the priority.
    @discardableResult
    public func createTask(
        intent: String,
        doneWhen: String? = nil,
        undo: UndoManager? = nil
    ) throws -> UUID {
        try createTask(intent: intent, doneWhen: doneWhen, actionName: .addPriority, undo: undo)
    }

    @discardableResult
    private func createTask(
        intent: String,
        doneWhen: String?,
        actionName: UndoActionName,
        undo: UndoManager?
    ) throws -> UUID {
        let trimmed = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PriorityStoreError.emptyIntent }

        let now = dateProvider.now
        let newID = UUID()

        return try journal(
            actionName,
            undo: undo,
            mutate: {
                context.insert(
                    FocusSchemaV3.PriorityTask(
                        id: newID,
                        intent: trimmed,
                        doneWhen: doneWhen,
                        createdAt: now
                    )
                )
                return newID
            },
            inverse: { store, undo in
                try? store.deleteTask(id: newID, actionName: actionName, undo: undo)
            }
        )
    }

    /// Make an existing task the active priority.
    ///
    /// This is also F-15's "work on this again": it re-points at the *existing* row and clears
    /// `completedAt`, so the stored context pack and rules come back with it by construction
    /// rather than by copying.
    public func activate(taskID: UUID, undo: UndoManager? = nil) throws {
        try activate(taskID: taskID, actionName: .changePriority, undo: undo)
    }

    private func activate(taskID: UUID, actionName: UndoActionName, undo: UndoManager?) throws {
        let task = try requireTask(taskID)
        let previous = try previousActivation()
        let previousLastActivatedAt = task.lastActivatedAt
        let previousCompletedAt = task.completedAt
        let now = dateProvider.now

        try journal(
            actionName,
            undo: undo,
            mutate: {
                task.lastActivatedAt = now
                task.completedAt = nil
                try rePoint(to: task, at: now)
            },
            inverse: { store, undo in
                try? store.undoActivate(
                    taskID: taskID,
                    lastActivatedAt: previousLastActivatedAt,
                    completedAt: previousCompletedAt,
                    previous: previous,
                    actionName: actionName,
                    undo: undo
                )
            }
        )
    }

    private func undoActivate(
        taskID: UUID,
        lastActivatedAt: Date?,
        completedAt: Date?,
        previous: Activation?,
        actionName: UndoActionName,
        undo: UndoManager?
    ) throws {
        let task = try requireTask(taskID)
        let redoLastActivatedAt = task.lastActivatedAt
        let redoCompletedAt = task.completedAt
        let redoPrevious = try previousActivation()

        try journal(
            actionName,
            undo: undo,
            mutate: {
                task.lastActivatedAt = lastActivatedAt
                task.completedAt = completedAt
                try restoreActivation(previous)
            },
            inverse: { store, undo in
                try? store.undoActivate(
                    taskID: taskID,
                    lastActivatedAt: redoLastActivatedAt,
                    completedAt: redoCompletedAt,
                    previous: redoPrevious,
                    actionName: actionName,
                    undo: undo
                )
            }
        )
    }

    /// Clear the active priority without completing or deleting anything.
    public func clearPriority(undo: UndoManager? = nil) throws {
        try clearPriority(actionName: .clearPriority, undo: undo)
    }

    private func clearPriority(actionName: UndoActionName, undo: UndoManager?) throws {
        let previous = try previousActivation()

        try journal(
            actionName,
            undo: undo,
            mutate: {
                try rePoint(to: nil, at: dateProvider.now)
            },
            inverse: { store, undo in
                try? store.undoClearPriority(previous: previous, actionName: actionName, undo: undo)
            }
        )
    }

    private func undoClearPriority(
        previous: Activation?,
        actionName: UndoActionName,
        undo: UndoManager?
    ) throws {
        let redoPrevious = try previousActivation()

        try journal(
            actionName,
            undo: undo,
            mutate: {
                try restoreActivation(previous)
            },
            inverse: { store, undo in
                try? store.undoClearPriority(
                    previous: redoPrevious,
                    actionName: actionName,
                    undo: undo
                )
            }
        )
    }

    // MARK: - Editing a priority

    /// Edit the intent, bumping `revision` so e04's verdict cache goes stale.
    public func editIntent(taskID: UUID, to intent: String, undo: UndoManager? = nil) throws {
        try editIntent(taskID: taskID, to: intent, restoringRevision: nil, undo: undo)
    }

    private func editIntent(
        taskID: UUID,
        to intent: String,
        restoringRevision: Int?,
        undo: UndoManager?
    ) throws {
        let trimmed = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PriorityStoreError.emptyIntent }

        let task = try requireTask(taskID)
        let previousIntent = task.intent
        let previousRevision = task.revision

        try journal(
            .editIntent,
            undo: undo,
            mutate: {
                task.intent = trimmed
                task.revision = restoringRevision ?? previousRevision + 1
            },
            inverse: { store, undo in
                try? store.editIntent(
                    taskID: taskID,
                    to: previousIntent,
                    restoringRevision: previousRevision,
                    undo: undo
                )
            }
        )
    }

    /// Edit the definition of done (F-08). `nil` removes it; it was always optional.
    public func editDoneWhen(taskID: UUID, to doneWhen: String?, undo: UndoManager? = nil) throws {
        try editDoneWhen(taskID: taskID, to: doneWhen, restoringRevision: nil, undo: undo)
    }

    private func editDoneWhen(
        taskID: UUID,
        to doneWhen: String?,
        restoringRevision: Int?,
        undo: UndoManager?
    ) throws {
        let task = try requireTask(taskID)
        let previousDoneWhen = task.doneWhen
        let previousRevision = task.revision
        let normalised = doneWhen?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = (normalised?.isEmpty ?? true) ? nil : normalised

        try journal(
            .editDoneWhen,
            undo: undo,
            mutate: {
                task.doneWhen = stored
                task.revision = restoringRevision ?? previousRevision + 1
            },
            inverse: { store, undo in
                try? store.editDoneWhen(
                    taskID: taskID,
                    to: previousDoneWhen,
                    restoringRevision: previousRevision,
                    undo: undo
                )
            }
        )
    }

    /// Set or clear the timebox (F-12).
    ///
    /// `startedAt` is stamped from the injected wall clock when a timebox is set and cleared
    /// with it. Wall clock, deliberately: a timebox is a promise about the clock on the wall,
    /// so a Mac that slept for an hour has spent that hour.
    public func setTimebox(taskID: UUID, seconds: Int?, undo: UndoManager? = nil) throws {
        try setTimebox(
            taskID: taskID,
            seconds: seconds,
            startedAt: seconds == nil ? nil : dateProvider.now,
            undo: undo
        )
    }

    private func setTimebox(
        taskID: UUID,
        seconds: Int?,
        startedAt: Date?,
        undo: UndoManager?
    ) throws {
        let task = try requireTask(taskID)
        let previousSeconds = task.timeboxSeconds
        let previousStartedAt = task.startedAt

        try journal(
            .setTimebox,
            undo: undo,
            mutate: {
                task.timeboxSeconds = seconds
                task.startedAt = startedAt
            },
            inverse: { store, undo in
                try? store.setTimebox(
                    taskID: taskID,
                    seconds: previousSeconds,
                    startedAt: previousStartedAt,
                    undo: undo
                )
            }
        )
    }

    // MARK: - Completion

    /// Complete the priority (F-22).
    ///
    /// Both reflection fields are optional and completion never waits for them. Completing
    /// writes `completedAt`, deletes the pointer row — the task is history now, not the
    /// current commitment — and clears every `.session`-scoped rule.
    public func complete(
        taskID: UUID,
        shipped: String? = nil,
        restartPoint: String? = nil,
        undo: UndoManager? = nil
    ) throws {
        let task = try requireTask(taskID)
        let previousCompletedAt = task.completedAt
        let previousShipped = task.shipped
        let previousRestartPoint = task.restartPoint
        let previousActivation = try previousActivation()
        let clearedRules = try sessionRules().map(RuleSnapshot.init(rule:))
        let now = dateProvider.now

        try journal(
            .completePriority,
            undo: undo,
            mutate: {
                task.completedAt = now
                task.shipped = normalised(shipped)
                task.restartPoint = normalised(restartPoint)
                for rule in try sessionRules() { context.delete(rule) }
                if task.isActive { try rePoint(to: nil, at: now) }
            },
            inverse: { store, undo in
                try? store.undoComplete(
                    taskID: taskID,
                    completedAt: previousCompletedAt,
                    shipped: previousShipped,
                    restartPoint: previousRestartPoint,
                    previous: previousActivation,
                    rules: clearedRules,
                    undo: undo
                )
            }
        )
    }

    private func undoComplete(
        taskID: UUID,
        completedAt: Date?,
        shipped: String?,
        restartPoint: String?,
        previous: Activation?,
        rules: [RuleSnapshot],
        undo: UndoManager?
    ) throws {
        let task = try requireTask(taskID)
        let redoCompletedAt = task.completedAt
        let redoShipped = task.shipped
        let redoRestartPoint = task.restartPoint
        let redoPrevious = try previousActivation()
        let redoRules = try sessionRules().map(RuleSnapshot.init(rule:))

        try journal(
            .completePriority,
            undo: undo,
            mutate: {
                task.completedAt = completedAt
                task.shipped = shipped
                task.restartPoint = restartPoint
                for rule in try sessionRules() { context.delete(rule) }
                for snapshot in rules { try insert(snapshot) }
                try restoreActivation(previous)
            },
            inverse: { store, undo in
                try? store.undoComplete(
                    taskID: taskID,
                    completedAt: redoCompletedAt,
                    shipped: redoShipped,
                    restartPoint: redoRestartPoint,
                    previous: redoPrevious,
                    rules: redoRules,
                    undo: undo
                )
            }
        )
    }

    // MARK: - Context pack

    @discardableResult
    public func addContextItem(
        taskID: UUID,
        kindRaw: String,
        value: String,
        displayName: String,
        bookmark: Data? = nil,
        undo: UndoManager? = nil
    ) throws -> UUID {
        let snapshot = ContextItemSnapshot(
            id: UUID(),
            kindRaw: kindRaw,
            value: value,
            displayName: displayName,
            bookmark: bookmark,
            addedAt: dateProvider.now,
            taskID: taskID
        )
        return try addContextItem(snapshot, undo: undo)
    }

    @discardableResult
    private func addContextItem(_ snapshot: ContextItemSnapshot, undo: UndoManager?) throws -> UUID {
        _ = try requireTask(snapshot.taskID)

        return try journal(
            .addContext,
            undo: undo,
            mutate: {
                try insert(snapshot)
                return snapshot.id
            },
            inverse: { store, undo in
                try? store.removeContextItem(id: snapshot.id, undo: undo)
            }
        )
    }

    public func removeContextItem(id: UUID, undo: UndoManager? = nil) throws {
        guard let item = try contextItem(id: id) else {
            throw PriorityStoreError.contextItemNotFound(id)
        }
        let snapshot = ContextItemSnapshot(item: item)

        try journal(
            .removeContext,
            undo: undo,
            mutate: {
                context.delete(item)
            },
            inverse: { store, undo in
                _ = try? store.addContextItem(snapshot, undo: undo)
            }
        )
    }

    // MARK: - Rules

    @discardableResult
    public func addRule(
        taskID: UUID?,
        scopeRaw: String,
        subject: String,
        verdictRaw: String,
        undo: UndoManager? = nil
    ) throws -> UUID {
        let snapshot = RuleSnapshot(
            id: UUID(),
            scopeRaw: scopeRaw,
            subject: subject,
            verdictRaw: verdictRaw,
            createdAt: dateProvider.now,
            taskID: taskID
        )
        return try addRule(snapshot, undo: undo)
    }

    @discardableResult
    private func addRule(_ snapshot: RuleSnapshot, undo: UndoManager?) throws -> UUID {
        if let taskID = snapshot.taskID { _ = try requireTask(taskID) }

        return try journal(
            .addRule,
            undo: undo,
            mutate: {
                try insert(snapshot)
                return snapshot.id
            },
            inverse: { store, undo in
                try? store.removeRule(id: snapshot.id, undo: undo)
            }
        )
    }

    /// Register the undo for a rule **another transaction has already committed** (R-78, F-93).
    ///
    /// A query answer writes its rule and its immutable receipt inside `QueryLedger.answer(…)`,
    /// as one transaction, because the two records must commit together or not at all. That
    /// leaves the rule persisted but with no entry in the undo journal — and R-86's table says
    /// "Yes, part of this" is undoable like every other correction.
    ///
    /// Calling `addRule(…)` to get the undo would insert a **second** row under a fresh
    /// identifier, so this registers the inverse and nothing else. It writes nothing, so it
    /// cannot fail; the inverse is `removeRule(id:undo:)`, which journals its own redo the way
    /// every other inverse in this file does.
    ///
    /// - Parameters:
    ///   - id: the identifier the committed row already carries.
    ///   - undo: the responder-chain undo manager, or `nil` when there is none to register with.
    public func registerCommittedRuleUndo(id: UUID, undo: UndoManager?) {
        guard let undo else { return }

        undo.beginUndoGrouping()
        undo.setActionName(UndoActionName.addRule.localizedName)
        undo.registerUndo(withTarget: self) { store in
            // `UndoManager` runs a registered handler synchronously on the thread that called
            // `undo()`, and the only caller is the responder chain's Edit ▸ Undo, on main.
            MainActor.assumeIsolated {
                try? store.removeRule(id: id, undo: undo)
            }
        }
        undo.endUndoGrouping()
    }

    /// Change a rule's verdict — the "actually, this *is* relevant" path.
    public func changeRule(id: UUID, verdictRaw: String, undo: UndoManager? = nil) throws {
        guard let rule = try rule(id: id) else { throw PriorityStoreError.ruleNotFound(id) }
        let previousVerdict = rule.verdictRaw

        try journal(
            .changeRule,
            undo: undo,
            mutate: {
                rule.verdictRaw = verdictRaw
            },
            inverse: { store, undo in
                try? store.changeRule(id: id, verdictRaw: previousVerdict, undo: undo)
            }
        )
    }

    public func removeRule(id: UUID, undo: UndoManager? = nil) throws {
        guard let rule = try rule(id: id) else { throw PriorityStoreError.ruleNotFound(id) }
        let snapshot = RuleSnapshot(rule: rule)

        try journal(
            .removeRule,
            undo: undo,
            mutate: {
                context.delete(rule)
            },
            inverse: { store, undo in
                _ = try? store.addRule(snapshot, undo: undo)
            }
        )
    }

    // MARK: - Destructive delete

    /// Delete a task, its context pack, its scoped rules and its pointer.
    ///
    /// The most destructive thing the app can do, and therefore the one whose inverse is
    /// captured most completely: every child row travels as values, so undo puts back the
    /// words, the files and the rules — not just an empty task with the right title.
    public func deleteTask(id: UUID, undo: UndoManager? = nil) throws {
        try deleteTask(id: id, actionName: .deletePriority, undo: undo)
    }

    private func deleteTask(id: UUID, actionName: UndoActionName, undo: UndoManager?) throws {
        let task = try requireTask(id)
        let snapshot = TaskSnapshot(task: task, wasActive: task.isActive)

        try journal(
            actionName,
            undo: undo,
            mutate: {
                context.delete(task)
            },
            inverse: { store, undo in
                try? store.restoreTask(snapshot, actionName: actionName, undo: undo)
            }
        )
    }

    private func restoreTask(
        _ snapshot: TaskSnapshot,
        actionName: UndoActionName,
        undo: UndoManager?
    ) throws {
        try journal(
            actionName,
            undo: undo,
            mutate: {
                let task = FocusSchemaV3.PriorityTask(
                    id: snapshot.id,
                    intent: snapshot.intent,
                    doneWhen: snapshot.doneWhen,
                    createdAt: snapshot.createdAt,
                    completedAt: snapshot.completedAt,
                    revision: snapshot.revision,
                    timeboxSeconds: snapshot.timeboxSeconds,
                    startedAt: snapshot.startedAt,
                    shipped: snapshot.shipped,
                    restartPoint: snapshot.restartPoint,
                    lastActivatedAt: snapshot.lastActivatedAt
                )
                context.insert(task)
                for item in snapshot.contextItems { try insert(item) }
                for rule in snapshot.rules { try insert(rule) }
                if snapshot.wasActive {
                    try rePoint(to: task, at: snapshot.activatedAt ?? dateProvider.now)
                }
            },
            inverse: { store, undo in
                try? store.deleteTask(id: snapshot.id, actionName: actionName, undo: undo)
            }
        )
    }

    // MARK: - The pointer, and nothing but the pointer

    /// One row, re-pointed, never re-inserted (R-18).
    ///
    /// `nil` clears the priority by deleting the row. Any stray extra rows are removed rather
    /// than left for the unique constraint to merge: the app survives collision resolution, it
    /// never depends on it.
    private func rePoint(to task: FocusSchemaV3.PriorityTask?, at date: Date) throws {
        let pointers = try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>())

        guard let task else {
            for pointer in pointers { context.delete(pointer) }
            return
        }

        if let pointer = pointers.first {
            for extra in pointers.dropFirst() { context.delete(extra) }
            pointer.task = task
            pointer.activatedAt = date
        } else {
            context.insert(FocusSchemaV3.ActivePriority(task: task, activatedAt: date))
        }
    }

    /// What the pointer pointed at, as plain values — safe to hold across a delete.
    private struct Activation: Sendable, Equatable, Hashable {
        let taskID: UUID
        let activatedAt: Date
    }

    private func previousActivation() throws -> Activation? {
        guard let pointer = try activePointer(), let task = pointer.task else { return nil }
        return Activation(taskID: task.id, activatedAt: pointer.activatedAt)
    }

    private func restoreActivation(_ activation: Activation?) throws {
        guard let activation else {
            try rePoint(to: nil, at: dateProvider.now)
            return
        }
        guard let task = try task(id: activation.taskID) else {
            // The previously active task has since been deleted. Restoring nothing is the
            // honest outcome; inventing a row would be worse.
            try rePoint(to: nil, at: dateProvider.now)
            return
        }
        try rePoint(to: task, at: activation.activatedAt)
    }

    // MARK: - Snapshots

    private struct ContextItemSnapshot: Sendable, Equatable, Hashable {
        let id: UUID
        let kindRaw: String
        let value: String
        let displayName: String
        let bookmark: Data?
        let addedAt: Date
        let taskID: UUID

        init(
            id: UUID,
            kindRaw: String,
            value: String,
            displayName: String,
            bookmark: Data?,
            addedAt: Date,
            taskID: UUID
        ) {
            self.id = id
            self.kindRaw = kindRaw
            self.value = value
            self.displayName = displayName
            self.bookmark = bookmark
            self.addedAt = addedAt
            self.taskID = taskID
        }

        init(item: FocusSchemaV3.ContextItem) {
            id = item.id
            kindRaw = item.kindRaw
            value = item.value
            displayName = item.displayName
            bookmark = item.bookmark
            addedAt = item.addedAt
            taskID = item.task?.id ?? UUID()
        }
    }

    private struct RuleSnapshot: Sendable, Equatable, Hashable {
        let id: UUID
        let scopeRaw: String
        let subject: String
        let verdictRaw: String
        let createdAt: Date
        let taskID: UUID?

        init(
            id: UUID,
            scopeRaw: String,
            subject: String,
            verdictRaw: String,
            createdAt: Date,
            taskID: UUID?
        ) {
            self.id = id
            self.scopeRaw = scopeRaw
            self.subject = subject
            self.verdictRaw = verdictRaw
            self.createdAt = createdAt
            self.taskID = taskID
        }

        init(rule: FocusSchemaV3.RelevanceRule) {
            id = rule.id
            scopeRaw = rule.scopeRaw
            subject = rule.subject
            verdictRaw = rule.verdictRaw
            createdAt = rule.createdAt
            taskID = rule.task?.id
        }
    }

    private struct TaskSnapshot: Sendable, Equatable, Hashable {
        let id: UUID
        let intent: String
        let doneWhen: String?
        let createdAt: Date
        let completedAt: Date?
        let revision: Int
        let timeboxSeconds: Int?
        let startedAt: Date?
        let shipped: String?
        let restartPoint: String?
        let lastActivatedAt: Date?
        let contextItems: [ContextItemSnapshot]
        let rules: [RuleSnapshot]
        let wasActive: Bool
        let activatedAt: Date?

        init(task: FocusSchemaV3.PriorityTask, wasActive: Bool) {
            id = task.id
            intent = task.intent
            doneWhen = task.doneWhen
            createdAt = task.createdAt
            completedAt = task.completedAt
            revision = task.revision
            timeboxSeconds = task.timeboxSeconds
            startedAt = task.startedAt
            shipped = task.shipped
            restartPoint = task.restartPoint
            lastActivatedAt = task.lastActivatedAt
            contextItems = task.contextItems.map(ContextItemSnapshot.init(item:))
            rules = task.rules.map(RuleSnapshot.init(rule:))
            self.wasActive = wasActive
            activatedAt = task.activePointer?.activatedAt
        }
    }

    private func insert(_ snapshot: ContextItemSnapshot) throws {
        let item = FocusSchemaV3.ContextItem(
            id: snapshot.id,
            kindRaw: snapshot.kindRaw,
            value: snapshot.value,
            displayName: snapshot.displayName,
            bookmark: snapshot.bookmark,
            addedAt: snapshot.addedAt,
            task: try task(id: snapshot.taskID)
        )
        context.insert(item)
    }

    private func insert(_ snapshot: RuleSnapshot) throws {
        let rule = FocusSchemaV3.RelevanceRule(
            id: snapshot.id,
            scopeRaw: snapshot.scopeRaw,
            subject: snapshot.subject,
            verdictRaw: snapshot.verdictRaw,
            createdAt: snapshot.createdAt,
            task: try snapshot.taskID.flatMap { try task(id: $0) }
        )
        context.insert(rule)
    }

    private func sessionRules() throws -> [FocusSchemaV3.RelevanceRule] {
        let scope = Self.sessionRuleScopeRaw
        let descriptor = FetchDescriptor<FocusSchemaV3.RelevanceRule>(
            predicate: #Predicate { $0.scopeRaw == scope }
        )
        return try context.fetch(descriptor)
    }

    private func normalised(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
