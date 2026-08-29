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
/// `LadderMachineTests` proves the reducer escalates `ambient → panel → recommitment` on a
/// transcript. `NudgeDeciderTests` proves the decision does. Neither could see that the running
/// loop's ladder was **never told about the mandate**: `NudgeDecider.accuse(…)` folds it into a
/// *copy* of the machine to work out which rung is next, and that copy dies with the decision.
/// Without the same fold in `NudgeHost.accuse`, `liveMandate` stayed `nil` on the ladder that
/// survives — so `candidate(at:budgetPermits:)` answered `nil`, `offer(…)` recorded nothing,
/// `reduce(.delivery(.delivered(_)))` found no attempt to resolve, and the state never left
/// `.idle`. Every judgement re-entered at `LadderRung.entry(for:)`, and **the app could not
/// escalate past the ambient glyph however long somebody drifted**: the panel and recommitment
/// rungs were unreachable in the shipping loop.
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
    @Test("sustained drift climbs ambient, then the panel, then the recommitment")
    func theLoopClimbsTheWholeLadder() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        var rungs: [LadderRung.Kind] = []
        var surfaces: [String] = []
        for _ in 0..<3 {
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
            NudgeHostFixture.settle()
            if let rung = fixture.host.currentRung { rungs.append(rung) }
            if case .accuse(_, .surface(let surface), _) = fixture.host.lastDecision {
                surfaces.append(surface.rawValue)
            }
            fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }

        #expect(
            rungs == [.ambient, .panel, .recommitment],
            "the loop's ladder did not climb: it reached \(rungs)"
        )
        // The ambient rung is the menu-bar glyph and raises no window; the two above it are the
        // panel, because this fixture's notification centre answers `denied` — the ordinary state
        // of a Mac nobody has granted notifications on (R-82).
        #expect(surfaces == ["menuBar", "panel", "panel"])
        #expect(fixture.panel.isVisible)
        #expect(fixture.host.deliveredCount == 3)

        // Three delivered rows, each naming the rung it carried: the climb is legible in the
        // record rather than only in memory. Compared as a sorted set, because this fixture's
        // clock is fixed on purpose and three rows stamped with one instant have no order to
        // assert — a receipt's time is not what this is about.
        let rows = try fixture.interventions()
            .filter { $0.dispositionRaw == InterventionDisposition.delivered.rawValue }
        #expect(rows.compactMap(\.rungRaw).sorted() == ["ambient", "panel", "recommitment"])
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
