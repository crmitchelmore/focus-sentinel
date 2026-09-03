import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **The seam, driven directly** (focus-my0, focus-r28.1, focus-tzj.6).
///
/// `NudgeChargingInvariantTests` and `NudgeUnseenAttemptTests` drive the whole loop against the
/// real panel and the real status item, which is what makes them worth having and also what makes
/// them silent about the mechanism: they can say a rung was not charged, and they cannot say
/// which of the three reasons it was not charged for. This suite asks the accountant on its own —
/// no store, no window, no judgement — the four questions the seam is *for*:
///
/// * a proof offered inside a turn is settled once, at the end of the outermost one;
/// * a turn entered from inside another turn is the same turn, so there is one seam and not two;
/// * every seam leaves a baseline for **both** kinds, whether or not either was proven, because
///   the kind a future rung lands as is not known yet (focus-r28.1);
/// * and the armed set is emptied by the seam, so nothing is proven twice.
///
/// The fifth guarantee — that a seam cannot be kept and spent later — is not tested here because
/// it is not testable here: `SurfaceTurn.Seam` is `~Copyable` and arrives `borrowing`, so a
/// handler that stored one, returned one or escaped one into a closure does not compile. The test
/// for it is the compiler, and R-96s pins the one file that can turn a reading into evidence.
@MainActor
@Suite("The accountant of when a nudge may be charged")
struct SurfaceProofAccountantTests {
    /// A reading that is not `.nothingSeen`: the item has been written to, and it is saying what
    /// a glyph rung needs it to say.
    private func itemSaying(_ mark: MenuBarAttention, writes: Int) -> SurfaceObservation {
        SurfaceObservation(
            menuBarWrites: writes,
            menuBarAnnouncements: 0,
            markOnTheItem: mark,
            panel: .nothingUp,
            popover: .nothingUp
        )
    }

    /// An accountant whose instrument answers `reading` and whose prover records what it was asked
    /// to prove, and whether the seam would accept it.
    private func accountant(
        observing reading: @escaping @MainActor () -> SurfaceObservation,
        proven: Proven
    ) -> SurfaceProofAccountant {
        let accountant = SurfaceProofAccountant()
        accountant.observe = { _ in reading() }
        accountant.prove = { nudge, seam in
            proven.kinds.append(nudge)
            // The seam is borrowed here and blessed here, which is the only shape the type allows.
            proven.settled.append(seam.settled(reading()))
        }
        return accountant
    }

    /// What the prover was asked, in order.
    private final class Proven {
        var kinds: [MenuBarNudge] = []
        var settled: [SettledObservation] = []
    }

    @Test("an offer inside a turn is proven once, when the outermost turn ends")
    func provenAtTheSeam() {
        let proven = Proven()
        let accountant = accountant(observing: { self.itemSaying(.noticing, writes: 1) }, proven: proven)

        accountant.run {
            accountant.offer(.accusation)
            // Nothing has been proven yet: the surfaces may still be moving.
            #expect(proven.kinds.isEmpty)
        }

        #expect(proven.kinds == [.accusation])
        #expect(accountant.offeredOutsideATurn == 0)
    }

    @Test("a turn entered from inside another turn is the same turn: one seam, not two")
    func nestedTurnsAreOneTurn() {
        let proven = Proven()
        let accountant = accountant(observing: { self.itemSaying(.noticing, writes: 1) }, proven: proven)

        accountant.run {
            accountant.offer(.accusation)
            accountant.run {
                accountant.offer(.query)
                #expect(proven.kinds.isEmpty)
            }
            #expect(proven.kinds.isEmpty)
        }

        // Both kinds, in `MenuBarNudge.allCases` order, from one seam.
        #expect(proven.kinds == MenuBarNudge.allCases)
    }

    @Test("the seam empties what was armed, so nothing is proven twice")
    func theSeamEmptiesTheOffers() {
        let proven = Proven()
        let accountant = accountant(observing: { self.itemSaying(.noticing, writes: 1) }, proven: proven)

        accountant.run { accountant.offer(.accusation) }
        accountant.run { }

        #expect(proven.kinds == [.accusation])
    }

    @Test("every seam leaves a baseline for both kinds, proven or not")
    func everySeamLeavesABaseline() {
        let proven = Proven()
        var reading = SurfaceObservation.nothingSeen
        let accountant = accountant(observing: { reading }, proven: proven)

        // Before the first seam there is no baseline, and the honest reading for surfaces that
        // have never settled is that nothing was seen.
        for nudge in MenuBarNudge.allCases {
            #expect(accountant.settledObservation(of: nudge) == .nothingSeen)
        }

        reading = itemSaying(.waiting, writes: 3)
        // A turn that offers nothing at all still settles a baseline.
        accountant.run { }

        #expect(proven.kinds.isEmpty)
        for nudge in MenuBarNudge.allCases {
            #expect(accountant.settledObservation(of: nudge) == reading)
        }
    }

    @Test("the baseline a landing is measured against is the last settled one, not a live reading")
    func theBaselineIsTheLastSettledReading() {
        let proven = Proven()
        var reading = itemSaying(.unmarked, writes: 1)
        let accountant = accountant(observing: { reading }, proven: proven)

        accountant.run { }
        // The item moves and moves back inside one turn — the shape focus-my0 was written for.
        accountant.run {
            reading = itemSaying(.noticing, writes: 2)
            reading = itemSaying(.unmarked, writes: 3)
            accountant.offer(.accusation)
        }

        // What the seam recorded is the state that survived to the end of the turn, and a proof
        // taken against it cannot be a proof about a frame that never existed.
        #expect(accountant.settledObservation(of: .accusation) == itemSaying(.unmarked, writes: 3))
        #expect(
            PerceptibleChange.proven(
                on: .menuBar,
                from: itemSaying(.unmarked, writes: 1),
                to: proven.settled[0]
            ) == nil
        )
    }

    @Test("a proof offered with no turn open is counted, and settled at the next seam")
    func offersOutsideATurnAreCounted() {
        let proven = Proven()
        let accountant = accountant(observing: { self.itemSaying(.noticing, writes: 1) }, proven: proven)

        accountant.offer(.accusation)

        #expect(accountant.offeredOutsideATurn == 1)
        #expect(proven.kinds.isEmpty)

        // Nothing imperceptible is charged either way: the offer survives to the next seam, where
        // the reading really is one of surfaces that had stopped moving. What is lost is the tie
        // between the write and the charge, which is why the count exists.
        accountant.run { }
        #expect(proven.kinds == [.accusation])
    }

    @Test("a reading blessed at the seam is the after half of a proof")
    func aBlessedReadingProvesAChange() {
        let proven = Proven()
        let accountant = accountant(observing: { self.itemSaying(.noticing, writes: 2) }, proven: proven)

        accountant.run { accountant.offer(.accusation) }

        #expect(
            PerceptibleChange.proven(
                on: .menuBar,
                from: .nothingSeen,
                to: proven.settled[0]
            ) != nil
        )
    }
}
