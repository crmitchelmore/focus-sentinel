import AppKit
import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **The charging invariant, folded over the space rather than walked down a scenario**
/// (focus-1b5, focus-nrl, focus-ndh, U-1, U-2).
///
/// ## Why this suite exists at all
///
/// Three consecutive rounds fixed the same defect class and three consecutive adversarial lenses
/// found it again, one generalisation further out:
///
/// | round | what was charged while invisible | what the proof drove |
/// |---|---|---|
/// | focus-2xw | a badge accusation | the badge |
/// | focus-mkk | the **first** glyph rung, on one subject | seven rounds on ONE subject |
/// | focus-1b5 | every glyph rung **after** the first | nothing in the repository drove a second subject |
/// | focus-nrl | every glyph rung, from the first, whenever a badge nudge is pending | nothing in the repository drove a rung beside a pending badge |
///
/// Each repair was correct for the case it was handed and blind one step out, and each proof was
/// green because it drove exactly the scenario its bead described.
/// `NudgeHostGlyphRungTests.everyGlyphChargeIsPaidForByAWrite` drives seven rounds on one
/// subject, so the ladder holds a single rung and only **one** of its seven rounds is chargeable
/// at all — the round the previous fix repaired.
///
/// So this suite is not a list of instances. It folds the invariant over the space: distinct
/// subjects in sequence, every combination of what the badge is carrying × each rung × each voice
/// deck × the reduced-interruption flag, with **non-vacuity assertions** so a fold that silently
/// covered nothing fails instead of passing.
///
/// ## What is counted
///
/// Assignments that actually happened to a real `NSStatusBarButton`, the mark that button is
/// actually drawing, `NSWindow.isVisible` conjoined with a hit test of the offered actions, and
/// `NSPopover.isShown` conjoined with what the popover is carrying. **Not one predicate.**
/// `NudgeSurface.reachesThePersonOnLanding` answers `true` for `.menuBar` and cannot fail; reading
/// it back is what produced three of the four beads above.
@Suite("Nothing is charged that nobody was shown", .serialized)
@MainActor
struct NudgeChargingInvariantTests {
    // MARK: - The instrument

    /// Everything one round of the loop did, read off the real surfaces on both sides of it.
    struct Round {
        let index: Int
        let subject: String
        /// Where the rung this host is holding stands, after the round.
        let landedOn: NudgeSurface?
        let chargedAccusations: Int
        let chargedQueries: Int
        /// Assignments to the real `NSStatusBarButton` during the round.
        let glyphWrites: Int
        let announcements: Int
        /// What the button was drawing before and after — not what the presentation asked for.
        let markBefore: MenuBarAttention
        let markAfter: MenuBarAttention
        let panelShowsTheAccusation: Bool
        let panelShowsTheQuestion: Bool
        let popoverShowsTheAccusation: Bool
        let popoverShowsTheQuestion: Bool

        var charged: Int { chargedAccusations + chargedQueries }

        /// **Whether the surface the rung is standing on was observed to change.**
        ///
        /// The menu bar's is a *difference* — the item is always there, so only a change in what
        /// it says is perceptible — and the window's and the popover's are states, because each
        /// is absent or present and each carries the subject's own sentence.
        var theRungWasPerceived: Bool {
            switch landedOn {
            case .menuBar:
                (glyphWrites > 0 || announcements > 0)
                    && markBefore != .noticing
                    && markAfter == .noticing
            case .panel: panelShowsTheAccusation
            case .popoverBadge: popoverShowsTheAccusation
            case .notification, nil: false
            }
        }

        var theQuestionWasPerceived: Bool { panelShowsTheQuestion || popoverShowsTheQuestion }

        var summary: String {
            """
            round \(index + 1) on \(subject): landed \(landedOn?.rawValue ?? "nowhere") \
            charged \(chargedAccusations)a/\(chargedQueries)q \
            writes \(glyphWrites) announcements \(announcements) \
            mark \(markBefore.rawValue)->\(markAfter.rawValue) \
            panel a/q \(panelShowsTheAccusation)/\(panelShowsTheQuestion) \
            popover a/q \(popoverShowsTheAccusation)/\(popoverShowsTheQuestion)
            """
        }
    }

