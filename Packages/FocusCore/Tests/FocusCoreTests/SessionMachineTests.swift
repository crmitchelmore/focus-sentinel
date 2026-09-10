import Foundation
import Testing

@testable import FocusCore

// MARK: - Fixture

/// 2026-01-01T00:00:00Z — the same reference instant every other suite in this package uses.
private let t0 = Date(timeIntervalSince1970: 1_767_225_600)
/// One minute later. Every accepted transition below happens here, so "the phase changed at
/// `t1`" is a claim about *this* event rather than about the clock the runner happened to have.
private let t1 = t0.addingTimeInterval(60)
/// One minute earlier than the last phase change: the clock ran backwards.
private let tMinus = t0.addingTimeInterval(-60)

private func state(
    _ phase: SessionPhase,
    causes: Set<PauseReason> = [],
    resumeTo: ResumablePhase? = nil,
    endedAt: Date? = nil
) -> SessionState {
    SessionState(
        phase: phase,
        pauseCauses: causes,
        resumeTo: resumeTo,
        phaseChangedAt: t0,
        endedAt: endedAt
    )
}

/// Assert one **accepted phase change** and return the state it produced.
///
/// Every accepted outcome is checked for the cause-set invariant here rather than in a test of
/// its own, so that a cell which moved the phase and forgot to clear the causes fails at the
/// cell rather than somewhere later and less obviously.
@discardableResult
private func expectAccepted(
    _ event: SessionEvent,
    from: SessionState,
    to expected: SessionPhase,
    sourceLocation: SourceLocation = #_sourceLocation
) -> SessionState? {
    let transition = SessionMachine.apply(event, to: from, at: t1)
    guard case .accepted(let next, let value) = transition else {
        Issue.record(
            "expected .accepted(\(expected)) but got \(transition)",
            sourceLocation: sourceLocation
        )
        return nil
    }
    #expect(next.phase == expected, sourceLocation: sourceLocation)
    #expect(next.phaseChangedAt == t1, sourceLocation: sourceLocation)
    #expect(next.pauseCausesInvariantHolds, sourceLocation: sourceLocation)
    #expect(value.from == from.phase, sourceLocation: sourceLocation)
    #expect(value.to == expected, sourceLocation: sourceLocation)
    #expect(value.event == event.kind, sourceLocation: sourceLocation)
    #expect(value.reasonRaw == event.reasonRaw, sourceLocation: sourceLocation)
    #expect(value.outcome == .accepted, sourceLocation: sourceLocation)
    #expect(value.changesPhase, sourceLocation: sourceLocation)
    return next
}

/// Assert one **cause-set change**: the causes moved, the phase did not, and neither did the
/// phase-change timestamp.
@discardableResult
private func expectCauseChanged(
    _ event: SessionEvent,
    from: SessionState,
    causes expected: Set<PauseReason>,
    outcome expectedOutcome: SessionTransitionOutcome,
    sourceLocation: SourceLocation = #_sourceLocation
) -> SessionState? {
    let transition = SessionMachine.apply(event, to: from, at: t1)
    guard case .causeChanged(let next, let value) = transition else {
        Issue.record(
            "expected .causeChanged(\(expectedOutcome)) but got \(transition)",
            sourceLocation: sourceLocation
        )
        return nil
    }
    #expect(next.phase == .paused, sourceLocation: sourceLocation)
    #expect(next.pauseCauses == expected, sourceLocation: sourceLocation)
    #expect(next.pauseCausesInvariantHolds, sourceLocation: sourceLocation)
    #expect(next.resumeTo == from.resumeTo, "resumeTo is set once and never overwritten", sourceLocation: sourceLocation)
    #expect(
        next.phaseChangedAt == from.phaseChangedAt,
        "a cause change is not a phase change and must not move the clock",
        sourceLocation: sourceLocation
    )
    #expect(value.from == .paused, sourceLocation: sourceLocation)
    #expect(value.to == .paused, sourceLocation: sourceLocation)
    #expect(value.outcome == expectedOutcome, sourceLocation: sourceLocation)
    #expect(!value.changesPhase, sourceLocation: sourceLocation)
    return next
}

