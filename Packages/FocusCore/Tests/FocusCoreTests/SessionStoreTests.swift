import Foundation
import SwiftData
import Testing

@testable import FocusCore

/// A wall clock a test can move, which the session store needs because a session is a thing
/// that happens over time and `FixedDateProvider` is by definition fixed.
final class MovingDateProvider: DateProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(now: Date = FixedDateProvider.reference.now) {
        self.value = now
    }

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

    func set(_ instant: Date) {
        lock.lock()
        defer { lock.unlock() }
        value = instant
    }
}

/// An uptime source a test can move. `TestUptimeClock` is a value type, so a copy handed to
/// the store can never be advanced from outside it.
final class MovingUptimeClock: UptimeClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double

    init(uptimeSeconds: Double = 100_000) {
        self.value = uptimeSeconds
    }

    var uptimeSeconds: Double {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by seconds: Double) {
        precondition(seconds >= 0, "an uptime clock must never move backwards")
        lock.lock()
        defer { lock.unlock() }
        value += seconds
    }
}

/// A store and the container that owns it, kept alive together — the same reason
/// `PriorityStoreHarness` exists.
@MainActor
struct SessionStoreHarness {
    let container: ModelContainer
    let store: SessionStore
    let clock: MovingDateProvider
    let uptime: MovingUptimeClock
    let bootIdentity: String

    init(
        clock: MovingDateProvider = MovingDateProvider(),
        uptime: MovingUptimeClock = MovingUptimeClock(),
        bootIdentity: String = "1786742847.869178",
        url: URL? = nil
    ) throws {
        container = try FocusStore.makeContainer(kind: url.map { .temporary($0) } ?? .inMemory)
        self.clock = clock
        self.uptime = uptime
        self.bootIdentity = bootIdentity
        store = SessionStore(
            context: container.mainContext,
            dateProvider: clock,
            uptimeClock: uptime,
            bootIdentity: bootIdentity
        )
    }

    var context: ModelContext { container.mainContext }

    func sessions() throws -> [FocusSchemaV3.FocusSessionRecord] {
        try context.fetch(FetchDescriptor<FocusSchemaV3.FocusSessionRecord>())
    }

    func transitionRows() throws -> [FocusSchemaV3.SessionTransitionRecord] {
        try context.fetch(FetchDescriptor<FocusSchemaV3.SessionTransitionRecord>())
            .sorted { lhs, rhs in
                if lhs.at != rhs.at { return lhs.at < rhs.at }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    /// A manager configured the way a headless test gets one.
    static func makeUndoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.levelsOfUndo = 0
        return undo
    }
}

@MainActor
@Suite("Session store")
struct SessionStoreTests {
    // MARK: - Starting

    @Test("Starting creates one open session in focus, with the anchor and boot identity")
    func startCreatesAFocusedSession() throws {
        let harness = try SessionStoreHarness()

        let id = try harness.store.start()

        let record = try #require(try harness.store.openSession())
        #expect(record.id == id)
        #expect(record.phase == .focus)
        #expect(record.startedAt == harness.clock.now)
        #expect(record.phaseChangedAt == harness.clock.now)
        #expect(record.endedAt == nil)
        #expect(record.pauseCauses.isEmpty)
        #expect(record.uptimeAnchorSeconds == harness.uptime.uptimeSeconds)
        #expect(record.bootIdentity == harness.bootIdentity)
        // Starting is not an event on a state; it produces the first one, so the log is empty.
        #expect(try harness.transitionRows().isEmpty)
    }

    @Test("A second start is refused while one is open")
    func onlyOneSessionIsOpen() throws {
        let harness = try SessionStoreHarness()
        let first = try harness.store.start()

        #expect(throws: SessionStoreError.sessionAlreadyOpen(first)) {
            try harness.store.start()
        }
    }

