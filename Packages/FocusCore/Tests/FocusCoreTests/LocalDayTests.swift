import Foundation
import Testing

@testable import FocusCore

@Suite("Local day")
struct LocalDayTests {
    private func calendar(_ timeZoneIdentifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(
            TimeZone(identifier: timeZoneIdentifier),
            "\(timeZoneIdentifier) is not a timezone this machine knows"
        )
        return calendar
    }

    /// 2026-01-01T00:00:00Z — the reference instant. In UTC it is the 1st at midnight; in
    /// Auckland it is the 1st at 13:00. Probe P-69 measured both.
    private let newYearUTC = Date(timeIntervalSince1970: 1_767_225_600)

    @Test("the measured case: the same instant is the 1st in both UTC and Auckland")
    func measuredCase() throws {
        #expect(LocalDay.containing(newYearUTC, calendar: try calendar("UTC")).key == "2026-01-01")
        #expect(
            LocalDay.containing(newYearUTC, calendar: try calendar("Pacific/Auckland")).key
                == "2026-01-01"
        )
    }

    /// The reason the calendar is a parameter. Twelve hours later the two timezones disagree
    /// about what day it is, and a test that read `Calendar.current` would pass in London and
    /// fail in Auckland.
    @Test("twelve hours later the same instant is two different days")
    func theSameInstantIsTwoDays() throws {
        let midday = newYearUTC.addingTimeInterval(12 * 60 * 60)
        #expect(LocalDay.containing(midday, calendar: try calendar("UTC")).key == "2026-01-01")
        #expect(
            LocalDay.containing(midday, calendar: try calendar("Pacific/Auckland")).key
                == "2026-01-02"
        )
        #expect(
            LocalDay.containing(midday, calendar: try calendar("America/Los_Angeles")).key
                == "2026-01-01"
        )
    }

    @Test("local midnight is where the key changes, in each timezone's own time")
    func theKeyChangesAtLocalMidnight() throws {
        let auckland = try calendar("Pacific/Auckland")
        // 2026-01-01T10:59:59Z is 23:59:59 on the 1st in Auckland (UTC+13).
        let justBefore = newYearUTC.addingTimeInterval(10 * 60 * 60 + 59 * 60 + 59)
        let justAfter = justBefore.addingTimeInterval(1)
        #expect(LocalDay.containing(justBefore, calendar: auckland).key == "2026-01-01")
        #expect(LocalDay.containing(justAfter, calendar: auckland).key == "2026-01-02")

        let utc = try calendar("UTC")
        #expect(LocalDay.containing(justBefore, calendar: utc).key == "2026-01-01")
        #expect(LocalDay.containing(justAfter, calendar: utc).key == "2026-01-01")
    }

    @Test("today reads from an injected clock, never from the system one")
    func todayIsInjected() throws {
        let utc = try calendar("UTC")
        let clock = FixedDateProvider.reference
        #expect(LocalDay.today(calendar: utc, now: clock.now).key == "2026-01-01")
        #expect(LocalDay.today(calendar: utc, dateProvider: clock).key == "2026-01-01")
        #expect(
            LocalDay.today(
                calendar: utc,
                dateProvider: FixedDateProvider(now: newYearUTC.addingTimeInterval(86_400))
            ).key == "2026-01-02"
        )
    }

    @Test("keys round-trip, and a key that is not a day reads as no day at all")
    func keyRoundTrip() {
        for day in [
            LocalDay(year: 2026, month: 1, day: 1),
            LocalDay(year: 2026, month: 12, day: 31),
            LocalDay(year: 1999, month: 9, day: 9)
        ] {
            #expect(LocalDay(key: day.key) == day)
        }
        #expect(LocalDay(year: 2026, month: 1, day: 1).key == "2026-01-01")
        #expect(LocalDay(year: 2026, month: 12, day: 31).key == "2026-12-31")

        for bad in ["", "2026", "2026-01", "2026-1-1", "not-a-day", "2026-13-01", "2026-01-32"] {
            #expect(LocalDay(key: bad) == nil, "‘\(bad)’ was read as a day")
        }
    }

    @Test("days order chronologically")
    func ordering() {
        #expect(LocalDay(year: 2026, month: 1, day: 1) < LocalDay(year: 2026, month: 1, day: 2))
        #expect(LocalDay(year: 2026, month: 1, day: 31) < LocalDay(year: 2026, month: 2, day: 1))
        #expect(LocalDay(year: 2025, month: 12, day: 31) < LocalDay(year: 2026, month: 1, day: 1))
    }
}
