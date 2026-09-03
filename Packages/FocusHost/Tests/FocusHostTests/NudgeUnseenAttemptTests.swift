import AppKit
import FocusCore
import FocusUI
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// **Every attempt the person did not see leaves exactly one row that says so** (focus-zeq,
/// focus-6vz, focus-5xf, focus-sq7).
///
/// ## The space, and why it is crossed with the status item
///
/// `NudgeSurface.allCases` × *{the item is installed, the item is not}*. The second axis is
/// focus-zeq: with the charge a consequence of a write to the `NSStatusBarButton`,
/// `MenuBarController.redraw(force:)` correctly refuses to write to an item nobody can see
/// (F-163) — so an app whose status item was never installed, or whose item
/// `MenuBarController.remove()` took out, charges nothing for an ambient rung. That is right, and
/// the loop said **nothing at all** about it: the rung landed, the ladder advanced, an unopened
/// row was written when the rung was let go of, and no reading anywhere said *the menu bar is not
/// there*. `SurfaceRouter` has had the honest vocabulary since P-131 —
/// `DeferralReason.menuBarHidden` — and could not see the case.
///
/// So the second column of this fold is the ruling: **an uninstalled status item is a stated
/// deferral, not a free landing.** And because a deferral does not advance the ladder (R-81), an
/// app with no item cannot climb at all — every attempt it makes is that same deferral, whichever
/// rung it would have been.
///
/// ## What each cell asserts
///
/// One attempt, and exactly one row about it:
///
/// | surface | item | the row |
/// |---|---|---|
/// | `menuBar` | installed | `delivered` — the item was written and the mark is the rung's |
/// | `panel` | installed | `delivered` — the window is up with every correction in reach |
/// | `popoverBadge` | installed | `unopened` — it reached a surface and waited behind a click |
/// | `notification` | installed | nothing routes here at all (U-2, R-96s) |
/// | any | not installed | `deferred`, and the decision names `menuBarHidden` |
///
/// **Exactly one**, in both directions: a second row would be the loop counting one attempt
/// twice, and no row at all is focus-sq7's own defect — *a day on which the app raised its top
/// rung and nobody ever looked read exactly like a day on which the ladder never left the glyph*.
///
/// ## What it restores
///
/// focus-5xf: `NudgeChargingInvariantTests` rests its unpaid-glyph conjunct on one arrangement —
/// a badge question holding the item at `waiting` — because focus-f2a removed the other one. This
/// is a second, structurally different one: a glyph rung whose item does not exist. The invariant
/// itself is asserted here too, on every cell, so the two suites cannot drift apart.
///
/// ## The vacuity guard, stated
///
/// A fold where nothing ever landed would satisfy "no charge without a receipt" everywhere, so
/// every installed cell asserts that its surface really was reached, the completeness check walks
/// `NudgeSurface.allCases` × both item states, and the fold refuses an empty space. A fold where
/// nothing was ever deferred would prove nothing about focus-zeq, so the deferred count is
/// asserted non-zero at the end.
@Suite("Every attempt nobody saw leaves exactly one row", .serialized)
@MainActor
struct NudgeUnseenAttemptTests {
    /// The second axis, and focus-zeq's whole subject.
    enum Item: String, CaseIterable {
        case installed
        case notInstalled

        var menuBarVisible: Bool { self == .installed }
    }

    /// One row, read out of the store as plain values.
    ///
    /// Copied rather than carried: a `FocusSchemaV7.InterventionRecord` belongs to the fixture's
    /// container, and this suite outlives every fixture it makes.
    struct Row {
        let kind: String
        let disposition: InterventionDisposition?
        let surface: NudgeSurface?
        let spendsBudget: Bool
    }

    /// What one attempt left behind.
    struct Attempt {
        let rows: [Row]
        let landedOn: NudgeSurface?
        let decision: NudgeDecision?
        /// **How many times the notch companion actually drew during this attempt** (e08a). Read
        /// off `NotchCompanionController.writeCount`, which counts assignments and not requests,
        /// for `glyphWriteCount`'s reason: a predicate saying the companion behaved cannot fail.
        let companionWrites: Int
        /// Whether the strip was on the screen when the attempt ended.
        let companionVisible: Bool
        /// Whether the geometry the companion was pointed at could carry a strip at all. The
        /// vacuity guard: a fold in which no cell had a landed geometry would satisfy "the
        /// companion drew nothing" on every Mac in the programme and prove nothing.
        let companionCouldHaveDrawn: Bool

