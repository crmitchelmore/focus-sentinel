import Foundation

/// The whole of a session, as a value a surface can render.
///
/// The cockpit, the menu bar and (in e09) the notch all read this and nothing else. It carries
/// **no clock**: every elapsed and remaining figure is a function of an injected `now`, which
/// is what makes each of them snapshot-testable at a fixed instant and what keeps the promise
/// that there is no timer object anywhere in this programme.
public struct SessionSnapshot: Sendable, Equatable, Hashable {
    public let sessionID: UUID
    /// The priority this session is about, if there is one.
    public let taskID: UUID?
    public let phase: SessionPhase
    public let pauseCauses: Set<PauseReason>
    public let resumeTo: ResumablePhase?
    public let kind: SessionKind
    /// Never rewritten — not on restore, not on resume, not ever.
    public let startedAt: Date
    public let endedAt: Date?
    /// The countdown's length, for a `countdown` session.
    public let plannedSeconds: Int?
    /// The wall-clock moment to be finished by, for a `deadline` session.
    public let deadlineAt: Date?
    /// What restoring this session had to say about it, if it was restored at all.
    public let notes: Set<RestoredSession.ReconciliationNote>

    public init(
        sessionID: UUID,
        taskID: UUID? = nil,
        phase: SessionPhase,
        pauseCauses: Set<PauseReason> = [],
        resumeTo: ResumablePhase? = nil,
        kind: SessionKind = .openEnded,
        startedAt: Date,
        endedAt: Date? = nil,
        plannedSeconds: Int? = nil,
        deadlineAt: Date? = nil,
        notes: Set<RestoredSession.ReconciliationNote> = []
    ) {
        self.sessionID = sessionID
        self.taskID = taskID
        self.phase = phase
        self.pauseCauses = pauseCauses
        self.resumeTo = resumeTo
        self.kind = kind
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedSeconds = plannedSeconds
        self.deadlineAt = deadlineAt
        self.notes = notes
    }

    /// How long this session has been running, on the clock on the wall.
    ///
    /// A Mac that slept for an hour has spent that hour: a timebox is a promise about the wall
    /// clock, and an "active-only" figure would be a different and quieter promise than the
    /// one the user was made. A session that has ended reports the span it actually ran.
    public func elapsedWallSeconds(now: Date) -> Double {
        (endedAt ?? now).timeIntervalSince(startedAt)
    }

    /// Seconds left, for the two kinds that have an answer. `nil` for `openEnded`, which is a
    /// real answer and not a missing one. Negative once the session has run over — the app
    /// says so rather than clamping to zero and pretending nothing happened.
    public func remainingSeconds(now: Date) -> Double? {
        switch kind {
        case .openEnded:
            nil
        case .countdown:
            plannedSeconds.map { Double($0) - elapsedWallSeconds(now: now) }
        case .deadline:
            deadlineAt.map { $0.timeIntervalSince(now) }
        }
    }

    /// Whether the app may interrupt the person right now, as far as the *session* is
    /// concerned. e05's ladder must satisfy this **and** `FocusStatus.permitsIntervention`.
    public var permitsIntervention: Bool { phase.permitsIntervention }

    /// The causes the person cannot clear themselves.
    ///
    /// The Resume control is disabled, with a named explanation, while any of these is still
    /// held — because `resumed(cause: .user)` will be rejected `notPausedForThatCause` for
    /// anything the user did not set, and a button that silently does nothing is worse than a
    /// button that says why.
    public var causesTheUserCannotClear: Set<PauseReason> {
        pauseCauses.subtracting([.user])
    }

    /// Whether pressing Resume would actually resume anything.
    public var userMayResume: Bool {
        phase == .paused && pauseCauses == [.user]
    }
}
