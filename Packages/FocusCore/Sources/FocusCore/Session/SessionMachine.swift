import Foundation

/// The session phase machine: forty-eight cells, fifty-one named outcomes, and no I/O.
///
/// `apply(_:to:at:)` is a **pure static function** — no clock, no store, no side effect, no
/// hidden state. Everything it needs arrives as an argument and everything it decides comes
/// back as a value. That is what makes the whole transition table a headless unit test rather
/// than something you have to run an app to find out about, and it is why this machine is
/// specified completely here: it is an *input* to e05's nudge ladder, and e05 adds nothing to
/// it.
///
/// ## The table
///
/// | from ＼ event | detourStarted | detourEnded | breakStarted | breakEnded | paused(cause) | resumed(cause) | interrupted | completed |
/// |---|---|---|---|---|---|---|---|---|
/// | **focus** | ✓ `intentionalDetour` | ✗ `noDetourInProgress` | ✓ `onBreak` | ✗ `noBreakInProgress` | ✓ `paused` | ✗ `notPaused` | ✓ `interrupted` | ✓ `complete` |
/// | **intentionalDetour** | ✗ `alreadyInPhase` | ✓ `focus` | ✗ `endDetourFirst` | ✗ `noBreakInProgress` | ✓ `paused` | ✗ `notPaused` | ✓ `interrupted` | ✓ `complete` |
/// | **onBreak** | ✗ `endBreakFirst` | ✗ `noDetourInProgress` | ✗ `alreadyInPhase` | ✓ `focus` | ✓ `paused` | ✗ `notPaused` | ✓ `interrupted` | ✓ `complete` |
/// | **paused** | ✗ `pausedSessionIsInert` | ✗ `pausedSessionIsInert` | ✗ `pausedSessionIsInert` | ✗ `pausedSessionIsInert` | ⊕ `causeAdded` / ✗ `alreadyInPhase` | ✓ `resumeTo ?? focus` / ⊕ `causeRemoved` / ✗ `notPausedForThatCause` | ✓ `interrupted` | ✓ `complete` |
/// | **interrupted** | ✗ `terminal` × 8 |||||||
/// | **complete** | ✗ `terminal` × 8 |||||||
///
/// Forty-six cells with one outcome each, `(paused, paused)` with two and `(paused, resumed)`
/// with three: **fifty-one outcomes, eighteen accepted (sixteen phase changes and two
/// cause-set changes) and thirty-three rejected.**
///
/// ## The rulings the table encodes, each with its reason
///
/// * **`breakStarted` is legal only from `focus`.** To take a break during a detour you end
///   the detour first. The UI does both in one click; the machine records two transitions,
///   which is what makes the timeline honest about what happened.
/// * **`paused` freezes everything.** No detour, break or their ends may be applied to a
///   paused session. A paused session is inert; that is what "paused" means, and it removes
///   eight cells of ambiguity.
/// * **`resumed(cause:)` returns to `resumeTo`**, set at the *first* pause and never
///   overwritten by a later cause. It exists for one reason: an auto-pause because the user
///   opened their password manager must return them to the break they were on, not to work
///   they had stopped. And it returns there only when the **last** cause is gone.
/// * **Self-transitions of the *phase* are always rejected.** The two `⊕` outcomes are not
///   exceptions: they change the cause set, not the phase, and they are themselves rejected
///   `alreadyInPhase` when the set would not change either.
/// * **A closed row rejects everything** (`sessionEnded`), before the table is consulted.
/// * **Time may not go backwards** (`clockWentBackwards`). Probe P-99 measured 2.96 s of
///   drift on this very machine over 8.55 days, so an NTP correction mid-session is an
///   ordinary event and must not corrupt the record.
public enum SessionMachine {
    /// Offer `event` to `state` at `instant`.
    ///
    /// - Parameters:
    ///   - event: what happened.
    ///   - state: the session as it stands.
    ///   - instant: the wall-clock moment, from an injected `DateProvider`. The machine reads
    ///     no clock of its own, which is what makes every one of the fifty-one outcomes
    ///     reproducible.
    public static func apply(
        _ event: SessionEvent,
        to state: SessionState,
        at instant: Date
    ) -> SessionTransition {
        // 1 — a closed row is closed, whatever its phase says. Checked before the table.
        if state.endedAt != nil {
            return .rejected(.sessionEnded)
        }

        // 2 — time may not run backwards.
        if instant < state.phaseChangedAt {
            return .rejected(.clockWentBackwards)
        }

        // 3 — the table.
        switch state.phase {
        case .interrupted, .complete:
            return .rejected(.terminal)

        case .focus:
            switch event {
            case .detourStarted:
                return accept(state, to: .intentionalDetour, event: event, at: instant)
            case .detourEnded:
                return .rejected(.noDetourInProgress)
            case .breakStarted:
                return accept(state, to: .onBreak, event: event, at: instant)
            case .breakEnded:
                return .rejected(.noBreakInProgress)
            case .paused(let cause):
                return firstPause(state, cause: cause, event: event, at: instant)
            case .resumed:
                return .rejected(.notPaused)
            case .interrupted:
                return accept(state, to: .interrupted, event: event, at: instant)
            case .completed:
                return accept(state, to: .complete, event: event, at: instant)
            }

        case .intentionalDetour:
            switch event {
            case .detourStarted:
                return .rejected(.alreadyInPhase)
            case .detourEnded:
                return accept(state, to: .focus, event: event, at: instant)
            case .breakStarted:
                return .rejected(.endDetourFirst)
            case .breakEnded:
                return .rejected(.noBreakInProgress)
            case .paused(let cause):
                return firstPause(state, cause: cause, event: event, at: instant)
            case .resumed:
                return .rejected(.notPaused)
            case .interrupted:
                return accept(state, to: .interrupted, event: event, at: instant)
            case .completed:
                return accept(state, to: .complete, event: event, at: instant)
            }

        case .onBreak:
            switch event {
            case .detourStarted:
                return .rejected(.endBreakFirst)
            case .detourEnded:
                return .rejected(.noDetourInProgress)
            case .breakStarted:
                return .rejected(.alreadyInPhase)
            case .breakEnded:
                return accept(state, to: .focus, event: event, at: instant)
            case .paused(let cause):
                return firstPause(state, cause: cause, event: event, at: instant)
            case .resumed:
                return .rejected(.notPaused)
            case .interrupted:
                return accept(state, to: .interrupted, event: event, at: instant)
            case .completed:
                return accept(state, to: .complete, event: event, at: instant)
            }

        case .paused:
            switch event {
            case .detourStarted, .detourEnded, .breakStarted, .breakEnded:
                return .rejected(.pausedSessionIsInert)
            case .paused(let cause):
                return addCause(state, cause: cause, event: event, at: instant)
            case .resumed(let cause):
                return removeCause(state, cause: cause, event: event, at: instant)
            case .interrupted:
                return accept(state, to: .interrupted, event: event, at: instant)
            case .completed:
                return accept(state, to: .complete, event: event, at: instant)
            }
        }
    }

