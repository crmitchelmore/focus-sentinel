import Foundation
import SwiftData
import Testing

@testable import FocusCore

/// **The app forgets, and it forgets the right things** (F-115, focus-tzj.3).
///
/// Three tables grew without bound: `ActivityEventStore` said so in its own doc comment and
/// deferred a policy to a later epic, and `InterventionLog.purge(before:)` and the ledger's
/// purges were written, tested and called by **nothing**. The sweep is the caller.
///
/// Every case here is driven from both sides of the boundary — 89 days and 91 — because a sweep
/// that deleted everything would satisfy any test that only checked the old row was gone, and a
/// sweep that deleted nothing would satisfy any test that only checked the young one stayed.
@Suite("Retention")
@MainActor
struct RetentionSweepTests {
    static let reference = Date(timeIntervalSince1970: 1_767_225_600)   // 2026-01-01T00:00:00Z

    static var londonCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    /// Everything the sweep touches, over one in-memory store.
    @MainActor
    struct Harness {
        let container: ModelContainer
        let context: ModelContext
        let events: ActivityEventStore
        let log: InterventionLog
        let ledger: QueryLedger
        let priorities: PriorityStore
        let now: Date

        init(now: Date = RetentionSweepTests.reference) throws {
            container = try FocusStore.makeContainer(kind: .inMemory)
            context = container.mainContext
            self.now = now
            let clock = FixedDateProvider(now: now)
            events = ActivityEventStore(context: context, dateProvider: clock)
            log = InterventionLog(
                context: context,
                dateProvider: clock,
                calendar: RetentionSweepTests.londonCalendar
            )
            ledger = QueryLedger(context: context, dateProvider: clock)
            priorities = PriorityStore(context: context, dateProvider: clock)
        }

        func daysAgo(_ days: Int) -> Date {
            RetentionSweepTests.londonCalendar.date(byAdding: .day, value: -days, to: now)!
        }

        /// Write the window the person would have chosen. The sweep reads it out of the store,
        /// so this is how a case says which promise it is testing.
        func setWindow(_ window: RetentionWindow) throws {
            try FocusStore.setRetentionWindow(window, in: context, now: now)
        }

        func sweep() throws -> RetentionSweep.Result {
            try RetentionSweep(
                context: context,
                events: events,
                log: log,
                ledger: ledger,
                priorities: priorities,
                calendar: RetentionSweepTests.londonCalendar,
                dateProvider: FixedDateProvider(now: now)
            ).run()
        }
    }

    @Test("the committed window is ninety days")
    func theWindowIsCommitted() {
        #expect(RetentionPolicy.committedDefault.days == 90)
        #expect(RetentionWindow.committedDefault == .ninetyDays)
    }

    /// The bead's own witness: 89 days stays, 91 days goes, in the two tables whose rows die of
    /// age alone.
    @Test("a row at 89 days is kept and one at 91 is not")
    func theWindowCutsWhereItSays() throws {
        let harness = try Harness()

        _ = try harness.events.append(kind: .frontmostApplicationChanged, bundleID: "com.example.Young", at: harness.daysAgo(89))
        _ = try harness.events.append(kind: .frontmostApplicationChanged, bundleID: "com.example.Old", at: harness.daysAgo(91))
        _ = try harness.log.record(
            InterventionEvent(kind: .query, subject: "com.example.Young", disposition: .delivered),
            at: harness.daysAgo(89)
        )
        _ = try harness.log.record(
            InterventionEvent(kind: .query, subject: "com.example.Old", disposition: .delivered),
            at: harness.daysAgo(91)
        )

        let result = try harness.sweep()

        #expect(result.activityEvents == 1)
        #expect(result.interventionRows == 1)
        #expect(try harness.events.all().map(\.bundleID) == ["com.example.Young"])
        #expect(try harness.log.all().map(\.subject) == ["com.example.Young"])
        // Both directions in one reading: something went, and something stayed.
        #expect(result.rowsRemoved == 2)
    }