    /// Rows the store marks `delivered`, by kind — the number the day's caps are summed from.
    static func deliveredRows(_ fixture: NudgeHostFixture, kind: InterruptionKind) throws -> Int {
        try fixture.interventions().count {
            $0.dispositionRaw == InterventionDisposition.delivered.rawValue && $0.kind == kind
        }
    }

    /// Hand the loop one judgement and read what the surfaces did about it.
    static func drive(
        _ fixture: NudgeHostFixture,
        _ judgement: NudgeJudgement,
        subject: String,
        index: Int
    ) throws -> Round {
        let writesBefore = fixture.menuBar.glyphWriteCount
        let announcedBefore = fixture.menuBar.announcementCount
        let markBefore = fixture.menuBar.markOnTheItem
        let accusationsBefore = try deliveredRows(fixture, kind: .accusation)
        let queriesBefore = try deliveredRows(fixture, kind: .query)

        fixture.host.consider(judgement)
        NudgeHostFixture.settle()

        return Round(
            index: index,
            subject: subject,
            landedOn: fixture.host.landedRungSurface,
            chargedAccusations: try deliveredRows(fixture, kind: .accusation) - accusationsBefore,
            chargedQueries: try deliveredRows(fixture, kind: .query) - queriesBefore,
            glyphWrites: fixture.menuBar.glyphWriteCount - writesBefore,
            announcements: fixture.menuBar.announcementCount - announcedBefore,
            markBefore: markBefore,
            markAfter: fixture.menuBar.markOnTheItem,
            panelShowsTheAccusation: fixture.panel.isVisible
                && fixture.panel.showing == .accusation,
            panelShowsTheQuestion: fixture.panel.isVisible && fixture.panel.showing == .question,
            popoverShowsTheAccusation: fixture.menuBar.isPopoverShown
                && fixture.menuBar.isShowing(.accusation),
            popoverShowsTheQuestion: fixture.menuBar.isPopoverShown
                && fixture.menuBar.isShowing(.query)
        )
    }

