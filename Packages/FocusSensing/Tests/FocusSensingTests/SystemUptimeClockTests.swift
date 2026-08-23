import FocusCore
import Foundation
import Testing

@testable import FocusSensing

@Suite("System uptime clock")
struct SystemUptimeClockTests {
    @Test("Two reads inside one process are non-decreasing")
    func readsAreNonDecreasing() {
        let clock = SystemUptimeClock()
        let first = clock.uptimeSeconds
        let second = clock.uptimeSeconds

        #expect(second >= first)
        #expect(first > 0)
        #expect(first.isFinite)
    }

    @Test("The value lies within a plausible band of now minus kern.boottime")
    func valueAgreesWithBootTime() {
        guard let boot = BootIdentity.parse(BootIdentity.current()) else {
            Issue.record("this machine reports no boot identity")
            return
        }

        let bootInstant = Double(boot.seconds) + Double(boot.microseconds) / 1_000_000
        let wallSinceBoot = SystemDateProvider().now.timeIntervalSince1970 - bootInstant
        let uptime = SystemUptimeClock().uptimeSeconds

        // Not equality: probe P-99 measured the adjusted wall clock and the raw counter
        // **2.96 s** apart after 8.55 days of uptime on this very machine — about 4 ppm — so a
        // cross-check between them needs a tolerance, and zero is not it. Sixty seconds is
        // loose enough to survive a year of that drift and tight enough that a wrong timebase
        // ratio (which would be wrong by a factor of forty on Intel) could never pass it.
        #expect(abs(uptime - wallSinceBoot) < 60)
    }

    @Test("The timebase ratio is read from the platform, not written down")
    func timebaseIsReadFromMachTimebaseInfo() {
        var info = mach_timebase_info_data_t()
        #expect(mach_timebase_info(&info) == KERN_SUCCESS)

        // The assertion is that the shipped constant *equals what the machine says*, so a
        // hard-coded pair would fail here on any Mac whose ratio differs — which is every
        // Intel one. Recorded for this rig: numer 125, denom 3 (probe P-106).
        #expect(SystemUptimeClock.timebase.numerator == info.numer)
        #expect(SystemUptimeClock.timebase.denominator == info.denom)
        #expect(SystemUptimeClock.timebase.denominator != 0)
    }

    @Test("Ticks become seconds through that ratio and nothing else")
    func ticksConvertThroughTheTimebase() {
        let numerator = Double(SystemUptimeClock.timebase.numerator)
        let denominator = Double(SystemUptimeClock.timebase.denominator)

        // One second's worth of ticks, computed from the ratio, converts back to one second.
        let ticksPerSecond = 1_000_000_000 * denominator / numerator
        let seconds = SystemUptimeClock.seconds(fromTicks: UInt64(ticksPerSecond.rounded()))

        #expect(abs(seconds - 1) < 0.000_001)
        #expect(SystemUptimeClock.seconds(fromTicks: 0) == 0)
    }

    @Test("It satisfies the UptimeClock seam FocusCore declares")
    func satisfiesTheSeam() {
        let clock: any UptimeClock = SystemUptimeClock()
        #expect(clock.uptimeSeconds > 0)
    }

    @Test("It returns a Double, where MonotonicClock returns a Duration")
    func thetwoClocksCannotBeConfused() {
        // The types are the enforcement: `MonotonicClock` measures a duration inside one
        // process (its origin is taken in `init`, so its zero moves on every launch), and this
        // measures seconds since boot, which is comparable across processes on one boot. A
        // call site cannot substitute one for the other any more than it can substitute
        // either for a `Date`.
        let uptime: Double = SystemUptimeClock().uptimeSeconds
        let elapsed: Duration = SystemMonotonicClock().elapsed

        #expect(uptime > 0)
        #expect(elapsed >= .zero)
    }

    @Test("A sleep-inclusive anchor raises no anomaly when the wall clock moves with it")
    func theSleepInvariantHolds() {
        // The invariant this clock is chosen for, asserted against the pure reconciler: across
        // a four-hour sleep the wall clock and the anchor advance **together**, so the drift is
        // untouched and no anomaly is raised. `mach_continuous_time` keeps counting while the
        // Mac sleeps; `mach_absolute_time`/`SuspendingClock` would not, and an active-only
        // elapsed would make every overnight session report a fabricated figure.
        //
        // It cannot be measured here — this Mac has not slept in 8.55 days (probes P-86/P-98)
        // — so it is injected, which is exactly why the reconciler is a pure function.
        let started = Date(timeIntervalSince1970: 1_767_225_600)
        let anchor = SystemUptimeClock().uptimeSeconds
        let record = SessionRestoration.StoredSession(
            sessionID: UUID(),
            startedAt: started,
            phase: .focus,
            phaseChangedAt: started,
            uptimeAnchorSeconds: anchor,
            bootIdentity: BootIdentity.current()
        )

        let fourHours: Double = 4 * 60 * 60
        let restored = SessionRestoration.reconcile(
            record: record,
            now: started.addingTimeInterval(fourHours),
            nowUptimeSeconds: anchor + fourHours,
            bootIdentity: BootIdentity.current(),
            staleAfter: .seconds(24 * 60 * 60)
        )

        #expect(restored.elapsedWallSeconds == fourHours)
        #expect(restored.notes.contains(.clockAnomaly) == false)
    }
}
