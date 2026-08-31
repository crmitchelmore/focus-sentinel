import AppKit
import FocusCore
import FocusUI
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// **THE DAY SIDE: on a day shaped like a real one, did the app ever speak?** (focus-f2a, U-1).
///
/// ## The question this suite exists to ask, and the one it replaces
///
/// `NudgeFloorTests` built a floor last round and an independent ship lens graded it precisely:
/// *"the fence was built on the BUDGET side and not on the DAY side. The question asked was 'did
/// the app ever speak?' and the question answered was 'does the budget still permit speaking?' —
/// strictly weaker, and the one that happens to be true."*
/// `InterruptionBudgetTests.theFloorHoldsOverEveryReachableDay` is a genuine breadth-first search
/// over the spending algebra and it holds; it simply answers a different question. So does every
/// other proof in this epic: they fold over *gates*, *rungs*, *surfaces* and *caps*. None of them
/// folds over the shape of a **day**.
///
/// The lens then drove the shipping composition root and measured the gap:
///
/// | day | what the person got |
/// |---|---|
/// | twenty minutes in one distraction | the glyph marks, the panel appears, three actions reachable |
/// | 14–16 drifts into nine applications over 45 minutes | `hasSpokenToday = false`, `accusationsToday = 0`, **no panel ever** |
///
/// The north star worked and the commoner rhythm did not, because `LadderMachine.arrive(_:)` reset
/// the ladder on a change of subject and escalation therefore required two consecutive mandates
/// about the same bundle identifier. focus-f2a is the repair; **this is its proof, and it is
/// deliberately not a walk down the reported scenario.** The reported scenario is one row of the
/// fold below.
///
/// ## What a day is, here
///
/// A `DayShape` is a script of `Beat`s driven through `AppComposition` — the real
/// `NudgePanelController` with a real `NSPanel`, the real `MenuBarController` with the real
/// `NSStatusItem` the root installed, the real stores over an in-memory container, and every
/// closure `startNudgeLoop()` makes. The only substitution is `nudgeHost.surroundings`, which is
/// the sensing boundary a test process must not reach through.
///
/// Every shape ends with the same question — **did the app say something the person could answer,
/// and is it in the day's own account of itself?** — and the answer is read off
/// `InterruptionBudget`, which is rebuilt from stored rows, rather than off any counter this suite
/// keeps.
///
/// ## The completeness check
///
/// `DayShape.allCases` is the space and `script(for:)` is a total function over it: adding a case
/// without a script fails to compile, and `everyShapeIsDriven` fails if the fold ran fewer days
/// than there are cases. The voice decks are folded the same way against `NudgeVoice.allCases`.
///
/// ## The vacuity guard, stated
///
/// This proof would still be green for:
///
/// * **an app that speaks too much.** So every day also asserts the ceiling: no day exceeds
///   `InterventionPolicy.dailyAccusationCap`, and no day delivers two panel rungs back to back
///   without the glyph between them — the repetition focus-f2a's surviving reset exists to forbid.
/// * **an app that speaks about the wrong thing.** So every day asserts that the rung that spoke
///   named the application the person was actually in when it was raised.
/// * **a day that never happened.** A script whose judgements were all refused would satisfy
///   nothing above by having nothing to satisfy, so every day asserts that the loop really
///   considered every beat and that the store really holds delivered rows.
/// * **a day driven on a fixture instead of the product.** It cannot: `joinedRoot` is
///   `AppComposition`, and `NudgeHostFixture.wireMenuBarToTheLoop()` — which installs four of the
///   root's five wires by hand — is deliberately not used here.
///
/// What it is **not** a guard against: the *classification* that produces a mandate. Every beat
/// hands the loop a judgement that has already been decided `unrelated` and sustained, exactly as
/// `NudgeFloorTests` does, because this suite is about what the nudge does with a mandate and e04
/// owns whether there should be one.
@Suite("The day side: a day shaped like a real one, and whether the app spoke", .serialized)
@MainActor
struct NudgeDayShapeTests {
    // MARK: - The world these days happen in

    /// Nine applications an ordinary distracted day drifts into — the lens's own count.
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

    /// One thing that happens in a day.
    enum Beat {
        /// The person is in this application, and the engine has called it unrelated and sustained.
        case drift(String)
        /// Time passes with nothing to report.
        case wait(Duration)
        /// The session leaves `.focus` — a break, a detour, an interruption.
        case takeABreak
        /// The person clicks the status item, which is the only way anything on the badge reaches
        /// anybody at all.
        case openThePopover
    }

