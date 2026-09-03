import Foundation
import SwiftData

/// **The one thing that ever shortens this app's memory** (F-115, focus-tzj.3).
///
/// ## What it is for
///
/// Three tables grew for ever. `InterventionLog.purge(before:)` and the ledger's purges existed
/// and had **zero callers** in the whole programme; the activity store had no purge at all and a
/// doc comment deferring one to a later epic. This is the caller, and the missing purge, and the
/// day-boundary rule that makes them run more than once.
///
/// ## What it deletes, and the one table it treats differently
///
/// * **Activity events** — what the person and the machine did. Older than the window, gone.
/// * **Intervention rows** — what the app said. Older than the window, gone. The day's caps read
///   *today's* rows, so nothing the fatigue controller consults is ever inside the window's
///   reach.
/// * **Query receipts** — the never-ask-twice memory, and the exception. A receipt is what gate
///   11 reads, so deleting one puts a question the person already answered back on the ladder.
///   A receipt therefore goes only when it is old **and** the priority it was written under is
///   old: a commitment somebody is still working on keeps every promise ever made about it,
///   however long ago the question was asked.
///
/// A priority counts as living if it was created or last activated inside the window. That is
/// deliberately generous — the failure it prevents is asking somebody twice, and the cost of
/// being wrong the other way is a handful of rows.
///
/// ## No user interface, on purpose
///
/// e07 §5 owns the picker, the delete-everything button and the sentence in Settings that says
/// what the window is. Inventing any of that here would be inventing a user-visible privacy
/// promise outside its epic. What is committed now is the mechanism and the default, because a
/// row that was never written is a row no later feature has to explain.
@MainActor
public struct RetentionSweep {
    /// What one sweep did.
    public struct Result: Sendable, Equatable, Hashable {
        /// The local day the sweep ran on. The daily rule compares against this, and the
        /// self-check publishes it.
        public let day: LocalDay
        public let activityEvents: Int
        public let interventionRows: Int
        public let queryReceipts: Int

        public init(day: LocalDay, activityEvents: Int, interventionRows: Int, queryReceipts: Int) {
            self.day = day
            self.activityEvents = activityEvents
            self.interventionRows = interventionRows
            self.queryReceipts = queryReceipts
        }

        /// Everything that went, as one number. Published, and never the only thing published:
        /// a sweep that deleted nothing and a sweep that deleted a table are both a zero and a
        /// number, and the three counts beside it say which.
        public var rowsRemoved: Int { activityEvents + interventionRows + queryReceipts }
    }

    private let policy: RetentionPolicy
    private let events: ActivityEventStore
    private let log: InterventionLog
    private let ledger: QueryLedger
    private let priorities: PriorityStore
    private let calendar: Calendar
    private let dateProvider: any DateProvider

    public init(
        policy: RetentionPolicy = .committedDefault,
        events: ActivityEventStore,
        log: InterventionLog,
        ledger: QueryLedger,
        priorities: PriorityStore,
        calendar: Calendar,
        dateProvider: any DateProvider
    ) {
        self.policy = policy
        self.events = events
        self.log = log
        self.ledger = ledger
        self.priorities = priorities
        self.calendar = calendar
        self.dateProvider = dateProvider
    }

    /// Run the sweep once, against the window as of now.
    ///
    /// Every store is asked even if an earlier one removed nothing: three tables, three
    /// independent windows-worth of rows, and a sweep that stopped at the first empty one would
    /// be a sweep whose behaviour depended on which table filled up first.
    @discardableResult
    public func run() throws -> Result {
        let now = dateProvider.now
        let cutoff = policy.cutoff(from: now, calendar: calendar)
        let cutoffDay = LocalDay.containing(cutoff, calendar: calendar)

        let living = Set(
            try priorities.recentTasks()
                .filter { max($0.lastActivatedAt ?? $0.createdAt, $0.createdAt) >= cutoff }
                .map(\.id)
        )

        return Result(
            day: LocalDay.containing(now, calendar: calendar),
            activityEvents: try events.purge(before: cutoff),
            interventionRows: try log.purge(before: cutoffDay),
            queryReceipts: try ledger.purge(before: cutoff, livingPriorityIDs: living)
        )
    }
}
