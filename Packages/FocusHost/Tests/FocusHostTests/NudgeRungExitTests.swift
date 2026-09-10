import AppKit
import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **Every way a delivered rung can end, driven one row per case through the shipping loop with
/// the rung on the PANEL** (focus-s4m, focus-fwy).
///
/// ## The closed set nobody folded, and the two defects it was hiding
///
/// A question's ending has been an enumerated `CaseIterable` vocabulary since focus-v0u —
/// `QuestionExit`, five cases, one door, `NudgeHostQuestionExitTests` walking `allCases`. A rung's
/// ending was six hand-written doors, and the three things an ending has to settle were
/// distributed across them by memory. Two of the six told the ladder nothing at all:
///
///     ⌃⌘H → panel.hide(); endOpenQuestion(.screenReclaimed); forgetOpenRung()
///
/// `forgetOpenRung()` → `setOpenRung(nil)` touches no ladder state, so the ladder stayed
/// `.engaged(rung: .panel, deliveredAt:)`. `LadderMachine.arrive(_:)` returns to `.idle` only when
/// the standing rung is the top **and** the subject differs; on the same subject
/// `candidate(at:budgetPermits:)` answers `rung.escalated(for:)`, which is `nil` at the top, and
/// `NudgeDecider.accuse(…)` turns a `nil` candidate into `.silent(.budgetExhausted)`. **One press
/// of Hide overlays silenced the only rung that says anything for the rest of the run.**
/// `withdrawForPresentation()` had the same hole under a doc comment promising the opposite.
///
/// ## Why every row puts the rung on the panel and not on the glyph
///
/// Because the glyph has no delivery to take back. `LadderRung.Kind.ambient` is not the top, so
/// `candidate(…)` still answers `.panel` from `.engaged(.ambient, …)` however badly an exit
/// mishandles it — a suite driven on the glyph would have been green through the whole of the
/// defect above, for the wrong reason. Every row here climbs the shipping ladder to the panel rung
/// first, and the assertion that matters is the last one: **once this exit has run, can the app
/// speak again at all?**
///
/// ## The vacuity guard
///
/// This suite would still be green if:
///
/// * **every exit answered `takesBackTheDelivery` the same way**, provided every row's literal
///   were edited to match. `theRuleIsNeverAConstantFunction` is the guard: each of the three
///   properties must be answered both ways by the table, and the row that takes a delivery back
///   must be `displayStranded`, which is the one exit that had its take-back before this round.
/// * **the table agreed with the implementation because it asked it.** It does not: every
///   expectation below is a **literal**, and `theVocabularyMatchesTheTable` compares the literal
///   with `RungExit`'s own answer. A table that read `exit.takesBackTheDelivery` back would agree
///   with any implementation, which is the *"proof written to the known failure"* shape the
///   charter counts at 31% of this backlog.
/// * **a seventh exit were added and given no row.** `theTableCoversEveryExit` walks
///   `RungExit.allCases`, and `everyExitIsOneTheLoopCanProduce` requires each row's drive to
///   really reach the door — so a case can be neither declared-and-undriven nor driven-by-a-drive
///   that produces some other exit.
/// * **the loop never spoke again after any exit, if the last assertion were dropped.** It is not
///   dropped: clause 5 of `everyExitSettlesEverythingAnEndingHasToSettle` restores whatever the
///   row injected into the world and then drifts again until a rung lands. It is the assertion
///   that fails on the shipping code as it stood, and it reports *"the loop never raised another
///   rung"*.
/// * **the person's own answer stopped being counted.** `.answered` is the one exit whose
///   consequences belong to `resolve(_:snoozeDuration:)` rather than to `RungExit`, and its row's
///   literals are what stop the door double-counting: `ignoredRunAfter: 1` is the run the
///   *dismissal* advanced, and a door that advanced it again would read 2.
/// * **the backoff advanced for every ending rather than for the ones the person caused.**
///   `ignoredRunAfter` is a count and four of the six rows expect `0`, so a door that told
///   `FatigueController` about a session ending or a withdrawn delivery fails here. The two that
///   expect `1` are the endings the person authored: ⌃⌘H, and a panel they drifted straight past
///   (focus-fzf). Driving the second of those under the ladder's old arithmetic put the app back
///   under focus-f2a's floor, and `NudgeDayShapeTests` is where that measurement is re-taken.
@Suite("Every exit from a delivered rung, with the rung on the panel", .serialized)
@MainActor
struct NudgeRungExitTests {
    static let drifted = "com.example.Browser"
    static let thenDrifted = "com.example.Reader"

