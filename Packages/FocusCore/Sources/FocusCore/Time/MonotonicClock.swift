import Foundation

/// A source of *elapsed* time.
///
/// This is separate from `DateProvider` on purpose, and the split is made explicit now
/// rather than when the first session timer is written. Measuring a duration by
/// subtracting two `Date`s is the classic macOS trap: the wall clock moves when NTP
/// corrects it, when the machine sleeps, when the user edits the date. `MonotonicClock`
/// never moves backwards and never jumps.
///
/// The two protocols return different types — `Duration` here, `Date` there — so a call
/// site physically cannot confuse them.
public protocol MonotonicClock: Sendable {
    /// Time elapsed since this clock's origin. Never decreases.
    var elapsed: Duration { get }
}

/// The production elapsed-time source, backed by `ContinuousClock` (which keeps counting
/// across system sleep and is unaffected by wall-clock adjustments).
public struct SystemMonotonicClock: MonotonicClock {
    private let origin: ContinuousClock.Instant

    public init() {
        self.origin = ContinuousClock().now
    }

    public var elapsed: Duration {
        ContinuousClock().now - origin
    }
}

/// An elapsed-time source that only ever moves when a test tells it to.
///
/// A value type, so a test holds its own clock and no two tests can interfere.
public struct TestClock: MonotonicClock {
    public private(set) var elapsed: Duration

    public init(elapsed: Duration = .zero) {
        self.elapsed = elapsed
    }

    /// Advance the clock. `delta` must not be negative — a monotonic clock that can be
    /// wound back would defeat the point of having one.
    public mutating func advance(by delta: Duration) {
        precondition(delta >= .zero, "MonotonicClock must never move backwards")
        elapsed += delta
    }
}
