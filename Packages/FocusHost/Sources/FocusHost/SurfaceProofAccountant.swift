import FocusCore
import FocusUI
import Foundation
import os

/// **When a nudge may be charged to somebody, and what the surfaces were saying last time they
/// stopped moving** (focus-my0, focus-r28.1, focus-1b5, focus-nrl, focus-tzj.6).
///
/// The *when* of the charging invariant, as an object. `NudgeHost` keeps the *what*: only it can
/// say whether the open question or the open rung was really shown, because only it holds them
/// and only it writes the ledger. This holds the three things that decide the moment — the turn,
/// what has asked to be proven at the end of it, and the baseline each proof is measured
/// against — and it holds them where they can be driven directly, with no store, no window and
/// no judgement in flight.
///
/// ## One turn of the loop, and the seam at the end of it
///
/// Every door into the host from outside — a judgement, a click, a redraw, a phase change, the
/// display changing — runs inside `run { … }`, and nothing is charged until the outermost one
/// ends. That is the whole of focus-my0:
/// `closeSurfaces(endingAnyQuestionAs:andAnyRungAs:)` clears the question, hides the panel and
/// ends the rung in one synchronous call stack, and the first of those three statements makes the
/// item say the rung's own mark for as long as it takes to reach the third. AppKit composites
/// nothing in between, so a charge taken from a reading in the middle was taken for a frame that
/// never existed.
///
/// The reading taken at the seam is the one thing `PerceptibleChange.proven(on:from:to:)` will
/// accept, so this is not a rule anybody is trusted to follow — a charge proven from a mid-turn
/// reading does not compile.
@MainActor
final class SurfaceProofAccountant {
    private let turn = SurfaceTurn()

    /// **What has asked to be proven when the surfaces stop moving.**
    ///
    /// The three doors that used to charge — a landing, a click that opens the popover, and a
    /// write to the status item — now *offer*, and this is the offer. It is a set of kinds rather
    /// than a flag so that the seam settles the question and the rung through the same loop over
    /// `MenuBarNudge.allCases`: a third thing the badge learns to carry cannot be settled for one
    /// kind and forgotten for the other.
    ///
    /// It is emptied by the seam and never by anything else. A rung that offered itself and was
    /// not provable is not lost — it stays open and unpaid, and the next write to the item offers
    /// it again, which is what makes focus-nrl's rung recoverable.
    private var armedProofs: Set<MenuBarNudge> = []

    /// **What each kind of nudge's surfaces were saying when they last stopped moving**
    /// (focus-r28.1).
    ///
    /// Written at every seam and read as the *before* half of every proof. It exists because a
    /// proof was a comparison between one composited state and one arbitrary instant: the *after*
    /// half has been a `SettledObservation` since focus-my0, and the *before* half was an ordinary
    /// reading taken mid-turn at the landing. A mark written and reverted earlier in the same turn
    /// went into that baseline, and the rung it belonged to could never be proven afterwards.
    ///
    /// Keyed by `MenuBarNudge` because the reading is: the panel and the popover each carry one
    /// kind at a time, and *"a panel is up"* is not *"my panel is up"*.
    private var settledSurfaces: [MenuBarNudge: SurfaceObservation] = [:]

    private let logger = Logger(
        subsystem: FocusStore.bundleIdentifier,
        category: "SurfaceProofAccountant"
    )

    /// **What a person could actually be shown of one kind of nudge, right now.**
    ///
    /// The host's instrument, because every field of it is read off a live AppKit object the host
    /// owns. Wired once, beside the seam. Absent — a host that has gone away — reads as
    /// `.nothingSeen`, which is the honest reading for surfaces nobody is holding.
    var observe: (@MainActor (MenuBarNudge) -> SurfaceObservation)?

    /// **Prove one offered kind, at the seam.** The host's two provers, behind the exhaustive
    /// switch that keeps the question and the rung from being given different treatment.
    ///
    /// The seam is **borrowed**, never given: `SurfaceTurn.Seam` is `~Copyable`, so this closure
    /// can neither store one nor let one escape.
    var prove: (@MainActor (MenuBarNudge, borrowing SurfaceTurn.Seam) -> Void)?

