import Foundation

/// A calendar day, in the user's own timezone.
///
/// F-19 promises the ritual asks **once per local day**. That is only a well-defined sentence
/// once you say whose calendar decides — probe P-69: `2026-01-01T00:00:00Z` is the 1st of
/// January in UTC and also the 1st in `Pacific/Auckland` (where it is already 13:00), while an
/// instant twelve hours later is the 1st in UTC and the 2nd in Auckland. The calendar is
/// therefore a **parameter** everywhere in this type. A test that read `Calendar.current`
/// would pass in London and fail in Auckland, and `scripts/check-forbidden.sh` bans
/// `Calendar.current` and `TimeZone.current` outside this directory for exactly that reason.
///
/// The key is `yyyy-MM-dd`, built by hand rather than by a `DateFormatter`, because a
/// formatter's output depends on a locale and a calendar identifier and this string is a
/// database key, not text a person reads.
public struct LocalDay: Sendable, Equatable, Hashable, Comparable, Codable,
                        CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parse a stored key. Returns `nil` for anything that is not `yyyy-MM-dd`, so a corrupt
    /// or future-format value reads as "no ritual has run" rather than as a crash.
    public init?(key: String) {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]), parts[0].count == 4,
              let month = Int(parts[1]), parts[1].count == 2, (1...12).contains(month),
              let day = Int(parts[2]), parts[2].count == 2, (1...31).contains(day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The stored key: `2026-01-01`.
    public var key: String {
        let month = self.month < 10 ? "0\(self.month)" : "\(self.month)"
        let day = self.day < 10 ? "0\(self.day)" : "\(self.day)"
        return "\(paddedYear)-\(month)-\(day)"
    }

    private var paddedYear: String {
        let digits = String(abs(year))
        let padding = String(repeating: "0", count: max(0, 4 - digits.count))
        return (year < 0 ? "-" : "") + padding + digits
    }

    public var description: String { key }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// The local day an instant falls in, according to the given calendar.
    public static func containing(_ date: Date, calendar: Calendar) -> LocalDay {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return LocalDay(
            year: components.year ?? 0,
            month: components.month ?? 1,
            day: components.day ?? 1
        )
    }

    /// Today, from an injected clock and an injected calendar. Both, always.
    public static func today(calendar: Calendar, now: Date) -> LocalDay {
        containing(now, calendar: calendar)
    }

    /// Today, from a `DateProvider`. The form the app uses.
    public static func today(calendar: Calendar, dateProvider: some DateProvider) -> LocalDay {
        containing(dateProvider.now, calendar: calendar)
    }
}

/// Whether the daily priority ritual should be offered right now (F-19).
///
/// A banner, not a modal: a modal on launch is a toll booth. And it asks **once** — answering
/// *or* dismissing writes the day key, so a ritual that has been dealt with does not come back
/// at lunchtime.
///
/// **No notification authorisation is requested for this feature, ever** (Court). The whole
/// mechanism is a stored string and a comparison.
public enum DailyRitualGate {
    /// Should the banner appear?
    ///
    /// - Parameters:
    ///   - lastRitualLocalDay: `AppSettingsRecord.lastRitualLocalDay`, or `nil` if it has
    ///     never run. An unparseable value counts as never.
    ///   - today: the local day, from an injected calendar.
    ///   - isEnabled: the user's own switch. Off means off; the day key is not consulted.
    public static func shouldPrompt(
        lastRitualLocalDay: String?,
        today: LocalDay,
        isEnabled: Bool
    ) -> Bool {
        guard isEnabled else { return false }
        guard let stored = lastRitualLocalDay, let lastDay = LocalDay(key: stored) else {
            return true
        }
        return lastDay != today
    }

    /// What to write once the ritual has been answered **or** dismissed. The same value for
    /// both, which is what makes "it asks once" true rather than aspirational.
    public static func dayKeyAfterPrompting(_ today: LocalDay) -> String {
        today.key
    }
}
