import FocusCore
import Foundation

/// **The task verbs, shared by the CLI and the MCP server** (task mirror).
///
/// Not main-actor-bound, so `main.swift`'s command functions and `MCPServer` call the same code.
/// Every change goes through `TaskMirrorFiles`; a change to a task held by another system is put
/// in the outbox and a sync of that source runs at once, so it reaches the source in seconds and
/// is retried by the app's next sync if the network is not there.
public struct TaskBridge: Sendable {
    public let files: TaskMirrorFiles
    public let registry: TaskProviderRegistry
    public let now: @Sendable () -> Date
    /// How long an interactive change waits for a sync the app is already running.
    public var lockWait: TimeInterval

    public init(
        directory: URL,
        registry: TaskProviderRegistry = .standard(),
        now: @escaping @Sendable () -> Date = Date.init,
        lockWait: TimeInterval = 30
    ) {
        self.files = TaskMirrorFiles(directory: directory)
        self.registry = registry
        self.now = now
        self.lockWait = lockWait
    }

    /// `FOCUS_TASK_MIRROR` if set, else the `TaskMirror` directory beside the store the bridge
    /// reads (`FOCUS_STORE`, else the Stable app's). The app sets `FOCUS_TASK_MIRROR` when it
    /// runs the bridge.
    public static func defaultDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["FOCUS_TASK_MIRROR"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return TaskMirror.directory(besideStore: Snapshot.defaultStoreURL(environment: environment))
    }

    public var sync: TaskSync { TaskSync(files: files, registry: registry, now: now) }

    // MARK: - Reading

    public struct Item: Encodable, Sendable, Equatable {
        public var key: String
        public var source: String
        public var title: String
        public var url: URL?
        public var reference: String?
        public var tags: [String]
        public var state: MirroredTaskState
        public var pinned: Bool
        public var pinnedTo: UUID?
        public var pinnedToCurrentPriority: Bool
        /// An action waiting for the source: `complete`, `reopen` or `create`.
        public var pending: TaskAction.Kind?
        public var updatedAt: Date?
        public var completedAt: Date?
    }

    public struct SourceStatus: Encodable, Sendable, Equatable {
        public var name: String
        public var provider: String
        public var settings: [String: String]?
        public var tags: [String]?
        public var enabled: Bool?
        public var isDefaultForCreate: Bool?
        public var syncedAt: Date?
        public var lastError: String?
        public var taskCount: Int
    }

    public struct Listing: Encodable, Sendable {
        public var items: [Item]
        public var sources: [SourceStatus]
        /// Every label on the board, for filtering.
        public var tags: [String]
        public var currentPriority: UUID?
    }

    /// The board, narrowed. `pinnedOnly` keeps the current priority's subtasks, or every pinned
    /// task when no current priority is known.
    public func list(
        tags: [String] = [],
        source: String? = nil,
        includeDone: Bool = false,
        pinnedOnly: Bool = false,
        currentPriority: UUID? = nil
    ) -> Listing {
        let board = files.board()
        let items = board.items(tagged: tags, includeDone: includeDone).filter { item in
            if let source, item.key.source != source { return false }
            if pinnedOnly {
                guard let pinnedTo = item.pinnedTo else { return false }
                if let currentPriority, pinnedTo != currentPriority { return false }
            }
            return true
        }
        return Listing(
            items: items.map { item(from: $0, currentPriority: currentPriority) },
            sources: board.sources.map {
                SourceStatus(name: $0.name, provider: $0.provider, syncedAt: $0.syncedAt, lastError: $0.lastError, taskCount: $0.taskCount)
            },
            tags: board.allTags,
            currentPriority: currentPriority
        )
    }

