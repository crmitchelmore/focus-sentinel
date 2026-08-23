import Foundation

/// Where a timebox is, right now (F-12).
///
/// ## Wall clock, deliberately
///
/// This is computed from a `DateProvider` — a **wall** clock — and not from `MonotonicClock`.
/// A timebox is a promise about the clock on the wall: if the Mac slept for an hour, that hour
/// is gone, and a timer that helpfully paused itself would be lying about how much of the
/// morning is left. e03's dwell measurement is the exact opposite and uses the monotonic
/// clock; the two are different types precisely so that a call site cannot confuse them.
///
/// There is no scheduling machinery here and none anywhere else (Court): the state is a pure
/// function of three values, so nothing has to fire for it to be correct.
public enum TimeboxState: Sendable, Equatable, Hashable {
    /// No timebox was set, or it has not been started. A real answer, not a missing one.
    case none
    /// Still inside the box.
    case running(remaining: Duration)
    /// Past the box, by this much.
    case overtime(over: Duration)

    /// The three presets the control offers, in seconds: 25, 50 and 90 minutes.
    /// Plus "None", which is the `nil` timebox rather than a fourth preset.
    public static let presetSeconds: [Int] = [25 * 60, 50 * 60, 90 * 60]

    /// The state of a timebox of `timeboxSeconds` started at `startedAt`, as of `now`.
    ///
    /// The boundary is closed on the overtime side: the instant the timebox is exactly spent
    /// the state is `.overtime(over: .zero)`, not `.running(remaining: .zero)`. A control
    /// showing "0:00 remaining" for a whole second while the box is already spent is the kind
    /// of small lie that makes people stop trusting the number.
    ///
    /// A `startedAt` in the future — the clock moved backwards, a timezone changed, NTP
    /// stepped — yields the full box rather than a negative overshoot.
    public static func state(timeboxSeconds: Int?, startedAt: Date?, now: Date) -> TimeboxState {
        guard let timeboxSeconds, timeboxSeconds > 0, let startedAt else { return .none }

        let elapsed = now.timeIntervalSince(startedAt)
        let remaining = Double(timeboxSeconds) - max(elapsed, 0)

        if remaining > 0 {
            return .running(remaining: .seconds(remaining))
        }
        return .overtime(over: .seconds(-remaining))
    }

    /// The state of a stored task's timebox.
    public static func state(for task: FocusSchemaV2.PriorityTask, now: Date) -> TimeboxState {
        state(timeboxSeconds: task.timeboxSeconds, startedAt: task.startedAt, now: now)
    }

    /// The magnitude the surface renders, whichever side of the boundary it is on.
    ///
    /// Display goes through `Duration.UnitsFormatStyle`, never string interpolation — which is
    /// why this hands back a `Duration` and not a formatted string.
    public var duration: Duration? {
        switch self {
        case .none: nil
        case .running(let remaining): remaining
        case .overtime(let over): over
        }
    }

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    public var isOvertime: Bool {
        if case .overtime = self { return true }
        return false
    }
}