/// Assert one **named** rejection, and that nothing was produced to write.
private func expectRejected(
    _ event: SessionEvent,
    from: SessionState,
    _ expected: SessionRejection,
    at instant: Date = t1,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let transition = SessionMachine.apply(event, to: from, at: instant)
    #expect(transition.rejection == expected, sourceLocation: sourceLocation)
    #expect(transition.state == nil, sourceLocation: sourceLocation)
    #expect(
        transition.value == nil,
        "a rejected transition must write nothing at all",
        sourceLocation: sourceLocation
    )
}

/// The eight events, one of each, for the two terminal rows.
private let everyEvent: [SessionEvent] = [
    .detourStarted(reason: .user),
    .detourEnded,
    .breakStarted(reason: .user),
    .breakEnded,
    .paused(cause: .user),
    .resumed(cause: .user),
    .interrupted(reason: .user),
    .completed
]

// MARK: - Row 1: focus

@Suite("Session transitions from focus")
struct SessionTransitionsFromFocusTests {
    private let from = state(.focus)

    @Test("1 · focus + detourStarted ⇒ intentionalDetour")
    func detourStarted() {
        expectAccepted(.detourStarted(reason: .user), from: from, to: .intentionalDetour)
    }

    @Test("2 · focus + detourEnded ⇒ rejected noDetourInProgress")
    func detourEnded() {
        expectRejected(.detourEnded, from: from, .noDetourInProgress)
    }

    @Test("3 · focus + breakStarted ⇒ onBreak")
    func breakStarted() {
        expectAccepted(.breakStarted(reason: .user), from: from, to: .onBreak)
    }

    @Test("4 · focus + breakEnded ⇒ rejected noBreakInProgress")
    func breakEnded() {
        expectRejected(.breakEnded, from: from, .noBreakInProgress)
    }

    @Test("5 · focus + paused(cause) ⇒ paused, holding that cause, resumeTo focus")
    func paused() {
        let next = expectAccepted(.paused(cause: .screenLocked), from: from, to: .paused)
        #expect(next?.pauseCauses == [.screenLocked])
        #expect(next?.resumeTo == .focus)
    }

    @Test("6 · focus + resumed(cause) ⇒ rejected notPaused")
    func resumed() {
        expectRejected(.resumed(cause: .user), from: from, .notPaused)
    }

    @Test("7 · focus + interrupted ⇒ interrupted")
    func interrupted() {
        expectAccepted(.interrupted(reason: .user), from: from, to: .interrupted)
    }

    @Test("8 · focus + completed ⇒ complete")
    func completed() {
        expectAccepted(.completed, from: from, to: .complete)
    }
}

// MARK: - Row 2: intentionalDetour

@Suite("Session transitions from intentionalDetour")
struct SessionTransitionsFromDetourTests {
    private let from = state(.intentionalDetour)

    @Test("9 · intentionalDetour + detourStarted ⇒ rejected alreadyInPhase")
    func detourStarted() {
        expectRejected(.detourStarted(reason: .user), from: from, .alreadyInPhase)
    }

    @Test("10 · intentionalDetour + detourEnded ⇒ focus")
    func detourEnded() {
        expectAccepted(.detourEnded, from: from, to: .focus)
    }

    /// A break during a detour is two transitions, not one. The UI does both in a single
    /// click; the machine insists the timeline says what actually happened.
    @Test("11 · intentionalDetour + breakStarted ⇒ rejected endDetourFirst")
    func breakStarted() {
        expectRejected(.breakStarted(reason: .user), from: from, .endDetourFirst)
    }

    @Test("12 · intentionalDetour + breakEnded ⇒ rejected noBreakInProgress")
    func breakEnded() {
        expectRejected(.breakEnded, from: from, .noBreakInProgress)
    }

    @Test("13 · intentionalDetour + paused(cause) ⇒ paused, resumeTo intentionalDetour")
    func paused() {
        let next = expectAccepted(.paused(cause: .sensitiveApp), from: from, to: .paused)
        #expect(next?.pauseCauses == [.sensitiveApp])
        #expect(next?.resumeTo == .intentionalDetour)
    }

