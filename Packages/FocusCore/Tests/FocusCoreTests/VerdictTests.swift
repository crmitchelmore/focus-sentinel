import Foundation
import Testing

@testable import FocusCore

/// The classification vocabulary, now that it lives beside the status it mirrors (R-53).
///
/// These assertions travelled here from `FocusClassifyTests.SeamTests` with the types. The
/// seam suite keeps only what is genuinely about the seam — the protocol, the undecided
/// classifier and the encoded shape of an input.
@Suite("Classification vocabulary")
struct VerdictTests {
    @Test("the Verdict enum has exactly three cases")
    func verdictHasThreeCases() {
        #expect(Verdict.allCases.count == 3)
        #expect(Set(Verdict.allCases) == [.relevant, .unrelated, .uncertain])
    }

    @Test("Verdict raw values are stable strings")
    func verdictRawValuesAreStable() {
        #expect(Verdict.relevant.rawValue == "relevant")
        #expect(Verdict.unrelated.rawValue == "unrelated")
        #expect(Verdict.uncertain.rawValue == "uncertain")
    }

    /// Standing condition 6, now that the `Bool` is gone (T82): the verdict enum offers no
    /// projection at all, and the only route to an intervention is a function that returns
    /// before it reads anything else. `InterventionInvariantTests` proves the behaviour over
    /// all 4 320 combinations; this asserts the *shape* — that there is nothing on a `Verdict`
    /// a call site could collapse into a `Bool`.
    @Test("a Verdict offers no boolean projection to collapse")
    func verdictHasNoBooleanProjection() {
        for verdict in Verdict.allCases {
            let mirror = Mirror(reflecting: verdict)
            #expect(mirror.children.isEmpty)
            #expect(!(verdict.rawValue.isEmpty))
        }
    }

    /// `FocusStatus` is the five-case surface vocabulary and `Verdict` the three-case
    /// judgement. The relationship is a superset, and it has to stay one: a verdict this
    /// build can reach with no status to draw it as would be a verdict no surface could show.
    @Test("every Verdict has a FocusStatus of the same name, and the two agree about silence")
    func verdictMapsOntoStatus() {
        for verdict in Verdict.allCases {
            let status = FocusStatus(rawValue: verdict.rawValue)
            #expect(status != nil, "no FocusStatus for \(verdict.rawValue)")
            #expect(status?.permitsIntervention == (verdict == .unrelated))
        }

        // The superset is proper: `paused` and `onBreak` are states of the *session*, not
        // judgements about a context, and no verdict may map onto one.
        let statuses = Set(FocusStatus.allCases.map(\.rawValue))
        let verdicts = Set(Verdict.allCases.map(\.rawValue))
        #expect(verdicts.isSubset(of: statuses))
        #expect(statuses.subtracting(verdicts) == ["paused", "onBreak"])
    }

    @Test("VerdictSource names every producer the cascade can have, including e06's model")
    func verdictSourceCoversEveryProducer() {
        #expect(Set(VerdictSource.allCases) == [.userRule, .heuristic, .onDeviceModel, .undecided])
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

    @Test("the undecided outcome is uncertain, unsourced and carries no confidence")
    func undecidedOutcomeIsFailingClosed() {
        #expect(ClassificationOutcome.undecided.verdict == .uncertain)
        #expect(ClassificationOutcome.undecided.source == .undecided)
        #expect(ClassificationOutcome.undecided.confidence == 0)
    }

    @Test("an empty input carries no evidence at all")
    func emptyInputIsEmpty() {
        #expect(ClassificationInput.empty.isEmpty)
        #expect(ClassificationInput(priorityIntent: "   ").isEmpty)
        #expect(!ClassificationInput(bundleIdentifier: "com.apple.Safari").isEmpty)
    }
}
