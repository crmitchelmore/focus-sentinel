import FocusCore
import FocusEvaluateCore
import Foundation
import Testing

/// **The corpus schema, and the two fields e05 added to it** (T143a, T143b, R-94a).
///
/// P-140 enumerated every field of all 165 committed cases and found that `expect` carries the
/// classifier's expected *output* and nothing else — **no field anywhere records what a person
/// would have answered**. That is why `queryRate ≤ 0.17` could never have been a false-positive
/// rate: the ground truth for one did not exist in the file.
///
/// This suite is what stops the same thing happening again. The label is required on every case a
/// question is asked about, forbidden on every case no question is asked about, and the loader
/// fails on either violation — so the awkward cases cannot be quietly skipped and a stray label
/// cannot quietly enter a denominator.
@Suite("Corpus schema")
struct CorpusSchemaTests {
    /// A case as JSON, with whatever the test wants to leave out left out.
    static func caseJSON(
        id: String = "gc-9001",
        uncertaintyReason: String? = "noNegativeBasis",
        verdict: String = "uncertain",
        bundleID: String? = "com.example.subject",
        expectNudge: String? = "ask:noNegativeBasis",
        queryGroundTruth: String? = "relevant"
    ) -> String {
        var fields: [String] = [
            "\"id\": \"\(id)\"",
            "\"note\": \"a case written by this suite to prove the loader refuses it\"",
            "\"priority\": { \"intent\": \"write the quarterly report\", \"revision\": 1 }",
            "\"evidence\": { \(bundleID.map { "\"bundleID\": \"\($0)\"" } ?? "\"titleTokens\": []") }",
            "\"dwellSeconds\": 120",
            "\"sessionPhase\": \"focus\"",
            "\"isUserIdle\": false",
            """
            "expect": { "verdict": "\(verdict)", "source": "heuristic", "stage": "heuristic", \
            "band": \(verdict == "uncertain" ? "null" : "\"high\""), \
            "eligibility": "suppressed:verdictUncertain", "clauses": [], \
            "uncertaintyReason": \(uncertaintyReason.map { "\"\($0)\"" } ?? "null") }
            """
        ]
        if let expectNudge { fields.append("\"expectNudge\": \"\(expectNudge)\"") }
        if let queryGroundTruth { fields.append("\"queryGroundTruth\": \"\(queryGroundTruth)\"") }
        return "{ \(fields.joined(separator: ", ")) }"
    }

    static func decode(_ json: String) throws -> CorpusCase {
        try CorpusCase.decode(
            try StrictObject.parse(data: Data(json.utf8), path: "test"), file: "test"
        )
    }

    // MARK: - The label is required exactly where a question is asked

    /// **The finding-2 guard.** A gate that scored a band on absent data would be a gate reporting
    /// a pass it did not measure, so the omission fails the *load*.
    @Test("an askable, subject-bearing case without a ground truth fails the load")
    func askableWithoutGroundTruthFails() {
        #expect(throws: CorpusDecodingError.self) {
            try Self.decode(Self.caseJSON(queryGroundTruth: nil))
        }
    }

    /// The other direction, and it matters as much: a label on a case nobody asks about is a vote
    /// in a denominator no question ever entered.
    @Test("an unaskable case carrying a ground truth fails the load")
    func unaskableWithGroundTruthFails() {
        #expect(throws: CorpusDecodingError.self) {
            try Self.decode(Self.caseJSON(uncertaintyReason: "noEvidence"))
        }
        #expect(throws: CorpusDecodingError.self) {
            try Self.decode(
                Self.caseJSON(uncertaintyReason: nil, verdict: "relevant", expectNudge: "silent:verdictDoesNotAuthorise")
            )
        }
    }

    /// A subject is what a question is *about*. An activation with neither a bundle identifier nor
    /// an origin is unaskable under R-76's no-subject rule, whatever its uncertainty reason —
    /// e03's P-83 measured six such processes in ninety-two.
    @Test("a case with no subject is unaskable however askable its reason is")
    func noSubjectIsUnaskable() throws {
        let decoded = try Self.decode(
            Self.caseJSON(bundleID: nil, expectNudge: "silent:verdictDoesNotAuthorise", queryGroundTruth: nil)
        )
        #expect(decoded.queryGroundTruth == nil)
        #expect(throws: CorpusDecodingError.self) {
            try Self.decode(Self.caseJSON(bundleID: nil))
        }
    }

    /// `expectNudge` is not optional. A case with no nudge expectation is a case the nudge lane
    /// silently stops asserting anything about.
    @Test("a case without an expectNudge fails the load")
    func missingNudgeExpectationFails() {
        #expect(throws: CorpusDecodingError.self) {
            try Self.decode(Self.caseJSON(expectNudge: nil))
        }
    }

    @Test("an unparseable nudge expectation fails the load rather than defaulting")
    func malformedNudgeExpectationFails() {
        for malformed in ["ask", "aks:noNegativeBasis", "ask:noEvidence", "shout:loudly"] {
            #expect(throws: CorpusDecodingError.self) {
                try Self.decode(Self.caseJSON(expectNudge: malformed))
            }
        }
    }

    // MARK: - The committed corpus itself

    /// Coverage is **1.0**, and the gate reads this rather than assuming it.
    @Test("every askable, subject-bearing committed case carries a ground truth")
    func committedCoverageIsComplete() throws {
        let corpus = try CorpusFixtures.loaded()
        var askable = 0
        for testCase in corpus.cases {
            let subject = testCase.evidence.bundleIdentifier ?? testCase.evidence.origin
            let isAskable = testCase.expect.verdict == .uncertain
                && testCase.expect.uncertaintyReason?.queryable != nil
                && subject != nil
            if isAskable {
                askable += 1
                #expect(
                    testCase.queryGroundTruth != nil,
                    "\(testCase.id) is askable and carries no queryGroundTruth"
                )
            } else {
                #expect(
                    testCase.queryGroundTruth == nil,
                    "\(testCase.id) is not askable and carries a queryGroundTruth"
                )
            }
        }
        // P-138 enumerated forty-seven askable subject-bearing cases across the four committed
        // files; e05 adds one at the dwell boundary. A number that fell would mean the corpus had
        // quietly stopped exercising the affordance U-1 exists to license.
        #expect(askable >= 47, "only \(askable) askable cases — P-138 counted 47")
    }

    /// The three labels are all used. A field with one value in practice is a field that measures
    /// nothing, and `eitherIsReasonable` in particular exists to be used rather than to be
    /// available.
    @Test("all three ground-truth labels appear in the committed corpus")
    func everyLabelIsUsed() throws {
        let corpus = try CorpusFixtures.loaded()
        let labels = Set(corpus.cases.compactMap(\.queryGroundTruth))
        for label in QueryGroundTruth.allCases {
            #expect(labels.contains(label), "no committed case is labelled \(label.rawValue)")
        }
    }

    // MARK: - The nudge expectation agrees with the classification expectation

    /// **U-1's invariant, asserted over the committed file rather than over a run.**
    ///
    /// A corpus that committed `accuse` beside an `uncertain` verdict would be a corpus asserting
    /// the one thing this epic may not do — and it would do it in a file nobody diffs closely.
    @Test("no committed case expects an accusation from anything but an unrelated verdict")
    func noAccusationFromUncertainty() throws {
        let corpus = try CorpusFixtures.loaded()
        for testCase in corpus.cases {
            switch testCase.expectNudge {
            case .accuse:
                #expect(
                    testCase.expect.verdict == .unrelated,
                    "\(testCase.id) expects an accusation from a \(testCase.expect.verdict.rawValue) verdict"
                )
                #expect(
                    testCase.expect.eligibility == .mandated,
                    "\(testCase.id) expects an accusation without a mandate"
                )
            case .ask(let reason):
                #expect(
                    testCase.expect.verdict == .uncertain,
                    "\(testCase.id) expects a question from a \(testCase.expect.verdict.rawValue) verdict"
                )
                let named = testCase.expect.uncertaintyReason?.rawValue ?? "no reason"
                #expect(
                    testCase.expect.uncertaintyReason?.queryable == reason,
                    "\(testCase.id) expects a question about \(reason.rawValue) from \(named)"
                )
            case .silent, .deferred:
                break
            }
        }
    }

    /// R-77's guard, read off the committed file: **`noEvidence` never produces a question.**
    /// "We did not look" must never become "tell us what you were doing."
    @Test("no committed case expects a question from an unaskable uncertainty")
    func noQuestionFromAnUnaskableReason() throws {
        let corpus = try CorpusFixtures.loaded()
        for testCase in corpus.cases where testCase.expectNudge.queryReason != nil {
            let reason = try #require(testCase.expect.uncertaintyReason)
            #expect(
                reason.queryable != nil,
                "\(testCase.id) expects a question about \(reason.rawValue), which R-77 marks unaskable"
            )
        }
    }

    // MARK: - The witnesses `InterventionPolicy` committed before the fixtures existed

    /// R-74.1, applied to e05's manifest: **a witness that was renamed is a witness that was
    /// lost.**
    ///
    /// The ids were allocated in T113, before any of these fixtures existed, precisely so they
    /// could not be chosen after the fact to pass. This is where that promise is checked.
    @Test("every constant InterventionPolicy names a witness for is in the committed corpus")
    func everyInterventionWitnessExists() throws {
        let corpus = try CorpusFixtures.loaded()
        let known = Set(corpus.cases.map(\.id))
            .union(corpus.sequences.map(\.id))
            .union(corpus.days.map(\.id))

        for constant in InterventionPolicy.manifest where !constant.witnesses.isEmpty {
            for witness in constant.witnesses {
                let detail = "\(constant.name) names \(witness), which is in neither the "
                    + "corpus, the sequences nor the days"
                #expect(known.contains(witness), "\(detail)")
            }
        }
    }

    /// Every **behavioural** constant owes a witness, and the manifest is where that is recorded.
    /// Asserted here as well as in `InterventionPolicyTests` because this is the side that can see
    /// whether the fixture is real.
    @Test("every behavioural intervention constant names at least one witness")
    func everyBehaviouralConstantHasAWitness() {
        for constant in InterventionPolicy.manifest where constant.kind == .behavioural {
            #expect(
                !constant.witnesses.isEmpty,
                "\(constant.name) is class B and names no witness"
            )
            #expect(
                !constant.mutations.isEmpty,
                "\(constant.name) is class B and names no mutation value"
            )
        }
    }
}