    /// What each exit must leave behind, stated as literals.
    struct Row: Sendable {
        let exit: RungExit
        /// `RungExit.takesBackTheDelivery`, written out rather than read back.
        let takesBackTheDelivery: Bool
        /// `RungExit.leavesTheInterruptionUnanswered`, written out.
        let leavesTheInterruptionUnanswered: Bool
        /// `RungExit.countsAsAnIgnoredAccusation`, written out.
        let countsAsAnIgnoredAccusation: Bool
        /// Where the ladder is standing once the exit has run — the reading the defect was in.
        let ladderAfter: LadderRung.Kind?
        /// Whether this host is holding a rung on a surface afterwards. Only a replacement is.
        let holdsARungAfter: Bool
        /// `FatigueController`'s session-wide run of ignored accusations afterwards. A count, not
        /// a flag, because the failure this catches is **double** counting as well as none.
        let ignoredRunAfter: Int
        /// Why that is the right answer. Read by a person; the assertions check the rest.
        let argument: String
    }

    /// **One row per `RungExit`.** A case missing here fails `theTableCoversEveryExit`.
    nonisolated static let rows: [Row] = [
        Row(
            exit: .answered,
            takesBackTheDelivery: false,
            leavesTheInterruptionUnanswered: false,
            countsAsAnIgnoredAccusation: false,
            ladderAfter: nil,
            holdsARungAfter: false,
            ignoredRunAfter: 1,
            argument: """
                The only exit whose consequences are not the vocabulary's. \
                `resolve(_:snoozeDuration:)` has already completed the row with the outcome that \
                names the correction, told `FatigueController` that outcome, and reduced \
                `.rungIgnored` for the one action that is not an answer. All three literals are \
                false so that the door adds nothing on top: the run below is the one the \
                dismissal advanced, and a door that advanced it again would read 2.
                """
        ),
        Row(
            exit: .replaced,
            takesBackTheDelivery: false,
            leavesTheInterruptionUnanswered: true,
            countsAsAnIgnoredAccusation: true,
            ladderAfter: .ambient,
            holdsARungAfter: true,
            ignoredRunAfter: 1,
            argument: """
                The person drifted into a second application, the ladder's top rung reset, and the \
                ambient glyph for the second replaced the panel for the first. The row is \
                completed `ignored`, because an `InterventionRecord` that never says how an \
                interruption turned out is focus-gmr's defect — and **both backoffs are told**, \
                which is focus-fwy's other half and focus-fzf: somebody who never touches a nudge \
                advances neither run, and drifting past a panel is the commonest way not to touch \
                one. The `1` below read `0` for one round, and the reason was a measurement rather \
                than a ruling: two replaced panels trip `ignoredAccusationBackoff`, the ladder was \
                left at `.engaged(.ambient, …)` with only an escalation to offer, \
                `candidate(at:budgetPermits:)` answered `nil`, and the glyph went silent with the \
                panel. focus-628 and focus-50m repaired that — the ladder's silences declare a \
                subject, the hold expires and retains the mark — so the ending ships and \
                `NudgeDayShapeTests` re-takes the measurement.
                """
        ),
        Row(
            exit: .screenReclaimed,
            takesBackTheDelivery: false,
            leavesTheInterruptionUnanswered: true,
            countsAsAnIgnoredAccusation: true,
            ladderAfter: nil,
            holdsARungAfter: false,
            ignoredRunAfter: 1,
            argument: """
                F-81's ⌃⌘H, and the defect this suite exists for. `QuestionExit.screenReclaimed`'s \
                twin exactly: the delivery stands, because the person saw it — they pressed a key \
                to make it go away — the row is completed `ignored`, and both backoffs hear about \
                it. Not a take-back: withdrawing the row would say nobody was shown anything, and \
                putting the ladder back where it stood would put the same panel in front of them \
                at the next mandate, which is the app arguing with the one command it has for \
                *stop showing me things*. The ladder is `nil` afterwards because the panel is the \
                top rung, so `LadderMachine.ignore(now:)` puts it on the floor.
                """
        ),
        Row(
            exit: .presentationWithdrew,
            takesBackTheDelivery: true,
            leavesTheInterruptionUnanswered: false,
            countsAsAnIgnoredAccusation: false,
            ladderAfter: .ambient,
            holdsARungAfter: false,
            ignoredRunAfter: 0,
            argument: """
                R-84. The app took its own overlay off the display, so nobody could have answered \
                it: R-81 applies exactly as it does at the show. The ladder returns to the rung it \
                was standing on before the panel was delivered — which is what \
                `withdrawForPresentation()` has documented since it was written and never did — \
                the row leaves the day's spend, and neither backoff is told, because a withdrawal \
                is the app's own statement that nobody was shown anything.
                """
        ),
        Row(
            exit: .displayStranded,
            takesBackTheDelivery: true,
            leavesTheInterruptionUnanswered: false,
            countsAsAnIgnoredAccusation: false,
            ladderAfter: .ambient,
            holdsARungAfter: false,
            ignoredRunAfter: 0,
            argument: """
                focus-56y, and the one exit that already had its take-back — which is why it is \
                the calibration row rather than a repair. A sticky panel outlives the display it \
                was placed on; unanswerable is undelivered, whether it became unanswerable in the \
                first millisecond or the first minute.
                """
        ),
        Row(
            exit: .worldMovedOn,
            takesBackTheDelivery: false,
            leavesTheInterruptionUnanswered: true,
            countsAsAnIgnoredAccusation: false,
            ladderAfter: nil,
            holdsARungAfter: false,
            ignoredRunAfter: 0,
            argument: """
                The exit nobody had counted: a session ending, the phase leaving focus, the \
                commitment changing, or the application quitting. The row still gets its outcome, \
                which is focus-gmr's ruling, but neither backoff may — ending a session is not \
                ignoring a nudge, and `sessionEnded()` reduces `FatigueEvent.sessionEnded` before \
                it closes the surfaces, so a run counted here would dirty one that has just been \
                reset. The `0` below is that clause, and it is the reason this exit is not spelled \
                `replaced` with a different comment.
                """
        )
    ]

