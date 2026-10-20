import Foundation

/// **Whether a mirrored task is still to do** (task mirror).
public enum MirroredTaskState: String, Sendable, Codable, CaseIterable, Hashable {
    case open
    case done
}

/// **One task, as its source holds it** (task mirror).
///
/// A mirror, not a record: the source (a GitHub repository's issues, a Projects board, the
/// app's own local list) owns the task, and this is the last copy `focus-bridge` fetched. `id`
/// is the source's own identifier — an issue number, a project item's node id, a local UUID —
/// and is unique only within its source; `TaskKey` makes it unique across them.
public struct MirroredTask: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: String
    public var title: String
    /// Where the task lives, to open it in the system it came from. `nil` for a local task.
    public var url: URL?
    /// A short handle for the task in its system, such as `work-os#42`.
    public var reference: String?
    /// The source's labels, as written there. The app filters on these.
    public var tags: [String]
    public var state: MirroredTaskState
    public var updatedAt: Date?
    public var completedAt: Date?

    public init(
        id: String,
        title: String,
        url: URL? = nil,
        reference: String? = nil,
        tags: [String] = [],
        state: MirroredTaskState = .open,
        updatedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.reference = reference
        self.tags = tags
        self.state = state
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }
}

/// **A task's identity across every source**: `<source>/<id>`.
public struct TaskKey: Sendable, Codable, Hashable, Comparable, CustomStringConvertible {
    public var source: String
    public var id: String

    public init(source: String, id: String) {
        self.source = source
        self.id = id
    }

    /// Parses `<source>/<id>`. The id may itself contain `/`; the source may not.
    public init?(_ text: String) {
        guard let slash = text.firstIndex(of: "/") else { return nil }
        let source = String(text[..<slash])
        let id = String(text[text.index(after: slash)...])
        guard TaskMirror.isValidSourceName(source), !id.isEmpty else { return nil }
        self.init(source: source, id: id)
    }

    public var description: String { "\(source)/\(id)" }

    public static func < (lhs: TaskKey, rhs: TaskKey) -> Bool { lhs.description < rhs.description }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let key = TaskKey(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a task key: \(text)"))
        }
        self = key
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// **The providers this build's bridge knows**, by the name a source's config gives.
///
/// A string in the config rather than an enum there, so a newer bridge can add a provider
/// without an older app refusing the file; this list is what the Settings pane offers.
public enum TaskProviderKind: String, Sendable, Codable, CaseIterable, Hashable {
    /// A GitHub repository's issues. Settings: `repository` (`owner/name`), optional `account`.
    case githubIssues = "github-issues"
    /// A GitHub Projects (v2) board. Settings: `owner`, `number`, optional `account`, optional
    /// `doneStatus` (defaults to "Done").
    case githubProject = "github-project"
}

/// **One configured source** (task mirror): which provider, where, and which of its labels the
/// person wants mirrored.
public struct TaskSourceConfig: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var name: String
    public var provider: String
    public var settings: [String: String]
    /// Labels to mirror: a task is kept if it carries any of them. Empty keeps every task.
    public var tags: [String]
    public var enabled: Bool

    public var id: String { name }

    public init(name: String, provider: String, settings: [String: String] = [:], tags: [String] = [], enabled: Bool = true) {
        self.name = name
        self.provider = provider
        self.settings = settings
        self.tags = tags
        self.enabled = enabled
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        provider = try container.decode(String.self, forKey: .provider)
        settings = try container.decodeIfPresent([String: String].self, forKey: .settings) ?? [:]
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    public var providerKind: TaskProviderKind? { TaskProviderKind(rawValue: provider) }
}

/// `TaskMirror/config.json`: the sources, written by Settings or `focus-bridge tasks add-source`.
public struct TaskMirrorConfig: Sendable, Codable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var sources: [TaskSourceConfig]
    /// How often the app asks the bridge to sync, in seconds.
    public var pollSeconds: Int
    /// Where a new task goes when none is named: a configured source, or `nil` for the local list.
    public var createSource: String?

