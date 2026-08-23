import Foundation
import Testing

@testable import FocusCore

// MARK: - Fixture

/// 2026-01-01T00:00:00Z. Every instant below is derived from it, so **no test here reads a
/// real clock** — which is the only way the four-hour sleep and the reboot can be exercised
/// at all on a rig that has not slept in 8.55 days (probe P-86).
private let start = Date(timeIntervalSince1970: 1_767_225_600)
private let sessionID = UUID(uuidString: "f0cc5e55-0000-4000-8000-000000000001")!

/// The boot this session was written on, and a different one.
private let bootA = "1786742847.869178"
private let bootB = "1787999999.123456"

/// Seconds since boot at the last phase change, in the shape `mach_continuous_time()` scaled
/// by `mach_timebase_info()` produces (probe P-106 read `741532.264` from a live process).
private let anchor = 741_532.264_185_666_6

private let fourHours: Double = 4 * 60 * 60

private func stored(
    phase: SessionPhase = .focus,
    startedAt: Date = start,
    phaseChangedAt: Date = start,
    endedAt: Date? = nil,
    resumeTo: ResumablePhase? = nil,
    pauseCauses: Set<PauseReason> = [],
    uptimeAnchorSeconds: Double? = anchor,
    bootIdentity: String? = bootA
) -> SessionRestoration.StoredSession {
    SessionRestoration.StoredSession(
        sessionID: sessionID,
        startedAt: startedAt,
        endedAt: endedAt,
        phase: phase,
        phaseChangedAt: phaseChangedAt,
        resumeTo: resumeTo,
        pauseCauses: pauseCauses,
        uptimeAnchorSeconds: uptimeAnchorSeconds,
        bootIdentity: bootIdentity
    )
}

private func reconcile(
    _ record: SessionRestoration.StoredSession,
    afterWall wallDelta: Double,
    afterUptime uptimeDelta: Double,
    boot: String = bootA
) -> RestoredSession {
    SessionRestoration.reconcile(
        record: record,
        now: start.addingTimeInterval(wallDelta),
        nowUptimeSeconds: anchor + uptimeDelta,
        bootIdentity: boot
    )
}

// MARK: - The documented defaults

@Suite("Restoration defaults")
struct SessionRestorationDefaultsTests {
    @Test("staleAfter is fifteen minutes and the drift tolerance is five seconds")
    func documentedDefaults() {
        #expect(SessionRestoration.defaultStaleAfter == .seconds(15 * 60))
        // Sized off P-99: 2.96 s of wall-versus-raw drift over 8.55 days of uptime on this
        // machine, with no sleep at all. Two clocks never agree exactly, and zero is not a
        // tolerance.
        #expect(SessionRestoration.defaultDriftTolerance == .seconds(5))
    }
}

// MARK: - The condition the Court bound this epic to

@Suite("startedAt is never rewritten")
struct SessionStartedAtTests {
    /// Asserted individually for each path, because "never rewritten" is only worth anything
    /// if it is true of the path you happen to be on.
    @Test("startedAt is byte-identical after every restoration path")
    func startedAtSurvivesEveryPath() {
        let cases: [(String, RestoredSession)] = [
            ("fresh relaunch", reconcile(stored(), afterWall: 5, afterUptime: 5)),
            ("stale relaunch", reconcile(stored(), afterWall: 3_600, afterUptime: 3_600)),
            ("reboot", reconcile(stored(), afterWall: 30, afterUptime: 30, boot: bootB)),
            ("clock anomaly", reconcile(stored(), afterWall: 6, afterUptime: 0)),
            (
                "terminal",
                reconcile(
                    stored(phase: .complete, endedAt: start.addingTimeInterval(600)),
                    afterWall: 100_000,
                    afterUptime: 100_000
                )
            )
        ]
        for (name, restored) in cases {
            #expect(restored.startedAt == start, "\(name) rewrote startedAt")
            #expect(
                restored.startedAt.timeIntervalSince1970 == start.timeIntervalSince1970,
                "\(name) rewrote startedAt"
            )
            #expect(restored.sessionID == sessionID)
        }
    }

    @Test("a session started ninety minutes ago restores with ninety minutes elapsed")
    func ninetyMinutes() {
        let restored = reconcile(
            stored(phaseChangedAt: start),
            afterWall: 5_400,
            afterUptime: 5_400
        )
        #expect(restored.elapsedWallSeconds == 5_400)
        #expect(restored.startedAt == start)
    }
}

