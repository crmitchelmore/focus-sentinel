import Foundation

/// Reconciling a persisted session against the wall clock, the uptime anchor and the boot
/// identity — as a **pure function**.
///
/// The Court's binding condition is that a restored running session must reconcile elapsed
/// wall-clock time and never blindly restart its timer. This is where that is satisfied, and
/// the strongest form of the second half is structural: **there is no timer object anywhere in
/// this programme**. The elapsed figure is computed on demand from `startedAt` and an injected
/// wall clock, exactly as e02's `TimeboxState` already does, so there is nothing to restart.
///
/// ## Why the reconciler is pure, and not merely tidy
///
/// The sleep case cannot be *measured* on the rig this programme is built on: probe P-86
/// recorded a Mac configured never to sleep, with `kern.sleeptime` at zero after 8.55 days of
/// uptime, and probe P-98 recorded `mach_absolute_time` and `mach_continuous_time` agreeing to
/// 8×10⁻⁸ s in consequence. Forcing a real sleep would suspend the process running the gate.
/// So the behaviour is exercised by **injected** clocks against one stated invariant, rather
/// than trusted to this Mac.
///
/// ## The invariant, chosen and documented
///
/// > Across a system sleep, **wall time and uptime advance together.** A four-hour sleep adds
/// > ~14 400 s to both, the drift stays inside tolerance, and **no `.clockAnomaly` is raised.**
/// > The only things that make the two diverge are a wall-clock correction (NTP, a manual date
/// > change) and a reboot.
///
/// That is a property of `mach_continuous_time`, which keeps counting while the Mac sleeps.
/// `SuspendingClock`/`mach_absolute_time` is rejected by name: an active-only elapsed would
/// contradict e02's ruling that a timebox is a promise about the clock on the wall, and would
/// make every overnight session report a fabricated figure.
public enum SessionRestoration {
    /// More than this since the last phase change and the session comes back paused.
    ///
    /// Fifteen minutes. A person who has been away for an hour did not spend it working, and
    /// an app that quietly counted it would be lying to them about their own day.
    public static let defaultStaleAfter: Duration = .seconds(15 * 60)

    /// How far the wall clock and the uptime anchor may disagree before it is worth saying so.
    ///
    /// Five seconds, sized off probe P-99: on this machine, over 8.55 days of uptime, the
    /// adjusted clock and the raw counter had drifted **2.96 s** apart (≈ 4 ppm) without a
    /// single sleep. Two figures derived from different clocks will never agree exactly, so a
    /// cross-check needs a tolerance — and zero is not it.
    public static let defaultDriftTolerance: Duration = .seconds(5)

    /// A persisted session, projected out of the store as plain values.
    ///
    /// The reconciler takes this rather than the `@Model` row so that it is genuinely pure and
    /// genuinely headless: every case below — a four-hour sleep, a reboot, a six-second NTP
    /// correction — is a struct literal in a test, not a container that has to be built and
    /// migrated first.
    public struct StoredSession: Sendable, Equatable, Hashable {
        public let sessionID: UUID
        public let startedAt: Date
        public let endedAt: Date?
        public let phase: SessionPhase
        public let phaseChangedAt: Date
        public let resumeTo: ResumablePhase?
        public let pauseCauses: Set<PauseReason>
        /// Seconds since boot at the last phase change, or `nil` if none was recorded.
        public let uptimeAnchorSeconds: Double?
        /// `"<kern.boottime.sec>.<usec>"` at the last phase change, or `nil`.
        public let bootIdentity: String?

        public init(
            sessionID: UUID,
            startedAt: Date,
            endedAt: Date? = nil,
            phase: SessionPhase,
            phaseChangedAt: Date,
            resumeTo: ResumablePhase? = nil,
            pauseCauses: Set<PauseReason> = [],
            uptimeAnchorSeconds: Double? = nil,
            bootIdentity: String? = nil
        ) {
            self.sessionID = sessionID
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.phase = phase
            self.phaseChangedAt = phaseChangedAt
            self.resumeTo = resumeTo
            self.pauseCauses = pauseCauses
            self.uptimeAnchorSeconds = uptimeAnchorSeconds
            self.bootIdentity = bootIdentity
        }
    }

