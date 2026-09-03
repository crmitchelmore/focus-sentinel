import AppKit
import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **The ladder climbs in the loop that is running, not only in the reducer** (R-80, R-81).
///
/// ## The defect this suite found
///
/// `LadderMachineTests` proves the reducer escalates `ambient → panel` on a
/// transcript. `NudgeDeciderTests` proves the decision does. Neither could see that the running
/// loop's ladder was **never told about the mandate**: `NudgeDecider.accuse(…)` folds it into a
/// *copy* of the machine to work out which rung is next, and that copy dies with the decision.
/// Without the same fold in `NudgeHost.accuse`, `liveMandate` stayed `nil` on the ladder that
/// survives — so `candidate(at:budgetPermits:)` answered `nil`, `offer(…)` recorded nothing,
/// `reduce(.delivery(.delivered(_)))` found no attempt to resolve, and the state never left
/// `.idle`. Every judgement re-entered at `LadderRung.entry(for:)`, and **the app could not
/// escalate past the ambient glyph however long somebody drifted**: the panel rung was
/// unreachable in the shipping loop.
///
/// It was invisible because every existing proof of R-80 drove the reducer or the decider
/// directly with a ladder the test had already put into the state it wanted. This drives the loop
/// — one `consider(_:)` per corroboration tick, on the real panel, against the real store — and
/// reads the rungs it actually arrives at.
@Suite("The ladder, climbed by the running loop", .serialized)
@MainActor
struct NudgeHostLadderTests {
    static let subject = "com.chrismitchelmore.FocusDecoy"

    /// **Sustained drift, one tick at a time, and the rungs it arrives at.**
    ///
    /// Nothing here installs a ladder state. The only inputs are an `unrelated` judgement that has
    /// been sustained — the input the ladder answers — and the monotonic clock moving between
    /// ticks past both of the two intervals that gate an escalation: `escalationDwell`, which is
    /// fact 3 of the four, and `mandateCooldown`, which is the longer of the two and therefore the
    /// one to step over. The rungs, the surfaces and the log rows are all what the loop decided.
    @Test("sustained drift climbs ambient, then the panel")
    func theLoopClimbsTheWholeLadder() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        // **The item is in the menu bar, exactly as the shipping app has it** (focus-1b5).
        // The ambient rung *is* the status item: with no item installed there is nothing for it
        // to change, `MenuBarController.redraw(force:)` refuses to write to an item nobody can
        // see (F-163), and the loop correctly charges nothing. A fixture without one drives an
        // app whose menu bar is not there, which is not the state this test is about.
        try fixture.wireMenuBarToTheLoop()

        var rungs: [LadderRung.Kind] = []
        var surfaces: [String] = []
        for _ in 0..<2 {
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
            NudgeHostFixture.settle()
            if let rung = fixture.host.currentRung { rungs.append(rung) }
            if case .accuse(_, .surface(let surface)) = fixture.host.lastDecision {
                surfaces.append(surface.rawValue)
            }
            fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }

