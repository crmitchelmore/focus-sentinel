import Foundation

/// Which of the three accepted outcomes a transition was.
///
/// Persisted as `SessionTransitionRecord.outcomeRaw`. `accepted` is an ordinary phase change.
/// The other two are the pause-cause outcomes, where the cause set changed and the phase did
/// not: those rows carry `fromRaw == toRaw` and no phase-change timestamp moves.
public enum SessionTransitionOutcome: String, Sendable, CaseIterable, Codable, Hashable {
    case accepted
    case causeAdded
    case causeRemoved
}

/// Everything the store needs to write one row of the transition log, and nothing else.
///
/// It is a value rather than a model object on purpose: the machine is pure — no clock, no
/// store, no I/O — so what it returns has to be something a caller can persist, hand to a
/// test, or throw away.
public struct SessionTransitionValue: Sendable, Equatable, Hashable {
    public let at: Date
    public let from: SessionPhase
    public let to: SessionPhase
    public let event: SessionEventKind
    /// The event's own reason or cause, if it carried one: a `PauseReason`, `BreakReason`,
    /// `DetourReason` or `InterruptionReason` raw value. `event` says which to read it as.
    public let reasonRaw: String?
    public let outcome: SessionTransitionOutcome

    public init(
        at: Date,
        from: SessionPhase,
        to: SessionPhase,
        event: SessionEventKind,
        reasonRaw: String?,
        outcome: SessionTransitionOutcome
    ) {
        self.at = at
        self.from = from
        self.to = to
        self.event = event
        self.reasonRaw = reasonRaw
        self.outcome = outcome
    }

    /// Whether this row moved the phase. False for both cause-set outcomes, which is exactly
    /// what makes them distinguishable in the timeline from a pause that actually happened.
    public var changesPhase: Bool { outcome == .accepted }
}

/// The result of offering an event to the machine.
///
/// A rejection is a value, never a thrown error and never a silent no-op: the caller records
/// it and the UI does nothing, because a rejected transition means what the user asked for was
/// already true.
///
/// `causeChanged` is the third outcome the pause-cause set requires: the pause causes changed
/// but the phase did not, so the store writes a `SessionTransitionRecord` with
/// `fromRaw == toRaw` and an `outcomeRaw` of `causeAdded`/`causeRemoved`, and no phase-change
/// timestamp moves.
public enum SessionTransition: Sendable, Equatable {
    case accepted(SessionState, SessionTransitionValue)
    case causeChanged(SessionState, SessionTransitionValue)
    case rejected(SessionRejection)

    /// The state to keep, or `nil` if the event was rejected and the old state stands.
    public var state: SessionState? {
        switch self {
        case .accepted(let state, _), .causeChanged(let state, _): state
        case .rejected: nil
        }
    }

    /// The row to write, or `nil` if there is none. Rejected transitions write **nothing**:
    /// a timeline that records what a caller attempted rather than what happened is a
    /// timeline that lies to the person reading it.
    public var value: SessionTransitionValue? {
        switch self {
        case .accepted(_, let value), .causeChanged(_, let value): value
        case .rejected: nil
        }
    }

    public var rejection: SessionRejection? {
        switch self {
        case .rejected(let reason): reason
        case .accepted, .causeChanged: nil
        }
    }
}
