import Foundation
import SwiftData

/// The one local timeline: append, query, and a debug export the evidence lane reads.
///
/// ## Normalised evidence only, enforced by the signature
///
/// `append` takes a `NormalisedDetail`, and `NormalisedDetail` has **no `String` initialiser**.
/// Its only two constructors take a closed vocabulary of tokens or a typed measurement, so a
/// window title, a URL with its path and query, a document name or an absolute file path cannot
/// be turned into one by any route — they are not forbidden here, they are unrepresentable. The
/// lint that fails on a raw assignment to `.detail` catches the one route left, which is
/// somebody bypassing this facade and writing to the model directly.
///
/// ## The export re-checks what it exports
///
/// `exportJSON` does not trust the column. Every stored `detail` is read back through
/// `NormalisedDetail.inspect(_:)` and re-emitted from what that recognised — so a value written
/// by a build that knew a token this one does not comes out as nothing at all, and a value that
/// somehow held raw text could not come out as text. That makes "the export contains only
/// closed-vocabulary tokens, numbers, bundle identifiers and timestamps" a property of the
/// exporter rather than an inherited promise.
///
/// ## Retention
///
/// The store is unbounded in e03 and F-116's delete-everything path already covers it. A
/// retention policy is e08's; inventing one here would be inventing a user-visible privacy
/// promise outside its epic.
@MainActor
public final class ActivityEventStore {
    private let context: ModelContext
    private let dateProvider: any DateProvider

    public init(context: ModelContext, dateProvider: some DateProvider = SystemDateProvider()) {
        self.context = context
        self.dateProvider = dateProvider
    }

    // MARK: - Appending

    /// Write one observation.
    ///
    /// - Parameters:
    ///   - kind: what happened, from the closed vocabulary.
    ///   - bundleID: the application involved, when there is one. A bundle identifier and
    ///     nothing else.
    ///   - detail: normalised evidence. `.empty` is the commonest answer and a perfectly good
    ///     one — most rows have nothing to add beyond their kind and their subject.
    ///   - dwellSeconds: **monotonic**, from `MonotonicClock`. The one quantity on a row that
    ///     is not wall-clock; `at` is, from the injected `DateProvider`, because it is what a
    ///     person reads tomorrow.
    ///   - at: the instant, defaulting to the injected clock's `now`. Passed explicitly only by
    ///     a caller that already stamped the observation — an activation carries its own `at`,
    ///     and re-reading the clock here would put the row a few microseconds after the thing
    ///     it describes.
    @discardableResult
    public func append(
        kind: ActivityEventKind,
        bundleID: String? = nil,
        detail: NormalisedDetail = .empty,
        sessionID: UUID? = nil,
        dwellSeconds: Double? = nil,
        displayID: Int? = nil,
        at instant: Date? = nil
    ) throws -> UUID {
        let id = UUID()
        let event = FocusSchemaV3.ActivityEvent(
            id: id,
            at: instant ?? dateProvider.now,
            kindRaw: kind.rawValue,
            bundleID: bundleID,
            // The only assignment to this column in the shipping graph, and its right-hand
            // side is a `NormalisedDetail`'s own stored value. There is no other way in.
            detail: detail.isEmpty ? nil : detail.storedValue,
            sessionID: sessionID,
            dwellSeconds: dwellSeconds,
            displayID: displayID
        )
        context.insert(event)
        try context.save()
        return id
    }

    // MARK: - Reading

    /// Every row, oldest first.
    ///
    /// Ordered by `at` and then by identifier, so rows stamped at the same instant — which the
    /// corroboration tick produces, several at a time — read back in one stable order rather
    /// than in whatever order the store felt like. Sorted in Swift for the same reason the
    /// history is: the tie-break is a decision, not a side effect.
    public func all() throws -> [FocusSchemaV3.ActivityEvent] {
        try context.countedFetch(FetchDescriptor<FocusSchemaV3.ActivityEvent>()).sorted(by: Self.chronological)
    }

    /// The rows in a half-open interval `[from, to)`.
    ///
    /// Half-open so that two adjacent windows partition the timeline exactly: a row on the
    /// boundary belongs to the later one and to nothing else.
    public func events(from start: Date, to end: Date) throws -> [FocusSchemaV3.ActivityEvent] {
        let descriptor = FetchDescriptor<FocusSchemaV3.ActivityEvent>(
            predicate: #Predicate { $0.at >= start && $0.at < end }
        )
        return try context.countedFetch(descriptor).sorted(by: Self.chronological)
    }

