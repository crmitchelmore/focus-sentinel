import Foundation

/// **What kind of time an outside source says a stretch is** (focus-ext).
///
/// A provider — an Outlook bridge, a rota, a script — tells the app about time it cannot read
/// itself, through `focus-bridge`. Some kinds hold the question (the person is busy, so the app
/// stays silent and books no focus block across it); the rest are accepted, kept with the
/// provider's file and change nothing. One place decides which is which.
public enum TimeBlockKind: String, Sendable, Codable, CaseIterable, Hashable {
    /// A meeting or anything else the person is committed to.
    case busy
    /// Away from the desk: out of office, travel, lunch.
    case away
    /// Probably busy. Treated as busy: a nudge into a maybe-meeting costs more than one missed.
    case tentative
    /// Time set aside for focus. The app keeps asking — focus time is when it is most use.
    case focus
    /// Explicitly free.
    case free

    /// Whether a block of this kind silences nudges and refuses a timebox that runs into it.
    public var holdsTheQuestion: Bool {
        switch self {
        case .busy, .away, .tentative: true
        case .focus, .free: false
        }
    }
}

/// **One stretch of time from an outside source** (focus-ext), as the provider wrote it.
///
/// `title` and `detail` are the provider's and stay in the provider's file: the app decodes
/// only `kind`, `start` and `end` (see `ExternalTimeBlocks.busyBlocks(from:in:)`), so no title
/// reaches the store, the export or a log.
public struct TimeBlock: Sendable, Codable, Equatable, Hashable {
    public var id: String?
    public var kind: TimeBlockKind
    public var start: Date
    public var end: Date
    public var title: String?
    public var detail: String?

    public init(id: String? = nil, kind: TimeBlockKind, start: Date, end: Date, title: String? = nil, detail: String? = nil) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.title = title
        self.detail = detail
    }
}

/// **One provider's file** (focus-ext): `<TimeBlocks>/<source>.json`, replaced whole on every
/// write so a provider owns its set and two providers never edit one another's.
public struct TimeBlockFile: Sendable, Codable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var source: String
    public var updatedAt: Date
    public var blocks: [TimeBlock]

    public init(source: String, updatedAt: Date, blocks: [TimeBlock]) {
        self.version = Self.currentVersion
        self.source = source
        self.updatedAt = updatedAt
        self.blocks = blocks
    }
}

/// Why a provider's block or source was refused.
public enum TimeBlockError: Error, Equatable, CustomStringConvertible {
    case invalidSource(String)
    case endNotAfterStart
    case tooLong(maximumDays: Int)
    case tooManyBlocks(maximum: Int)
    case textTooLong(field: String, maximum: Int)

    public var description: String {
        switch self {
        case .invalidSource(let source):
            "source \"\(source)\" must be 1–\(ExternalTimeBlocks.maximumSourceLength) characters of a–z, 0–9, '.', '_' or '-'"
        case .endNotAfterStart:
            "a time block must end after it starts"
        case .tooLong(let days):
            "a time block may last at most \(days) days"
        case .tooManyBlocks(let maximum):
            "a source may hold at most \(maximum) time blocks"
        case .textTooLong(let field, let maximum):
            "\(field) may be at most \(maximum) characters"
        }
    }
}

/// **The contract between a provider and the app** (focus-ext): where the files live, what a
/// valid one holds, and how the app reads one.
///
/// The transport is a directory beside the store, not a URL, because a block has to outlast the
/// call that sent it and arrive without the person confirming anything. With no file in it the
/// app behaves exactly as it did before outside sources existed.
public enum ExternalTimeBlocks {
    public static let directoryName = "TimeBlocks"
    public static let maximumSourceLength = 64
    public static let maximumBlocksPerSource = 500
    public static let maximumBlockDays = 31
    public static let maximumTitleLength = 200
    public static let maximumDetailLength = 2_000

