import FocusCore
import Foundation
import Testing

@testable import FocusClassify

/// The seam itself: the protocol, the classifier e01 ships, and the encoded shape of an
/// input. The *vocabulary* assertions moved to `FocusCoreTests.VerdictTests` with the types
/// they are about (R-53), and the rule-verdict mapping moved to `FocusRulesTests`.
///
/// What is asserted here that is not asserted there: that the aliases still resolve, so a
/// call site written against `FocusClassify.Verdict` in e01 still compiles and still means
/// the same type.
@Suite("Classification seam")
struct SeamTests {
    @Test("the aliases resolve to the vocabulary FocusCore now owns")
    func aliasesResolveToTheRelocatedTypes() {
        #expect(FocusClassify.Verdict.self == FocusCore.Verdict.self)
        #expect(FocusClassify.VerdictSource.self == FocusCore.VerdictSource.self)
        #expect(FocusClassify.ClassificationOutcome.self == FocusCore.ClassificationOutcome.self)
        #expect(FocusClassify.ClassificationInput.self == FocusCore.ClassificationInput.self)
    }

    @Test("an empty ClassificationInput yields uncertain")
    func emptyInputYieldsUncertain() {
        let classifier = UndecidedClassifier()
        let outcome = classifier.classify(.empty)

        #expect(ClassificationInput.empty.isEmpty)
        #expect(outcome.verdict == .uncertain)
        #expect(outcome.source == .undecided)
        #expect(outcome.confidence == 0)
        #expect(Self.eligibility(for: outcome) == .suppressed(.verdictUncertain))
    }

    /// The e01 assertion, rewritten for the route that replaced the `Bool` (R-55): the
    /// classifier that declines to decide cannot produce a mandate through the only function
    /// that makes one — whatever the drift, the phase, the status or the band beside it.
    @Test("the e01 classifier declines to decide about anything, so the app cannot nudge")
    func undecidedClassifierNeverProducesAMandate() {
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
            #expect(Self.eligibility(for: outcome).mandate == nil)
            #expect(Self.eligibility(for: outcome) == .suppressed(.verdictUncertain))
        }
    }

    /// The most favourable circumstances an interruption could ever have: sustained drift at
    /// the highest band, in focus, not idle, with a priority set. Everything except a verdict
    /// that permits one.
    private static func eligibility(for outcome: ClassificationOutcome) -> InterventionEligibility {
        InterventionEligibility.decide(
            outcome: ClassificationOutcome(
                verdict: outcome.verdict,
                source: outcome.source,
                confidence: outcome.confidence,
                band: .high
            ),
            drift: .sustained(subject: .single("com.apple.Safari"), accumulated: .seconds(600), isMixed: false),
            phase: .focus,
            status: .unrelated,
            isUserIdle: false,
            hasActivePriority: true,
            explanation: Explanation.make(stage: .unresolved, band: .high, clauses: [], stamp: .current),
            stamp: .current
        )
    }

    @Test("the seam is usable purely through the RelevanceClassifier protocol")
    func usableThroughTheProtocol() {
        let classifier: any RelevanceClassifier = UndecidedClassifier()
        #expect(classifier.classify(.empty).verdict == .uncertain)
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