    // MARK: - The world each row is driven in

    /// Sustained drift into one application until the shipping ladder puts a rung on a real panel.
    ///
    /// Every rung is delivered by the loop rather than installed by the test, and the menu bar is
    /// joined the way the composition root joins it — so the glyph rung underneath is charged from
    /// a real write to a real status item, and the panel rung above it is a real window.
    static func aRungOnThePanel(in fixture: NudgeHostFixture) throws {
        fixture.workspace.runningNames[Self.drifted] = "Browser"
        fixture.workspace.runningNames[Self.thenDrifted] = "Reader"
        try fixture.wireMenuBarToTheLoop()

        for _ in 0..<2 {
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.drifted))
            NudgeHostFixture.settle()
            fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }
        try #require(
            fixture.host.currentRung == .panel,
            "the ladder did not reach the panel rung, so this row drives nothing"
        )
        try #require(
            fixture.host.landedRungSurface == .panel && fixture.panel.isVisible
                && fixture.panel.showing == .accusation,
            "the panel rung did not reach a real panel, so this row drives nothing"
        )
    }

    /// Take this exit, on the loop, by the route the shipping app takes it by.
    ///
    /// One `switch`, exhaustive: a seventh exit is a compile error here rather than a seventh
    /// round.
    static func take(_ exit: RungExit, in fixture: NudgeHostFixture) {
        switch exit {
        case .answered:
            // A dismissal, because it is the one correction that is not an answer — so the ladder
            // and the fatigue run are moved by `resolve(…)` itself and the door must not move them
            // again. "This is relevant" would also mark the subject corrected, which would silence
            // the drift this row goes on to drive.
            fixture.host.resolve(.dismiss, snoozeDuration: nil)

        case .replaced:
            // The person gives up on that application and drifts into a different one. A different
            // subject resets a topped-out ladder, so the rung this raises is the ambient glyph.
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.thenDrifted))

        case .screenReclaimed:
            // F-81's one command, through the same function the View menu's ⌃⌘H sends.
            fixture.host.hideOverlays()

        case .presentationWithdrew:
            // A presentation claims the display. Reached through `consider(_:)` — the gate closing
            // is an event noticed on the next corroboration tick — rather than by calling the
            // private withdrawal, so the wiring is under test and not only the consequence.
            fixture.host.surroundings = { [clock = fixture.clock, commitment = fixture.commitment] in
                NudgeHostFixture.surroundings(
                    monotonic: clock.elapsed,
                    commitment: commitment,
                    presentation: PresentationState(
                        signals: .none, isUserExcluded: true, isPresenting: true
                    )
                )
            }
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.drifted))

        case .displayStranded:
            // The display is replaced by one that cannot hold the panel's actions however it is
            // placed, and the notification AppKit really posts is the thing that carries it in.
            // The display is derived from the panel's own arithmetic rather than written down:
            // what this row needs is one too small for whatever the shipping accusation turns out
            // to be.
            let stranding = NudgeHostDisplayChangeTests.displayTooSmall(for: fixture.panel)
            fixture.panel.displays = { stranding }
            NudgeHostDisplayChangeTests.theDisplayConfigurationChanges()

        case .worldMovedOn:
            fixture.host.sessionEnded()
        }
        NudgeHostFixture.settle()
    }

    /// Put back whatever the row injected into the world, so the last clause asks about the loop
    /// rather than about the rig.
    static func restoreTheWorld(after exit: RungExit, in fixture: NudgeHostFixture) {
        switch exit {
        case .presentationWithdrew:
            fixture.host.surroundings = { [clock = fixture.clock, commitment = fixture.commitment] in
                NudgeHostFixture.surroundings(monotonic: clock.elapsed, commitment: commitment)
            }
        case .displayStranded:
            fixture.panel.displays = { NudgeHostDisplayChangeTests.desk }
        case .answered, .replaced, .screenReclaimed, .worldMovedOn:
            break
        }
    }

    /// Sustained drift again, at the shipping cadence, until a rung lands on some surface.
    @discardableResult
    static func driftUntilARungLands(in fixture: NudgeHostFixture) -> NudgeSurface? {
        for _ in 0..<3 {
            if fixture.host.landedRungSurface != nil { break }
            fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.drifted))
            NudgeHostFixture.settle()
        }
        return fixture.host.landedRungSurface
    }

    // MARK: - The fold

    /// **The class, not the instance.** One row per case, each driven through the shipping loop
    /// with the rung on the panel.
    @Test(
        "every exit from a delivered panel rung settles the ladder, the row and both backoffs",
        .enabled(if: LocalizationLane.catalogsAreCompiled),
        arguments: NudgeRungExitTests.rows
    )
    func everyExitSettlesEverythingAnEndingHasToSettle(row: Row) throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try Self.aRungOnThePanel(in: fixture)

        let panelRowsBefore = try fixture.interventions()
            .filter { $0.rungRaw == LadderRung.Kind.panel.rawValue }
        try #require(
            panelRowsBefore.count == 1
                && panelRowsBefore[0].dispositionRaw == InterventionDisposition.delivered.rawValue,
            """
            the panel rung wrote \(panelRowsBefore.map(\.dispositionRaw)) rather than one \
            delivery, so there is nothing for \(row.exit.rawValue) to end
            """
        )

        Self.take(row.exit, in: fixture)

        // 1 · the ladder — the reading the two defects were in.
        #expect(
            fixture.host.currentRung == row.ladderAfter,
            """
            \(row.exit.rawValue) left the ladder at \
            \(fixture.host.currentRung?.rawValue ?? "nothing") rather than at \
            \(row.ladderAfter?.rawValue ?? "nothing"). \(row.argument)
            """
        )

        // 2 · the surfaces — nothing is left drawing a nudge this host is not holding.
        #expect(
            fixture.host.orphanedNudgeSurfaces.isEmpty,
            """
            \(row.exit.rawValue) left a nudge on \
            \(fixture.host.orphanedNudgeSurfaces.map(\.rawValue)) that this host has forgotten
            """
        )
        #expect(
            (fixture.host.landedRungSurface != nil) == row.holdsARungAfter,
            """
            \(row.exit.rawValue) left this host holding \
            \(fixture.host.landedRungSurface?.rawValue ?? "no rung")
            """
        )

        // 3 · the row — withdrawn from the day's spend, or completed, or neither.
        let panelRow = try #require(
            fixture.interventions().first { $0.rungRaw == LadderRung.Kind.panel.rawValue },
            "the panel rung's record vanished"
        )
        let expectedDisposition = row.takesBackTheDelivery
            ? InterventionDisposition.deferred
            : InterventionDisposition.delivered
        #expect(
            panelRow.dispositionRaw == expectedDisposition.rawValue,
            """
            \(row.exit.rawValue) left the panel rung's row \(panelRow.dispositionRaw) when \
            takesBackTheDelivery is \(row.takesBackTheDelivery). \(row.argument)
            """
        )
        if row.leavesTheInterruptionUnanswered {
            #expect(
                panelRow.outcomeRaw == InterventionOutcome.ignored.rawValue,
                """
                \(row.exit.rawValue) left the panel rung's row saying \
                \(panelRow.outcomeRaw ?? "nothing about what the person did")
                """
            )
        } else {
            #expect(
                panelRow.outcomeRaw != InterventionOutcome.ignored.rawValue,
                "\(row.exit.rawValue) wrote `ignored` onto a row it is not true of"
            )
        }

        // 4 · the session-wide backoff — a count, because double counting is a failure too.
        #expect(
            fixture.host.fatigue.state.consecutiveIgnoredAccusations == row.ignoredRunAfter,
            """
            \(row.exit.rawValue) left the ignored-accusation run at \
            \(fixture.host.fatigue.state.consecutiveIgnoredAccusations) rather than \
            \(row.ignoredRunAfter). \(row.argument)
            """
        )

        // 4a · **and no single exit reaches the ladder's own hold** (focus-50m, re-checked with
        // `replaced` counting).
        //
        // The hold is no longer a trap — it expires at `InterventionPolicy.backoffSpan` and
        // retains the mark, which is what let `replaced` ship (focus-fzf) — but it is still a
        // state one ending must not be able to reach on its own: `LadderMachine`'s run is what
        // `ignore(now:)` counts, and one ignore cannot be two. It holds because the door asks
        // `LadderRung.Kind.makesAnAccusation` as well as the exit, so only the top rung can be
        // ignored through it, and `ignore(now:)` puts the top rung on the floor before the run can
        // reach `InterventionPolicy.ignoredAccusationBackoff`.
        if case .heldAtAmbient = fixture.host.ladder.state {
            Issue.record(
                """
                \(row.exit.rawValue) reached LadderState.heldAtAmbient on ONE ending, so the \
                ladder's own run counted a single exit twice (focus-50m, focus-fzf)
                """
            )
        }

        // 5 · **and the app can still speak.** The clause the whole round is about.
        Self.restoreTheWorld(after: row.exit, in: fixture)
        let landed = Self.driftUntilARungLands(in: fixture)
        #expect(
            landed != nil,
            """
            after \(row.exit.rawValue) the loop never raised another rung: the ladder is standing \
            at \(fixture.host.currentRung?.rawValue ?? "nothing") and its last decision was \
            \(String(describing: fixture.host.lastDecision))
            """
        )
    }

    // MARK: - The completeness checks

    /// **Every exit the vocabulary declares has a row, and no two rows drive the same one.**
    @Test("the table covers every exit from a delivered rung")
    func theTableCoversEveryExit() {
        let covered = Set(Self.rows.map(\.exit))
        for exit in RungExit.allCases {
            #expect(
                covered.contains(exit),
                "\(exit.rawValue) ends a delivered rung and has no row saying what it settles"
            )
        }
        #expect(covered.count == Self.rows.count, "two rows drive the same exit")
        #expect(Self.rows.count == RungExit.allCases.count)
        #expect(!RungExit.allCases.isEmpty, "a fold over an empty vocabulary proves nothing")
    }

    /// **The table's literals are the specification; `RungExit` is the implementation.**
    ///
    /// Compared rather than read back. A row that asked `exit.takesBackTheDelivery` what it does
    /// would agree with any implementation, including the one that produced the defect.
    @Test("every literal in the table is the answer the vocabulary gives")
    func theVocabularyMatchesTheTable() {
        for row in Self.rows {
            #expect(
                row.exit.takesBackTheDelivery == row.takesBackTheDelivery,
                "\(row.exit.rawValue).takesBackTheDelivery contradicts its row. \(row.argument)"
            )
            #expect(
                row.exit.leavesTheInterruptionUnanswered == row.leavesTheInterruptionUnanswered,
                """
                \(row.exit.rawValue).leavesTheInterruptionUnanswered contradicts its row. \
                \(row.argument)
                """
            )
            #expect(
                row.exit.countsAsAnIgnoredAccusation == row.countsAsAnIgnoredAccusation,
                """
                \(row.exit.rawValue).countsAsAnIgnoredAccusation contradicts its row. \
                \(row.argument)
                """
            )
        }
    }

    /// **A delivery the app is taking back cannot also be a delivery the person ignored** (R-81).
    ///
    /// The one relation between the three properties, and the reason it is stated rather than left
    /// to the reader: `undeliverRecord(…)` turns the row into a deferral, so an outcome written
    /// onto it afterwards would be the app saying somebody ignored something it has just declared
    /// reached nobody — and a backoff advanced for it would be the same sentence in the fatigue
    /// controller. Asserted over the **table**, so an exit that acquired both answers fails here
    /// before any drive is run.
    @Test("no exit both withdraws a delivery and says somebody ignored it")
    func theTakeBackIsNotAlsoAnIgnore() {
        for row in Self.rows {
            #expect(
                !(row.takesBackTheDelivery
                    && (row.leavesTheInterruptionUnanswered || row.countsAsAnIgnoredAccusation)),
                """
                \(row.exit.rawValue) both withdraws a delivery and says somebody ignored it. \
                \(row.argument)
                """
            )
        }
    }

    /// **The rule is never a constant function.**
    ///
    /// Every one of the three properties is answered both ways by the table, so a build that
    /// collapsed one of them into `true` or `false` everywhere fails here rather than passing the
    /// fold with six rows that all agree.
    @Test("each property in the vocabulary is answered both ways")
    func theRuleIsNeverAConstantFunction() {
        #expect(Set(Self.rows.map(\.takesBackTheDelivery)) == [true, false])
        #expect(Set(Self.rows.map(\.leavesTheInterruptionUnanswered)) == [true, false])
        #expect(Set(Self.rows.map(\.countsAsAnIgnoredAccusation)) == [true, false])
        // And the exit that takes a delivery back includes the one that had its take-back before
        // this round, so the table is calibrated against known-correct behaviour rather than
        // against this round's own opinion.
        #expect(RungExit.displayStranded.takesBackTheDelivery)
    }

    /// **Every exit is one the loop can actually reach.**
    ///
    /// The check above counts rows; this is what stops an exit being declared, given a row, and
    /// never produced. Each row's own drive is run and the ending it produces has to be visible:
    /// the rung this host was holding is no longer the one it was holding.
    @Test(
        "every exit the vocabulary declares is one the shipping loop can take",
        .enabled(if: LocalizationLane.catalogsAreCompiled),
        arguments: NudgeRungExitTests.rows
    )
    func everyExitIsOneTheLoopCanProduce(row: Row) throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try Self.aRungOnThePanel(in: fixture)
        let before = try #require(fixture.host.openRungPresentation)

        Self.take(row.exit, in: fixture)

        let after = fixture.host.openRungPresentation
        #expect(
            after != before,
            """
            \(row.exit.rawValue) is declared and its drive left the same rung standing on the \
            same surface, so this row drives nothing
            """
        )
    }
}