    /// **A live priority never loses a receipt** (U-1's never-ask-twice, F-115).
    ///
    /// A receipt is what gate 11 reads, so a retention window that deleted one would put a
    /// question the person has already answered back on the ladder. Age is therefore not
    /// sufficient: the priority the receipt was written under has to be old too.
    @Test("an old receipt under a live priority stays; one under an old priority goes")
    func receiptsDieWithTheirPriority() throws {
        let harness = try Harness()

        // A priority the person touched this morning, with a question answered about it three
        // months ago — the shape a long-running commitment really has.
        let live = try harness.priorities.setPriority(intent: "Write the Q3 proposal")
        _ = try harness.ledger.record(
            priorityID: live,
            subjectKind: .app,
            subject: "com.example.Reader",
            reason: .noNegativeBasis,
            outcome: .declined,
            askedAt: harness.daysAgo(91),
            at: harness.daysAgo(91)
        )

        // A priority nobody has touched since before the window, with a receipt of its own.
        let stale = PriorityStore(
            context: harness.context,
            dateProvider: FixedDateProvider(now: harness.daysAgo(120))
        )
        let abandoned = try stale.createTask(intent: "Something from last quarter")
        _ = try harness.ledger.record(
            priorityID: abandoned,
            subjectKind: .app,
            subject: "com.example.Reader",
            reason: .noNegativeBasis,
            outcome: .declined,
            askedAt: harness.daysAgo(91),
            at: harness.daysAgo(91)
        )

        let result = try harness.sweep()

        #expect(result.queryReceipts == 1)
        // The reading that matters, taken through gate 11 itself rather than through the row
        // count beside it: after the sweep, the question the person answered three months ago is
        // still answered, so the ladder will not ask it again.
        #expect(
            try harness.ledger.isSettled(
                priorityID: live, subjectKind: .app, subject: "com.example.Reader"
            ),
            "the sweep took away the answer to a question asked under a live commitment"
        )
        #expect(
            try harness.ledger.isSettled(
                priorityID: abandoned, subjectKind: .app, subject: "com.example.Reader"
            ) == false,
            "the abandoned priority's receipt survived the window"
        )
        #expect(try harness.ledger.receipts(priorityID: live).count == 1)
        #expect(try harness.ledger.receipts(priorityID: abandoned).isEmpty)
    }

    /// A sweep on a store with nothing old in it removes nothing at all — the control that stops
    /// every count above being satisfied by a sweep that deletes whatever it finds.
    @Test("a store with nothing old in it loses nothing")
    func nothingYoungIsEverRemoved() throws {
        let harness = try Harness()
        _ = try harness.events.append(kind: .frontmostApplicationChanged, bundleID: "com.example.Young", at: harness.daysAgo(1))
        _ = try harness.log.record(
            InterventionEvent(kind: .query, subject: "com.example.Young", disposition: .delivered),
            at: harness.daysAgo(1)
        )
        let live = try harness.priorities.setPriority(intent: "Write the Q3 proposal")
        _ = try harness.ledger.record(
            priorityID: live,
            subjectKind: .app,
            subject: "com.example.Reader",
            reason: .noNegativeBasis,
            outcome: .declined
        )

        let result = try harness.sweep()

        #expect(result.rowsRemoved == 0)
        #expect(try harness.events.count() == 1)
        #expect(try harness.log.count() == 1)
        #expect(try harness.ledger.receipts(priorityID: live).count == 1)
    }

    // MARK: - The window the person chose (F-115, focus-l7n)

    /// **The pin.** The sweep used to be built with a `RetentionPolicy` and kept it for the life
    /// of the process, so the window a person set could not have reached it. It reads the window
    /// out of the store at the top of every run now, and this is the reading that says so.
    ///
    /// Both boundaries are outside the committed default on purpose: at 6 and 88 days, a sweep
    /// that had gone back to ninety days would remove **neither** row, so this cannot be
    /// satisfied by any constant.
    @Test("a seven-day window stored by the person is the window the sweep keeps")
    func theStoredWindowIsTheWindowTheSweepKeeps() throws {
        let harness = try Harness()
        try harness.setWindow(.sevenDays)

        _ = try harness.events.append(
            kind: .frontmostApplicationChanged,
            bundleID: "com.example.Young",
            at: harness.daysAgo(6)
        )
        _ = try harness.events.append(
            kind: .frontmostApplicationChanged,
            bundleID: "com.example.Old",
            at: harness.daysAgo(88)
        )

        let result = try harness.sweep()

        #expect(result.window == .sevenDays, "the sweep reported a window nobody stored")
        #expect(result.activityEvents == 1)
        #expect(try harness.events.all().map(\.bundleID) == ["com.example.Young"])
    }

    /// The other direction, and it is the one a longer window has to prove: ninety days stored
    /// keeps a row a seven-day window would have taken.
    @Test("a ninety-day window keeps what a seven-day window would have taken")
    func aLongerWindowKeepsMore() throws {
        let harness = try Harness()
        try harness.setWindow(.ninetyDays)

        _ = try harness.events.append(
            kind: .frontmostApplicationChanged,
            bundleID: "com.example.EightyEight",
            at: harness.daysAgo(88)
        )

        let result = try harness.sweep()

        #expect(result.window == .ninetyDays)
        #expect(result.activityEvents == 0)
        #expect(try harness.events.count() == 1)
    }

    /// **Forever is a branch, not a distant date.** The sweep runs, reports the window it kept,
    /// and removes nothing — including rows a decade old, which no cutoff arithmetic would
    /// spare.
    @Test("forever keeps everything, however old")
    func foreverKeepsEverything() throws {
        let harness = try Harness()
        try harness.setWindow(.forever)

        _ = try harness.events.append(
            kind: .frontmostApplicationChanged,
            bundleID: "com.example.Ancient",
            at: harness.daysAgo(3_650)
        )
        _ = try harness.log.record(
            InterventionEvent(
                kind: .query, subject: "com.example.Ancient", disposition: .delivered
            ),
            at: harness.daysAgo(3_650)
        )
        let abandoned = try harness.priorities.setPriority(intent: "Something from 2016")
        _ = try harness.ledger.record(
            priorityID: abandoned,
            subjectKind: .app,
            subject: "com.example.Ancient",
            reason: .noNegativeBasis,
            outcome: .declined,
            askedAt: harness.daysAgo(3_650),
            at: harness.daysAgo(3_650)
        )

        let result = try harness.sweep()

        #expect(result.window == .forever)
        #expect(result.rowsRemoved == 0)
        #expect(try harness.events.count() == 1)
        #expect(try harness.log.count() == 1)
        #expect(try harness.ledger.receipts(priorityID: abandoned).count == 1)
    }

    /// A store nobody has asked answers ninety days, which is what every build before the
    /// control kept. The upgrade changes nothing for somebody who never opens the pane.
    @Test("an unasked store sweeps at the committed default")
    func anUnaskedStoreKeepsTheCommittedDefault() throws {
        let harness = try Harness()

        #expect(FocusStore.privacyPreferencesRow(in: harness.context) == nil)
        _ = try harness.events.append(
            kind: .frontmostApplicationChanged,
            bundleID: "com.example.Old",
            at: harness.daysAgo(91)
        )

        let result = try harness.sweep()

        #expect(result.window == .ninetyDays)
        #expect(result.activityEvents == 1)
    }

    /// The window survives the round trip, every offered value, through the verb the pane calls.
    @Test("every offered window is written and read back", arguments: RetentionWindow.ordered)
    func everyWindowRoundTrips(window: RetentionWindow) throws {
        let harness = try Harness()
        try harness.setWindow(window)

        let stored = FocusStore.privacyPreferences(in: harness.context)
        #expect(stored.retention == window)
        #expect(stored.storedWindowWasRecognised)
        #expect(FocusStore.retentionPolicy(in: harness.context).window == window)
    }

    /// **A window this build has never heard of falls to the default and says so** — never to a
    /// shorter one, which would delete rows the person had asked to keep.
    @Test("an unreadable stored window reads as ninety days, loudly")
    func anUnreadableWindowIsLoud() throws {
        let harness = try Harness()
        let row = try FocusStore.setRetentionWindow(
            .sevenDays, in: harness.context, now: harness.now
        )
        row.retentionDays = 3
        try harness.context.save()

        let stored = FocusStore.privacyPreferences(in: harness.context)
        #expect(stored.retention == .ninetyDays)
        #expect(stored.storedWindowWasRecognised == false)

        _ = try harness.events.append(
            kind: .frontmostApplicationChanged,
            bundleID: "com.example.Fortnight",
            at: harness.daysAgo(14)
        )
        #expect(try harness.sweep().activityEvents == 0, "an unreadable row shortened the window")
    }

    /// The decoder is total and both halves of the pair are read.
    @Test("the window decoder is total")
    func theDecoderIsTotal() {
        #expect(RetentionWindow.decode(0) == (.forever, true))
        #expect(RetentionWindow.decode(7) == (.sevenDays, true))
        #expect(RetentionWindow.decode(30) == (.thirtyDays, true))
        #expect(RetentionWindow.decode(90) == (.ninetyDays, true))
        #expect(RetentionWindow.decode(-1) == (.ninetyDays, false))
        #expect(RetentionWindow.decode(3_650) == (.ninetyDays, false))
        // Every case is offered, and offered once.
        #expect(Set(RetentionWindow.ordered) == Set(RetentionWindow.allCases))
        #expect(RetentionWindow.ordered.count == RetentionWindow.allCases.count)
        #expect(RetentionWindow.forever.days == nil)
        #expect(
            RetentionPolicy(window: .forever)
                .cutoff(from: Self.reference, calendar: Self.londonCalendar) == nil
        )
    }
}
