import EventKit
import FocusCore
import Foundation

/// **The calendar, read as busy time and nothing else** (focus-cal).
///
/// Constructed only once the person switched the calendar on in Privacy *and* macOS answered
/// yes — `CalendarHost` decides that, and nothing else creates one, so a default install never
/// opens an event store.
///
/// What is read is the start and end of each event that makes the person busy. A title, a
/// location, a note, an attendee list — none of it is touched, held or stored: the agenda is a
/// list of intervals, rebuilt in memory and thrown away. An event does not make somebody busy
/// when it is all-day (a holiday is not a meeting), marked free, cancelled, or declined.
///
/// The one place this file is allowed to differ from a pure read is the change notification it
/// listens for, which macOS posts when any calendar changes; the host re-reads on it.
@MainActor
final class EventKitCalendarReader: CalendarReading {
    private let store = EKEventStore()
    private var observer: (any NSObjectProtocol)?

    /// - Parameter onChange: called on the main actor when macOS reports a calendar change.
    init(onChange: @escaping @MainActor () -> Void) {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { onChange() }
        }
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func busyBlocks(in interval: DateInterval) -> [CalendarBusyBlock] {
        let predicate = store.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: nil
        )
        return store.events(matching: predicate).compactMap { event in
            guard Self.makesThePersonBusy(event) else { return nil }
            return CalendarBusyBlock(start: event.startDate, end: event.endDate)
        }
    }

    private static func makesThePersonBusy(_ event: EKEvent) -> Bool {
        if event.isAllDay { return false }
        if event.availability == .free { return false }
        if event.status == .canceled { return false }
        if let me = event.attendees?.first(where: \.isCurrentUser),
           me.participantStatus == .declined {
            return false
        }
        return true
    }
}
