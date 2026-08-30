import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **An invitation nobody opened is a thing the app did** (focus-sq7, R-79).
///
/// ## The gap
///
/// A nudge routed to `.popoverBadge` that the person never opens the popover onto wrote **nothing**
/// to `InterventionLog`: not a delivered row — correct, nobody saw it — and not a deferred one
/// either. The question path had always behaved this way and the accusation path was made to match
/// it, so the parity was right and the gap was shared. But `InterventionLog` is the app's record of
/// what it did, and *"the app raised its top rung and nobody ever looked"* is a thing it did. The
/// record for such a day was indistinguishable from a day on which the ladder never left the glyph
/// — which is exactly the signal that would have shown focus-2xw in the wild, and it was absent by
/// construction.
///
/// ## Why `unopened` rather than `deferred`
///
/// A deferral is the statement *no surface could carry it*. This one reached a surface and waited,
/// so `DeferralReason.noSurfaceAvailable` would be false about it — and
/// `NudgeHostSlotOwnershipTests` reads `deferredCount` as a proxy for "the route offered nothing",
/// which writing it as a deferral would quietly corrupt. It spends nothing either way:
/// `spendsBudget` is `disposition == .delivered`.
///
/// ## Why this is one test over `MenuBarNudge.allCases`
///
/// Every bead in this sequence has the same shape — a treatment the question path had and the
/// accusation path lacked, or the reverse. `NudgeHost.recordUnopenedInvitation(_:)` switches over
/// `MenuBarNudge` exhaustively and this drives every case of it, so a third thing the badge learns
/// to carry cannot be recorded for one kind and forgotten for the other.
@Suite("An unopened badge invitation leaves a row", .serialized)
@MainActor
struct NudgeHostUnopenedInvitationTests {
    static let subject = NudgeHostFixture.decoy

    /// Rows the log marked `unopened`, with the surface and kind they name.
    static func unopened(_ fixture: NudgeHostFixture) throws -> [FocusSchemaV4.InterventionRecord] {
        try fixture.interventions()
            .filter { $0.dispositionRaw == InterventionDisposition.unopened.rawValue }
    }

    /// Rows the log marked `delivered` for one surface.
    static func delivered(_ fixture: NudgeHostFixture, on surface: NudgeSurface) throws -> Int {
        try fixture.interventions().count {
            $0.dispositionRaw == InterventionDisposition.delivered.rawValue
                && $0.surfaceRaw == surface.rawValue
        }
    }

