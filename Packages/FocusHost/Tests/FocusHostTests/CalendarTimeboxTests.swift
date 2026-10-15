import FocusCore
import Foundation
import Testing
@testable import FocusHost

/// A calendar the test writes, counting how often it is read.
@MainActor
final class ScriptedCalendar: CalendarReading {
    var busy: [CalendarBusyBlock]
    private(set) var reads = 0

    init(busy: [CalendarBusyBlock]) {
        self.busy = busy
    }

    func busyBlocks(in interval: DateInterval) -> [CalendarBusyBlock] {
        reads += 1
        return busy.filter { $0.end > interval.start && $0.start < interval.end }
    }
}

/// **Focus blocks stay out of meetings** (focus-cal), driven through the live composition root
/// the way the cockpit drives it and read back from the state the cockpit draws.
@Suite("Calendar-aware timeboxes", .serialized)
@MainActor
struct CalendarTimeboxTests {
    private static func meeting(_ root: AppComposition, from start: TimeInterval, to end: TimeInterval) -> CalendarBusyBlock {
        let now = root.dateProvider.now
        return CalendarBusyBlock(start: now.addingTimeInterval(start), end: now.addingTimeInterval(end))
    }

    private static func rootWithPriority(busy: (AppComposition) -> [CalendarBusyBlock]) throws -> (AppComposition, UUID) {
        let root = CompositionRootTests.root()
        root.calendarHost.use(ScriptedCalendar(busy: busy(root)))
        root.cockpitActions.setPriority(intent: "Write the Q3 proposal for Acme", doneWhen: "Sent")
        root.refreshCockpit()
        let id = try #require(root.cockpitState.priority?.id)
        return (root, id)
    }

    @Test("a default install reads no calendar and refuses nothing")
    func theDefaultRefusesNothing() throws {
        let root = CompositionRootTests.root()
        defer { root.stop() }
        #expect(!root.calendarHost.isReading)
        root.cockpitActions.setPriority(intent: "Write the Q3 proposal for Acme", doneWhen: nil)
        let id = try #require(root.cockpitState.priority?.id)
        root.cockpitActions.setTimebox(taskID: id, seconds: 90 * 60)
        #expect(root.cockpitState.priority?.timeboxSeconds == 90 * 60)
        #expect(root.cockpitState.priority?.calendar == .unread)
    }

    @Test("a timebox that would run into a meeting is refused, and nothing is written")
    func aBlockIntoAMeetingIsRefused() throws {
        let (root, id) = try Self.rootWithPriority { [Self.meeting($0, from: 30 * 60, to: 60 * 60)] }
        defer { root.stop() }
        guard case .meetingAhead(_, let away) = root.cockpitState.priority?.calendar else {
            Issue.record("the cockpit was not told about the meeting ahead: \(String(describing: root.cockpitState.priority?.calendar))")
            return
        }
        #expect(away == 30 * 60)

        root.cockpitActions.setTimebox(taskID: id, seconds: 60 * 60)
        #expect(root.cockpitState.priority?.timeboxSeconds == nil, "a focus block was booked over a meeting")

        // The room before the meeting is still bookable.
        root.cockpitActions.setTimebox(taskID: id, seconds: 25 * 60)
        #expect(root.cockpitState.priority?.timeboxSeconds == 25 * 60)
    }

    @Test("no timebox starts while a meeting is under way, and clearing one is never refused")
    func noBlockDuringAMeeting() throws {
        let (root, id) = try Self.rootWithPriority { _ in [] }
        defer { root.stop() }
        root.cockpitActions.setTimebox(taskID: id, seconds: 25 * 60)
        #expect(root.cockpitState.priority?.timeboxSeconds == 25 * 60)

        let scripted = ScriptedCalendar(busy: [Self.meeting(root, from: -10 * 60, to: 20 * 60)])
        root.calendarHost.use(scripted)
        root.refreshCockpit()
        #expect(root.cockpitState.priority?.calendar.isInMeeting == true)

        root.cockpitActions.setTimebox(taskID: id, seconds: 15 * 60)
        #expect(root.cockpitState.priority?.timeboxSeconds == 25 * 60, "a focus block was started in a meeting")

        root.cockpitActions.setTimebox(taskID: id, seconds: nil)
        #expect(root.cockpitState.priority?.timeboxSeconds == nil, "clearing a timebox was refused")
    }

    @Test("a meeting closes gate 13 in the surroundings the nudge loop reads")
    func aMeetingReachesTheNudgeLoop() throws {
        let (root, _) = try Self.rootWithPriority { [Self.meeting($0, from: -5 * 60, to: 25 * 60)] }
        defer { root.stop() }
        #expect(root.nudgeSurroundings().isInCalendarMeeting)

        root.calendarHost.use(nil)
        #expect(!root.nudgeSurroundings().isInCalendarMeeting)
    }
}

@Suite("The calendar host", .serialized)
@MainActor
struct CalendarHostTests {
    @Test("one read serves the minute, and invalidating or a clock moved back reads again")
    func readsAreShared() {
        let now = NudgeHostFixture.reference
        let calendar = ScriptedCalendar(busy: [CalendarBusyBlock(start: now.addingTimeInterval(600), end: now.addingTimeInterval(1_800))])
        let host = CalendarHost()
        #expect(host.agenda(at: now) == .unread)

        host.use(calendar)
        let first = host.agenda(at: now)
        #expect(first.nextMeeting(after: now) != nil)
        _ = host.agenda(at: now.addingTimeInterval(30))
        #expect(calendar.reads == 1)

        _ = host.agenda(at: now.addingTimeInterval(CalendarHost.freshness + 1))
        #expect(calendar.reads == 2)

        _ = host.agenda(at: now)
        #expect(calendar.reads == 3, "a clock moved backwards was served a read from its future")

        host.invalidate()
        _ = host.agenda(at: now)
        #expect(calendar.reads == 4)

        host.use(nil)
        #expect(host.agenda(at: now) == .unread)
        #expect(!host.isReading)
    }
}
