import Foundation
import SwiftData
import Testing

@testable import FocusCore

@Suite("Timebox state")
struct TimeboxStateTests {
    private let start = FixedDateProvider.reference.now
    private let twentyFiveMinutes = 25 * 60

    private func state(after seconds: TimeInterval, timebox: Int? = 25 * 60) -> TimeboxState {
        TimeboxState.state(
            timeboxSeconds: timebox,
            startedAt: start,
            now: start.addingTimeInterval(seconds)
        )
    }

    @Test("no timebox, or a timebox that was never started, is a real answer")
    func noTimebox() {
        #expect(TimeboxState.state(timeboxSeconds: nil, startedAt: start, now: start) == .none)
        #expect(TimeboxState.state(timeboxSeconds: 1_500, startedAt: nil, now: start) == .none)
        #expect(TimeboxState.state(timeboxSeconds: nil, startedAt: nil, now: start) == .none)
        // A zero or negative duration is not a timebox either.
        #expect(TimeboxState.state(timeboxSeconds: 0, startedAt: start, now: start) == .none)
        #expect(TimeboxState.state(timeboxSeconds: -60, startedAt: start, now: start) == .none)
        #expect(TimeboxState.none.duration == nil)
    }

    @Test("inside the box, the state is running and counts down")
    func running() {
        #expect(state(after: 0) == .running(remaining: .seconds(1_500)))
        #expect(state(after: 60) == .running(remaining: .seconds(1_440)))
        #expect(state(after: 1_499) == .running(remaining: .seconds(1)))
        #expect(state(after: 0).isRunning)
        #expect(state(after: 0).isOvertime == false)
    }

    /// The boundary is closed on the overtime side. A control that reads "0:00 remaining" for
    /// a whole second while the box is already spent is a small lie, and small lies about the
    /// clock are how people stop trusting the number.
    @Test("the boundary belongs to overtime, not to running")
    func theBoundary() {
        #expect(state(after: 1_499.999).isRunning)
        #expect(state(after: 1_500) == .overtime(over: .seconds(0)))
        #expect(state(after: 1_500).isOvertime)
        #expect(state(after: 1_501) == .overtime(over: .seconds(1)))
    }

    /// The wall-clock promise, stated as a test: a Mac that slept for four hours has spent
    /// four hours. A monotonic clock would have paused, and the timebox would be lying.
    @Test("a simulated four-hour sleep yields overtime, not a paused timer")
    func fourHourSleep() {
        let fourHours: TimeInterval = 4 * 60 * 60
        let after = state(after: fourHours)
        #expect(after.isOvertime)
        #expect(after == .overtime(over: .seconds(fourHours - Double(twentyFiveMinutes))))
        #expect(after.duration == .seconds(12_900))
    }

    @Test("a start in the future yields the full box rather than a negative overshoot")
    func clockMovedBackwards() {
        // NTP stepped, or the user changed the date. The honest answer is "you have the whole
        // box", not "you are minus ten minutes into it".
        #expect(state(after: -600) == .running(remaining: .seconds(1_500)))
    }

    @Test("the three presets are 25, 50 and 90 minutes, and None is not a fourth")
    func presets() {
        #expect(TimeboxState.presetSeconds == [1_500, 3_000, 5_400])
        #expect(TimeboxState.presetSeconds.count == 3)
    }

    @Test("a stored task's timebox reads through the same function")
    @MainActor
    func stateForAStoredTask() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        let task = FocusSchemaV3.PriorityTask(intent: "Timebox me", createdAt: start)
        context.insert(task)
        try context.save()

        #expect(TimeboxState.state(for: task, now: start) == .none)

        task.timeboxSeconds = 3_000
        task.startedAt = start
        try context.save()

        #expect(
            TimeboxState.state(for: task, now: start.addingTimeInterval(600))
                == .running(remaining: .seconds(2_400))
        )
        #expect(
            TimeboxState.state(for: task, now: start.addingTimeInterval(3_600))
                == .overtime(over: .seconds(600))
        )
    }

    @Test("the state is a pure function of its three inputs")
    func purity() {
        for seconds in stride(from: -600.0, through: 3_600.0, by: 137.0) {
            #expect(state(after: seconds) == state(after: seconds))
        }
    }
}