    @Test("14 · intentionalDetour + resumed(cause) ⇒ rejected notPaused")
    func resumed() {
        expectRejected(.resumed(cause: .user), from: from, .notPaused)
    }

    @Test("15 · intentionalDetour + interrupted ⇒ interrupted")
    func interrupted() {
        expectAccepted(.interrupted(reason: .priorityChanged), from: from, to: .interrupted)
    }

    @Test("16 · intentionalDetour + completed ⇒ complete")
    func completed() {
        expectAccepted(.completed, from: from, to: .complete)
    }
}

// MARK: - Row 3: onBreak

@Suite("Session transitions from onBreak")
struct SessionTransitionsFromBreakTests {
    private let from = state(.onBreak)

    @Test("17 · onBreak + detourStarted ⇒ rejected endBreakFirst")
    func detourStarted() {
        expectRejected(.detourStarted(reason: .user), from: from, .endBreakFirst)
    }

    @Test("18 · onBreak + detourEnded ⇒ rejected noDetourInProgress")
    func detourEnded() {
        expectRejected(.detourEnded, from: from, .noDetourInProgress)
    }

    @Test("19 · onBreak + breakStarted ⇒ rejected alreadyInPhase")
    func breakStarted() {
        expectRejected(.breakStarted(reason: .idle), from: from, .alreadyInPhase)
    }

    @Test("20 · onBreak + breakEnded ⇒ focus")
    func breakEnded() {
        expectAccepted(.breakEnded, from: from, to: .focus)
    }

    /// The whole reason `resumeTo` exists: an auto-pause because the user opened their
    /// password manager must return them to the break they were on, not to work they had
    /// stopped.
    @Test("21 · onBreak + paused(cause) ⇒ paused, resumeTo onBreak")
    func paused() {
        let next = expectAccepted(.paused(cause: .sensitiveApp), from: from, to: .paused)
        #expect(next?.pauseCauses == [.sensitiveApp])
        #expect(next?.resumeTo == .onBreak)
    }

    @Test("22 · onBreak + resumed(cause) ⇒ rejected notPaused")
    func resumed() {
        expectRejected(.resumed(cause: .user), from: from, .notPaused)
    }

    @Test("23 · onBreak + interrupted ⇒ interrupted")
    func interrupted() {
        expectAccepted(.interrupted(reason: .appQuit), from: from, to: .interrupted)
    }

    @Test("24 · onBreak + completed ⇒ complete")
    func completed() {
        expectAccepted(.completed, from: from, to: .complete)
    }
}

// MARK: - Row 4: paused — eight cells, ten outcomes

@Suite("Session transitions from paused")
struct SessionTransitionsFromPausedTests {
    private let from = state(.paused, causes: [.user], resumeTo: .focus)

    @Test("25 · paused + detourStarted ⇒ rejected pausedSessionIsInert")
    func detourStarted() {
        expectRejected(.detourStarted(reason: .user), from: from, .pausedSessionIsInert)
    }

    @Test("26 · paused + detourEnded ⇒ rejected pausedSessionIsInert")
    func detourEnded() {
        expectRejected(.detourEnded, from: from, .pausedSessionIsInert)
    }

    @Test("27 · paused + breakStarted ⇒ rejected pausedSessionIsInert")
    func breakStarted() {
        expectRejected(.breakStarted(reason: .user), from: from, .pausedSessionIsInert)
    }

    @Test("28 · paused + breakEnded ⇒ rejected pausedSessionIsInert")
    func breakEnded() {
        expectRejected(.breakEnded, from: from, .pausedSessionIsInert)
    }

    @Test("29a · paused + paused(new cause) ⇒ causeAdded, still paused")
    func pausedWithANewCause() {
        let next = expectCauseChanged(
            .paused(cause: .screenLocked),
            from: from,
            causes: [.user, .screenLocked],
            outcome: .causeAdded
        )
        #expect(next?.resumeTo == .focus)
    }

    @Test("29b · paused + paused(cause already held) ⇒ rejected alreadyInPhase")
    func pausedWithACauseAlreadyHeld() {
        expectRejected(.paused(cause: .user), from: from, .alreadyInPhase)
    }

