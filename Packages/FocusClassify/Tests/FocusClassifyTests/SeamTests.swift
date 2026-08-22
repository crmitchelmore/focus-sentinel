import FocusRules
import Foundation
import Testing

@testable import FocusClassify

@Suite("Classification seam")
struct SeamTests {
    @Test("the Verdict enum has exactly three cases")
    func verdictHasThreeCases() {
        #expect(Verdict.allCases.count == 3)
        #expect(Set(Verdict.allCases) == [.relevant, .unrelated, .uncertain])
    }

    /// Standing condition 6, asserted rather than documented: `uncertain` always suppresses
    /// intervention. If a later epic ever "helpfully" makes a low-confidence uncertain
    /// verdict nudge the user, this test fails.
    @Test("uncertain suppresses intervention, and only unrelated permits it")
    func uncertainSuppressesIntervention() {
        #expect(Verdict.uncertain.permitsIntervention == false)
        #expect(Verdict.relevant.permitsIntervention == false)
        #expect(Verdict.unrelated.permitsIntervention == true)

        for verdict in Verdict.allCases where verdict != .unrelated {
            #expect(verdict.permitsIntervention == false)
        }
    }

    @Test("an empty ClassificationInput yields uncertain")
    func emptyInputYieldsUncertain() {
        let classifier = UndecidedClassifier()
        let outcome = classifier.classify(.empty)

        #expect(ClassificationInput.empty.isEmpty)
        #expect(outcome.verdict == .uncertain)
        #expect(outcome.source == .undecided)
        #expect(outcome.confidence == 0)
        #expect(outcome.verdict.permitsIntervention == false)
    }

    @Test("the e01 classifier declines to decide about anything, so the app cannot nudge")
    func undecidedClassifierNeverPermitsIntervention() {
        let classifier = UndecidedClassifier()
        let inputs = [
            ClassificationInput.empty,
            ClassificationInput(priorityIntent: "finish the plan"),
            ClassificationInput(
                priorityIntent: "finish the plan",
                bundleIdentifier: "com.apple.Safari",
                origin: "https://news.example",
                titleTokens: ["breaking", "news"]
            )
        ]

        for input in inputs {
            let outcome = classifier.classify(input)
            #expect(outcome.verdict == .uncertain)
            #expect(outcome.verdict.permitsIntervention == false)
        }
    }

    @Test("the seam is usable purely through the RelevanceClassifier protocol")
    func usableThroughTheProtocol() {
        let classifier: any RelevanceClassifier = UndecidedClassifier()
        #expect(classifier.classify(.empty).verdict == .uncertain)
    }

    @Test("confidence is clamped to 0...1")
    func confidenceIsClamped() {
        #expect(
            ClassificationOutcome(verdict: .relevant, source: .heuristic, confidence: 4.2)
                .confidence == 1
        )
        #expect(
            ClassificationOutcome(verdict: .relevant, source: .heuristic, confidence: -1)
                .confidence == 0
        )
    }

    @Test("a user's explicit uncertain rule stays uncertain")
    func userUncertaintyIsPreserved() {
        #expect(RuleVerdict.relevant.classificationVerdict == .relevant)
        #expect(RuleVerdict.unrelated.classificationVerdict == .unrelated)
        #expect(RuleVerdict.uncertain.classificationVerdict == .uncertain)
    }

    @Test("ClassificationInput carries only normalised evidence")
    func inputCarriesOnlyNormalisedEvidence() throws {
        // A structural assertion, not a stylistic one: the encoded form of an input has
        // exactly these keys. If someone adds `rawURL`, `screenshot` or `documentText`,
        // this fails and the privacy posture is re-examined rather than eroded.
        let input = ClassificationInput(
            priorityIntent: "ship e01",
            priorityDoneWhen: "gate green",
            bundleIdentifier: "com.apple.dt.Xcode",
            origin: "https://developer.example",
            titleTokens: ["focus", "sentinel"]
        )
        let data = try JSONEncoder().encode(input)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(
            Set(object.keys) == [
                "priorityIntent", "priorityDoneWhen", "bundleIdentifier", "origin",
                "titleTokens"
            ]
        )
    }
}