    public init(sources: [TaskSourceConfig] = [], pollSeconds: Int = TaskMirror.defaultPollSeconds, createSource: String? = nil) {
        self.version = Self.currentVersion
        self.sources = sources
        self.pollSeconds = pollSeconds
        self.createSource = createSource
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        sources = try container.decodeIfPresent([TaskSourceConfig].self, forKey: .sources) ?? []
        pollSeconds = try container.decodeIfPresent(Int.self, forKey: .pollSeconds) ?? TaskMirror.defaultPollSeconds
        createSource = try container.decodeIfPresent(String.self, forKey: .createSource)
    }

    public func source(named name: String) -> TaskSourceConfig? { sources.first { $0.name == name } }

    /// The source a new task goes to when none is named: `createSource` while it is configured and
    /// enabled, otherwise the local list.
    public var defaultCreateSource: String {
        guard let name = createSource, source(named: name)?.enabled == true else { return TaskMirror.localSource }
        return name
    }

    /// Removes the source called `name`, and stops sending new tasks to it.
    public mutating func remove(named name: String) {
        sources.removeAll { $0.name == name }
        if createSource == name { createSource = nil }
    }

    /// Adds `source`, replacing one of the same name.
    public mutating func upsert(_ source: TaskSourceConfig) {
        if let index = sources.firstIndex(where: { $0.name == source.name }) {
            sources[index] = source
        } else {
            sources.append(source)
        }
    }
}

/// `TaskMirror/sources/<source>.json` (and `local.json`): one source's tasks, replaced whole.
public struct TaskSourceFile: Sendable, Codable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var source: String
    public var provider: String
    public var syncedAt: Date
    /// Why the last sync failed, in the bridge's words, or `nil`. The tasks are the last good set.
    public var lastError: String?
    public var tasks: [MirroredTask]

    public init(source: String, provider: String, syncedAt: Date, lastError: String? = nil, tasks: [MirroredTask]) {
        self.version = Self.currentVersion
        self.source = source
        self.provider = provider
        self.syncedAt = syncedAt
        self.lastError = lastError
        self.tasks = tasks
    }
}

/// `TaskMirror/pins.json`: which tasks are subtasks of which priority.
public struct TaskPins: Sendable, Codable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var pins: [TaskKey: UUID]

    public init(pins: [TaskKey: UUID] = [:]) {
        self.version = Self.currentVersion
        self.pins = pins
    }

    enum CodingKeys: String, CodingKey { case version, pins }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        let raw = try container.decodeIfPresent([String: UUID].self, forKey: .pins) ?? [:]
        var pins: [TaskKey: UUID] = [:]
        for (text, priority) in raw {
            if let key = TaskKey(text) { pins[key] = priority }
        }
        self.pins = pins
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        var raw: [String: UUID] = [:]
        for (key, priority) in pins { raw[key.description] = priority }
        try container.encode(raw, forKey: .pins)
    }
}

/// **Something done to a task that its source has not yet been told** (task mirror).
///
/// Written to `TaskMirror/outbox/` by whoever acted — the app or the bridge's MCP tools — and
/// drained by the bridge's sync, which tells the source and then re-fetches. Until then the
/// board shows the change as pending, so a click is answered at once whatever the network does.
public struct TaskAction: Sendable, Codable, Equatable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Codable, CaseIterable, Hashable {
        case complete
        case reopen
        case create
    }

    public var id: UUID
    public var kind: Kind
    public var source: String
    /// The task acted on; `nil` for `create`.
    public var taskID: String?
    /// The new task's title, for `create`.
    public var title: String?
    /// The new task's labels, for `create`.
    public var tags: [String]?
    /// For `create`: the priority the new task should be pinned to once the source names it.
    public var pinTo: UUID?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: Kind,
        source: String,
        taskID: String? = nil,
        title: String? = nil,
        tags: [String]? = nil,
        pinTo: UUID? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.taskID = taskID
        self.title = title
        self.tags = tags
        self.pinTo = pinTo
        self.createdAt = createdAt
    }

    public var taskKey: TaskKey? { taskID.map { TaskKey(source: source, id: $0) } }

    /// The key a pending `create` is shown under until the source names the task.
    public var pendingKey: TaskKey { TaskKey(source: source, id: "pending-\(id.uuidString.lowercased())") }
}

