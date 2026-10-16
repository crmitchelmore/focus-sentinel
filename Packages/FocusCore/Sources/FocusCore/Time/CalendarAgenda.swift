import Foundation

/// **One stretch of time the person's calendar marks as busy** (focus-cal).
///
/// Two instants and nothing else. The reader that builds these sees an event's title, location,
/// notes and attendees and passes none of them on: a busy block is the whole of what the app
/// takes from a calendar, so there is nothing in this type that could be logged, stored or
/// exported by mistake.
public struct CalendarBusyBlock: Sendable, Equatable, Hashable, Comparable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var isEmpty: Bool { end <= start }

    public func contains(_ instant: Date) -> Bool { start <= instant && instant < end }

    public static func < (lhs: CalendarBusyBlock, rhs: CalendarBusyBlock) -> Bool {
        (lhs.start, lhs.end) < (rhs.start, rhs.end)
    }
}

/// **The busy part of the person's day, as a value** (focus-cal).
///
/// Normalised on construction — empty blocks dropped, the rest sorted and every overlapping or
/// touching pair merged — so that "in a meeting until" names the end of back-to-back meetings
/// rather than the end of the first, and every question below is a scan of disjoint intervals.
///
/// A pure value, like `TimeboxState`: nothing here reads a clock or a calendar store. The host
/// reads EventKit and hands this over; every answer takes `now` as an argument (Court: no
/// scheduling machinery).
public struct CalendarAgenda: Sendable, Equatable, Hashable {
    /// Disjoint, sorted busy blocks.
    public let busy: [CalendarBusyBlock]
    /// Whether a calendar was read at all. `false` is **not** "a free day": it is the switch
    /// being off, the grant being refused, or nothing having been read yet — and in every one of
    /// those the app behaves exactly as it did before the calendar existed.
    public let isRead: Bool

    public init(busy: [CalendarBusyBlock], isRead: Bool = true) {
        self.busy = Self.normalised(busy)
        self.isRead = isRead
    }

    /// Nothing read. The shipped default.
    public static let unread = CalendarAgenda(busy: [], isRead: false)

    /// The meeting under way at `now`, or `nil`.
    public func meeting(at now: Date) -> CalendarBusyBlock? {
        busy.first { $0.contains(now) }
    }

    /// The next meeting to start strictly after `now`, or `nil`.
    public func nextMeeting(after now: Date) -> CalendarBusyBlock? {
        busy.first { $0.start > now }
    }

    /// What the calendar says about the time from `now` on, for the timebox control.
    public func outlook(at now: Date) -> CalendarOutlook {
        guard isRead else { return .unread }
        if let current = meeting(at: now) {
            return .inMeeting(endsAt: current.end, secondsLeft: Self.seconds(from: now, to: current.end))
        }
        if let next = nextMeeting(after: now) {
            return .meetingAhead(startsAt: next.start, secondsAway: Self.seconds(from: now, to: next.start))
        }
        return .clear
    }

    /// Today's busy time, for the cockpit's day strip (focus-ext).
    ///
    /// The span is the working day — 08:00 to 18:00 — widened to whole hours to take in every
    /// busy block of the local day and `now`, and never past midnight either side.
    public func day(at now: Date, calendar: Calendar) -> CalendarDay {
        guard isRead else { return .unread }
        let midnight = calendar.startOfDay(for: now)
        guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: midnight) else { return .unread }
        let today = busy.compactMap { block -> CalendarBusyBlock? in
            let clipped = CalendarBusyBlock(start: max(block.start, midnight), end: min(block.end, nextMidnight))
            return clipped.isEmpty ? nil : clipped
        }
        let hour: (Int) -> Date = { calendar.date(byAdding: .hour, value: $0, to: midnight) ?? midnight }
        var start = min(hour(CalendarDay.workdayStartHour), now)
        var end = max(hour(CalendarDay.workdayEndHour), now)
        if let first = today.first { start = min(start, first.start) }
        if let last = today.last { end = max(end, last.end) }
        start = calendar.dateInterval(of: .hour, for: start)?.start ?? start
        if let endHour = calendar.dateInterval(of: .hour, for: end), endHour.start < end {
            end = endHour.end
        }
        start = max(start, midnight)
        end = min(end, nextMidnight)
        return .read(span: DateInterval(start: start, end: max(start, end)), busy: today, now: now)
    }

    private static func seconds(from start: Date, to end: Date) -> Int {
        max(0, Int(end.timeIntervalSince(start).rounded(.down)))
    }

    private static func normalised(_ blocks: [CalendarBusyBlock]) -> [CalendarBusyBlock] {
        var merged: [CalendarBusyBlock] = []
        for block in blocks.filter({ !$0.isEmpty }).sorted() {
            if let last = merged.last, block.start <= last.end {
                merged[merged.count - 1] = CalendarBusyBlock(start: last.start, end: max(last.end, block.end))
            } else {
                merged.append(block)
            }
        }
        return merged
    }
}

/// **What the calendar says about the next stretch of time** (focus-cal).
///
/// An enum rather than a struct on purpose: it travels on `PrioritySnapshot`, and the shell's
/// totality walk stops at an enum — so the whole outlook is one datum the cockpit's receipt
/// digests, rather than four members a table has to name.
///
/// The seconds are measured from the `now` the outlook was built at, which is the same instant
/// the timebox readout beside it was built at.
public enum CalendarOutlook: Sendable, Equatable, Hashable {
    /// No calendar was read. The timebox control draws exactly what it drew before.
    case unread
    /// Read, and nothing busy from now on.
    case clear
    /// A meeting is under way and ends at `endsAt`.
    case inMeeting(endsAt: Date, secondsLeft: Int)
    /// Free now; the next meeting starts at `startsAt`.
    case meetingAhead(startsAt: Date, secondsAway: Int)

