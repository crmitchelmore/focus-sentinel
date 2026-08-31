import AppKit
import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **A surface may not go on drawing a nudge this host is not holding** (focus-v0u, focus-xix,
/// focus-my0).
///
/// ## The half of the invariant that was written down and not read
///
/// `setOpenRung(_:)` has carried the rule since focus-uru: *"replacing a rung is as much a change
/// as forgetting one"*, because an open popover still offering **this is relevant** for a rung the
/// host has let go of is a click that `resolve(_:snoozeDuration:)` applies to whatever rung it is
/// holding **now** — a correction about the wrong application. The redraw it added covers the
/// badge in both directions.
///
/// The panel got no such clause. Drift into one application until the ladder reaches its panel
/// rung, then drift into a **second** application: `LadderMachine.arrive(_:)` resets for a
/// different subject, the slot admits an accusation against an accusation (that is the ladder's
/// own escalation), and the ambient rung for the second application replaces the panel rung for
/// the first. Nothing takes the panel down. It stays on screen, fully drawn and fully clickable,
/// naming an application the host is no longer holding a rung about, with Pause and Change
/// priority live.
///
/// ## And the reading that exists to catch exactly this could not see it
///
/// `orphanedNudgeSurfaces` asked `openRung == nil` — *"is this host holding nothing?"* — when
/// the question it is named for is *"is this surface drawing a nudge this host is not holding?"*.
/// Those are the same question only when the loop holds at most one nudge at a time across all
/// surfaces, which is exactly what the badge and the glyph exist not to be. So the one state
/// the reading was built for was the one state it answered `[]` for, in every suite that asserts it
/// and in the self-check that publishes it.
@Suite("A surface draws only the nudge this host is holding", .serialized)
@MainActor
struct NudgeHostOrphanedPanelTests {
    static let drifted = "com.example.Browser"
    static let thenDrifted = "com.example.Reader"

    /// Sustained drift into one application until the ladder puts a rung on a real panel.
    static func aRungOnThePanel(in fixture: NudgeHostFixture) throws {
        fixture.workspace.runningNames[Self.drifted] = "Browser"
        fixture.workspace.runningNames[Self.thenDrifted] = "Reader"

        for _ in 0..<2 {
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.drifted))
            NudgeHostFixture.settle()
            fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }
        try #require(
            fixture.host.landedRungSurface == .panel && fixture.panel.isVisible,
            "the rung did not reach a panel, so this drives nothing"
        )
        try #require(
            fixture.panel.showing == .accusation,
            "the panel is not drawing an accusation, so this drives nothing"
        )
    }

    @Test("drifting into a second application does not leave the first one's panel on screen")
    func aPanelDoesNotOutliveTheRungItWasDrawing() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try fixture.wireMenuBarToTheLoop()
        try Self.aRungOnThePanel(in: fixture)

        // The person gives up on that application and drifts into a different one. A different
        // subject resets the ladder, so the rung this raises is the ambient glyph — and the slot
        // admits an accusation against an accusation, which is the ladder's own escalation rule.
        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.thenDrifted))
        NudgeHostFixture.settle()

        try #require(
            fixture.host.landedRungSurface == .menuBar,
            """
            the second application's rung did not replace the first's on the glyph \
            (\(fixture.host.landedRungSurface?.rawValue ?? "nowhere")), so this drives nothing
            """
        )
        #expect(
            !fixture.panel.isVisible,
            """
            a panel is still on screen accusing \(Self.drifted) with Pause and Change priority \
            live, while this host is holding a rung about \(Self.thenDrifted) — a click on it \
            would be applied to the wrong application
            """
        )
        #expect(
            fixture.host.orphanedNudgeSurfaces.isEmpty,
            """
            a nudge is drawn on a surface this host is not holding it on: \
            \(fixture.host.orphanedNudgeSurfaces.map(\.rawValue))
            """
        )
    }

    /// **The reading itself, driven from the state it was blind to.**
    ///
    /// Asserted separately from the repair above, because *"the panel is taken down"* and *"the
    /// reading can see a panel that was not"* are two claims, and this epic's whole method is that
    /// a repair which leaves its own reading unfalsifiable is the next round's bead. The panel is
    /// put back up by hand, behind the host's back, into exactly the state the drive above used to
    /// leave it in — and the reading has to name it.
    @Test("the reading names a panel drawing an accusation this host is not holding")
    func theReadingSeesAPanelTheHostIsNotHolding() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try fixture.wireMenuBarToTheLoop()
        try Self.aRungOnThePanel(in: fixture)

        let stranded = try #require(
            fixture.host.openRungPresentation,
            "the panel rung had no presentation, so this drives nothing"
        )

        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.thenDrifted))
        NudgeHostFixture.settle()
        try #require(fixture.host.landedRungSurface == .menuBar)

        // The panel is ordered back in front of the person still drawing the accusation it was
        // drawing — a window server that never got the order out, a second display, a hosting
        // controller rebuilt from the presentation the panel was last handed. The host is holding
        // a rung on the glyph, so a click here is a correction about the wrong application, and
        // that is precisely what this reading is for.
        fixture.panel.update(AccusationPanelView(presentation: stranded) { _, _ in })
        fixture.panel.show(presentationIsClear: true, announcement: nil)
        NudgeHostFixture.settle()
        try #require(
            fixture.panel.isVisible && fixture.panel.showing == .accusation,
            "the panel did not come back, so this drives nothing"
        )

        #expect(
            fixture.host.orphanedNudgeSurfaces == [.panel],
            """
            the panel is drawing an accusation this host is not holding and the reading built to \
            catch exactly that says \(fixture.host.orphanedNudgeSurfaces.map(\.rawValue))
            """
        )
    }
}
