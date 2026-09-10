import FocusCore
import Foundation

/// **The three transitions that end an open nudge, noticed** (focus-d0a, U-1, R-83).
///
/// `NudgeHost` has always been able to answer them — `sessionEnded()`, `phaseLeftFocus()` and
/// `priorityChanged()` are three functions that expire the open question, de-escalate the ladder
/// and clear the session state. Nothing in the shipping graph ever called one. The only reference
/// to any of them anywhere in the repository was a test, so the running loop was never told the
/// session had ended, the phase had left focus, or the person had committed to something else —
/// and an open question stayed live and answerable hours after the situation it was asked about
/// had gone.
///
/// This is the part that has to be a value rather than a closure: the facts arrive as a *level*
/// (the session that is open now, the phase it is in now, the priority that is active now) and
/// the loop needs an *edge*. Deriving the edge in the composition root would put a rule nobody
/// could drive into the one file no test bundle can reach; deriving it here makes "a session that
/// ended is noticed exactly once" an assertion in `NudgeLifecycleWatchTests` rather than a claim.
///
/// ## The order the transitions are reported in, and why it does not matter much
///
/// A session ending is reported before a phase leaving focus, and a priority change last, because
/// each of `NudgeHost`'s three answers begins by expiring the open question and ends by taking
/// the surfaces down. After the first of them there is no open question left for the second to
/// write a second receipt about, which is the property that makes reporting all three of a
/// simultaneous change safe rather than a source of duplicate rows.
///
/// A phase leaving focus is **not** reported when the session that held it has gone: the session
/// ending is the larger fact and it is already being reported, and a loop told both would
/// de-escalate the ladder twice for one event.
struct NudgeLifecycleWatch: Equatable {
    /// One thing that happened, named as `NudgeHost` names it.
    enum Transition: String, CaseIterable, Equatable {
        case sessionEnded
        case phaseLeftFocus
        case priorityChanged
    }

    /// The session that was open the last time this was asked. `nil` before the first reading
    /// and whenever there is no session.
    private(set) var sessionID: UUID?
    /// The phase that session was in. `nil` when there was no session to have one.
    private(set) var phase: SessionPhase?
    /// The commitment that was active. `nil` before the first reading and whenever there is none.
    private(set) var priorityID: UUID?
    /// Whether anything has been observed yet. The first reading establishes a baseline and
    /// reports nothing: an application that has just launched into a running session has not
    /// watched a session start, and reporting three transitions at launch would de-escalate a
    /// ladder that has never escalated and expire a question that was never asked.
    private(set) var hasObserved = false

    /// Take one reading and say what changed.
    ///
    /// - Returns: the transitions to tell the loop about, in the order to tell it. Empty for the
    ///   overwhelmingly common case — the corroboration tick that found the world where it left
    ///   it — which is why this is called on every refresh without costing anything.
    mutating func observe(
        sessionID: UUID?,
        phase: SessionPhase?,
        priorityID: UUID?
    ) -> [Transition] {
        defer {
            self.sessionID = sessionID
            self.phase = phase
            self.priorityID = priorityID
            hasObserved = true
        }
        guard hasObserved else { return [] }

        var transitions: [Transition] = []

        // A session that is no longer the open one has ended, whether it completed, was
        // abandoned, or was replaced by a new one. `nil` previously means there was none, and a
        // session starting is not a session ending.
        let sessionWentAway = self.sessionID != nil && self.sessionID != sessionID
        if sessionWentAway { transitions.append(.sessionEnded) }

        // The phase left focus: a break, a detour, an interruption, a pause, completion. Only
        // reported for a session that is still the same one — otherwise the session ending above
        // is the honest description of what happened.
        if !sessionWentAway, self.phase == .focus, phase != .focus {
            transitions.append(.phaseLeftFocus)
        }

        // A different commitment. `nil` previously means the person had not committed to
        // anything, and a first commitment is not a change of one.
        if self.priorityID != nil, self.priorityID != priorityID {
            transitions.append(.priorityChanged)
        }

        return transitions
    }
}
