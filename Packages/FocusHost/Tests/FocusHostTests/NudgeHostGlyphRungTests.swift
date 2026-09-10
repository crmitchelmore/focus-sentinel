import AppKit
import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **The app does not charge for an interruption it never showed** (focus-mkk, focus-2xw, U-1).
///
/// ## The defect, as it was measured
///
/// `NudgeHost.accuse(…)` charges the day's budget the moment a rung lands on a surface whose
/// `NudgeSurface.reachesThePersonOnLanding` is `true`, and `.menuBar` answers `true` on the stated
/// ground that *"the glyph is redrawn on the next refresh"*. It was not. `currentStatus` never
/// read the ladder; `MenuBarController.redraw` drew the glyph, the title and the VoiceOver
/// announcement from `presentation.status` alone; `setOpenRung` asked for a redraw only when the
/// badge was involved; and `InterventionPolicy`'s mandate needs ninety seconds of sustained drift,
/// so the status had already been `.unrelated` throughout and the announcement could not fire
/// either.
///
/// Driven on the shipping loop with a real installed `NSStatusItem`, seven drifts seven hundred
/// seconds apart, the result was **six accusation rows marked `delivered` on `menuBar`, the whole
/// day's accusation cap spent, the query budget squeezed from four remaining to one, and writes to
/// the menu bar of `[1, 1, 1, 1, 1, 1, 1]`** — the single write being the one `install()` made
/// before the first rung existed. The Intervention pane then printed *"6 / 6"* to somebody who had
/// been shown a glyph they already had, and the panel rung, the only rung carrying a sentence and
/// a correction economy, could not be raised again that day.
///
/// ## Why this suite counts writes
///
/// The previous repair of this shape split `reachesThePersonOnLanding` out of
/// `holdsTheInterruptionSlot` and then blessed the glyph cell **by assertion** — a proof that read
/// the predicate back and therefore could not fail. So nothing here asks a surface what it
/// promises. It installs the real status item, drives the real loop, and reads
/// `MenuBarController.glyphWriteCount` and `announcementCount`, which are counts of assignments
/// that actually happened to a real `NSStatusBarButton`.
@Suite("The glyph rung reaches the menu bar", .serialized)
@MainActor
struct NudgeHostGlyphRungTests {
    static let subject = NudgeHostFixture.decoy

    /// A real item in the real menu bar, drawing the loop's own projection.
    ///
    /// The application has to be active for the status bar to hand out a visible item, exactly as
    /// `MenuBarStage` needs it for the popover — and `MenuBarController.redraw` refuses to write
    /// to an item nobody can see (F-163), so an inactive process would measure zero writes for the
    /// fixed code as well as for the broken code.
    static func installedMenuBar(_ fixture: NudgeHostFixture) throws {
        try fixture.wireMenuBarToTheLoop()
    }

    /// Rows the log marked `delivered` for one surface.
    static func delivered(_ fixture: NudgeHostFixture, on surface: NudgeSurface) throws -> Int {
        try fixture.interventions().count {
            $0.dispositionRaw == InterventionDisposition.delivered.rawValue
                && $0.surfaceRaw == surface.rawValue
        }
    }

    /// **Every charge on the glyph is paid for by a write to the glyph.**
    ///
    /// The bead's own drive, with the reading it was missing. Seven drifts, seven hundred seconds
    /// apart, and after each one: how many rows the log now calls delivered on `menuBar`, and how
    /// many times the status item's image has actually been assigned since the round began.
    ///
    /// The assertion is the pairing, not either number: a round that produced a delivered row on
    /// the glyph and no write to the glyph is the defect, whatever the totals are. Before the fix
    /// the writes were `[0, 0, 0, 0, 0, 0, 0]` against six delivered rows.
    @Test("seven drifts: no delivered glyph rung is charged without a write to the menu bar")
    func everyGlyphChargeIsPaidForByAWrite() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try Self.installedMenuBar(fixture)

        var writes: [Int] = []
        var charges: [Int] = []
        var chargedSoFar = 0

        for _ in 0..<7 {
            let writesBefore = fixture.menuBar.glyphWriteCount
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
            NudgeHostFixture.settle()

            let chargedNow = try Self.delivered(fixture, on: .menuBar)
            charges.append(chargedNow - chargedSoFar)
            chargedSoFar = chargedNow
            writes.append(fixture.menuBar.glyphWriteCount - writesBefore)

            fixture.clock.advance(by: .seconds(700))
        }

