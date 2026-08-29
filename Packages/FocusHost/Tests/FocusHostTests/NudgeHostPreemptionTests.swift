import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **A preemption that reached nobody must not spend the one ask** (focus-7w3, R-84a, U-1).
///
/// ## The defect these drive
///
/// `NudgeHost.accuse(…)` began `if let preempted { close(preempted) }`, and closing meant
/// *settling*: the receipt went in with `ending: .preempted`, which `QuestionEnding` allows to end
/// the asking, so gate 11 refused the question for the life of the commitment. It ran on the first
/// line — before the function knew whether a surface was available, before the panel's actions
/// were checked for reach, before the notification had been delivered or suppressed — and nothing
/// anywhere compared the accusation's subject with the question's.
///
/// R-84a's argument for settling is that the person was handed something **richer** about the
/// **same subject**. The repair makes that a precondition the code checks, and these drive the
/// real loop rather than the pure rule: `PreemptionCreditTests` covers the table, and this covers
/// the host actually consulting it.
@MainActor
struct NudgeHostPreemptionTests {
    static let subject = NudgeHostFixture.decoy

    /// The control, and it has to come first: if an ordinary preemption stopped settling, the
    /// repair would be a regression rather than a fix.
    @Test(
        "a delivered accusation about the same subject still settles the question it displaced",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func theJustifiedPreemptionStillSettles() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        // **Climb to the panel rung first**, because the ladder's entry rung is the menu-bar
        // glyph and a glyph is not the richer affordance R-84a's argument rests on. One
        // unrelated judgement delivers `ambient`; the next reaches `panel`, which is the rung
        // that draws the whole correction ladder with "this is relevant" on it.
        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        // The person asks for their screen back. This releases the slot so a question can be
        // admitted, and — unlike a session ending — leaves the ladder where it climbed to, which
        // is the state a real second escalation arrives in.
        fixture.host.hideOverlays()

        // Now the question, on the panel.
        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        #expect(fixture.panel.isVisible, "no question was on screen to displace")

        // The same subject, escalated onto the panel. This is the one path R-84a describes.
        fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        guard case .accuse(_, .surface(.panel), _) = fixture.host.lastDecision else {
            Issue.record(
                "the accusation did not reach the panel: \(String(describing: fixture.host.lastDecision))"
            )
            return
        }

        #expect(fixture.host.lastPreemptionCredit == .credited)
        let receipts = try fixture.receipts()
        let settled = receipts.filter(\.outcome.settlesTheQuestion)
        #expect(
            settled.count == 1,
            "the question the accusation replaced was not settled: \(receipts.map(\.outcome))"
        )
    }

    /// **The ordinary case, and the one the task is about.**
    ///
    /// No contrivance is needed: the ladder's entry rung is `ambient`, which is the menu-bar
    /// glyph. So the *most common* preemption of all replaces a panel carrying a question with a
    /// tint in the menu bar — and it settled the question, permanently, every time. That is the
    /// burn U-1 names arriving through the most ordinary route there is.
    @Test(
        "the ordinary preemption onto the menu-bar glyph does not settle the question",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func anUndeliveredAccusationDoesNotSettle() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        #expect(fixture.panel.isVisible, "no question was on screen to displace")

        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
        NudgeHostFixture.settle()

        guard case .accuse(_, .surface(.menuBar), _) = fixture.host.lastDecision else {
            Issue.record(
                "this test is about the glyph: \(String(describing: fixture.host.lastDecision))"
            )
            return
        }
        #expect(
            fixture.host.lastPreemptionCredit == .surfaceOffersNoCorrection,
            "credit: \(String(describing: fixture.host.lastPreemptionCredit))"
        )
        let receipts = try fixture.receipts()
        #expect(
            receipts.allSatisfy { !$0.outcome.settlesTheQuestion },
            "an accusation nobody saw spent the one ask: \(receipts.map(\.outcome))"
        )
        let settling = try fixture.ledger.settledReceipt(
            priorityID: fixture.priorityID, subjectKind: .app, subject: Self.subject
        )
        #expect(
            settling == nil,
            "the question was silenced by a preemption the person never saw (U-1)"
        )
    }

    /// The subject clause, at the level the running loop can actually reach it.
    ///
    /// An accusation about a **different** application cannot arrive on the panel on its first
    /// appearance: the ladder is keyed to the mandate, so a new subject re-enters at `ambient`.
    /// Both clauses therefore refuse it, and which one gets there first is not a claim worth
    /// making — `PreemptionCreditTests` drives the subject clause on its own, over the whole
    /// cross product, where it can be isolated. What is asserted here is the behaviour: a
    /// question about one application is not settled by an accusation about another.
    @Test(
        "an accusation about a different subject does not settle the question",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func anAccusationAboutSomethingElseDoesNotSettle() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        #expect(fixture.panel.isVisible, "no question was on screen to displace")

        fixture.host.consider(
            NudgeHostFixture.unrelatedJudgement(subject: "com.apple.Safari")
        )
        NudgeHostFixture.settle()

        #expect(
            fixture.host.lastPreemptionCredit != .credited,
            "credit: \(String(describing: fixture.host.lastPreemptionCredit))"
        )
        let settling = try fixture.ledger.settledReceipt(
            priorityID: fixture.priorityID, subjectKind: .app, subject: Self.subject
        )
        #expect(
            settling == nil,
            "a question about one application was settled by an accusation about another"
        )
    }

    /// **The question's own log row is the one marked dismissed, not the accusation's.**
    ///
    /// Caught by review rather than by a test, which is why there is now a test. Moving the write
    /// to the end of the accusation put it *after* `delivered(surface:rung:priorityID:)`, and
    /// delivery assigns `openRecordID` to the accusation's brand-new row — so completing "the open
    /// record" marked the accusation dismissed the instant it was raised, and left the question's
    /// row open for ever. The row identifier is captured at displacement with everything else.
    @Test(
        "a preemption completes the question's log row and leaves the accusation's open",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func thePreemptionCompletesTheQuestionsOwnRow() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        #expect(fixture.panel.isVisible, "no question was on screen to displace")

        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
        NudgeHostFixture.settle()

        let rows = try fixture.interventions()
        let questions = rows.filter { $0.kindRaw == InterruptionKind.query.rawValue }
        let accusations = rows.filter { $0.kindRaw == InterruptionKind.accusation.rawValue }

        #expect(questions.count == 1, "expected one question row, got \(rows.map(\.kindRaw))")
        #expect(
            questions.first?.outcomeRaw == InterventionOutcome.dismissed.rawValue,
            "the question's row was left open: \(String(describing: questions.first?.outcomeRaw))"
        )
        #expect(
            accusations.allSatisfy { $0.outcomeRaw == nil },
            "the accusation was completed the instant it was raised: \(accusations.map { $0.outcomeRaw })"
        )
    }
}
