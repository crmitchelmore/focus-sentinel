import FocusCore
import Foundation
import Testing

@testable import FocusHost

/// **The gate's own accusation-route fold, run by the unit lane** (focus-vxo).
///
/// ## Why this suite exists at all
///
/// `SelfCheck.nudgeReport()` publishes `everyAccusationRouteCanBeAnswered`, and the
/// `selfcheck-debug` gate stage fails on it. It read `true` for a whole round while the running
/// loop was putting a *delivered* accusation on the menu-bar glyph under a deck reachable in two
/// clicks — because the fold behind it carried two exemptions. It asked
/// `voice.renderedRung(for: rung)`, the rung a **deck** claimed to draw rather than the rung the
/// ladder had climbed to, so the four broken cells were skipped by the guard that exists to find
/// them; and it pinned `media: .idle` with no presentation, the conditions under which nothing is
/// demoted at all. A verdict over a space chosen so that it cannot be false is not evidence.
///
/// `SurfaceRouterTests.everyRouteCanBeAnsweredBack` carried the *same* exemption, in a second
/// copy of the same loop — which is why the two lanes agreed all round and neither could tell
/// anybody. So the fold is now one function, `SelfCheck.accusationRouteAudit()`, and this suite
/// runs the one the binary runs. Mutating it fails both lanes together, which is the only
/// arrangement in which their agreement means something.
@Suite("The self-check's accusation-route audit")
struct SelfCheckAccusationAuditTests {
    /// The whole space, spelled from the vocabularies rather than as a literal (R-96j): one
    /// accusing rung × presenting × microphone × the flag × menu-bar visible × every deck.
    static let wholeSpace =
        LadderRung.Kind.allCases.count(where: \.makesAnAccusation)
        * 2 * 2 * 2 * 2 * NudgeVoice.allCases.count

    /// **The size of the fold, asserted before the verdict it qualifies.**
    ///
    /// This is the assertion the round was missing. Both exemptions were *shrinkages* — one took
    /// four cells out through a guard, the other took twelve sixteenths of the space out through
    /// pinned inputs — and neither changed the `true` they produced. A count cannot be shrunk
    /// quietly.
    @Test("the audit folds over the whole input space, not a subset of it")
    func theAuditCoversTheWholeSpace() {
        #expect(SelfCheck.accusationRouteAudit().cells == Self.wholeSpace)
    }

    /// **And every one of those cells is answerable.**
    ///
    /// Named cells rather than a bare `false`, exactly as the gate reports them, so this suite
    /// fails with the same sentence the gate would print.
    @Test("no accusation route in the whole space lands where it cannot be answered")
    func noAccusationRouteIsUnanswerable() {
        let audit = SelfCheck.accusationRouteAudit()

        #expect(
            audit.unanswerable.isEmpty,
            """
            the self-check would report an accusation with no way to answer it:
            \(audit.unanswerable.joined(separator: "\n"))
            """
        )
    }

    /// **The audit can go red**, which is the half of a green reading nobody checks.
    ///
    /// `offersAnAnswer` is the predicate the audit turns on, and `.menuBar` is the surface that
    /// answers `false` for it. If that ever stopped being true the audit would pass over any
    /// routing defect at all, silently, and the gate would go on printing a green line — which is
    /// precisely the failure this bead is about, one layer further down.
    @Test("the predicate the audit turns on still has a false case")
    func theAuditHasSomethingToFind() {
        #expect(NudgeSurface.allCases.contains { !$0.offersAnAnswer })
        #expect(!NudgeSurface.menuBar.offersAnAnswer)
        #expect(NudgeSurface.popoverBadge.offersAnAnswer)
    }
}
