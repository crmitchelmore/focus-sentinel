import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **The app must never ignore an answer it asked for** (focus-v0u, U-1).
///
/// ## The defect these drive
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
/// The ladder's entry rung is the menu-bar glyph, so this is not an edge: it is what the most
/// common preemption of all did. Every earlier finding in this epic was the app silencing itself;
/// this is the app ignoring the person and then asking them the same thing again, which is U-1's
/// repeat-asking clause broken from the other side.
@MainActor
struct NudgeHostQuestionExitTests {
    static let subject = NudgeHostFixture.decoy

    /// **The measurement, as an assertion.**
    ///
    /// Reverting `endOpenQuestion(.preempted, replacedOn: route.surface)` in `accuse(…)` to the
    /// `openWarrant = nil` it replaced turns this red on the first `#expect`: the panel is still
    /// visible, still carrying the question, and `orphanedQuestionSurfaces` names it.
    @Test(
        "a question displaced onto the glyph does not stay clickable on the panel",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func aDisplacedQuestionLeavesTheScreen() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        #expect(fixture.panel.isVisible, "no question was on screen to displace")
        #expect(fixture.panel.showing == .question)

        // The ordinary preemption: the ladder's entry rung is the menu-bar glyph.
        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        guard case .accuse(_, .surface(.menuBar), _) = fixture.host.lastDecision else {
            Issue.record(
                "this test is about the glyph: \(String(describing: fixture.host.lastDecision))"
            )
            return
        }

        #expect(
            fixture.host.orphanedQuestionSurfaces.isEmpty,
            """
            the question is still on screen and the host has forgotten it: \
            \(fixture.host.orphanedQuestionSurfaces.map(\.rawValue))
            """
        )
        #expect(
            fixture.panel.showing != .question,
            "the panel is still carrying a question nobody is listening for"
        )
    }

    /// **The click itself.** The reading above says the affordance is gone; this says what used
    /// to happen when it was not. On the unfixed loop the person's answer wrote nothing at all,
    /// and the only record of the whole episode was an `expired` receipt.
    @Test(
        "a person cannot press an answer the loop would silently drop",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func anAnswerIsNeverDropped() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        #expect(fixture.panel.isVisible)

        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
        NudgeHostFixture.settle()

        // Whatever is on screen now, it is not a question. A person who clicks what they can see
        // is answering the accusation, and the accusation's actions write.
        #expect(fixture.host.orphanedQuestionSurfaces.isEmpty)

        // …and the question is not settled, so the app will ask again properly rather than having
        // silently consumed the person's click (focus-7w3's clause, still holding).
        let settling = try fixture.ledger.settledReceipt(
            priorityID: fixture.priorityID, subjectKind: .app, subject: Self.subject
        )
        #expect(settling == nil, "an unseen preemption settled the question")
    }

    /// **The class, not the instance** (focus-v0u).
    ///
    /// Five rounds each found a different exit individually wrong. `QuestionExit` enumerates every
    /// one of them, `endOpenQuestion(_:replacedOn:)` is the only door, and this walks `allCases`
    /// and drives each through the real loop. The `switch` is exhaustive by construction: a sixth
    /// exit added without a driver here is a compile error rather than a sixth round.
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

        case .preempted:
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
            NudgeHostFixture.settle()

        case .worldMovedOn:
            fixture.host.sessionEnded()

        case .surfaceWentOutOfReach:
            // A display the question cannot fit on, and the notification AppKit really posts —
            // the wiring under test rather than a direct call to the handler.
            fixture.panel.displays = { NudgeHostDisplayChangeTests.displayTooSmall(for: 4_000) }
            NudgeHostDisplayChangeTests.theDisplayConfigurationChanges()

        case .neverDelivered:
            // An intent nobody would type makes a panel whose answers really are past the edge of
            // the display, which is the situation `ask(…)` refuses to deliver into.
            let long = try NudgeHostFixture(intent: String(repeating: "an unanswerable ask ", count: 60))
            defer { long.tearDown() }
            long.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
            NudgeHostFixture.settle()
            #expect(
                long.host.orphanedQuestionSurfaces.isEmpty,
                """
                \(exit.rawValue) left a question on \
                \(long.host.orphanedQuestionSurfaces.map(\.rawValue))
                """
            )
            return
        }

        NudgeHostFixture.settle()
        #expect(
            fixture.host.orphanedQuestionSurfaces.isEmpty,
            """
            \(exit.rawValue) left a question on screen that the host has forgotten: \
            \(fixture.host.orphanedQuestionSurfaces.map(\.rawValue))
            """
        )
    }

    /// The one exit that is **allowed** to leave the panel up, and only because something else is
    /// putting its own content on it in the same turn. Without this the fix would be "hide the
    /// panel always", which would flicker between two things a person is meant to read one after
    /// the other — and would break the one preemption R-84a actually describes.
    @Test(
        "an accusation routed to the panel keeps the panel, and it is carrying the accusation",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func aPanelAccusationTakesTheSurfaceOver() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        // Climb to the panel rung, exactly as `NudgeHostPreemptionTests` does.
        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        fixture.host.hideOverlays()

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        #expect(fixture.panel.showing == .question)

        fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        guard case .accuse(_, .surface(.panel), _) = fixture.host.lastDecision else {
            Issue.record(
                "the accusation did not reach the panel: \(String(describing: fixture.host.lastDecision))"
            )
            return
        }

        #expect(fixture.panel.isVisible, "the accusation was put on a panel that is not on screen")
        #expect(
            fixture.panel.showing == .accusation,
            "the panel kept the question after an accusation took it over"
        )
        #expect(fixture.host.orphanedQuestionSurfaces.isEmpty)
    }
}
