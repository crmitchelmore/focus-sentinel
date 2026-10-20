import FocusCore
import Foundation
import Observation

/// **What the task views can ask for** (task mirror). The app's `TaskMirrorHost` is the one
/// conformer: it writes the outbox, the pins and the config, and runs the bridge to sync.
@MainActor
public protocol TaskMirrorActing: AnyObject {
    /// Marks a task done (or open again), and tells its source.
    func setDone(_ key: TaskKey, done: Bool)
    /// Adds a task to `source` (the config's default when `nil`), pinned to `priority` if given.
    func create(title: String, source: String?, tags: [String], pinTo priority: UUID?)
    /// Makes a task a subtask of `priority`, or returns it to the inbox when `nil`.
    func pin(_ key: TaskKey, to priority: UUID?)
    /// Asks every source for its tasks now.
    func syncNow()
    /// Replaces the sources and settings, and syncs.
    func saveConfig(_ config: TaskMirrorConfig)
}

/// **The task board, as the views see it** (task mirror).
///
/// An `@Observable` reached through the environment rather than a field of `CockpitState`: the
/// board changes on its own clock (a sync, a file the bridge wrote), and a cockpit or Settings
/// window without one — every snapshot fixture — simply draws no tasks.
@MainActor
@Observable
public final class TaskBoardModel {
    public var board: TaskBoard
    public var config: TaskMirrorConfig
    /// A sync is running.
    public var isSyncing: Bool
    /// When the last sync finished, whatever its outcome.
    public var lastSyncedAt: Date?
    /// Why the last sync could not run at all (the bridge is missing, say); a source's own
    /// failure is on its `TaskSourceStatus` instead.
    public var syncProblem: String?
    @ObservationIgnored public weak var actions: (any TaskMirrorActing)?

    public init(
        board: TaskBoard = .empty,
        config: TaskMirrorConfig = TaskMirrorConfig(),
        isSyncing: Bool = false,
        lastSyncedAt: Date? = nil,
        syncProblem: String? = nil,
        actions: (any TaskMirrorActing)? = nil
    ) {
        self.board = board
        self.config = config
        self.isSyncing = isSyncing
        self.lastSyncedAt = lastSyncedAt
        self.syncProblem = syncProblem
        self.actions = actions
    }

    /// A short name for a task's source, for the row's link: the reference when the source gave
    /// one (`work-os#12`), else the source's name; nothing for the local list.
    public static func sourceLabel(_ item: TaskBoardItem) -> String? {
        if let reference = item.task.reference, !reference.isEmpty { return reference }
        return item.key.source == TaskMirror.localSource ? nil : item.key.source
    }
}
