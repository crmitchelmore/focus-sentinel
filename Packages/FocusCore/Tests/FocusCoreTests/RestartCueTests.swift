import Foundation
import Testing

@testable import FocusCore

/// **The break is over, and the person has not gone back** (F-67, focus-2w1).
///
/// `SessionEvent.breakEnded` and the break's suppression have shipped since e03, and the app did
/// nothing whatever with the ending. This is the rule that decides whether the ambient rung says
/// so — and, as much as the rule, the six named ways of being silent, because "no cue" covered
/// six different situations and a boolean could not tell a test which one it was in.
@Suite("Restart cue")
struct RestartCueTests {
    /// **The fold.** Every phase produces an answer, and the answer is the same whichever way the
    /// other two facts fall for the phases that can never speak.
    ///
    /// Written over `SessionPhase.allCases` rather than over the arms somebody remembered: a
    /// seventh phase added in a later epic fails this until whoever adds it decides what a break
    /// ending inside it means.
    @Test("every session phase has an answer, and only a running one can speak", arguments: SessionPhase.allCases)
    func everyPhaseIsAnswered(phase: SessionPhase) {
        let longAgo = RestartCue.grace + .seconds(60)
        let cue = RestartCue.state(phase: phase, sinceBreakEnded: longAgo, isBackOnTask: false)

        switch phase {
        case .focus, .intentionalDetour:
            #expect(cue == .due, "\(phase) had a break end long ago and says nothing")
        case .complete, .interrupted:
            #expect(cue == .silent(.sessionIsOver))
        case .paused, .onBreak:
            #expect(cue == .silent(.notRunning))
        }

        // And a phase that cannot speak cannot be made to by any combination of the other two.
        if phase != .focus && phase != .intentionalDetour {
            for since in [nil, Duration.seconds(0), longAgo] as [Duration?] {
                for back in [true, false] {
                    #expect(
                        RestartCue.state(
                            phase: phase, sinceBreakEnded: since, isBackOnTask: back
                        ).isDue == false
                    )
                }
            }
        }
    }

    /// **No session, no cue** — the state a fresh launch is in, and the one a reading taken
    /// before anything happened would otherwise have to call `false` without saying why.
    @Test("no session at all is its own silence")
    func noSessionIsItsOwnSilence() {
        #expect(
            RestartCue.state(phase: nil, sinceBreakEnded: .seconds(3_600), isBackOnTask: false)
                == .silent(.noSession)
        )
    }

    /// A session that has never taken a break is not a session anybody has failed to return from.
    @Test("a session that never took a break says nothing")
    func noBreakIsItsOwnSilence() {
        #expect(
            RestartCue.state(phase: .focus, sinceBreakEnded: nil, isBackOnTask: false)
                == .silent(.noBreakHasEnded)
        )
    }

    /// **Both sides of the grace**, because a cue that fired the instant a break ended would be
    /// the app standing over somebody as they sat down, and one that never fired is the defect
    /// F-67 names.
    @Test("the grace is a boundary, and it cuts where it says")
    func theGraceCutsWhereItSays() {
        let justInside = RestartCue.grace - .seconds(1)
        #expect(
            RestartCue.state(phase: .focus, sinceBreakEnded: justInside, isBackOnTask: false)
                == .silent(.withinGrace)
        )
        #expect(
            RestartCue.state(phase: .focus, sinceBreakEnded: .zero, isBackOnTask: false)
                == .silent(.withinGrace)
        )
        // Inclusive at the boundary: the grace is how long the person has, not how long plus one.
        #expect(
            RestartCue.state(phase: .focus, sinceBreakEnded: .seconds(120), isBackOnTask: false)
                == .due
        )
        #expect(RestartCue.grace == .seconds(120))
    }

    /// **The outcome clears it.** Being back is not a dismissal and there is nothing to press:
    /// the cue is a state, so it stops being true rather than being answered.
    @Test("being back on task is silence, however long ago the break ended")
    func beingBackIsSilence() {
        for since in [Duration.seconds(0), .seconds(120), .seconds(86_400)] {
            #expect(
                RestartCue.state(phase: .focus, sinceBreakEnded: since, isBackOnTask: true)
                    == .silent(.backOnTask)
            )
        }
    }

    /// The cue has exactly one sentence, and silence adds no word at all — an empty sentence
    /// appended to the status label reads as a pause to somebody listening.
    @Test("only the due cue has a sentence")
    func onlyTheDueCueSpeaks() {
        #expect(RestartCue.due.copyKey == "nudge.restart.cue")
        #expect(RestartCue.due.copyResource != nil)
        for reason in RestartCue.Reason.allCases {
            #expect(RestartCue.silent(reason).copyKey == nil)
            #expect(RestartCue.silent(reason).copyResource == nil)
        }
    }

    /// Every named silence is reachable from `state(…)` — a reason nothing can produce is a
    /// reason nobody can act on, and would sit in the vocabulary looking like a case that is
    /// covered.
    @Test("every named silence is a state the rule can actually reach")
    func everySilenceIsReachable() {
        var reached = Set<RestartCue.Reason>()
        let phases: [SessionPhase?] = [nil] + SessionPhase.allCases.map { $0 }
        let spans: [Duration?] = [nil, .zero, RestartCue.grace, RestartCue.grace + .seconds(1)]
        for phase in phases {
            for span in spans {
                for back in [true, false] {
                    if case .silent(let reason) = RestartCue.state(
                        phase: phase, sinceBreakEnded: span, isBackOnTask: back
                    ) {
                        reached.insert(reason)
                    }
                }
            }
        }
        #expect(reached == Set(RestartCue.Reason.allCases), "unreachable: \(Set(RestartCue.Reason.allCases).subtracting(reached))")
    }
}