    /// **How far a timebox may run into a meeting and still not count as running into it.**
    ///
    /// A minute, for two reasons. The outlook is built on the cockpit's refresh, so by the time
    /// somebody clicks it can be a few seconds stale; and the "until your meeting" choice is
    /// rounded down to whole minutes. Without the grace, the choice the control offered could be
    /// refused by the host a moment later for running a second over.
    public static let overlapGraceSeconds = 60

    /// **The shortest stretch worth offering as a timebox before a meeting.** Five minutes: less
    /// than that is not a focus block, it is the walk to the meeting room.
    public static let minimumRoomSeconds = 5 * 60

    /// Why a timebox of `seconds`, started now, is refused — or `nil` when it fits.
    ///
    /// Clearing a timebox (`nil`) is never refused: taking a commitment off the clock cannot
    /// collide with anything.
    public func refusal(forTimeboxSeconds seconds: Int?) -> TimeboxRefusal? {
        guard let seconds else { return nil }
        switch self {
        case .unread, .clear:
            return nil
        case .inMeeting(let endsAt, _):
            return .duringMeeting(endsAt: endsAt)
        case .meetingAhead(let startsAt, let secondsAway):
            return seconds > secondsAway + Self.overlapGraceSeconds
                ? .runsIntoMeeting(startsAt: startsAt)
                : nil
        }
    }

    /// The longest timebox that ends before the next meeting, in whole minutes — or `nil` when
    /// there is no meeting ahead, a meeting is under way, or the room is under five minutes.
    public var roomBeforeMeetingSeconds: Int? {
        guard case .meetingAhead(_, let secondsAway) = self else { return nil }
        let wholeMinutes = (secondsAway / 60) * 60
        return wholeMinutes >= Self.minimumRoomSeconds ? wholeMinutes : nil
    }

    /// Whether a meeting is under way.
    public var isInMeeting: Bool {
        if case .inMeeting = self { return true }
        return false
    }
}

/// **Today's busy time, as the cockpit's day strip draws it** (focus-ext).
///
/// An enum for the same reason as `CalendarOutlook`: it travels on `PrioritySnapshot` and the
/// shell's totality walk stops at an enum, so the whole day is one datum the receipt digests.
public enum CalendarDay: Sendable, Equatable, Hashable {
    /// No calendar and no outside source was read. The strip draws nothing.
    case unread
    /// The span the strip covers, the busy blocks inside it (clipped to the local day, disjoint
    /// and sorted), and the instant it was built at.
    case read(span: DateInterval, busy: [CalendarBusyBlock], now: Date)

    /// The working day the strip covers unless a busy block or now lies outside it.
    public static let workdayStartHour = 8
    public static let workdayEndHour = 18

    /// One busy block as fractions of the span, from 0 to 1, and whether it is over.
    public struct Segment: Sendable, Equatable, Hashable {
        public let start: Double
        public let end: Double
        public let isPast: Bool
    }

    /// The span, or `nil` when unread.
    public var span: DateInterval? {
        guard case .read(let span, _, _) = self else { return nil }
        return span
    }

    /// The busy blocks, empty when unread.
    public var busy: [CalendarBusyBlock] {
        guard case .read(_, let busy, _) = self else { return [] }
        return busy
    }

    /// Whether there is anything to draw: read, with at least one busy block today.
    public var hasBusyTime: Bool { !busy.isEmpty }

    /// Every busy block as fractions of the span.
    public var segments: [Segment] {
        guard case .read(let span, let busy, let now) = self, span.duration > 0 else { return [] }
        return busy.compactMap { block in
            let start = Self.fraction(of: block.start, in: span)
            let end = Self.fraction(of: block.end, in: span)
            guard end > start else { return nil }
            return Segment(start: start, end: end, isPast: block.end <= now)
        }
    }

    /// Where now falls in the span, from 0 to 1, or `nil` when unread.
    public var nowFraction: Double? {
        guard case .read(let span, _, let now) = self, span.duration > 0 else { return nil }
        return Self.fraction(of: now, in: span)
    }

    private static func fraction(of instant: Date, in span: DateInterval) -> Double {
        min(1, max(0, instant.timeIntervalSince(span.start) / span.duration))
    }
}

/// **Why a timebox was refused** (focus-cal). A focus block may not be scheduled into a meeting.
public enum TimeboxRefusal: Sendable, Equatable, Hashable {
    /// A meeting is under way; it ends at `endsAt`.
    case duringMeeting(endsAt: Date)
    /// The box would still be running when the meeting at `startsAt` begins.
    case runsIntoMeeting(startsAt: Date)
}

/// **The one seam that reads the person's calendar** (focus-cal).
///
/// Declared here so the host can hold "a calendar" without naming EventKit, and so every test
/// drives a double. Implemented once, in `FocusHost` (`EventKitCalendarReader`, beside the one
/// confined requester), and constructed only after the person switched the calendar grant on
/// and macOS said yes.
@MainActor
public protocol CalendarReading: AnyObject {
    /// The busy blocks overlapping `interval`. All-day events, events marked free, cancelled
    /// events and invitations the person declined are not busy, and are not returned.
    func busyBlocks(in interval: DateInterval) -> [CalendarBusyBlock]
}