    /// **The invariant itself, asserted on one round.**
    ///
    /// Nothing is charged against the person's day unless something they could perceive actually
    /// changed. Stated as an implication in one direction only, which is why every caller also
    /// asserts non-vacuity: a loop that charged nothing at all would satisfy this everywhere.
    static func assertTheInvariant(_ round: Round, cell: String = "") {
        if round.chargedAccusations > 0 {
            #expect(
                round.theRungWasPerceived,
                "\(cell)a rung was charged and no surface changed — \(round.summary)"
            )
        }
        if round.chargedQueries > 0 {
            #expect(
                round.theQuestionWasPerceived,
                "\(cell)a question was charged and no surface showed it — \(round.summary)"
            )
        }
    }

    /// **The join, asserted at the end of every drive.**
    ///
    /// The receipts the perception path issued against the delivered rows the store actually
    /// holds, computed by two completely different routes. A delivered row with no receipt behind
    /// it is a charge that did not go through the door — which is the mutation this whole round
    /// exists to make impossible, and the reading that would catch a fifth way of writing one.
    static func assertTheJoin(_ fixture: NudgeHostFixture, cell: String = "") throws {
        let rows = try fixture.host.deliveredRowsToday()
        #expect(
            rows == fixture.host.chargesPaidFor.count,
            """
            \(cell)\(rows) delivered row(s) in the store against \
            \(fixture.host.chargesPaidFor.count) receipt(s): a charge was made without a proof
            """
        )
    }

    // MARK: - Distinct subjects, which nothing in the repository drove

    /// Seven applications an ordinary distracted day drifts into, each with a name of its own.
    static let subjects = [
        "com.chrismitchelmore.FocusDecoy",
        "com.chrismitchelmore.FocusOtherApp",
        "com.example.Reader",
        "com.example.Chat",
        "com.example.Browser",
        "com.example.Mail",
        "com.example.Music"
    ]

    static func namedSubjects(_ fixture: NudgeHostFixture) {
        for (index, identifier) in Self.subjects.enumerated() where
            fixture.workspace.runningNames[identifier] == nil {
            // A display name that differs from the key, for focus-ebv's reason: a fixture whose
            // name equals its key cannot tell a drawn sentence from a stored identifier.
            fixture.workspace.runningNames[identifier] = "Decoy \(index)"
        }
    }

    /// **focus-1b5's own drive: seven drifts into seven DIFFERENT applications.**
    ///
    /// Measured before the repair: `charges = [1,1,1,1,1,1,0]`, `glyphWrites = [1,0,0,0,0,0,0]`,
    /// `announcements = [1,0,0,0,0,0,0]`. Six charges, one write, and the whole day's accusation
    /// cap gone. The mark carries no subject, so it cannot distinguish *noticing app A* from
    /// *noticing app B* — which is the point: a second accusation about a different application
    /// was charged at full price while the person was shown a picture identical to the one
    /// already on their screen.
    ///
    /// A single-subject drive cannot reach this, because the ladder holds one rung per subject.
    @Test("seven drifts into seven different applications charge only what the item said")
    func sevenDistinctSubjects() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try fixture.wireMenuBarToTheLoop()
        Self.namedSubjects(fixture)

        var rounds: [Round] = []
        for (index, subject) in Self.subjects.enumerated() {
            rounds.append(
                try Self.drive(
                    fixture,
                    NudgeHostFixture.unrelatedJudgement(subject: subject),
                    subject: subject,
                    index: index
                )
            )
            fixture.clock.advance(by: .seconds(700))
        }

        for round in rounds { Self.assertTheInvariant(round) }
        try Self.assertTheJoin(fixture)

        // **Non-vacuity, both ways.** A drive in which nothing was ever chargeable satisfies the
        // implication above by having nothing to imply about, which is the shape of a green that
        // means nothing — and it is exactly the shape the previous proof had, where six of its
        // seven rounds were untestable.
        #expect(
            rounds.contains { $0.landedOn == .menuBar },
            "no rung ever reached the glyph, so this drive proves nothing"
        )
        #expect(
            rounds.contains { $0.charged > 0 },
            "nothing was charged in the whole drive, so the invariant had nothing to hold"
        )
        #expect(
            rounds.contains { $0.charged == 0 },
            """
            every round charged, so a loop that charges unconditionally would pass this — \
            \(rounds.map(\.summary).joined(separator: " | "))
            """
        )
        // And the number the bead measured: one write, and therefore at most one charge.
        let charged = rounds.filter { $0.charged > 0 }.count
        #expect(
            charged == 1,
            """
            six of these seven landings changed nothing in the menu bar and \(charged) were \
            charged — \(rounds.map(\.summary).joined(separator: " | "))
            """
        )
    }

    /// **focus-1b5's consequence, and focus-ndh's driven proof.**
    ///
    /// The bead's second half: after six invisible charges, *ten further rounds of sustained
    /// drift on one subject never raise the panel rung* — the only rung that carries a sentence,
    /// a subject and the whole correction economy is gone for the day, spent on landings the
    /// person could not perceive.
    ///
    /// focus-ndh's acceptance criteria asks for exactly this shape rather than a predicate: drive
    /// the drifts, read `InterruptionBudget.accusationsToday` on the round after the sixth, and
    /// assert the panel rung is still reachable.
    @Test("a day of glyph landings leaves the panel rung reachable")
    func thePanelRungSurvivesADayOfDrift() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try fixture.wireMenuBarToTheLoop()
        Self.namedSubjects(fixture)

        // A distracted day: seven applications, seven hundred seconds apart.
        for subject in Self.subjects {
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: subject))
            NudgeHostFixture.settle()
            fixture.clock.advance(by: .seconds(700))
        }

        let afterTheDrift = fixture.host.todaysUsage()
        #expect(
            afterTheDrift.accusationsToday < InterventionPolicy.dailyAccusationCap,
            """
            the day's accusation cap was spent by glyph landings: accusationsToday \
            \(afterTheDrift.accusationsToday) of \(InterventionPolicy.dailyAccusationCap)
            """
        )
        #expect(
            afterTheDrift.permits(.accusation),
            "the app may no longer accuse anybody, having shown them a glyph"
        )
        #expect(
            afterTheDrift.permits(.query),
            """
            the query budget was squeezed by glyph landings: \
            \(afterTheDrift.remaining(for: .query)) remaining
            """
        )

        // And the rung that carries a sentence really is still reachable: sustained drift on one
        // subject climbs to the panel.
        let subject = Self.subjects[0]
        var reachedThePanel = false
        for _ in 0..<10 {
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: subject))
            NudgeHostFixture.settle()
            if fixture.host.currentRung == .panel { reachedThePanel = true }
            fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }
        #expect(
            reachedThePanel,
            """
            ten rounds of sustained drift and the ladder never left the glyph — \
            \(String(describing: fixture.host.lastDecision))
            """
        )
        #expect(fixture.panel.isVisible, "the panel rung was reached and no window appeared")
        try Self.assertTheJoin(fixture)
    }

    // MARK: - The grid

    /// What the menu bar's popover is already carrying when the rung lands.
    ///
    /// The dimension nothing in the repository drove, and the one focus-nrl lives in:
    /// `MenuBarPresentation.attention` is the **maximum** of the rung's mark and the badge's, so
    /// anything waiting behind the click holds the item at `waiting` and the glyph rung underneath
    /// it changes nothing at all.
    enum Pending: String, CaseIterable, Sendable {
        case nothing
        case question
        case accusation
    }

    /// Which rung the cell drives to.
    enum TargetRung: String, CaseIterable, Sendable {
        case ambient
        case panel

        /// How many sustained judgements it takes to get there.
        var judgements: Int {
            switch self {
            case .ambient: 1
            case .panel: 2
            }
        }
    }

    /// One cell of the grid: what is waiting, which rung, which deck, which flag.
    struct Cell: CustomStringConvertible, Sendable {
        let pending: Pending
        let rung: TargetRung
        let voice: NudgeVoice
        let reducedInterruption: Bool

        var description: String {
            "\(pending.rawValue)/\(rung.rawValue)/\(voice.rawValue)/reduced=\(reducedInterruption)"
        }
    }

    nonisolated static let grid: [Cell] = Pending.allCases.flatMap { pending in
        TargetRung.allCases.flatMap { rung in
            NudgeVoice.allCases.flatMap { voice in
                [false, true].map { reduced in
                    Cell(
                        pending: pending,
                        rung: rung,
                        voice: voice,
                        reducedInterruption: reduced
                    )
                }
            }
        }
    }

    /// Put the badge into the state this cell asks for, **before** the cell's own deck and flag
    /// are chosen.
    ///
    /// Reduced interruption is turned on to get the nudge onto the badge and then set to whatever
    /// the cell wants, which is a state the shipping app really reaches: a person turns Reduce
    /// Motion off, or hangs up, while something is still waiting behind the click.
    static func establish(_ pending: Pending, in fixture: NudgeHostFixture) throws {
        guard pending != .nothing else { return }
        fixture.host.choose(reducedInterruption: true)
        switch pending {
        case .nothing:
            return
        case .question:
            fixture.host.consider(
                NudgeHostFixture.uncertainJudgement(subject: Self.subjects[1])
            )
            NudgeHostFixture.settle()
            try #require(
                fixture.host.pendingPopoverQuery != nil,
                "the question did not reach the badge, so this cell drives nothing"
            )
        case .accusation:
            for _ in 0..<2 {
                fixture.host.consider(
                    NudgeHostFixture.unrelatedJudgement(subject: Self.subjects[2])
                )
                NudgeHostFixture.settle()
                fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
            }
            try #require(
                fixture.host.pendingPopoverAccusation != nil,
                "the rung did not reach the badge, so this cell drives nothing"
            )
        }
    }

    /// **The whole grid: what the badge is carrying × each rung × each deck × the flag.**
    ///
    /// Sixty cells, each on its own fixture with its own status item in the real menu bar, and
    /// each asserting the same one thing: a charge implies an observed change on the surface the
    /// nudge landed on. The per-cell non-vacuity is `#require`d in `establish(_:in:)` — a cell
    /// that failed to reach the state it names fails loudly rather than proving the invariant
    /// about a state nobody drove — and the whole-grid non-vacuity is at the foot of this
    /// function.
    @Test(
        "every combination of what is waiting, which rung, which deck and the flag",
        arguments: NudgeChargingInvariantTests.grid
    )
    func theGrid(cell: Cell) throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try fixture.wireMenuBarToTheLoop()
        Self.namedSubjects(fixture)

        try Self.establish(cell.pending, in: fixture)

        // The cell's own state, chosen after the badge is loaded.
        fixture.host.choose(voice: cell.voice)
        fixture.host.choose(reducedInterruption: cell.reducedInterruption)

        var rounds: [Round] = []
        for index in 0..<cell.rung.judgements {
            rounds.append(
                try Self.drive(
                    fixture,
                    NudgeHostFixture.unrelatedJudgement(subject: Self.subjects[0]),
                    subject: Self.subjects[0],
                    index: index
                )
            )
            fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }

        for round in rounds { Self.assertTheInvariant(round, cell: "\(cell): ") }
        try Self.assertTheJoin(fixture, cell: "\(cell): ")

        // The cell really drove a rung. Without this a routing change that silenced the loop
        // everywhere would turn the whole grid green.
        #expect(
            rounds.contains { $0.landedOn != nil },
            "\(cell): no rung landed anywhere, so this cell proves nothing"
        )
    }

    /// **The grid's own non-vacuity, which no single cell can state.**
    ///
    /// A fold that covered zero chargeable rounds must fail rather than pass, and "chargeable" is
    /// a property of the *whole* grid: a cell may legitimately charge nothing. This runs the same
    /// sixty cells and asserts that across them the loop both charged and refused to charge, that
    /// every surface a rung can land on was landed on, and that both answers of every dimension
    /// were really exercised.
    @Test("the grid covers both answers, or it proves nothing")
    func theGridIsNotVacuous() throws {
        var charged = 0
        var refused = 0
        var surfacesLandedOn: Set<NudgeSurface> = []
        var pendingCovered: Set<Pending> = []
        var rungsCovered: Set<LadderRung.Kind> = []

        for cell in Self.grid {
            let fixture = try NudgeHostFixture()
            defer { fixture.tearDown() }
            try fixture.wireMenuBarToTheLoop()
            Self.namedSubjects(fixture)
            try Self.establish(cell.pending, in: fixture)
            pendingCovered.insert(cell.pending)
            fixture.host.choose(voice: cell.voice)
            fixture.host.choose(reducedInterruption: cell.reducedInterruption)

            for index in 0..<cell.rung.judgements {
                let round = try Self.drive(
                    fixture,
                    NudgeHostFixture.unrelatedJudgement(subject: Self.subjects[0]),
                    subject: Self.subjects[0],
                    index: index
                )
                Self.assertTheInvariant(round, cell: "\(cell): ")
                if round.chargedAccusations > 0 { charged += 1 } else { refused += 1 }
                if let surface = round.landedOn { surfacesLandedOn.insert(surface) }
                if let rung = fixture.host.currentRung { rungsCovered.insert(rung) }
                fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
            }
            try Self.assertTheJoin(fixture, cell: "\(cell): ")
        }

        #expect(charged > 0, "no cell in the whole grid charged anything, so it proves nothing")
        #expect(
            refused > 0,
            "every cell charged, so a loop that charges unconditionally would pass the grid"
        )
        #expect(pendingCovered == Set(Pending.allCases))
        #expect(
            rungsCovered == Set(LadderRung.Kind.allCases),
            "the grid never reached \(Set(LadderRung.Kind.allCases).subtracting(rungsCovered))"
        )
        // Every surface a rung can actually land on. `.notification` is excluded by U-2 — no rung
        // routes to one — and `NudgeSurfaceTests` holds that separately.
        #expect(
            surfacesLandedOn == [.menuBar, .panel, .popoverBadge],
            "the grid never landed a rung on \(Set(NudgeSurface.allCases).subtracting(surfacesLandedOn))"
        )
    }

    // MARK: - focus-nrl, driven end to end

    /// **A pending badge nudge hides the glyph rung, so the glyph rung is charged nothing — and
    /// is charged the moment the item finally says it.**
    ///
    /// This is the whole of focus-nrl in one drive, including the half the bead says was missing
    /// entirely: the rung landed on `.menuBar`, so the popover shows only the question, and *the
    /// accusation existed in no channel at all*. It is not lost now — it stays open and unpaid,
    /// and the first write that puts the rung's own mark on the item pays for it.
    @Test("a rung under a pending badge question is charged nothing until the mark falls to it")
    func aPendingBadgeDefersTheChargeAndThenPaysIt() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try fixture.wireMenuBarToTheLoop()
        Self.namedSubjects(fixture)

        // Reduced interruption is on: the state macOS Reduce Motion forces (focus-w7v), and the
        // state of everybody on a call and everybody using the silent-and-visual deck.
        fixture.host.choose(reducedInterruption: true)
        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subjects[1]))
        NudgeHostFixture.settle()
        try #require(fixture.host.pendingPopoverQuery != nil, "no question reached the badge")
        try #require(
            fixture.menuBar.markOnTheItem == .waiting,
            "the badge did not mark the item, so this drives nothing"
        )

        // Sustained drift into a different application: the ambient rung lands on the glyph.
        let landing = try Self.drive(
            fixture,
            NudgeHostFixture.unrelatedJudgement(subject: Self.subjects[0]),
            subject: Self.subjects[0],
            index: 0
        )
        try #require(
            fixture.host.landedRungSurface == .menuBar,
            "the rung did not reach the glyph, so this drives nothing"
        )
        #expect(
            fixture.menuBar.markOnTheItem == .waiting,
            "the item stopped inviting the click that the question is still waiting behind"
        )
        #expect(
            landing.chargedAccusations == 0,
            "a rung the menu bar never mentioned was charged — \(landing.summary)"
        )
        Self.assertTheInvariant(landing)

        // The person opens the popover and answers the question. The badge's mark goes with it,
        // the item falls to the rung's own `noticing`, and **that** write is the first moment
        // anybody could perceive the accusation — so it is the moment it is charged.
        //
        // This is the recovery focus-nrl said did not exist: the bead's rung landed on
        // `.menuBar`, so the popover showed only the question and *the accusation existed in no
        // channel at all*, while six of them spent the whole day's accusation cap. It is not lost
        // now; it is unpaid, and it waits.
        let chargesBefore = fixture.host.chargesPaidFor.count
        try MenuBarStage.open(
            fixture.menuBar,
            showing: NudgeHostFixture.menuBarPresentation(of: fixture.host)
        )
        NudgeHostFixture.settle()
        fixture.host.answer(.notNow)
        NudgeHostFixture.settle()

        #expect(
            fixture.menuBar.markOnTheItem == .noticing,
            """
            the question is answered and the item is drawing \
            \(fixture.menuBar.markOnTheItem.rawValue) rather than the rung standing under it
            """
        )
        #expect(
            fixture.host.landedRungSurface == .menuBar,
            "answering a question about one application destroyed an accusation about another"
        )
        // Two receipts, and they are the two things the person was actually shown: the question,
        // charged when the popover opened onto it, and the rung, charged when the item stopped
        // saying `waiting` and started saying `noticing`.
        #expect(
            fixture.host.chargesPaidFor.count == chargesBefore + 2,
            """
            the item finally said what the rung needed it to say and the rung was never \
            charged — receipts \(fixture.host.chargesPaidFor.map(\.channel.rawValue))
            """
        )
        #expect(
            fixture.host.chargesPaidFor.last?.channel == .menuBarItem,
            "the rung was charged on something other than the item that drew it"
        )
        #expect(try Self.deliveredRows(fixture, kind: .accusation) == 1)
        try Self.assertTheJoin(fixture)
    }

    /// **focus-ti4's second consequence: an answer must not order somebody else's window out.**
    ///
    /// With reduced interruption off and a copy deck, a question can be waiting on the badge —
    /// left there when the flag went off, or by the deck changing — while the top rung stands on
    /// a real panel. Answering the badge question used to run `panel.hide()`, so the accusation
    /// panel was ordered out with the rung still open and its corrections still on offer from an
    /// object nobody could see: `orphanedNudgeSurfaces`' own condition, arrived at from the one
    /// direction it did not watch.
    ///
    /// Nothing in the repository drove this, which is the shape of every bead in the sequence.
    @Test("answering a badge question leaves an accusation panel on screen")
    func answeringAQuestionDoesNotTakeThePanelDown() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try fixture.wireMenuBarToTheLoop()
        Self.namedSubjects(fixture)

        // A question onto the badge, with the quiet flag on...
        fixture.host.choose(reducedInterruption: true)
        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subjects[1]))
        NudgeHostFixture.settle()
        try #require(fixture.host.pendingPopoverQuery != nil, "no question reached the badge")

        // ...and then the flag goes off — the person turned Reduce Motion off, or hung up — and
        // sustained drift climbs to a panel rung about a different application.
        fixture.host.choose(reducedInterruption: false)
        for _ in 0..<2 {
            fixture.host.consider(
                NudgeHostFixture.unrelatedJudgement(subject: Self.subjects[0])
            )
            NudgeHostFixture.settle()
            fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }
        try #require(
            fixture.host.landedRungSurface == .panel && fixture.panel.isVisible,
            "the rung did not reach a panel, so this drives nothing"
        )
        try #require(fixture.host.pendingPopoverQuery != nil, "the rung ate the pending question")

        try MenuBarStage.open(
            fixture.menuBar,
            showing: NudgeHostFixture.menuBarPresentation(of: fixture.host)
        )
        NudgeHostFixture.settle()
        fixture.host.answer(.notNow)
        NudgeHostFixture.settle()

        #expect(
            fixture.panel.isVisible,
            "an answer to a question about one application ordered out an accusation about another"
        )
        #expect(fixture.host.landedRungSurface == .panel)
        #expect(
            fixture.host.orphanedNudgeSurfaces.isEmpty,
            """
            a nudge is drawn on a surface the loop has forgotten: \
            \(fixture.host.orphanedNudgeSurfaces.map(\.rawValue))
            """
        )
        try Self.assertTheJoin(fixture)
    }

    /// **And a rung that was never perceived is still in the record** (focus-sq7).
    ///
    /// Not charging is not the same as not happening. A rung the item never mentioned is a thing
    /// the app did, and it gets a row — `unopened`, which spends nothing, because `spendsBudget`
    /// is `disposition == .delivered`. Without this, "stop charging for it" could be satisfied by
    /// making the whole landing invisible to the record, which is the opposite failure.
    @Test("a rung nobody was shown is written down as unopened and spends nothing")
    func anUnperceivedRungIsStillRecorded() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try fixture.wireMenuBarToTheLoop()
        Self.namedSubjects(fixture)

        // Two different applications in a row: the second glyph rung finds the item already
        // saying `noticing`, and the mark carries no subject.
        for subject in Self.subjects.prefix(2) {
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: subject))
            NudgeHostFixture.settle()
            fixture.clock.advance(by: .seconds(700))
        }
        // A third landing, which is what makes the second one be let go of and therefore written.
        fixture.host.consider(
            NudgeHostFixture.unrelatedJudgement(subject: Self.subjects[2])
        )
        NudgeHostFixture.settle()

        let rows = try fixture.interventions()
        let unopened = rows.filter {
            $0.dispositionRaw == InterventionDisposition.unopened.rawValue
        }
        #expect(
            !unopened.isEmpty,
            """
            a rung the person could not perceive vanished from the record entirely: \
            \(rows.map { "\($0.kindRaw)/\($0.dispositionRaw)/\($0.surfaceRaw)" })
            """
        )
        #expect(unopened.allSatisfy { !$0.spendsBudget }, "an unopened row spent a cap")
        #expect(unopened.contains { $0.surface == .menuBar })
        try Self.assertTheJoin(fixture)
    }
}
