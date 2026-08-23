import Foundation

/// A source of **seconds since this boot**.
///
/// ## Why this exists beside `MonotonicClock` rather than inside it
///
/// `MonotonicClock` measures a duration *within one process*: `SystemMonotonicClock` takes its
/// origin in `init`, so its zero moves on every launch. That is exactly right for dwell — how
/// long has this app been frontmost — and it is all it was ever meant to do.
///
/// It cannot supply a **cross-process** anchor, and neither can the type behind it. Measured
/// (probe P-105): `Double(ContinuousClock().now)` does not compile at all —
/// `ContinuousClock.Instant` conforms to none of `BinaryInteger`, `BinaryFloatingPoint` or
/// `StringProtocol` and exposes no public numeric accessor. A persisted anchor therefore
/// cannot be a `ContinuousClock.Instant`, and it cannot be a `MonotonicClock.elapsed` either.
///
/// So restoration takes its anchor from here: a plain `Double` of seconds since boot, which
/// `FocusSensing` implements over `mach_continuous_time()` scaled by `mach_timebase_info()`.
/// Measured end to end with the production formula (probe P-106): two separate process
/// launches two seconds apart read `741532.264` and `741534.294` — a delta of 2.0294 s against
/// a wall delta of 2.0294 s — while `kern.boottime` read `1786742847.869178` byte-identically
/// in both.
///
/// ## The two properties that make it usable, and the one that makes it dangerous
///
/// * It is **comparable across processes on the same boot**, which is the whole point.
/// * It **keeps counting across system sleep**, like `mach_continuous_time` and
///   `ContinuousClock` and unlike `mach_absolute_time` and `SuspendingClock`. That is the
///   invariant the reconciler is built on: across a sleep the wall clock and this advance
///   *together*, so a four-hour sleep raises no anomaly. An active-only elapsed was rejected
///   by name, because it would contradict e02's ruling that a timebox is a promise about the
///   clock on the wall and would make every overnight session report a fabricated figure.
/// * It is **meaningless across a reboot**, which is what the boot identity exists to detect.
///   Nothing here can tell you that on its own; comparing an anchor from one boot against a
///   reading from another is arithmetic on unrelated numbers.
///
/// `MonotonicClock` returns a `Duration` and this returns a `Double`, so a call site cannot
/// confuse them any more than it can confuse either with a `Date`.
///
/// The **implementation** deliberately lives in `FocusSensing`: reading `mach_continuous_time`
/// is a platform fact, and keeping it out of here is what keeps `FocusCore`'s import row three
/// words long.
public protocol UptimeClock: Sendable {
    /// Seconds since this boot. Comparable across processes on the same boot; meaningless
    /// across a reboot, which is what `bootIdentity` exists to detect.
    var uptimeSeconds: Double { get }
}

/// An uptime source that only ever moves when a test tells it to.
///
/// A value type, so a test holds its own clock and no two tests can interfere. It is what
/// makes the sleep case testable at all: this rig has not slept in 8.55 days (probe P-86), so
/// the divergence a sleep would produce cannot be *measured* here — it has to be injected.
public struct TestUptimeClock: UptimeClock {
    public private(set) var uptimeSeconds: Double

    public init(uptimeSeconds: Double = 0) {
        self.uptimeSeconds = uptimeSeconds
    }

    /// Advance the clock. `delta` must not be negative: an uptime that could be wound back
    /// would defeat the point of having one, and would let a test assert an anomaly the real
    /// substrate cannot produce.
    public mutating func advance(by delta: Double) {
        precondition(delta >= 0, "UptimeClock must never move backwards")
        uptimeSeconds += delta
    }
}
