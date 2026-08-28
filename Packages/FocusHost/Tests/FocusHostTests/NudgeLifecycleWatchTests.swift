import FocusCore
import Foundation
import Testing

@testable import FocusHost

/// **The edges the loop was never told about** (focus-d0a).
///
/// `NudgeHost.sessionEnded()`, `phaseLeftFocus()` and `priorityChanged()` had three definitions
/// and zero production callers: `grep -rn` across `Packages/*/Sources` and `App` found the names
/// only in a test. So the loop was never told the session had ended, the phase had left focus, or
/// the person had committed to something else — and an open question stayed live and answerable
/// eight simulated hours later.
///
/// The facts arrive as a level and the loop needs an edge. These drive the part that turns one
/// into the other.
@Suite("The three transitions that end an open nudge")
struct NudgeLifecycleWatchTests {
    static let sessionA = UUID()
    static let sessionB = UUID()
    static let priorityA = UUID()
    static let priorityB = UUID()

    /// The first reading is a baseline, not three events.
    ///
    /// An application that launches straight into a running session has not watched that session
    /// start, and reporting a transition for it would de-escalate a ladder that has never
    /// escalated and expire a question that was never asked.
    @Test("the first reading establishes a baseline and reports nothing")
    func theFirstReadingIsABaseline() {
        var watch = NudgeLifecycleWatch()
        #expect(
            watch.observe(
                sessionID: Self.sessionA, phase: .focus, priorityID: Self.priorityA
            ).isEmpty
        )
    }

    @Test("a world that has not moved is not an event")
    func anUnchangedReadingReportsNothing() {
        var watch = NudgeLifecycleWatch()
        _ = watch.observe(sessionID: Self.sessionA, phase: .focus, priorityID: Self.priorityA)
        #expect(
            watch.observe(
                sessionID: Self.sessionA, phase: .focus, priorityID: Self.priorityA
            ).isEmpty
        )
    }

    // MARK: - The session

    @Test("a session that is no longer open has ended")
    func aClosedSessionEnds() {
        var watch = NudgeLifecycleWatch()
        _ = watch.observe(sessionID: Self.sessionA, phase: .focus, priorityID: Self.priorityA)
        #expect(
            watch.observe(sessionID: nil, phase: nil, priorityID: Self.priorityA)
                == [.sessionEnded]
        )
    }

    /// A session replaced by a different one has still ended — and the phase change that comes
    /// with it is not reported separately, because the session ending is the larger fact and a
    /// loop told both would de-escalate the ladder twice for one event.
    @Test("a session replaced by another reports the ending alone")
    func aReplacedSessionReportsTheEndingAlone() {
        var watch = NudgeLifecycleWatch()
        _ = watch.observe(sessionID: Self.sessionA, phase: .focus, priorityID: Self.priorityA)
        #expect(
            watch.observe(sessionID: Self.sessionB, phase: .onBreak, priorityID: Self.priorityA)
                == [.sessionEnded]
        )
    }

    @Test("a session starting is not a session ending")
    func aStartedSessionIsNotAnEnding() {
        var watch = NudgeLifecycleWatch()
        _ = watch.observe(sessionID: nil, phase: nil, priorityID: Self.priorityA)
        #expect(
            watch.observe(sessionID: Self.sessionA, phase: .focus, priorityID: Self.priorityA)
                .isEmpty
        )
    }

    // MARK: - The phase

    /// Every phase that is not `focus` is one the loop must hear about: a break, a detour, a
    /// pause, an interruption, completion.
    @Test(
        "the phase leaving focus is reported for every phase that is not focus",
        arguments: SessionPhase.allCases.filter { $0 != .focus }
    )
    func leavingFocusIsReported(_ phase: SessionPhase) {
        var watch = NudgeLifecycleWatch()
        _ = watch.observe(sessionID: Self.sessionA, phase: .focus, priorityID: Self.priorityA)
        #expect(
            watch.observe(sessionID: Self.sessionA, phase: phase, priorityID: Self.priorityA)
                == [.phaseLeftFocus]
        )
    }

    @Test("returning to focus is not leaving it")
    func returningToFocusIsNotAnEvent() {
        var watch = NudgeLifecycleWatch()
        _ = watch.observe(sessionID: Self.sessionA, phase: .onBreak, priorityID: Self.priorityA)
        #expect(
            watch.observe(sessionID: Self.sessionA, phase: .focus, priorityID: Self.priorityA)
                .isEmpty
        )
    }

    // MARK: - The commitment

    @Test("a different commitment is reported")
    func aDifferentCommitmentIsReported() {
        var watch = NudgeLifecycleWatch()
        _ = watch.observe(sessionID: Self.sessionA, phase: .focus, priorityID: Self.priorityA)
        #expect(
            watch.observe(sessionID: Self.sessionA, phase: .focus, priorityID: Self.priorityB)
                == [.priorityChanged]
        )
    }

    @Test("a commitment cleared is a commitment changed")
    func aClearedCommitmentIsReported() {
        var watch = NudgeLifecycleWatch()
        _ = watch.observe(sessionID: Self.sessionA, phase: .focus, priorityID: Self.priorityA)
        #expect(
            watch.observe(sessionID: Self.sessionA, phase: .focus, priorityID: nil)
                == [.priorityChanged]
        )
    }

    @Test("a first commitment is not a change of commitment")
    func aFirstCommitmentIsNotAChange() {
        var watch = NudgeLifecycleWatch()
        _ = watch.observe(sessionID: Self.sessionA, phase: .focus, priorityID: nil)
        #expect(
            watch.observe(sessionID: Self.sessionA, phase: .focus, priorityID: Self.priorityA)
                .isEmpty
        )
    }

    /// Everything at once, in the order `NudgeHost` is told: the ending first, because each of
    /// its three answers expires the open question and takes the surfaces down.
    @Test("a session ending under a new commitment reports both, ending first")
    func simultaneousChangesAreOrdered() {
        var watch = NudgeLifecycleWatch()
        _ = watch.observe(sessionID: Self.sessionA, phase: .focus, priorityID: Self.priorityA)
        #expect(
            watch.observe(sessionID: nil, phase: nil, priorityID: Self.priorityB)
                == [.sessionEnded, .priorityChanged]
        )
    }
}