    init() {
        // **The seam** (focus-my0). Set once, here, so that there is one place in the programme
        // where a reading of the surfaces becomes evidence, and it is a place that can only be
        // reached with the call stack unwound.
        turn.atSeam = { [weak self] seam in self?.settleCharges(at: seam) }
    }

    /// **A proof offered while no turn was open** (focus-my0) — always zero, and it is the one
    /// number that says the seam is actually reached.
    ///
    /// `SettledObservation` makes charging from a mid-turn reading unrepresentable, and that is
    /// the half of focus-my0 the type system holds. The other half is plumbing: every door into
    /// the host from outside has to run inside `run { … }`, and a door added without one is a rule
    /// somebody has to remember — which is precisely the shape this epic keeps finding.
    ///
    /// The failure it would cause is late rather than dishonest: an offer made outside a turn is
    /// settled at the *next* seam, against a reading of surfaces that really had stopped moving,
    /// so nothing imperceptible is charged either way. What is lost is the tie between the write
    /// and the charge — a rung would be paid for by an event that had nothing to do with it. So it
    /// is a reading rather than a fault to the person: stated as a count, so the unit lane and
    /// `--focus-self-check` can read it and a regression is a number.
    ///
    /// It is zero by construction today, and it is **falsifiable by mutation**, which is this
    /// programme's bar for a reading nothing can currently drive: deleting `run` from any entry
    /// point turns it non-zero on the next drive that reaches it. Measured with the wrapper
    /// removed from `menuBarItemRedrawn()`: two drives in `NudgeChargingInvariantTests` report 1
    /// each — the two that write to the status item from outside the loop, which is exactly the
    /// path a composition root takes on its five-second refresh.
    private(set) var offeredOutsideATurn = 0

    /// Run `body` as part of one turn, and reach the seam when the outermost one ends.
    @discardableResult
    func run<T>(_ body: () throws -> T) rethrows -> T {
        try turn.run(body)
    }

    /// **Offer one kind of nudge to the seam of this turn** (focus-1b5, focus-nrl, focus-my0).
    ///
    /// The offer matters: a redraw that never happens offers nothing, so a composition root that
    /// forgot to wire `MenuBarController.onGlyphWritten` still charges nothing for a glyph rung.
    /// The seam settles what was offered, never everything it can find.
    func offer(_ nudge: MenuBarNudge) {
        if !turn.isOpen {
            offeredOutsideATurn += 1
            logger.fault("a proof was offered outside a turn, so its seam is somebody else's event")
        }
        armedProofs.insert(nudge)
    }

    /// **What the surfaces were saying when they last stopped moving** (focus-r28.1).
    ///
    /// The *before* half of every proof. `.nothingSeen` until the first seam, which is the honest
    /// reading for a process whose surfaces have never settled: nothing has been drawn, nothing is
    /// up, and the item is bare.
    func settledObservation(of nudge: MenuBarNudge) -> SurfaceObservation {
        settledSurfaces[nudge] ?? .nothingSeen
    }

    /// **The surfaces have stopped moving; now ask what the person could have seen** (focus-my0).
    ///
    /// The one moment in the programme that spends a unit of the person's day, and the only one at
    /// which a reading of the surfaces becomes evidence — `SurfaceTurn.Seam` is handed to nothing
    /// but `prove`, and `PerceptibleChange.proven(on:from:to:)` takes nothing else.
    ///
    /// Over `MenuBarNudge.allCases` rather than as two statements: the question and the rung have
    /// been given the same treatment by hand four times in this epic and the hand has been wrong
    /// three of them.
    private func settleCharges(at seam: borrowing SurfaceTurn.Seam) {
        let offered = armedProofs
        armedProofs = []
        for nudge in MenuBarNudge.allCases where offered.contains(nudge) {
            prove?(nudge, seam)
        }
        // **And every seam leaves the baseline the next landing will be measured against**
        // (focus-r28.1). Taken for both kinds, whether or not either was proven here: a rung that
        // lands three turns from now is measured against what the surfaces were saying when they
        // last stopped moving, and the kind it lands as is not known yet.
        for nudge in MenuBarNudge.allCases {
            settledSurfaces[nudge] = observe?(nudge) ?? .nothingSeen
        }
    }
}
