import AppKit
import FocusCore
import FocusUI
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// **THE FLOOR: on a day of sustained drift, the app must reach the panel rung** (focus-d6r).
///
/// ## The half of this epic that had no proof
///
/// An independent ship lens read the whole programme and said it plainly: *"Every proof in this
/// epic answers 'did the app charge for something nobody saw?' and none answers 'on a day of
/// sustained drift, did the app ever speak?' … the programme has a fence on one side of the
/// road."*
///
/// Five rounds built the ceiling. `PerceptibleChange` closed the family — a receipt with a
/// `fileprivate` init, one pinned producer, and a charge that is a consequence of a write — and
/// it holds. Nothing at all held the floor, and the cost was live and measurable:
/// `InterventionLog.budget` summed the day's interruptions over `spendsBudget`, so eight ambient
/// glyph landings spent the whole shared budget, and `remaining(for:)` conjoins that budget into
/// **both** kinds. Measured on the shipping store, one landing at a time:
///
///     landing 7  interruptions=7  accusations=0  permits(.accusation)=true   permits(.query)=FALSE
///     landing 8  interruptions=8  accusations=0  permits(.accusation)=FALSE  permits(.query)=false
///
/// The panel rung — the only rung that carries a sentence, a subject and the whole correction
/// economy — was unreachable for the rest of a day on which the app had accused nobody and asked
/// nobody anything. An app that never speaks is as broken as one that charges for silence, and
/// nothing in the repository would have gone red.
///
/// ## Three rules this suite keeps, each learned from a defect
///
/// 1. **Driven through the shipping loop, not the reducer.** Every object here is
///    `AppComposition`'s own: the real `NudgePanelController` with a real `NSPanel`, the real
///    `MenuBarController` with the real `NSStatusItem` the root installed, the real stores over
///    an in-memory container, and every closure `startNudgeLoop()` makes. Nothing installs a
///    closure of its own — `NudgeHostFixture.wireMenuBarToTheLoop()` wires four of the root's
///    five wires by hand, which is correct for a suite about the loop and wrong for a suite
///    about whether the *shipping arrangement* can speak.
/// 2. **The count comes off the constant that binds, never off a bead's sentence.** The drive is
///    `InterventionPolicy.dailyInterruptionCap` landings.
///    `sixPerceptibleGlyphLandingsSpendNoAccusation` drove exactly six because focus-ndh's bead
///    said six, and stopped one landing short of the failure. That is the pattern that produced
///    this defect and it is not repeated here.
/// 3. **Non-vacuity is asserted in both directions.** A drive in which no landing was ever
///    perceptible would satisfy every implication below by having nothing to imply about.
@Suite("The floor: a day of drift reaches the rung that speaks", .serialized)
@MainActor
struct NudgeFloorTests {
    /// Nine applications an ordinary distracted day drifts into, so a day of
    /// `dailyInterruptionCap` landings never has to reuse one in consecutive rounds.
    static let subjects = [
        "com.chrismitchelmore.FocusDecoy",
        "com.chrismitchelmore.FocusOtherApp",
        "com.example.Reader",
        "com.example.Chat",
        "com.example.Browser",
        "com.example.Mail",
        "com.example.Music",
        "com.example.Notes",
        "com.example.Maps"
    ]

    static let intent = "Write the Q3 proposal for Acme"

