import Foundation
import Testing

@testable import FocusCore

@Suite("Time sources")
struct ClockTests {
    @Test("TestClock starts at zero and advances only when told")
    func testClockAdvancesOnlyWhenTold() {
        var clock = TestClock()
        #expect(clock.elapsed == .zero)

        // Reading does not advance it.
        _ = clock.elapsed
        _ = clock.elapsed
        #expect(clock.elapsed == .zero)

        clock.advance(by: .seconds(90))
        #expect(clock.elapsed == .seconds(90))

        clock.advance(by: .milliseconds(500))
        #expect(clock.elapsed == .seconds(90) + .milliseconds(500))
    }

    @Test("TestClock instances are independent values")
    func testClockInstancesAreIndependent() {
        var a = TestClock()
        let b = a
        a.advance(by: .seconds(10))

        #expect(a.elapsed == .seconds(10))
        #expect(b.elapsed == .zero)
    }

    @Test("FixedDateProvider.now is stable across reads")
    func fixedDateProviderIsStable() {
        let provider = FixedDateProvider.reference
        let first = provider.now
        let second = provider.now
        let third = provider.now

        #expect(first == second)
        #expect(second == third)
        #expect(first == Date(timeIntervalSince1970: 1_767_225_600))
    }

    @Test("SystemMonotonicClock never reports a negative elapsed time")
    func systemMonotonicClockIsMonotonic() {
        let clock = SystemMonotonicClock()
        let first = clock.elapsed
        let second = clock.elapsed

        #expect(first >= .zero)
        #expect(second >= first)
    }

    @Test("SystemDateProvider reports a plausible wall-clock instant")
    func systemDateProviderIsWallClock() {
        let provider = SystemDateProvider()
        // 2020-01-01. A wall clock that predates this is misconfigured, not merely slow.
        #expect(provider.now > Date(timeIntervalSince1970: 1_577_836_800))
    }

    /// The wall clock and the elapsed-time clock are different protocols returning
    /// different types. This test exists to pin that down: if someone ever "simplifies"
    /// `MonotonicClock` into returning a `Date`, the two become interchangeable at a call
    /// site and the duration-measurement trap re-opens.
    @Test("Wall-clock and monotonic sources cannot be confused at a call site")
    func clockTypesAreDistinct() {
        let wall: any DateProvider = FixedDateProvider.reference
        let monotonic: any MonotonicClock = TestClock(elapsed: .seconds(5))

        let instant: Date = wall.now
        let duration: Duration = monotonic.elapsed

        #expect(instant == FixedDateProvider.reference.now)
        #expect(duration == .seconds(5))
        #expect(type(of: instant) != type(of: duration))
    }
}
