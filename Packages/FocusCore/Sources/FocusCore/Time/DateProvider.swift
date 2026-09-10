import Foundation

/// A source of wall-clock time.
///
/// Every piece of logic in this programme that needs to know *what time it is* takes a
/// `DateProvider` rather than calling `Date()`. That is what makes session boundaries,
/// break timers and "how long have you been off task" assertions deterministic in a test.
///
/// Wall-clock time is not the same thing as elapsed time and the two are deliberately
/// different protocols: see `MonotonicClock`. A wall clock can jump backwards (NTP, a
/// timezone change, the user changing the date) and must never be used to measure a
/// duration.
public protocol DateProvider: Sendable {
    /// The current wall-clock instant.
    var now: Date { get }
}

/// The production wall clock.
public struct SystemDateProvider: DateProvider {
    public init() {}

    public var now: Date { Date() }
}

/// A wall clock frozen at a known instant.
///
/// Reading `now` repeatedly returns the same value, which is what makes a test that
/// formats or compares dates reproducible.
public struct FixedDateProvider: DateProvider {
    public let now: Date

    public init(now: Date) {
        self.now = now
    }

    /// A fixed, arbitrary-but-stable instant used as the default in tests:
    /// 2026-01-01T00:00:00Z.
    public static let reference = FixedDateProvider(
        now: Date(timeIntervalSince1970: 1_767_225_600)
    )
}
