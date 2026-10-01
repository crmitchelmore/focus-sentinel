import Foundation

/// Why a session is paused — **and who is allowed to un-pause it**.
///
/// This is not a label. It is the pause-authority token: the value handed to
/// `SessionEvent.paused(cause:)` is the only value that can later clear that pause through
/// `SessionEvent.resumed(cause:)`, and a mismatched resume is rejected
/// `notPausedForThatCause` rather than quietly taking the pause over.
///
/// Without it, waking the display would resume a pause the *user* asked for, and leaving a
/// password manager would clear a *global* pause — in both cases the app overruling a person.
/// A session may hold several causes at once and needs every one of them cleared.
public enum PauseReason: String, Sendable, CaseIterable, Codable, Hashable, Comparable {
    /// The person pressed Pause. Only they can lift it.
    case user
    /// The frontmost application is on the sensitive list, so the app stood down (F-118).
    case sensitiveApp
    /// The global sensing switch is off (F-119). Lifted only by turning it back on.
    case globalPause
    /// The screen locked. Detected primarily by `com.apple.loginwindow` becoming frontmost —
    /// a public API — and corroborated, never decided, by the distributed notification.
    case screenLocked
    /// The displays went to sleep.
    case displaysAsleep
    /// The Mac went to sleep.
    case systemAsleep
    /// The login session resigned active (fast user switching).
    case sessionInactive
    /// The app was relaunched more than `staleAfter` since the last phase change. A person
    /// who has been away for an hour did not spend it working.
    case relaunch
    /// The Mac restarted while this session was running: the boot identity differs, so the
    /// uptime anchor belongs to another boot and was discarded.
    case systemRestart

    /// Ordered by raw value, so a cause set has one deterministic persisted encoding.
    public static func < (lhs: PauseReason, rhs: PauseReason) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// **Whether the person may lift this pause from the cockpit** (focus-mmty).
    ///
    /// Three causes are theirs to clear. `.user` because they set it. `.relaunch` and
    /// `.systemRestart` because nothing else ever will: they are raised by
    /// `SessionRestoration.reconcile` on the launch that found the session, and the whole point
    /// of that pause is that *one click puts the person back where they were*. Before this
    /// property the Resume control sent `resumed(cause: .user)` and nothing else, so a session
    /// that came back from a reboot sat under "Paused because this Mac restarted" with a
    /// disabled Resume and a sentence promising it would clear — which it never could.
    ///
    /// The other five belong to the lifecycle: the lock, the displays, the Mac's sleep, the
    /// login session and the global switch each lift their own pause when their condition
    /// ends, and a person pressing Resume against one of those would be the app letting them
    /// overrule a fact about the machine.
    public var isClearedByThePerson: Bool {
        switch self {
        case .user, .relaunch, .systemRestart: true
        case .sensitiveApp, .globalPause, .screenLocked, .displaysAsleep, .systemAsleep, .sessionInactive: false
        }
    }
}

/// Why a break was started.
///
/// `.idle` is declared now, unused, so that e05's F-67 idle→break policy adds a behaviour and
/// not a state.
public enum BreakReason: String, Sendable, CaseIterable, Codable, Hashable {
    case user
    case idle
}

/// Why a detour was started. One case today; the enum exists so that adding a second is a
/// case and not a schema change.
public enum DetourReason: String, Sendable, CaseIterable, Codable, Hashable {
    case user
}

/// Why a session was interrupted.
public enum InterruptionReason: String, Sendable, CaseIterable, Codable, Hashable {
    case user
    case priorityChanged
    case appQuit
    case systemRestart
    case timeboxAbandoned
}

/// The eight events the machine understands, without their payloads.
///
/// Stored as `SessionTransitionRecord.eventRaw`, so the raw values are part of the persisted
/// vocabulary and never change.
public enum SessionEventKind: String, Sendable, CaseIterable, Codable, Hashable {
    case detourStarted
    case detourEnded
    case breakStarted
    case breakEnded
    case paused
    case resumed
    case interrupted
    case completed
}

/// Something that happens to a session that already exists.
///
/// **Starting a session is not an event on an existing state** — it *creates* one, in
/// `.focus`. That is why there are eight events and not nine: an event is offered to a state,
/// and before a session exists there is no state to offer it to.
///
/// `paused` and `resumed` both carry a `PauseReason`, and the reason is load-bearing rather
/// than descriptive: see `PauseReason`.
public enum SessionEvent: Sendable, Equatable, Hashable {
    case detourStarted(reason: DetourReason)
    case detourEnded
    case breakStarted(reason: BreakReason)
    case breakEnded
    case paused(cause: PauseReason)
    case resumed(cause: PauseReason)
    case interrupted(reason: InterruptionReason)
    case completed

    public var kind: SessionEventKind {
        switch self {
        case .detourStarted: .detourStarted
        case .detourEnded: .detourEnded
        case .breakStarted: .breakStarted
        case .breakEnded: .breakEnded
        case .paused: .paused
        case .resumed: .resumed
        case .interrupted: .interrupted
        case .completed: .completed
        }
    }

    /// The event's own reason or cause as it is persisted, or `nil` for the four events that
    /// carry none. One column serves all four vocabularies because a row's `eventRaw` says
    /// which one to read it as.
    public var reasonRaw: String? {
        switch self {
        case .detourStarted(let reason): reason.rawValue
        case .breakStarted(let reason): reason.rawValue
        case .paused(let cause): cause.rawValue
        case .resumed(let cause): cause.rawValue
        case .interrupted(let reason): reason.rawValue
        case .detourEnded, .breakEnded, .completed: nil
        }
    }

    /// Whether a person asked for this, as opposed to the system deciding it.
    ///
    /// The undo journal reads this: user-initiated operations are undoable, and system-driven
    /// ones deliberately are not, because an auto-pause is not something a person meant to do
    /// and offering to undo it would be offering to undo the world.
    public var isUserInitiated: Bool {
        switch self {
        case .detourStarted(let reason): reason == .user
        case .breakStarted(let reason): reason == .user
        case .paused(let cause): cause == .user
        case .resumed(let cause): cause == .user
        case .interrupted(let reason): reason == .user
        case .detourEnded, .breakEnded, .completed: true
        }
    }
}
