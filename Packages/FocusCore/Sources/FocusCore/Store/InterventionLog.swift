import Foundation
import SwiftData

/// **What the app said, when, on which surface, and to what effect** (R-79, R-83, R-93).
///
/// Two jobs, and they are the reason this table exists rather than a column on e04's
/// `ActivityEvent`:
///
/// * **The caps read it.** `dailyQueryCap`, `dailyQueryCapAllPriorities`, `dailyAccusationCap`
///   and the shared `dailyInterruptionCap` are all counts of rows on one **local day**, so the
///   fatigue controller is a pure function of stored rows plus a clock reading, and the caps
///   survive a relaunch. `localDayKey` is written at insert time, so the day filter is a
///   `#Predicate` on an indexed string rather than a scan that decodes every timestamp.
/// * **e09 renders it.** Every interruption with its kind, rung, surface, disposition and
///   outcome — F-104's timeline, F-105's patterns and F-107's counters — **with no causal claim
///   attached** for e09 to have to walk back (R-93, D-01).
///
/// It is deliberately *not* e04's `ActivityEventStore`. That records what the **person and the
/// machine** did; this records what the **app** did. Mixing them would make F-115's retention
/// policy delete the app's own accountability alongside the observations, and would make the
/// daily-cap predicate a scan over the largest table in the store.
///
/// ## Not write-once, and why that is not a contradiction
///
/// `QueryLedger`'s receipts are immutable because an absolute invariant rests on them. A log
/// row is different in kind: it is written when the app speaks and **completed** when the
/// person answers, because "delivered, outcome not yet known" is a true state that lasts as
/// long as a panel is on screen. `complete(_:outcome:)` fills that one field once; nothing else
/// about a row is ever edited.
@MainActor
public final class InterventionLog {
    private let context: ModelContext
    private let dateProvider: any DateProvider
    private let calendar: Calendar

    /// - Parameters:
    ///   - calendar: the user's own calendar. Never `Calendar.current` — a day boundary is a
    ///     fact about where somebody is, and e02's P-69 measured that the same instant is two
    ///     different days in two timezones.
    public init(
        context: ModelContext,
        dateProvider: some DateProvider = SystemDateProvider(),
        calendar: Calendar
    ) {
        self.context = context
        self.dateProvider = dateProvider
        self.calendar = calendar
    }

    // MARK: - Writing

    /// Record one thing the app did.
    ///
    /// - Parameters:
    ///   - event: the typed value. Its `disposition` is what decides whether a cap was spent —
    ///     **only a delivery spends** (R-81).
    ///   - priorityID: the priority it happened under, or `nil` for a suppression at gate 1,
    ///     which is precisely the case where there is none.
    ///   - instant: the wall clock, from the injected `DateProvider` by default.
    /// - Returns: the row's identifier, so the surface can complete it when the person answers.
    @discardableResult
    public func record(
        _ event: InterventionEvent,
        priorityID: UUID? = nil,
        at instant: Date? = nil
    ) throws -> UUID {
        let now = instant ?? dateProvider.now
        let row = FocusSchemaV4.InterventionRecord(
            at: now,
            localDayKey: LocalDay.containing(now, calendar: calendar).key,
            kindRaw: event.kind.rawValue,
            rungRaw: event.rung?.rawValue,
            subject: event.subject,
            subjectKindRaw: RuleSubjectKind.app.rawValue,
            priorityID: priorityID,
            surfaceRaw: event.surface?.rawValue ?? "",
            dispositionRaw: event.disposition.rawValue,
            outcomeRaw: event.outcome?.rawValue,
            originatingAnswerRaw: event.originatingAnswer?.rawValue
        )
        context.insert(row)
        try context.save()
        return row.id
    }

    /// Fill in what the person did. The one field a row ever gains after it is written.
    ///
    /// A second call is refused rather than allowed to overwrite: an interruption has one
    /// outcome, and a row that could be re-outcomed is a row whose counters could drift.
    public func complete(
        _ id: UUID,
        outcome: InterventionOutcome
    ) throws {
        let descriptor = FetchDescriptor<FocusSchemaV4.InterventionRecord>(
            predicate: #Predicate { $0.id == id }
        )
        guard let row = try context.fetch(descriptor).first else { return }
        guard row.outcomeRaw == nil else { return }
        row.outcome = outcome
        try context.save()
    }

