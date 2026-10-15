import Foundation
import Testing

@testable import FocusCore

/// A snooze is about a subject, it is visible, it dies with the process — and it never silences
/// the glyph (R-87, F-61, F-64).
@Suite("Snooze and pause")
struct SnoozeStateTests {
    static let decoy = "com.chrismitchelmore.FocusDecoy"
    static let other = "com.apple.MobileSMS"

    // MARK: - A snooze is about one subject

    /// **The ruling this suite exists for.** Snoozing one application says nothing about any
    /// other. A snooze that silenced everything would be a global pause with a friendlier name.
    @Test("a snooze suppresses its own subject and no other")
    func snoozeIsSubjectScoped() {
        let snooze = SnoozeState.starting(subject: Self.decoy, for: .seconds(300), now: .zero)
        #expect(snooze.suppresses(subject: Self.decoy, at: .seconds(100)))
        #expect(!snooze.suppresses(subject: Self.other, at: .seconds(100)))

        let book = SnoozeBook.none.adding(snooze)
        #expect(book.suppresses(subject: Self.decoy, at: .seconds(100)))
        #expect(!book.suppresses(subject: Self.other, at: .seconds(100)))
    }

    /// No prefix matching, no "same company", no "probably the same thing". A guessed match is
    /// how a subject-scoped suppression quietly becomes a global one.
    @Test("a snooze matches its subject exactly and never approximately")
    func snoozeMatchesExactly() {
        let book = SnoozeBook.none.adding(
            SnoozeState.starting(subject: "com.apple.Safari", for: .seconds(300), now: .zero)
        )
        for candidate in [
            "com.apple.SafariTechnologyPreview", "com.apple", "com.apple.Safari.Helper",
            "COM.APPLE.SAFARI", "safari"
        ] {
            #expect(
                !book.suppresses(subject: candidate, at: .seconds(10)),
                "\(candidate) was suppressed by a snooze on com.apple.Safari"
            )
        }
        #expect(book.suppresses(subject: "com.apple.Safari", at: .seconds(10)))
    }

    /// **A snooze does not stop the ambient rung.** The glyph still tells the truth: a person
    /// who snoozed a panel asked for quiet, not for a lie.
    @Test("the ambient rung still reports the true status while a subject is snoozed")
    func ambientRungIsNeverSnoozed() {
        let book = SnoozeBook.none.adding(
            SnoozeState.starting(subject: Self.decoy, for: .seconds(900), now: .zero)
        )
        #expect(book.suppresses(subject: Self.decoy, at: .seconds(60)))

        // **The ruling, where it now lives** (focus-uru). `SnoozeBook.suppresses(rung:subject:at:)`
        // was one of four spellings of "not the ambient rung"; the book now answers only about a
        // subject and `SilenceSubject` answers about the rung, once, for all five fatigue gates.
        #expect(FatigueRefusal.Kind.snoozed.subject == .theAppSpeaking)
        #expect(!FatigueRefusal.Kind.snoozed.subject.silences(.ambient))
        #expect(FatigueRefusal.Kind.snoozed.subject.silences(.panel))

        // And the ruling driven through the controller a person actually meets, both ways round.
        func decide(_ rung: LadderRung.Kind, subject: String) -> FatigueDecision {
            FatigueController.decide(
                kind: .accusation,
                subject: subject,
                rung: rung,
                budget: .empty,
                fatigue: .fresh,
                snoozes: book,
                now: .seconds(60)
            )
        }
        #expect(
            decide(.ambient, subject: Self.decoy) == .permitted,
            "a snooze silenced the glyph, which is the one channel nobody objected to"
        )
        #expect(
            decide(.panel, subject: Self.decoy)
                == .refused(.snoozed(subject: Self.decoy, remaining: .seconds(840))),
            "a snooze did not stop the rung it was asked for"
        )

        // …and no rung is suppressed for a subject nobody snoozed.
        #expect(!book.suppresses(subject: Self.other, at: .seconds(60)))
        for rung in LadderRung.Kind.allCases {
            #expect(decide(rung, subject: Self.other) == .permitted)
        }
    }

    // MARK: - The countdown

    /// The countdown the menu bar draws, on the **monotonic** clock: a Mac that slept for an
    /// hour has not spent that hour ignoring somebody.
    @Test("the countdown runs down to zero and then the snooze lifts")
    func countdown() {
        let snooze = SnoozeState.starting(subject: Self.decoy, for: .seconds(600), now: .seconds(100))
        #expect(snooze.until == .seconds(700))
        #expect(snooze.remaining(at: .seconds(100)) == .seconds(600))
        #expect(snooze.remaining(at: .seconds(400)) == .seconds(300))
        #expect(snooze.remaining(at: .seconds(699)) == .seconds(1))
        #expect(snooze.isActive(at: .seconds(699)))

        // Half-open, like every other interval in this programme: at `until` it is over.
        #expect(!snooze.isActive(at: .seconds(700)))
        #expect(snooze.remaining(at: .seconds(700)) == .zero)
        #expect(snooze.remaining(at: .seconds(9000)) == .zero)
        #expect(!snooze.suppresses(subject: Self.decoy, at: .seconds(700)))
    }

    @Test("the three durations are F-61's own, and each produces its own countdown")
    func theThreeDurations() {
        for duration in InterventionPolicy.snoozeDurations {
            let snooze = SnoozeState.starting(subject: Self.decoy, for: duration, now: .zero)
            #expect(snooze.remaining(at: .zero) == duration)
            #expect(!snooze.isActive(at: duration))
        }
        #expect(InterventionPolicy.snoozeDurations.count == 3)
    }

    // MARK: - The book

    /// A second snooze for the same subject **replaces** the first: a person who clicks fifteen
    /// minutes twice gets fifteen minutes from the second click, not thirty.
    @Test("snoozing the same subject twice replaces rather than stacks")
    func snoozesDoNotStack() throws {
        let book = SnoozeBook.none
            .adding(SnoozeState.starting(subject: Self.decoy, for: .seconds(900), now: .zero))
            .adding(SnoozeState.starting(subject: Self.decoy, for: .seconds(300), now: .seconds(60)))

        let snooze = try #require(book.snooze(for: Self.decoy))
        #expect(snooze.until == .seconds(360))
        #expect(book.active(at: .seconds(60)).count == 1)
        #expect(!book.suppresses(subject: Self.decoy, at: .seconds(400)))
    }

    /// Cancel, from the popover. A suppression a person cannot see is a suppression they cannot
    /// trust, so it has to be one they can also lift.
    @Test("a snooze can be cancelled from the popover")
    func cancelling() {
        let book = SnoozeBook.none
            .adding(SnoozeState.starting(subject: Self.decoy, for: .seconds(900), now: .zero))
            .adding(SnoozeState.starting(subject: Self.other, for: .seconds(900), now: .zero))
        #expect(book.active(at: .zero).count == 2)

        let cancelled = book.cancelling(subject: Self.decoy)
        #expect(!cancelled.suppresses(subject: Self.decoy, at: .seconds(10)))
        #expect(cancelled.suppresses(subject: Self.other, at: .seconds(10)))
        #expect(cancelled.active(at: .zero).count == 1)
        #expect(cancelled.cancelling(subject: Self.other).isEmpty)
    }

    @Test("the popover lists what is running, longest remaining first")
    func activeListingIsOrdered() {
        let book = SnoozeBook.none
            .adding(SnoozeState.starting(subject: "a", for: .seconds(300), now: .zero))
            .adding(SnoozeState.starting(subject: "b", for: .seconds(900), now: .zero))
            .adding(SnoozeState.starting(subject: "c", for: .seconds(600), now: .zero))
        #expect(book.active(at: .zero).map(\.subject) == ["b", "c", "a"])

        // …and lifted snoozes drop out of the listing and out of a pruned book.
        #expect(book.active(at: .seconds(650)).map(\.subject) == ["b"])
        #expect(book.pruned(at: .seconds(650)).active(at: .seconds(650)).count == 1)
        #expect(book.pruned(at: .seconds(1000)).isEmpty)
    }

    // MARK: - Pause requests

    /// A pause request is **not a second pause concept**: it resolves to the one event e03's
    /// session machine already takes, and the phase it produces is e03's.
    @Test("every pause preset hands the same event to the shipped session machine")
    func pauseUsesTheShippedMachine() {
        for preset in InterventionPolicy.pauseDurations {
            #expect(PauseRequest(preset: preset).sessionEvent == .paused(cause: .user))
            #expect(PauseRequest(preset: preset).sessionEvent.kind == .paused)
        }
    }

    @Test("a fixed pause ends a fixed span later")
    func fixedPause() throws {
        let calendar = Self.londonCalendar
        let now = Self.instant(hour: 14, minute: 30)
        let request = PauseRequest(preset: .fixed(.seconds(900)))
        let expiry = try #require(request.expiry(now: now, calendar: calendar))
        #expect(expiry == now.addingTimeInterval(900))
        #expect(request.isWellFormed(now: now, calendar: calendar))
    }

    /// "Until 3 pm" is a promise about the clock on the wall, so it is wall clock — the
    /// opposite of a snooze, and deliberately so.
    @Test("an until-time pause needs a time, and it must be in the future")
    func untilTimePause() throws {
        let calendar = Self.londonCalendar
        let now = Self.instant(hour: 14, minute: 30)
        let threePM = Self.instant(hour: 15, minute: 0)

        let good = PauseRequest(preset: .untilTime, chosenTime: threePM)
        #expect(try #require(good.expiry(now: now, calendar: calendar)) == threePM)

        // A malformed request is refused rather than silently reinterpreted: an "until" with no
        // time and an "until" already past are both mistakes, not instructions.
        #expect(PauseRequest(preset: .untilTime).expiry(now: now, calendar: calendar) == nil)
        #expect(
            PauseRequest(preset: .untilTime, chosenTime: Self.instant(hour: 9, minute: 0))
                .expiry(now: now, calendar: calendar) == nil
        )
        #expect(!PauseRequest(preset: .untilTime).isWellFormed(now: now, calendar: calendar))
    }

    /// "The rest of today" is shorter in the evening, and it is the *user's* day — never a UTC
    /// day and never a fixed number of hours.
    @Test("the rest of the day ends at the start of tomorrow in the user's own calendar")
    func restOfDayPause() throws {
        let calendar = Self.londonCalendar
        let request = PauseRequest(preset: .restOfDay)

        let morning = try #require(
            request.expiry(now: Self.instant(hour: 9, minute: 0), calendar: calendar)
        )
        let evening = try #require(
            request.expiry(now: Self.instant(hour: 22, minute: 0), calendar: calendar)
        )
        #expect(morning == evening, "the rest of the day ends at the same instant all day")
        #expect(morning == calendar.startOfDay(for: Self.instant(hour: 9, minute: 0))
            .addingTimeInterval(86_400))

        // In Auckland the same instant belongs to a different day, and the answer moves with
        // the person's calendar rather than with the machine's.
        var auckland = Calendar(identifier: .gregorian)
        auckland.timeZone = try #require(TimeZone(identifier: "Pacific/Auckland"))
        let elsewhere = try #require(
            request.expiry(now: Self.instant(hour: 9, minute: 0), calendar: auckland)
        )
        #expect(elsewhere != morning)
    }

    /// Where the clocks change at midnight the day starts at 01:00, and "start of today plus a
    /// day" kept the 01:00 — an hour into tomorrow. Santiago went forward at midnight on
    /// 11 September 2022, so that day began at 01:00 and the next one at 00:00.
    @Test("the rest of the day ends at tomorrow's midnight on a day that began at 01:00")
    func restOfDayOnAMidnightClockChange() throws {
        var santiago = Calendar(identifier: .gregorian)
        santiago.timeZone = try #require(TimeZone(identifier: "America/Santiago"))
        // 12:00 local on the day of the change (UTC−3 after it).
        let now = try #require(ISO8601DateFormatter().date(from: "2022-09-11T15:00:00Z"))
        try #require(
            santiago.component(.hour, from: santiago.startOfDay(for: now)) == 1,
            "this zone's data no longer starts that day at 01:00, so this drives nothing"
        )

        let expiry = try #require(
            PauseRequest(preset: .restOfDay).expiry(now: now, calendar: santiago)
        )
        #expect(santiago.component(.hour, from: expiry) == 0)
        #expect(santiago.component(.day, from: expiry) == 12)
        #expect(expiry == santiago.startOfDay(for: expiry))
    }

    // MARK: - Helpers

    static var londonCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    /// A wall-clock instant on 2026-01-01 in the London calendar.
    static func instant(hour: Int, minute: Int) -> Date {
        let reference = Date(timeIntervalSince1970: 1_767_225_600)
        var components = londonCalendar.dateComponents([.year, .month, .day], from: reference)
        components.hour = hour
        components.minute = minute
        return londonCalendar.date(from: components) ?? reference
    }
}