    /// The rows for one session, oldest first.
    public func events(ofSession sessionID: UUID) throws -> [FocusSchemaV3.ActivityEvent] {
        let descriptor = FetchDescriptor<FocusSchemaV3.ActivityEvent>(
            predicate: #Predicate { $0.sessionID == sessionID }
        )
        return try context.countedFetch(descriptor).sorted(by: Self.chronological)
    }

    public func count() throws -> Int {
        try context.countedFetchCount(FetchDescriptor<FocusSchemaV3.ActivityEvent>())
    }

    // MARK: - Retention (F-115, focus-tzj.3)

    /// **Delete every observation older than `cutoff`.**
    ///
    /// The one thing that ever removes a row here. It is a predicate rather than a fetch-all and
    /// filter, because this is the largest table in the store — the corroboration tick appends
    /// to it twelve times a minute — and the sweep that calls it runs at launch, when the app is
    /// doing everything else it does at launch.
    ///
    /// Half-open the other way round from `events(from:to:)`: a row stamped **exactly** at the
    /// cutoff is inside the window and is kept, so a row is never removed on the day it becomes
    /// eligible-by-rounding.
    ///
    /// - Returns: how many rows went. Read by `RetentionSweep`, published by the self-check, and
    ///   the reason this is a count rather than `Void`: "the sweep ran" and "the sweep removed
    ///   something" are different facts and only the second one is evidence.
    @discardableResult
    public func purge(before cutoff: Date) throws -> Int {
        let descriptor = FetchDescriptor<FocusSchemaV3.ActivityEvent>(
            predicate: #Predicate { $0.at < cutoff }
        )
        let doomed = try context.countedFetch(descriptor)
        for row in doomed { context.delete(row) }
        if !doomed.isEmpty { try context.save() }
        return doomed.count
    }

    private static func chronological(
        _ lhs: FocusSchemaV3.ActivityEvent,
        _ rhs: FocusSchemaV3.ActivityEvent
    ) -> Bool {
        if lhs.at != rhs.at { return lhs.at < rhs.at }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    // MARK: - The debug export

    /// One exported row. Every field is a token, a number, a bundle identifier, an identifier
    /// or a timestamp — there is no member that could hold captured content, because there is
    /// no member of a type that could.
    public struct ExportedEvent: Sendable, Equatable, Codable {
        public let at: Date
        /// The kind's raw value, or `nil` for a row this build cannot interpret.
        public let kind: String?
        public let bundleID: String?
        /// The closed-vocabulary tokens this row carries, re-derived from the stored value
        /// rather than copied out of it.
        public let tokens: [String]?
        /// A typed measurement's kind and value, when the row carries one instead.
        public let measurement: String?
        public let measurementValue: Int?
        public let sessionID: String?
        public let dwellSeconds: Double?
        public let displayID: Int?
    }

    /// Project one stored row into its exportable form, re-checking the detail column.
    ///
    /// A stored value this build cannot interpret contributes **nothing** — not the raw string,
    /// not a placeholder. It is inert, which is what `NormalisedDetail.Inspection.unreadable`
    /// means: a row written by a build that knew a token this one does not is not a licence to
    /// print its contents.
    public static func exported(_ event: FocusSchemaV3.ActivityEvent) -> ExportedEvent {
        var tokens: [String]?
        var measurement: String?
        var measurementValue: Int?

        switch NormalisedDetail.inspect(event.detail) {
        case .none, .unreadable:
            break
        case .tokens(let found):
            tokens = found.map(\.rawValue)
        case .measurement(let kind, let value):
            measurement = kind.rawValue
            measurementValue = value
        }

        return ExportedEvent(
            at: event.at,
            kind: ActivityEventKind.decode(event.kindRaw)?.rawValue,
            bundleID: event.bundleID,
            tokens: tokens,
            measurement: measurement,
            measurementValue: measurementValue,
            sessionID: event.sessionID?.uuidString,
            dwellSeconds: event.dwellSeconds,
            displayID: event.displayID
        )
    }

    /// The whole timeline as JSON, for the live evidence lane to read.
    ///
    /// Deterministic on purpose — sorted keys, ISO-8601 instants, oldest first — so two runs of
    /// the same drive produce two diffable files and a reviewer can see what changed rather
    /// than re-reading the whole thing.
    public func exportJSON(from start: Date? = nil, to end: Date? = nil) throws -> Data {
        let rows: [FocusSchemaV3.ActivityEvent]
        switch (start, end) {
        case (let start?, let end?):
            rows = try events(from: start, to: end)
        default:
            rows = try all()
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(rows.map(Self.exported))
    }
}
