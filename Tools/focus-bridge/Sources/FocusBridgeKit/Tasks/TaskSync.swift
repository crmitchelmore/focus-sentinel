import Darwin
import FocusCore
import Foundation

/// **What one sync did**, as `focus-bridge tasks sync` prints it.
public struct TaskSyncSummary: Codable, Sendable, Equatable {
    public struct Source: Codable, Sendable, Equatable {
        public var name: String
        public var provider: String
        /// How many tasks the source file now holds (the last good set when `error` is set).
        public var tasks: Int
        public var error: String?
    }

    public enum Outcome: String, Codable, Sendable {
        /// The source has been told; the action is gone from the outbox.
        case applied
        /// It failed and stays in the outbox for the next sync.
        case kept
        /// It failed for good (the task is gone, the source refused it, or a week passed) and was removed.
        case dropped
        /// Not attempted this time (another source's action, or a disabled source).
        case skipped
    }

    public struct Action: Codable, Sendable, Equatable {
        public var id: UUID
        public var kind: TaskAction.Kind
        public var source: String
        /// The task acted on, or for a create the key the source gave the new task.
        public var key: TaskKey?
        public var outcome: Outcome
        public var error: String?
    }

    /// Another sync held the lock, so this one did nothing.
    public var alreadyRunning: Bool
    public var syncedAt: Date
    public var sources: [Source]
    public var actions: [Action]

    /// Whether every source fetched and no action failed.
    public var ok: Bool {
        !alreadyRunning && sources.allSatisfy { $0.error == nil } && actions.allSatisfy { $0.outcome == .applied || $0.outcome == .skipped }
    }

    enum CodingKeys: String, CodingKey { case alreadyRunning, syncedAt, sources, actions, ok }

    public init(alreadyRunning: Bool, syncedAt: Date, sources: [Source], actions: [Action]) {
        self.alreadyRunning = alreadyRunning
        self.syncedAt = syncedAt
        self.sources = sources
        self.actions = actions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        alreadyRunning = try container.decode(Bool.self, forKey: .alreadyRunning)
        syncedAt = try container.decode(Date.self, forKey: .syncedAt)
        sources = try container.decode([Source].self, forKey: .sources)
        actions = try container.decode([Action].self, forKey: .actions)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(alreadyRunning, forKey: .alreadyRunning)
        try container.encode(syncedAt, forKey: .syncedAt)
        try container.encode(sources, forKey: .sources)
        try container.encode(actions, forKey: .actions)
        try container.encode(ok, forKey: .ok)
    }
}

/// **One pass of the task mirror** (task mirror): tell each source what was done here, then
/// fetch what each source holds.
///
/// 1. Take `TaskMirror/.sync.lock` without waiting (or waiting up to `lockWait`); if another
///    sync holds it, return at once with `alreadyRunning`.
/// 2. Drain the outbox, oldest first. Local actions are applied to `local.json`; others go to the
///    source's provider. An action that succeeds is removed (and a created task pinned where the
///    action asked); one that fails is kept, unless the failure is permanent (HTTP 404, 410, 422)
///    or the action is more than a week old.
/// 3. Fetch every enabled source (or one), writing its file; a failed fetch keeps the last good
///    tasks and records `lastError`.
/// 4. Prune local tasks finished more than a week ago.
public struct TaskSync: Sendable {
    public static let actionLifetime: TimeInterval = 7 * 24 * 60 * 60
    public static let localDoneLifetime: TimeInterval = 7 * 24 * 60 * 60
    public static let lockName = ".sync.lock"

    public let files: TaskMirrorFiles
    public let registry: TaskProviderRegistry
    public let now: @Sendable () -> Date

    public init(files: TaskMirrorFiles, registry: TaskProviderRegistry, now: @escaping @Sendable () -> Date = Date.init) {
        self.files = files
        self.registry = registry
        self.now = now
    }

    /// Runs one sync. `source` limits the fetch, and the outbox drain, to that source (local
    /// actions are always applied). `lockWait` is how long to wait for another sync to finish.
    public func run(source only: String? = nil, lockWait: TimeInterval = 0) async throws -> TaskSyncSummary {
        guard let lock = try await acquireLock(waiting: lockWait) else {
            return TaskSyncSummary(alreadyRunning: true, syncedAt: now(), sources: [], actions: [])
        }
        defer { lock.release() }

        let config = files.loadConfig()
        var actions: [TaskSyncSummary.Action] = []
        for action in files.loadOutbox() {
            actions.append(await drain(action, config: config, only: only))
        }

        var sources: [TaskSyncSummary.Source] = []
        for source in config.sources where source.enabled && source.name != TaskMirror.localSource && (only == nil || source.name == only) {
            sources.append(await fetch(source))
        }

        try files.pruneLocal(doneBefore: now().addingTimeInterval(-Self.localDoneLifetime))
        return TaskSyncSummary(alreadyRunning: false, syncedAt: now(), sources: sources, actions: actions)
    }

    // MARK: - Outbox