    /// The shipping composition root, joined, with a commitment made and the world held still.
    ///
    /// The one substitution is `nudgeHost.surroundings`, which is the sensing boundary — the
    /// single place a test process must not reach through to live `NSWorkspace` state.
    static func joinedRoot(
        clock: FixedMonotonicClock
    ) throws -> (root: AppComposition, priorityID: UUID) {
        let root = AppComposition(
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference),
            monotonicClock: clock,
            calendar: NudgeHostFixture.londonCalendar,
            locale: Locale(identifier: "en_GB"),
            hotKeyRegistrar: InertHotKeyRegistrar(),
            storeKind: .inMemory,
            notificationCentre: SilentNotificationCentre()
        )
        root.joinHosts()
        let priorities = PriorityStore(
            context: root.modelContainer.mainContext,
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference)
        )
        let priorityID = try priorities.setPriority(intent: Self.intent)
        let commitment = ActiveCommitment(id: priorityID, intent: Self.intent)
        root.nudgeHost.surroundings = {
            NudgeHostFixture.surroundings(monotonic: clock.elapsed, commitment: commitment)
        }
        // The workspace is the root's own `SystemReturnWorkspace`, deliberately: this suite
        // asserts on the record and on whether a window appeared, never on the sentence drawn in
        // it, so there is nothing here for a naming double to make true. `SubjectNamingTests`
        // owns that half.
        root.refreshCockpit()
        // The root installed the item; this makes the process one whose item is on screen, so
        // that a write to the glyph is a write somebody could have seen (F-163).
        try MenuBarStage.reveal(root.menuBar)
        return (root, priorityID)
    }

    static func tearDown(_ root: AppComposition) {
        root.nudgeHost.hideOverlays()
        root.nudgePanel.hide()
        root.menuBar.closePopover()
        root.menuBar.remove()
        root.stop()
    }

    /// Everything one glyph landing did, read off the real status item on both sides of it.
    struct Landing {
        let subject: String
        let landedOn: NudgeSurface?
        let deliveredRows: Int
        let glyphWrites: Int
        let markBefore: MenuBarAttention
        let markAfter: MenuBarAttention

        /// The menu bar's channel is a **difference**, never a state: the item is always there,
        /// so what a person perceives is the moment it starts saying something it was not saying.
        var wasPerceived: Bool {
            landedOn == .menuBar && glyphWrites > 0
                && markBefore != .noticing && markAfter == .noticing
        }

        var summary: String {
            "\(subject) landed \(landedOn?.rawValue ?? "nowhere") rows +\(deliveredRows) "
                + "writes \(glyphWrites) mark \(markBefore.rawValue)->\(markAfter.rawValue)"
        }
    }

    static func deliveredRows(_ root: AppComposition) throws -> Int {
        try root.modelContainer.mainContext
            .fetch(FetchDescriptor<FocusSchemaV4.InterventionRecord>())
            .count { $0.disposition == .delivered }
    }

    /// One drift into one application, through the shipping verdict stream, followed by a break
    /// that takes the mark off the item so the next landing has something new to say.
    static func drift(
        _ root: AppComposition,
        clock: FixedMonotonicClock,
        into subject: String,
        thenBreak: Bool = true
    ) throws -> Landing {
        let writesBefore = root.menuBar.glyphWriteCount
        let markBefore = root.menuBar.markOnTheItem
        let rowsBefore = try Self.deliveredRows(root)

        root.relevanceHost.onJudgement?(NudgeHostFixture.unrelatedJudgement(subject: subject))
        NudgeHostFixture.settle()

        let landing = Landing(
            subject: subject,
            landedOn: root.nudgeHost.landedRungSurface,
            deliveredRows: try Self.deliveredRows(root) - rowsBefore,
            glyphWrites: root.menuBar.glyphWriteCount - writesBefore,
            markBefore: markBefore,
            markAfter: root.menuBar.markOnTheItem
        )

        if thenBreak {
            root.nudgeHost.phaseLeftFocus()
            NudgeHostFixture.settle()
            clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }
        return landing
    }

    // MARK: - The floor itself

    /// **A whole shared budget's worth of glyph landings, and the app can still speak.**
    ///
    /// The drive the bead asks for: `dailyInterruptionCap` landings the person really saw, then
    /// the question *did the app ever speak?* asked of the shipping surfaces rather than of a
    /// counter. Before this round the answer after the eighth landing was no, permanently, for
    /// the rest of that local day.
    @Test("after a whole day's shared budget of glyph landings, the panel rung is still reached")
    func aDayOfDriftStillReachesTheRungThatSpeaks() throws {
        let clock = FixedMonotonicClock()
        let (root, priorityID) = try Self.joinedRoot(clock: clock)
        defer { Self.tearDown(root) }

        var landings: [Landing] = []
        for index in 0..<InterventionPolicy.dailyInterruptionCap {
            landings.append(
                try Self.drift(
                    root,
                    clock: clock,
                    into: Self.subjects[index % Self.subjects.count]
                )
            )
        }

        // **Non-vacuity.** Every landing must have reached the glyph and been perceived there,
        // or the day this asserts about is a day on which nothing happened.
        let perceived = landings.count(where: \.wasPerceived)
        #expect(
            perceived == InterventionPolicy.dailyInterruptionCap,
            """
            only \(perceived) of \(landings.count) landings changed the status item, so this \
            drives no cap at all — \(landings.map(\.summary).joined(separator: " | "))
            """
        )
        #expect(
            landings.allSatisfy { $0.deliveredRows == 1 },
            """
            a perceptible glyph landing wrote no delivered row, so the day's budget was never \
            asked to hold anything — \(landings.map(\.summary).joined(separator: " | "))
            """
        )

        // The day, as the caps see it: eight rows, and not one unit of anybody's day spent.
        let log = InterventionLog(
            context: root.modelContainer.mainContext,
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference),
            calendar: NudgeHostFixture.londonCalendar
        )
        let budget = try log.budget(on: log.today, priorityID: priorityID)
        #expect(
            budget.interruptionsToday == 0,
            """
            \(budget.interruptionsToday) of the day's \
            \(InterventionPolicy.dailyInterruptionCap) interruptions were spent on marks that \
            accused nobody and asked nobody anything
            """
        )
        #expect(
            budget.permits(.accusation),
            """
            \(InterventionPolicy.dailyInterruptionCap) glyph landings silenced the panel rung, \
            bound by \(String(describing: budget.bindingLimit(for: .accusation)))
            """
        )
        #expect(
            budget.permits(.query),
            "the question budget was spent by marks nobody was asked anything by"
        )

        // **And the app really does speak.** Sustained drift on one subject, climbed through the
        // shipping loop until the ladder leaves the glyph — the rung that carries a sentence.
        let subject = Self.subjects[0]
        var reachedThePanel = false
        for _ in 0..<10 {
            root.relevanceHost.onJudgement?(NudgeHostFixture.unrelatedJudgement(subject: subject))
            NudgeHostFixture.settle()
            if root.nudgeHost.currentRung == .panel { reachedThePanel = true; break }
            clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }
        #expect(
            reachedThePanel,
            """
            a whole day of sustained drift and the ladder never left the glyph — \
            \(String(describing: root.nudgeHost.lastDecision))
            """
        )
        #expect(
            root.nudgePanel.isVisible,
            "the panel rung was reached and no window ever appeared"
        )
        #expect(
            root.nudgePanel.showing == .accusation,
            "the window that appeared was not the one carrying the accusation"
        )

        // And the sentence it carries was paid for: the panel rung spends a real accusation, so
        // the day's account of itself now says the app spoke.
        let afterSpeaking = try log.budget(on: log.today, priorityID: priorityID)
        #expect(
            afterSpeaking.accusationsToday == 1,
            "the panel rung was raised and the day recorded no accusation for it"
        )
        #expect(afterSpeaking.hasSpokenToday)
    }

    // MARK: - S5 · the fifth wire the composition root makes

    /// **The glyph wire, run** (focus-d6r) — the twin of `CompositionRootWireTests`' S1.
    ///
    /// `startNudgeLoop()` makes **five** wires and `CompositionRootWireTests` drives four. The one
    /// it does not is `menuBar.onGlyphWritten`, which is the wire the whole ambient rung's
    /// accountability hangs from: since focus-1b5 the charge is a *consequence* of the write, and
    /// only the object that makes the assignment knows one happened. Nothing in the repository ran
    /// the shipping closure — `NudgeHostFixture.wireMenuBarToTheLoop()` installs one of its own,
    /// which is precisely the thing that suite's own doctrine forbids: *"never install a closure
    /// of its own"*.
    ///
    /// **The drive has to be the one where the wire is load-bearing**, and finding that out is the
    /// point. On the ordinary path `accuse(…)` asks for the redraw and then calls
    /// `deliverPendingRung()` itself on the next line, so the item has already been written by the
    /// time it looks — a dead `onGlyphWritten` is invisible there, and a test built on that path
    /// would have been another green that means nothing. The wire is the *only* door in exactly
    /// focus-nrl's state: a badge question pending draws the item `waiting`, so a glyph rung
    /// landing underneath it is perceptible to nobody and stays open and unpaid; when the question
    /// is answered the mark falls to the rung's own `noticing`, the item is written, and nothing
    /// but this closure tells the loop.
    ///
    /// With it a no-op, that rung is never charged — the person is shown the app noticing them and
    /// the record says it never said anything, which is the absence
    /// `InterventionDisposition.unopened` exists to make visible (focus-sq7).
    @Test("the glyph wire pays for a rung the item only gets round to drawing later")
    func theGlyphWireChargesTheRungItFinallyDrew() throws {
        let clock = FixedMonotonicClock()
        let (root, priorityID) = try Self.joinedRoot(clock: clock)
        defer { Self.tearDown(root) }

        try #require(try Self.deliveredRows(root) == 0, "the day did not start empty")

        // Reduced interruption: the state macOS Reduce Motion forces (focus-w7v), and the state
        // of everybody on a call. The question goes to the badge and marks the item `waiting`.
        root.nudgeHost.choose(reducedInterruption: true)
        root.relevanceHost.onJudgement?(
            NudgeHostFixture.uncertainJudgement(subject: Self.subjects[1])
        )
        NudgeHostFixture.settle()
        try #require(root.nudgeHost.pendingPopoverQuery != nil, "no question reached the badge")
        try #require(
            root.menuBar.markOnTheItem == .waiting,
            "the badge did not mark the item, so this drives nothing"
        )

        // Sustained drift into a different application: the ambient rung lands on the glyph, and
        // the glyph is still drawing the badge's mark rather than the rung's.
        let landing = try Self.drift(
            root,
            clock: clock,
            into: Self.subjects[0],
            thenBreak: false
        )
        try #require(
            landing.landedOn == .menuBar,
            "the rung did not reach the glyph, so this drives nothing — \(landing.summary)"
        )
        try #require(
            root.menuBar.markOnTheItem == .waiting,
            "the item stopped inviting the click the question is still waiting behind"
        )
        #expect(
            landing.deliveredRows == 0,
            "a rung the menu bar never mentioned was charged — \(landing.summary)"
        )

        // The person opens the popover and answers. The badge's mark goes with the question, the
        // item falls to the rung's own `noticing`, and **that write** is the first moment anybody
        // could perceive the accusation. Nothing here wires `onGlyphWritten`: the root already
        // did, and that closure is what is under test.
        let rowsBefore = try Self.deliveredRows(root)
        try MenuBarStage.open(
            root.menuBar,
            showing: root.menuBarPresentation(),
            install: false
        )
        NudgeHostFixture.settle()
        root.nudgeHost.answer(.notNow)
        NudgeHostFixture.settle()

        try #require(
            root.menuBar.markOnTheItem == .noticing,
            """
            the question is answered and the item is drawing \
            \(root.menuBar.markOnTheItem.rawValue) rather than the rung standing under it
            """
        )
        let rungRows = try root.modelContainer.mainContext
            .fetch(FetchDescriptor<FocusSchemaV4.InterventionRecord>())
            .filter { $0.disposition == .delivered && $0.kind == .accusation }
        #expect(
            rungRows.count == 1,
            """
            the item finally said what the rung needed it to say and \(rungRows.count) rung \
            row(s) were written: the root's onGlyphWritten wire never reached the loop
            """
        )
        #expect(rungRows.first?.surface == .menuBar)
        #expect(rungRows.first?.rung == .ambient)
        #expect(
            try Self.deliveredRows(root) > rowsBefore,
            "nothing at all was recorded after the item was written"
        )
        // The other half of the same wire, and the half this round is about: the rung was written
        // down and cost the person nothing, because it accused nobody.
        let log = InterventionLog(
            context: root.modelContainer.mainContext,
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference),
            calendar: NudgeHostFixture.londonCalendar
        )
        let budget = try log.budget(on: log.today, priorityID: priorityID)
        #expect(budget.accusationsToday == 0, "the glyph, which accuses nobody, spent an accusation")
        #expect(
            budget.interruptionsToday == budget.queriesAllPrioritiesToday,
            "the glyph landing spent a unit of the shared budget"
        )
    }

    // MARK: - The floor's other half: the glyph on a day the app has already spoken

    /// **A day that has spent its six accusations still marks the status item** (focus-2yy).
    ///
    /// focus-d6r's sweep found the same shape one gate further down, inside the same function.
    /// `FatigueController.decide` runs five gates and the first three all exempt the ambient rung
    /// by name — a correction is subject-scoped, a snooze is asked as `rung ?? .panel` precisely
    /// so it never takes the glyph, and the ignored-accusation hold answers `rung != .ambient`
    /// with the comment *"the accusation backoff does not silence the ladder; it holds it at the
    /// ambient rung, which is the one channel the person has not objected to"*. Gate 5, the caps,
    /// exempted nothing. Measured, six accusations spent and fatigue fresh:
    ///
    ///     rung=ambient accuses=false spendsAccusationCap=false
    ///       decision=refused(cap(dailyAccusationCap))
    ///     rung=ambient, shared cap spent instead
    ///       decision=refused(cap(dailyInterruptionCap))
    ///
    /// So a rung that spends neither cap was refused by both, and the consequence reaches the
    /// person: `NudgeDecider` passes `budgetPermits: fatigue.isPermitted` into the suppression
    /// stack for a rung of any kind, so after six panel accusations the status item stopped
    /// saying anything for the rest of the local day. F-146's *"the state is always legible"*,
    /// broken by arithmetic — which is precisely what gates 2 and 3 exist to prevent.
    ///
    /// The rows are written to the store rather than climbed to, deliberately: the budget is a
    /// pure function of stored rows and this drive is about the **decision** the loop makes on a
    /// day that has already happened, not about how that day was reached. The rung this asserts
    /// on is climbed through the shipping loop like every other one here.
    @Test("a day that has spent every accusation still marks the item when the person drifts")
    func theGlyphSurvivesADaySpentToTheCap() throws {
        let clock = FixedMonotonicClock()
        let (root, priorityID) = try Self.joinedRoot(clock: clock)
        defer { Self.tearDown(root) }

        let log = InterventionLog(
            context: root.modelContainer.mainContext,
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference),
            calendar: NudgeHostFixture.londonCalendar
        )
        // Six panel rungs: a heavy but ordinary day, and the whole of `dailyAccusationCap`.
        for index in 0..<InterventionPolicy.dailyAccusationCap {
            try log.record(
                InterventionEvent(
                    kind: .accusation,
                    rung: .panel,
                    subject: Self.subjects[index % Self.subjects.count],
                    surface: .panel,
                    disposition: .delivered
                ),
                priorityID: priorityID
            )
        }
        let spent = try log.budget(on: log.today, priorityID: priorityID)
        try #require(
            !spent.permits(.accusation),
            "the day is not actually spent, so this drives nothing"
        )
        try #require(spent.bindingLimit(for: .accusation) == .dailyAccusationCap)

        // And now the person drifts into something new. The app may not say another sentence —
        // it has said its six — and it must still tell them what it thinks.
        let landing = try Self.drift(
            root,
            clock: clock,
            into: Self.subjects[0],
            thenBreak: false
        )
        #expect(
            landing.landedOn == .menuBar,
            """
            a day of six accusations took the status item with it: the app went quiet about the \
            person's own state — \(String(describing: root.nudgeHost.lastDecision))
            """
        )
        #expect(
            root.menuBar.markOnTheItem == .noticing,
            "the item is drawing \(root.menuBar.markOnTheItem.rawValue) while the person drifts"
        )
        #expect(landing.glyphWrites > 0, "the item was never written — \(landing.summary)")

        // The ladder stops there, which is the half that must NOT change: the rung that carries a
        // sentence is still refused, because it is the rung that spends the cap that is spent.
        #expect(
            root.nudgeHost.currentRung == .ambient,
            "the ladder climbed past the glyph on a day whose accusations are gone"
        )
        #expect(!root.nudgePanel.isVisible, "a seventh accusation reached the screen")
        let after = try log.budget(on: log.today, priorityID: priorityID)
        #expect(
            after.accusationsToday == InterventionPolicy.dailyAccusationCap,
            "the glyph the app was allowed to draw spent a seventh accusation"
        )
        #expect(after.interruptionsToday == InterventionPolicy.dailyAccusationCap)
    }
}
