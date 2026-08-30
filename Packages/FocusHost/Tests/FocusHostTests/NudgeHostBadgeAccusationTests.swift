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
/// is set, and `AppearanceObserver` forces that flag on whenever macOS **Reduce Motion** is on
/// — also under the `silentVisual` deck, and while a microphone is running. The popover drew the
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

    /// Drive sustained drift under reduced interruption until the ladder reaches the panel rung.
    ///
    /// Two ticks, exactly as `NudgeHostLadderTests.theLoopClimbsTheWholeLadder` drives it: the
    /// ladder enters at `.ambient` and escalates once the clock has passed both `escalationDwell`
    /// and the longer `mandateCooldown`.
    static func climbToTheBadge(_ fixture: NudgeHostFixture) {
        fixture.host.choose(reducedInterruption: true)
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
    @Test("a top rung routed to the badge arrives with every answer the panel would offer")
    func theBadgeRungCarriesItsAnswers() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        Self.climbToTheBadge(fixture)

        #expect(fixture.host.currentRung == .panel, "the ladder did not reach the top rung")
        guard case .accuse(_, .surface(.popoverBadge)) = fixture.host.lastDecision else {
            Issue.record(
                "the rung was not routed to the badge: \(String(describing: fixture.host.lastDecision))"
            )
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
        #expect(presentation.subject == Self.subject)
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
    @Test("a correction pressed on the badge is written, and takes the rung down with it")
    func aCorrectionOnTheBadgeIsWritten() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        var written: [CorrectionOutcome] = []
        fixture.host.onCorrection = { outcome, _ in written.append(outcome) }

        Self.climbToTheBadge(fixture)
        #expect(fixture.host.pendingPopoverAccusation != nil)

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