// MARK: - Sleep, the invariant this epic commits to

@Suite("A system sleep raises no anomaly")
struct SessionSleepReconciliationTests {
    /// **The invariant.** `mach_continuous_time` keeps counting across sleep, so a four-hour
    /// sleep adds ~14 400 s to the wall clock *and* to the anchor. They move together, the
    /// drift is unchanged, and no anomaly is raised.
    ///
    /// An earlier draft of this plan asserted the opposite — wall advances, monotonic does not
    /// — which would have manufactured a 14 400 s anomaly out of a night's sleep and had the
    /// suite certify the bug.
    @Test("a four-hour sleep with wall and uptime both advancing 14 400 s raises no anomaly")
    func fourHourSleepRaisesNoAnomaly() {
        let restored = reconcile(stored(), afterWall: fourHours, afterUptime: fourHours)

        #expect(restored.elapsedWallSeconds == fourHours, "four hours on the clock on the wall")
        #expect(
            !restored.notes.contains(.clockAnomaly),
            "a night's sleep is not a clock correction"
        )
        #expect(restored.driftSeconds == 0)
        #expect(!restored.notes.contains(.rebootedDuringSession))

        // It *is* stale, and that is correct: four hours have passed since the last phase
        // change, and a person who has been away that long did not spend it working. One
        // matching resume puts them back in focus.
        #expect(restored.notes.contains(.restoredStale))
        #expect(restored.phase == .paused)
        #expect(restored.pauseCauses == [.relaunch])
        #expect(restored.resumeTo == .focus)
    }

    /// The anomaly path, proved by the case that really produces one: the same sleep, plus an
    /// NTP correction that moved the wall clock and could not move the anchor.
    @Test("the same sleep plus a 6 s NTP correction reports the time and raises .clockAnomaly")
    func fourHourSleepPlusNTPRaisesAnomaly() {
        let restored = reconcile(stored(), afterWall: fourHours + 6, afterUptime: fourHours)

        #expect(restored.elapsedWallSeconds == fourHours + 6)
        #expect(
            abs(restored.elapsedWallSeconds - fourHours) < 10,
            "still four hours to any reader; the correction is six seconds"
        )
        #expect(restored.notes.contains(.clockAnomaly))
        #expect(restored.driftSeconds == 6)
        // The wall figure is still what is displayed. Silently showing a number the app knows
        // is suspect would be worse than saying so.
        #expect(restored.elapsedWallSeconds > fourHours)
    }
}

// MARK: - Reboot

@Suite("A reboot discards the anchor and names what happened")
struct SessionRebootReconciliationTests {
    @Test("a different boot identity discards the anchor and restores paused(.systemRestart)")
    func rebootDuringSession() {
        let restored = reconcile(
            stored(phase: .onBreak),
            afterWall: 30,
            afterUptime: 30,
            boot: bootB
        )

        #expect(restored.notes.contains(.rebootedDuringSession))
        #expect(restored.phase == .paused)
        #expect(restored.pauseCauses == [.systemRestart])
        #expect(restored.resumeTo == .onBreak, "one click puts them back where they were")
        #expect(restored.startedAt == start)
        #expect(restored.elapsedWallSeconds == 30)
    }

    /// Explicitly asserted, because the tempting implementation raises both: across boots
    /// there is nothing comparable to difference, and a fabricated anomaly beside a reboot
    /// would tell the user the clock changed when what actually happened is that the Mac
    /// restarted.
    @Test("a reboot carries no .clockAnomaly and computes no drift at all")
    func rebootRaisesNoClockAnomaly() {
        // Wall and uptime disagree wildly — as they must, being from different boots.
        let restored = reconcile(stored(), afterWall: 30, afterUptime: -700_000, boot: bootB)
        #expect(!restored.notes.contains(.clockAnomaly))
        #expect(restored.driftSeconds == nil)
        #expect(restored.notes == [.rebootedDuringSession])
    }

