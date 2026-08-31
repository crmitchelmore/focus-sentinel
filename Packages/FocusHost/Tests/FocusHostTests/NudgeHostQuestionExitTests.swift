import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **The app must never ignore an answer it asked for** (focus-v0u, U-1, U-2).
///
/// ## The defect these used to drive, and why three of them are gone
///
/// `accuse(…)` cleared `openWarrant` on one line and then touched the panel on the `.panel`
/// branch **alone**. On `.menuBar`, `.popoverBadge` and `.notification` the question's panel was
/// left on screen, fully drawn, fully clickable and fully reachable, while the host had forgotten
/// it existed. `answer(_:)` then hit `guard let warrant = openWarrant else { return }` and dropped
/// the click, and `defer { closeSurfaces() }` tidied the evidence away.
///
/// Measured on the unfixed loop: before `visible=true reachable=true`; an ordinary glyph
/// preemption; after `visible=true reachable=true`, *"every offered action is reachable"*. The
/// person clicks **"Yes, add it"**. Rules written: **0**. Receipts: `["expired"]`. And the
/// question is asked again.
///
/// Every one of those readings was taken **through a preemption**, and U-2 deleted preemption. A
/// question can no longer be displaced by anything, so the orphaned-surface class has no way in
/// from that direction at all. What is left here is the half that still has to hold: the four
/// remaining exits, walked exhaustively, and the new rule in place of the old one — an accusation
/// raised over an open question **waits**, and the question it did not displace is untouched.
@MainActor
struct NudgeHostQuestionExitTests {
    static let subject = NudgeHostFixture.decoy

    /// **The accusation waits, and the question is exactly as it was** (U-2).
    ///
    /// This replaces three tests that each asserted a different consequence of displacement. The
    /// ladder's entry rung is the menu-bar glyph, so the drift below is the commonest accusation
    /// there is — and on the unfixed loop it took the question off the screen.
    ///
    /// **The glyph is not what waits** (focus-0y6). The drive stopped at the ambient rung and read
    /// `silent(interruptionInFlight)` as U-2 holding, when gate 9 is an occupancy rule and
    /// `NudgeSurface.menuBar.holdsTheInterruptionSlot` is `false` — so what it was really reading
    /// is the status item going blank for as long as a question sat on the screen. The glyph now
    /// lands beside the question and the drive climbs one rung further, to the **panel**, which is
    /// the rung U-2's ruling was always about. Every assertion about the question being untouched
    /// is made twice: once under the rung that landed, once under the rung that waited.
    @Test(
        "an accusation raised over an open question leaves the question alone",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func anAccusationDoesNotDisplaceAQuestion() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        #expect(fixture.panel.isVisible, "no question was on screen to displace")
        #expect(fixture.panel.showing == .question)

        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
        NudgeHostFixture.settle()

        // **The glyph landed** (focus-0y6). It occupies nothing a second nudge could want, so an
        // occupancy rule has nothing to say about it — and the question is still on the screen
        // beside it, which is the whole point.
        #expect(
            fixture.host.currentRung == .ambient,
            """
            an open question took the status item with it: \
            \(String(describing: fixture.host.lastDecision))
            """
        )
        // The question is still on the screen, still owned, still answerable.
        #expect(fixture.panel.isVisible && fixture.panel.showing == .question)
        #expect(fixture.host.slot.openQuery != nil, "the question lost the slot it was holding")
        #expect(fixture.host.orphanedNudgeSurfaces.isEmpty)

        // **And the rung that SPEAKS waits** (U-2). Past the escalation dwell and past the gap the
        // app keeps between two sentences, so the withholding below is gate 9's and nothing
        // else's, the panel rung is due — and it is the one that would have taken the question off
        // the screen.
        fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
        NudgeHostFixture.settle()

        #expect(
            fixture.host.lastDecision?.silence?.reason == .interruptionInFlight,
            """
            the rung that speaks was raised over an open question: \
            \(String(describing: fixture.host.lastDecision))
            """
        )
        // The same three readings again, under the rung that waited rather than the one that
        // landed: a withheld rung must leave the question exactly as untouched as a silent one.
        #expect(fixture.panel.isVisible && fixture.panel.showing == .question)
        #expect(fixture.host.slot.openQuery != nil, "the question lost the slot it was holding")
        #expect(fixture.host.orphanedNudgeSurfaces.isEmpty)

        // Nothing was written about it, and it certainly was not settled.
        let settling = try fixture.ledger.settledReceipt(
            priorityID: fixture.priorityID, subjectKind: .app, subject: Self.subject
        )
        #expect(settling == nil, "an accusation that never appeared settled the question")

        // And the person's answer still reaches the loop.
        fixture.host.answer(.yesAddIt)
        NudgeHostFixture.settle()
        #expect(fixture.host.orphanedNudgeSurfaces.isEmpty)
        #expect(
            try fixture.ledger.settledReceipt(
                priorityID: fixture.priorityID, subjectKind: .app, subject: Self.subject
            ) != nil,
            "the person answered and the loop dropped the click"
        )
    }

    /// **The class, not the instance** (focus-v0u).
    ///
    /// Five rounds each found a different exit individually wrong. `QuestionExit` enumerates every
    /// one of them, `endOpenQuestion(_:)` is the only door, and this walks `allCases` and drives
    /// each through the real loop. The `switch` is exhaustive by construction: a fifth exit added
    /// without a driver here is a compile error rather than a sixth round.
    @Test(
        "every exit from an open question takes it off every surface it was on",
        .enabled(if: LocalizationLane.catalogsAreCompiled),
        arguments: QuestionExit.allCases
    )
    func everyExitTakesTheQuestionDown(exit: QuestionExit) throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        // Every case except `neverDelivered` needs a question actually on the screen; that one is
        // about an ask that never got there, so it builds its own situation.
        if exit != .neverDelivered {
            fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
            NudgeHostFixture.settle()
            #expect(fixture.panel.isVisible, "no question was on screen for \(exit.rawValue)")
        }

        switch exit {
        case .answered:
            fixture.host.answer(.yesAddIt)

        case .worldMovedOn:
            fixture.host.sessionEnded()

        case .surfaceWentOutOfReach:
            // A display the question cannot fit on, and the notification AppKit really posts —
            // the wiring under test rather than a direct call to the handler.
            fixture.panel.displays = { NudgeHostDisplayChangeTests.displayTooSmall(for: 4_000) }
            NudgeHostDisplayChangeTests.theDisplayConfigurationChanges()

        case .screenReclaimed:
            // F-81's one command. It writes nothing — the person asked for their screen back, not
            // to tell the app anything — and the question must still come off every surface.
            fixture.host.hideOverlays()

        case .neverDelivered:
            // An intent nobody would type makes a panel whose answers really are past the edge of
            // the display, which is the situation `ask(…)` refuses to deliver into.
            let long = try NudgeHostFixture(intent: String(repeating: "an unanswerable ask ", count: 60))
            defer { long.tearDown() }
            long.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
            NudgeHostFixture.settle()
            #expect(
                long.host.orphanedNudgeSurfaces.isEmpty,
                """
                \(exit.rawValue) left a question on \
                \(long.host.orphanedNudgeSurfaces.map(\.rawValue))
                """
            )
            return
        }

        NudgeHostFixture.settle()
        #expect(
            fixture.host.orphanedNudgeSurfaces.isEmpty,
            """
            \(exit.rawValue) left a question on screen that the host has forgotten: \
            \(fixture.host.orphanedNudgeSurfaces.map(\.rawValue))
            """
        )
    }
}
