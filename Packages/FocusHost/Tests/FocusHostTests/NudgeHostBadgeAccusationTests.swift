import AppKit
import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **The top rung on the badge is a decision surface, not a label** (focus-uru, U-1, D-07).
///
/// ## The defect
///
/// `SurfaceRouter.route(rung: .panel, …)` answers `.popoverBadge` whenever `reducedInterruption`
/// is set, and the composition root forces that flag on from `AppearanceObserver`'s traits
/// whenever macOS **Reduce Motion** is on — also under the `silentVisual` deck, and while a
/// microphone is running. The popover drew the
/// belief row and nothing else: *"Nudge: Panel"*. No dismiss, no "this is relevant", no "not this
/// time", no snooze. The rung was a read-only label.
///
/// `CorrectionAction`'s own doc states the rule it broke — *"a nudge you cannot answer back to is
/// an anti-pattern… Every surface, including the top rung, is dismissible"* — and U-1's bargain
/// fails at its root there: this app is licensed to interrupt **because** the answer is one cheap
/// click that teaches it. On this surface there was no answer to give, for exactly the people who
/// had asked the system for a calmer one.
///
/// ## Why the suite could not see it
///
/// Every reading the gate took said *in-app*. `everyRungIsInApp` was true, `everyRungHasASurface`
/// was true, and the routing table's self-check row was computed at `reducedInterruption: false`
/// alone — the one setting that always answers `.panel`. Nothing anywhere asked whether the
/// surface a rung landed on had anything on it to press.
///
/// ## What this drives
///
/// The running loop, one corroboration tick at a time, with the flag on: the ladder climbs to the
/// panel rung, the router sends it to the badge, and the host is asked for the presentation the
/// popover draws. Then a correction is pressed **through the menu bar's own typed request**, the
/// way the composition root wires it, and the write it produced is read out of the store.
@Suite("The top rung on the badge can be answered", .serialized)
@MainActor
struct NudgeHostBadgeAccusationTests {
    static let subject = NudgeHostFixture.decoy

    /// **The two ways a person reaches the badge from the Intervention pane**, and both are two
    /// clicks away (focus-vxo).
    ///
    /// The suite drove the checkbox alone, and the deck was the one that was broken: it sent the
    /// top rung to the menu-bar glyph, where the loop recorded it *delivered* against a named
    /// application while the popover had nothing on it to press. Both are now driven, because a
    /// proof written to one of two settings of one pane is a proof written to the case somebody
    /// happened to hold.
    ///
    /// The third route to the badge — a running microphone — cannot be driven here and is not
    /// missing: gate 6 of the suppression stack refuses the whole intervention while a microphone
    /// is running, so the router's backstop is reached only from a caller that skipped the stack.
    /// `SurfaceRouterTests` and the self-check's own fold cover that cell over the whole matrix.
    enum QuietRoute: String, CaseIterable, Sendable {
        /// F-148's checkbox — the one macOS Reduce Motion forces on.
        case reducedInterruption
        /// Settings → Intervention → "Silent and visual".
        case routingDeck
    }

    /// Drive sustained drift under one of the quiet routes until the ladder reaches the panel rung.
    ///
    /// Two ticks, exactly as `NudgeHostLadderTests.theLoopClimbsTheWholeLadder` drives it: the
    /// ladder enters at `.ambient` and escalates once the clock has passed both `escalationDwell`
    /// and the longer `mandateCooldown`.
    static func climbToTheBadge(_ fixture: NudgeHostFixture, via route: QuietRoute) {
        switch route {
        case .reducedInterruption: fixture.host.choose(reducedInterruption: true)
        case .routingDeck: fixture.host.choose(voice: .silentVisual)
        }
        for _ in 0..<2 {
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
            NudgeHostFixture.settle()
            fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }
    }

