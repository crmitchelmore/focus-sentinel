import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **The host presents; the decider decides** (T140, R-84a).
///
/// ## What this replaces
///
/// A source scan. `oneDecisionPath` counted the files containing the string
/// `NudgeDecider.decide(`; `oneCallSite` counted the lines; `hostRunsNoGateItself` looked for
/// seven more strings — `QueryEligibility.decide(`, `SuppressionStack.evaluate(`,
/// `FatigueController.permits(`, `SurfaceRouter.route(` and the rest — and asserted their
/// absence. Every one of those is a statement about spelling. A host that re-derived a gate
/// under a different name, or reached a different conclusion from the one it was handed, would
/// satisfy all nine of them.
///
/// The claim they were reaching for is behavioural and is checkable: **whatever the host does,
/// it is what `NudgeDecider.decide(…)` said, for the same inputs.** So the decider is run
/// independently over a cross product and the two answers are compared, and then the effects are
/// compared against the decision's own kind.
///
/// The structural half — that no file in the shipping graph *constructs* a `QueryWarrant`, an
/// `InterventionMandate` or a `LadderRung` outside their one producer — stays where a
/// source-level claim belongs: `check-forbidden.sh`'s R-96a/b/c, which counts files across `App`
/// and `Packages` and fails the gate on a second one.
@Suite("The host takes the decider's answer and no other", .serialized)
@MainActor
struct NudgeHostDecisionPathTests {
    /// The memory the host would have read, read the same way from the same stores.
    static func memory(_ fixture: NudgeHostFixture, subject: QuerySubject?) throws -> NudgeMemory {
        try NudgeMemory.reading(
            ledger: fixture.ledger,
            log: fixture.log,
            priorityID: fixture.priorityID,
            subject: subject,
            slot: fixture.host.slot,
            fatigue: fixture.host.fatigue.state,
            snoozes: fixture.host.snoozes,
            correctedSubjects: fixture.host.correctedSubjects,
            ladder: fixture.host.ladder
        )
    }

    /// Every verdict the loop can be handed, named so a failure says which one.
    ///
    /// A `nonisolated` list of names rather than a list of judgements, because the argument set
    /// of a parameterised test is evaluated outside the actor and the judgements are built on it.
    nonisolated static let cases = [
        "relevant",
        "uncertain",
        "uncertain, no subject",
        "unrelated, sustained",
        "uncertain, undwelled"
    ]

    static func judgement(_ name: String) -> NudgeJudgement {
        switch name {
        case "relevant": relevantJudgement(subject: "com.example.Editor")
        case "uncertain": NudgeHostFixture.uncertainJudgement(subject: "com.example.Reader")
        case "uncertain, no subject": NudgeHostFixture.uncertainJudgement(subject: nil)
        case "unrelated, sustained": NudgeHostFixture.unrelatedJudgement(subject: "com.example.Decoy")
        default:
            NudgeHostFixture.uncertainJudgement(subject: "com.example.Reader", dwelled: .seconds(1))
        }
    }

    static func relevantJudgement(subject: String) -> NudgeJudgement {
        let outcome = ClassificationOutcome(
            verdict: .relevant, source: .heuristic, confidence: 1, band: .high
        )
        let explanation = Explanation.make(
            stage: .heuristic, band: .high, clauses: [.similarityCorroborated], stamp: .current
        )
        let eligibility = InterventionEligibility.decide(
            outcome: outcome,
            drift: .aligned,
            phase: .focus,
            status: .relevant,
            isUserIdle: false,
            hasActivePriority: true,
            explanation: explanation,
            stamp: .current
        )
        return NudgeJudgement(
            outcome: outcome,
            uncertainty: nil,
            subject: subject,
            dwelled: .seconds(120),
            snapshot: VerdictSnapshot(
                status: .relevant,
                stage: .heuristic,
                band: .high,
                drift: .aligned,
                eligibility: eligibility,
                explanation: explanation,
                stampKey: EngineStamp.current.cacheKey
            ),
            stamp: .current
        )
    }