    @Test("An event offered with no open session is a caller mistake, not a rejection")
    func noOpenSessionThrows() throws {
        let harness = try SessionStoreHarness()

        #expect(throws: SessionStoreError.noOpenSession) {
            try harness.store.apply(.completed)
        }
    }

    // MARK: - Accepted transitions are written

    @Test("An accepted transition writes one row, and it moves the phase clock and the anchor")
    func acceptedTransitionWritesARow() throws {
        let harness = try SessionStoreHarness()
        try harness.store.start()
        harness.clock.advance(by: 60)
        harness.uptime.advance(by: 60)

        let transition = try harness.store.apply(.breakStarted(reason: .user))

        guard case .accepted = transition else {
            Issue.record("a break from focus must be accepted")
            return
        }

        let rows = try harness.transitionRows()
        #expect(rows.count == 1)
        #expect(rows[0].fromRaw == "focus")
        #expect(rows[0].toRaw == "onBreak")
        #expect(rows[0].eventRaw == "breakStarted")
        #expect(rows[0].reasonRaw == "user")
        #expect(rows[0].outcomeRaw == "accepted")

        let record = try #require(try harness.store.openSession())
        #expect(record.phase == .onBreak)
        #expect(record.phaseChangedAt == harness.clock.now)
        #expect(record.uptimeAnchorSeconds == harness.uptime.uptimeSeconds)
    }

    @Test("A rejected transition writes nothing at all")
    func rejectedTransitionWritesNothing() throws {
        let harness = try SessionStoreHarness()
        try harness.store.start()

        // Ending a break that is not in progress.
        let transition = try harness.store.apply(.breakEnded)

        #expect(transition.rejection == .noBreakInProgress)
        #expect(try harness.transitionRows().isEmpty)
        #expect(try harness.store.openSession()?.phase == .focus)
    }

    @Test("Every one of the eight events is refused by a terminal session, and writes nothing")
    func terminalSessionWritesNothing() throws {
        let harness = try SessionStoreHarness()
        try harness.store.start()
        harness.clock.advance(by: 10)
        try harness.store.complete()

        let rowsAfterComplete = try harness.transitionRows().count

        // The row is closed, so `sessionEnded` is the refusal, checked before the table.
        // Every event is offered to the same closed row.
        let record = try #require(try harness.store.session(id: harness.sessions()[0].id))
        for event in Self.everyEvent {
            let transition = try harness.store.apply(event, to: record)
            #expect(transition.rejection == .sessionEnded)
        }
        #expect(try harness.transitionRows().count == rowsAfterComplete)
    }

    static let everyEvent: [SessionEvent] = [
        .detourStarted(reason: .user),
        .detourEnded,
        .breakStarted(reason: .user),
        .breakEnded,
        .paused(cause: .user),
        .resumed(cause: .user),
        .interrupted(reason: .user),
        .completed
    ]

    // MARK: - The two cause-set outcomes

    @Test("A second pause cause writes a row with fromRaw == toRaw and outcome causeAdded")
    func causeAddedWritesADistinguishableRow() throws {
        let harness = try SessionStoreHarness()
        try harness.store.start()
        harness.clock.advance(by: 10)
        try harness.store.apply(.paused(cause: .user))
        let phaseChangedAtFirstPause = try harness.store.openSession()?.phaseChangedAt

        harness.clock.advance(by: 10)
        harness.uptime.advance(by: 10)
        let transition = try harness.store.apply(.paused(cause: .screenLocked))

        guard case .causeChanged = transition else {
            Issue.record("a second cause must be a cause change rather than a phase change")
            return
        }

        let rows = try harness.transitionRows()
        #expect(rows.count == 2)
        #expect(rows[1].fromRaw == "paused")
        #expect(rows[1].toRaw == "paused")
        #expect(rows[1].fromRaw == rows[1].toRaw)
        #expect(rows[1].outcomeRaw == "causeAdded")
        #expect(rows[1].reasonRaw == "screenLocked")

        let record = try #require(try harness.store.openSession())
        #expect(record.pauseCauses == [.user, .screenLocked])
        // Not a phase change: the staleness clock does not restart every time the screen locks.
        #expect(record.phaseChangedAt == phaseChangedAtFirstPause)
    }

    @Test("A resume that leaves causes standing writes a causeRemoved row and stays paused")
    func causeRemovedWritesADistinguishableRow() throws {
        let harness = try SessionStoreHarness()
        try harness.store.start()
        harness.clock.advance(by: 10)
        try harness.store.apply(.paused(cause: .user))
        harness.clock.advance(by: 10)
        try harness.store.apply(.paused(cause: .screenLocked))

        harness.clock.advance(by: 10)
        let transition = try harness.store.apply(.resumed(cause: .screenLocked))

        guard case .causeChanged = transition else {
            Issue.record("resuming one of two causes must be a cause change")
            return
        }

        let rows = try harness.transitionRows()
        #expect(rows.last?.outcomeRaw == "causeRemoved")
        #expect(rows.last?.fromRaw == rows.last?.toRaw)

        let record = try #require(try harness.store.openSession())
        // The unlock lifted the lock's pause and left the user's standing.
        #expect(record.phase == .paused)
        #expect(record.pauseCauses == [.user])
    }

    @Test("A resume naming a cause the session does not hold is rejected and writes nothing")
    func mismatchedResumeIsRejected() throws {
        let harness = try SessionStoreHarness()
        try harness.store.start()
        harness.clock.advance(by: 10)
        try harness.store.apply(.paused(cause: .user))
        let rowsBefore = try harness.transitionRows().count

        let transition = try harness.store.apply(.resumed(cause: .globalPause))

        #expect(transition.rejection == .notPausedForThatCause)
        #expect(try harness.transitionRows().count == rowsBefore)
        #expect(try harness.store.openSession()?.pauseCauses == [.user])
    }

    @Test("The last cause returns the session to the phase it was in, exactly once")
    func lastCauseReturnsToResumeTo() throws {
        let harness = try SessionStoreHarness()
        try harness.store.start()
        harness.clock.advance(by: 10)
        try harness.store.apply(.breakStarted(reason: .user))
        harness.clock.advance(by: 10)
        try harness.store.apply(.paused(cause: .sensitiveApp))

        #expect(try harness.store.openSession()?.resumeTo == .onBreak)

        harness.clock.advance(by: 10)
        try harness.store.apply(.resumed(cause: .sensitiveApp))

        let record = try #require(try harness.store.openSession())
        // An auto-pause because a password manager came forward returns the person to the
        // break they were on, not to work they had stopped.
        #expect(record.phase == .onBreak)
        #expect(record.pauseCauses.isEmpty)
        #expect(record.resumeTo == nil)
    }

    // MARK: - The persisted cause set

    @Test("A two-cause set round-trips through a store reopen")
    func pauseCausesRoundTripThroughAReopen() throws {
        let directory = URL.temporaryDirectory.appending(
            path: "focus-session-store-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "FocusSentinel.store", directoryHint: .notDirectory)

        let sessionID: UUID
        do {
            let harness = try SessionStoreHarness(url: url)
            sessionID = try harness.store.start()
            harness.clock.advance(by: 10)
            try harness.store.apply(.paused(cause: .user))
            harness.clock.advance(by: 10)
            try harness.store.apply(.paused(cause: .screenLocked))

            let record = try #require(try harness.store.openSession())
            // Sorted and comma-joined, so the encoding is deterministic and two identical
            // pauses produce two identical columns.
            #expect(record.pauseCausesRaw == "screenLocked,user")
        }

        // A second container over the same file — the store as a later launch finds it.
        let reopened = try SessionStoreHarness(url: url)
        let record = try #require(try reopened.store.session(id: sessionID))
        #expect(record.pauseCauses == [.user, .screenLocked])
        #expect(record.phase == .paused)
        #expect(record.resumeTo == .focus)
    }

    @Test("A non-paused phase stores no causes at all")
    func nonPausedPhasesStoreNoCauses() throws {
        let harness = try SessionStoreHarness()
        try harness.store.start()

        let record = try #require(try harness.store.openSession())
        #expect(record.pauseCausesRaw == nil)
        #expect(harness.store.state(of: record).pauseCausesInvariantHolds)
    }

    // MARK: - Interruption capture (F-101)

    @Test("Interrupting stores the reason, the note and the last-active bundle identifier")
    func interruptStoresItsThreeFields() throws {
        let harness = try SessionStoreHarness()
        try harness.store.start()
        harness.clock.advance(by: 60)

        let transition = try harness.store.interrupt(
            reason: .priorityChanged,
            note: "  half way through the second section  ",
            lastActiveBundleID: "com.apple.TextEdit"
        )

        guard case .accepted = transition else {
            Issue.record("interrupting a focused session must be accepted")
            return
        }

        let record = try #require(try harness.store.session(id: harness.sessions()[0].id))
        #expect(record.phase == .interrupted)
        #expect(record.endedAt == harness.clock.now)
        #expect(record.interruptionReasonRaw == "priorityChanged")
        #expect(record.restartPointNote == "half way through the second section")
        // A bundle identifier and nothing else. Never a window title, never a document.
        #expect(record.lastActiveBundleID == "com.apple.TextEdit")
    }

    @Test("Interrupting with every field empty is allowed, and stores nothing it was not given")
    func interruptWithEmptyFields() throws {
        let harness = try SessionStoreHarness()
        try harness.store.start()
        harness.clock.advance(by: 60)

        try harness.store.interrupt(note: "   ")

        let record = try #require(try harness.store.session(id: harness.sessions()[0].id))
        #expect(record.interruptionReasonRaw == "user")
        // Whitespace is not a note. Reflection is offered, never extracted.
        #expect(record.restartPointNote == nil)
        #expect(record.lastActiveBundleID == nil)
    }

    @Test("Complete is enabled with every field empty and closes the row")
    func completeNeedsNothing() throws {
        let harness = try SessionStoreHarness()
        try harness.store.start()
        harness.clock.advance(by: 900)

        let transition = try harness.store.complete()

        guard case .accepted = transition else {
            Issue.record("completing a focused session must be accepted")
            return
        }
        let record = try #require(try harness.store.session(id: harness.sessions()[0].id))
        #expect(record.phase == .complete)
        #expect(record.endedAt == harness.clock.now)
        #expect(record.restartPointNote == nil)
        // And there is no open session left to offer anything to.
        #expect(try harness.store.openSession() == nil)
    }

    @Test("A terminal session is closed in the same save as its last transition row")
    func terminalIsNeverOpenAndTerminalAtOnce() throws {
        let harness = try SessionStoreHarness()
        try harness.store.start()
        harness.clock.advance(by: 10)
        try harness.store.complete()

        let record = try #require(try harness.store.session(id: harness.sessions()[0].id))
        #expect(record.phase.isTerminal)
        #expect(record.endedAt != nil)
        #expect(try harness.transitionRows().last?.toRaw == "complete")
    }

    // MARK: - Undo: a person's acts only

    @Test("Starting is undoable, and undo removes the session")
    func startIsUndoable() throws {
        let harness = try SessionStoreHarness()
        let undo = SessionStoreHarness.makeUndoManager()

        try harness.store.start(undo: undo)
        #expect(try harness.sessions().count == 1)

        undo.undo()

        #expect(try harness.sessions().isEmpty)
        #expect(try harness.store.openSession() == nil)
    }

    @Test("A user pause is undoable and undo takes its transition row with it")
    func userPauseIsUndoable() throws {
        let harness = try SessionStoreHarness()
        let undo = SessionStoreHarness.makeUndoManager()
        try harness.store.start(undo: undo)
        harness.clock.advance(by: 30)

        try harness.store.apply(.paused(cause: .user), undo: undo)
        #expect(try harness.store.openSession()?.phase == .paused)
        #expect(try harness.transitionRows().count == 1)

        undo.undo()

        let record = try #require(try harness.store.openSession())
        #expect(record.phase == .focus)
        #expect(record.pauseCauses.isEmpty)
        // Undo is not another thing that happened: leaving the row in would make the timeline
        // claim a pause the person took back.
        #expect(try harness.transitionRows().isEmpty)
    }

    @Test("Redo puts a user pause back")
    func userPauseRedoes() throws {
        let harness = try SessionStoreHarness()
        let undo = SessionStoreHarness.makeUndoManager()
        try harness.store.start(undo: undo)
        harness.clock.advance(by: 30)
        try harness.store.apply(.paused(cause: .user), undo: undo)

        undo.undo()
        #expect(try harness.store.openSession()?.phase == .focus)

        undo.redo()
        let record = try #require(try harness.store.openSession())
        #expect(record.phase == .paused)
        #expect(record.pauseCauses == [.user])
    }

    @Test("A system-driven pause is deliberately NOT undoable")
    func systemPauseIsNotUndoable() throws {
        let harness = try SessionStoreHarness()
        let undo = SessionStoreHarness.makeUndoManager()
        try harness.store.start(undo: undo)
        harness.clock.advance(by: 30)

        // The screen locked. Nobody meant to do that, and offering to undo it would be
        // offering to undo the world.
        try harness.store.apply(.paused(cause: .screenLocked), undo: undo)
        #expect(try harness.store.openSession()?.phase == .paused)

        undo.undo()

        // The undo stack popped the *start*, because the pause never went onto it.
        #expect(try harness.sessions().isEmpty)
    }

    @Test("Every pause cause but .user is system-driven, and every one of them says so")
    func onlyTheUserCausePausesUndoably() {
        for cause in PauseReason.allCases {
            #expect(SessionEvent.paused(cause: cause).isUserInitiated == (cause == .user))
            #expect(SessionEvent.resumed(cause: cause).isUserInitiated == (cause == .user))
        }
    }

    @Test("Interrupting is undoable, and undo restores the reason fields as well as the phase")
    func interruptIsUndoable() throws {
        let harness = try SessionStoreHarness()
        let undo = SessionStoreHarness.makeUndoManager()
        try harness.store.start(undo: undo)
        harness.clock.advance(by: 30)

        try harness.store.interrupt(
            reason: .appQuit,
            note: "mid sentence",
            lastActiveBundleID: "com.apple.Terminal",
            undo: undo
        )
        #expect(try harness.sessions()[0].phase == .interrupted)

        undo.undo()

        let record = try #require(try harness.store.openSession())
        #expect(record.phase == .focus)
        #expect(record.endedAt == nil)
        #expect(record.interruptionReasonRaw == nil)
        #expect(record.restartPointNote == nil)
        #expect(record.lastActiveBundleID == nil)
    }

    @Test("Completing is undoable and reopens the session")
    func completeIsUndoable() throws {
        let harness = try SessionStoreHarness()
        let undo = SessionStoreHarness.makeUndoManager()
        try harness.store.start(undo: undo)
        harness.clock.advance(by: 30)
        try harness.store.complete(undo: undo)
        #expect(try harness.store.openSession() == nil)

        undo.undo()

        let record = try #require(try harness.store.openSession())
        #expect(record.phase == .focus)
        #expect(record.endedAt == nil)
    }

    // MARK: - Restoration (F-97)

    @Test("A fresh relaunch restores the stored phase and writes nothing")
    func freshRelaunchChangesNothing() throws {
        let harness = try SessionStoreHarness()
        try harness.store.start()
        harness.clock.advance(by: 5)
        harness.uptime.advance(by: 5)

        let restored = try #require(try harness.store.restore())

        #expect(restored.phase == .focus)
        #expect(restored.notes.isEmpty)
        #expect(try harness.transitionRows().isEmpty)
    }

    @Test("A stale relaunch comes back paused for the relaunch, with resumeTo set")
    func staleRelaunchPauses() throws {
        let harness = try SessionStoreHarness()
        try harness.store.start()
        let startedAt = try #require(try harness.store.openSession()?.startedAt)

        // Twenty minutes since the last phase change, on the same boot: the person was away.
        harness.clock.advance(by: 20 * 60)
        harness.uptime.advance(by: 20 * 60)

        let restored = try #require(try harness.store.restore())

        #expect(restored.notes.contains(.restoredStale))
        #expect(restored.pauseCauses == [.relaunch])
        #expect(restored.resumeTo == .focus)

        let record = try #require(try harness.store.openSession())
        // The one thing that is never rewritten, in the one path most likely to rewrite it.
        #expect(record.startedAt == startedAt)
        #expect(record.phase == .paused)
        #expect(record.pauseCauses == [.relaunch])
        #expect(record.resumeTo == .focus)

        // One row, carrying the cause a single matching resume will clear.
        let rows = try harness.transitionRows()
        #expect(rows.count == 1)
        #expect(rows[0].reasonRaw == "relaunch")
        #expect(rows[0].toRaw == "paused")
    }

    @Test("A restoration pause is cleared by its own cause and by no other")
    func restorationPauseIsClearedByItsOwnCause() throws {
        let harness = try SessionStoreHarness()
        try harness.store.start()
        harness.clock.advance(by: 20 * 60)
        harness.uptime.advance(by: 20 * 60)
        try harness.store.restore()

        #expect(try harness.store.apply(.resumed(cause: .user)).rejection == .notPausedForThatCause)

        harness.clock.advance(by: 1)
        try harness.store.apply(.resumed(cause: .relaunch))
        #expect(try harness.store.openSession()?.phase == .focus)
    }

    @Test("A different boot identity restores as a restart, discards the anchor and raises no anomaly")
    func rebootRestoresAsARestart() throws {
        let directory = URL.temporaryDirectory.appending(
            path: "focus-session-reboot-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "FocusSentinel.store", directoryHint: .notDirectory)

        let startedAt: Date
        do {
            let before = try SessionStoreHarness(bootIdentity: "1786742847.869178", url: url)
            try before.store.start()
            startedAt = try #require(try before.store.openSession()?.startedAt)
        }

        // A different boot: the anchor belongs to a machine-lifetime that is over.
        let after = try SessionStoreHarness(
            clock: MovingDateProvider(now: FixedDateProvider.reference.now.addingTimeInterval(60)),
            uptime: MovingUptimeClock(uptimeSeconds: 12),
            bootIdentity: "1786800000.111111",
            url: url
        )
        let restored = try #require(try after.store.restore())

        #expect(restored.startedAt == startedAt)
        #expect(restored.notes.contains(.rebootedDuringSession))
        // Across boots there is nothing comparable to difference, so no drift is computed and
        // no anomaly is manufactured out of a restart.
        #expect(restored.notes.contains(.clockAnomaly) == false)
        #expect(restored.driftSeconds == nil)
        #expect(restored.pauseCauses == [.systemRestart])

        let record = try #require(try after.store.openSession())
        #expect(record.startedAt == startedAt)
        #expect(record.pauseCauses == [.systemRestart])
        // The anchor now belongs to this launch, so it is never compared against again.
        #expect(record.uptimeAnchorSeconds == 12)
        #expect(record.bootIdentity == "1786800000.111111")
    }

    @Test("A wall-clock jump with the anchor unmoved raises a clock anomaly")
    func clockAnomalyIsRaisedAndCarried() throws {
        let harness = try SessionStoreHarness()
        try harness.store.start()

        // Six seconds of wall clock, no uptime: an NTP correction, not elapsed time. The
        // tolerance is five, sized off the 2.96 s of real drift measured over 8.55 days.
        harness.clock.advance(by: 6)

        let restored = try #require(try harness.store.restore())

        #expect(restored.notes.contains(.clockAnomaly))
        #expect(restored.elapsedWallSeconds == 6)
        // The note rides on the snapshot for as long as it is true, so the cockpit can say
        // "the clock changed while this ran" rather than showing a number it knows is suspect.
        let snapshot = try #require(try harness.store.openSnapshot())
        #expect(snapshot.notes.contains(.clockAnomaly))
    }

    /// The restoration re-stamps the uptime anchor, so it must move `phaseChangedAt` with it.
    /// Otherwise the next relaunch differences the old phase instant against the new anchor and
    /// reads the whole gap before the first restoration as a clock anomaly.
    @Test("A second relaunch after a restoration pause raises no clock anomaly")
    func secondRelaunchAfterARestorationPauseIsClean() throws {
        let harness = try SessionStoreHarness()
        try harness.store.start()
        harness.clock.advance(by: 20 * 60)
        harness.uptime.advance(by: 20 * 60)
        let first = try #require(try harness.store.restore())
        try #require(first.pauseCauses == [.relaunch])

        let record = try #require(try harness.store.openSession())
        #expect(record.phaseChangedAt == harness.clock.now)
        #expect(record.uptimeAnchorSeconds == harness.uptime.uptimeSeconds)

        harness.clock.advance(by: 30)
        harness.uptime.advance(by: 30)
        let second = try #require(try harness.store.restore())

        #expect(second.notes.contains(.clockAnomaly) == false)
        #expect(second.notes.isEmpty)
        #expect(second.pauseCauses == [.relaunch])
        #expect(try harness.transitionRows().count == 1)
    }

    @Test("A two-second jump is inside the tolerance and raises nothing")
    func smallJumpIsNotAnAnomaly() throws {
        let harness = try SessionStoreHarness()
        try harness.store.start()
        harness.clock.advance(by: 2)

        let restored = try #require(try harness.store.restore())
        #expect(restored.notes.isEmpty)
    }

    @Test("A terminal session is not restored, because there is no open session to restore")
    func terminalSessionsAreNotRestored() throws {
        let harness = try SessionStoreHarness()
        try harness.store.start()
        harness.clock.advance(by: 10)
        try harness.store.complete()

        #expect(try harness.store.restore() == nil)
        #expect(harness.store.restorationNotes.isEmpty)
    }

    // MARK: - The snapshot a surface renders

    @Test("The snapshot carries the session without carrying a clock")
    func snapshotIsAValueOverAnInjectedNow() throws {
        let harness = try SessionStoreHarness()
        try harness.store.start(kind: .countdown, plannedSeconds: 1500)
        harness.clock.advance(by: 300)

        let snapshot = try #require(try harness.store.openSnapshot())

        #expect(snapshot.kind == .countdown)
        #expect(snapshot.plannedSeconds == 1500)
        #expect(snapshot.elapsedWallSeconds(now: harness.clock.now) == 300)
        #expect(snapshot.remainingSeconds(now: harness.clock.now) == 1200)
        #expect(snapshot.permitsIntervention)
    }

    @Test("A session paused for a cause the user cannot clear says so")
    func userMayNotResumeSomebodyElsesPause() throws {
        let harness = try SessionStoreHarness()
        try harness.store.start()
        harness.clock.advance(by: 10)
        try harness.store.apply(.paused(cause: .screenLocked))

        let snapshot = try #require(try harness.store.openSnapshot())
        #expect(snapshot.userMayResume == false)
        #expect(snapshot.causesTheUserCannotClear == [.screenLocked])
        #expect(snapshot.permitsIntervention == false)
    }

    @Test("The transition log reads back oldest first")
    func transitionsReadBackInOrder() throws {
        let harness = try SessionStoreHarness()
        try harness.store.start()
        harness.clock.advance(by: 10)
        try harness.store.apply(.detourStarted(reason: .user))
        harness.clock.advance(by: 10)
        try harness.store.apply(.detourEnded)
        harness.clock.advance(by: 10)
        try harness.store.apply(.breakStarted(reason: .user))

        let record = try #require(try harness.store.openSession())
        let rows = harness.store.transitions(of: record)

        // Ending the detour and starting the break is two rows, which is what makes the
        // timeline honest about what happened.
        #expect(rows.map(\.eventRaw) == ["detourStarted", "detourEnded", "breakStarted"])
        #expect(rows.map(\.toRaw) == ["intentionalDetour", "focus", "onBreak"])
    }
}