    /// **Take back a delivery nobody ever saw** (R-81, U-1, focus-mfc).
    ///
    /// `spendsBudget` is `disposition == .delivered`, and `budget(on:priorityID:)` and
    /// `deliveredCount(kind:on:)` both sum on it. So a nudge the loop has *un-delivered* — a rung
    /// stranded by a display change, a question whose answers went off the edge of a projector —
    /// still spent a unit of the day's interruption budget for as long as the row said
    /// `delivered`. Under U-1 the budget is what decides whether the app may speak again at all:
    /// a nudge nobody saw, charged to it, is the app silencing itself over an interruption that
    /// never happened.
    ///
    /// This is the log's half of `LadderMachine.undeliver(at:)`, and it is called from the same
    /// places: the ladder stops the escalation clock, and this stops the spend.
    ///
    /// The surface is cleared with the disposition, for the reason the column's own
    /// documentation gives — the empty string means "reached no surface", and leaving a surface
    /// named on a withdrawn row would be the record claiming somebody saw something.
    ///
    /// - Returns: whether a delivery was actually taken back. `false` for a row that does not
    ///   exist, for one that was never a delivery, and for one a person has already answered —
    ///   an interruption somebody responded to was seen by definition, and withdrawing it would
    ///   be the app editing history rather than correcting it.
    @discardableResult
    public func withdraw(_ id: UUID) throws -> Bool {
        let descriptor = FetchDescriptor<FocusSchemaV4.InterventionRecord>(
            predicate: #Predicate { $0.id == id }
        )
        guard let row = try context.fetch(descriptor).first else { return false }
        guard row.disposition == .delivered, row.outcomeRaw == nil else { return false }
        row.disposition = .deferred
        row.surface = nil
        try context.save()
        return true
    }

    // MARK: - Reading, by local day

    /// **The daily cap's fetch: a predicate, never a scan.**
    ///
    /// Exposed so `InterventionLogTests` can assert the predicate exists rather than inferring
    /// it from a stopwatch. A day filter written as `all().filter { … }` would decode every row
    /// in the table on every classification, and this is the largest table the nudge touches.
    public static func descriptor(
        forDay day: LocalDay
    ) -> FetchDescriptor<FocusSchemaV4.InterventionRecord> {
        let key = day.key
        return FetchDescriptor<FocusSchemaV4.InterventionRecord>(
            predicate: #Predicate { $0.localDayKey == key }
        )
    }

    /// Every row on one local day, oldest first.
    public func records(on day: LocalDay) throws -> [FocusSchemaV4.InterventionRecord] {
        try context.fetch(Self.descriptor(forDay: day)).sorted(by: Self.chronological)
    }

    /// Every row in the log, oldest first.
    public func all() throws -> [FocusSchemaV4.InterventionRecord] {
        try context.fetch(FetchDescriptor<FocusSchemaV4.InterventionRecord>())
            .sorted(by: Self.chronological)
    }

    public func count() throws -> Int {
        try context.fetchCount(FetchDescriptor<FocusSchemaV4.InterventionRecord>())
    }

    /// The local day an instant falls in, in this log's calendar.
    public func day(of instant: Date) -> LocalDay {
        LocalDay.containing(instant, calendar: calendar)
    }

    /// Today, from the injected clock and the injected calendar. Both, always.
    public var today: LocalDay { day(of: dateProvider.now) }

    // MARK: - The budget

