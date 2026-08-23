import Foundation

/// Why the machine declined an event.
///
/// Every rejection is **named**. "Illegal transitions are rejected" is not a specification;
/// *this* cell under *these* causes yielding *that* reason is, and the suite asserts all
/// thirty-three of them individually.
///
/// A rejection is a value, never a thrown error and never a silent no-op: the caller records
/// it and the UI does nothing, because a rejected transition means what the user asked for
/// was already true.
public enum SessionRejection: String, Sendable, CaseIterable, Codable, Hashable {
    /// The phase is `interrupted` or `complete`. Terminal is terminal.
    case terminal
    /// The persisted row is closed (`endedAt != nil`). Checked before the table.
    case sessionEnded
    /// The transition would not change the phase — or, for a pause cause, would not change
    /// the cause set either. A transition that changes nothing is a bug in the caller, and
    /// accepting it would put a meaningless row in the timeline.
    case alreadyInPhase
    /// A resume was offered to a session that is not paused at all.
    case notPaused
    /// `resumed(cause:)` named a cause this session is not paused for. The pause stands.
    case notPausedForThatCause
    /// A paused session is inert: no detour, no break, and no ending either of them.
    case pausedSessionIsInert
    case noDetourInProgress
    case noBreakInProgress
    /// A break may be started only from `focus`. End the detour first — the UI does both in
    /// one click, and the machine records two transitions, which is what makes the timeline
    /// honest about what happened.
    case endDetourFirst
    case endBreakFirst
    /// The event's instant precedes the last phase change. Probe P-99 measured 2.96 s of
    /// wall-versus-monotonic drift on this machine over 8.55 days of uptime, so an NTP
    /// correction during a session is an ordinary event — and must not be allowed to write a
    /// transition that appears to have happened before the one it follows.
    case clockWentBackwards
}
