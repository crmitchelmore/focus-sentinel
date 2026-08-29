import AppKit
import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **The nudge surfaces are drawn in the appearance the person is actually running** (focus-pq8).
///
/// ## The defect
///
/// `NudgeHost` raised both of its surfaces with the **default** traits argument:
///
/// ```swift
/// panel.update(QueryPanelView(presentation: presentation) { … })   // traits: .systemDefault
/// menuBar.update(menuBarPresentation())                            // traits: nil
/// ```
///
/// `AppearanceTraits.systemDefault` is light with every accessibility setting off. So the two
/// surfaces a person only ever meets *because the app interrupted them* were pinned to
/// `light/-/-/-/-` for the life of the process, whatever the Mac was set to — and
/// `AppComposition.appearanceChanged(_:)`, the wire that exists to tell the shell the appearance
/// moved, reached the quick-capture panel and nothing else.
///
/// Two consequences a person meets today. In dark mode the panel's text is drawn for a light
/// background on a dark one. And `differentiateWithoutColor` was never passed into
/// `MenuBarPresentation` at all, so it took its default of `false`: for somebody who has turned
/// Differentiate Without Colour on, the status item reported the app's state in hue alone, which
/// is the one thing that setting exists to prevent (F-146).
@Suite("The nudge surfaces follow the Mac's appearance", .serialized)
@MainActor
struct NudgeAppearanceTests {
    static let dark = AppearanceTraits(
        colorScheme: .dark,
        increasedContrast: true,
        reduceTransparency: true,
        reduceMotion: true,
        differentiateWithoutColor: true
    )

    /// **A question panel is raised in the live appearance, not in `systemDefault`.**
    @Test("the question panel is drawn in the traits the host is given")
    func theQuestionPanelFollowsTheTraits() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        fixture.host.appearanceTraits = { Self.dark }

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: NudgeHostFixture.decoy))
        NudgeHostFixture.settle()

        #expect(fixture.panel.showing == .question, "no question was raised to check")
        #expect(
            fixture.panel.appliedTraits == Self.dark,
            """
            the question panel was drawn in \(fixture.panel.appliedTraits.renderedDescription) \
            while the Mac is \(Self.dark.renderedDescription)
            """
        )
    }

    /// **And so is an accusation panel.** Both surfaces, because they are two call sites and the
    /// defect was that each carried its own default.
    @Test("the accusation panel is drawn in the traits the host is given")
    func theAccusationPanelFollowsTheTraits() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        fixture.host.appearanceTraits = { Self.dark }

        for _ in 0..<2 {
            fixture.host.consider(
                NudgeHostFixture.unrelatedJudgement(subject: NudgeHostFixture.decoy)
            )
            NudgeHostFixture.settle()
            fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }

        #expect(fixture.panel.showing == .accusation, "no accusation reached the panel")
        #expect(
            fixture.panel.appliedTraits == Self.dark,
            """
            the accusation panel was drawn in \(fixture.panel.appliedTraits.renderedDescription) \
            while the Mac is \(Self.dark.renderedDescription)
            """
        )
    }

    /// **The appearance can change while a nudge is on the screen.**
    ///
    /// The panel is sticky — `hidesOnDeactivate` is `false` (R-89) — so it really can still be up
    /// when the Mac switches to dark at sunset. Raising it correctly is not enough on its own.
    @Test("a panel already on screen is redrawn when the appearance changes")
    func aLivePanelFollowsAChange() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: NudgeHostFixture.decoy))
        NudgeHostFixture.settle()
        #expect(fixture.panel.showing == .question)
        #expect(fixture.panel.appliedTraits.colorScheme == .light)

        fixture.panel.update(traits: Self.dark)
        NudgeHostFixture.settle()

        #expect(
            fixture.panel.appliedTraits == Self.dark,
            "a panel on screen kept the appearance it was raised in"
        )
    }
}