    /// **What the fatigue controller reads**: the day's spend, as a value.
    ///
    /// Only **delivered** rows count. A deferred rung nobody could see and a suppressed one the
    /// app chose not to make both leave the budget untouched (R-81), which is what makes
    /// `nudge.escalationsFromDeferred == 0` a property of the arithmetic rather than of a
    /// separate check.
    ///
    /// - Parameter priorityID: the active priority, for the per-priority query cap. `nil`
    ///   leaves `queriesForPriorityToday` at zero, which is the honest answer when there is no
    ///   priority — and gate 1 will have suppressed the interruption anyway.
    public func budget(on day: LocalDay, priorityID: UUID?) throws -> InterruptionBudget {
        var queriesForPriority = 0
        var queriesAllPriorities = 0
        var accusations = 0
        var interruptions = 0

        for row in try records(on: day) where row.spendsBudget {
            interruptions += 1
            switch row.kind {
            case .query:
                queriesAllPriorities += 1
                if let priorityID, row.priorityID == priorityID { queriesForPriority += 1 }
            case .accusation:
                // **A rung that accuses nobody spends no accusation** (focus-ndh). The
                // interruption above is charged either way — the glyph really did take a moment
                // of the person's attention — and `dailyAccusationCap` is a cap on *sentences*,
                // which the ambient rung is not. Every ambient landing used to spend one, so six
                // silent marks made the panel rung, the only rung that carries a sentence and the
                // whole correction economy, unreachable for the rest of the day.
                if row.spendsTheAccusationCap { accusations += 1 }
            }
        }

        return InterruptionBudget(
            queriesForPriorityToday: queriesForPriority,
            queriesAllPrioritiesToday: queriesAllPriorities,
            accusationsToday: accusations,
            interruptionsToday: interruptions
        )
    }

    /// Deliveries of one kind on one local day.
    public func deliveredCount(kind: InterruptionKind, on day: LocalDay) throws -> Int {
        try records(on: day).count { $0.spendsBudget && $0.kind == kind }
    }

    // MARK: - The counters

    /// The counters for one local day, or for the whole log when `day` is `nil`.
    ///
    /// Built from the columns R-79 commits — kind, rung, surface, disposition, outcome. The
    /// *reason* breakdowns `evaluation.json` reports (`byQueryReason`, `bySuppressionReason`,
    /// `byDeferralReason`) are computed by the evaluation harness from the decider's own
    /// answers, not reconstructed from the store: a reason is why the app decided something,
    /// and the log is a record of what it did.
    public func counters(on day: LocalDay? = nil) throws -> InterventionCounters {
        let rows = try day.map { try records(on: $0) } ?? all()
        var counters = InterventionCounters.empty
        for row in rows { counters.record(Self.event(from: row)) }
        return counters
    }

    /// One stored row, as the value type the counters and e09 read.
    public static func event(from row: FocusSchemaV4.InterventionRecord) -> InterventionEvent {
        InterventionEvent(
            kind: row.kind,
            rung: row.rung,
            subject: row.subject,
            surface: row.surface,
            disposition: row.disposition,
            outcome: row.outcome,
            originatingAnswer: row.originatingAnswer
        )
    }

    // MARK: - Retention (F-115, F-116)

    /// Delete every row for one priority.
    @discardableResult
    public func purge(priorityID: UUID) throws -> Int {
        let doomed = try all().filter { $0.priorityID == priorityID }
        for row in doomed { context.delete(row) }
        if !doomed.isEmpty { try context.save() }
        return doomed.count
    }

    /// Delete every row from before a local day — F-115's retention picker, applied to the
    /// app's own record of itself.
    @discardableResult
    public func purge(before day: LocalDay) throws -> Int {
        let doomed = try all().filter { self.day(of: $0.at) < day }
        for row in doomed { context.delete(row) }
        if !doomed.isEmpty { try context.save() }
        return doomed.count
    }

    /// F-116's delete-everything path.
    @discardableResult
    public func purgeAll() throws -> Int {
        let doomed = try all()
        for row in doomed { context.delete(row) }
        if !doomed.isEmpty { try context.save() }
        return doomed.count
    }

    // MARK: - Helpers

    /// Oldest first, tie-broken by identifier so rows stamped at the same instant read back in
    /// one stable order rather than in whatever order the store felt like.
    private static func chronological(
        _ lhs: FocusSchemaV4.InterventionRecord,
        _ rhs: FocusSchemaV4.InterventionRecord
    ) -> Bool {
        lhs.at == rhs.at ? lhs.id.uuidString < rhs.id.uuidString : lhs.at < rhs.at
    }
}