        // Non-vacuity first. A drive in which the ladder never reached the glyph would satisfy
        // every pairing below by having nothing to pair, which is the shape of a green that means
        // nothing.
        #expect(
            chargedSoFar > 0,
            "no rung was ever delivered to the glyph, so this drive proves nothing"
        )

        for round in writes.indices where charges[round] > 0 {
            #expect(
                writes[round] > 0,
                """
                round \(round + 1) charged \(charges[round]) glyph rung(s) and wrote to the menu \
                bar \(writes[round]) time(s) — writes \(writes), charges \(charges)
                """
            )
        }
    }

    /// **The write is the rung's, and it is a different picture and a different sentence.**
    ///
    /// The pairing above would be satisfied by a write of the same glyph — the image used to be
    /// assigned unconditionally on every redraw, so "a write happened" was true on every tick and
    /// meant nothing. This reads what was written: the item's mark goes from `unmarked` to
    /// `noticing`, VoiceOver is given a sentence it was not given before, and both go back when
    /// the rung is over.
    @Test("the landing marks the item and speaks, and forgetting the rung unmarks it")
    func theLandingMarksTheItemAndTheEndingUnmarksIt() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try Self.installedMenuBar(fixture)

        #expect(NudgeHostFixture.menuBarPresentation(of: fixture.host).attention == .unmarked)
        let writesBefore = fixture.menuBar.glyphWriteCount
        let announcedBefore = fixture.menuBar.announcementCount
        let sentenceBefore = fixture.menuBar.lastAnnouncement

        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
        NudgeHostFixture.settle()

        try #require(
            fixture.host.landedRungSurface == .menuBar,
            "the router did not send the ambient rung to the glyph, so this drives nothing"
        )
        #expect(NudgeHostFixture.menuBarPresentation(of: fixture.host).attention == .noticing)
        #expect(fixture.menuBar.glyphWriteCount == writesBefore + 1)
        // F-144's channel, on the one rung whose entire content is the glyph. Keyed to
        // `FocusStatus` this could not fire at all: the mandate needs ninety seconds of sustained
        // drift, so the status was already `.unrelated` when the rung arrived.
        #expect(fixture.menuBar.announcementCount == announcedBefore + 1)
        #expect(fixture.menuBar.lastAnnouncement != sentenceBefore)

        // And the item goes back. A mark that survived the nudge would be a permanent accusation,
        // which is the opposite failure and just as dishonest.
        fixture.host.hideOverlays()
        NudgeHostFixture.settle()
        #expect(fixture.host.landedRungSurface == nil)
        #expect(NudgeHostFixture.menuBarPresentation(of: fixture.host).attention == .unmarked)
        #expect(fixture.menuBar.glyphWriteCount == writesBefore + 2)
    }

    /// **A quiet tick writes nothing** — the negative control the pairing needs.
    ///
    /// Without it, a controller that assigned the image on every refresh would satisfy every
    /// assertion above while telling the person nothing, which is exactly the state this suite is
    /// about: the image *was* assigned unconditionally, and the menu bar still never changed.
    @Test("a refresh with nothing new writes nothing to the item")
    func aQuietRefreshWritesNothing() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try Self.installedMenuBar(fixture)

        let writes = fixture.menuBar.glyphWriteCount
        let announcements = fixture.menuBar.announcementCount
        for _ in 0..<5 {
            fixture.menuBar.update(NudgeHostFixture.menuBarPresentation(of: fixture.host))
        }
        #expect(fixture.menuBar.glyphWriteCount == writes)
        #expect(fixture.menuBar.announcementCount == announcements)
    }

    /// **focus-2xw: the badge asks for the click it needs** (U-1).
    ///
    /// `NudgeSurface.popoverBadge` is the shipping top rung for every Reduce Motion user, every
    /// `silentVisual` user and anybody with a microphone running, and it is the only surface a
    /// question reaches under the same three conditions. Delivery there is correctly withheld
    /// until the popover shows the nudge — which sharpened the defect rather than softening it: a
    /// nudge nobody was invited to open was never delivered, never counted and never answered.
    ///
    /// Driven over **both** quiet routes and asserted on writes to the item, not on
    /// `pendingAccusation != nil`, which is the value that already existed.
    @Test(
        "the badge marks the menu bar so the click that delivers it is invited",
        arguments: NudgeHostBadgeAccusationTests.QuietRoute.allCases
    )
    func theBadgeInvitesTheClick(route: NudgeHostBadgeAccusationTests.QuietRoute) throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try Self.installedMenuBar(fixture)

        let writesBefore = fixture.menuBar.glyphWriteCount
        NudgeHostBadgeAccusationTests.climbToTheBadge(fixture, via: route)
        NudgeHostFixture.settle()

        try #require(
            fixture.host.landedRungSurface == .popoverBadge,
            "the \(route.rawValue) route did not reach the badge, so this drives nothing"
        )
        #expect(NudgeHostFixture.menuBarPresentation(of: fixture.host).attention == .waiting)
        #expect(
            fixture.menuBar.glyphWriteCount > writesBefore,
            "a nudge is waiting behind a click and the menu bar never changed"
        )
        // The invitation is an invitation and not a delivery: nothing is counted until somebody
        // opens the popover, which is focus-xix's rule and is untouched here.
        #expect(try Self.delivered(fixture, on: .popoverBadge) == 0)
    }
}