    @Test("30a · paused + resumed(last cause) ⇒ resumeTo")
    func resumedByTheLastCause() {
        let next = expectAccepted(.resumed(cause: .user), from: from, to: .focus)
        #expect(next?.pauseCauses.isEmpty == true)
        #expect(next?.resumeTo == nil, "the pause is over; there is nothing left to resume to")
    }

    @Test("30b · paused + resumed(one of several causes) ⇒ causeRemoved, still paused")
    func resumedByOneOfSeveralCauses() {
        let two = state(.paused, causes: [.user, .screenLocked], resumeTo: .onBreak)
        expectCauseChanged(
            .resumed(cause: .screenLocked),
            from: two,
            causes: [.user],
            outcome: .causeRemoved
        )
    }

    /// The wake handler cannot clear a `.user` pause it never set.
    @Test("30c · paused + resumed(cause never held) ⇒ rejected notPausedForThatCause")
    func resumedByACauseNeverHeld() {
        expectRejected(.resumed(cause: .globalPause), from: from, .notPausedForThatCause)
    }

    @Test("31 · paused + interrupted ⇒ interrupted")
    func interrupted() {
        let next = expectAccepted(.interrupted(reason: .user), from: from, to: .interrupted)
        #expect(next?.pauseCauses.isEmpty == true)
    }

    @Test("32 · paused + completed ⇒ complete")
    func completed() {
        let next = expectAccepted(.completed, from: from, to: .complete)
        #expect(next?.pauseCauses.isEmpty == true)
    }
}

// MARK: - Rows 5 and 6: the terminal phases

@Suite("Session transitions from the terminal phases")
struct SessionTransitionsFromTerminalTests {
    @Test("33–40 · interrupted rejects all eight events as terminal")
    func interruptedRejectsEverything() {
        let from = state(.interrupted)
        for event in everyEvent {
            expectRejected(event, from: from, .terminal)
        }
        #expect(everyEvent.count == 8)
    }

    @Test("41–48 · complete rejects all eight events as terminal")
    func completeRejectsEverything() {
        let from = state(.complete)
        for event in everyEvent {
            expectRejected(event, from: from, .terminal)
        }
        #expect(everyEvent.count == 8)
    }

    @Test("terminal is exactly interrupted and complete")
    func terminalSet() {
        #expect(SessionPhase.allCases.filter(\.isTerminal) == [.interrupted, .complete])
    }
}

// MARK: - The two checks that run before the table

@Suite("Session machine short-circuits")
struct SessionMachineShortCircuitTests {
    /// A closed row rejects everything, whatever its phase says — checked *before* the table,
    /// so a `focus` row that has been ended does not accept a detour.
    @Test("endedAt != nil rejects every event with sessionEnded, before the table")
    func endedSessionRejectsEverything() {
        for phase in SessionPhase.allCases {
            let causes: Set<PauseReason> = phase == .paused ? [.user] : []
            let from = state(phase, causes: causes, endedAt: t0)
            for event in everyEvent {
                expectRejected(event, from: from, .sessionEnded)
            }
        }
    }

    /// P-99 measured 2.96 s of wall-versus-monotonic drift on this machine over 8.55 days of
    /// uptime, so an NTP correction during a session is an ordinary event — and must never be
    /// able to write a transition that appears to precede the one it follows.
    @Test("an instant before the last phase change rejects with clockWentBackwards")
    func backwardsClockRejects() {
        for phase in SessionPhase.allCases {
            let causes: Set<PauseReason> = phase == .paused ? [.user] : []
            let from = state(phase, causes: causes)
            for event in everyEvent {
                expectRejected(event, from: from, .clockWentBackwards, at: tMinus)
            }
        }
    }

    /// An event exactly *at* the last phase change is not backwards, and is decided by the
    /// table like any other.
    @Test("an instant equal to the last phase change is not backwards")
    func equalInstantIsAccepted() {
        let from = state(.focus)
        let transition = SessionMachine.apply(.breakStarted(reason: .user), to: from, at: t0)
        #expect(transition.state?.phase == .onBreak)
    }

    /// A closed row is rejected `sessionEnded` even when the clock also ran backwards: the
    /// order of the two checks is itself part of the specification.
    @Test("sessionEnded is decided before clockWentBackwards")
    func endedBeatsBackwards() {
        let from = state(.focus, endedAt: t0)
        expectRejected(.completed, from: from, .sessionEnded, at: tMinus)
    }
}

