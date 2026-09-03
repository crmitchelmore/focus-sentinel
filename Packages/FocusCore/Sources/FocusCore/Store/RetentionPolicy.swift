import Foundation

/// **How long this app keeps what it wrote down** (F-115, focus-tzj.3).
///
/// ## Why there is a number here at all
///
/// Three tables grew without bound. `ActivityEventStore` said so in as many words — *"the store
/// is unbounded in e03 … a retention policy is e08's"* — and `InterventionLog.purge(before:)`,
/// `QueryLedger.purge(priorityID:)` and `purgeAll()` were all written, all tested, and called by
/// **nothing**. So the app observed a person's day every five seconds and kept every row of it
/// for the life of the installation, while the code that would have deleted them sat there
/// looking like a policy.
///
/// A privacy posture that is only a plan is not a posture. e07 §5 owns the *user-visible* part —
/// the picker, the delete-everything button, the sentence in Settings that says what this number
/// is — and this is the mechanism underneath it, committed now so that the rows are not there to
/// expose later.
///
/// ## Why ninety days
///
/// It is the shortest window that still leaves e09's timeline and pattern work something to read
/// — a quarter is the unit a person thinks about their own work in — and it is a **default**,
/// not a law: the type carries the number so that e07's picker moves one value rather than
/// touching four stores. Chosen rather than measured, and said so.
public struct RetentionPolicy: Sendable, Equatable, Hashable, Codable {
    /// How many days of history are kept. Rows stamped strictly before the cutoff are removed.
    public let days: Int

    public init(days: Int) {
        self.days = days
    }

    /// **The committed default** — the one e07's picker will start at.
    public static let committedDefault = RetentionPolicy(days: 90)

    /// The instant before which rows are no longer kept, as of `now`.
    ///
    /// Computed by calendar days rather than by subtracting 90 × 86 400 seconds, because a
    /// retention window is a promise about **days** and two of them a year are not 86 400
    /// seconds long. The calendar is the person's own, for `LocalDay`'s reason.
    public func cutoff(from now: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now) ?? now
    }

    /// The same boundary as a local day, for the stores that key on one.
    public func cutoffDay(from now: Date, calendar: Calendar) -> LocalDay {
        LocalDay.containing(cutoff(from: now, calendar: calendar), calendar: calendar)
    }
}
