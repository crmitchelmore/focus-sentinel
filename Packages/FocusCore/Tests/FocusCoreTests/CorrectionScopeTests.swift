import Foundation
import Testing

@testable import FocusCore

/// What each click writes, and the rule that a correction can never name a subject the
/// judgement did not use (R-86, F-51, F-60, F-62, F-64).
@Suite("Correction scope")
struct CorrectionScopeTests {
    static let stamp = EngineStamp.current
    static let instant = Date(timeIntervalSince1970: 1_767_225_600)

    static func explanation(
        _ clauses: [ExplanationClause], band: EvidenceBand = .medium
    ) -> Explanation {
        Explanation.make(stage: .heuristic, band: band, clauses: clauses, stamp: stamp)
    }

    static func mandate(
        subject: String = "com.chrismitchelmore.FocusDecoy",
        isMixed: Bool = false
    ) -> InterventionMandate {
        let eligibility = InterventionEligibility.decide(
            outcome: ClassificationOutcome(
                verdict: .unrelated, source: .heuristic, confidence: 1, band: .medium
            ),
            drift: .sustained(
                subject: isMixed ? .mixed : .single(subject),
                accumulated: .seconds(120),
                isMixed: isMixed
            ),
            phase: .focus,
            status: .unrelated,
            isUserIdle: false,
            hasActivePriority: true,
            explanation: explanation([.sustainedDwell(seconds: 120)]),
            stamp: stamp
        )
        guard let mandate = eligibility.mandate else {
            fatalError("e04's producer refused to mandate on inputs that must mandate")
        }
        return mandate
    }

    static func warrant(
        subject: String = "com.chrismitchelmore.FocusDecoy2",
        reason: QueryableUncertainty = .noNegativeBasis,
        clauses: [ExplanationClause] = [.noNegativeBasis]
    ) -> QueryWarrant {
        let eligibility = QueryEligibility.decide(
            outcome: ClassificationOutcome(
                verdict: .uncertain, source: .heuristic, confidence: 0, band: .low
            ),
            uncertainty: reason.reason,
            drift: .sustained(subject: .single(subject), accumulated: .seconds(60), isMixed: false),
            dwelled: .seconds(60),
            dwellSatisfied: true,
            phase: .focus,
            status: .uncertain,
            isUserIdle: false,
            hasActivePriority: true,
            hasAsked: false,
            budgetPermits: true,
            interruptionInFlight: false,
            judgedSubject: subject,
            explanation: explanation(clauses, band: .low),
            stamp: stamp
        )
        guard let warrant = eligibility.warrant else {
            fatalError("the query producer refused to warrant on inputs that must warrant")
        }
        return warrant
    }

    // MARK: - The scope comes from the judgement and from nowhere else

