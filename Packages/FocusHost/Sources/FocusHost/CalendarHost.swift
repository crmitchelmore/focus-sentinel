import FocusCore
import Foundation

/// **The calendar the rest of the app reads** (focus-cal), as one `CalendarAgenda`.
///
/// Holds the reader when there is one and caches what it read, so the five-second cockpit tick
/// and the nudge loop share one read rather than each asking EventKit. With no reader — the
/// switch is off, or macOS said no — the agenda is `.unread`, which refuses no timebox, closes
/// no gate and draws nothing: a default install behaves exactly as it did before this existed.
///
/// Outside sources (focus-ext) add their busy time through `useExternal(_:)`: the files
/// `focus-bridge` writes on a provider's behalf. Their blocks merge with the calendar's, so an
/// Outlook meeting pushed by a provider holds the question exactly as an EventKit one does. The
/// agenda is `.unread` only when there is no calendar reader and no source has written a file.
///
/// Nothing here is stored. The agenda is a window of busy intervals around now, held in memory
/// and replaced on the next read.
@MainActor
final class CalendarHost {
    /// How far either side of now is read, at least; the window also always covers the whole
    /// local day. Twelve hours covers the longest timebox several times over and a meeting that
    /// started this morning, without reading a person's week.
    static let horizon: TimeInterval = 12 * 60 * 60
    /// How long a read is trusted before the next one. A minute is well inside the minute's
    /// grace `CalendarOutlook` allows, and EventKit's change notification re-reads sooner.
    static let freshness: TimeInterval = 60

    /// The calendar whose local day the window always covers, so the day strip sees this
    /// evening's meetings at eight in the morning.
    var calendar: Calendar = .autoupdatingCurrent

    private var reader: (any CalendarReading)?
    private var external: (any ExternalTimeReading)?
    private var cached: [CalendarBusyBlock] = []
    private var readAt: Date?

    /// Point the host at a reader, or at none. Drops the cache either way, so a calendar the
    /// person just switched off is gone from the next refresh rather than a minute later.
    func use(_ reader: (any CalendarReading)?) {
        self.reader = reader
        invalidate()
    }

    /// Point the host at the outside sources' directory reader, or at none.
    func useExternal(_ external: (any ExternalTimeReading)?) {
        self.external = external
    }

    var isReading: Bool { reader != nil }
    var readsExternalTime: Bool { external != nil }

    /// Forget the last read; the next `agenda(at:)` reads again.
    func invalidate() {
        cached = []
        readAt = nil
    }

    /// The agenda around `now`. The calendar is read again when the last read is older than
    /// `freshness` or `now` has moved backwards past it (a clock change); the outside sources'
    /// reader is asked every time, and re-reads its files only when one changed.
    func agenda(at now: Date) -> CalendarAgenda {
        let midnight = calendar.startOfDay(for: now)
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight
        let window = DateInterval(
            start: min(now.addingTimeInterval(-Self.horizon), midnight),
            end: max(now.addingTimeInterval(Self.horizon), nextMidnight)
        )
        let outside = external?.busyBlocks(in: window)
        guard reader != nil || outside != nil else { return .unread }
        return CalendarAgenda(busy: calendarBlocks(at: now, window: window) + (outside ?? []))
    }

    private func calendarBlocks(at now: Date, window: DateInterval) -> [CalendarBusyBlock] {
        guard let reader else { return [] }
        if let readAt, now >= readAt, now.timeIntervalSince(readAt) < Self.freshness {
            return cached
        }
        cached = reader.busyBlocks(in: window)
        readAt = now
        return cached
    }
}