/// Why a source, a task or an action was refused.
public enum TaskMirrorError: Error, Equatable, CustomStringConvertible {
    case invalidSource(String)
    case reservedSource(String)
    case unknownProvider(String)
    case missingSetting(provider: String, setting: String)
    case emptyTitle
    case textTooLong(field: String, maximum: Int)
    case tooManyTasks(maximum: Int)

    public var description: String {
        switch self {
        case .invalidSource(let source):
            "source \"\(source)\" must be 1–\(TaskMirror.maximumSourceLength) characters of a–z, 0–9, '.', '_' or '-'"
        case .reservedSource(let source):
            "source \"\(source)\" is reserved"
        case .unknownProvider(let provider):
            "unknown provider \"\(provider)\"; known: \(TaskProviderKind.allCases.map(\.rawValue).joined(separator: ", "))"
        case .missingSetting(let provider, let setting):
            "provider \(provider) needs the setting \"\(setting)\""
        case .emptyTitle:
            "a task needs a title"
        case .textTooLong(let field, let maximum):
            "\(field) may be at most \(maximum) characters"
        case .tooManyTasks(let maximum):
            "a source may hold at most \(maximum) tasks"
        }
    }
}

/// **The contract between `focus-bridge` and the app for mirrored tasks**: where the files live,
/// what a valid one holds, and how the app turns them into one board.
///
/// The layout, under `TaskMirror/` beside the store:
///
/// * `config.json` — the sources (`TaskMirrorConfig`).
/// * `sources/<source>.json` — each source's tasks, written only by the bridge's sync.
/// * `local.json` — tasks that live only here, under the reserved source `local`.
/// * `pins.json` — which tasks are subtasks of which priority.
/// * `outbox/<id>.json` — actions waiting for the bridge to tell the source.
///
/// Files, not the store, for the reason time blocks are: the bridge writes them unattended, and
/// a mirror has no business in a schema version. Every writer replaces a file whole (write to a
/// temporary file, then rename), so a reader never sees half of one.
public enum TaskMirror {
    public static let directoryName = "TaskMirror"
    public static let localSource = "local"
    public static let maximumSourceLength = 64
    public static let maximumTasksPerSource = 1_000
    public static let maximumTitleLength = 300
    public static let maximumTagLength = 100
    public static let defaultPollSeconds = 90

    public static func directory(besideStore store: URL) -> URL {
        store.deletingLastPathComponent().appending(path: directoryName, directoryHint: .isDirectory)
    }

    public static func configURL(in directory: URL) -> URL {
        directory.appending(path: "config.json", directoryHint: .notDirectory)
    }

    public static func sourcesDirectory(in directory: URL) -> URL {
        directory.appending(path: "sources", directoryHint: .isDirectory)
    }

    public static func sourceFileURL(for source: String, in directory: URL) -> URL {
        if source == localSource { return localURL(in: directory) }
        return sourcesDirectory(in: directory).appending(path: "\(source).json", directoryHint: .notDirectory)
    }

    public static func localURL(in directory: URL) -> URL {
        directory.appending(path: "local.json", directoryHint: .notDirectory)
    }

    public static func pinsURL(in directory: URL) -> URL {
        directory.appending(path: "pins.json", directoryHint: .notDirectory)
    }

    public static func outboxDirectory(in directory: URL) -> URL {
        directory.appending(path: "outbox", directoryHint: .isDirectory)
    }

    public static func outboxURL(for action: TaskAction, in directory: URL) -> URL {
        outboxDirectory(in: directory).appending(path: "\(action.id.uuidString.lowercased()).json", directoryHint: .notDirectory)
    }

