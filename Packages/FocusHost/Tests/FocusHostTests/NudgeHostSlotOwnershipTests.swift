import AppKit
import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **The one interruption slot is held by something a person can actually answer** (focus-k42,
/// R-84a, U-1, U-2).
///
/// ## Ownership is not identity
///
/// `openRung` stood for two different facts at once — *which rung this loop is holding, with its
/// commitment and its offered corrections*, and *whether the one interruption slot is occupied* —
/// and `slot` was derived from `openRung != nil`, which made the two formally **identical**. A
/// disagreement between them stopped being spottable rather than becoming impossible.
///
/// Two consequences follow from that identity, and both are things a person meets:
///
/// * `accuse(…)` assigns the rung *before* it knows whether any surface will carry it, and
///   releases it on **no deferral path at all** — not the no-surface path, not the unreadable
///   panel, not a suppressed delivery. A rung that reached nobody holds the slot for the rest of
///   the session, and `record(deferral:)` writes `disposition=deferred` for it: R-81's *"reached
///   nobody"*, still holding the one thing a nudge can hold.
/// * A rung that landed on the **ambient glyph** holds it too — and nothing ever takes an ambient
///   rung down, because the glyph carries no actions and `resolve(…)` is unreachable from it. One
///   drift lights the glyph and the app can never ask about anything again.
///
/// The second is U-1's entire affordance dying with no symptom but silence. What is asserted here
/// is the rule that replaces four separately-remembered releases: **the slot is held by a rung
/// standing on a surface a person can answer on, and by nothing else.**
@Suite("The interruption slot is held only by a rung a person can answer", .serialized)
@MainActor
struct NudgeHostSlotOwnershipTests {
    static let decoy = "com.chrismitchelmore.FocusDecoy"
    static let other = "com.chrismitchelmore.FocusOtherApp"

    /// A display too small to hold the accusation panel, so its corrections really are out of
    /// reach — the `focus-vpu` case, reached at the show rather than at a later display change.
    ///
    /// This is the deferral path that is reachable **from the decider's own routing**: a hidden
    /// menu bar is refused earlier, by `NudgeDecider`, and never reaches `accuse(…)` at all. The
    /// panel whose actions are below the clip is shown, read, found unanswerable and hidden again
    /// — all inside `accuse(…)`, after the rung has taken the slot.
    static let tooSmallForAPanel = [
        DisplayGeometry(
            displayID: 9,
            screenIndex: 0,
            isPrimary: true,
            frame: ScreenRect(x: 0, y: 0, width: 800, height: 160),
            visibleFrame: ScreenRect(x: 0, y: 0, width: 800, height: 140),
            backingScaleFactor: 1
        )
    ]

    /// **A rung the loop hid for being unanswerable gives the slot back** (R-81, focus-vpu).
    ///
    /// The panel is shown, read, found unanswerable and hidden again. `record(deferral:)` writes
    /// `disposition=deferred`, which is R-81's *"reached nobody"* — and a rung that reached nobody
    /// must not go on holding the slot any more than one that never found a surface.
    @Test("a rung hidden for being unanswerable does not go on holding the interruption slot")
    func anUnreadableRungReleasesTheSlot() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        fixture.panel.displays = { Self.tooSmallForAPanel }

        // Two ticks to climb past the ambient glyph onto the panel, which is the rung with
        // corrections that can be out of reach.
        for _ in 0..<2 {
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.decoy))
            NudgeHostFixture.settle()
            fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }

        #expect(!fixture.panel.isVisible, "the unanswerable panel was left on the screen")
        #expect(
            fixture.host.slot.isOpen,
            """
            a rung the loop hid for being unanswerable is still holding the slot: \
            \(fixture.host.slot.holder)
            """
        )
        #expect(
            fixture.host.openRungPanelActions.isEmpty,
            "a hidden panel is still offering \(fixture.host.openRungPanelActions)"
        )
    }

    /// **And the question U-1 requires is still asked afterwards.**
    ///
    /// The reading above is the mechanism; this is the consequence a person meets. The symptom of
    /// the defect is the app saying nothing at all, which is the hardest kind of thing to notice.
    @Test("a rung hidden for being unanswerable does not silence the question that follows it")
    func anUnreadableRungDoesNotSilenceTheNextQuestion() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        fixture.panel.displays = { Self.tooSmallForAPanel }

        for _ in 0..<2 {
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.decoy))
            NudgeHostFixture.settle()
            fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }
        #expect(!fixture.panel.isVisible)

        // The display comes back, so a question has somewhere legible to go.
        fixture.panel.displays = { NudgePanelController.currentScreens() }
        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.other))
        NudgeHostFixture.settle()

        #expect(
            fixture.panel.isVisible && fixture.panel.showing == .question,
            """
            no question could be asked after one rung that reached nobody: \
            \(String(describing: fixture.host.lastDecision))
            """
        )
    }

    /// **The ambient glyph is not an interruption in flight** (R-84a, U-1).
    ///
    /// The slot exists because *"two panels on screen at once is the behaviour that makes people
    /// uninstall"*. A status-item glyph and a question panel are not two panels: the glyph carries
    /// no sentence and offers nothing to press, which is already the rule the surface type states
    /// as `holdsTheInterruptionSlot`.
    ///
    /// Measured against the unfixed tree: `slot = accusation(ambient)` after a single `unrelated`
    /// judgement, and every `uncertain` judgement afterwards is
    /// `silent(interruptionInFlight)` — for the life of the session, because nothing can ever take
    /// an ambient rung down.
    @Test("an accusation on the glyph does not silence the question affordance for the session")
    func theGlyphDoesNotHoldTheSlot() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        // **The item is in the menu bar, exactly as the shipping app has it** (focus-1b5).
        // The ambient rung *is* the status item: with no item installed there is nothing for it
        // to change, `MenuBarController.redraw(force:)` refuses to write to an item nobody can
        // see (F-163), and the loop correctly charges nothing. A fixture without one drives an
        // app whose menu bar is not there, which is not the state this test is about.
        try fixture.wireMenuBarToTheLoop()

        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.decoy))
        NudgeHostFixture.settle()

        #expect(fixture.host.deliveredCount == 1, "the glyph never lit")
        #expect(fixture.host.currentRung == .ambient, "the ladder is not on its entry rung")
        #expect(
            fixture.host.slot.isOpen,
            "the menu-bar glyph is holding the one interruption slot: \(fixture.host.slot.holder)"
        )

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.other))
        NudgeHostFixture.settle()

        #expect(
            fixture.panel.isVisible && fixture.panel.showing == .question,
            """
            the glyph silenced the question U-1 requires: \
            \(String(describing: fixture.host.lastDecision))
            """
        )
    }

    /// **A rung on the panel does still hold it.**
    ///
    /// The half of R-84a that must survive the repair of the other half: a question raised over an
    /// accusation panel is exactly what the one slot exists to prevent. Without this, "release the
    /// slot" could be satisfied by releasing it always.
    @Test("a rung on the panel holds the slot, and the question behind it is withheld")
    func thePanelRungStillHoldsTheSlot() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        // Two ticks to climb past the ambient glyph onto the panel.
        for _ in 0..<2 {
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.decoy))
            NudgeHostFixture.settle()
            fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }

        #expect(fixture.host.currentRung == .panel, "the ladder never reached the panel")
        #expect(fixture.panel.isVisible && fixture.panel.showing == .accusation)
        #expect(
            fixture.host.slot.openAccusation != nil,
            "an accusation on the panel released the one interruption slot"
        )

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.other))
        NudgeHostFixture.settle()

        #expect(
            fixture.panel.showing == .accusation,
            "a question was raised over an accusation panel"
        )
    }

    // MARK: - The same rule, on the question's side of the slot

    /// **A badge question waiting behind a click does not hold the slot** (U-2's own defect).
    ///
    /// The repair above was applied to the rung and not to the question: `slot` asked
    /// `openQuestion != nil`, which is the identity `focus-k42` condemned, spelled on the other
    /// branch. It was latent for as long as an accusation could displace a question — preemption
    /// was the release valve. Deleting preemption (U-2) turned it into the loudest failure in the
    /// epic, because `offering(_ rung:)` now withholds against an open query.
    ///
    /// The route is the shipping one, not a contrivance: reduced interruption is a checkbox in the
    /// Intervention pane, and `silentVisual` and an active microphone reach the same branch. The
    /// popover opens **only** when a person clicks the status item, and until then the loop's own
    /// doctrine is that *"the badge is an invitation, not a delivery — nothing is counted and
    /// nothing is written"*. Nothing is counted, and it used to hold the one interruption slot.
    @Test("a badge question nobody has opened does not hold the interruption slot")
    func aBadgeQuestionDoesNotHoldTheSlot() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        fixture.host.choose(reducedInterruption: true)

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.other))
        NudgeHostFixture.settle()

        try #require(fixture.host.pendingPopoverQuery != nil, "the question did not reach the badge")
        #expect(!fixture.menuBar.isPopoverShown, "the popover opened without anybody clicking")
        #expect(
            fixture.host.deliveredCount == 0,
            "a question sitting behind a click was counted as delivered"
        )
        #expect(
            fixture.host.slot.isOpen,
            """
            a question nobody has been shown is holding the one interruption slot: \
            \(fixture.host.slot.holder)
            """
        )
    }

    /// **…and the consequence a person meets: the app still speaks about the drift.**
    ///
    /// The mechanism above, measured as behaviour. On the unfixed tree this is sustained drift
    /// into a decoy application, for as long as you like, answered every single time with
    /// `silent(interruptionInFlight)` — because a question nobody was ever shown is waiting.
    /// U-2 says an accusation waits for a question; it does not say an accusation waits for a
    /// question that reached nobody.
    @Test("a badge question nobody has opened does not silence the accusation behind it")
    func aBadgeQuestionDoesNotSilenceTheAccusation() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try fixture.wireMenuBarToTheLoop()
        fixture.host.choose(reducedInterruption: true)

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.other))
        NudgeHostFixture.settle()
        try #require(fixture.host.pendingPopoverQuery != nil)

        // Sustained, unambiguous drift into a different application, over the day.
        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.decoy))
        NudgeHostFixture.settle()

        #expect(
            fixture.host.currentRung == .ambient,
            """
            eight minutes of sustained drift and the ladder never left the ground, because a \
            question nobody saw was holding the slot: \
            \(String(describing: fixture.host.lastDecision))
            """
        )
        // **It landed, and it was charged nothing** (focus-nrl). The rung reached the glyph —
        // which is what this test is about, and what the slot must not have prevented — and the
        // status item went on drawing the badge's `waiting` mark, because
        // `MenuBarPresentation.attention` is the *maximum* of the rung's mark and the badge's.
        // The stronger mark subsuming the weaker is right about what to draw and wrong about what
        // to charge, and this is the line that says so: nothing is spent for a rung the item
        // never mentioned, and the rung stays open to be charged the moment the mark falls to it.
        #expect(
            fixture.host.landedRungSurface == .menuBar,
            "the ambient rung never reached the glyph while an unopened question held the slot"
        )
        #expect(
            fixture.host.deliveredCount == 0,
            "a rung the menu bar never mentioned was charged (focus-nrl)"
        )
        // And the question is still there to be answered — waiting, not spent.
        #expect(fixture.host.pendingPopoverQuery != nil, "the accusation ate the pending question")
    }

    /// **A question on the panel does still hold it, and the rung that speaks waits** (U-2).
    ///
    /// The half of the cut that must survive the repair of the other half — the single most
    /// important line of the scope cut, asserted as behaviour. Without this, "release the slot"
    /// could be satisfied by releasing it always, and preemption would be back by omission.
    ///
    /// **"The accusation" is the rung that speaks, and this drove the glyph** (focus-0y6). Gate 9
    /// is an occupancy rule and `NudgeSurface.menuBar.holdsTheInterruptionSlot` is `false`, so
    /// withholding the ambient rung was refusing a thing on the grounds of a property it does not
    /// have — the status item went blank for as long as the question sat on the screen, which is
    /// the same failure the suite above this one repairs from the other side. The drive now climbs
    /// one rung further: the glyph lands under the question, the **panel** rung is withheld, and
    /// it arrives once the question has been answered. U-2 is not loosened; what changed is which
    /// rung it was ever about.
    @Test("a question on the panel holds the slot, and the rung that speaks waits behind it")
    func aPanelQuestionStillHoldsTheSlot() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.other))
        NudgeHostFixture.settle()

        try #require(fixture.panel.isVisible && fixture.panel.showing == .question)
        #expect(
            fixture.host.slot.openQuery != nil,
            "a question on the panel released the one interruption slot"
        )

        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.decoy))
        NudgeHostFixture.settle()

        #expect(
            fixture.panel.showing == .question,
            "an accusation displaced the question U-1 licensed the interruption for"
        )
        // **The glyph is not withheld** (focus-0y6). It occupies nothing a second nudge could
        // want, so an occupancy rule has nothing to say about it — and the question is still on
        // the screen beside it, which is the point.
        #expect(
            fixture.host.currentRung == .ambient,
            """
            an open question took the status item with it: \
            \(String(describing: fixture.host.lastDecision))
            """
        )
        #expect(fixture.host.slot.openQuery != nil, "the glyph took the slot it cannot hold")

        // Past the escalation dwell — and past the gap between two sentences as well, so the
        // rung below is refused by gate 9 and by nothing else — the PANEL rung is due. That is
        // the one U-2 makes wait.
        fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.decoy))
        NudgeHostFixture.settle()

        #expect(
            fixture.panel.showing == .question,
            "the panel rung displaced the question U-1 licensed the interruption for"
        )
        // **Withheld is not spent** (U-2). The ladder never left the glyph: no delivery was
        // recorded for the rung above it, so the escalation clock never restarted and the same
        // rung is still there.
        #expect(
            fixture.host.currentRung == .ambient,
            "the withheld rung was consumed rather than kept for the next judgement"
        )
        #expect(
            fixture.host.lastDecision?.silence?.reason == .interruptionInFlight,
            """
            the panel rung was refused for some other reason, so this drives gate 9 at neither \
            rung — \(String(describing: fixture.host.lastDecision))
            """
        )

        // The person answers — Escape on the question panel is "Not now", which is an answer —
        // and the accusation that waited is now free to arrive.
        fixture.panel.onDismiss?()
        NudgeHostFixture.settle()
        try #require(fixture.host.slot.isOpen, "the answered question did not give the slot back")

        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.decoy))
        NudgeHostFixture.settle()

        #expect(
            fixture.host.currentRung == .panel,
            """
            the accusation was lost rather than delayed: \
            \(String(describing: fixture.host.lastDecision))
            """
        )
        #expect(
            fixture.panel.isVisible && fixture.panel.showing == .accusation,
            "the rung that waited arrived and carried no sentence"
        )
    }

    /// **Escape on an accusation panel dismisses the accusation, not the invisible question.**
    ///
    /// A state that could not exist before the repair above and can now: an accusation on the
    /// panel while a badge question waits behind a click. `panel.onDismiss` asked
    /// `openQuestion != nil`, which was a safe spelling only while the two were the same state —
    /// so Escape would have answered *"Not now"* to a question that is not on the screen, written
    /// its receipt, settled the subject under gate 11 so it could never be asked again, and left
    /// the accusation the person meant to dismiss still up.
    ///
    /// **Reaching it needs the settings pane**, and that is the point: every route that sends a
    /// question to the badge also demotes the panel rung — reduced interruption, an active
    /// microphone and the `silentVisual` deck all send both to the badge (focus-vxo) — so the two
    /// can only meet if the preference changes between the ask and the accusation. Unchecking the
    /// Intervention pane's box while a badge question waits is an ordinary thing to do.
    @Test("escape on an accusation panel does not answer a question waiting in the badge")
    func escapeDismissesThePanelNotThePendingBadgeQuestion() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        // Reduced interruption routes the question to the badge…
        fixture.host.choose(reducedInterruption: true)

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.other))
        NudgeHostFixture.settle()
        try #require(fixture.host.pendingPopoverQuery != nil)

        // …and then the person turns it off again, with the question still waiting behind a click.
        fixture.host.choose(reducedInterruption: false)

        for _ in 0..<2 {
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.decoy))
            NudgeHostFixture.settle()
            fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }
        try #require(
            fixture.panel.isVisible && fixture.panel.showing == .accusation,
            "the accusation never reached the panel: \(String(describing: fixture.host.lastDecision))"
        )

        fixture.panel.onDismiss?()
        NudgeHostFixture.settle()

        #expect(
            fixture.host.pendingPopoverQuery != nil,
            "Escape on an accusation panel answered a question that was not on the screen"
        )
        #expect(
            try fixture.receipts().isEmpty,
            "a receipt was written for a question nobody was ever shown"
        )
        #expect(
            !(try fixture.ledger.isSettled(
                priorityID: fixture.priorityID,
                subjectKind: .app,
                subject: Self.other
            )),
            "gate 11 would now suppress a question that was never asked"
        )
    }

    /// **A question does not take the badge's accusation down with it** (focus-2rg, U-2).
    ///
    /// The mirror of `aBadgeQuestionDoesNotSilenceTheAccusation` above, and it was the direction
    /// nothing guarded. `ask(…)` called `forgetOpenRung()` **unconditionally**: the rung holds no
    /// slot when it is on the badge, so `slot.offering(warrant)` admitted, and the open accusation
    /// was dropped with nothing recorded — no deferral, no `ladder.undeliver`, no withdrawal.
    ///
    /// Ask what that line could still reach and the answer is only ever the two rungs that hold no
    /// slot: a rung on the **panel** withholds the question at the line above. So it existed to
    /// take down exactly the surfaces it must not.
    ///
    /// Driven on the shipping loop before the repair: ladder at `.panel`, badge carrying five
    /// answers about the decoy, then one ordinary uncertain judgement about another application —
    /// and `pendingPopoverAccusation` went to `nil` while the delivered row went on charging the
    /// budget. The person was asked about one thing and silently lost the nudge about another.
    ///
    /// The two do not collide: `MenuBarPopoverView` draws both as two rows of one popover, which
    /// is the state the reverse order has produced since focus-k42.
    @Test("a question does not wipe the accusation waiting in the badge")
    func aQuestionDoesNotWipeTheBadgeAccusation() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        fixture.host.choose(reducedInterruption: true)

        for _ in 0..<2 {
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.decoy))
            NudgeHostFixture.settle()
            fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }
        try #require(
            fixture.host.pendingPopoverAccusation?.subject?.identifier == Self.decoy,
            "the rung never reached the badge: \(String(describing: fixture.host.lastDecision))"
        )
        let rungsBefore = try fixture.interventions().filter { $0.kind == .accusation }.count

        // One ordinary uncertain judgement about a different application.
        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.other))
        NudgeHostFixture.settle()

        try #require(
            fixture.host.pendingPopoverQuery?.subject.identifier == Self.other,
            "the question was not raised at all, so this proves nothing about the accusation"
        )
        #expect(
            fixture.host.pendingPopoverAccusation?.subject?.identifier == Self.decoy,
            "the question wiped the accusation waiting in the badge, and recorded nothing"
        )
        #expect(fixture.host.currentRung == .panel, "the ladder lost the rung it was holding")
        // Nothing was written about the accusation on the way past: no deferral, and no second
        // row. Losing it silently was the defect; recording a loss that did not happen would be
        // the over-correction.
        #expect(fixture.host.deferredCount == 0)
        #expect(
            try fixture.interventions().filter { $0.kind == .accusation }.count == rungsBefore,
            "a row was written about an accusation that is still on the badge"
        )
    }

    /// **And it is still answerable afterwards** — the consequence a person meets.
    ///
    /// The reading above is the mechanism. This is the badge being pressed after the question
    /// arrived beside it, which is the whole point of not dropping it: a correction that reaches
    /// `resolve(…)` and writes the rule the person meant.
    @Test("the accusation the question did not wipe can still be answered")
    func theSurvivingBadgeAccusationStillAnswers() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        fixture.host.choose(reducedInterruption: true)
        var written: [CorrectionOutcome] = []
        fixture.host.onCorrection = { outcome, _ in written.append(outcome) }

        for _ in 0..<2 {
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.decoy))
            NudgeHostFixture.settle()
            fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }
        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.other))
        NudgeHostFixture.settle()
        try #require(fixture.host.pendingPopoverQuery != nil)

        fixture.host.resolve(.thisIsRelevant, snoozeDuration: nil)
        NudgeHostFixture.settle()

        let rule = try #require(
            written.compactMap(\.ruleAwaitingPersistence).first,
            "the correction on the surviving badge accusation wrote nothing"
        )
        #expect(rule.subject == Self.decoy, "the correction landed on the wrong application")
        // And the question is untouched by a correction aimed at the accusation.
        #expect(
            fixture.host.pendingPopoverQuery?.subject.identifier == Self.other,
            "answering the accusation spent the question beside it"
        )
    }

    /// **One question at a time is a fact about the loop, not about the slot.**
    ///
    /// The guard that had to be added when ownership stopped answering identity: with the badge
    /// question no longer holding the slot, `slot.offering(warrant)` says *admitted* while one
    /// waits. Raising the second would strand the badge the menu bar is already drawing and leave
    /// `popoverPresented()` to deliver a question about a different subject.
    @Test("a second question is not raised over one still waiting in the badge")
    func aPendingBadgeQuestionIsNotSilentlyReplaced() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        fixture.host.choose(reducedInterruption: true)

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.other))
        NudgeHostFixture.settle()
        try #require(fixture.host.pendingPopoverQuery?.subject.identifier == Self.other)

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.decoy))
        NudgeHostFixture.settle()

        #expect(
            fixture.host.pendingPopoverQuery?.subject.identifier == Self.other,
            "the question waiting behind the click was replaced by a second one"
        )
    }
}
