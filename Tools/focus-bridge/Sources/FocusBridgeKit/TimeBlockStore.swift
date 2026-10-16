import FocusCore
import Foundation

/// **Where outside sources' time goes** (focus-ext): one JSON file per source beside the store,
/// which the app reads on its next tick. No confirmation, because a block of busy time asks the
/// app to do *less* — stay quiet, book no focus block across it — never more.
public struct TimeBlockStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `FOCUS_TIME_BLOCKS` if set, else the `TimeBlocks` directory beside the store the bridge
    /// reads (`FOCUS_STORE`, else the Stable app's).
    public static func defaultDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["FOCUS_TIME_BLOCKS"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return ExternalTimeBlocks.directory(besideStore: Snapshot.defaultStoreURL(environment: environment))
    }

    /// Replace a source's whole set. Blocks that have already ended are dropped.
    @discardableResult
    public func set(source: String, blocks: [TimeBlock], now: Date) throws -> TimeBlockFile {
        try ExternalTimeBlocks.validate(source: source)
        let kept = blocks.filter { $0.end > now }.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        try ExternalTimeBlocks.validate(kept)
        let file = TimeBlockFile(source: source, updatedAt: now, blocks: kept)
        try write(file)
        return file
    }

    /// Add one block to a source's set, replacing any block with the same `id`.
    @discardableResult
    public func add(source: String, block: TimeBlock, now: Date) throws -> TimeBlockFile {
        try ExternalTimeBlocks.validate(source: source)
        try ExternalTimeBlocks.validate(block)
        var blocks = try load(source: source)?.blocks ?? []
        if let id = block.id { blocks.removeAll { $0.id == id } }
        blocks.append(block)
        return try set(source: source, blocks: blocks, now: now)
    }

    /// Every source's file, or one source's, with blocks that have ended left out.
    public func list(source: String? = nil, now: Date) throws -> [TimeBlockFile] {
        let sources: [String]
        if let source {
            try ExternalTimeBlocks.validate(source: source)
            sources = [source]
        } else {
            sources = allSources()
        }
        return try sources.compactMap { try load(source: $0) }.map { file in
            var file = file
            file.blocks = file.blocks.filter { $0.end > now }
            return file
        }
    }

    /// Remove one source's file, or every source's. Returns the sources removed.
    @discardableResult
    public func clear(source: String? = nil) throws -> [String] {
        let sources: [String]
        if let source {
            try ExternalTimeBlocks.validate(source: source)
            sources = [source]
        } else {
            sources = allSources()
        }
        var removed: [String] = []
        for source in sources {
            let url = ExternalTimeBlocks.fileURL(for: source, in: directory)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            try FileManager.default.removeItem(at: url)
            removed.append(source)
        }
        return removed
    }

    // MARK: - Input

    /// A source name from arguments, refused unless it is filename-safe.
    public static func source(_ value: Any?) throws -> String {
        guard let source = value as? String else { throw BridgeError("source is required") }
        guard ExternalTimeBlocks.isValidSource(source) else {
            throw BridgeError(TimeBlockError.invalidSource(source).description)
        }
        return source
    }

    /// A block from tool or CLI arguments: `kind`, `start` (default now), and `end` or
    /// `duration_minutes`; `title`, `detail` and `id` optional.
    public static func block(from arguments: [String: Any], now: Date) throws -> TimeBlock {
        guard let kindName = arguments["kind"] as? String else { throw BridgeError("kind is required") }
        guard let kind = TimeBlockKind(rawValue: kindName.lowercased()) else {
            let known = TimeBlockKind.allCases.map(\.rawValue).joined(separator: ", ")
            throw BridgeError("kind must be one of \(known), not '\(kindName)'")
        }
        let start = try (arguments["start"] as? String).map { try date($0, name: "start") } ?? now
        let end: Date
        switch (arguments["end"] as? String, minutes(arguments["duration_minutes"])) {
        case (let text?, nil):
            end = try date(text, name: "end")
        case (nil, let minutes?):
            guard minutes > 0 else { throw BridgeError("duration_minutes must be positive") }
            end = start.addingTimeInterval(minutes * 60)
        case (.some, .some):
            throw BridgeError("give end or duration_minutes, not both")
        case (nil, nil):
            throw BridgeError("end or duration_minutes is required")
        }
        let block = TimeBlock(
            id: nonEmpty(arguments["id"]),
            kind: kind,
            start: start,
            end: end,
            title: nonEmpty(arguments["title"]),
            detail: nonEmpty(arguments["detail"])
        )
        do {
            try ExternalTimeBlocks.validate(block)
        } catch let error as TimeBlockError {
            throw BridgeError(error.description)
        }
        return block
    }

    private static func date(_ text: String, name: String) throws -> Date {
        guard let date = ExternalTimeBlocks.parseDate(text) else {
            throw BridgeError("\(name) must be an ISO 8601 time (e.g. 2026-10-16T14:00:00+01:00), not '\(text)'")
        }
        return date
    }

    private static func minutes(_ value: Any?) -> Double? {
        if let number = value as? NSNumber, !(value is Bool) { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }

    // MARK: - Files

    private func allSources() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(5)) }
            .filter(ExternalTimeBlocks.isValidSource)
            .sorted()
    }

    private func load(source: String) throws -> TimeBlockFile? {
        let url = ExternalTimeBlocks.fileURL(for: source, in: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        do {
            return try ExternalTimeBlocks.decoder().decode(TimeBlockFile.self, from: data)
        } catch {
            throw BridgeError("\(url.path) is not a time-block file: \(error)")
        }
    }

    private func write(_ file: TimeBlockFile) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = ExternalTimeBlocks.fileURL(for: file.source, in: directory)
        try ExternalTimeBlocks.encoder().encode(file).write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