    /// The directory beside a store file.
    public static func directory(besideStore store: URL) -> URL {
        store.deletingLastPathComponent().appending(path: directoryName, directoryHint: .isDirectory)
    }

    /// The file a source writes. `source` must already be valid.
    public static func fileURL(for source: String, in directory: URL) -> URL {
        directory.appending(path: "\(source).json", directoryHint: .notDirectory)
    }

    /// A source names a file, so it is held to a filename-safe alphabet.
    public static func isValidSource(_ source: String) -> Bool {
        !source.isEmpty
            && source.count <= maximumSourceLength
            && !source.hasPrefix(".")
            && source.unicodeScalars.allSatisfy { scalar in
                ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar)
                    || scalar == "." || scalar == "_" || scalar == "-"
            }
    }

    public static func validate(source: String) throws {
        guard isValidSource(source) else { throw TimeBlockError.invalidSource(source) }
    }

    public static func validate(_ block: TimeBlock) throws {
        guard block.end > block.start else { throw TimeBlockError.endNotAfterStart }
        guard block.end.timeIntervalSince(block.start) <= Double(maximumBlockDays) * 86_400 else {
            throw TimeBlockError.tooLong(maximumDays: maximumBlockDays)
        }
        if let title = block.title, title.count > maximumTitleLength {
            throw TimeBlockError.textTooLong(field: "title", maximum: maximumTitleLength)
        }
        if let detail = block.detail, detail.count > maximumDetailLength {
            throw TimeBlockError.textTooLong(field: "detail", maximum: maximumDetailLength)
        }
        if let id = block.id, id.count > maximumTitleLength {
            throw TimeBlockError.textTooLong(field: "id", maximum: maximumTitleLength)
        }
    }

    public static func validate(_ blocks: [TimeBlock]) throws {
        guard blocks.count <= maximumBlocksPerSource else {
            throw TimeBlockError.tooManyBlocks(maximum: maximumBlocksPerSource)
        }
        for block in blocks { try validate(block) }
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = parseDate(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "not an ISO 8601 date: \(text)")
            }
            return date
        }
        return decoder
    }

    /// ISO 8601 with or without fractional seconds, or a bare local `yyyy-MM-ddTHH:mm[:ss]`.
    public static func parseDate(_ text: String, timeZone: TimeZone = .current) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: trimmed) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) { return date }
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    /// **What the app takes from a provider's file**: the stretches that hold the question and
    /// overlap `interval`, as busy blocks.
    ///
    /// Decodes through a narrow shape that names only `kind`, `start` and `end`, so a title is
    /// never held in a value the app owns. A block of a kind this build does not know, a block
    /// that ends before it starts or runs past the limit, and anything past the per-source cap
    /// are ignored rather than failing the file. An unreadable file yields `nil`.
    public static func busyBlocks(from data: Data, in interval: DateInterval) -> [CalendarBusyBlock]? {
        guard let file = try? decoder().decode(NarrowFile.self, from: data) else { return nil }
        return file.blocks.prefix(maximumBlocksPerSource).compactMap { block in
            guard let kindName = block.kind,
                  let kind = TimeBlockKind(rawValue: kindName),
                  kind.holdsTheQuestion,
                  let start = block.start, let end = block.end,
                  end > start,
                  end.timeIntervalSince(start) <= Double(maximumBlockDays) * 86_400,
                  end > interval.start, start < interval.end
            else { return nil }
            return CalendarBusyBlock(start: start, end: end)
        }
    }

    private struct NarrowFile: Decodable {
        let blocks: [NarrowBlock]
    }

    private struct NarrowBlock: Decodable {
        let kind: String?
        let start: Date?
        let end: Date?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try? container.decodeIfPresent(String.self, forKey: .kind)
            start = try? container.decodeIfPresent(Date.self, forKey: .start)
            end = try? container.decodeIfPresent(Date.self, forKey: .end)
        }

        enum CodingKeys: String, CodingKey { case kind, start, end }
    }
}
