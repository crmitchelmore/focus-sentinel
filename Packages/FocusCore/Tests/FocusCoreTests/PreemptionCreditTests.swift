import Foundation
import Testing

@testable import FocusCore

/// **A preemption has to earn the right to spend the one ask** (focus-7w3, R-84a, U-1).
///
/// ## The defect these drive
///
/// `QuestionEnding.preempted.settlesTheQuestion` is `true`, and the justification written beside
/// it is R-84a: the app replaced the question with an accusation **about the same subject**, on a
/// surface offering *"this is relevant"* — a strictly richer affordance, so the chance to be
/// taught was escalated rather than lost.
///
/// That justification was enforced **nowhere**. `NudgeHost.accuse(…)` closed the open question on
/// its first line — before it knew whether a surface was available, before the panel's actions
/// were checked for reach, before the notification had been delivered or suppressed — and nothing
/// compared the two subjects. So a preemption that reached nobody still settled the question, and
/// the preemption channel was measured as *more frequent* than the lunch channel it replaced.
///
/// The whole cross product is driven here rather than the interesting corners, because the rule
/// is a pure function and there is no reason to sample it.
struct PreemptionCreditTests {
    static let subject = "com.figma.Desktop"

    /// Every surface, against the two that offer a correction.
    @Test(
        "only a surface that offers a correction can credit a preemption",
        arguments: NudgeSurface.allCases
    )
    func surfaceMustOfferACorrection(surface: NudgeSurface) {
        let credit = PreemptionCredit.decide(
            questionSubject: Self.subject,
            accusationSubject: Self.subject,
            deliveredOn: surface
        )
        if surface.offersACorrection {
            #expect(credit == .credited)
            #expect(PreemptionCredit.ending(for: credit) == .preempted)
        } else {
            #expect(credit == .surfaceOffersNoCorrection)
            #expect(
                PreemptionCredit.ending(for: credit) == .expired,
                "a glyph with nothing on it to press is not a richer affordance"
            )
        }
    }

    /// The panel and the notification draw the rung's actions; the glyph and the badge do not.
    /// Pinned as a table so a surface added later has to state its answer rather than inherit one.
    @Test("which surfaces offer a correction is a committed table")
    func theCorrectionTableIsCommitted() {
        #expect(NudgeSurface.panel.offersACorrection)
        #expect(NudgeSurface.notification.offersACorrection)
        #expect(!NudgeSurface.menuBar.offersACorrection)
        #expect(!NudgeSurface.popoverBadge.offersACorrection)
        #expect(NudgeSurface.allCases.count == 4, "a new surface has no answer here yet")
    }

    /// **The case the whole task is about.** Nothing reached the person, so nothing richer was
    /// offered, so the question is not spent.
    @Test("an accusation that was never delivered credits nothing")
    func anUndeliveredAccusationCreditsNothing() {
        let credit = PreemptionCredit.decide(
            questionSubject: Self.subject,
            accusationSubject: Self.subject,
            deliveredOn: nil
        )
        #expect(credit == .accusationWasNotDelivered)
        #expect(
            PreemptionCredit.ending(for: credit) == .expired,
            "an unseen preemption must not spend the one ask (U-1)"
        )
    }

    @Test("an accusation about something else credits nothing")
    func aDifferentSubjectCreditsNothing() {
        let credit = PreemptionCredit.decide(
            questionSubject: Self.subject,
            accusationSubject: "com.apple.Safari",
            deliveredOn: .panel
        )
        #expect(credit == .aDifferentSubject)
        #expect(PreemptionCredit.ending(for: credit) == .expired)
    }

    /// A mixed accusation names nobody, and `LadderRung.subject` is `nil` for it. Being about
    /// "your afternoon" rather than about the application the question asked about is exactly the
    /// case R-84a's *"about the same subject"* clause excludes.
    @Test("a mixed accusation names nobody and credits nothing", arguments: [nil, ""])
    func aMixedAccusationCreditsNothing(accusationSubject: String?) {
        let credit = PreemptionCredit.decide(
            questionSubject: Self.subject,
            accusationSubject: accusationSubject,
            deliveredOn: .panel
        )
        #expect(credit == .aDifferentSubject)
        #expect(PreemptionCredit.ending(for: credit) == .expired)
    }

    /// The one path that settles, stated on its own so the rule cannot become vacuous: a version
    /// of this that never credited anything would pass every test above.
    @Test("a delivered accusation about the same subject on the panel settles the question")
    func theJustifiedCaseStillSettles() {
        let credit = PreemptionCredit.decide(
            questionSubject: Self.subject,
            accusationSubject: Self.subject,
            deliveredOn: .panel
        )
        #expect(credit == .credited)
        #expect(PreemptionCredit.ending(for: credit) == .preempted)
        #expect(
            QuestionEnding.preempted.settlesTheQuestion,
            "the ending this returns is the one that ends the asking"
        )
        #expect(
            !QuestionEnding.expired.settlesTheQuestion,
            "and the one it returns otherwise is the one that does not"
        )
    }

    /// Exactly one reason credits. A rule that answered `.credited` for two of them would be a
    /// rule with a second way in.
    @Test("only one reason settles")
    func onlyOneReasonSettles() {
        let settling = PreemptionCreditReason.allCases.filter {
            PreemptionCredit.ending(for: $0).settlesTheQuestion
        }
        #expect(settling == [.credited])
    }
}
