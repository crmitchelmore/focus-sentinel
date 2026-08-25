import Foundation
import SwiftData
import Testing

@testable import FocusCore

/// The record of what the app said — and the three properties the caps depend on: a day filter
/// that is a predicate, a day boundary that is the **user's**, and a purge that is complete
/// (R-79, R-83, R-93, F-115, F-116).
@Suite("Intervention log")
struct InterventionLogTests {
    /// 2026-01-01T00:00:00Z. In London that is 1 January; in Auckland it is already 13:00 on
    /// the same date, and twelve hours later the two calendars disagree about the day.
    static let reference = Date(timeIntervalSince1970: 1_767_225_600)
    static let decoy = "com.chrismitchelmore.FocusDecoy"
    static let decoy2 = "com.chrismitchelmore.FocusDecoy2"

    static var london: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    static var auckland: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        return calendar
    }

    @MainActor
    static func makeLog(
        calendar: Calendar = InterventionLogTests.london,
        now: Date = InterventionLogTests.reference
    ) throws -> (log: InterventionLog, container: ModelContainer) {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        return (
            InterventionLog(
                context: container.mainContext,
                dateProvider: FixedDateProvider(now: now),
                calendar: calendar
            ),
            container
        )
    }

    static func delivered(
        _ kind: InterruptionKind,
        subject: String = InterventionLogTests.decoy,
        rung: LadderRung.Kind? = nil,
        surface: NudgeSurface = .panel
    ) -> InterventionEvent {
        InterventionEvent(
            kind: kind,
            rung: rung ?? (kind == .accusation ? .panel : nil),
            subject: subject,
            surface: surface,
            disposition: .delivered
        )
    }

    // MARK: - The day filter is a predicate

    /// **A predicate, never a scan.** A day filter written as `all().filter { … }` would decode
    /// every row in the table on every classification, and this is the largest table the nudge
    /// touches. Asserted on the descriptor rather than with a stopwatch, because a stopwatch
    /// measures the machine and this measures the query.
    @Test("the daily fetch carries a predicate on the stored day key")
    @MainActor
    func theDailyFetchIsAPredicate() {
        let day = LocalDay(year: 2026, month: 1, day: 1)
        let descriptor = InterventionLog.descriptor(forDay: day)
        #expect(descriptor.predicate != nil, "the daily cap's fetch became a scan")
        #expect(descriptor.fetchLimit == nil)
    }

    @Test("the stored day key is written at insert time, in the log's own calendar")
    @MainActor
    func theDayKeyIsWrittenOnInsert() throws {
        let (log, container) = try Self.makeLog()
        defer { withExtendedLifetime(container) {} }

        try log.record(Self.delivered(.accusation))
        let row = try #require(try log.all().first)
        #expect(row.localDayKey == "2026-01-01")
        #expect(row.localDayKey == log.today.key)
    }

    /// A day filter returns that day's rows and no others, whatever else is in the table.
    @Test("a day's rows are exactly that day's rows")
    @MainActor
    func aDaysRowsAreThatDaysRows() throws {
        let (log, container) = try Self.makeLog()
        defer { withExtendedLifetime(container) {} }

        try log.record(Self.delivered(.accusation), at: Self.reference)
        try log.record(Self.delivered(.query, subject: Self.decoy2, surface: .panel), at: Self.reference)
        try log.record(
            Self.delivered(.accusation), at: Self.reference.addingTimeInterval(86_400)
        )
        try log.record(
            Self.delivered(.accusation), at: Self.reference.addingTimeInterval(-86_400)
        )

        #expect(try log.count() == 4)
        #expect(try log.records(on: LocalDay(year: 2026, month: 1, day: 1)).count == 2)
        #expect(try log.records(on: LocalDay(year: 2026, month: 1, day: 2)).count == 1)
        #expect(try log.records(on: LocalDay(year: 2025, month: 12, day: 31)).count == 1)
        #expect(try log.records(on: LocalDay(year: 2026, month: 6, day: 1)).isEmpty)
    }

    // MARK: - The day boundary is the user's

    /// **A day boundary in the user's calendar resets the caps.** The same four interruptions,
    /// read through two calendars, fall on one day in London and across two in Auckland — and
    /// the caps must follow the person, not the machine.
    @Test("a day boundary in the user's own calendar resets the count")
    @MainActor
    func theDayBoundaryIsTheUsers() throws {
        // 2026-01-01T20:00Z: 20:00 in London, and 09:00 on 2 January in Auckland.
        let evening = Self.reference.addingTimeInterval(72_000)

        let (londonLog, londonContainer) = try Self.makeLog(calendar: Self.london)
        defer { withExtendedLifetime(londonContainer) {} }
        try londonLog.record(Self.delivered(.accusation), at: Self.reference)
        try londonLog.record(Self.delivered(.accusation), at: evening)

        #expect(try londonLog.records(on: LocalDay(year: 2026, month: 1, day: 1)).count == 2)
        #expect(try londonLog.records(on: LocalDay(year: 2026, month: 1, day: 2)).isEmpty)

        let (aucklandLog, aucklandContainer) = try Self.makeLog(calendar: Self.auckland)
        defer { withExtendedLifetime(aucklandContainer) {} }
        try aucklandLog.record(Self.delivered(.accusation), at: Self.reference)
        try aucklandLog.record(Self.delivered(.accusation), at: evening)

        #expect(try aucklandLog.records(on: LocalDay(year: 2026, month: 1, day: 1)).count == 1)
        #expect(
            try aucklandLog.records(on: LocalDay(year: 2026, month: 1, day: 2)).count == 1,
            "the day boundary followed the machine rather than the person"
        )
    }

    // MARK: - The budget

    /// **Only a delivery spends.** A deferred rung nobody could see and a suppressed one the
    /// app chose not to make both leave the budget untouched (R-81).
    @Test("the day's budget counts deliveries and nothing else")
    @MainActor
    func onlyDeliveriesSpend() throws {
        let (log, container) = try Self.makeLog()
        defer { withExtendedLifetime(container) {} }
        let priorityID = UUID()

        try log.record(Self.delivered(.accusation), priorityID: priorityID)
        try log.record(Self.delivered(.query, subject: Self.decoy2), priorityID: priorityID)
        try log.record(
            InterventionEvent(
                kind: .accusation, rung: .ambient, subject: Self.decoy,
                disposition: .deferred, deferralReason: .menuBarHidden
            ),
            priorityID: priorityID
        )
        try log.record(
            InterventionEvent(
                kind: .query, subject: Self.decoy2, disposition: .suppressed,
                suppressionReason: .alreadyAsked, queryReason: .noNegativeBasis
            ),
            priorityID: priorityID
        )

        let budget = try log.budget(on: log.today, priorityID: priorityID)
        #expect(budget.interruptionsToday == 2, "a deferral or a suppression spent a cap")
        #expect(budget.accusationsToday == 1)
        #expect(budget.queriesAllPrioritiesToday == 1)
        #expect(budget.queriesForPriorityToday == 1)
        #expect(try log.count() == 4, "a deferral or a suppression was not recorded at all")

        #expect(try log.deliveredCount(kind: .accusation, on: log.today) == 1)
        #expect(try log.deliveredCount(kind: .query, on: log.today) == 1)
    }

    /// The per-priority cap and the all-priorities cap are different counts of the same rows,
    /// and the difference is the whole reason `dailyQueryCapAllPriorities` exists: three
    /// priorities in one day must not license three times as many questions.
    @Test("the per-priority query count is narrower than the day's")
    @MainActor
    func perPriorityAndPerDayCounts() throws {
        let (log, container) = try Self.makeLog()
        defer { withExtendedLifetime(container) {} }

        let first = UUID()
        let second = UUID()
        try log.record(Self.delivered(.query, subject: "a.one"), priorityID: first)
        try log.record(Self.delivered(.query, subject: "a.two"), priorityID: first)
        try log.record(Self.delivered(.query, subject: "b.one"), priorityID: second)

        let forFirst = try log.budget(on: log.today, priorityID: first)
        #expect(forFirst.queriesForPriorityToday == 2)
        #expect(forFirst.queriesAllPrioritiesToday == 3)

        let forSecond = try log.budget(on: log.today, priorityID: second)
        #expect(forSecond.queriesForPriorityToday == 1)
        #expect(forSecond.queriesAllPrioritiesToday == 3)

        // With no priority the per-priority count is zero rather than a guess.
        #expect(try log.budget(on: log.today, priorityID: nil).queriesForPriorityToday == 0)
        #expect(try log.budget(on: log.today, priorityID: nil).queriesAllPrioritiesToday == 3)
    }

    /// The caps survive a relaunch, because they are a function of stored rows.
    @Test("the day's budget is rebuilt from the store after a relaunch")
    @MainActor
    func theBudgetSurvivesARelaunch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "focus-log-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: FocusStore.storeFileName, directoryHint: .notDirectory)
        let priorityID = UUID()

        do {
            let container = try FocusStore.makeContainer(kind: .temporary(url))
            let log = InterventionLog(
                context: container.mainContext,
                dateProvider: FixedDateProvider(now: Self.reference),
                calendar: Self.london
            )
            try log.record(Self.delivered(.query, subject: Self.decoy2), priorityID: priorityID)
            try log.record(Self.delivered(.accusation), priorityID: priorityID)
        }

        let reopened = try FocusStore.makeContainer(kind: .temporary(url))
        let log = InterventionLog(
            context: reopened.mainContext,
            dateProvider: FixedDateProvider(now: Self.reference),
            calendar: Self.london
        )
        let budget = try log.budget(on: log.today, priorityID: priorityID)
        #expect(budget.interruptionsToday == 2, "quitting the app cleared the day's budget")
        #expect(budget.queriesForPriorityToday == 1)
        #expect(budget.accusationsToday == 1)
    }

    // MARK: - Completion

    /// A row gains its outcome once and never again: an interruption has one outcome, and a row
    /// that could be re-outcomed is a row whose counters could drift.
    @Test("an outcome is filled in once and never overwritten")
    @MainActor
    func anOutcomeIsWrittenOnce() throws {
        let (log, container) = try Self.makeLog()
        defer { withExtendedLifetime(container) {} }

        let id = try log.record(Self.delivered(.accusation))
        #expect(try log.all().first?.outcome == nil, "an outcome was invented at insert time")

        try log.complete(id, outcome: .corrected)
        #expect(try log.all().first?.outcome == .corrected)

        try log.complete(id, outcome: .ignored)
        #expect(try log.all().first?.outcome == .corrected, "an outcome was overwritten")

        // Completing a row that does not exist is a no-op, not a crash.
        try log.complete(UUID(), outcome: .dismissed)
        #expect(try log.count() == 1)
    }

    // MARK: - The counters

    @Test("the counters read the columns the schema commits")
    @MainActor
    func countersReadTheStoredColumns() throws {
        let (log, container) = try Self.makeLog()
        defer { withExtendedLifetime(container) {} }

        for rung in LadderRung.Kind.allCases {
            try log.record(
                Self.delivered(
                    .accusation, rung: rung, surface: rung == .ambient ? .menuBar : .panel
                )
            )
        }
        try log.record(Self.delivered(.query, subject: Self.decoy2))
        try log.record(
            InterventionEvent(
                kind: .accusation, rung: .ambient, subject: Self.decoy,
                disposition: .deferred, deferralReason: .presentationActive
            )
        )

        let counters = try log.counters(on: log.today)
        #expect(counters.total == 5)
        #expect(counters.byRung == [.ambient: 2, .panel: 1, .recommitment: 1])
        #expect(counters.bySurface == [.menuBar: 1, .panel: 3])
        #expect(counters.byDisposition == [.delivered: 4, .deferred: 1])
        #expect(counters.delivered(.accusation) == 3)
        #expect(counters.delivered(.query) == 1)
        #expect(counters.deferredRungShare == 0.2)

        // …and the whole log reads the same when there is only one day in it.
        #expect(try log.counters().total == 5)
    }

    /// **Nothing here claims an intervention helped.** The stored row has no field for it and
    /// the counters have no column for it (R-93, D-01).
    @Test("a stored row carries no causal claim")
    @MainActor
    func noCausalClaimIsStored() throws {
        let (log, container) = try Self.makeLog()
        defer { withExtendedLifetime(container) {} }

        let id = try log.record(Self.delivered(.accusation))
        try log.complete(id, outcome: .returned)
        let row = try #require(try log.all().first)

        let columns = Mirror(reflecting: row).children.compactMap(\.label)
        for column in columns {
            for word in ["effectiv", "helped", "success", "streak", "score", "compliance"] {
                #expect(
                    !column.lowercased().contains(word),
                    "\(column) reads as a claim that an intervention worked"
                )
            }
        }
        // What it does carry: what the app did, and what the person did next, as two facts.
        #expect(row.disposition == .delivered)
        #expect(row.outcome == .returned)
    }

    // MARK: - Retention

    /// **The purge is complete**: by priority, by age, and altogether.
    @Test("purging by priority, by age and altogether each removes exactly what it names")
    @MainActor
    func retentionPurgeIsComplete() throws {
        let (log, container) = try Self.makeLog()
        defer { withExtendedLifetime(container) {} }

        let kept = UUID()
        let doomed = UUID()
        try log.record(Self.delivered(.accusation), priorityID: kept, at: Self.reference)
        try log.record(Self.delivered(.query, subject: Self.decoy2), priorityID: doomed, at: Self.reference)
        try log.record(
            Self.delivered(.accusation), priorityID: kept,
            at: Self.reference.addingTimeInterval(-2 * 86_400)
        )
        // A row with no priority at all — a gate-1 suppression — which no per-priority purge
        // may take and no per-priority purge may leave behind for ever.
        try log.record(
            InterventionEvent(
                kind: .query, subject: Self.decoy2, disposition: .suppressed,
                suppressionReason: .noActivePriority
            ),
            at: Self.reference
        )
        #expect(try log.count() == 4)

        #expect(try log.purge(priorityID: doomed) == 1)
        #expect(try log.count() == 3)
        #expect(try log.all().allSatisfy { $0.priorityID != doomed })

        // By age: everything before 2026-01-01 goes, and that day's rows stay.
        #expect(try log.purge(before: LocalDay(year: 2026, month: 1, day: 1)) == 1)
        #expect(try log.count() == 2)
        #expect(try log.records(on: LocalDay(year: 2026, month: 1, day: 1)).count == 2)

        // F-116: everything, including the priority-less row.
        #expect(try log.purgeAll() == 2)
        #expect(try log.count() == 0)
        #expect(try log.all().isEmpty)

        // Purging an empty log is a no-op, not an error.
        #expect(try log.purgeAll() == 0)
        #expect(try log.purge(priorityID: kept) == 0)
    }
}