    /// Every configured source, with its settings and how it last synced.
    public func sources() -> [SourceStatus] {
        let config = files.loadConfig()
        let statuses = Dictionary(files.board().sources.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        return config.sources.map { source in
            let status = statuses[source.name]
            let file = status == nil ? files.loadSourceFile(source.name) : nil
            return SourceStatus(
                name: source.name,
                provider: source.provider,
                settings: source.settings,
                tags: source.tags,
                enabled: source.enabled,
                isDefaultForCreate: config.defaultCreateSource == source.name,
                syncedAt: status?.syncedAt ?? file?.syncedAt,
                lastError: status?.lastError ?? file?.lastError,
                taskCount: status?.taskCount ?? file?.tasks.count ?? 0
            )
        }
    }

    // MARK: - Changing tasks

    public struct Change: Encodable, Sendable {
        /// The task's key; for a create still waiting on its source, the pending key.
        public var key: String
        public var title: String?
        public var state: MirroredTaskState?
        public var pinnedTo: UUID?
        /// Whether the change is still in the outbox, waiting for its source.
        public var pending: Bool
        /// The source refused the change for good, and it was dropped.
        public var refused: Bool = false
        public var note: String
        public var sync: TaskSyncSummary?
    }

    /// Creates a task: on the local list, or in `source` (the config's default when `nil`).
    public func create(title: String, source: String? = nil, tags: [String] = [], pinTo: UUID? = nil) async throws -> Change {
        let title = try TaskMirror.normalisedTitle(title)
        for tag in tags where tag.count > TaskMirror.maximumTagLength {
            throw TaskMirrorError.textTooLong(field: "tag", maximum: TaskMirror.maximumTagLength)
        }
        let config = files.loadConfig()
        let source = source?.nilIfEmpty ?? config.defaultCreateSource
        if source == TaskMirror.localSource {
            let task = try files.addLocal(title: title, tags: tags, now: now())
            let key = TaskKey(source: source, id: task.id)
            if let pinTo { try files.pin(key, to: pinTo) }
            return Change(key: key.description, title: title, state: .open, pinnedTo: pinTo, pending: false, note: "Added to the local list.")
        }
        let configured = try configuredSource(source, in: config)
        let action = TaskAction(kind: .create, source: configured.name, title: title, tags: tags, pinTo: pinTo, createdAt: now())
        try files.enqueue(action)
        let summary = try await sync.run(source: configured.name, lockWait: lockWait)
        let result = summary.actions.first { $0.id == action.id }
        if result?.outcome == .applied, let key = result?.key {
            return Change(key: key.description, title: title, state: .open, pinnedTo: pinTo, pending: false,
                          note: "Created in \(configured.name).", sync: summary)
        }
        return Change(key: action.pendingKey.description, title: title, state: .open, pinnedTo: pinTo,
                      pending: result?.outcome != .dropped, refused: result?.outcome == .dropped,
                      note: Self.note(result, summary: summary, source: configured.name), sync: summary)
    }

    /// Marks a task done, or open again when `done` is `false`.
    public func setState(key text: String, done: Bool) async throws -> Change {
        let key = try Self.key(text)
        let state: MirroredTaskState = done ? .done : .open
        if key.source == TaskMirror.localSource {
            guard try files.setLocal(id: key.id, state: state, now: now()) else { throw BridgeError("no task \(key)") }
            return Change(key: key.description, state: state, pending: false, note: done ? "Done." : "Reopened.")
        }
        let config = files.loadConfig()
        let source = try configuredSource(key.source, in: config)
        guard !key.id.hasPrefix("pending-") else {
            throw BridgeError("\(key) is still being created in \(source.name); try again after the next sync")
        }
        guard files.loadSourceFile(source.name)?.tasks.contains(where: { $0.id == key.id }) == true else {
            throw BridgeError("no task \(key); run `focus-bridge tasks sync` first if it is new")
        }
        for earlier in files.loadOutbox() where earlier.taskKey == key && earlier.kind != .create {
            try files.removeAction(earlier)
        }
        let action = TaskAction(kind: done ? .complete : .reopen, source: source.name, taskID: key.id, createdAt: now())
        try files.enqueue(action)
        let summary = try await sync.run(source: source.name, lockWait: lockWait)
        let result = summary.actions.first { $0.id == action.id }
        let applied = result?.outcome == .applied
        return Change(
            key: key.description,
            state: state,
            pending: !applied && result?.outcome != .dropped,
            refused: result?.outcome == .dropped,
            note: applied ? (done ? "Done in \(source.name)." : "Reopened in \(source.name).") : Self.note(result, summary: summary, source: source.name),
            sync: summary
        )
    }

    /// Pins a task to a priority, or unpins it.
    public func pin(key text: String, to priority: UUID?) throws -> Change {
        let key = try Self.key(text)
        let board = files.board()
        let known = board.items.contains { $0.key == key }
            || files.loadSourceFile(key.source)?.tasks.contains { $0.id == key.id } == true
        guard known else { throw BridgeError("no task \(key)") }
        try files.pin(key, to: priority)
        return Change(key: key.description, pinnedTo: priority, pending: false, note: priority == nil ? "Unpinned." : "Pinned.")
    }

    // MARK: - Sources

    /// Adds or replaces a source after checking its settings. `makeDefault` sends new tasks there.
    public func addSource(_ source: TaskSourceConfig, makeDefault: Bool = false) throws -> TaskSourceConfig {
        var source = source
        source.settings = source.settings.mapValues { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.value.isEmpty }
        try TaskMirror.validate(source)
        switch source.providerKind {
        case .githubIssues:
            _ = try GitHubClient.repository(source)
        case .githubProject:
            _ = try GitHubProjectProvider.Settings(source)
        case nil:
            break
        }
        var config = files.loadConfig()
        config.upsert(source)
        if makeDefault { config.createSource = source.name }
        try files.saveConfig(config)
        return source
    }

    public struct Removal: Encodable, Sendable {
        public var removed: String
        public var actionsDropped: Int
        public var pinsDropped: Int
    }

    /// Removes a source, its mirrored tasks, its waiting actions and its pins.
    public func removeSource(named name: String) throws -> Removal {
        var config = files.loadConfig()
        guard config.source(named: name) != nil else { throw BridgeError("no source \(name)") }
        config.remove(named: name)
        try files.saveConfig(config)
        try files.removeSourceFile(name)
        var actions = 0
        for action in files.loadOutbox() where action.source == name {
            try files.removeAction(action)
            actions += 1
        }
        var pins = files.loadPins()
        let before = pins.pins.count
        pins.pins = pins.pins.filter { $0.key.source != name }
        if pins.pins.count != before { try files.savePins(pins) }
        return Removal(removed: name, actionsDropped: actions, pinsDropped: before - pins.pins.count)
    }

    // MARK: - Input

    public static func key(_ text: String) throws -> TaskKey {
        guard let key = TaskKey(text.trimmingCharacters(in: .whitespaces)) else {
            throw BridgeError("a task key is <source>/<id>, e.g. work-os/42 or local/<uuid>, not '\(text)'")
        }
        return key
    }

    /// A source config from tool arguments: `name`, `provider`, `settings` (an object of
    /// strings or numbers), `tags`, `enabled`.
    public static func sourceConfig(from arguments: [String: Any]) throws -> TaskSourceConfig {
        guard let name = arguments["name"] as? String else { throw BridgeError("name is required") }
        guard let provider = arguments["provider"] as? String else { throw BridgeError("provider is required") }
        var settings: [String: String] = [:]
        if let raw = arguments["settings"] {
            guard let object = raw as? [String: Any] else { throw BridgeError("settings must be an object") }
            for (key, value) in object {
                switch value {
                case let text as String: settings[key] = text
                case let number as NSNumber where !(value is Bool): settings[key] = number.stringValue
                default: throw BridgeError("setting \(key) must be a string or a number")
                }
            }
        }
        let tags = try MCPServer.strings(arguments["tags"], name: "tags")
        return TaskSourceConfig(name: name, provider: provider, settings: settings, tags: tags, enabled: arguments["enabled"] as? Bool ?? true)
    }

    private func configuredSource(_ name: String, in config: TaskMirrorConfig) throws -> TaskSourceConfig {
        guard let source = config.source(named: name) else {
            let known = ([TaskMirror.localSource] + config.sources.map(\.name)).joined(separator: ", ")
            throw BridgeError("no source \(name); known: \(known)")
        }
        guard source.enabled else { throw BridgeError("source \(name) is switched off") }
        return source
    }

    private func item(from item: TaskBoardItem, currentPriority: UUID?) -> Item {
        Item(
            key: item.key.description,
            source: item.key.source,
            title: item.task.title,
            url: item.task.url,
            reference: item.task.reference,
            tags: item.task.tags,
            state: item.task.state,
            pinned: item.pinnedTo != nil,
            pinnedTo: item.pinnedTo,
            pinnedToCurrentPriority: currentPriority != nil && item.pinnedTo == currentPriority,
            pending: item.pending,
            updatedAt: item.task.updatedAt,
            completedAt: item.task.completedAt
        )
    }

    private static func note(_ result: TaskSyncSummary.Action?, summary: TaskSyncSummary, source: String) -> String {
        if summary.alreadyRunning { return "Queued; another sync is running and the next one will send it to \(source)." }
        switch result?.outcome {
        case .dropped?: return "\(source) refused it and it was dropped: \(result?.error ?? "no reason given")."
        case .kept?: return "Queued; \(source) could not be told yet (\(result?.error ?? "no reason given")). The next sync retries."
        default: return "Queued for \(source)."
        }
    }
}