    /// A source names a file, so it is held to a filename-safe alphabet.
    public static func isValidSourceName(_ source: String) -> Bool {
        !source.isEmpty
            && source.count <= maximumSourceLength
            && !source.hasPrefix(".")
            && source.unicodeScalars.allSatisfy { scalar in
                ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar)
                    || scalar == "." || scalar == "_" || scalar == "-"
            }
    }

    /// A name for a source the person configures: valid, and not the reserved local list.
    public static func validate(sourceName: String) throws {
        guard isValidSourceName(sourceName) else { throw TaskMirrorError.invalidSource(sourceName) }
        guard sourceName != localSource else { throw TaskMirrorError.reservedSource(sourceName) }
    }

    /// The settings each known provider cannot work without.
    public static func requiredSettings(for provider: TaskProviderKind) -> [String] {
        switch provider {
        case .githubIssues: ["repository"]
        case .githubProject: ["owner", "number"]
        }
    }

    public static func validate(_ config: TaskSourceConfig) throws {
        try validate(sourceName: config.name)
        guard let kind = config.providerKind else { throw TaskMirrorError.unknownProvider(config.provider) }
        for setting in requiredSettings(for: kind) where (config.settings[setting] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            throw TaskMirrorError.missingSetting(provider: config.provider, setting: setting)
        }
        for tag in config.tags where tag.count > maximumTagLength {
            throw TaskMirrorError.textTooLong(field: "tag", maximum: maximumTagLength)
        }
    }

    /// A title as a task may carry it: trimmed, one line, not empty, not too long.
    public static func normalisedTitle(_ title: String) throws -> String {
        let flattened = title.components(separatedBy: .newlines).joined(separator: " ")
        let trimmed = flattened.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw TaskMirrorError.emptyTitle }
        guard trimmed.count <= maximumTitleLength else {
            throw TaskMirrorError.textTooLong(field: "title", maximum: maximumTitleLength)
        }
        return trimmed
    }

    /// Splits `a, b ,c` into labels.
    public static func parseTags(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Whether `tags` passes a filter: an empty filter passes everything, otherwise any match,
    /// compared without regard to case.
    public static func matches(tags: [String], filter: [String]) -> Bool {
        guard !filter.isEmpty else { return true }
        let wanted = Set(filter.map { $0.lowercased() })
        return tags.contains { wanted.contains($0.lowercased()) }
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        ExternalTimeBlocks.decoder()
    }
}

/// **One task on the board**: the mirror's copy, with what the app knows on top of it.
public struct TaskBoardItem: Sendable, Equatable, Hashable, Identifiable {
    public var key: TaskKey
    public var task: MirroredTask
    /// The priority this task is a subtask of, or `nil` for the inbox.
    public var pinnedTo: UUID?
    /// An action waiting in the outbox, which `task.state` already reflects.
    public var pending: TaskAction.Kind?

    public var id: TaskKey { key }
    public var isDone: Bool { task.state == .done }

    public init(key: TaskKey, task: MirroredTask, pinnedTo: UUID? = nil, pending: TaskAction.Kind? = nil) {
        self.key = key
        self.task = task
        self.pinnedTo = pinnedTo
        self.pending = pending
    }
}

/// **How one source stands**, for the Settings pane and the board's footer.
public struct TaskSourceStatus: Sendable, Equatable, Hashable, Identifiable {
    public var name: String
    public var provider: String
    public var syncedAt: Date?
    public var lastError: String?
    public var taskCount: Int

    public var id: String { name }

    public init(name: String, provider: String, syncedAt: Date?, lastError: String?, taskCount: Int) {
        self.name = name
        self.provider = provider
        self.syncedAt = syncedAt
        self.lastError = lastError
        self.taskCount = taskCount
    }
}

/// **Every mirrored task, composed from the files** (task mirror).
public struct TaskBoard: Sendable, Equatable {
    public var items: [TaskBoardItem]
    public var sources: [TaskSourceStatus]

    public static let empty = TaskBoard(items: [], sources: [])

    public init(items: [TaskBoardItem], sources: [TaskSourceStatus]) {
        self.items = items
        self.sources = sources
    }