    /// **The rung lands on the badge carrying the panel's whole correction economy.**
    ///
    /// The presentation is built by the same `accusationPresentation(for:commitment:)` the panel
    /// is drawn from, so this is not "the badge has some buttons" — it is the same six actions,
    /// in the same order, about the same subject, under the same commitment.
    @Test(
        "a top rung routed to the badge arrives with every answer the panel would offer",
        arguments: QuietRoute.allCases
    )
    func theBadgeRungCarriesItsAnswers(via route: QuietRoute) throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        Self.climbToTheBadge(fixture, via: route)

        #expect(fixture.host.currentRung == .panel, "the ladder did not reach the top rung")
        guard case .accuse(_, .surface(.popoverBadge)) = fixture.host.lastDecision else {
            let decision = String(describing: fixture.host.lastDecision)
            Issue.record("\(route.rawValue): the rung was not routed to the badge: \(decision)")
            return
        }
        // Reduce Motion does not get a panel. That was the alternative fix and it is the wrong
        // one: it overrides a setting the person chose, and the microphone case that shares this
        // route forbids it outright — a panel over a call is a panel everybody on the call sees.
        #expect(!fixture.panel.isVisible)

        let presentation = try #require(
            fixture.host.pendingPopoverAccusation,
            "the badge rung published no presentation, so the popover has only a label to draw"
        )
        #expect(presentation.rung == .panel)
        // **Both halves, and they differ** (focus-ebv). The identifier is what the correction
        // will be keyed on; the display name is what the badge draws — and asserting the second
        // is what proves the host consulted the naming seam rather than falling back to the key.
        #expect(presentation.subject?.identifier == Self.subject)
        #expect(presentation.subject?.displayName == NudgeHostFixture.displayNames[Self.subject])
        #expect(presentation.task == fixture.commitment.intent)

        // The invariant, read on the surface the rung actually reached.
        #expect(NudgeSurface.popoverBadge.offersAnAnswer)
        #expect(
            !presentation.offeredActions.isEmpty,
            "the top rung reached a surface with no way to answer it"
        )
        // Every action that writes a rule has a subject to write it about, and the two that do
        // not need one are here as well: this is the panel's set, unabridged.
        #expect(presentation.offeredActions.contains(.thisIsRelevant))
        #expect(presentation.offeredActions.contains(.notThisTime))
        #expect(presentation.offeredActions.contains(.snooze))
        #expect(presentation.offeredActions.contains(.pause))
    }

    /// **The answer travels, and it writes** — through the same `MenuBarAction` the popover
    /// reports and the composition root performs.
    ///
    /// A surface that offers a button whose click nothing acts on is the same defect one layer
    /// further along, so the proof ends at the store: "this is relevant" writes a task-authority
    /// rule about this subject, the ladder de-escalates, and the badge stops offering answers for
    /// a rung this host no longer holds.
    @Test(
        "a correction pressed on the badge is written, and takes the rung down with it",
        arguments: QuietRoute.allCases
    )
    func aCorrectionOnTheBadgeIsWritten(via route: QuietRoute) throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        var written: [CorrectionOutcome] = []
        fixture.host.onCorrection = { outcome, _ in written.append(outcome) }

        Self.climbToTheBadge(fixture, via: route)
        #expect(
            fixture.host.pendingPopoverAccusation != nil,
            "\(route.rawValue) published no presentation for the badge to draw"
        )

        // The press. `AppComposition.perform(_:)` maps `.correct` straight onto this call, so a
        // click on the badge and a click on the panel are literally the same one.
        fixture.host.resolve(.thisIsRelevant, snoozeDuration: nil)
        NudgeHostFixture.settle()

        let rule = try #require(
            written.compactMap(\.ruleAwaitingPersistence).first,
            "the correction wrote nothing at all"
        )
        #expect(rule.subject == Self.subject)
        #expect(rule.verdict == .relevant)
        #expect(rule.authority == .task)

        // De-escalation is immediate and total, and the badge gives its answers back with the
        // rung they belonged to — an open popover still offering "this is relevant" for a rung
        // the host has forgotten is focus-v0u's orphan wearing the accusation's clothes.
        #expect(fixture.host.currentRung == nil)
        #expect(fixture.host.pendingPopoverAccusation == nil)
    }

    // MARK: - The badge is an invitation, not a delivery (focus-xix)

    /// **A rung sitting behind a click has cost the person nothing** (focus-xix, R-81).
    ///
    /// The defect, as the person met it. `accuse(…)`'s `.menuBar, .popoverBadge` branch called
    /// `delivered(…)` unconditionally, and `delivered(…)` did three things in one breath: advanced
    /// the ladder, spent `fatigue.reduce(.delivered(.accusation))`, and wrote a
    /// `disposition = .delivered` row. Nothing on screen changed — `MenuBarController.redraw`
    /// draws from the status and the timer alone, `pendingAccusation` reaches the button by no
    /// path, and `announceStatusChange` does not fire because the ambient rung already set
    /// `.unrelated`. So the climb from rung 1 to rung 2 was silent, invisible **and**
    /// unannounced, while it spent one of `dailyAccusationCap`'s six and one of
    /// `dailyInterruptionCap`'s eight and armed a 600-second cooldown.
    ///
    /// Measured on the shipping loop before the repair: `accusationsToday=2`,
    /// `interruptionsToday=2`, two rows both `disposition=delivered`, popover never opened. Three
    /// drift episodes exhausted the day, and `InterventionSettingsView` printed *"Nudges today
    /// 3 / 6"* back to somebody who had been shown a glyph.
    ///
    /// **What must still be true**, and is asserted here so the repair cannot be "stop counting
    /// it" — the mutation that produced four failures, all `currentRung == .ambient`: the rung has
    /// still *landed*. The ladder is on it, the badge is carrying its answers, and the popover has
    /// something to draw. Landing and being seen are two facts, and only the second is a spend.
    @Test(
        "a rung waiting in an unopened badge spends nothing",
        arguments: QuietRoute.allCases
    )
    func aBadgeRungBehindAClickIsNotCounted(via route: QuietRoute) throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try fixture.wireMenuBarToTheLoop()

        Self.climbToTheBadge(fixture, via: route)

        try #require(!fixture.menuBar.isPopoverShown, "the popover opened without anybody clicking")
        // It landed: the ladder is on the top rung and the badge is carrying its answers.
        #expect(fixture.host.currentRung == .panel, "the rung did not land")
        #expect(
            fixture.host.pendingPopoverAccusation != nil,
            "the badge has nothing to draw, so the rung reached no surface at all"
        )

        // And it has cost the person nothing. One delivery — the ambient glyph, which really is
        // on screen — and not the badge behind the click.
        #expect(
            fixture.host.deliveredCount == 1,
            "\(route.rawValue): a rung nobody has been shown was counted as delivered"
        )
        let budget = fixture.host.todaysUsage()
        #expect(
            budget.accusationsToday == 0,
            "the day's accusation budget was charged for a badge nobody opened"
        )
        // **The one delivery is the ambient glyph, and it spends an interruption and not an
        // accusation** (focus-ndh). The glyph took a moment of the person's attention and is
        // counted for it; it accuses nobody — `LadderRung.Kind.ambient.makesAnAccusation` is
        // `false` — so `dailyAccusationCap`, which is a cap on sentences, is untouched.
        #expect(budget.interruptionsToday == 1)
        let badgeRows = try fixture.interventions().filter { $0.surface == .popoverBadge }
        #expect(
            badgeRows.isEmpty,
            "a row was written for a badge nobody opened: \(badgeRows.map(\.disposition.rawValue))"
        )
    }

    /// **Opening the popover is what counts it** — the accusation's
    /// `popoverPresentedTheQuestion()`, which did not exist.
    ///
    /// Driven through the wire the composition root actually installs: the status item is clicked,
    /// `MenuBarController.onPopoverDidShow` fires, and `NudgeHost.popoverPresented()` is the only
    /// thing that turns the invitation into a delivery. Nothing here calls `delivered(…)` by
    /// another name.
    @Test("the rung is counted at the moment the popover shows it, and only then")
    func openingThePopoverCountsTheBadgeRung() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try fixture.wireMenuBarToTheLoop()

        Self.climbToTheBadge(fixture, via: .reducedInterruption)
        // The ambient rung has landed and is charged one *interruption*, and no accusation: the
        // glyph accuses nobody (focus-ndh).
        try #require(fixture.host.todaysUsage().interruptionsToday == 1)
        try #require(fixture.host.todaysUsage().accusationsToday == 0)

        // The click. `onDidShow` is `nil` so the stage leaves the shipping wire alone.
        try MenuBarStage.open(
            fixture.menuBar,
            showing: NudgeHostFixture.menuBarPresentation(of: fixture.host)
        )
        NudgeHostFixture.settle()

        #expect(fixture.menuBar.isDrawing(.accusation), "the popover is not showing the rung")
        #expect(fixture.host.deliveredCount == 2, "the rung the person is looking at was not counted")
        // The badge carries the **panel** rung, which does accuse somebody, so this one spends
        // an accusation as well as an interruption (focus-ndh).
        #expect(fixture.host.todaysUsage().accusationsToday == 1)
        #expect(fixture.host.todaysUsage().interruptionsToday == 2)

        let badge = try #require(
            try fixture.interventions().first { $0.surface == .popoverBadge },
            "no row was written for the rung the person opened the popover onto"
        )
        #expect(badge.kind == .accusation)
        #expect(badge.disposition == .delivered)
        #expect(badge.rung == .panel)
        #expect(badge.subject == Self.subject)
    }

    /// **Looked at twice is still one delivery.**
    ///
    /// The guard that makes the repair safe to call from three places — the landing, the redraw
    /// and the click — rather than from exactly one that somebody has to remember. Without it the
    /// fix would trade a spend nobody earned for a spend charged once per glance.
    @Test("a rung is counted once however many times the popover is opened on it")
    func theBadgeRungIsCountedOnce() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try fixture.wireMenuBarToTheLoop()

        Self.climbToTheBadge(fixture, via: .reducedInterruption)
        try MenuBarStage.open(
            fixture.menuBar,
            showing: NudgeHostFixture.menuBarPresentation(of: fixture.host)
        )
        NudgeHostFixture.settle()
        try #require(fixture.host.todaysUsage().accusationsToday == 1)
        try #require(fixture.host.todaysUsage().interruptionsToday == 2)

        fixture.menuBar.closePopover()
        NudgeHostFixture.settle()
        try MenuBarStage.open(
            fixture.menuBar,
            showing: NudgeHostFixture.menuBarPresentation(of: fixture.host),
            install: false
        )
        NudgeHostFixture.settle()
        // And the loop is asked directly, twice more, which is what a redraw does.
        fixture.host.popoverPresented()
        fixture.host.popoverPresented()

        #expect(
            fixture.host.todaysUsage().accusationsToday == 1,
            "the same rung was charged again for a second look"
        )
        #expect(
            fixture.host.todaysUsage().interruptionsToday == 2,
            "the same rung interrupted the person again for a second look"
        )
        let badgeRows = try fixture.interventions().filter { $0.surface == .popoverBadge }
        #expect(badgeRows.count == 1, "one rung, \(badgeRows.count) rows")
    }

    /// **R-81's own worry cannot happen here, and this is why the ladder may advance on a landing.**
    ///
    /// R-81 forbids escalating *through* a rung nobody saw, because the person would meet the
    /// loudest thing the app can do having never been shown the quietest. The badge cannot produce
    /// that: `SurfaceRouter` reaches `.popoverBadge` for an accusation from the `.panel` rung
    /// alone, and `.panel` is the top — U-2 deleted the rung above it. So the advance this repair
    /// keeps carries the ladder past nothing, and the part of R-81 that is still at stake — the
    /// budget, the fatigue run and the ledger — is exactly the part the repair holds back.
    ///
    /// Stated as an assertion rather than as a comment, because it is the load-bearing half of
    /// the argument and it would stop being true the moment focus-5ab puts a rung above `.panel`.
    @Test("no rung sits above the one the badge carries, so an unopened badge escalates past nothing")
    func theBadgeCarriesTheTopRung() throws {
        #expect(
            LadderRung.Kind.panel.next == nil,
            "a rung above the panel exists, so an unseen badge could now escalate through R-81"
        )
        for reduced in [true, false] {
            let route = SurfaceRouter.route(
                rung: .ambient,
                presentation: .notPresenting,
                media: .idle,
                reducedInterruption: reduced,
                menuBarVisible: true,
                voice: .silentVisual
            )
            #expect(
                route.surface != .popoverBadge,
                "the ambient rung now reaches the badge, so a lower rung can go unseen"
            )
        }
    }

    // MARK: - The badge draws the rung's own commitment (focus-xix, focus-lmo)

    /// **The badge keeps its sentence when the commitment can no longer be read.**
    ///
    /// `pendingPopoverAccusation` carried a guard its twin does not: `guard let commitment =
    /// activeCommitment() else { return nil }`, taken against a **live** reading of the
    /// surroundings rather than against the value the rung was raised with. Every redraw of an
    /// open popover re-runs it, so the one taken after the commitment went away answered `nil` —
    /// the badge's five answers vanished mid-nudge, on a surface the person was looking at, with
    /// the rung still open and `resolve(…)` still willing to write a correction nothing was
    /// offering.
    ///
    /// The panel never had this failure because its presentation is built once, from the
    /// commitment `accuse(…)` was handed. The rung carries that commitment now, so both surfaces
    /// are drawn from one value and the second reading is gone rather than guarded.
    @Test("the badge still draws its rung when the commitment can no longer be read")
    func theBadgeDrawsTheRungsOwnCommitment() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        Self.climbToTheBadge(fixture, via: .reducedInterruption)
        let raised = try #require(fixture.host.pendingPopoverAccusation)
        #expect(raised.task == fixture.commitment.intent)

        // The surroundings stop naming a commitment — a completion, a pause between two
        // judgements, anything that empties `PriorityHost.activeCommitment` between the landing
        // and the next redraw.
        fixture.host.surroundings = { [clock = fixture.clock] in
            NudgeHostFixture.surroundings(monotonic: clock.elapsed, commitment: nil)
        }

        let redrawn = try #require(
            fixture.host.pendingPopoverAccusation,
            "the badge went blank on a second reading of the commitment, mid-nudge"
        )
        #expect(
            redrawn.task == fixture.commitment.intent,
            "the badge redrew under a different task from the one the correction will be keyed to"
        )
        #expect(redrawn.subject?.identifier == Self.subject)
    }

    // MARK: - Nothing is left drawn that the loop is not holding (focus-v0u's other half)

    /// **A rung that leaves the badge takes the popover's answers with it.**
    ///
    /// `forgetOpenRung()` carried the redraw and the two assignments in `accuse(…)` did not, so a
    /// rung that was on the badge and was *replaced* — by a fresh entry rung for a different
    /// subject, which is what `LadderMachine.arrive(_:)` produces — left the popover drawing the
    /// old accusation about the old application. A click on it would not have been dropped: it
    /// would have reached `resolve(…)` and been applied to the rung this host is holding **now**,
    /// writing a rule about the wrong application.
    ///
    /// Every write of `openRung` goes through `setOpenRung(_:)`, which redraws whenever the
    /// badge's contents change in either direction.
    @Test("a rung replaced on the badge stops being offered there")
    func aReplacedBadgeRungStopsBeingOffered() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try fixture.wireMenuBarToTheLoop()

        Self.climbToTheBadge(fixture, via: .reducedInterruption)
        try Self.openThePopoverOnTheBadge(fixture)
        try #require(fixture.menuBar.isDrawing(.accusation))

        // A different application, once the mandate cooldown has passed — otherwise the decider
        // is silent and nothing is replaced, which would make this test pass by measuring
        // nothing. The ladder resets to `.idle` for a new subject and re-enters at the ambient
        // glyph, so the badge's rung is replaced by one on the menu bar.
        fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        fixture.host.consider(
            NudgeHostFixture.unrelatedJudgement(subject: "com.chrismitchelmore.FocusOtherApp")
        )
        NudgeHostFixture.settle()

        try #require(
            fixture.host.pendingPopoverAccusation == nil,
            "the rung is still on the badge, so this proves nothing about the redraw"
        )
        #expect(
            !fixture.menuBar.isDrawing(.accusation),
            """
            the popover is still offering answers for a rung the loop has replaced; a click on \
            them would be written against the new one
            """
        )
    }

    /// **The invariant that watches for it reads both kinds.**
    ///
    /// `orphanedQuestionSurfaces` was built for focus-v0u and read half the screen: an accusation
    /// can be left drawn on the same two surfaces, with a worse consequence, and had no reading at
    /// all. This drives the reading into the state it exists to catch — the popover carrying an
    /// accusation the loop is not holding — and then out of it again, because a reading that
    /// cannot go non-empty is not an invariant, it is a constant.
    @Test("the orphan reading sees an accusation the loop is not holding")
    func theOrphanReadingSeesAnAccusation() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        Self.climbToTheBadge(fixture, via: .reducedInterruption)
        let stranded = try #require(fixture.host.pendingPopoverAccusation)
        try MenuBarStage.open(
            fixture.menuBar,
            showing: MenuBarPresentation(status: .unrelated, pendingAccusation: stranded)
        )
        NudgeHostFixture.settle()
        try #require(fixture.menuBar.isDrawing(.accusation))

        // The loop lets the rung go — a phase change, a session end — while the popover keeps the
        // presentation it was last handed, which is exactly what a hosting controller does.
        fixture.host.phaseLeftFocus()
        NudgeHostFixture.settle()

        #expect(
            fixture.host.orphanedNudgeSurfaces == [.popoverBadge],
            """
            the popover is offering an accusation the loop has forgotten and the invariant \
            cannot see it: \(fixture.host.orphanedNudgeSurfaces.map(\.rawValue))
            """
        )

        // And the redraw the shipping wire performs clears it.
        fixture.menuBar.update(NudgeHostFixture.menuBarPresentation(of: fixture.host))
        NudgeHostFixture.settle()
        #expect(fixture.host.orphanedNudgeSurfaces.isEmpty)
    }

    static func openThePopoverOnTheBadge(_ fixture: NudgeHostFixture) throws {
        try MenuBarStage.open(
            fixture.menuBar,
            showing: NudgeHostFixture.menuBarPresentation(of: fixture.host)
        )
        NudgeHostFixture.settle()
    }

    /// **A rung on the panel is not published to the badge**, so the popover cannot draw an
    /// accusation the router sent somewhere else.
    ///
    /// The twin of `pendingPopoverQuery`'s own guard (focus-kby): the test is the surface the
    /// router chose, not "the panel is not up".
    @Test("a rung the router sent to the panel never appears in the popover")
    func aPanelRungIsNotOnTheBadge() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        for _ in 0..<2 {
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
            NudgeHostFixture.settle()
            fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }

        #expect(fixture.host.currentRung == .panel)
        #expect(fixture.panel.isVisible)
        #expect(
            fixture.host.pendingPopoverAccusation == nil,
            "a panel rung was offered to the popover as well, which is two nudges for one rung"
        )
    }
}
