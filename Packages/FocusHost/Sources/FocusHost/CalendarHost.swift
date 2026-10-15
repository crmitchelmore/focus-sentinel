import FocusCore
import Foundation

/// **The calendar the rest of the app reads** (focus-cal), as one `CalendarAgenda`.
///
/// Holds the reader when there is one and caches what it read, so the five-second cockpit tick
/// and the nudge loop share one read rather than each asking EventKit. With no reader — the
/// switch is off, or macOS said no — the agenda is `.unread`, which refuses no timebox, closes
/// no gate and draws nothing: a default install behaves exactly as it did before this existed.
///
/// Nothing here is stored. The agenda is a window of busy intervals around now, held in memory
/// and replaced on the next read.
@MainActor
final class CalendarHost {
    /// How far either side of now is read. Twelve hours covers the longest timebox several
    /// times over and a meeting that started this morning, without reading a person's week.
    static let horizon: TimeInterval = 12 * 60 * 60
    /// How long a read is trusted before the next one. A minute is well inside the minute's
    /// grace `CalendarOutlook` allows, and EventKit's change notification re-reads sooner.
    static let freshness: TimeInterval = 60

    private var reader: (any CalendarReading)?
    private var cached: CalendarAgenda = .unread
    private var readAt: Date?

    /// Point the host at a reader, or at none. Drops the cache either way, so a calendar the
    /// person just switched off is gone from the next refresh rather than a minute later.
    func use(_ reader: (any CalendarReading)?) {
        self.reader = reader
        invalidate()
    }

    var isReading: Bool { reader != nil }

    /// Forget the last read; the next `agenda(at:)` reads again.
    func invalidate() {
        cached = .unread
        readAt = nil
    }

    /// The agenda around `now`, read again when the last read is older than `freshness` or
    /// `now` has moved backwards past it (a clock change).
    func agenda(at now: Date) -> CalendarAgenda {
        guard let reader else { return .unread }
        if let readAt, now >= readAt, now.timeIntervalSince(readAt) < Self.freshness {
            return cached
        }
        let window = DateInterval(
            start: now.addingTimeInterval(-Self.horizon),
            end: now.addingTimeInterval(Self.horizon)
        )
        cached = CalendarAgenda(busy: reader.busyBlocks(in: window))
        readAt = now
        return cached
    }
}
