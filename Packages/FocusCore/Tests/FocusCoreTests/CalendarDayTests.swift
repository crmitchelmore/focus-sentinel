import Foundation
import Testing

@testable import FocusCore

/// Today's busy time, as the cockpit's day strip draws it (focus-ext).
@Suite("Calendar day strip")
struct CalendarDayTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    /// 2026-10-19 at `hour:minute`, London time.
    static func at(_ hour: Int, _ minute: Int = 0, day: Int = 19) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    static func block(_ from: Date, _ to: Date) -> CalendarBusyBlock {
        CalendarBusyBlock(start: from, end: to)
    }

    @Test("unread draws nothing")
    func unread() {
        let day = CalendarAgenda.unread.day(at: Self.at(10), calendar: Self.calendar)
        #expect(day == .unread)
        #expect(day.segments.isEmpty)
        #expect(day.nowFraction == nil)
        #expect(!day.hasBusyTime)
    }

    @Test("a read day with nothing busy has a span and nothing to draw")
    func clearDay() {
        let day = CalendarAgenda(busy: []).day(at: Self.at(10), calendar: Self.calendar)
        #expect(day.span == DateInterval(start: Self.at(8), end: Self.at(18)))
        #expect(!day.hasBusyTime)
    }

    @Test("the working day is the span, blocks are fractions of it, and past ones are marked")
    func fractions() {
        let agenda = CalendarAgenda(busy: [
            Self.block(Self.at(9), Self.at(9, 30)),
            Self.block(Self.at(13), Self.at(15, 30))
        ])
        let day = agenda.day(at: Self.at(13), calendar: Self.calendar)
        #expect(day.span == DateInterval(start: Self.at(8), end: Self.at(18)))
        #expect(day.segments == [
            CalendarDay.Segment(start: 0.1, end: 0.15, isPast: true),
            CalendarDay.Segment(start: 0.5, end: 0.75, isPast: false)
        ])
        #expect(day.nowFraction == 0.5)
    }

    @Test("an early meeting, a late one and now widen the span to whole hours")
    func widening() {
        let agenda = CalendarAgenda(busy: [
            Self.block(Self.at(7, 30), Self.at(8, 15)),
            Self.block(Self.at(18, 30), Self.at(19, 10))
        ])
        #expect(agenda.day(at: Self.at(12), calendar: Self.calendar).span
            == DateInterval(start: Self.at(7), end: Self.at(20)))
        #expect(CalendarAgenda(busy: [Self.block(Self.at(9), Self.at(10))])
            .day(at: Self.at(21, 20), calendar: Self.calendar).span
            == DateInterval(start: Self.at(8), end: Self.at(22)))
    }

    @Test("blocks from other days are dropped and a block over midnight is clipped to today")
    func clipping() {
        let agenda = CalendarAgenda(busy: [
            Self.block(Self.at(10, day: 18), Self.at(11, day: 18)),
            Self.block(Self.at(23, day: 19), Self.at(1, day: 20)),
            Self.block(Self.at(9, day: 20), Self.at(10, day: 20))
        ])
        let day = agenda.day(at: Self.at(12), calendar: Self.calendar)
        #expect(day.busy == [Self.block(Self.at(23), Self.at(0, day: 20))])
        #expect(day.span == DateInterval(start: Self.at(8), end: Self.at(0, day: 20)))
    }
}