    @Test(
        "the host's answer is the decider's answer, for every verdict the loop can be handed",
        arguments: NudgeHostDecisionPathTests.cases
    )
    func theHostReachesTheDecidersConclusion(name: String) throws {
        let judgement = Self.judgement(name)
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        // **The item is in the menu bar, exactly as the shipping app has it** (focus-1b5).
        // The ambient rung *is* the status item: with no item installed there is nothing for it
        // to change, `MenuBarController.redraw(force:)` refuses to write to an item nobody can
        // see (F-163), and the loop correctly charges nothing. A fixture without one drives an
        // app whose menu bar is not there, which is not the state this test is about.
        try fixture.wireMenuBarToTheLoop()

        // What the decider says, computed from the stores before the host touches them.
        let subject = NudgeDecider.querySubject(for: judgement)
        let expected = NudgeDecider.decide(
            judgement,
            surroundings: NudgeHostFixture.surroundings(
                monotonic: fixture.clock.elapsed, commitment: fixture.commitment
            ),
            memory: try Self.memory(fixture, subject: subject),
            preferences: fixture.host.preferences
        )

        fixture.host.consider(judgement)
        NudgeHostFixture.settle()

        #expect(
            fixture.host.lastDecision == expected,
            "\(name): the host concluded something the decider did not"
        )
        #expect(fixture.host.decisionCount == 1)

        // …and what it *did* is what that decision says. A silence writes nothing at all: the
        // app is quiet far more often than it speaks, and a row per silence would drown the
        // record of what it actually did.
        let rows = try fixture.interventions()
        switch expected {
        case .silent:
            #expect(rows.isEmpty, "\(name): a silence was written down")
            #expect(!fixture.panel.isVisible)
            #expect(fixture.host.deliveredCount == 0)
            #expect(fixture.host.deferredCount == 0)
        case .deferred:
            #expect(rows.count == 1)
            #expect(rows.first?.dispositionRaw == InterventionDisposition.deferred.rawValue)
        case .ask:
            #expect(rows.count == 1)
            #expect(rows.first?.kindRaw == InterruptionKind.query.rawValue)
        case .accuse:
            #expect(rows.count == 1)
            #expect(rows.first?.kindRaw == InterruptionKind.accusation.rawValue)
        }
    }

    /// **The gate the host must not re-run, made observable.**
    ///
    /// Gate 11 is `hasAsked`, and it is read from the ledger through `NudgeMemory.reading(…)` —
    /// which is the seam. A host that consulted the ledger itself, or that remembered its own
    /// answered subjects, would go on being silent after the receipt was purged. It does not:
    /// the decision follows the store, because the store is where the decision's input comes
    /// from.
    @Test("the host asks again the moment the ledger stops saying it already asked")
    func theHostFollowsTheLedgerRatherThanAMemoryOfItsOwn() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        let subject = "com.example.Reader"

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: subject))
        NudgeHostFixture.settle()
        // "Not now" on purpose: it writes the receipt and **no** rule, so the only thing standing
        // between this subject and a second question is gate 11 itself. "Yes, add it" would also
        // put the subject in the session's corrected set, which is a different gate and would
        // make this test pass for the wrong reason.
        fixture.host.answer(.notNow)
        #expect(try fixture.receipts().count == 1)

        // Past every cooldown the resolution started, so fatigue is not what is speaking here.
        fixture.clock.advance(by: .seconds(3_600))

        // Gate 11 suppresses it, and the host is silent about this subject.
        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: subject))
        #expect(fixture.host.lastDecision?.isSpeaking == false)

        // Take the receipt away — which is what a purge does — and the same host asks again,
        // because it never held an opinion of its own about whether it had asked.
        _ = try fixture.ledger.purge(priorityID: fixture.priorityID)
        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: subject))

        #expect(
            fixture.host.lastDecision?.isSpeaking == true,
            "the host stayed silent about a question the ledger no longer says was asked"
        )
    }
}