        #expect(
            rungs == [.ambient, .panel],
            "the loop's ladder did not climb: it reached \(rungs)"
        )
        // The ambient rung is the menu-bar glyph and raises no window; the one above it is the
        // panel, which is now the top of the ladder (U-2).
        #expect(surfaces == ["menuBar", "panel"])
        #expect(fixture.panel.isVisible)
        #expect(fixture.host.deliveredCount == 2)

        // Two delivered rows, each naming the rung it carried: the climb is legible in the
        // record rather than only in memory. Compared as a sorted set, because this fixture's
        // clock is fixed on purpose and rows stamped with one instant have no order to
        // assert — a receipt's time is not what this is about.
        let rows = try fixture.interventions()
            .filter { $0.dispositionRaw == InterventionDisposition.delivered.rawValue }
        #expect(rows.compactMap(\.rungRaw).sorted() == ["ambient", "panel"])
    }

    /// **A held return puts the ladder down, and one alt-tab does not** (focus-4xy, U-1).
    ///
    /// `LadderDeEscalation.verdictRelevant` — *"the engine now says this is real work"* — was a
    /// case in the vocabulary that nothing emitted. So the ladder came down for things the PERSON
    /// did and never for the app getting better at recognising the work in front of it, which is
    /// the half of U-1's bargain the ruling rests on.
    ///
    /// **Both halves are required, and the first is what stops the fix being the alt-tab defeat.**
    /// `DriftMachine` ruling 1 credits a return only once it has been HELD past
    /// `driftResetGrace`, and a ladder that reset on a single `.aligned` judgement would be
    /// defeated exactly the way `focus-f2a` measured: the drift-return-drift rhythm produces one
    /// aligned reading between every pair of drifts. So this drives the loop up to the panel,
    /// feeds aligned judgements for less than the grace and requires the ladder to be STILL UP,
    /// and only then steps over it.
    @Test("a return the engine has held past the grace puts the ladder down; one does not")
    func aHeldReturnPutsTheLadderDown() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try fixture.wireMenuBarToTheLoop()

        // Climb to the panel, the same way theLoopClimbsTheWholeLadder does.
        for _ in 0..<2 {
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
            NudgeHostFixture.settle()
            fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }
        try #require(fixture.host.currentRung == .panel, "the ladder never reached the panel")

        // The first aligned judgement starts the clock and puts nothing down.
        fixture.host.consider(NudgeHostFixture.alignedJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        #expect(
            fixture.host.currentRung == .panel,
            "one aligned verdict put the ladder down — that is the alt-tab defeat focus-f2a is about"
        )

        // Held, but not yet past the grace: still up.
        fixture.clock.advance(by: RelevancePolicy.driftResetGrace - .seconds(1))
        fixture.host.consider(NudgeHostFixture.alignedJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        #expect(
            fixture.host.currentRung == .panel,
            "the ladder came down one second short of the grace"
        )

        // …and one step over it: down.
        fixture.clock.advance(by: .seconds(2))
        fixture.host.consider(NudgeHostFixture.alignedJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        #expect(
            fixture.host.currentRung == nil,
            "a return held past driftResetGrace left the ladder standing at \(String(describing: fixture.host.currentRung))"
        )
        #expect(!fixture.panel.isVisible, "the rung's own panel outlived the ladder that raised it")
    }

    /// **Drift breaking the alignment restarts the clock** (focus-4xy).
    ///
    /// The control for the test above: without it, "held past the grace" would be satisfied by
    /// any two aligned readings far enough apart, whatever the person did in between — which is
    /// the drift-return-drift rhythm, and is the shape the fix must not have.
    @Test("a drift between two aligned verdicts restarts the grace")
    func driftBetweenAlignmentsRestartsTheGrace() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try fixture.wireMenuBarToTheLoop()

        for _ in 0..<2 {
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
            NudgeHostFixture.settle()
            fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }
        try #require(fixture.host.currentRung == .panel)

        fixture.host.consider(NudgeHostFixture.alignedJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        // A drift in the middle. The alignment is broken, so the clock starts again.
        fixture.clock.advance(by: RelevancePolicy.driftResetGrace - .seconds(1))
        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        fixture.clock.advance(by: .seconds(2))
        fixture.host.consider(NudgeHostFixture.alignedJudgement(subject: Self.subject))
        NudgeHostFixture.settle()

        #expect(
            fixture.host.currentRung != nil,
            "two aligned verdicts either side of a drift put the ladder down"
        )
    }

    /// **A rung that was only deferred is not a rung the ladder climbed past** (R-81).
    ///
    /// The other half of the same wire, and the one the fold above could have broken in the other
    /// direction. A presentation claims the display before the ambient rung is delivered: the
    /// menu bar is hidden, the rung is deferred, and no `deliveredAt` is written — so when the
    /// presentation ends the ladder is still at the bottom and offers the **same** rung again
    /// rather than escalating on the strength of a rung nobody saw.
    @Test("a deferred rung leaves the ladder where it was, so the same rung comes back")
    func aDeferredRungDoesNotAdvanceTheLoopsLadder() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        // No menu bar: the glyph has nowhere to appear, which is a deferral and never a delivery.
        fixture.host.surroundings = { [clock = fixture.clock, commitment = fixture.commitment] in
            NudgeHostFixture.surroundings(
                monotonic: clock.elapsed, commitment: commitment, menuBarVisible: false
            )
        }
        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
        NudgeHostFixture.settle()

        #expect(fixture.host.deferredCount == 1)
        #expect(fixture.host.deliveredCount == 0)
        #expect(
            fixture.host.currentRung == nil,
            "a rung nobody could see put the ladder on a rung it had not delivered"
        )

        // The menu bar comes back after long enough for an escalation to have been possible.
        fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        fixture.host.surroundings = { [clock = fixture.clock, commitment = fixture.commitment] in
            NudgeHostFixture.surroundings(monotonic: clock.elapsed, commitment: commitment)
        }
        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
        NudgeHostFixture.settle()

        #expect(
            fixture.host.currentRung == .ambient,
            "the ladder escalated through a rung it had only deferred"
        )
        #expect(!fixture.panel.isVisible, "a deferred glyph escalated straight to the panel")
    }
}