// MARK: - Resume authority, by name

@Suite("Resume is authorised by the cause that paused")
struct SessionResumeAuthorityTests {
    /// A user pause, then a screen lock, resumed by the unlock: the session **stays paused**
    /// holding `[.user]`. Without this, unlocking the screen would resume a pause the person
    /// asked for.
    @Test("user then lock, resumed by lock, stays paused holding [.user]")
    func userThenLockResumedByLock() {
        var current = state(.focus)
        current = SessionMachine.apply(.paused(cause: .user), to: current, at: t1).state!
        current = SessionMachine.apply(.paused(cause: .screenLocked), to: current, at: t1).state!
        #expect(current.pauseCauses == [.user, .screenLocked])

        let transition = SessionMachine.apply(.resumed(cause: .screenLocked), to: current, at: t1)
        guard case .causeChanged(let next, let value) = transition else {
            Issue.record("expected .causeChanged, got \(transition)")
            return
        }
        #expect(next.phase == .paused)
        #expect(next.pauseCauses == [.user])
        #expect(next.resumeTo == .focus)
        #expect(value.outcome == .causeRemoved)
    }

    /// The same pair, resumed by the user: still paused, now holding `[.screenLocked]`. The
    /// person may not un-pause the machine's lock either — the authority runs both ways.
    @Test("user then lock, resumed by user, stays paused holding [.screenLocked]")
    func userThenLockResumedByUser() {
        var current = state(.onBreak)
        current = SessionMachine.apply(.paused(cause: .user), to: current, at: t1).state!
        current = SessionMachine.apply(.paused(cause: .screenLocked), to: current, at: t1).state!

        let transition = SessionMachine.apply(.resumed(cause: .user), to: current, at: t1)
        #expect(transition.state?.phase == .paused)
        #expect(transition.state?.pauseCauses == [.screenLocked])
        #expect(transition.value?.outcome == .causeRemoved)
    }

    @Test("either order, fully resumed, returns to resumeTo exactly once")
    func eitherOrderFullyResumedReturnsOnce() {
        for order in [[PauseReason.user, .screenLocked], [.screenLocked, .user]] {
            var current = state(.onBreak)
            for cause in order {
                current = SessionMachine.apply(.paused(cause: cause), to: current, at: t1).state!
            }
            #expect(current.resumeTo == .onBreak)

            // The first resume changes only the cause set.
            let first = SessionMachine.apply(.resumed(cause: order[0]), to: current, at: t1)
            #expect(first.value?.outcome == .causeRemoved)
            #expect(first.state?.phase == .paused)

            // The second — the last cause — is the one that moves the phase, once.
            let second = SessionMachine.apply(.resumed(cause: order[1]), to: first.state!, at: t1)
            #expect(second.value?.outcome == .accepted)
            #expect(second.state?.phase == .onBreak)
            #expect(second.state?.pauseCauses.isEmpty == true)
            #expect(second.state?.resumeTo == nil)
        }
    }

    /// `SensingHost.resume()` sends `.globalPause` and nothing else. Against a session paused
    /// only for `.user`, that is a rejection rather than a takeover.
    @Test("resumed(.globalPause) against a user-only pause is rejected notPausedForThatCause")
    func globalPauseCannotClearAUserPause() {
        let from = state(.paused, causes: [.user], resumeTo: .focus)
        expectRejected(.resumed(cause: .globalPause), from: from, .notPausedForThatCause)
    }

    /// `resumeTo` is stamped at the **first** pause and is never overwritten by a later cause,
    /// for all three resumable phases.
    @Test("resumeTo round-trips for all three resumable phases and survives a second cause")
    func resumeToRoundTripsAndSurvivesASecondCause() {
        for resumable in ResumablePhase.allCases {
            var current = state(resumable.phase)
            current = SessionMachine.apply(.paused(cause: .user), to: current, at: t1).state!
            #expect(current.resumeTo == resumable)

            current = SessionMachine.apply(.paused(cause: .globalPause), to: current, at: t1).state!
            #expect(current.resumeTo == resumable, "a later cause must not overwrite resumeTo")

            current = SessionMachine.apply(.resumed(cause: .globalPause), to: current, at: t1).state!
            current = SessionMachine.apply(.resumed(cause: .user), to: current, at: t1).state!
            #expect(current.phase == resumable.phase)
        }
    }

