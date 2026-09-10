import FocusCore
import Foundation
import Testing

@testable import FocusHost

/// **What one corroboration tick costs the store** (focus-tzj.2).
///
/// ## The defect
///
/// The five-second tick fetched what could not have changed. `PriorityStore.recentTasks(limit:)`
/// read **every** `PriorityTask` in the table and sorted them in Swift to draw a list of eight;
/// `PriorityHost.refresh()` called it on every tick; and `NudgeMemory.reading` folded **today's
/// whole intervention log** and looked for a query receipt *before* gate 1 was consulted, so
/// somebody with no commitment at all paid for both twelve times a minute. None of that is
/// visible in a stopwatch on a store with four rows in it, which is why the reading is a count.
///
/// ## Why it drives the self-check's own survey
///
/// `SelfCheck.tickFetchSurvey()` is what the shipping binary publishes and what
/// `scripts/self-check.sh` pins in both lanes. Asserting on the same function here means the
/// number the gate reads and the number this suite guards cannot drift apart — and it puts the
/// survey itself under test, which matters because a survey that stopped ticking would publish
/// zeros that every pin would happily accept.
@Suite("The tick's fetch budget")
@MainActor
struct TickFetchBudgetTests {
    /// The three states, and what each is allowed to spend on a tick that changes nothing.
    ///
    /// * **no commitment** — nothing at all in the nudge half. Gate 1 closes before either read
    ///   is consulted, and `everyMemoryDecidesTheSameThingWithNoCommitment` proves the skip is
    ///   sound over the whole space.
    /// * **a commitment, popover closed** — the settings row the ritual gate reads and the active
    ///   pointer, plus gate 11's receipt. The history and the day's budget are cached against the
    ///   two write counters, so they cost nothing until something is written.
    /// * **a commitment, popover open** — the same, because building the popover's content
    ///   touches no store.
    @Test("a tick that changes nothing fetches almost nothing, in every state")
    func aQuietTickIsCheap() throws {
        let survey = SelfCheck.tickFetchSurvey()
        try #require(
            survey["available"] as? Bool == true,
            "the survey never ran: \(survey["error"] as? String ?? "no reason given")"
        )

        for state in ["noCommitment", "commitmentPopoverClosed", "commitmentPopoverOpen"] {
            let row = try #require(survey[state] as? [String: Any], "no row for \(state)")
            let steadyTicks = try #require(row["steadyTicks"] as? Int)
            let first = try #require(row["firstTickFetches"] as? Int)
            let steady = try #require(row["fetchesOverSteadyTicks"] as? Int)
            let nudge = try #require(row["nudgeFetchesOverSteadyTicks"] as? Int)
            let popover = try #require(row["popoverFetchesOverSteadyTicks"] as? Int)

            // Non-vacuity, first and per state: a survey that ticked a store which answered
            // nothing would satisfy every ceiling below.
            #expect(steadyTicks >= 2, "\(state) ticked \(steadyTicks) times")
            #expect(first > 0, "\(state)'s first tick fetched nothing, so nothing below is a reading")

            #expect(
                steady <= 2 * steadyTicks,
                "\(state) spent \(steady) fetches over \(steadyTicks) quiet ticks"
            )
            #expect(
                popover == 0,
                "building the popover's content fetched \(popover) times"
            )
            // The nudge half, in every state: gate 11's receipt and the day's budget are both
            // cached against their store's own write count, and a tick writes nothing. With no
            // commitment neither is even asked for.
            #expect(
                nudge == 0,
                "\(state) spent \(nudge) nudge fetches over \(steadyTicks) quiet ticks"
            )
        }
    }

    /// **The two caches are invalidated by a write, not by time** (focus-tzj.2).
    ///
    /// The history is cached against `PriorityStore.mutationCount` and the day's budget against
    /// `InterventionLog.writeCount`, both process-wide. A cache that a write did not invalidate
    /// would be the far worse defect the repair could introduce: a cockpit that draws yesterday's
    /// history, and a fatigue controller that lets the app speak past its daily cap. So both are
    /// driven from the other side — write, then read, and the answer must have moved.
    @Test("a write moves what the caches are keyed on, through any store over the same rows")
    func aWriteInvalidatesTheCaches() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        let dateProvider = FixedDateProvider(now: NudgeHostFixture.reference)
        let store = PriorityStore(context: context, dateProvider: dateProvider)
        let log = InterventionLog(
            context: context,
            dateProvider: dateProvider,
            calendar: NudgeHostFixture.londonCalendar
        )

        let mutationsBefore = PriorityStore.mutationCount
        _ = try store.setPriority(intent: "Write the Q3 proposal")
        #expect(PriorityStore.mutationCount > mutationsBefore)

        // The budget, read twice with nothing in between, then again across a write made through
        // a **second** log over the same rows — which is the case a per-instance counter would
        // get wrong.
        let today = log.today
        let before = try log.budget(on: today, priorityID: nil)
        let hitsBefore = log.budgetCacheHits
        _ = try log.budget(on: today, priorityID: nil)
        #expect(
            log.budgetCacheHits == hitsBefore + 1,
            "the second read of an unchanged day went back to the store"
        )

        let other = InterventionLog(
            context: context,
            dateProvider: dateProvider,
            calendar: NudgeHostFixture.londonCalendar
        )
        _ = try other.record(
            InterventionEvent(
                kind: .query,
                subject: "com.example.Reader",
                surface: .panel,
                disposition: .delivered
            )
        )
        let after = try log.budget(on: today, priorityID: nil)
        #expect(
            after != before,
            "a delivery written through another log left the first one's budget where it was"
        )
    }
}
