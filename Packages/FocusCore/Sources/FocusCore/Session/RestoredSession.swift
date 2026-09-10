import Foundation

/// What restoring a persisted session produced.
///
/// `startedAt` is carried through untouched. Every elapsed figure the user sees is derived
/// from it and from an injected wall clock — there is no timer object anywhere in this
/// programme, which is the strongest available form of "never blindly restarts its timer".
public struct RestoredSession: Sendable, Equatable, Hashable {
    public let sessionID: UUID
    public let startedAt: Date
    public let phase: SessionPhase
    public let resumeTo: ResumablePhase?
    /// The pause causes the restored session holds — `[.relaunch]`, `[.systemRestart]`, or
    /// whatever was persisted. A single matching `resumed(cause:)` clears a restoration
    /// pause; a session that was *also* paused for another reason before the relaunch comes
    /// back holding both, and needs both cleared.
    public let pauseCauses: Set<PauseReason>
    public let elapsedWallSeconds: Double
    public let notes: Set<ReconciliationNote>
    /// How far the wall clock and the uptime anchor disagreed, in seconds, when there was an
    /// anchor to compare against and it belonged to this boot.
    ///
    /// `ReconciliationNote` is a `String`-raw enum so that it can be persisted and rendered as
    /// a token, which leaves it no room for an associated value; the magnitude the ruling asks
    /// the app to report therefore rides here, beside the note rather than inside it. It is
    /// `nil` exactly when no drift was computed — no anchor, or a different boot, where
    /// differencing two unrelated numbers would manufacture a figure rather than measure one.
    public let driftSeconds: Double?

    public init(
        sessionID: UUID,
        startedAt: Date,
        phase: SessionPhase,
        resumeTo: ResumablePhase?,
        pauseCauses: Set<PauseReason>,
        elapsedWallSeconds: Double,
        notes: Set<ReconciliationNote>,
        driftSeconds: Double? = nil
    ) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.phase = phase
        self.resumeTo = resumeTo
        self.pauseCauses = pauseCauses
        self.elapsedWallSeconds = elapsedWallSeconds
        self.notes = notes
        self.driftSeconds = driftSeconds
    }

    public enum ReconciliationNote: String, Sendable, CaseIterable, Codable, Hashable {
        /// The boot identity differed: the machine restarted while this session was running,
        /// so the monotonic anchor belongs to another boot and was discarded.
        case rebootedDuringSession
        /// More than `staleAfter` passed since the last phase change; the session comes back
        /// paused with `resumeTo` set, because a person who has been away for an hour did not
        /// spend it working.
        case restoredStale
        /// The wall clock and the uptime anchor disagree by more than the tolerance. The
        /// wall-clock figure is still what is shown — a timebox is a promise about the clock
        /// on the wall — but the user is told the clock moved rather than shown a number the
        /// app knows is suspect. Measured basis for the tolerance: 2.96 s of drift over 8.55
        /// days of uptime on the rig (probe P-99).
        ///
        /// A **system sleep does not raise this**: the anchor is `mach_continuous_time`, which
        /// keeps counting while the Mac sleeps, so both terms grow together and a four-hour
        /// sleep leaves the drift untouched. What raises it is a wall-clock correction — NTP,
        /// or a person editing the date. It is also never raised alongside
        /// `rebootedDuringSession`, because across boots there is no comparable anchor to
        /// difference and a fabricated anomaly would misname what happened.
        case clockAnomaly
    }
}