    @Test("a session with no anchor at all computes no drift and raises no anomaly")
    func noAnchorNoDrift() {
        let restored = reconcile(
            stored(uptimeAnchorSeconds: nil),
            afterWall: 6,
            afterUptime: 0
        )
        #expect(restored.driftSeconds == nil)
        #expect(!restored.notes.contains(.clockAnomaly))
    }
}

// MARK: - Relaunch

@Suite("Relaunch, fresh and stale")
struct SessionRelaunchReconciliationTests {
    /// An app that crashed and came back five seconds later should not make anyone press
    /// Resume.
    @Test("a fresh relaunch five seconds later restores the stored phase unchanged")
    func freshRelaunch() {
        for phase in [SessionPhase.focus, .intentionalDetour, .onBreak] {
            let restored = reconcile(stored(phase: phase), afterWall: 5, afterUptime: 5)
            #expect(restored.phase == phase)
            #expect(restored.pauseCauses.isEmpty)
            #expect(restored.notes.isEmpty)
        }
    }

    @Test("more than fifteen minutes since the last phase change restores paused(.relaunch)")
    func staleRelaunch() {
        let restored = reconcile(
            stored(phase: .intentionalDetour),
            afterWall: 16 * 60,
            afterUptime: 16 * 60
        )
        #expect(restored.notes.contains(.restoredStale))
        #expect(restored.phase == .paused)
        #expect(restored.pauseCauses == [.relaunch])
        #expect(restored.resumeTo == .intentionalDetour)
        #expect(!restored.notes.contains(.clockAnomaly))
    }

    @Test("fourteen minutes is not stale; sixteen is")
    func staleBoundary() {
        let fresh = reconcile(stored(), afterWall: 14 * 60, afterUptime: 14 * 60)
        #expect(!fresh.notes.contains(.restoredStale))
        #expect(fresh.phase == .focus)

        let stale = reconcile(stored(), afterWall: 16 * 60, afterUptime: 16 * 60)
        #expect(stale.notes.contains(.restoredStale))
    }

    /// A restoration pause is a *single* cause, so a single matching `resumed(cause:)` clears
    /// it — and it composes with whatever the session was already paused for.
    @Test("a session already paused comes back holding its own causes and the restoration one")
    func alreadyPausedSessionAccumulatesCauses() {
        let restored = reconcile(
            stored(phase: .paused, resumeTo: .onBreak, pauseCauses: [.user]),
            afterWall: 3_600,
            afterUptime: 3_600
        )
        #expect(restored.phase == .paused)
        #expect(restored.pauseCauses == [.user, .relaunch], "both must be cleared")
        #expect(restored.resumeTo == .onBreak, "resumeTo was set at the first pause, not here")

        // And the machine agrees: clearing only the relaunch leaves the user's pause standing.
        let state = SessionState(
            phase: restored.phase,
            pauseCauses: restored.pauseCauses,
            resumeTo: restored.resumeTo,
            phaseChangedAt: start
        )
        let transition = SessionMachine.apply(
            .resumed(cause: .relaunch),
            to: state,
            at: start.addingTimeInterval(3_600)
        )
        #expect(transition.state?.phase == .paused)
        #expect(transition.state?.pauseCauses == [.user])
    }

    @Test("resumeTo is set to the real phase for all three resumable phases")
    func resumeToForEveryResumablePhase() {
        for resumable in ResumablePhase.allCases {
            let restored = reconcile(
                stored(phase: resumable.phase),
                afterWall: 3_600,
                afterUptime: 3_600
            )
            #expect(restored.phase == .paused)
            #expect(restored.resumeTo == resumable)
        }
    }
}

// MARK: - Wall-clock corrections

@Suite("Wall-clock corrections against a stationary anchor")
struct SessionClockAnomalyTests {
    /// The wall clock jumped six seconds and the anchor did not move at all — an NTP
    /// correction, or a person editing the date. That is what an anomaly *is*.
    @Test("a 6 s wall jump with the anchor unmoved raises .clockAnomaly")
    func sixSecondJumpRaisesAnomaly() {
        let restored = reconcile(stored(), afterWall: 6, afterUptime: 0)
        #expect(restored.notes.contains(.clockAnomaly))
        #expect(restored.driftSeconds == 6)
        // The displayed figure is still the wall-clock one, anomaly or not.
        #expect(restored.elapsedWallSeconds == 6)
        #expect(restored.phase == .focus, "six seconds is not stale")
    }

