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
/// `QuestionLedgerPolicy.decide(…)` to `return .settle` and `noBurnWithoutAReading`,
/// `everyBurnPathIsClosed` and `anExpiryIsNotAnAnswer` go red on the first cell they reach.
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
        // …and one the person did open, and read, and left open, is written down — as an
        // asking that happened and was never answered (focus-qds).
        #expect(Self.decide(.popoverBadge, .readable, .readable, .expired) == .recordUnanswered)
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
    }

    /// A question can only be carried by a surface that has an answer affordance. The glyph has
    /// none, and *a question is never a notification* (R-82).
    @Test("no receipt for a question routed somewhere it could not have been answered")
    func onlyAQuestionSurfaceCanEndAQuestion() {
        for surface in [NudgeSurface.menuBar, .notification] {
            // Not `.answered`: a person cannot press an answer on a glyph, so that combination
            // does not arise, and the policy settles on an answer whatever surface it names.
            for ending in [QuestionEnding.expired] {
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

    /// The panel a person read, still on screen, ended by a session end: the asking happened, and
    /// a question whose receipt was never written is a question that comes back. This is the cell
    /// that stops the rule collapsing into "never write anything".
    @Test("a question that was readable at both ends is written down")
    func aReadableQuestionIsRecorded() {
        #expect(Self.decide(.panel, .readable, .readable, .expired) == .recordUnanswered)
        #expect(Self.decide(.panel, .readable, .readable, .answered) == .settle)
    }

    // MARK: - focus-qds · what each ending means for askability

    /// **An expiry is not an answer** (focus-qds, U-1).
    ///
    /// The regression this epic introduced, at the level it was introduced: wiring
    /// `sessionEnded()`, `phaseLeftFocus()` and `priorityChanged()` gave the expiry path its
    /// first callers, and the policy settled on it. Taking a break therefore answered a
    /// question the person never answered, permanently, because the receipt is immutable and
    /// gate 11 reads it before any warrant is built.
    ///
    /// Written down and **not** settled is the whole distinction. Mutate
    /// `QuestionEnding.settlesTheQuestion` to `true` for `.expired` and this dies.
    @Test("a question the world ended is recorded and stays askable, whatever the readings")
    func anExpiryIsNotAnAnswer() {
        for (surface, atAsk, now, _) in Self.everyCell {
            let action = Self.decide(surface, atAsk, now, .expired)
            #expect(
                !action.settlesTheQuestion,
                """
                an expiry settled a question on \(String(describing: surface)) \
                read \(atAsk) at the ask and \(now) at the end
                """
            )
        }
        // Non-vacuous in the other direction: the asking is still written down when somebody
        // could read it, so the day's record is not silently short of an interruption.
        #expect(Self.decide(.panel, .readable, .readable, .expired).writesAReceipt)
    }

    /// **The one ending that settles a question is the person answering it** (U-2).
    ///
    /// There were two. The other was a preemption, on the argument that the app had replaced the
    /// question with an accusation about the same subject offering a richer correction — and that
    /// argument justified spending somebody's single licensed interruption on a question they had
    /// not answered. U-2 deleted the mechanism, so the vocabulary is two endings and exactly one
    /// of them settles.
    @Test("only an answer settles a question")
    func theEndingsThatSettle() {
        #expect(QuestionEnding.allCases.count == 2)
        #expect(QuestionEnding.answered.settlesTheQuestion)
        #expect(!QuestionEnding.expired.settlesTheQuestion)
        #expect(QuestionEnding.allCases.filter(\.settlesTheQuestion) == [.answered])

        #expect(Self.decide(.panel, .readable, .readable, .answered).settlesTheQuestion)
    }

    /// The store-level half of the same ruling, on the value gate 11 actually reads.
    ///
    /// `QueryLedger.isSettled(…)` reads the receipt's **outcome**, not the branch that wrote it,
    /// so the two vocabularies have to agree — and this is where they are checked against each
    /// other rather than in a comment.
    @Test("the outcomes that settle are exactly the three a person can produce")
    func theOutcomesThatSettle() {
        #expect(AskedQuestionOutcome.answeredRelevant.settlesTheQuestion)
        #expect(AskedQuestionOutcome.answeredUnrelated.settlesTheQuestion)
        #expect(AskedQuestionOutcome.declined.settlesTheQuestion)
        #expect(!AskedQuestionOutcome.expired.settlesTheQuestion)
        #expect(
            AskedQuestionOutcome.allCases.filter(\.settlesTheQuestion).count == 3,
            "a new outcome arrived without a ruling on what it means for askability"
        )
    }

    /// **An answer is its own proof.** A person cannot click a button they cannot see, and this
    /// path writes the learned rule in the same transaction — refusing the receipt here would
    /// leave the app having learned the answer and forgotten the asking (R-78).
    @Test("an answered question is always written down, whatever any instrument says")
    func anAnswerAlwaysCounts() {
        for (surface, atAsk, now, _) in Self.everyCell {
            #expect(
                Self.decide(surface, atAsk, now, .answered) == .settle,
                "an answer was lost for \(String(describing: surface)) \(atAsk)/\(now)"
            )
        }
    }

    // MARK: - The properties, over the whole cross product

    /// **The burn defence, stated as a property rather than as a list of cells.**
    ///
    /// No unanswered question is ever written down unless readability was **proven** at the ask
    /// and proven at the end — where *proven at the end*, for a surface that cannot be re-read,
    /// is the reading it already gave. This is the assertion the `return .writeReceipt` mutation
    /// dies on.
    ///
    /// **The second clause is focus-gmr and it is not a loosening of the first.** The reading at
    /// the ask is `.readable` only when the host watched the popover open and watched it draw
    /// this question; the surface column says whether a *second* look at that surface is a thing
    /// that exists. A transient `NSPopover` has no second state — it is drawing the question or
    /// it is gone — so demanding one demanded evidence the surface cannot produce, and the whole
    /// quiet route recorded no unanswered asking ever.
    @Test("no unanswered question is written down without a proven reading at each end")
    func noBurnWithoutAReading() {
        var written = 0
        var refused = 0
        for (surface, atAsk, now, ending) in Self.everyCell where ending != .answered {
            let action = Self.decide(surface, atAsk, now, ending)
            let carriesIt = surface?.canCarryAQuestion == true
            // A second reading is required exactly where a second reading is possible.
            let provenAtTheEnd = now == .readable
                || (carriesIt && surface?.canBeReReadAtTheEnd == false)
            guard atAsk == .readable, carriesIt, provenAtTheEnd else {
                #expect(
                    !action.writesAReceipt,
                    """
                    a receipt was written about a question on \(String(describing: surface)) \
                    read \(atAsk) at the ask and \(now) at the \(ending)
                    """
                )
                refused += 1
                continue
            }
            #expect(action.writesAReceipt)
            written += 1
        }
        // Non-vacuity in both directions: a policy that wrote everything and one that wrote
        // nothing would each satisfy an implication written only one way round.
        #expect(written > 0, "no cell in the whole grid wrote a receipt, so this proves nothing")
        #expect(refused > 0, "every cell wrote a receipt, so this proves nothing")
    }

    /// **focus-gmr: the badge records an unanswered asking, and the panel still needs its second
    /// look.**
    ///
    /// The two halves of the rule at their two extremes, so the surface column cannot be deleted
    /// without a named failure. Driven at `readingNow == .unknowable`, which is what a shut
    /// popover and a hidden panel both give.
    @Test("a transient surface's proven reading is the only reading it will ever give")
    func theBadgeRecordsWhatItReallyShowed() {
        // The badge: proven on screen at the ask, popover shut by the time the break arrives.
        #expect(
            Self.decide(.popoverBadge, .readable, .unknowable, .expired) == .recordUnanswered,
            "a question the person opened the popover onto and read left no receipt at all"
        )
        // And it still stays askable — an expiry is not an answer (focus-qds).
        #expect(!Self.decide(.popoverBadge, .readable, .unknowable, .expired).settlesTheQuestion)
        // A badge question that was never shown is still written down as nothing.
        #expect(
            Self.decide(.popoverBadge, .unknowable, .unknowable, .expired)
                == .stayAskable(.neverReachedAReadableSurface)
        )
        // The panel is sticky, so it can be re-read and must be: a panel whose answers went off
        // an edge is a question that was not readable at the end, and nothing is written.
        #expect(
            Self.decide(.panel, .readable, .notReadable, .expired)
                == .stayAskable(.readabilityCouldNotBeProven)
        )
        #expect(
            Self.decide(.panel, .readable, .unknowable, .expired)
                == .stayAskable(.readabilityCouldNotBeProven)
        )
        // The column itself, read off the surfaces rather than off a list written here.
        #expect(NudgeSurface.panel.canBeReReadAtTheEnd)
        #expect(!NudgeSurface.popoverBadge.canBeReReadAtTheEnd)
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
            case .settle, .recordUnanswered: receipts += 1
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