    /// Reconcile a persisted session against the world as it is now.
    ///
    /// The rules, in the order they are applied:
    ///
    /// 1. **`startedAt` is never rewritten.** Not on restore, not on resume, not ever. Every
    ///    elapsed figure the user sees is derived from it.
    /// 2. `elapsedWallSeconds = now − startedAt` — **this is the number the UI shows**. A Mac
    ///    that slept for an hour has spent that hour. A session that has already ended reports
    ///    the span it actually ran, because `now − startedAt` on a closed session would grow
    ///    for ever.
    /// 3. If the boot identity **matches** and an anchor exists, the drift between the
    ///    wall-clock and uptime views of the current phase is computed, and a drift beyond
    ///    tolerance raises `.clockAnomaly`. The wall figure is still what is displayed;
    ///    silently showing a number you know is wrong is worse than saying so.
    /// 4. If the boot identity **differs**, the anchor is discarded and `.rebootedDuringSession`
    ///    is raised. **No drift is computed** — differencing an anchor from one boot against a
    ///    reading from another is arithmetic on unrelated numbers, and a spurious
    ///    `.clockAnomaly` beside a reboot would tell the user the clock changed when what
    ///    actually happened is that the Mac restarted.
    /// 5. The phase: a different boot restores `paused(cause: .systemRestart)`; more than
    ///    `staleAfter` since the last phase change restores `paused(cause: .relaunch)`; both
    ///    set `resumeTo` to the phase the session was actually in, so one click puts the person
    ///    back where they were. Otherwise the stored phase is restored as-is — an app that
    ///    crashed and came back five seconds later should not make anyone press Resume. A
    ///    session already `interrupted` or `complete` restores unchanged: terminal is terminal.
    /// 6. **No timer is started**, because there is none to start.
    public static func reconcile(
        record: StoredSession,
        now: Date,
        nowUptimeSeconds: Double,
        bootIdentity: String,
        staleAfter: Duration = defaultStaleAfter,
        driftTolerance: Duration = defaultDriftTolerance
    ) -> RestoredSession {
        // 2 — the number the user sees.
        let elapsedWallSeconds = (record.endedAt ?? now).timeIntervalSince(record.startedAt)

        // Terminal is terminal: a session that is over has nothing to reconcile, no pause to
        // come back to and no clock to be suspicious of.
        guard !record.phase.isTerminal else {
            return RestoredSession(
                sessionID: record.sessionID,
                startedAt: record.startedAt,
                phase: record.phase,
                resumeTo: record.resumeTo,
                pauseCauses: [],
                elapsedWallSeconds: elapsedWallSeconds,
                notes: [],
                driftSeconds: nil
            )
        }

        var notes: Set<RestoredSession.ReconciliationNote> = []
        var driftSeconds: Double?

        let sameBoot = record.bootIdentity == bootIdentity
        if !sameBoot {
            // 4 — the anchor belongs to another boot. Discard it, and compute no drift.
            notes.insert(.rebootedDuringSession)
        } else if let anchor = record.uptimeAnchorSeconds {
            // 3 — the two views of the current phase, compared.
            let wallSincePhaseChange = now.timeIntervalSince(record.phaseChangedAt)
            let elapsedUptimeSeconds = nowUptimeSeconds - anchor
            let drift = abs(wallSincePhaseChange - elapsedUptimeSeconds)
            driftSeconds = drift
            if drift > seconds(driftTolerance) {
                notes.insert(.clockAnomaly)
            }
        }

        let isStale = now.timeIntervalSince(record.phaseChangedAt) > seconds(staleAfter)
        if isStale {
            notes.insert(.restoredStale)
        }

        // 5 — the phase, and the single cause that a single matching resume will clear.
        let restorationCause: PauseReason?
        if !sameBoot {
            restorationCause = .systemRestart
        } else if isStale {
            restorationCause = .relaunch
        } else {
            restorationCause = nil
        }

        guard let cause = restorationCause else {
            // A fresh relaunch: the stored phase, and the causes it was already holding.
            return RestoredSession(
                sessionID: record.sessionID,
                startedAt: record.startedAt,
                phase: record.phase,
                resumeTo: record.resumeTo,
                pauseCauses: record.pauseCauses,
                elapsedWallSeconds: elapsedWallSeconds,
                notes: notes,
                driftSeconds: driftSeconds
            )
        }

        // A session that was *already* paused comes back holding its own causes **and** the
        // restoration one, and needs both cleared — the same arithmetic `SessionMachine`
        // performs when a second cause arrives while the app is running. Its `resumeTo` was
        // set at its first pause and is not overwritten here either.
        let wasPaused = record.phase == .paused
        return RestoredSession(
            sessionID: record.sessionID,
            startedAt: record.startedAt,
            phase: .paused,
            resumeTo: wasPaused ? record.resumeTo : ResumablePhase.narrowing(record.phase),
            pauseCauses: record.pauseCauses.union([cause]),
            elapsedWallSeconds: elapsedWallSeconds,
            notes: notes,
            driftSeconds: driftSeconds
        )
    }

    /// `Duration` as a `Double` of seconds.
    ///
    /// `Duration` is the right type at the boundary — it cannot be confused with a `Date` or
    /// with a count of anything else — and a `Double` is the right type for the arithmetic,
    /// because the uptime anchor is one. This is the one place the two meet.
    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