    @Test("a 2 s jump is inside the tolerance and raises nothing")
    func twoSecondJumpRaisesNothing() {
        let restored = reconcile(stored(), afterWall: 2, afterUptime: 0)
        #expect(!restored.notes.contains(.clockAnomaly))
        #expect(restored.driftSeconds == 2)
        #expect(restored.notes.isEmpty)
    }

    /// The tolerance is a strict `>`: five seconds exactly is the measured drift's own order
    /// of magnitude and is not an anomaly.
    @Test("exactly five seconds is not an anomaly and 5.001 is")
    func toleranceBoundary() {
        #expect(!reconcile(stored(), afterWall: 5, afterUptime: 0).notes.contains(.clockAnomaly))
        #expect(reconcile(stored(), afterWall: 5.001, afterUptime: 0).notes.contains(.clockAnomaly))
    }

    /// A clock that ran *backwards* is just as anomalous as one that ran forwards.
    @Test("a backwards wall correction raises the anomaly too")
    func backwardsJumpRaisesAnomaly() {
        let restored = SessionRestoration.reconcile(
            record: stored(phaseChangedAt: start.addingTimeInterval(-100)),
            now: start.addingTimeInterval(-10),
            nowUptimeSeconds: anchor + 100,
            bootIdentity: bootA
        )
        #expect(restored.notes.contains(.clockAnomaly))
        #expect(restored.driftSeconds == 10)
    }

    /// An injected tolerance is honoured, so the default is a default and not a constant in
    /// disguise.
    @Test("the drift tolerance is injected")
    func toleranceIsInjected() {
        let record = stored()
        let lenient = SessionRestoration.reconcile(
            record: record,
            now: start.addingTimeInterval(6),
            nowUptimeSeconds: anchor,
            bootIdentity: bootA,
            driftTolerance: .seconds(30)
        )
        #expect(!lenient.notes.contains(.clockAnomaly))

        let strict = SessionRestoration.reconcile(
            record: record,
            now: start.addingTimeInterval(6),
            nowUptimeSeconds: anchor,
            bootIdentity: bootA,
            driftTolerance: .seconds(1)
        )
        #expect(strict.notes.contains(.clockAnomaly))
    }

    @Test("the staleness window is injected")
    func staleAfterIsInjected() {
        let record = stored()
        let patient = SessionRestoration.reconcile(
            record: record,
            now: start.addingTimeInterval(3_600),
            nowUptimeSeconds: anchor + 3_600,
            bootIdentity: bootA,
            staleAfter: .seconds(7_200)
        )
        #expect(!patient.notes.contains(.restoredStale))
        #expect(patient.phase == .focus)
    }
}

// MARK: - Terminal

@Suite("Terminal sessions restore unchanged")
struct SessionTerminalRestorationTests {
    @Test("an interrupted or complete session comes back exactly as it was")
    func terminalRestoresUnchanged() {
        for phase in [SessionPhase.interrupted, .complete] {
            let ended = start.addingTimeInterval(600)
            let restored = reconcile(
                stored(phase: phase, endedAt: ended, bootIdentity: bootB),
                afterWall: 100_000,
                afterUptime: 100_000
            )
            #expect(restored.phase == phase, "terminal is terminal")
            #expect(restored.pauseCauses.isEmpty, "a session that is over is not paused")
            #expect(restored.notes.isEmpty, "there is nothing to reconcile")
            #expect(restored.driftSeconds == nil)
            // The span it actually ran, not a figure that keeps growing for ever.
            #expect(restored.elapsedWallSeconds == 600)
        }
    }
}

// MARK: - The strongest form of "never restarts its timer"

@Suite("There is no timer to restart")
struct SessionNoTimerTests {
    /// Reconciliation is a function of its arguments and nothing else — the same inputs give
    /// the same answer, every time, with no scheduling, no state and no clock of its own.
    @Test("reconcile is pure: the same inputs give the same result")
    func reconcileIsPure() {
        let record = stored(phase: .onBreak, resumeTo: nil)
        let first = reconcile(record, afterWall: 3_600, afterUptime: 3_600)
        let second = reconcile(record, afterWall: 3_600, afterUptime: 3_600)
        #expect(first == second)
    }

