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
/// ## The window is a fact about the run, not about the sweep
///
/// This used to take a `RetentionPolicy` in its initialiser, defaulted to the committed ninety
/// days — and the app built one sweep at launch and kept it, so the window a person chose in
/// Settings could never have reached it even once the column existed to hold their choice
/// (F-115, focus-l7n). It reads the window out of the store at the top of every run instead, and
/// `Result` carries the window it used, so *which* promise a sweep kept is a published fact
/// rather than an assumption about how the object was built.
@MainActor
public struct RetentionSweep {
    /// What one sweep did.
    public struct Result: Sendable, Equatable, Hashable {
        /// The local day the sweep ran on. The daily rule compares against this, and the
        /// self-check publishes it.
        public let day: LocalDay
        /// **The window this run actually kept**, read from the store when the run began.
        ///
        /// Published rather than inferred: a sweep that removed nothing because the person asked
        /// for forever and a sweep that removed nothing because there was nothing old are the
        /// same four numbers, and this is what tells them apart.
        public let window: RetentionWindow
        public let activityEvents: Int
        public let interventionRows: Int
        public let queryReceipts: Int

        public init(
            day: LocalDay,
            window: RetentionWindow = .committedDefault,
            activityEvents: Int,
            interventionRows: Int,
            queryReceipts: Int
        ) {
            self.day = day
            self.window = window
            self.activityEvents = activityEvents
            self.interventionRows = interventionRows
            self.queryReceipts = queryReceipts
        }

        /// Everything that went, as one number. Published, and never the only thing published:
        /// a sweep that deleted nothing and a sweep that deleted a table are both a zero and a
        /// number, and the three counts beside it say which.
        public var rowsRemoved: Int { activityEvents + interventionRows + queryReceipts }
    }

    /// The context the window is read from. The four stores below are facades over this same
    /// context; the sweep holds it directly because the window is the one thing it needs that no
    /// store of rows owns.
    private let context: ModelContext
    private let events: ActivityEventStore
    private let log: InterventionLog
    private let ledger: QueryLedger
    private let priorities: PriorityStore
    private let calendar: Calendar
    private let dateProvider: any DateProvider

    public init(
        context: ModelContext,
        events: ActivityEventStore,
        log: InterventionLog,
        ledger: QueryLedger,
        priorities: PriorityStore,
        calendar: Calendar,
        dateProvider: any DateProvider
    ) {
        self.context = context
        self.events = events
        self.log = log
        self.ledger = ledger
        self.priorities = priorities
        self.calendar = calendar
        self.dateProvider = dateProvider
    }

    /// Run the sweep once, against the window the person has stored, as of now.
    ///
    /// Every store is asked even if an earlier one removed nothing: three tables, three
    /// independent windows-worth of rows, and a sweep that stopped at the first empty one would
    /// be a sweep whose behaviour depended on which table filled up first.
    ///
    /// **Forever is a branch and not a very distant date.** A window of `forever` returns a run
    /// that touched nothing, rather than a cutoff so far back that the purges happen to match no
    /// rows: the difference is invisible on a young store and is the whole promise on an old one.
    @discardableResult
    public func run() throws -> Result {
        let now = dateProvider.now
        let policy = FocusStore.retentionPolicy(in: context)
        let today = LocalDay.containing(now, calendar: calendar)
        guard
            let cutoff = policy.cutoff(from: now, calendar: calendar),
            let cutoffDay = policy.cutoffDay(from: now, calendar: calendar)
        else {
            return Result(
                day: today,
                window: policy.window,
                activityEvents: 0,
                interventionRows: 0,
                queryReceipts: 0
            )
        }

        let living = Set(
            try priorities.recentTasks()
                .filter { max($0.lastActivatedAt ?? $0.createdAt, $0.createdAt) >= cutoff }
                .map(\.id)
        )

        return Result(
            day: today,
            window: policy.window,
            activityEvents: try events.purge(before: cutoff),
            interventionRows: try log.purge(before: cutoffDay),
            queryReceipts: try ledger.purge(before: cutoff, livingPriorityIDs: living)
        )
    }
}
