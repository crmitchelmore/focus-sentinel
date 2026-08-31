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

    // MARK: - The same fold, over every rung: which surfaces a rung can reach (focus-3vb)

    /// The whole space for **every** rung, spelled from the vocabularies rather than as a literal
    /// (R-96j), so adding a rung or a deck grows the expected count without anybody editing it.
    static let everyRungWholeSpace =
        LadderRung.Kind.allCases.count * 2 * 2 * 2 * 2 * NudgeVoice.allCases.count

    /// **The set of surfaces a rung can reach, pinned exactly.**
    ///
    /// The gate's reading of this was `"notification" not in surfacesARungCanReach` — a membership
    /// test over a set built from the two-cell `routes` table. Two failures in one line. A
    /// membership test cannot see a surface *appearing*: route every rung to the badge and the
    /// check stays green. And the set it searched was every rung asked exactly once at
    /// `.notPresenting`, `.idle`, `reducedInterruption: false`, `menuBarVisible: true`,
    /// `voice: .standard`, so a notification route reachable under Reduce Motion, a running
    /// microphone, `silentVisual` or a hidden menu bar was invisible to it — and this is the only
    /// "no notification" reading the RELEASE lane takes.
    ///
    /// Three surfaces, and the third is the point: `popoverBadge` **is** reachable, under exactly
    /// the conditions the two-cell table pinned away. A reading that said two was not a stronger
    /// claim, it was a narrower one.
    static let surfacesEveryRungCanReach = ["menuBar", "panel", "popoverBadge"]

    /// The size of the fold, asserted before the set it qualifies — the same discipline
    /// `theAuditCoversTheWholeSpace` applies to the accusation half.
    @Test("the every-rung fold covers the whole input space, not the two cells it used to")
    func theEveryRungFoldCoversTheWholeSpace() {
        #expect(SelfCheck.routeAudit(over: LadderRung.Kind.allCases).cells == Self.everyRungWholeSpace)
        // …and it really is wider than the table it replaced, which had one cell per rung.
        #expect(Self.everyRungWholeSpace > LadderRung.Kind.allCases.count)
    }

    /// **Pinned in both directions.** A surface leaving the set fails this as loudly as one
    /// joining it — which a `not in` test does in neither direction.
    @Test("over the whole space the only surfaces any rung reaches are these three")
    func theSurfacesARungCanReachArePinned() {
        let audit = SelfCheck.routeAudit(over: LadderRung.Kind.allCases)
        #expect(audit.surfaces == Self.surfacesEveryRungCanReach)
    }

    /// **The completeness check: it fails when the space grows and this proof does not.**
    ///
    /// `NudgeSurface` is `CaseIterable`. Every case is either reached by some cell of the fold or
    /// named here as one no rung can carry, and the two lists must together be the whole
    /// vocabulary — so a fifth surface added tomorrow fails this line until somebody says which it
    /// is. `notification` is the case U-2 forbids and the reason the whole reading exists.
    @Test("every declared surface is either reached by the fold or named as unreachable")
    func theFoldAccountsForEverySurface() {
        let audit = SelfCheck.routeAudit(over: LadderRung.Kind.allCases)
        let reached = Set(audit.surfaces)
        let unreachable = Set(NudgeSurface.allCases.map(\.rawValue)).subtracting(reached)
        #expect(unreachable == ["notification"])
        #expect(reached.union(unreachable) == Set(NudgeSurface.allCases.map(\.rawValue)))
    }

    /// **The vacuity guard, stated rather than assumed.**
    ///
    /// What this fold would still be green for, named so nobody has to re-derive it:
    ///
    /// 1. **A dimension the fold does not vary.** It varies rung, presentation, microphone,
    ///    `reducedInterruption`, menu-bar visibility and deck — six. A surface reachable only
    ///    under a *seventh* input, if one were ever added to `SurfaceRouter.route(…)`, would not
    ///    appear here; the cell count is what would move, and it is asserted above.
    /// 2. **A notification posted without being routed to.** This is a fold over the ROUTER. A
    ///    rung that reached `UNUserNotificationCenter` without asking the router would pass every
    ///    line in this file. The shipped Mach-O carrying no posting selector is the other half,
    ///    and it lives in `check-forbidden.sh` where it can be measured on the artefact.
    /// 3. **A set that agrees for the wrong reason.** So this asserts the fold discriminates: it
    ///    reaches more than one surface, and at least one declared surface it does not reach.
    @Test("the fold discriminates: several surfaces reached, and at least one not")
    func theFoldIsNotVacuous() {
        let audit = SelfCheck.routeAudit(over: LadderRung.Kind.allCases)
        #expect(audit.surfaces.count > 1)
        #expect(audit.surfaces.count < NudgeSurface.allCases.count)
        #expect(audit.cells == Self.everyRungWholeSpace)
    }
}