    /// **Composes the board.** Pending actions are applied over the mirror so a completed task
    /// reads as done before the source has heard, and a created one appears at once. Tasks
    /// from a disabled or unconfigured source are left out (the local list is always in), as are
    /// tasks the source's label filter does not match. Open tasks first, each group by source
    /// then title.
    public static func compose(
        config: TaskMirrorConfig,
        files: [TaskSourceFile],
        pins: TaskPins,
        outbox: [TaskAction]
    ) -> TaskBoard {
        let enabled = Set(config.sources.filter(\.enabled).map(\.name)).union([TaskMirror.localSource])
        var items: [TaskKey: TaskBoardItem] = [:]
        var statuses: [String: TaskSourceStatus] = [:]

        for file in files where enabled.contains(file.source) {
            let filter = config.source(named: file.source)?.tags ?? []
            var count = 0
            for task in file.tasks.prefix(TaskMirror.maximumTasksPerSource) where TaskMirror.matches(tags: task.tags, filter: filter) {
                let key = TaskKey(source: file.source, id: task.id)
                items[key] = TaskBoardItem(key: key, task: task, pinnedTo: pins.pins[key])
                count += 1
            }
            if file.source != TaskMirror.localSource {
                statuses[file.source] = TaskSourceStatus(
                    name: file.source, provider: file.provider, syncedAt: file.syncedAt, lastError: file.lastError, taskCount: count
                )
            }
        }

        for action in outbox.sorted(by: { $0.createdAt < $1.createdAt }) where enabled.contains(action.source) {
            switch action.kind {
            case .complete, .reopen:
                guard let key = action.taskKey, var item = items[key] else { continue }
                item.task.state = action.kind == .complete ? .done : .open
                item.task.completedAt = action.kind == .complete ? action.createdAt : nil
                item.pending = action.kind
                items[key] = item
            case .create:
                guard let title = action.title else { continue }
                let key = action.pendingKey
                let task = MirroredTask(id: key.id, title: title, tags: action.tags ?? [], updatedAt: action.createdAt)
                items[key] = TaskBoardItem(key: key, task: task, pinnedTo: action.pinTo ?? pins.pins[key], pending: .create)
            }
        }

        for source in config.sources where source.enabled && statuses[source.name] == nil {
            statuses[source.name] = TaskSourceStatus(name: source.name, provider: source.provider, syncedAt: nil, lastError: nil, taskCount: 0)
        }

        let sorted = items.values.sorted { lhs, rhs in
            if lhs.isDone != rhs.isDone { return !lhs.isDone }
            if lhs.key.source != rhs.key.source { return lhs.key.source < rhs.key.source }
            let order = lhs.task.title.localizedStandardCompare(rhs.task.title)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.key < rhs.key
        }
        let statusOrder = config.sources.map(\.name)
        let sortedStatuses = statuses.values.sorted { lhs, rhs in
            let left = statusOrder.firstIndex(of: lhs.name) ?? Int.max
            let right = statusOrder.firstIndex(of: rhs.name) ?? Int.max
            return left == right ? lhs.name < rhs.name : left < right
        }
        return TaskBoard(items: sorted, sources: sortedStatuses)
    }

    /// Every label on the board, for the filter chips: case-folded duplicates merged, sorted.
    public var allTags: [String] {
        var seen: [String: String] = [:]
        for item in items {
            for tag in item.task.tags where seen[tag.lowercased()] == nil { seen[tag.lowercased()] = tag }
        }
        return seen.values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The board narrowed to tasks with any of `tags`; done tasks only if `includeDone`.
    public func items(tagged tags: [String], includeDone: Bool) -> [TaskBoardItem] {
        items.filter { (includeDone || !$0.isDone) && TaskMirror.matches(tags: $0.task.tags, filter: tags) }
    }

    /// The subtasks of `priority`, open first.
    public func pinned(to priority: UUID) -> [TaskBoardItem] {
        items.filter { $0.pinnedTo == priority }
    }

    /// Open task titles, for the remote judge's context: the priority's subtasks first.
    public func openTitles(priority: UUID?, limit: Int = 30) -> [String] {
        let open = items.filter { !$0.isDone }
        let pinned = priority.map { id in open.filter { $0.pinnedTo == id } } ?? []
        let pinnedKeys = Set(pinned.map(\.key))
        let rest = open.filter { !pinnedKeys.contains($0.key) }
        return Array((pinned + rest).prefix(limit).map(\.task.title))
    }
}