    /// **The claim this suite exists for.** Over every shape either authorisation can take, the
    /// scope's subject is one the judgement itself carried — never a third value invented on
    /// the way to the rules store.
    @Test("a correction never names a subject the judgement did not use")
    func neverInventsASubject() {
        let subjects = [
            "com.chrismitchelmore.FocusDecoy",
            "com.apple.Safari",
            "https://docs.google.com",
            "https://news.example.com:8443"
        ]

        for subject in subjects {
            let mandate = Self.mandate(subject: subject)
            if let scope = CorrectionScope.from(mandate) {
                #expect(
                    scope.subject == mandate.subject,
                    "an accusation's correction named \(scope.subject), not \(mandate.subject)"
                )
            }

            let warrant = Self.warrant(subject: subject)
            let scope = CorrectionScope.from(warrant)
            #expect(
                scope.subject == warrant.subject.identifier,
                "a question's answer named \(scope.subject), not \(warrant.subject.identifier)"
            )
            #expect(scope.kind == warrant.subject.kind)
        }
    }

    /// A mixed mandate has no single subject, so "this is relevant" has nothing to be about and
    /// is not offered. Taking the last application would be the app writing a durable rule
    /// about something the person never pointed at.
    @Test("a mixed mandate yields no scope, and the actions that need one write nothing")
    func mixedMandateYieldsNoScope() {
        let mixed = Self.mandate(isMixed: true)
        #expect(mixed.isMixed)
        #expect(CorrectionScope.from(mixed) == nil)

        for action in CorrectionAction.allCases where action.requiresScope {
            #expect(
                action.outcome(scope: nil, at: Self.instant) == .nothing,
                "\(action.rawValue) wrote something with no subject to write about"
            )
        }
    }

    /// A question can never be mixed — `QuerySubject` has no such case and the producer
    /// withholds instead — so `from(_ warrant:)` is not optional and cannot be.
    @Test("a question's scope is never absent")
    func aQuestionAlwaysHasAScope() {
        for reason in QueryableUncertainty.allCases {
            let scope = CorrectionScope.from(Self.warrant(reason: reason))
            #expect(!scope.subject.isEmpty)
        }
    }

    /// The baseline is app-wide and e07's narrowing arrives with no change to this type: an
    /// origin subject already bands `.domain`.
    @Test("the scope's narrowness is read from the subject's shape")
    func scopeKind() throws {
        let app = try #require(CorrectionScope.from(Self.mandate(subject: "com.apple.Safari")))
        #expect(app.kind == .app)

        let origin = try #require(
            CorrectionScope.from(Self.mandate(subject: "https://docs.google.com"))
        )
        #expect(origin.kind == .domain)
    }

    @Test("a scope writes one rule shape, whatever surface it came from")
    func scopeWritesOneRuleShape() throws {
        let scope = try #require(CorrectionScope.from(Self.mandate()))
        let identifier = UUID()
        let rule = scope.rule(
            verdict: .relevant, authority: .task, at: Self.instant, id: identifier
        )
        #expect(rule.id == identifier)
        #expect(rule.authority == .task)
        #expect(rule.subjectKind == scope.kind)
        #expect(rule.subject == scope.subject)
        #expect(rule.verdict == .relevant)
        #expect(rule.createdAt == Self.instant)
    }

    // MARK: - Totality over the two action vocabularies

    @Test("there are exactly three answers, and every one has a receipt")
    func queryAnswerTotality() {
        #expect(QueryAnswer.allCases.count == 3)
        #expect(Set(QueryAnswer.allCases) == [.yesAddIt, .no, .notNow])

        var outcomes: Set<AskedQuestionOutcome> = []
        for answer in QueryAnswer.allCases {
            #expect(outcomes.insert(answer.outcome).inserted, "two answers share a receipt")
        }
        #expect(QueryAnswer.yesAddIt.outcome == .answeredRelevant)
        #expect(QueryAnswer.no.outcome == .answeredUnrelated)
        #expect(QueryAnswer.notNow.outcome == .declined)

        #expect(QueryAnswer.yesAddIt.ruleVerdict == .relevant)
        #expect(QueryAnswer.no.ruleVerdict == .unrelated)
        #expect(QueryAnswer.notNow.ruleVerdict == nil)
    }

    /// **R-78's atomic pair, and the one action whose transaction has a single row.**
    @Test("yes and no each write one transaction of two records; not now writes only the receipt")
    func answersWriteTheRightTransaction() throws {
        let scope = CorrectionScope.from(Self.warrant())

        let yes = QueryAnswer.yesAddIt.outcome(scope: scope, at: Self.instant)
        #expect(yes.isAtomicPair)
        let yesRule = try #require(yes.persistedRule)
        #expect(yesRule.verdict == .relevant)
        #expect(yesRule.authority == .task)
        #expect(yesRule.subject == scope.subject)
        #expect(yes.receipt == .answeredRelevant)

        let no = QueryAnswer.no.outcome(scope: scope, at: Self.instant)
        #expect(no.isAtomicPair)
        #expect(try #require(no.persistedRule).verdict == .unrelated)
        #expect(no.receipt == .answeredUnrelated)

        let notNow = QueryAnswer.notNow.outcome(scope: scope, at: Self.instant)
        #expect(!notNow.isAtomicPair)
        #expect(notNow.persistedRule == nil, "\"Not now\" wrote a rule")
        #expect(notNow.receipt == .declined)
        #expect(notNow == .receiptOnly(.declined))
    }

    @Test("there are exactly seven correction actions and every one writes exactly one thing")
    func correctionActionTotality() throws {
        #expect(CorrectionAction.allCases.count == 7)
        #expect(
            Set(CorrectionAction.allCases) == [
                .thisIsRelevant, .notThisTime, .snooze, .changePriority, .pause,
                .returnToTask, .dismiss
            ]
        )

        let scope = try #require(CorrectionScope.from(Self.mandate()))
        var outcomes: [CorrectionAction: CorrectionOutcome] = [:]
        for action in CorrectionAction.allCases {
            outcomes[action] = action.outcome(scope: scope, at: Self.instant)
        }

        // "This is relevant": a persisted task-authority rule, and nothing else.
        let relevant = try #require(outcomes[.thisIsRelevant])
        #expect(try #require(relevant.persistedRule).authority == .task)
        #expect(try #require(relevant.persistedRule).verdict == .relevant)
        #expect(relevant.receipt == nil, "an accusation's correction wrote a query receipt")

        // "Not this time": a session-lived rule that is deliberately NOT persisted.
        let session = try #require(outcomes[.notThisTime])
        #expect(session.persistedRule == nil, "a session rule reached the persisted store")
        if case .sessionRule(let rule) = session {
            #expect(rule.authority == .session)
        } else {
            Issue.record("\"Not this time\" did not write a session rule")
        }

        // Snooze: subject-scoped, and the shortest span unless the person chose another.
        #expect(
            outcomes[.snooze]
                == .snooze(
                    subject: scope.subject,
                    duration: try #require(InterventionPolicy.snoozeDurations.first)
                )
        )
        #expect(
            CorrectionAction.snooze.outcome(
                scope: scope, at: Self.instant, snoozeDuration: .seconds(900)
            ) == .snooze(subject: scope.subject, duration: .seconds(900))
        )

        // The three that need no subject.
        #expect(outcomes[.changePriority] == .priorityChangeRequested)
        #expect(outcomes[.pause] == .pause(try #require(InterventionPolicy.pauseDurations.first)))
        #expect(outcomes[.returnToTask] == .returnToTask)

        // **Zero coercion**: every surface is dismissible, and dismissing writes nothing.
        #expect(outcomes[.dismiss] == .nothing)
    }

    /// De-escalation is immediate and total on every correction. Only a dismissal leaves the
    /// ladder where it was — the person closed a window, they did not tell the app anything.
    @Test("every action but a dismissal ends the ladder")
    func actionsDeEscalate() {
        for action in CorrectionAction.allCases where action != .dismiss {
            #expect(action.deEscalation != nil, "\(action.rawValue) does not end the ladder")
        }
        #expect(CorrectionAction.dismiss.deEscalation == nil)
        #expect(CorrectionAction.thisIsRelevant.deEscalation == .corrected)
        #expect(CorrectionAction.notThisTime.deEscalation == .excusedForThisSession)
        #expect(CorrectionAction.returnToTask.deEscalation == .returnedToTask)
    }

    @Test("the two action vocabularies round-trip through Codable on their raw values")
    func codableRoundTrip() throws {
        for answer in QueryAnswer.allCases {
            let data = try JSONEncoder().encode(answer)
            #expect(try JSONDecoder().decode(QueryAnswer.self, from: data) == answer)
        }
        for action in CorrectionAction.allCases {
            let data = try JSONEncoder().encode(action)
            #expect(try JSONDecoder().decode(CorrectionAction.self, from: data) == action)
        }
    }
}
