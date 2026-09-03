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

        func sweep(policy: RetentionPolicy = .committedDefault) throws -> RetentionSweep.Result {
            try RetentionSweep(
                policy: policy,
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
}
