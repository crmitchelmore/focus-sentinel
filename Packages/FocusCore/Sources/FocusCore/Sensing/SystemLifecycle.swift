import Foundation

/// What the Mac itself is doing, reduced from seven possibly-silent inputs into one typed
/// value.
///
/// Nothing else in the app reads the raw notifications. That matters because several of them
/// were measured **not to fire at all** on macOS 26.5.2: a `pmset displaysleepnow` produced no
/// `screensDidSleepNotification`, no `screensDidWake`, no `sessionDidResignActive` and no
/// `sessionDidBecomeActive` (probe P-88). An observer written as "when this notification
/// arrives, do that" would simply never have run.
///
/// What *was* observed, across a real lock and unlock (probe P-87):
/// `didActivateApplication` with `bundleIdentifier == "com.apple.loginwindow"`, and
/// `frontmostApplication` already agreeing — **1.5 ms before** the undocumented
/// `com.apple.screenIsLocked` distributed notification arrived. That is a **public,
/// documented API**, and it is the primary. The distributed notification may corroborate and
/// may accelerate; the app's behaviour must be identical if it never arrives, which is
/// asserted by a test that drives the whole table with that input removed.
public enum SystemLifecycle: String, Sendable, CaseIterable, Codable, Hashable {
    case active
    case screenLocked
    case displaysAsleep
    case systemAsleep
    case sessionInactive
    case poweringOff

    /// The pause cause this state owns — **and the only cause that can lift the pause it
    /// caused**.
    ///
    /// Every non-`.active` state maps to its own cause, and the return to `.active` sends
    /// `resumed(cause:)` with that same value and no other. That is what makes an unlock lift
    /// the lock's pause and leave every other pause standing.
    public var pauseCause: PauseReason? {
        switch self {
        case .active: nil
        case .screenLocked: .screenLocked
        case .displaysAsleep: .displaysAsleep
        case .systemAsleep: .systemAsleep
        case .sessionInactive: .sessionInactive
        // Powering off is the end of the session as far as the machine is concerned; the
        // system-restart cause is the one a later launch will find and reconcile against.
        case .poweringOff: .systemRestart
        }
    }

    public var isActive: Bool { self == .active }
}
