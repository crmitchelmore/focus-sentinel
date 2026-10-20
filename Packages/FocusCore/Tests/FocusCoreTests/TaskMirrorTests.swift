import Foundation
import Testing
@testable import FocusCore

@Suite("Task mirror")
struct TaskMirrorTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let priority = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!

    private static func task(_ id: String, _ title: String, tags: [String] = [], state: MirroredTaskState = .open) -> MirroredTask {
        MirroredTask(id: id, title: title, tags: tags, state: state, updatedAt: now)
    }

    private static func file(_ source: String, _ tasks: [MirroredTask], error: String? = nil) -> TaskSourceFile {
        TaskSourceFile(source: source, provider: "github-issues", syncedAt: now, lastError: error, tasks: tasks)
    }

    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "task-mirror-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test("a key reads and writes as source/id, the id keeping any further slash")
    func keys() throws {
        let key = try #require(TaskKey("work-os/PVTI_abc/def"))
        #expect(key.source == "work-os")
        #expect(key.id == "PVTI_abc/def")
        #expect(key.description == "work-os/PVTI_abc/def")
        #expect(TaskKey("nosource") == nil)
        #expect(TaskKey("/id") == nil)
        #expect(TaskKey("source/") == nil)

        let data = try TaskMirror.encoder().encode([key])
        #expect(try TaskMirror.decoder().decode([TaskKey].self, from: data) == [key])
    }

    @Test("source names are filename-safe and the local list's name is reserved")
    func sourceNames() {
        #expect(TaskMirror.isValidSourceName("work-os"))
        #expect(TaskMirror.isValidSourceName("board_2"))
        #expect(!TaskMirror.isValidSourceName(""))
        #expect(!TaskMirror.isValidSourceName("../x"))
        #expect(!TaskMirror.isValidSourceName("a/b"))
        #expect(throws: TaskMirrorError.reservedSource("local")) { try TaskMirror.validate(sourceName: "local") }
    }

    @Test("a source names a known provider and carries its required settings")
    func sourceValidation() throws {
        try TaskMirror.validate(TaskSourceConfig(name: "work-os", provider: "github-issues", settings: ["repository": "o/r"]))
        try TaskMirror.validate(TaskSourceConfig(name: "board", provider: "github-project", settings: ["owner": "o", "number": "3"]))
        #expect(throws: TaskMirrorError.missingSetting(provider: "github-issues", setting: "repository")) {
            try TaskMirror.validate(TaskSourceConfig(name: "work-os", provider: "github-issues"))
        }
        #expect(throws: TaskMirrorError.unknownProvider("jira")) {
            try TaskMirror.validate(TaskSourceConfig(name: "x", provider: "jira"))
        }
    }

    @Test("titles are trimmed and refused when empty; tags are split on commas")
    func titlesAndTags() throws {
        #expect(try TaskMirror.normalisedTitle("  Ship it \n") == "Ship it")
        #expect(throws: TaskMirrorError.emptyTitle) { try TaskMirror.normalisedTitle("   ") }
        #expect(TaskMirror.parseTags(" cat:hve, ai-gathered ,, ") == ["cat:hve", "ai-gathered"])
        #expect(TaskMirror.matches(tags: ["Cat:HVE"], filter: ["cat:hve", "cat:bat"]))
        #expect(!TaskMirror.matches(tags: ["cat:travel"], filter: ["cat:hve"]))
        #expect(TaskMirror.matches(tags: [], filter: []))
    }

    @Test("a config with only sources decodes with the defaults")
    func configDefaults() throws {
        let json = #"{"sources":[{"name":"work-os","provider":"github-issues","settings":{"repository":"o/r"}}]}"#
        let config = try TaskMirror.decoder().decode(TaskMirrorConfig.self, from: Data(json.utf8))
        #expect(config.pollSeconds == TaskMirror.defaultPollSeconds)
        #expect(config.sources.first?.enabled == true)
        #expect(config.sources.first?.tags == [])
    }

    @Test("the board keeps enabled sources and the local list, filtered by the source's labels")
    func composeFilters() {
        let config = TaskMirrorConfig(sources: [
            TaskSourceConfig(name: "work-os", provider: "github-issues", settings: ["repository": "o/r"], tags: ["cat:hve"]),
            TaskSourceConfig(name: "off", provider: "github-issues", settings: ["repository": "o/s"], enabled: false),
        ])
        let board = TaskBoard.compose(
            config: config,
            files: [
                Self.file("work-os", [Self.task("1", "Kept", tags: ["cat:hve"]), Self.task("2", "Filtered", tags: ["cat:bat"])]),
                Self.file("off", [Self.task("3", "Disabled")]),
                Self.file("stray", [Self.task("4", "Unconfigured")]),
                Self.file(TaskMirror.localSource, [Self.task("5", "Local")]),
            ],
            pins: TaskPins(),
            outbox: []
        )
        #expect(board.items.map(\.task.title) == ["Local", "Kept"])
        #expect(board.sources.map(\.name) == ["work-os"])
        #expect(board.sources.first?.taskCount == 1)
    }

    @Test("open tasks come first, then by source and title")
    func composeOrder() {
        let config = TaskMirrorConfig(sources: [TaskSourceConfig(name: "a", provider: "github-issues", settings: ["repository": "o/r"])])
        let board = TaskBoard.compose(
            config: config,
            files: [Self.file("a", [Self.task("1", "Zed"), Self.task("2", "Alpha", state: .done), Self.task("3", "Beta")])],
            pins: TaskPins(),
            outbox: []
        )
        #expect(board.items.map(\.task.title) == ["Beta", "Zed", "Alpha"])
    }

    @Test("pending actions show at once: done before the source hears, created before it exists")
    func composePending() throws {
        let config = TaskMirrorConfig(sources: [TaskSourceConfig(name: "a", provider: "github-issues", settings: ["repository": "o/r"])])
        let complete = TaskAction(kind: .complete, source: "a", taskID: "1", createdAt: Self.now)
        let create = TaskAction(kind: .create, source: "a", title: "New", tags: ["x"], pinTo: Self.priority, createdAt: Self.now)
        let board = TaskBoard.compose(
            config: config,
            files: [Self.file("a", [Self.task("1", "Old")])],
            pins: TaskPins(),
            outbox: [complete, create]
        )
        let old = try #require(board.items.first { $0.key == TaskKey(source: "a", id: "1") })
        #expect(old.isDone)
        #expect(old.pending == .complete)
        let new = board.items.first { $0.key == create.pendingKey }
        #expect(new?.task.title == "New")
        #expect(new?.pending == .create)
        #expect(new?.pinnedTo == Self.priority)
    }

    @Test("pins make subtasks, and the judge's titles put the priority's own first")
    func pinsAndTitles() {
        let config = TaskMirrorConfig(sources: [TaskSourceConfig(name: "a", provider: "github-issues", settings: ["repository": "o/r"])])
        let pinned = TaskKey(source: "a", id: "2")
        let board = TaskBoard.compose(
            config: config,
            files: [Self.file("a", [Self.task("1", "Inbox"), Self.task("2", "Subtask"), Self.task("3", "Finished", state: .done)])],
            pins: TaskPins(pins: [pinned: Self.priority]),
            outbox: []
        )
        #expect(board.pinned(to: Self.priority).map(\.key) == [pinned])
        #expect(board.openTitles(priority: Self.priority) == ["Subtask", "Inbox"])
        #expect(board.openTitles(priority: nil, limit: 1) == ["Inbox"])
    }

    @Test("the chip list merges labels that differ only in case")
    func allTags() {
        let board = TaskBoard.compose(
            config: TaskMirrorConfig(),
            files: [Self.file(TaskMirror.localSource, [Self.task("1", "a", tags: ["cat:hve", "B"]), Self.task("2", "b", tags: ["CAT:HVE"])])],
            pins: TaskPins(),
            outbox: []
        )
        #expect(board.allTags.count == 2)
        #expect(board.items(tagged: ["b"], includeDone: false).map(\.task.title) == ["a"])
    }

    @Test("the files round-trip: config, local list, pins and outbox compose one board")
    func filesRoundTrip() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = TaskMirrorFiles(directory: directory)

        #expect(files.board() == .empty)
        let config = TaskMirrorConfig(sources: [TaskSourceConfig(name: "work-os", provider: "github-issues", settings: ["repository": "o/r"])])
        try files.saveConfig(config)
        #expect(files.loadConfig() == config)

        try files.writeSourceFile(Self.file("work-os", [Self.task("7", "Remote")]))
        let local = try files.addLocal(title: " Local ", tags: ["home"], now: Self.now)
        #expect(local.title == "Local")
        try files.pin(TaskKey(source: TaskMirror.localSource, id: local.id), to: Self.priority)
        let action = TaskAction(kind: .complete, source: "work-os", taskID: "7", createdAt: Self.now)
        try files.enqueue(action)

        let board = files.board()
        #expect(board.items.count == 2)
        #expect(board.pinned(to: Self.priority).map(\.task.title) == ["Local"])
        #expect(board.items.first { $0.key.source == "work-os" }?.pending == .complete)

        let attributes = try FileManager.default.attributesOfItem(atPath: TaskMirror.configURL(in: directory).path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        try files.removeAction(action)
        #expect(files.loadOutbox().isEmpty)
    }

    @Test("a local task completes and reopens; old finished ones are pruned")
    func localLifecycle() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = TaskMirrorFiles(directory: directory)
        let task = try files.addLocal(title: "Water plants", tags: [], now: Self.now)

        #expect(try files.setLocal(id: task.id, state: .done, now: Self.now))
        #expect(files.loadLocal().tasks.first?.completedAt == Self.now)
        #expect(try files.setLocal(id: task.id, state: .open, now: Self.now))
        #expect(files.loadLocal().tasks.first?.completedAt == nil)
        #expect(try files.setLocal(id: "missing", state: .done, now: Self.now) == false)

        try files.setLocal(id: task.id, state: .done, now: Self.now)
        try files.pruneLocal(doneBefore: Self.now.addingTimeInterval(1))
        #expect(files.loadLocal().tasks.isEmpty)
    }

    @Test("the signature moves when a file is written, and only then")
    func signature() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = TaskMirrorFiles(directory: directory)
        let empty = files.signature()
        #expect(empty == files.signature())
        try files.writeSourceFile(Self.file("work-os", [Self.task("1", "One")]))
        let written = files.signature()
        #expect(written != empty)
        #expect(written == files.signature())
    }

    @Test("an unreadable file is skipped, not fatal")
    func unreadableFile() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = TaskMirrorFiles(directory: directory)
        try files.writeSourceFile(Self.file("good", [Self.task("1", "One")]))
        try Data("not json".utf8).write(to: TaskMirror.sourceFileURL(for: "bad", in: directory))
        #expect(files.loadSourceFiles().map(\.source) == ["good"])
    }
}
