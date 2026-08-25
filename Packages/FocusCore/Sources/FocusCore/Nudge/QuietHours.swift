import Foundation

/// Hours the person has told the app to keep quiet in.
///
/// ## The shipped default is **off**, and that is a ruling
///
/// There is no bundled `22:00–08:00`. A default window would be the app making a claim about a
/// person's life it has no evidence for, and the product boundary is that the priority outranks
/// the app's opinions (R-85). `InterventionPolicy.quietHoursDefault` is `nil`, and `QuietHours`
/// with no window suppresses nothing.
///
/// ## Quiet hours are **not** the system Focus, and the copy says so
///
/// P-137 measured that `~/Library/DoNotDisturb/DB/Assertions.json` does not exist on this
/// machine and `ModeConfigurations.json` is not readable by this process; standing condition 8
/// forbids the private route in any case. So the app makes **no claim** to know the system
/// Focus state. The notification rung honours it for free, because `UNUserNotificationCenter`
/// does; the in-app rungs honour *this*, which is the app's own window and the person's own
/// setting. Claiming to respect a Focus mode we cannot read would be a false capability claim.
///
/// ## Wall clock, wrapping, and somebody else's calendar
///
/// The window is a pair of minute-of-day offsets and `end` may be **less** than `start`, which
/// is a window that crosses midnight and is the common case. Membership is evaluated against
/// the *wall-clock* hour and minute in an injected `Calendar` — never against elapsed minutes
/// since midnight — so a day with a DST transition in it still means 22:00 when the person set
/// 22:00. The calendar is a parameter everywhere, exactly as `LocalDay`'s is, because a test
/// that read `Calendar.current` would pass in London and fail in Auckland (e02's P-69), and
/// `check-forbidden.sh` bans `Calendar.current` outside `FocusCore/Time/`.
public struct QuietHours: Sendable, Equatable, Hashable {
    /// The window, or `nil` for "off" — the shipped default.
    public let window: QuietHoursWindow?

    public init(window: QuietHoursWindow?) {
        self.window = window
    }

    /// What ships: no window at all.
    public static let off = QuietHours(window: InterventionPolicy.quietHoursDefault)

    /// Whether quiet hours are configured at all.
    public var isEnabled: Bool { window != nil }

    /// Whether `date` falls inside the window, in the given calendar's timezone.
    ///
    /// The interval is half-open `[start, end)`, so a window ending at 08:00 is over at 08:00
    /// and two adjacent windows would partition a day exactly. A window whose start equals its
    /// end is **empty**, not all-day: "quiet from 9 to 9" is a mistake somebody made, and
    /// reading it as twenty-four hours of silence would be the app choosing the most
    /// interventionist interpretation of an ambiguous setting, which is the opposite of what
    /// this type is for.
    public func isQuiet(at date: Date, calendar: Calendar) -> Bool {
        guard let window else { return false }
        guard let minuteOfDay = Self.minuteOfDay(of: date, calendar: calendar) else {
            // A calendar with no minutes in it is not a calendar this app can reason about.
            // Answer "not quiet" rather than silently muting the guardian for ever.
            return false
        }

        let start = window.startMinuteOfDay
        let end = window.endMinuteOfDay
        if start == end { return false }
        if start < end { return minuteOfDay >= start && minuteOfDay < end }
        // Wraps midnight: everything at or after `start`, and everything before `end`.
        return minuteOfDay >= start || minuteOfDay < end
    }

    /// The wall-clock minute of the day, `0…(hours × minutes − 1)`, in the given calendar.
    ///
    /// Read from `hour` and `minute` components rather than as elapsed minutes since
    /// `startOfDay`, because those two disagree on the two days a year a timezone changes
    /// offset — and on those days the person still means the time on their clock.
    static func minuteOfDay(of date: Date, calendar: Calendar) -> Int? {
        guard let minutesPerHour = calendar.maximumRange(of: .minute)?.count else { return nil }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return nil }
        return hour * minutesPerHour + minute
    }

    /// A window from two wall-clock times, in the given calendar.
    ///
    /// Provided so that a settings pane and a test can both say "22:00 to 08:00" without either
    /// of them doing the arithmetic — and so that the arithmetic exists in exactly one place.
    public static func window(
        fromHour startHour: Int,
        minute startMinute: Int,
        toHour endHour: Int,
        minute endMinute: Int,
        calendar: Calendar
    ) -> QuietHoursWindow? {
        guard let minutesPerHour = calendar.maximumRange(of: .minute)?.count,
              let hoursPerDay = calendar.maximumRange(of: .hour)?.count
        else { return nil }
        guard (0..<hoursPerDay).contains(startHour), (0..<hoursPerDay).contains(endHour),
              (0..<minutesPerHour).contains(startMinute),
              (0..<minutesPerHour).contains(endMinute)
        else { return nil }
        return QuietHoursWindow(
            startMinuteOfDay: startHour * minutesPerHour + startMinute,
            endMinuteOfDay: endHour * minutesPerHour + endMinute
        )
    }
}
