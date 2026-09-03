import Foundation

/// **How long the person asked this app to keep what it wrote down** (F-115, focus-l7n).
///
/// Four choices and no free-text field, because the value is a promise the sweep has to keep
/// exactly: a number a person could type is a number somebody types `0` into by accident, and
/// "forever" is a *decision* rather than a very large number — the sweep skips its stores
/// altogether rather than computing a cutoff in the year 4000.
///
/// The raw value **is** the day count and `0` is forever, so the stored column is a plain `Int`
/// whose meaning does not depend on a lookup table anybody has to keep in step. `decode(_:)` is
/// total, for `NudgeVoice.decode(_:)`'s reason: a newer build may have written a window this one
/// has never heard of, and the honest answer is the committed default plus a fact saying the row
/// was not understood — never a crash, and never a silent reinterpretation as a *shorter*
/// window, which would delete rows the person had asked to keep.
public enum RetentionWindow: Int, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// Keep everything. The sweep still runs; it removes nothing.
    case forever = 0
    case sevenDays = 7
    case thirtyDays = 30
    case ninetyDays = 90

    /// How many days are kept, or `nil` for "keep everything" — which is not a day count and is
    /// deliberately not spelled as one.
    public var days: Int? {
        self == .forever ? nil : rawValue
    }

    /// What goes in the column.
    public var storedDays: Int { rawValue }

    /// **The committed default** — the window a store that has never been asked answers with.
    ///
    /// Ninety days, unchanged from the value that shipped before there was a control: a person
    /// upgrading must not silently have their history shortened by the arrival of a picker.
    public static let committedDefault: RetentionWindow = .ninetyDays

    /// The order the control draws: shortest first, with forever last because it keeps the most
    /// and reads as the end of a scale.
    public static let ordered: [RetentionWindow] = [
        .sevenDays, .thirtyDays, .ninetyDays, .forever
    ]

    /// The stored window, decoded totally, **and whether this build could read it**.
    ///
    /// The pair rather than an optional, for the reason `NudgeVoice.decode(_:)` returns one: the
    /// caller owes the person a fault in the log and a reading in the self-check, not a
    /// substitution nobody can see.
    public static func decode(_ raw: Int) -> (window: RetentionWindow, wasRecognised: Bool) {
        switch raw {
        case 0: (.forever, true)
        case 7: (.sevenDays, true)
        case 30: (.thirtyDays, true)
        case 90: (.ninetyDays, true)
        default: (committedDefault, false)
        }
    }
}

/// **How long this app keeps what it wrote down** (F-115, focus-tzj.3, focus-l7n).
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
/// A privacy posture that is only a plan is not a posture. `RetentionSweep` is the mechanism;
/// this is the window it keeps.
///
/// ## Why it is no longer a constant
///
/// It shipped as one — ninety days, with a doc comment promising that "e07's picker moves one
/// value rather than touching four stores". That promise is now kept: the policy wraps a
/// `RetentionWindow` the person sets in Settings ▸ Privacy, the sweep reads it out of the store
/// on every run, and `committedDefault` is what an unasked store answers rather than what every
/// store is stuck with.
public struct RetentionPolicy: Sendable, Equatable, Hashable, Codable {
    /// The window this policy keeps — the person's choice, or the committed default.
    public let window: RetentionWindow

    public init(window: RetentionWindow) {
        self.window = window
    }

    /// How many days of history are kept, or `nil` when the answer is "all of them". Rows
    /// stamped strictly before the cutoff are removed.
    public var days: Int? { window.days }

    /// **The committed default** — what a store that has never been asked answers.
    public static let committedDefault = RetentionPolicy(window: .committedDefault)

    /// The instant before which rows are no longer kept, as of `now` — or `nil` when the window
    /// is forever, which is an instruction to touch nothing rather than a date far enough away.
    ///
    /// Computed by calendar days rather than by subtracting 90 × 86 400 seconds, because a
    /// retention window is a promise about **days** and two of them a year are not 86 400
    /// seconds long. The calendar is the person's own, for `LocalDay`'s reason.
    public func cutoff(from now: Date, calendar: Calendar) -> Date? {
        guard let days else { return nil }
        return calendar.date(byAdding: .day, value: -days, to: now) ?? now
    }

    /// The same boundary as a local day, for the stores that key on one.
    public func cutoffDay(from now: Date, calendar: Calendar) -> LocalDay? {
        cutoff(from: now, calendar: calendar).map { LocalDay.containing($0, calendar: calendar) }
    }
}
