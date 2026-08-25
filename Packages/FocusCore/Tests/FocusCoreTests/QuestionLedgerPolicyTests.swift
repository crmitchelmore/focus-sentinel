import Foundation
import Testing

@testable import FocusCore

/// **The burned-question regression, as behaviour rather than as spelling** (U-1, focus-kby).
///
/// ## What this suite replaces, and why the thing it replaces was worthless
///
/// The first fix for "a question nobody could see must never spend the one chance the app gets to
/// ask it" lived as a private method in the application target. No test target can import that
/// target, so the regression test was a **source scan** over `App/*.swift` asserting that certain
/// substrings appeared. An adversarial lens replaced the method's body with `return true` —
/// reinstating every burn path — and all 824 tests stayed green, because the substrings were
/// still spelled exactly as before. A scan for spelling cannot see behaviour.
///
/// So the decision moved into `FocusCore` as a pure function, `QueryLedger` consults it at the
/// write, and this suite instantiates the real thing over its whole input space. Mutate
/// `QuestionLedgerPolicy.decide(…)` to `return .writeReceipt` and `noBurnWithoutAReading` and
/// `everyBurnPathIsClosed` go red on the first cell they reach.
@Suite("A question is written down only if somebody could read it")
struct QuestionLedgerPolicyTests {
    /// Every surface a route can name, plus "it reached none at all".
    static let surfaces: [NudgeSurface?] = [nil] + NudgeSurface.allCases.map { $0 }
    static let readings = SurfaceReadability.allCases
    static let endings = QuestionEnding.allCases

    /// The whole cross product: 5 surfaces × 3 readings at ask × 3 readings now × 3 endings.
    static var everyCell: [(NudgeSurface?, SurfaceReadability, SurfaceReadability, QuestionEnding)] {
        surfaces.flatMap { surface in
            readings.flatMap { atAsk in
                readings.flatMap { now in
                    endings.map { ending in (surface, atAsk, now, ending) }
                }
            }
        }
    }

    static func decide(
        _ surface: NudgeSurface?,
        _ atAsk: SurfaceReadability,
        _ now: SurfaceReadability,
        _ ending: QuestionEnding
    ) -> QuestionLedgerAction {
        QuestionLedgerPolicy.decide(
            surface: surface, readingAtAsk: atAsk, readingNow: now, ending: ending
        )
    }

    // MARK: - The four holes the lens proved, one named cell each