    /// The shapes a day can have. **The space this suite folds over.**
    enum DayShape: String, CaseIterable {
        /// The north star, and the one thing that already worked: twenty minutes in one
        /// distraction.
        case oneLongDistraction
        /// **The lens's own day**: drift, return, drift, sixteen times into nine applications.
        case driftReturnDrift
        /// The same, with the person taking breaks — the transitions that reset the ladder outright
        /// and must not therefore make the whole day silent.
        case driftAroundBreaks
        /// Reduce Motion, or a person on a call: every rung that speaks goes to the badge, and the
        /// badge reaches nobody until the popover is opened.
        case reducedInterruption
    }

    /// The script for one shape, and a total function over `DayShape`.
    static func script(for shape: DayShape) -> [Beat] {
        // A drift long enough for the ladder's own dwell, which is the interval every climb needs.
        let dwell = RelevancePolicy.escalationDwell + .seconds(1)
        switch shape {
        case .oneLongDistraction:
            // ~20 minutes in one application, judged as the corroboration tick judges.
            return (0..<4).flatMap { _ in [Beat.drift(Self.subjects[0]), .wait(dwell)] }

        case .driftReturnDrift:
            // Sixteen drifts into nine applications. The returns to the task are the *gaps*: the
            // engine reports nothing between them, which is what a person coming back looks like
            // from here.
            return (0..<16).flatMap { index in
                [Beat.drift(Self.subjects[index % Self.subjects.count]), .wait(dwell)]
            }

        case .driftAroundBreaks:
            // Three stretches of focus with a real break between them. A break de-escalates the
            // ladder outright (R-80) and is *supposed* to, so each stretch has to be able to climb
            // on its own — which is the whole difference between "a break puts the ladder down"
            // and "a day with breaks in it is a silent day".
            return (0..<3).flatMap { stretch -> [Beat] in
                [
                    .drift(Self.subjects[stretch * 2]),
                    .wait(dwell),
                    .drift(Self.subjects[stretch * 2 + 1]),
                    .wait(dwell),
                    .takeABreak,
                    .wait(RelevancePolicy.mandateCooldown + .seconds(1))
                ]
            }

        case .reducedInterruption:
            return (0..<4).flatMap { index -> [Beat] in
                [.drift(Self.subjects[index % Self.subjects.count]), .wait(dwell)]
            } + [.openThePopover]
        }
    }

    // MARK: - Driving a day through the shipping composition root

    /// The shipping composition root, joined, with a commitment made and the world held still.
    static func joinedRoot(
        clock: FixedMonotonicClock,
        reducedInterruption: Bool = false,
        voice: NudgeVoice = .standard
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
        root.nudgeHost.choose(reducedInterruption: reducedInterruption)
        root.nudgeHost.choose(voice: voice)
        root.refreshCockpit()
        // The root installed the item; this makes the process one whose item is on screen, so a
        // write to the glyph is a write somebody could have seen (F-163).
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

    /// Everything one whole day did, read off the real surfaces and the real store.
    struct Day {
        let name: String
        /// One entry per `.drift` beat: the rung the loop was standing on afterwards, and where it
        /// had landed. `nil` means the app said nothing new about that drift.
        let rungs: [LadderRung.Kind?]
        let landings: [NudgeSurface?]
        /// The subject each drift was about, so a sentence can be checked against it.
        let subjects: [String]
        /// The subject the rung the app spoke with was raised about, read off the loop's own
        /// presentation at the moment it spoke.
        let spokenAbout: [String?]
        let considered: Int
        let deliveredRows: Int
        let budget: InterruptionBudget

        var drifts: Int { rungs.count }
        var spoke: Bool { budget.hasSpokenToday }

        var summary: String {
            let steps = zip(subjects, zip(rungs, landings)).map { subject, pair in
                "\(subject.split(separator: ".").last ?? "?")"
                    + ":\(pair.0?.rawValue ?? "-")@\(pair.1?.rawValue ?? "-")"
            }
            return """
                \(name): \(steps.joined(separator: " ")) | considered \(considered) rows \
                \(deliveredRows) accusations \(budget.accusationsToday) interruptions \
                \(budget.interruptionsToday)
                """
        }
    }

    /// Run one script through the shipping loop and read the day back.
    static func run(
        _ name: String,
        _ beats: [Beat],
        root: AppComposition,
        clock: FixedMonotonicClock,
        priorityID: UUID
    ) throws -> Day {
        var rungs: [LadderRung.Kind?] = []
        var landings: [NudgeSurface?] = []
        var subjects: [String] = []
        var spokenAbout: [String?] = []
        var considered = 0

        for beat in beats {
            switch beat {
            case .drift(let subject):
                let rungBefore = root.nudgeHost.currentRung
                root.relevanceHost.onJudgement?(
                    NudgeHostFixture.unrelatedJudgement(subject: subject)
                )
                NudgeHostFixture.settle()
                considered += 1
                let rung = root.nudgeHost.currentRung
                subjects.append(subject)
                // Only a rung the loop actually moved to is this drift's answer. A ladder standing
                // where it already stood said nothing new, and recording it as an arrival is how a
                // day of silence reads like a day of nudges.
                let moved = rung != rungBefore || root.nudgeHost.lastDecision?.rung != nil
                rungs.append(moved ? rung : nil)
                landings.append(moved ? root.nudgeHost.landedRungSurface : nil)
                spokenAbout.append(
                    moved ? root.nudgeHost.lastDecision?.rung?.subject : nil
                )

            case .wait(let interval):
                clock.advance(by: interval)

            case .takeABreak:
                root.nudgeHost.phaseLeftFocus()
                NudgeHostFixture.settle()

            case .openThePopover:
                try MenuBarStage.open(
                    root.menuBar,
                    showing: root.menuBarPresentation(),
                    install: false
                )
                NudgeHostFixture.settle()
            }
        }

        let log = InterventionLog(
            context: root.modelContainer.mainContext,
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference),
            calendar: NudgeHostFixture.londonCalendar
        )
        let rows = try root.modelContainer.mainContext
            .fetch(FetchDescriptor<FocusSchemaV4.InterventionRecord>())
            .count { $0.disposition == .delivered }
        return Day(
            name: name,
            rungs: rungs,
            landings: landings,
            subjects: subjects,
            spokenAbout: spokenAbout,
            considered: considered,
            deliveredRows: rows,
            budget: try log.budget(on: log.today, priorityID: priorityID)
        )
    }