    /// Put one kind of nudge on the badge, under a quiet route, without opening the popover.
    static func waitingOnTheBadge(_ fixture: NudgeHostFixture, _ nudge: MenuBarNudge) throws {
        switch nudge {
        case .accusation:
            NudgeHostBadgeAccusationTests.climbToTheBadge(fixture, via: .reducedInterruption)
            NudgeHostFixture.settle()
            try #require(
                fixture.host.landedRungSurface == .popoverBadge,
                "no accusation reached the badge, so there is no invitation to leave unopened"
            )

        case .query:
            fixture.host.choose(reducedInterruption: true)
            fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
            NudgeHostFixture.settle()
            try #require(
                fixture.host.pendingPopoverQuery != nil,
                "no question reached the badge, so there is no invitation to leave unopened"
            )
        }
    }

    /// **Both kinds, one mechanism, one row each.**
    ///
    /// The invitation goes up on the badge and the popover is never opened; then the loop lets it
    /// go. Before the fix the whole drive wrote nothing at all.
    @Test(
        "an invitation the person never opened is written down, for either kind",
        arguments: MenuBarNudge.allCases
    )
    func anUnopenedInvitationIsWrittenDown(nudge: MenuBarNudge) throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        fixture.wireMenuBarToTheLoop()

        try Self.waitingOnTheBadge(fixture, nudge)
        #expect(try Self.unopened(fixture).isEmpty, "the invitation was written off before it ended")

        // The person asked for their screen back without ever opening the popover — F-81, and the
        // commonest way an invitation ends unlooked-at.
        fixture.host.hideOverlays()
        NudgeHostFixture.settle()

        let rows = try Self.unopened(fixture)
        #expect(
            rows.count == 1,
            """
            \(nudge.rawValue): \(rows.count) unopened row(s) — a badge invitation nobody opened \
            must leave exactly one
            """
        )
        #expect(rows.first?.surfaceRaw == NudgeSurface.popoverBadge.rawValue)
        #expect(rows.first?.kindRaw == expectedKind(nudge).rawValue)

        // It is a record, never a charge. R-81: only a delivery spends a cap, and an invitation
        // nobody opened reached nobody. Counted on the badge alone — the accusation route climbs
        // through the ambient rung on the glyph, which really was delivered and really is charged.
        #expect(
            try Self.delivered(fixture, on: .popoverBadge) == 0,
            "an invitation nobody opened was counted as a delivery"
        )
        // And it is not a deferral. `NudgeHostSlotOwnershipTests` reads `deferredCount` as "the
        // route offered nothing", and this route offered a surface.
        #expect(
            try fixture.interventions()
                .count { $0.dispositionRaw == InterventionDisposition.deferred.rawValue } == 0,
            "an invitation that reached a surface was written down as having reached none"
        )
    }

    /// **A rung replaced before it was seen is an attempt that reached nobody too** (focus-sq7).
    ///
    /// `LadderMachine.arrive(_:)` resets to `.idle` for a different subject, so a fresh ambient
    /// rung lands and `setOpenRung(_:)` replaces the badge's rung. The first invitation used to
    /// vanish with no row, which is why the recording lives in the door that writes `openRung`
    /// rather than only in the paths that clear it.
    @Test("a badge rung replaced before anybody looked still leaves its row")
    func aReplacedInvitationStillLeavesItsRow() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        fixture.wireMenuBarToTheLoop()

        try Self.waitingOnTheBadge(fixture, .accusation)
        #expect(try Self.unopened(fixture).isEmpty)

        // A different application drifts, so the ladder starts again and a new rung lands.
        fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        fixture.host.consider(
            NudgeHostFixture.unrelatedJudgement(subject: "com.chrismitchelmore.FocusOtherApp")
        )
        NudgeHostFixture.settle()

        let rows = try Self.unopened(fixture)
        #expect(
            rows.count >= 1,
            "a badge rung was replaced before anybody looked and left no trace"
        )
        #expect(rows.first?.subject == Self.subject)
    }

    /// **The negative control: an invitation that WAS opened is a delivery and nothing else.**
    ///
    /// Without this the fold above is satisfied by a loop that writes `unopened` for every badge
    /// nudge including the ones somebody answered — which would double-count every quiet route in
    /// e09 and undo focus-xix's own rule from the other side.
    @Test("an invitation the person opened is a delivery, with no unopened row beside it")
    func anOpenedInvitationIsADeliveryAlone() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        fixture.wireMenuBarToTheLoop()

        try Self.waitingOnTheBadge(fixture, .accusation)
        try MenuBarStage.open(
            fixture.menuBar,
            showing: NudgeHostFixture.menuBarPresentation(of: fixture.host),
            onDidShow: nil
        )
        NudgeHostFixture.settle()

        #expect(
            try Self.delivered(fixture, on: .popoverBadge) == 1,
            "the popover showed the rung and the loop did not count it"
        )

        fixture.host.hideOverlays()
        NudgeHostFixture.settle()
        #expect(
            try Self.unopened(fixture).isEmpty,
            "a nudge the person was shown was also written down as never opened"
        )
    }

    /// The log's kind for one half of the badge. A `switch` rather than a stored map, so a third
    /// `MenuBarNudge` fails to compile here as well as in the host.
    func expectedKind(_ nudge: MenuBarNudge) -> InterruptionKind {
        switch nudge {
        case .query: .query
        case .accusation: .accusation
        }
    }
}