        var dispositions: [InterventionDisposition] { rows.compactMap(\.disposition) }

        var summary: String {
            "rows \(rows.map { "\($0.kind)/\($0.disposition?.rawValue ?? "?")/\($0.surface?.rawValue ?? "-")" }) "
                + "landed \(landedOn?.rawValue ?? "-")"
        }
    }

    static let subjects = [
        "com.chrismitchelmore.FocusDecoy",
        "com.chrismitchelmore.FocusOtherApp"
    ]

    static func named(_ fixture: NudgeHostFixture) {
        for (index, identifier) in Self.subjects.enumerated() {
            fixture.workspace.runningNames[identifier] = "Decoy \(index)"
        }
    }

    /// Drive one cell and read back the row the last attempt wrote.
    ///
    /// The surface is aimed at through the product's own routing rather than injected: the glyph
    /// is the entry rung, the panel is the rung above it, and the badge is that same rung under
    /// `reducedInterruption` — which is the ordinary state of every Reduce Motion user and
    /// everybody on a call.
    static func drive(surface: NudgeSurface, item: Item) throws -> Attempt {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        // **The companion is wired with the same reading the loop is driven by** (e08a). The
        // fixture points it at a synthetic notched display, so in every cell it has somewhere it
        // could draw — which is what makes its silence in the deferred cells a measurement.
        try fixture.wireMenuBarToTheLoop(menuBarVisible: item.menuBarVisible)
        Self.named(fixture)

        let commitment = fixture.commitment
        let clock = fixture.clock
        fixture.host.surroundings = {
            NudgeHostFixture.surroundings(
                monotonic: clock.elapsed,
                commitment: commitment,
                menuBarVisible: item.menuBarVisible
            )
        }
        fixture.host.choose(reducedInterruption: surface == .popoverBadge)

        // The glyph first, whatever the target: the ladder enters at the ambient rung and there
        // is no other way in. For a target above it, the climb needs the dwell.
        if surface != .menuBar, item == .installed {
            fixture.host.consider(
                NudgeHostFixture.unrelatedJudgement(subject: Self.subjects[0])
            )
            NudgeHostFixture.settle()
            clock.advance(by: RelevancePolicy.escalationDwell + .seconds(1))
        }

        let before = try fixture.interventions().count
        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subjects[1]))
        NudgeHostFixture.settle()
        let landedOn = fixture.host.landedRungSurface
        let decision = fixture.host.lastDecision
        // The person takes their screen back without ever opening the popover: the one door that
        // lets an unpaid rung go, and therefore the moment an unopened invitation is written.
        fixture.host.hideOverlays()
        NudgeHostFixture.settle()

        let rows = try fixture.interventions()
        // **And the invariant this fold shares with the charging suite** (focus-5xf): every
        // delivered row in the store has a receipt behind it, computed by a different route.
        let deliveredRows = try fixture.host.deliveredRowsToday()
        let receipts = fixture.host.chargesPaidFor.count
        #expect(
            deliveredRows == receipts,
            """
            \(surface.rawValue)/\(item.rawValue): \(deliveredRows) delivered row(s) against \
            \(receipts) receipt(s)
            """
        )
        return Attempt(
            rows: rows.dropFirst(before).map {
                Row(
                    kind: $0.kindRaw,
                    disposition: InterventionDisposition(rawValue: $0.dispositionRaw),
                    surface: $0.surface,
                    spendsBudget: $0.spendsBudget
                )
            },
            landedOn: landedOn,
            decision: decision,
            companionWrites: fixture.notchCompanion.writeCount,
            companionVisible: fixture.notchCompanion.isVisible,
            companionCouldHaveDrawn: fixture.notchCompanion.landing().collapsed != nil
        )
    }

    @Test("every surface, with the item and without it, writes exactly one row per attempt")
    func everyCellWritesExactlyOneRow() throws {
        var driven: Set<String> = []
        var deferrals = 0
        var deliveries = 0
        var unopened = 0
        // e08a's two counters, folded rather than asserted in a suite of their own.
        var cellsWhereTheCompanionCouldHaveDrawn = 0
        var cellsWhereTheCompanionDidDraw = 0

        for surface in NudgeSurface.allCases {
            for item in Item.allCases {
                let cell = "\(surface.rawValue)/\(item.rawValue): "
                driven.insert(cell)

                // **The row no rung can reach** (U-2, R-96s). Nothing routes to a notification,
                // so there is no attempt to make and the assertion is that the loop never makes
                // one — asserted in the fold rather than beside it, so the dead row is dead in
                // the same place every live row is proven.
                guard surface != .notification else {
                    let attempt = try Self.drive(surface: .menuBar, item: item)
                    #expect(
                        attempt.landedOn != .notification,
                        "\(cell)a rung reached a surface no rung can reach — \(attempt.summary)"
                    )
                    #expect(
                        !attempt.rows.contains { $0.surface == .notification },
                        "\(cell)a row was written against a surface nothing routes to"
                    )
                    continue
                }

                let attempt = try Self.drive(surface: surface, item: item)
                #expect(
                    attempt.rows.count == 1,
                    """
                    \(cell)one attempt wrote \(attempt.rows.count) row(s) — \(attempt.summary)
                    """
                )
                if attempt.companionCouldHaveDrawn { cellsWhereTheCompanionCouldHaveDrawn += 1 }
                if attempt.companionWrites > 0 { cellsWhereTheCompanionDidDraw += 1 }

                switch item {
                case .notInstalled:
                    // **focus-zeq's ruling.** No item, so no surface: a stated deferral, never a
                    // landing nobody could have seen. And because a deferral does not advance the
                    // ladder, this is true of every rung the app has rather than of the glyph
                    // alone.
                    #expect(
                        attempt.dispositions == [.deferred],
                        "\(cell)an attempt with no status item was not a deferral — \(attempt.summary)"
                    )
                    #expect(
                        attempt.decision?.deferralReason == .menuBarHidden,
                        """
                        \(cell)the loop deferred without saying the menu bar was missing — \
                        \(String(describing: attempt.decision?.deferralReason))
                        """
                    )
                    #expect(attempt.landedOn == nil, "\(cell)a rung landed with no item to land on")
                    // **The e08a conjunct** (review §3, e08a T3). The notch companion is a second
                    // renderer of this same rung, and a renderer that drew where the item could not
                    // would make the notch the only surface a rung reaches — focus-mkk inverted,
                    // and a fifth surface needing its own `PerceptionChannel`, its own difference
                    // arithmetic and its own `surfacesARungCanReach` row. The geometry it is
                    // pointed at *lands*, so this is a companion that could have drawn and did not.
                    #expect(
                        attempt.companionCouldHaveDrawn,
                        "\(cell)the companion had nowhere to draw, so its silence proves nothing"
                    )
                    #expect(
                        attempt.companionWrites == 0 && !attempt.companionVisible,
                        """
                        \(cell)the companion drew where the glyph could not — \
                        \(attempt.companionWrites) write(s), visible \(attempt.companionVisible). \
                        The notch has stopped being a renderer of the ambient rung.
                        """
                    )
                    deferrals += 1

                case .installed:
                    #expect(
                        attempt.landedOn == surface,
                        """
                        \(cell)the rung was aimed at \(surface.rawValue) and reached \
                        \(attempt.landedOn?.rawValue ?? "nothing")
                        """
                    )
                    if surface.reachesThePersonOnLanding {
                        #expect(
                            attempt.dispositions == [.delivered],
                            "\(cell)a rung the person saw was not delivered — \(attempt.summary)"
                        )
                        deliveries += 1
                    } else {
                        // The badge: it reached a surface and waited behind a click nobody made.
                        #expect(
                            attempt.dispositions == [.unopened],
                            """
                            \(cell)an invitation nobody opened was not written down as unopened \
                            — \(attempt.summary)
                            """
                        )
                        #expect(
                            attempt.rows.allSatisfy { !$0.spendsBudget },
                            "\(cell)an unopened row spent a cap"
                        )
                        unopened += 1
                    }
                }
            }
        }

        // — the completeness check, self-referential —
        let space = NudgeSurface.allCases.flatMap { surface in
            Item.allCases.map { "\(surface.rawValue)/\($0.rawValue): " }
        }
        #expect(
            driven == Set(space),
            "\(Set(space).subtracting(driven)) were never driven, so the fold is smaller than the space"
        )
        #expect(!space.isEmpty, "the space is empty, so the fold proves nothing")

        // — the vacuity guard, stated —
        #expect(deferrals > 0, "nothing was ever deferred, so focus-zeq's column proves nothing")
        #expect(deliveries > 0, "nothing was ever delivered, so a silent app would pass this")
        #expect(unopened > 0, "no invitation was ever left unopened, so focus-sq7's row is unproven")
        // — e08a's own vacuity guards —
        #expect(
            cellsWhereTheCompanionCouldHaveDrawn > 0,
            """
            no cell had a landed geometry, so the companion conjunct holds because no companion \
            ever existed
            """
        )
        #expect(
            cellsWhereTheCompanionDidDraw > 0,
            """
            the companion never drew in any cell, so a renderer that draws nothing at all would \
            satisfy the conjunct
            """
        )
    }

    /// Drive one question at one surface and read back the row it wrote.
    ///
    /// The question's twin of `drive(surface:item:)`, and the whole point of having one: the
    /// shape of every bead in this sequence is a treatment one half of the loop received and the
    /// other did not.
    static func askQuestion(surface: NudgeSurface, item: Item) throws -> Attempt {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try fixture.wireMenuBarToTheLoop()
        Self.named(fixture)

        let commitment = fixture.commitment
        let clock = fixture.clock
        fixture.host.surroundings = {
            NudgeHostFixture.surroundings(
                monotonic: clock.elapsed,
                commitment: commitment,
                menuBarVisible: item.menuBarVisible
            )
        }
        fixture.host.choose(reducedInterruption: surface == .popoverBadge)

        let before = try fixture.interventions().count
        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subjects[0]))
        NudgeHostFixture.settle()
        let decision = fixture.host.lastDecision
        // Where the question was routed, read off the decision the loop actually took — the same
        // reading `NudgeDayShapeTests` takes for a rung, and never a second predicate.
        let asked = decision?.warrant == nil ? nil : decision?.route?.surface
        // F-81's one command: the person takes their screen back and answers nothing, which is
        // the door an unopened invitation is written at.
        fixture.host.hideOverlays()
        NudgeHostFixture.settle()

        let rows = try fixture.interventions()
        return Attempt(
            rows: rows.dropFirst(before).map {
                Row(
                    kind: $0.kindRaw,
                    disposition: InterventionDisposition(rawValue: $0.dispositionRaw),
                    surface: $0.surface,
                    spendsBudget: $0.spendsBudget
                )
            },
            landedOn: asked,
            decision: decision,
            companionWrites: fixture.notchCompanion.writeCount,
            companionVisible: fixture.notchCompanion.isVisible,
            companionCouldHaveDrawn: fixture.notchCompanion.landing().collapsed != nil
        )
    }

    /// **The same fold, on the question** (focus-6vz).
    ///
    /// `recordUnopenedInvitation(_:)`'s doc states the doctrine — *one function over
    /// `MenuBarNudge`, not one per kind* — and its two arms were not the same treatment. The
    /// accusation's was repaired to key on `OpenRung.perceived`, the receipt, *"a rung that was
    /// never perceived is unopened, whichever surface it was standing on"*; the question's still
    /// keyed on `NudgeSurface.reachesThePersonOnLanding`, the predicate this whole round exists
    /// to retire, conjoined with `readingAtAsk` — a field written **from** the proof rather than
    /// the proof itself. `OpenQuestion` has carried `perceived` since focus-my0 and the arm did
    /// not read it.
    ///
    /// The bead is explicit that it could construct no wrong number in the build it was filed
    /// against: `ask(…)` refuses to deliver into an unreadable panel, so the one arrangement in
    /// which the two keys disagree — a question standing on a surface that reaches on landing and
    /// was never proven — is not reachable today. It is filed for its **shape**, and this is the
    /// fold that holds the two arms to one answer whichever surface a question reaches.
    @Test("a question on every surface it can reach writes exactly one row per ask")
    func everyQuestionAttemptWritesExactlyOneRow() throws {
        var driven: Set<String> = []
        var delivered = 0
        var unopened = 0
        var deferred = 0

        for surface in NudgeSurface.allCases {
            for item in Item.allCases {
                let cell = "\(surface.rawValue)/\(item.rawValue): "
                driven.insert(cell)

                // A question is offered the panel and the badge and nothing else: the glyph
                // carries no sentence and nothing routes to a notification (U-2, R-96s).
                guard surface == .panel || surface == .popoverBadge else {
                    let attempt = try Self.askQuestion(surface: .panel, item: item)
                    #expect(
                        attempt.landedOn != surface,
                        "\(cell)a question reached a surface no question can reach"
                    )
                    continue
                }

                let attempt = try Self.askQuestion(surface: surface, item: item)
                #expect(
                    attempt.rows.count == 1,
                    "\(cell)one ask wrote \(attempt.rows.count) row(s) — \(attempt.summary)"
                )

                // The panel does not need the status item; the badge is drawn inside it. So the
                // second column is uniform for the ladder — which cannot climb without the glyph
                // — and NOT for the question, which is a fact about the surface rather than about
                // the item, and is asserted as such rather than assumed.
                if surface == .popoverBadge, item == .notInstalled {
                    #expect(
                        attempt.dispositions == [.deferred],
                        "\(cell)a badge with no item to draw it on was not deferred — \(attempt.summary)"
                    )
                    #expect(attempt.decision?.deferralReason == .menuBarHidden)
                    deferred += 1
                    continue
                }

                #expect(
                    attempt.landedOn == surface,
                    """
                    \(cell)the question was aimed at \(surface.rawValue) and reached \
                    \(attempt.landedOn?.rawValue ?? "nothing")
                    """
                )
                if surface.reachesThePersonOnLanding {
                    #expect(
                        attempt.dispositions == [.delivered],
                        "\(cell)a question the person saw was not delivered — \(attempt.summary)"
                    )
                    delivered += 1
                } else {
                    #expect(
                        attempt.dispositions == [.unopened],
                        """
                        \(cell)an invitation nobody opened was not written down as unopened — \
                        \(attempt.summary)
                        """
                    )
                    #expect(attempt.rows.allSatisfy { !$0.spendsBudget }, "\(cell)unopened spent a cap")
                    unopened += 1
                }
            }
        }

        let space = NudgeSurface.allCases.flatMap { surface in
            Item.allCases.map { "\(surface.rawValue)/\($0.rawValue): " }
        }
        #expect(driven == Set(space), "\(Set(space).subtracting(driven)) were never driven")
        #expect(delivered > 0, "no question was ever delivered, so a mute app would pass this")
        #expect(unopened > 0, "no question was ever left unopened, so the arm proves nothing")
        #expect(deferred > 0, "no question was ever deferred, so focus-zeq's column is unproven")
    }

    /// **The composition root's own reading, which is where focus-zeq lives** (focus-zeq).
    ///
    /// The fold above drives the loop through `NudgeSurroundings.menuBarVisible`; this is the one
    /// line that decides what that value is in the shipping app. It read
    /// `!presentationState.suppressesOverlays` alone — the full-screen space P-131 measured — and
    /// had no reading at all for an item that is not there.
    @Test("the root's menu-bar reading knows whether the item is installed")
    func theRootReadsTheItem() throws {
        let root = AppComposition(
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference),
            monotonicClock: FixedMonotonicClock(),
            calendar: NudgeHostFixture.londonCalendar,
            locale: Locale(identifier: "en_GB"),
            hotKeyRegistrar: InertHotKeyRegistrar(),
            storeKind: .inMemory,
            notificationCentre: SilentNotificationCentre()
        )
        root.joinHosts()
        defer { root.menuBar.remove(); root.stop() }

        try MenuBarStage.install(root.menuBar)
        try #require(root.menuBar.isInstalled)
        #expect(
            root.nudgeSurroundings().menuBarVisible,
            "the item is in the menu bar and the loop was told the menu bar was not there"
        )

        root.menuBar.remove()
        try #require(!root.menuBar.isInstalled)
        #expect(
            !root.nudgeSurroundings().menuBarVisible,
            "the item was taken out of the menu bar and the loop was never told"
        )
    }
}