    private func drain(_ action: TaskAction, config: TaskMirrorConfig, only: String?) async -> TaskSyncSummary.Action {
        var result = TaskSyncSummary.Action(id: action.id, kind: action.kind, source: action.source, key: action.taskKey, outcome: .skipped)
        if action.source == TaskMirror.localSource {
            do {
                result.key = try applyLocally(action)
                result.outcome = .applied
                try files.removeAction(action)
            } catch {
                result.error = TaskProviderError.describe(error)
                result.outcome = .dropped
                try? files.removeAction(action)
            }
            return result
        }
        if let only, action.source != only { return result }
        guard let source = config.source(named: action.source) else {
            result.error = "source \(action.source) is no longer configured"
            result.outcome = .dropped
            try? files.removeAction(action)
            return result
        }
        guard source.enabled else { return result }

        do {
            let provider = try registry.provider(for: source)
            switch action.kind {
            case .complete, .reopen:
                guard let id = action.taskID else { throw TaskProviderError.notFound("the action names no task") }
                if action.kind == .complete {
                    try await provider.complete(source, taskID: id)
                } else {
                    try await provider.reopen(source, taskID: id)
                }
                updateMirror(source: source) { tasks in
                    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
                    tasks[index].state = action.kind == .complete ? .done : .open
                    tasks[index].completedAt = action.kind == .complete ? action.createdAt : nil
                }
            case .create:
                let title = try TaskMirror.normalisedTitle(action.title ?? "")
                let task = try await provider.create(source, title: title, tags: action.tags ?? [])
                let key = TaskKey(source: source.name, id: task.id)
                result.key = key
                updateMirror(source: source) { tasks in
                    tasks.removeAll { $0.id == task.id }
                    tasks.append(task)
                }
                try movePin(from: action, to: key)
            }
            try files.removeAction(action)
            result.outcome = .applied
        } catch {
            result.error = TaskProviderError.describe(error)
            let expired = now().timeIntervalSince(action.createdAt) > Self.actionLifetime
            if TaskProviderError.isPermanent(error) || error is TaskMirrorError || expired {
                result.outcome = .dropped
                try? files.removeAction(action)
            } else {
                result.outcome = .kept
            }
        }
        return result
    }

    /// Applies a local action to `local.json` and returns the task's key.
    private func applyLocally(_ action: TaskAction) throws -> TaskKey {
        let at = now()
        switch action.kind {
        case .complete, .reopen:
            guard let id = action.taskID, try files.setLocal(id: id, state: action.kind == .complete ? .done : .open, now: at) else {
                throw TaskProviderError.notFound("no local task \(action.taskID ?? "")")
            }
            return TaskKey(source: TaskMirror.localSource, id: id)
        case .create:
            let task = try files.addLocal(title: action.title ?? "", tags: action.tags ?? [], now: at)
            let key = TaskKey(source: TaskMirror.localSource, id: task.id)
            try movePin(from: action, to: key)
            return key
        }
    }

    /// A created task takes the pin its action asked for, or the one placed on its pending key.
    private func movePin(from action: TaskAction, to key: TaskKey) throws {
        var pins = files.loadPins()
        let pending = pins.pins.removeValue(forKey: action.pendingKey)
        guard let priority = action.pinTo ?? pending else { return }
        pins.pins[key] = priority
        try files.savePins(pins)
    }

    /// Reflects a change the source accepted in its file at once, so the board is right even if
    /// the fetch that follows fails.
    private func updateMirror(source: TaskSourceConfig, _ change: (inout [MirroredTask]) -> Void) {
        guard var file = files.loadSourceFile(source.name) else {
            var tasks: [MirroredTask] = []
            change(&tasks)
            try? files.writeSourceFile(TaskSourceFile(source: source.name, provider: source.provider, syncedAt: now(), tasks: tasks))
            return
        }
        change(&file.tasks)
        try? files.writeSourceFile(file)
    }

    // MARK: - Fetch

    private func fetch(_ source: TaskSourceConfig) async -> TaskSyncSummary.Source {
        do {
            let provider = try registry.provider(for: source)
            let tasks = Self.bounded(try await provider.fetch(source), filter: source.tags)
            try files.writeSourceFile(TaskSourceFile(source: source.name, provider: source.provider, syncedAt: now(), tasks: tasks))
            return .init(name: source.name, provider: source.provider, tasks: tasks.count, error: nil)
        } catch {
            let message = TaskProviderError.describe(error)
            let old = files.loadSourceFile(source.name)
            let tasks = old?.tasks ?? []
            try? files.writeSourceFile(TaskSourceFile(
                source: source.name, provider: source.provider, syncedAt: old?.syncedAt ?? now(), lastError: message, tasks: tasks
            ))
            return .init(name: source.name, provider: source.provider, tasks: tasks.count, error: message)
        }
    }

    /// At most `maximumTasksPerSource`: if a source holds more, those its label filter matches
    /// first, open before done.
    static func bounded(_ tasks: [MirroredTask], filter: [String]) -> [MirroredTask] {
        let limit = TaskMirror.maximumTasksPerSource
        guard tasks.count > limit else { return tasks }
        let ranked = tasks.enumerated().sorted { lhs, rhs in
            let left = (TaskMirror.matches(tags: lhs.element.tags, filter: filter) ? 0 : 2) + (lhs.element.state == .open ? 0 : 1)
            let right = (TaskMirror.matches(tags: rhs.element.tags, filter: filter) ? 0 : 2) + (rhs.element.state == .open ? 0 : 1)
            return left == right ? lhs.offset < rhs.offset : left < right
        }
        return Array(ranked.prefix(limit).map(\.element))
    }

    // MARK: - Lock

    final class Lock: Sendable {
        let descriptor: Int32
        init(_ descriptor: Int32) { self.descriptor = descriptor }
        func release() {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
    }

    private func acquireLock(waiting: TimeInterval) async throws -> Lock? {
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = files.directory.appending(path: Self.lockName, directoryHint: .notDirectory).path
        let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw BridgeError("could not open \(path): \(String(cString: strerror(errno)))")
        }
        let deadline = Date().addingTimeInterval(waiting)
        while true {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return Lock(descriptor) }
            guard errno == EWOULDBLOCK, Date() < deadline else { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        close(descriptor)
        return nil
    }
}