    // MARK: - The three accepted shapes

    /// An ordinary phase change. Clears the pause causes and `resumeTo`, because every phase
    /// this is used for is a phase that is not `.paused` — the invariant is maintained here,
    /// once, rather than remembered at eight call sites.
    private static func accept(
        _ state: SessionState,
        to phase: SessionPhase,
        event: SessionEvent,
        at instant: Date
    ) -> SessionTransition {
        let next = SessionState(
            phase: phase,
            pauseCauses: [],
            resumeTo: nil,
            phaseChangedAt: instant,
            endedAt: state.endedAt
        )
        return .accepted(
            next,
            SessionTransitionValue(
                at: instant,
                from: state.phase,
                to: phase,
                event: event.kind,
                reasonRaw: event.reasonRaw,
                outcome: .accepted
            )
        )
    }

    /// The **first** pause: the phase moves, the cause set becomes exactly `[cause]`, and
    /// `resumeTo` is stamped from the phase being left — once, here, and never again.
    private static func firstPause(
        _ state: SessionState,
        cause: PauseReason,
        event: SessionEvent,
        at instant: Date
    ) -> SessionTransition {
        let next = SessionState(
            phase: .paused,
            pauseCauses: [cause],
            resumeTo: ResumablePhase.narrowing(state.phase),
            phaseChangedAt: instant,
            endedAt: state.endedAt
        )
        return .accepted(
            next,
            SessionTransitionValue(
                at: instant,
                from: state.phase,
                to: .paused,
                event: event.kind,
                reasonRaw: event.reasonRaw,
                outcome: .accepted
            )
        )
    }

    /// A second (or third) reason to be paused. The phase does not move, `resumeTo` is **not**
    /// overwritten, and `phaseChangedAt` does not advance — this is not a phase change, and
    /// pretending it was one would restart the staleness clock every time the screen locked.
    private static func addCause(
        _ state: SessionState,
        cause: PauseReason,
        event: SessionEvent,
        at instant: Date
    ) -> SessionTransition {
        guard !state.pauseCauses.contains(cause) else {
            // The set has not changed, so nothing happened.
            return .rejected(.alreadyInPhase)
        }
        let next = SessionState(
            phase: .paused,
            pauseCauses: state.pauseCauses.union([cause]),
            resumeTo: state.resumeTo,
            phaseChangedAt: state.phaseChangedAt,
            endedAt: state.endedAt
        )
        return .causeChanged(
            next,
            SessionTransitionValue(
                at: instant,
                from: .paused,
                to: .paused,
                event: event.kind,
                reasonRaw: event.reasonRaw,
                outcome: .causeAdded
            )
        )
    }

    /// A resume, authorised by the cause that paused.
    ///
    /// Removes **only** the named cause. If others remain the session stays paused and the
    /// outcome is `causeRemoved`; only when the set empties does the phase move to
    /// `resumeTo?.phase ?? .focus`. A cause the session does not hold is rejected — the wake
    /// handler cannot clear a `.user` pause it never set.
    private static func removeCause(
        _ state: SessionState,
        cause: PauseReason,
        event: SessionEvent,
        at instant: Date
    ) -> SessionTransition {
        guard state.pauseCauses.contains(cause) else {
            return .rejected(.notPausedForThatCause)
        }

        let remaining = state.pauseCauses.subtracting([cause])
        if remaining.isEmpty {
            let destination = state.resumeTo?.phase ?? .focus
            let next = SessionState(
                phase: destination,
                pauseCauses: [],
                resumeTo: nil,
                phaseChangedAt: instant,
                endedAt: state.endedAt
            )
            return .accepted(
                next,
                SessionTransitionValue(
                    at: instant,
                    from: .paused,
                    to: destination,
                    event: event.kind,
                    reasonRaw: event.reasonRaw,
                    outcome: .accepted
                )
            )
        }

        let next = SessionState(
            phase: .paused,
            pauseCauses: remaining,
            resumeTo: state.resumeTo,
            phaseChangedAt: state.phaseChangedAt,
            endedAt: state.endedAt
        )
        return .causeChanged(
            next,
            SessionTransitionValue(
                at: instant,
                from: .paused,
                to: .paused,
                event: event.kind,
                reasonRaw: event.reasonRaw,
                outcome: .causeRemoved
            )
        )
    }
}
