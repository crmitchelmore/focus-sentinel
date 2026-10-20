import Foundation

/// **Reads and writes the task mirror's files** (task mirror): one implementation shared by the
/// app and `focus-bridge`, so the two can never disagree about the layout.
///
/// Every write replaces a whole file atomically, with the directory at 0700 and the file at 0600,
/// as the time-block store does. Reads are forgiving: a missing file is an empty one, and an
/// unreadable one is skipped rather than failing the board.
public struct TaskMirrorFiles: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    // MARK: - Config

    public func loadConfig() -> TaskMirrorConfig {
        read(TaskMirrorConfig.self, at: TaskMirror.configURL(in: directory)) ?? TaskMirrorConfig()
    }

    public func saveConfig(_ config: TaskMirrorConfig) throws {
        try write(config, to: TaskMirror.configURL(in: directory))
    }

    // MARK: - Source files

    /// Every source's file, the local list included.
    public func loadSourceFiles() -> [TaskSourceFile] {
        let sources = TaskMirror.sourcesDirectory(in: directory)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: sources.path)) ?? [])
            .filter { $0.hasSuffix(".json") }
            .sorted()
        var files = names.compactMap { read(TaskSourceFile.self, at: sources.appending(path: $0, directoryHint: .notDirectory)) }
            .filter { $0.source != TaskMirror.localSource && TaskMirror.isValidSourceName($0.source) }
        if let local = read(TaskSourceFile.self, at: TaskMirror.localURL(in: directory)) {
            files.append(local)
        }
        return files
    }

    public func loadSourceFile(_ source: String) -> TaskSourceFile? {
        read(TaskSourceFile.self, at: TaskMirror.sourceFileURL(for: source, in: directory))
    }

    public func writeSourceFile(_ file: TaskSourceFile) throws {
        guard TaskMirror.isValidSourceName(file.source) else { throw TaskMirrorError.invalidSource(file.source) }
        guard file.tasks.count <= TaskMirror.maximumTasksPerSource else {
            throw TaskMirrorError.tooManyTasks(maximum: TaskMirror.maximumTasksPerSource)
        }
        try write(file, to: TaskMirror.sourceFileURL(for: file.source, in: directory))
    }

    public func removeSourceFile(_ source: String) throws {
        let url = TaskMirror.sourceFileURL(for: source, in: directory)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    // MARK: - The local list

    public func loadLocal() -> TaskSourceFile {
        loadSourceFile(TaskMirror.localSource)
            ?? TaskSourceFile(source: TaskMirror.localSource, provider: TaskMirror.localSource, syncedAt: .distantPast, tasks: [])
    }

    /// Adds a task to the local list and returns it.
    @discardableResult
    public func addLocal(title: String, tags: [String], now: Date) throws -> MirroredTask {
        let task = MirroredTask(
            id: UUID().uuidString.lowercased(),
            title: try TaskMirror.normalisedTitle(title),
            tags: tags,
            updatedAt: now
        )
        var file = loadLocal()
        file.tasks.append(task)
        file.syncedAt = now
        try writeSourceFile(file)
        return task
    }

    /// Marks a local task done or open. Returns `false` if there is no such task.
    @discardableResult
    public func setLocal(id: String, state: MirroredTaskState, now: Date) throws -> Bool {
        var file = loadLocal()
        guard let index = file.tasks.firstIndex(where: { $0.id == id }) else { return false }
        file.tasks[index].state = state
        file.tasks[index].completedAt = state == .done ? now : nil
        file.tasks[index].updatedAt = now
        file.syncedAt = now
        try writeSourceFile(file)
        return true
    }

    /// Removes local tasks finished before `cutoff`, so the list does not grow without end.
    public func pruneLocal(doneBefore cutoff: Date) throws {
        var file = loadLocal()
        let kept = file.tasks.filter { $0.state == .open || ($0.completedAt ?? .distantFuture) >= cutoff }
        guard kept.count != file.tasks.count else { return }
        file.tasks = kept
        try writeSourceFile(file)
    }

    // MARK: - Pins

    public func loadPins() -> TaskPins {
        read(TaskPins.self, at: TaskMirror.pinsURL(in: directory)) ?? TaskPins()
    }

    public func savePins(_ pins: TaskPins) throws {
        try write(pins, to: TaskMirror.pinsURL(in: directory))
    }

    /// Pins `key` to `priority`, or unpins it when `priority` is `nil`.
    public func pin(_ key: TaskKey, to priority: UUID?) throws {
        var pins = loadPins()
        pins.pins[key] = priority
        try savePins(pins)
    }

    // MARK: - Outbox

    public func loadOutbox() -> [TaskAction] {
        let outbox = TaskMirror.outboxDirectory(in: directory)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: outbox.path)) ?? [])
            .filter { $0.hasSuffix(".json") }
        return names.compactMap { read(TaskAction.self, at: outbox.appending(path: $0, directoryHint: .notDirectory)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func enqueue(_ action: TaskAction) throws {
        guard TaskMirror.isValidSourceName(action.source) else { throw TaskMirrorError.invalidSource(action.source) }
        try write(action, to: TaskMirror.outboxURL(for: action, in: directory))
    }

    public func removeAction(_ action: TaskAction) throws {
        let url = TaskMirror.outboxURL(for: action, in: directory)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    // MARK: - The board

    public func board() -> TaskBoard {
        TaskBoard.compose(config: loadConfig(), files: loadSourceFiles(), pins: loadPins(), outbox: loadOutbox())
    }

    /// **What changed since the last read**, cheaply: the name, size and modification date of
    /// every file under the directory. A reader re-composes the board only when this moves.
    public func signature() -> [String] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        let locations = [directory, TaskMirror.sourcesDirectory(in: directory), TaskMirror.outboxDirectory(in: directory)]
        return locations.flatMap { location -> [String] in
            let files = (try? FileManager.default.contentsOfDirectory(
                at: location,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )) ?? []
            return files.filter { $0.pathExtension == "json" }.map { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                let modified = values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
                return "\(location.lastPathComponent)/\(url.lastPathComponent)|\(values?.fileSize ?? -1)|\(modified)"
            }
        }
        .sorted()
    }

    /// Removes everything the mirror holds: *Delete Everything*.
    public func removeAll() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: - Files

    private func read<Value: Decodable>(_ type: Value.Type, at url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? TaskMirror.decoder().decode(type, from: data)
    }

    private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        let manager = FileManager.default
        let parent = url.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try TaskMirror.encoder().encode(value).write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
