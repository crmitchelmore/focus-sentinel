import FocusCore
import FocusUI
import Foundation
import os

/// **Runs `focus-bridge tasks sync`** (task mirror): the one way the app reaches a task source.
///
/// The app never opens a socket for tasks. The bridge talks to GitHub with the `gh` sign-in,
/// drains the outbox and rewrites the source files; the app only reads what it wrote. Returns
/// `nil` when the sync ran (a source's own failure is in its file), else why it could not run.
public protocol TaskBridgeRunning: Sendable {
    func sync(directory: URL) async -> String?
}

public struct TaskBridgeRunner: TaskBridgeRunning {
    /// Where `Tools/focus-bridge/install.sh` and a package manager put the binary.
    static var candidates: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.local/bin/focus-bridge",
            "/opt/homebrew/bin/focus-bridge",
            "/usr/local/bin/focus-bridge",
        ]
    }

    public init() {}

    public func sync(directory: URL) async -> String? {
        guard let executable = Self.candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            return "focus-bridge is not installed (Tools/focus-bridge/install.sh)"
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["tasks", "sync"]
        var environment = ProcessInfo.processInfo.environment
        // `gh` lives in Homebrew's prefix, which a GUI app's PATH does not include.
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        environment["FOCUS_TASK_MIRROR"] = directory.path
        process.environment = environment
        let errors = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                let data = errors.fileHandleForReading.readDataToEndOfFile()
                let message = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if finished.terminationStatus == 0 {
                    continuation.resume(returning: nil)
                } else {
                    let line = message.split(separator: "\n").last.map(String.init)
                    continuation.resume(returning: line ?? "focus-bridge exited \(finished.terminationStatus)")
                }
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: error.localizedDescription)
            }
        }
    }
}

/// **The task mirror, on the app's side** (task mirror).
///
/// Owns the board the views draw and is the one `TaskMirrorActing`. A change to the local list
/// or to a pin is a file write here; a change that belongs to a remote source goes to the
/// outbox, shows as pending at once, and is drained by a bridge sync started straight after.
/// The board is re-read whenever the directory's signature moves, so a task an agent added
/// through the bridge's MCP tools appears without a sync.
@MainActor
public final class TaskMirrorHost: TaskMirrorActing {
    public let model: TaskBoardModel
    public let files: TaskMirrorFiles
    private let runner: any TaskBridgeRunning
    private let now: () -> Date
    private let logger = Logger(subsystem: FocusStore.bundleIdentifier, category: "TaskMirrorHost")

    private var signature: [String]?
    private var lastSyncStarted: Date?
    private var syncQueued = false
    private var loop: Task<Void, Never>?

    /// How often the directory is looked at for a change the bridge made on its own.
    static let watchInterval: Duration = .seconds(5)

    public init(
        directory: URL,
        runner: any TaskBridgeRunning = TaskBridgeRunner(),
        now: @escaping () -> Date = Date.init
    ) {
        self.files = TaskMirrorFiles(directory: directory)
        self.runner = runner
        self.now = now
        self.model = TaskBoardModel()
        model.actions = self
        reload(force: true)
    }

    /// Reads the board and syncs once, then watches the directory and syncs every
    /// `pollSeconds`. Never called in a lane or a self-check.
    public func start() {
        guard loop == nil else { return }
        try? files.pruneLocal(doneBefore: now().addingTimeInterval(-7 * 24 * 60 * 60))
        reload(force: true)
        syncNow()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.watchInterval)
                self?.tick()
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    func tick() {
        reload(force: false)
        let interval = TimeInterval(max(model.config.pollSeconds, 30))
        if let lastSyncStarted, now().timeIntervalSince(lastSyncStarted) < interval { return }
        syncNow()
    }

    /// Open task titles for the remote judge: the priority's subtasks first.
    public func openTitles(priority: UUID?, limit: Int = 30) -> [String] {
        model.board.openTitles(priority: priority, limit: limit)
    }

    /// Re-composes the board when anything under the directory changed.
    func reload(force: Bool) {
        let current = files.signature()
        guard force || current != signature else { return }
        signature = current
        let config = files.loadConfig()
        let board = files.board()
        if model.config != config { model.config = config }
        if model.board != board { model.board = board }
    }

    private var hasRemoteWork: Bool {
        model.config.sources.contains(where: \.enabled) || !files.loadOutbox().isEmpty
    }

    // MARK: - TaskMirrorActing

    public func setDone(_ key: TaskKey, done: Bool) {
        do {
            if key.source == TaskMirror.localSource {
                _ = try files.setLocal(id: key.id, state: done ? .done : .open, now: now())
                reload(force: true)
            } else {
                try files.enqueue(TaskAction(kind: done ? .complete : .reopen, source: key.source, taskID: key.id, createdAt: now()))
                reload(force: true)
                syncNow()
            }
        } catch {
            report("could not change a task", error)
        }
    }

    public func create(title: String, source: String?, tags: [String], pinTo priority: UUID?) {
        do {
            let title = try TaskMirror.normalisedTitle(title)
            let target = source ?? model.config.defaultCreateSource
            if target == TaskMirror.localSource {
                let task = try files.addLocal(title: title, tags: tags, now: now())
                if let priority {
                    try files.pin(TaskKey(source: TaskMirror.localSource, id: task.id), to: priority)
                }
                reload(force: true)
            } else {
                try files.enqueue(TaskAction(kind: .create, source: target, title: title, tags: tags, pinTo: priority, createdAt: now()))
                reload(force: true)
                syncNow()
            }
        } catch {
            report("could not add a task", error)
        }
    }

    public func pin(_ key: TaskKey, to priority: UUID?) {
        do {
            try files.pin(key, to: priority)
            reload(force: true)
        } catch {
            report("could not pin a task", error)
        }
    }

    public func syncNow() {
        guard hasRemoteWork else {
            model.syncProblem = nil
            return
        }
        guard !model.isSyncing else {
            syncQueued = true
            return
        }
        model.isSyncing = true
        lastSyncStarted = now()
        let directory = files.directory
        let runner = runner
        Task { [weak self] in
            let problem = await runner.sync(directory: directory)
            self?.syncFinished(problem: problem)
        }
    }

    private func syncFinished(problem: String?) {
        model.isSyncing = false
        model.lastSyncedAt = now()
        model.syncProblem = problem
        if let problem { logger.error("task sync could not run: \(problem, privacy: .public)") }
        reload(force: true)
        if syncQueued {
            syncQueued = false
            syncNow()
        }
    }

    public func saveConfig(_ config: TaskMirrorConfig) {
        let previous = Set(files.loadConfig().sources.map(\.name))
        do {
            try files.saveConfig(config)
            for removed in previous.subtracting(config.sources.map(\.name)) {
                try files.removeSourceFile(removed)
            }
            reload(force: true)
            syncNow()
        } catch {
            report("could not save the task sources", error)
        }
    }

    private func report(_ what: String, _ error: any Error) {
        logger.error("\(what, privacy: .public): \(String(describing: error), privacy: .public)")
        model.syncProblem = String(describing: error)
    }
}