    // MARK: - What every day must be true of

    /// **The floor and the ceiling, asserted on one day.**
    ///
    /// The floor is the whole point of the round and the ceiling is the vacuity guard: a proof
    /// that only asked "did it speak?" would be satisfied by an app that never stops.
    static func assertTheDay(_ day: Day) {
        // — the day really happened —
        #expect(
            day.considered == day.drifts && day.drifts > 0,
            "the loop was never driven, so this day asserts nothing — \(day.summary)"
        )
        #expect(
            day.deliveredRows > 0,
            "a whole day of drift and the store holds no delivered rung — \(day.summary)"
        )

        // — THE FLOOR: the app said something the person could answer —
        #expect(
            day.spoke,
            """
            a whole day of sustained drift and the app never spoke: hasSpokenToday is false and \
            accusationsToday is \(day.budget.accusationsToday) — \(day.summary)
            """
        )
        #expect(
            day.budget.accusationsToday >= 1,
            "the day recorded no accusation at all — \(day.summary)"
        )
        #expect(
            day.rungs.contains(.panel),
            "the ladder never left the glyph on a whole day of drift — \(day.summary)"
        )
        // And it reached a surface with the correction economy on it. A rung that "reached" the
        // menu-bar glyph carries no sentence and nothing to press, which is exactly the state the
        // lens found the app permanently in.
        #expect(
            day.landings.contains(where: { $0 == .panel || $0 == .popoverBadge }),
            "the rung that speaks never landed anywhere it could be answered — \(day.summary)"
        )

        // — THE CEILING, which is the vacuity guard —
        #expect(
            day.budget.accusationsToday <= InterventionPolicy.dailyAccusationCap,
            """
            the day spent \(day.budget.accusationsToday) accusations against a cap of \
            \(InterventionPolicy.dailyAccusationCap) — \(day.summary)
            """
        )
        // Two panel rungs running is a repetition rather than an escalation, and
        // `LadderMachine.arrive(_:)`'s surviving reset is what forbids it. Read off the rungs the
        // ladder actually moved to, so a silent day cannot satisfy it by moving nowhere.
        let climbed = day.rungs.compactMap { $0 }
        #expect(
            !zip(climbed, climbed.dropFirst()).contains { $0 == .panel && $1 == .panel },
            "the app said its sentence twice running — \(day.summary)"
        )
        // — and it spoke about what the person was actually doing —
        for (index, spoken) in day.spokenAbout.enumerated() where spoken != nil {
            #expect(
                spoken == day.subjects[index],
                """
                the app spoke about \(spoken ?? "nothing") while the person was in \
                \(day.subjects[index]) — \(day.summary)
                """
            )
        }
    }

    // MARK: - The fold

    @Test("every shape of day reaches the rung that speaks")
    func everyShapeIsDriven() throws {
        var driven: [DayShape: Day] = [:]

        for shape in DayShape.allCases {
            let clock = FixedMonotonicClock()
            let (root, priorityID) = try Self.joinedRoot(
                clock: clock,
                reducedInterruption: shape == .reducedInterruption
            )
            defer { Self.tearDown(root) }

            let day = try Self.run(
                shape.rawValue,
                Self.script(for: shape),
                root: root,
                clock: clock,
                priorityID: priorityID
            )
            driven[shape] = day
            Self.assertTheDay(day)
        }

        // **The completeness check.** Self-referential: a case added to `DayShape` with no row in
        // the fold fails here rather than being silently uncovered, and a fold that ran nothing at
        // all fails on the same line.
        #expect(
            Set(driven.keys) == Set(DayShape.allCases),
            """
            \(Set(DayShape.allCases).subtracting(driven.keys).map(\.rawValue)) were never driven, \
            so the space this suite claims to fold over is larger than the fold
            """
        )
        #expect(!DayShape.allCases.isEmpty, "the space is empty, so the fold proves nothing")
    }

    /// **A day under each voice deck.**
    ///
    /// Folded separately because the deck is orthogonal to the shape: `NudgeVoice.silentVisual` is
    /// a *routing* deck, so under it the rung that speaks goes to the badge exactly as it does
    /// under Reduce Motion, and the four copy decks leave the routing alone. A day that could not
    /// speak under one of them would be a day whose silence depended on a setting.
    @Test("a day of drift reaches the rung that speaks under every voice deck")
    func everyVoiceDeckSpeaks() throws {
        var driven: Set<NudgeVoice> = []

        for voice in NudgeVoice.allCases {
            let clock = FixedMonotonicClock()
            let (root, priorityID) = try Self.joinedRoot(clock: clock, voice: voice)
            defer { Self.tearDown(root) }

            // The routing decks put the rung behind a click, so the day has to contain the click.
            var beats = Self.script(for: .driftReturnDrift)
            if voice.isRoutingDeck { beats.append(.openThePopover) }

            let day = try Self.run(
                "voice \(voice.rawValue)",
                beats,
                root: root,
                clock: clock,
                priorityID: priorityID
            )
            driven.insert(voice)
            Self.assertTheDay(day)
        }

        #expect(
            driven == Set(NudgeVoice.allCases),
            """
            \(Set(NudgeVoice.allCases).subtracting(driven).map(\.rawValue)) were never driven, so \
            a deck could be added and left unproven
            """
        )
    }

    /// **The lens's own day, read the way the lens read it.**
    ///
    /// Kept beside the fold rather than folded into it, because the numbers are the measurement
    /// that produced the ruling and a fold that generalised them away would lose the one row a
    /// reader can check against the bead. Sixteen drifts, nine applications, and the two readings
    /// that were false: `hasSpokenToday` and `accusationsToday`.
    @Test("the lens's own day — sixteen drifts into nine applications — is no longer silent")
    func theLensesOwnDaySpeaks() throws {
        let clock = FixedMonotonicClock()
        let (root, priorityID) = try Self.joinedRoot(clock: clock)
        defer { Self.tearDown(root) }

        let day = try Self.run(
            "the lens's day",
            Self.script(for: .driftReturnDrift),
            root: root,
            clock: clock,
            priorityID: priorityID
        )

        try #require(day.drifts == 16, "the lens drove sixteen drifts and this drove \(day.drifts)")
        try #require(
            Set(day.subjects).count == Self.subjects.count,
            "the lens drove nine applications and this drove \(Set(day.subjects).count)"
        )
        #expect(day.budget.hasSpokenToday, "hasSpokenToday is still false — \(day.summary)")
        #expect(
            day.budget.accusationsToday > 0,
            "accusationsToday is still zero — \(day.summary)"
        )
        // **How many of the sixteen showed the person nothing at all.** The lens counted twelve,
        // over a day that also carried phase transitions and the fatigue gate another round
        // repaired; this drive is the ladder's own share of that number and does not claim to
        // reproduce it. What it asserts is the property the twelve violated: most of a day's
        // drifts get an answer, and a drift the ladder answered with the glyph counts as one.
        let shownNothing = day.rungs.count(where: { $0 == nil })
        #expect(
            shownNothing < day.drifts / 2,
            """
            \(shownNothing) of \(day.drifts) drifts showed the person nothing at all — \
            \(day.summary)
            """
        )
    }
}