    /// With no stored destination a resume goes to `.focus`, which is the one phase it is
    /// always safe to come back to.
    @Test("resume with no resumeTo goes to focus")
    func resumeWithoutADestinationGoesToFocus() {
        let from = state(.paused, causes: [.relaunch], resumeTo: nil)
        let next = expectAccepted(.resumed(cause: .relaunch), from: from, to: .focus)
        #expect(next?.pauseCauses.isEmpty == true)
    }
}

// MARK: - The cause set's persisted encoding

@Suite("Pause causes and their persisted encoding")
struct SessionPauseCauseEncodingTests {
    @Test("the cause set is non-empty if and only if the phase is paused")
    func invariantHoldsAcrossTheWholeTable() {
        for phase in SessionPhase.allCases {
            let causes: Set<PauseReason> = phase == .paused ? [.user] : []
            let from = state(phase, causes: causes, resumeTo: phase == .paused ? .focus : nil)
            for event in everyEvent {
                let transition = SessionMachine.apply(event, to: from, at: t1)
                if let next = transition.state {
                    #expect(
                        next.pauseCausesInvariantHolds,
                        "\(phase) + \(event) produced \(next.phase) holding \(next.pauseCauses)"
                    )
                }
            }
        }
    }

    @Test("a two-cause set encodes sorted and comma-joined, and decodes back")
    func twoCausesRoundTrip() {
        let causes: Set<PauseReason> = [.user, .screenLocked]
        let raw = SessionState(phase: .paused, pauseCauses: causes, phaseChangedAt: t0)
            .pauseCausesRaw
        #expect(raw == "screenLocked,user", "sorted, so the encoding is deterministic")
        #expect(SessionState.decodePauseCauses(raw) == causes)
    }

    @Test("no causes encodes as nil, and nil and empty both decode to no causes")
    func noCausesEncodeAsNil() {
        #expect(SessionState(phase: .focus, phaseChangedAt: t0).pauseCausesRaw == nil)
        #expect(SessionState.decodePauseCauses(nil).isEmpty)
        #expect(SessionState.decodePauseCauses("").isEmpty)
    }

    @Test("a token this build does not know is dropped rather than crashing the launch")
    func unknownTokensAreDropped() {
        #expect(SessionState.decodePauseCauses("user,cosmicRays") == [.user])
        #expect(SessionState.decodePauseCauses("cosmicRays").isEmpty)
    }

    @Test("every PauseReason round-trips through the encoding")
    func everyCauseRoundTrips() {
        for cause in PauseReason.allCases {
            let raw = SessionState(phase: .paused, pauseCauses: [cause], phaseChangedAt: t0)
                .pauseCausesRaw
            #expect(SessionState.decodePauseCauses(raw) == [cause])
        }
        #expect(PauseReason.allCases.count == 9)
    }
}

// MARK: - Decoder totality

@Suite("Session phase decoding")
struct SessionPhaseDecodingTests {
    /// The switch's completeness is held here, not by the compiler. A seventh phase added
    /// without touching `decode(_:)` fails this test rather than silently decoding to
    /// `.complete` in production.
    @Test("every SessionPhase round-trips through decode(_:)")
    func everyPhaseRoundTrips() {
        for phase in SessionPhase.allCases {
            #expect(SessionPhase.decode(phase.rawValue) == phase, "\(phase) does not round-trip")
        }
        #expect(SessionPhase.allCases.count == 6)
    }

    @Test("every ResumablePhase round-trips through its exhaustive phase switch")
    func everyResumablePhaseRoundTrips() {
        for resumable in ResumablePhase.allCases {
            #expect(resumable.phase.rawValue == resumable.rawValue)
            #expect(ResumablePhase.decode(resumable.rawValue) == resumable)
            #expect(ResumablePhase.narrowing(resumable.phase) == resumable)
        }
        #expect(ResumablePhase.allCases.count == 3)
    }

