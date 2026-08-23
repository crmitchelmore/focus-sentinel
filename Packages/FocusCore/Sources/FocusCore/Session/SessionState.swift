import Foundation

/// The state the machine reduces over. `pauseCauses` is non-empty **if and only if** `phase`
/// is `.paused`, which the machine maintains and a test asserts on every accepted outcome.
///
/// Causes exist so that resume is authorised rather than ambient: whoever paused is the only
/// one who can lift that pause. Without this, waking the display resumes a pause the user
/// asked for, and leaving a password manager resumes a global pause — both of which are the
/// app overruling a person.
///
/// ## `endedAt` is read here and written elsewhere
///
/// The machine treats `endedAt` as an **input it respects and never assigns**: a session whose
/// `endedAt` is set rejects every event with `sessionEnded` before the table is consulted.
/// Closing a session is the store's act, in the same save as the terminal transition record,
/// because `endedAt` is a fact about the persisted row rather than about the reduction. That
/// keeps the two rejections independently meaningful — `terminal` is an in-memory phase that
/// nothing can leave, `sessionEnded` is a row that has been closed.
public struct SessionState: Sendable, Equatable, Hashable {
    public let phase: SessionPhase
    public let pauseCauses: Set<PauseReason>
    public let resumeTo: ResumablePhase?
    public let phaseChangedAt: Date
    public let endedAt: Date?

    public init(
        phase: SessionPhase,
        pauseCauses: Set<PauseReason> = [],
        resumeTo: ResumablePhase? = nil,
        phaseChangedAt: Date,
        endedAt: Date? = nil
    ) {
        self.phase = phase
        self.pauseCauses = pauseCauses
        self.resumeTo = resumeTo
        self.phaseChangedAt = phaseChangedAt
        self.endedAt = endedAt
    }

    /// A session as it is the moment it is created: focused, uncaused, unpaused.
    ///
    /// There is no `started` event, because starting a session does not act on a state — it
    /// produces the first one.
    public static func started(at instant: Date) -> SessionState {
        SessionState(phase: .focus, phaseChangedAt: instant)
    }

    /// The invariant, as something a test can read rather than something a comment claims.
    ///
    /// `pauseCauses` is non-empty exactly when the phase is `.paused`. The machine never
    /// produces a state that violates this; the suite asserts it on every accepted and
    /// cause-changed outcome, which is what stops the claim from decaying into a comment.
    public var pauseCausesInvariantHolds: Bool {
        (phase == .paused) == !pauseCauses.isEmpty
    }

    /// The cause set as it is persisted: sorted and comma-joined, so the encoding is
    /// deterministic and a two-cause pause reads back as the same two causes in the same
    /// order. `nil` when there are none, which is every non-paused phase.
    public var pauseCausesRaw: String? {
        guard !pauseCauses.isEmpty else { return nil }
        return pauseCauses.sorted().map(\.rawValue).joined(separator: ",")
    }

    /// The inverse of `pauseCausesRaw`, in the same exhaustive-decode spirit as
    /// `SessionPhase.decode(_:)`: a token this build does not recognise is dropped rather
    /// than crashing the launch of an app whose whole job is to be there when you open it.
    public static func decodePauseCauses(_ raw: String?) -> Set<PauseReason> {
        guard let raw, !raw.isEmpty else { return [] }
        return Set(raw.split(separator: ",").compactMap { token in
            PauseReason.allCases.first { $0.rawValue == token }
        })
    }
}
