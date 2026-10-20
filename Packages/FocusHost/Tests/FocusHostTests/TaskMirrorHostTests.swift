import FocusCore
import Foundation
import Testing
@testable import FocusHost

/// **The app's side of the task mirror** (task mirror), over a directory the test owns and a
/// bridge that is a recording. Pure: no window, no process, no network.
@Suite("Task mirror host", .serialized)
@MainActor
struct TaskMirrorHostTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Stands in for `focus-bridge tasks sync`: drains the outbox the way the bridge would,
    /// marking completions done in the source file, and counts its calls.
    final class FakeBridge: TaskBridgeRunning, @unchecked Sendable {
        private let lock = NSLock()
        private var _calls = 0
        var problem: String?
        var calls: Int { lock.withLock { _calls } }

        func sync(directory: URL) async -> String? {
            lock.withLock { _calls += 1 }
            let files = TaskMirrorFiles(directory: directory)
            for action in files.loadOutbox() {
                if action.kind == .complete, let id = action.taskID,
                   var file = files.loadSourceFile(action.source) {
                    file.tasks = file.tasks.map { task in
                        var task = task
                        if task.id == id { task.state = .done }
                        return task
                    }
                    try? files.writeSourceFile(file)
                }
                try? files.removeAction(action)
            }
            return problem
        }
    }

    private static func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "focus-task-mirror-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func seedRemote(_ directory: URL) throws {
        let files = TaskMirrorFiles(directory: directory)
        try files.saveConfig(TaskMirrorConfig(sources: [
            TaskSourceConfig(name: "work-os", provider: "github-issues", settings: ["repository": "o/r"]),
        ]))
        try files.writeSourceFile(TaskSourceFile(
            source: "work-os", provider: "github-issues", syncedAt: now,
            tasks: [MirroredTask(id: "42", title: "Ship it", reference: "work-os#42", tags: ["focus"])]
        ))
    }

    private static func settle(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("the board is read at construction, and the model's actions are the host")
    func readsTheBoard() throws {
        let directory = try Self.directory()
        try Self.seedRemote(directory)
        let host = TaskMirrorHost(directory: directory, runner: FakeBridge(), now: { Self.now })
        #expect(host.model.board.items.map(\.task.title) == ["Ship it"])
        #expect(host.model.actions === host)
    }

    @Test("a local task is added, pinned and completed with no sync")
    func localNeedsNoBridge() async throws {
        let bridge = FakeBridge()
        let host = TaskMirrorHost(directory: try Self.directory(), runner: bridge, now: { Self.now })
        let priority = UUID()
        host.create(title: "  Write the notes  ", source: nil, tags: [], pinTo: priority)
        let pinned = host.model.board.pinned(to: priority)
        #expect(pinned.map(\.task.title) == ["Write the notes"])
        host.setDone(try #require(pinned.first).key, done: true)
        #expect(host.model.board.pinned(to: priority).first?.isDone == true)
        #expect(bridge.calls == 0)
    }

    @Test("completing a remote task shows pending at once, then the bridge drains it")
    func remoteCompletionGoesThroughTheOutbox() async throws {
        let directory = try Self.directory()
        try Self.seedRemote(directory)
        let bridge = FakeBridge()
        let host = TaskMirrorHost(directory: directory, runner: bridge, now: { Self.now })
        let key = TaskKey(source: "work-os", id: "42")

        host.setDone(key, done: true)
        let item = host.model.board.items.first { $0.key == key }
        #expect(item?.pending == .complete)
        #expect(item?.isDone == true)

        await Self.settle { !host.model.isSyncing && bridge.calls > 0 }
        #expect(bridge.calls == 1)
        let after = host.model.board.items.first { $0.key == key }
        #expect(after?.pending == nil)
        #expect(after?.isDone == true)
        #expect(host.model.syncProblem == nil)
    }

    @Test("a bridge that cannot run is reported, not hidden")
    func syncProblemIsShown() async throws {
        let directory = try Self.directory()
        try Self.seedRemote(directory)
        let bridge = FakeBridge()
        bridge.problem = "focus-bridge is not installed"
        let host = TaskMirrorHost(directory: directory, runner: bridge, now: { Self.now })
        host.syncNow()
        await Self.settle { !host.model.isSyncing && bridge.calls > 0 }
        #expect(host.model.syncProblem == "focus-bridge is not installed")
    }

    @Test("with no remote source and an empty outbox, the bridge is never run")
    func nothingRemoteRunsNothing() async throws {
        let bridge = FakeBridge()
        let host = TaskMirrorHost(directory: try Self.directory(), runner: bridge, now: { Self.now })
        host.syncNow()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(bridge.calls == 0)
        #expect(!host.model.isSyncing)
    }

    @Test("removing a source removes its mirrored tasks")
    func removingASourceForgetsItsTasks() async throws {
        let directory = try Self.directory()
        try Self.seedRemote(directory)
        let host = TaskMirrorHost(directory: directory, runner: FakeBridge(), now: { Self.now })
        host.saveConfig(TaskMirrorConfig())
        #expect(host.model.board.items.isEmpty)
        #expect(TaskMirrorFiles(directory: directory).loadSourceFile("work-os") == nil)
    }

    @Test("the judge's titles are the open ones, pinned first")
    func openTitlesForTheJudge() throws {
        let directory = try Self.directory()
        try Self.seedRemote(directory)
        let host = TaskMirrorHost(directory: directory, runner: FakeBridge(), now: { Self.now })
        let priority = UUID()
        host.create(title: "Pinned one", source: TaskMirror.localSource, tags: [], pinTo: priority)
        host.create(title: "Done one", source: TaskMirror.localSource, tags: [], pinTo: nil)
        let done = try #require(host.model.board.items.first { $0.task.title == "Done one" })
        host.setDone(done.key, done: true)
        let titles = host.openTitles(priority: priority)
        #expect(titles.first == "Pinned one")
        #expect(titles.contains("Ship it"))
        #expect(!titles.contains("Done one"))
    }
}