    /// **Hole 1.** A question routed to the popover badge was marked presentable having read
    /// nothing, because the flag was set outside the `if surface == .panel` branch. The popover
    /// opens only on a human click, so the reading at ask for a closed popover is `notReadable`
    /// — and a question that ends there is never written down.
    @Test("a question the popover never showed is not written down when it ends")
    func aBadgeQuestionNobodyOpenedStaysAskable() {
        #expect(
            Self.decide(.popoverBadge, .notReadable, .unknowable, .expired)
                == .stayAskable(.neverReachedAReadableSurface)
        )
        #expect(
            Self.decide(.popoverBadge, .notReadable, .unknowable, .preempted)
                == .stayAskable(.neverReachedAReadableSurface)
        )
        // …and one the person did open, and read, and left open, is.
        #expect(Self.decide(.popoverBadge, .readable, .readable, .expired) == .writeReceipt)
    }

    /// **Hole 2.** `guard panel.isVisible else { return true }` answered *readable* exactly when
    /// the surface had gone. Under default-deny the honest answer is "not proven", so a surface
    /// that cannot be re-read writes nothing.
    @Test("a surface that cannot be re-read is never evidence that it was readable")
    func aSurfaceThatIsGoneProvesNothing() {
        #expect(
            Self.decide(.panel, .readable, .unknowable, .expired)
                == .stayAskable(.readabilityCouldNotBeProven)
        )
        #expect(
            Self.decide(.panel, .unknowable, .unknowable, .expired)
                == .stayAskable(.neverReachedAReadableSurface)
        )
        #expect(
            Self.decide(.panel, .unknowable, .readable, .preempted)
                == .stayAskable(.neverReachedAReadableSurface)
        )
    }

    /// A question can only be carried by a surface that has an answer affordance. The glyph has
    /// none, and *a question is never a notification* (R-82).
    @Test("no receipt for a question routed somewhere it could not have been answered")
    func onlyAQuestionSurfaceCanEndAQuestion() {
        for surface in [NudgeSurface.menuBar, .notification] {
            for ending in [QuestionEnding.expired, .preempted] {
                #expect(
                    Self.decide(surface, .readable, .readable, ending)
                        == .stayAskable(.neverReachedAQuestionSurface)
                )
            }
        }
        #expect(
            Self.decide(nil, .readable, .readable, .expired)
                == .stayAskable(.neverReachedAQuestionSurface)
        )
    }

    /// The panel a person read, still on screen, ended by a preemption or a session end: the
    /// asking happened, and a question whose receipt was never written is a question that comes
    /// back. This is the cell that stops the rule collapsing into "never write anything".
    @Test("a question that was readable at both ends is written down")
    func aReadableQuestionIsRecorded() {
        #expect(Self.decide(.panel, .readable, .readable, .expired) == .writeReceipt)
        #expect(Self.decide(.panel, .readable, .readable, .preempted) == .writeReceipt)
    }

    /// **An answer is its own proof.** A person cannot click a button they cannot see, and this
    /// path writes the learned rule in the same transaction — refusing the receipt here would
    /// leave the app having learned the answer and forgotten the asking (R-78).
    @Test("an answered question is always written down, whatever any instrument says")
    func anAnswerAlwaysCounts() {
        for (surface, atAsk, now, _) in Self.everyCell {
            #expect(
                Self.decide(surface, atAsk, now, .answered) == .writeReceipt,
                "an answer was lost for \(String(describing: surface)) \(atAsk)/\(now)"
            )
        }
    }

    // MARK: - The properties, over the whole cross product

    /// **The burn defence, stated as a property rather than as a list of cells.**
    ///
    /// No unanswered question is ever written down unless *both* readings prove readability.
    /// This is the assertion the `return .writeReceipt` mutation dies on.
    @Test("no unanswered question is written down without two readable readings")
    func noBurnWithoutAReading() {
        for (surface, atAsk, now, ending) in Self.everyCell where ending != .answered {
            let action = Self.decide(surface, atAsk, now, ending)
            guard atAsk == .readable, now == .readable, surface?.canCarryAQuestion == true else {
                #expect(
                    action != .writeReceipt,
                    """
                    a receipt was written about a question on \(String(describing: surface)) \
                    read \(atAsk) at the ask and \(now) at the \(ending)
                    """
                )
                continue
            }
            #expect(action == .writeReceipt)
        }
    }

    /// Every unwritten question is unwritten **for a stated reason**, and every reason is
    /// reachable. A reason no cell produces would be a case somebody could delete without any
    /// test noticing.
    @Test("every reason a question stays askable is reachable, and none is a catch-all")
    func everyBurnPathIsClosed() {
        var seen: Set<QuestionStaysAskableReason> = []
        var receipts = 0
        for (surface, atAsk, now, ending) in Self.everyCell {
            switch Self.decide(surface, atAsk, now, ending) {
            case .writeReceipt: receipts += 1
            case .stayAskable(let reason): seen.insert(reason)
            }
        }

        #expect(seen == Set(QuestionStaysAskableReason.allCases))
        // Non-vacuity in the other direction: the policy is not "never write anything".
        #expect(receipts > 0)
    }

    /// The two surfaces that can carry a question are exactly the two with an answer affordance.
    @Test("panel and popover carry questions; the glyph and the notification do not")
    func questionSurfaces() {
        #expect(NudgeSurface.panel.canCarryAQuestion)
        #expect(NudgeSurface.popoverBadge.canCarryAQuestion)
        #expect(!NudgeSurface.menuBar.canCarryAQuestion)
        #expect(!NudgeSurface.notification.canCarryAQuestion)
    }
}
