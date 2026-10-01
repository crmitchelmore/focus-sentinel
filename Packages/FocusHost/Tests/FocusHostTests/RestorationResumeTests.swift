import FocusCore
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// **Resume lifts the pause a relaunch raised** (focus-mmty).
///
/// `SessionRestoration` pauses a session that came back from another boot, or from more than
/// `staleAfter` away, and documents the pause as "one click puts the person back where they
/// were". Until this bead the host's one click sent `resumed(cause: .user)` and nothing else, so
/// the machine refused it `notPausedForThatCause` and the cockpit — reading the same rule — never
/// enabled the button in the first place. This is the wiring proof, end to end through the store:
/// a session survives a reboot, comes back paused for that reason, and the person's Resume puts
/// it back in the phase it was in.
@Suite("Restoration resume")
@MainActor
struct RestorationResumeTests {
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

    /// Two launches over one store: the first on one boot, the second on whichever boot the
    /// test names.
    @MainActor
    struct Harness {
        let container: ModelContainer
        let clock: MovingClock

        init() throws {
            container = try FocusStore.makeContainer(kind: .inMemory)
            clock = MovingClock(now: RestorationResumeTests.reference)
        }

        func launch(boot: String) -> SessionHost {
            let context = container.mainContext
            return SessionHost(
                context: context,
                events: ActivityEventStore(context: context, dateProvider: clock),
                dateProvider: clock,
                uptimeClock: StillUptime(),
                bootIdentity: boot
            )
        }
    }

    @Test("a session that survived a reboot resumes on the person's one click")
    func aRebootedSessionResumes() throws {
        let harness = try Harness()
        let first = harness.launch(boot: "boot-a")
        first.startSession()
        #expect(first.snapshot?.phase == .focus)

        let second = harness.launch(boot: "boot-b")
        let restored = second.restore()
        #expect(restored?.pauseCauses == [.systemRestart])
        #expect(second.snapshot?.phase == .paused)
        #expect(second.snapshot?.userMayResume == true, "the cockpit must offer Resume here")

        second.resumeSession()
        #expect(second.lastRejection == nil)
        #expect(second.snapshot?.phase == .focus)
        #expect(second.snapshot?.pauseCauses.isEmpty == true)
    }

    @Test("a session restored stale resumes on the person's one click")
    func aStaleSessionResumes() throws {
        let harness = try Harness()
        let first = harness.launch(boot: "boot-a")
        first.startSession()
        first.startBreak()
        #expect(first.snapshot?.phase == .onBreak)

        harness.clock.advance(by: 16 * 60)
        let second = harness.launch(boot: "boot-a")
        let restored = second.restore()
        #expect(restored?.pauseCauses == [.relaunch])
        #expect(second.snapshot?.userMayResume == true)

        second.resumeSession()
        #expect(second.lastRejection == nil)
        // Back where they were: the break, not focus.
        #expect(second.snapshot?.phase == .onBreak)
    }

    @Test("a session the person paused before the reboot needs one click, not two")
    func aPausedSessionThatSurvivedARebootResumesOnce() throws {
        let harness = try Harness()
        let first = harness.launch(boot: "boot-a")
        first.startSession()
        first.pauseSession()
        #expect(first.snapshot?.pauseCauses == [.user])

        let second = harness.launch(boot: "boot-b")
        _ = second.restore()
        #expect(second.snapshot?.pauseCauses == [.user, .systemRestart])
        #expect(second.snapshot?.userMayResume == true)

        second.resumeSession()
        #expect(second.lastRejection == nil)
        #expect(second.snapshot?.phase == .focus)
    }

    /// The control: a lifecycle pause is still not the person's to lift, and the host sends
    /// nothing the machine would take for it.
    @Test("a reboot beside a lock leaves Resume refused for the lock")
    func aLockStillHolds() throws {
        let harness = try Harness()
        let first = harness.launch(boot: "boot-a")
        first.startSession()
        _ = try first.sessionStore.apply(.paused(cause: .screenLocked))

        let second = harness.launch(boot: "boot-b")
        _ = second.restore()
        #expect(second.snapshot?.pauseCauses == [.screenLocked, .systemRestart])
        #expect(second.snapshot?.userMayResume == false)
        #expect(second.snapshot?.causesTheUserCannotClear == [.screenLocked])
    }
}