    @Test("the three non-resumable phases narrow to nil rather than to focus")
    func nonResumablePhasesNarrowToNil() {
        #expect(ResumablePhase.narrowing(.paused) == nil)
        #expect(ResumablePhase.narrowing(.interrupted) == nil)
        #expect(ResumablePhase.narrowing(.complete) == nil)
    }

    @Test("the e01/e02 legacy raw values decode to their successors")
    func legacyAliasesDecode() {
        #expect(SessionPhase.decode("running") == .focus)
        #expect(SessionPhase.decode("ended") == .complete)
    }

    @Test("a raw value this build cannot interpret decodes to complete")
    func unknownRawDecodesToComplete() {
        #expect(SessionPhase.decode("hyperfocus") == .complete)
        #expect(SessionPhase.decode("") == .complete)
        #expect(ResumablePhase.decode("hyperfocus") == nil)
        #expect(ResumablePhase.decode(nil) == nil)
        // A terminal phase is not resumable, so it must not decode as one either.
        #expect(ResumablePhase.decode("complete") == nil)
    }
}

// MARK: - The nudge contract

@Suite("The nudge contract this machine declares for e05")
struct SessionInterventionContractTests {
    /// `.focus` only. During an intentional detour the user has declared the deviation
    /// deliberate; on a break, paused, interrupted or complete there is nothing to nudge
    /// about. e05's ladder must require this **and** `FocusStatus.permitsIntervention`.
    @Test("permitsIntervention is true for focus and false for the other five")
    func permitsInterventionForFocusAlone() {
        #expect(SessionPhase.focus.permitsIntervention)
        for phase in SessionPhase.allCases where phase != .focus {
            #expect(!phase.permitsIntervention, "\(phase) must not permit intervention")
        }
        #expect(SessionPhase.allCases.filter(\.permitsIntervention) == [.focus])
    }

    @Test("a started session begins in focus with no causes")
    func startedSessionShape() {
        let started = SessionState.started(at: t0)
        #expect(started.phase == .focus)
        #expect(started.pauseCauses.isEmpty)
        #expect(started.resumeTo == nil)
        #expect(started.endedAt == nil)
        #expect(started.phaseChangedAt == t0)
        #expect(started.pauseCausesInvariantHolds)
    }

    /// The undo journal reads this: user-initiated operations are undoable and system-driven
    /// pauses deliberately are not, because an auto-pause is not something a person meant to
    /// do.
    @Test("only a user-caused pause or resume counts as user-initiated")
    func userInitiatedEvents() {
        #expect(SessionEvent.paused(cause: .user).isUserInitiated)
        #expect(!SessionEvent.paused(cause: .screenLocked).isUserInitiated)
        #expect(SessionEvent.resumed(cause: .user).isUserInitiated)
        #expect(!SessionEvent.resumed(cause: .globalPause).isUserInitiated)
        #expect(!SessionEvent.breakStarted(reason: .idle).isUserInitiated)
        #expect(SessionEvent.completed.isUserInitiated)
    }

    @Test("every event kind has a stable raw value and a matching kind")
    func eventKindsAreStable() {
        #expect(SessionEventKind.allCases.count == 8)
        #expect(SessionEvent.detourStarted(reason: .user).kind == .detourStarted)
        #expect(SessionEvent.detourEnded.kind == .detourEnded)
        #expect(SessionEvent.breakStarted(reason: .user).kind == .breakStarted)
        #expect(SessionEvent.breakEnded.kind == .breakEnded)
        #expect(SessionEvent.paused(cause: .user).kind == .paused)
        #expect(SessionEvent.resumed(cause: .user).kind == .resumed)
        #expect(SessionEvent.interrupted(reason: .user).kind == .interrupted)
        #expect(SessionEvent.completed.kind == .completed)

        // The four events that carry no reason carry none in the row either.
        #expect(SessionEvent.detourEnded.reasonRaw == nil)
        #expect(SessionEvent.breakEnded.reasonRaw == nil)
        #expect(SessionEvent.completed.reasonRaw == nil)
        #expect(SessionEvent.paused(cause: .relaunch).reasonRaw == "relaunch")
    }
}
