import Foundation
import Testing

@testable import FocusCore

/// The calendar as busy blocks, and the rule that a focus block may not be scheduled into a
/// meeting (focus-cal).
@Suite("Calendar agenda")
struct CalendarAgendaTests {
    static let now = Date(timeIntervalSince1970: 1_767_225_600)   // 2026-01-01T00:00:00Z

    static func block(_ fromMinutes: Int, _ toMinutes: Int) -> CalendarBusyBlock {
        CalendarBusyBlock(
            start: now.addingTimeInterval(TimeInterval(fromMinutes * 60)),
            end: now.addingTimeInterval(TimeInterval(toMinutes * 60))
        )
    }

    @Test("blocks are sorted, empty ones dropped, and overlapping or touching ones merged")
    func normalisation() {
        let agenda = CalendarAgenda(busy: [
            Self.block(60, 90), Self.block(10, 20), Self.block(15, 30), Self.block(30, 40),
            Self.block(50, 50), Self.block(45, 44)
        ])
        #expect(agenda.busy == [Self.block(10, 40), Self.block(60, 90)])
        #expect(agenda.isRead)
    }

    @Test("an unread calendar says nothing and refuses nothing")
    func unreadIsSilent() {
        let outlook = CalendarAgenda.unread.outlook(at: Self.now)
        #expect(outlook == .unread)
        #expect(outlook.refusal(forTimeboxSeconds: 90 * 60) == nil)
        #expect(outlook.roomBeforeMeetingSeconds == nil)
        #expect(CalendarAgenda.unread.meeting(at: Self.now) == nil)
        // A read calendar with nothing on it is clear, not unread: the control may say so.
        #expect(CalendarAgenda(busy: []).outlook(at: Self.now) == .clear)
    }

    @Test("a meeting is under way from its first instant until, not including, its last")
    func halfOpenBlocks() {
        let agenda = CalendarAgenda(busy: [Self.block(0, 30)])
        #expect(agenda.meeting(at: Self.now) != nil)
        #expect(agenda.meeting(at: Self.now.addingTimeInterval(30 * 60)) == nil)
        #expect(
            agenda.outlook(at: Self.now.addingTimeInterval(10 * 60))
                == .inMeeting(endsAt: Self.block(0, 30).end, secondsLeft: 20 * 60)
        )
    }

    @Test("no timebox may start during a meeting, and clearing one is never refused")
    func duringAMeeting() {
        let outlook = CalendarAgenda(busy: [Self.block(-5, 25)]).outlook(at: Self.now)
        #expect(outlook.isInMeeting)
        #expect(outlook.refusal(forTimeboxSeconds: 60) == .duringMeeting(endsAt: Self.block(-5, 25).end))
        #expect(outlook.refusal(forTimeboxSeconds: nil) == nil)
        #expect(outlook.roomBeforeMeetingSeconds == nil)
    }

    @Test("a timebox that would run into the next meeting is refused, with a minute's grace")
    func runningIntoAMeeting() {
        let meeting = Self.block(40, 70)
        let outlook = CalendarAgenda(busy: [meeting]).outlook(at: Self.now)
        #expect(outlook == .meetingAhead(startsAt: meeting.start, secondsAway: 40 * 60))
        #expect(outlook.refusal(forTimeboxSeconds: 25 * 60) == nil)
        #expect(outlook.refusal(forTimeboxSeconds: 40 * 60) == nil)
        #expect(outlook.refusal(forTimeboxSeconds: 41 * 60) == nil, "inside the minute's grace")
        #expect(outlook.refusal(forTimeboxSeconds: 41 * 60 + 1) == .runsIntoMeeting(startsAt: meeting.start))
        #expect(outlook.refusal(forTimeboxSeconds: 50 * 60) == .runsIntoMeeting(startsAt: meeting.start))
    }

    @Test("the room before a meeting is whole minutes, and under five minutes is no room")
    func roomBeforeTheMeeting() {
        let ahead = CalendarAgenda(busy: [Self.block(40, 70)])
        // 40 minutes and 30 seconds away rounds down to 40 minutes.
        let outlook = ahead.outlook(at: Self.now.addingTimeInterval(-30))
        #expect(outlook.roomBeforeMeetingSeconds == 40 * 60)
        #expect(outlook.refusal(forTimeboxSeconds: outlook.roomBeforeMeetingSeconds) == nil)

        let tight = CalendarAgenda(busy: [Self.block(4, 10)]).outlook(at: Self.now)
        #expect(tight.roomBeforeMeetingSeconds == nil)
        #expect(CalendarOutlook.clear.roomBeforeMeetingSeconds == nil)
    }

    @Test("after the last meeting the calendar is clear")
    func afterTheLastMeeting() {
        let agenda = CalendarAgenda(busy: [Self.block(-90, -60)])
        #expect(agenda.outlook(at: Self.now) == .clear)
        #expect(agenda.nextMeeting(after: Self.now) == nil)
    }
}
