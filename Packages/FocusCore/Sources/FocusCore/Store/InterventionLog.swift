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

    /// **How many times anything in this process has written an intervention row** (focus-tzj.2).
    ///
    /// Every insert, every outcome, every withdrawal and every purge below bumps it, and nothing
    /// outside this file writes an `InterventionRecord` at all — the lint that keeps
    /// `InterventionEvent` the only way to describe one is what makes that true rather than
    /// hoped for. So a budget computed at one value of this number is still the budget at the
    /// same value.
    ///
    /// Process-wide for `PriorityStore.mutationCount`'s reason: the question is about the rows,
    /// not about the object holding them, and a nudge test routinely writes through one log and
    /// reads through another over the same context.
    public private(set) static var writeCount = 0

    /// The last budget computed, with everything it was computed from.
    ///
    /// `budget(on:priorityID:)` folds **today's whole log** — every row the app has written since
    /// midnight — and the nudge loop asked for it on every five-second tick, whether or not the
    /// app had said anything since the last one. A day in which nothing happens is the common
    /// case and it now costs nothing: the day, the priority and the write count are all the
    /// budget is a function of, so an unchanged triple is an unchanged answer.
    private var cachedBudget: (day: LocalDay, priorityID: UUID?, writes: Int, value: InterruptionBudget)?

    /// How many budget reads this log answered without going to the store. Read by the
    /// self-check's per-tick survey, so "the day is cached" is a number rather than a comment.
    public private(set) var budgetCacheHits = 0

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
            subjectKindRaw: Self.subjectKind(of: event.subject).rawValue,
            priorityID: priorityID,
            surfaceRaw: event.surface?.rawValue ?? "",
            dispositionRaw: event.disposition.rawValue,
            outcomeRaw: event.outcome?.rawValue,
            originatingAnswerRaw: event.originatingAnswer?.rawValue
        )
        context.insert(row)
        try context.save()
        Self.writeCount += 1
        return row.id
    }

    /// **What kind of thing the row is about, read off the subject rather than assumed.**
    ///
    /// This line used to be `RuleSubjectKind.app.rawValue`, a literal, which made
    /// `InterventionRecord.subjectKindRaw` a constant column: every judgement about a site was
    /// stored as a judgement about an application, and nothing downstream could tell the two
    /// apart. History has to, because an origin judgement is not correctable the way an
    /// application judgement is.
    ///
    /// It calls `NudgeSubject.isOrigin(_:)` rather than re-deciding, because that is the
    /// discriminator `CorrectionScope.kind(of:)` and `QuerySubject.kind(of:)` already share — a
    /// second spelling of `contains("://")` is a second answer waiting to disagree with the rule
    /// a correction writes about the same subject.
    ///
    /// An empty subject answers `.app`, and that is the honest reading rather than a fallback: a
    /// mixed accusation and a gate-1 suppression both name nobody, and neither is about a site.
    nonisolated static func subjectKind(of subject: String) -> RuleSubjectKind {
        NudgeSubject.isOrigin(subject) ? .domain : .app
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
        guard let row = try context.countedFetch(descriptor).first else { return }
        guard row.outcomeRaw == nil else { return }
        // **An outcome belongs to a delivery** (focus-gmr, R-81). What the person did about an
        // interruption is only a fact about an interruption that reached them: a deferred row
        // reached nobody and a withdrawn one has just been taken off the day's spend for exactly
        // that reason, so stamping *"they ignored it"* on either would be the falsified row
        // focus-7w3 was about, reached from the other side. It is a guard rather than a caller's
        // responsibility because the two orderings really do both occur — `endOpenQuestion(_:)`
        // completes before the withdrawal and `displaysChanged()` withdraws before it forgets —
        // and a rule that holds by accident of statement order is the shape this epic retires.
        guard row.spendsBudget else { return }
        row.outcome = outcome
        try context.save()
        Self.writeCount += 1
    }

    /// **Take back a delivery nobody ever saw** (R-81, U-1, focus-mfc).
    ///
    /// `spendsBudget` is `disposition == .delivered`; `deliveredCount(kind:on:)` sums on it and
    /// `budget(on:priorityID:)` folds the subset of it that actually said something (focus-d6r).
    /// Either way a delivery is what a day's account is made of, so a nudge the loop has
    /// *un-delivered* — a rung
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
        guard let row = try context.countedFetch(descriptor).first else { return false }
        guard row.disposition == .delivered, row.outcomeRaw == nil else { return false }
        row.disposition = .deferred
        row.surface = nil
        try context.save()
        Self.writeCount += 1
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
        try context.countedFetch(Self.descriptor(forDay: day)).sorted(by: Self.chronological)
    }

    /// Every row in the log, oldest first.
    public func all() throws -> [FocusSchemaV4.InterventionRecord] {
        try context.countedFetch(FetchDescriptor<FocusSchemaV4.InterventionRecord>())
            .sorted(by: Self.chronological)
    }

    public func count() throws -> Int {
        try context.countedFetchCount(FetchDescriptor<FocusSchemaV4.InterventionRecord>())
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
        // **A rung that accuses nobody spends nothing at all** (focus-ndh, focus-d6r).
        //
        // Folded through `InterruptionCharge`, which is the one place *"did this speak to
        // anybody?"* is decided, rather than summed here into four locals. It was four locals,
        // and the pass that filled the interruption one asked `spendsBudget` while the pass that
        // filled the accusation one asked `spendsTheAccusationCap` — so focus-ndh's repair
        // reached the second and left the first, and eight glyph landings went on making
        // `permits(.accusation)` and `permits(.query)` alike answer `false` on a day the app had
        // said nothing. There is now one question and one arithmetic, and `interruptionsToday` is
        // derived from the two per-kind counters rather than summed beside them.
        //
        // `priorityID` is the active priority, for the per-priority query cap. `nil` leaves
        // `queriesForPriorityToday` at zero, which is the honest answer when there is no
        // priority — and gate 1 will have suppressed the interruption anyway.
        //
        // **Asked once per day per priority per write, and not once per tick** (focus-tzj.2).
        // This is a fold over today's whole log — every row since midnight — and the nudge loop
        // asked for it on every five-second corroboration tick. The three things it is a function
        // of are all here: which day, which priority, and whether anything has been written since
        // the last answer. An unchanged triple is the same arithmetic over the same rows, so the
        // store is not asked again.
        let writes = Self.writeCount
        if let cached = cachedBudget,
           cached.day == day,
           cached.priorityID == priorityID,
           cached.writes == writes {
            budgetCacheHits += 1
            return cached.value
        }
        let charges = try records(on: day).compactMap { row in
            InterruptionCharge(row.budgetEvent, priorityID: row.priorityID)
        }
        let budget = InterruptionBudget.spent(charges, underPriority: priorityID)
        cachedBudget = (day: day, priorityID: priorityID, writes: writes, value: budget)
        return budget
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
        if !doomed.isEmpty {
            try context.save()
            Self.writeCount += 1
        }
        return doomed.count
    }

    /// Delete every row from before a local day — F-115's retention picker, applied to the
    /// app's own record of itself.
    @discardableResult
    public func purge(before day: LocalDay) throws -> Int {
        let doomed = try all().filter { self.day(of: $0.at) < day }
        for row in doomed { context.delete(row) }
        if !doomed.isEmpty {
            try context.save()
            Self.writeCount += 1
        }
        return doomed.count
    }

    /// F-116's delete-everything path.
    @discardableResult
    public func purgeAll() throws -> Int {
        let doomed = try all()
        for row in doomed { context.delete(row) }
        if !doomed.isEmpty {
            try context.save()
            Self.writeCount += 1
        }
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
