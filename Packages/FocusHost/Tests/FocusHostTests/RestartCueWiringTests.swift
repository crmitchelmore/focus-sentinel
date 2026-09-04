import FocusCore
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// **That `breakEnded` produces a cue at all** (F-67, focus-2w1).
///
/// `RestartCueTests` in `FocusCore` proves the rule. This proves the fact the rule needs and that
/// nothing in the application used to hold: **when this session last came back from a break.**
/// The snapshot cannot say it — it carries the phase and not the event that produced it, and a
/// session enters `focus` from a break, from a detour and from being started — so the moment is
/// taken where the machine answers, and only when it answered *yes*.
@Suite("Restart cue wiring")
@MainActor
struct RestartCueWiringTests {
    /// A wall clock a test can move. A break is a thing that happens over time.
    final class MovingClock: DateProvider, @unchecked Sendable {
        private let lock = NSLock()
        private var value: Date

        init(now: Date) { self.value = now }

        var now: Date {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func advance(by seconds: TimeInterval) {
            lock.lock()
            defer { lock.unlock() }
            value = value.addingTimeInterval(seconds)
        }
    }

    struct StillUptime: UptimeClock {
        var uptimeSeconds: Double { 100_000 }
    }

    static let reference = Date(timeIntervalSince1970: 1_767_225_600)

    @MainActor
    struct Harness {
        let container: ModelContainer
        let clock: MovingClock
        let host: SessionHost

        init() throws {
            container = try FocusStore.makeContainer(kind: .inMemory)
            let context = container.mainContext
            clock = MovingClock(now: RestartCueWiringTests.reference)
            host = SessionHost(
                context: context,
                events: ActivityEventStore(context: context, dateProvider: clock),
                dateProvider: clock,
                uptimeClock: StillUptime(),
                bootIdentity: "restart-cue-wiring"
            )
        }

        /// The cue as the composition root assembles it, from the two facts the host holds.
        func cue(isBackOnTask: Bool = false) -> RestartCue {
            RestartCue.state(
                phase: host.snapshot?.phase,
                sinceBreakEnded: host.breakEndedAt.map {
                    .seconds(Int(clock.now.timeIntervalSince($0)))
                },
                isBackOnTask: isBackOnTask
            )
        }
    }

    /// **The bead's own witness.** A session, a break, the break ending, and the grace running
    /// out — and the cue is due. Before the wiring this went all the way to `.silent`, because
    /// nothing in the application recorded that a break had ever ended.
    @Test("a break that ends and is not returned from produces a cue")
    func aBreakThatEndsProducesACue() throws {
        let harness = try Harness()
        harness.host.startSession()
        #expect(harness.cue() == .silent(.noBreakHasEnded))

        harness.host.startBreak()
        #expect(harness.host.snapshot?.phase == .onBreak)
        #expect(harness.cue() == .silent(.notRunning))

        harness.clock.advance(by: 600)
        harness.host.endBreak()
        #expect(harness.host.snapshot?.phase == .focus)
        #expect(harness.host.breakEndedAt != nil, "the accepted breakEnded was not recorded")
        // Straight after: the person is allowed a moment.
        #expect(harness.cue() == .silent(.withinGrace))

        harness.clock.advance(by: 130)
        #expect(harness.cue() == .due)
        // And the outcome clears it without anybody pressing anything.
        #expect(harness.cue(isBackOnTask: true) == .silent(.backOnTask))
    }

    /// **A refused `breakEnded` records nothing.** The control the reading above needs: a host
    /// that stamped the moment on every attempt would produce a cue for a session that never
    /// took a break, which is the app inventing a break to have an opinion about.
    @Test("a breakEnded the machine refused leaves no moment behind")
    func aRefusedBreakEndedRecordsNothing() throws {
        let harness = try Harness()
        harness.host.startSession()

        // Ending a break that is not in progress: `SessionStoreTests` records this as
        // `.noBreakInProgress`, and it must write nothing here either.
        harness.host.endBreak()
        #expect(harness.host.breakEndedAt == nil)

        harness.clock.advance(by: 3_600)
        #expect(harness.cue() == .silent(.noBreakHasEnded))
    }

    /// A break in a session that is over is history, and a new session starts with none.
    @Test("the moment does not survive its session")
    func theMomentDoesNotSurviveItsSession() throws {
        let harness = try Harness()
        harness.host.startSession()
        harness.host.startBreak()
        harness.clock.advance(by: 600)
        harness.host.endBreak()
        #expect(harness.host.breakEndedAt != nil)

        harness.clock.advance(by: 130)
        harness.host.completeSession()
        // A completed session is not an *open* one, so the projection is `nil` and the silence
        // is `noSession` rather than `sessionIsOver`. Both are real; `sessionIsOver` is what an
        // interrupted session that is still open answers, and `RestartCueTests` folds over it.
        #expect(harness.cue() == .silent(.noSession))

        harness.host.startSession()
        #expect(harness.host.breakEndedAt == nil, "a new session inherited the old one's break")
        #expect(harness.cue() == .silent(.noBreakHasEnded))
    }
}