    /// The elapsed figure is a function of an injected `now`, which is what "there is no timer
    /// object anywhere in this programme" means in practice: nothing has to be started,
    /// stopped or restarted for the number to be right.
    @Test("a snapshot's elapsed and remaining are functions of an injected now")
    func snapshotDerivesEverythingFromNow() {
        let snapshot = SessionSnapshot(
            sessionID: sessionID,
            phase: .focus,
            kind: .countdown,
            startedAt: start,
            plannedSeconds: 1_500
        )
        #expect(snapshot.elapsedWallSeconds(now: start.addingTimeInterval(600)) == 600)
        #expect(snapshot.remainingSeconds(now: start.addingTimeInterval(600)) == 900)
        // Running over is reported, not clamped away.
        #expect(snapshot.remainingSeconds(now: start.addingTimeInterval(1_800)) == -300)

        let openEnded = SessionSnapshot(sessionID: sessionID, phase: .focus, startedAt: start)
        #expect(openEnded.remainingSeconds(now: start.addingTimeInterval(600)) == nil)

        let deadline = SessionSnapshot(
            sessionID: sessionID,
            phase: .focus,
            kind: .deadline,
            startedAt: start,
            deadlineAt: start.addingTimeInterval(3_600)
        )
        #expect(deadline.remainingSeconds(now: start.addingTimeInterval(600)) == 3_000)
    }

    /// The Resume control's contract: a cause the person cannot clear keeps the button
    /// disabled, with a name to show them, rather than letting them press something that will
    /// be rejected.
    @Test("a snapshot says which causes the user cannot clear")
    func snapshotNamesTheCausesTheUserCannotClear() {
        let userOnly = SessionSnapshot(
            sessionID: sessionID,
            phase: .paused,
            pauseCauses: [.user],
            startedAt: start
        )
        #expect(userOnly.userMayResume)
        #expect(userOnly.causesTheUserCannotClear.isEmpty)

        let alsoLocked = SessionSnapshot(
            sessionID: sessionID,
            phase: .paused,
            pauseCauses: [.user, .screenLocked],
            startedAt: start
        )
        #expect(!alsoLocked.userMayResume)
        #expect(alsoLocked.causesTheUserCannotClear == [.screenLocked])
        #expect(!alsoLocked.permitsIntervention)
    }
}

// MARK: - The kind decoder

@Suite("Session kind decoding")
struct SessionKindDecodingTests {
    @Test("every SessionKind round-trips and an unknown raw reads as openEnded")
    func kindRoundTrips() {
        for kind in SessionKind.allCases {
            #expect(SessionKind.decode(kind.rawValue) == kind)
        }
        #expect(SessionKind.allCases.count == 3)
        #expect(SessionKind.decode("pomodoro") == .openEnded)
        #expect(SessionKind.decode(nil) == .openEnded)
    }
}

// MARK: - The injected uptime clock

@Suite("The uptime clock seam")
struct UptimeClockSeamTests {
    @Test("a test uptime clock advances only when told to, and never backwards")
    func testClockAdvances() {
        var clock = TestUptimeClock(uptimeSeconds: anchor)
        #expect(clock.uptimeSeconds == anchor)
        clock.advance(by: fourHours)
        #expect(clock.uptimeSeconds == anchor + fourHours)
        clock.advance(by: 0)
        #expect(clock.uptimeSeconds == anchor + fourHours)
    }

    /// The seam is what makes the sleep case testable at all: it cannot be measured on this
    /// rig, so it is injected. This is that, end to end.
    @Test("a four-hour sleep driven through the injected clock raises no anomaly")
    func injectedClockDrivesTheSleepCase() {
        var clock = TestUptimeClock(uptimeSeconds: anchor)
        clock.advance(by: fourHours)

        let restored = SessionRestoration.reconcile(
            record: stored(),
            now: start.addingTimeInterval(fourHours),
            nowUptimeSeconds: clock.uptimeSeconds,
            bootIdentity: bootA
        )
        #expect(restored.driftSeconds == 0)
        #expect(!restored.notes.contains(.clockAnomaly))
        #expect(restored.elapsedWallSeconds == fourHours)
    }
}
