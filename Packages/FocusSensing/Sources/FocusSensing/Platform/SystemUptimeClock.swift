import FocusCore
import Foundation

/// Seconds since this boot, from `mach_continuous_time()` scaled by `mach_timebase_info()`.
///
/// ## Why this exists at all, rather than `MonotonicClock`
///
/// A restored session has to compare an anchor written by a **previous process** against a
/// reading taken by this one. Neither of e01's clocks can do that, and the review that caught
/// it did so by compiling the attempt:
///
/// * `Double(ContinuousClock().now)` **does not compile** — `ContinuousClock.Instant` conforms
///   to none of `BinaryInteger`, `BinaryFloatingPoint` or `StringProtocol` and exposes no
///   public numeric accessor at all (probe P-105). So a persisted anchor cannot be one.
/// * `SystemMonotonicClock` takes its origin in `init`, so its `elapsed` is *process-relative*
///   and its zero moves on every launch. It measures dwell inside one process, which is all it
///   was ever meant to do, and this epic does not touch it.
///
/// So the anchor is a plain `Double` of seconds since boot, and this is where it comes from.
/// **Measured end to end with this exact formula** (probe P-106): two separate process launches
/// two seconds apart read `741532.2641856666` and `741534.29358425` — a delta of `2.0294 s`
/// against a wall delta of `2.0294 s` — while `kern.boottime` read identically in both.
///
/// ## The timebase is read, never assumed
///
/// `mach_continuous_time()` counts in *ticks*, and the ratio that turns ticks into nanoseconds
/// is a property of the machine: `numer = 125`, `denom = 3` on this arm64 Mac, and different on
/// others. Hard-coding either would produce a figure that is silently wrong by a factor of
/// forty on Intel — so the ratio comes from `mach_timebase_info()`, once, and a test asserts
/// that it was read rather than written down.
///
/// ## It keeps counting across sleep, and that is the point
///
/// `mach_continuous_time` advances while the Mac sleeps, unlike `mach_absolute_time` and
/// `SuspendingClock`. That is the invariant the reconciler is built on: across a sleep the wall
/// clock and this advance **together**, so a four-hour sleep raises no anomaly and only a
/// wall-clock correction or a reboot makes them diverge. An active-only elapsed was rejected by
/// name, because it would contradict e02's ruling that a timebox is a promise about the clock on
/// the wall and would make every overnight session report a fabricated figure.
///
/// The divergence itself could not be *measured* here: this Mac is configured never to sleep
/// and had not slept in 8.55 days, so `mach_absolute_time` and `mach_continuous_time` agreed to
/// 8×10⁻⁸ s (probes P-86, P-98). That is precisely why the reconciler is a pure function
/// exercised by injected clocks rather than trusted to this machine.
public struct SystemUptimeClock: UptimeClock {
    public init() {}

    /// The machine's tick-to-nanosecond ratio, read from `mach_timebase_info()`.
    ///
    /// Cached in a `static let` because it is a constant of the hardware and the call is not
    /// free; exposed because the suite asserts it came from the platform. `(1, 1)` is the
    /// identity fallback for the call failing, which it does not do on any Mac this app runs
    /// on — and which is the only ratio that cannot make a reading wrong by an unknown factor.
    public static let timebase: (numerator: UInt32, denominator: UInt32) = {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom != 0 else {
            return (1, 1)
        }
        return (info.numer, info.denom)
    }()

    /// Seconds since boot. Comparable across processes on the same boot; meaningless across a
    /// reboot, which is what `BootIdentity` exists to detect.
    public var uptimeSeconds: Double {
        Self.seconds(fromTicks: mach_continuous_time())
    }

    /// Ticks to seconds, through the machine's own ratio.
    ///
    /// Separated so that the arithmetic is testable without the counter: given `numer = 125`
    /// and `denom = 3`, a tick count is `ticks × 125 / 3` nanoseconds.
    public static func seconds(fromTicks ticks: UInt64) -> Double {
        let nanoseconds = Double(ticks) * Double(timebase.numerator) / Double(timebase.denominator)
        return nanoseconds / 1_000_000_000
    }
}
