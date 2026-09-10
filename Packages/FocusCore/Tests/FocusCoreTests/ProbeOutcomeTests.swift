import Foundation
import Testing

@testable import FocusCore

/// **One way for every probe in the gate to say NOT TAKEN** (focus-rxc).
///
/// Three rounds, three probes, one shape: an assertion whose subject was a reading the machine
/// could legitimately not take, reported as a **failed assertion**. The sensing seed, then the undo
/// probe, then `NudgePanelTests.showingTakesNothing` — each fixed on its own, and the shape came
/// back the next round because what was fixed was the probe rather than the vocabulary.
///
/// The vocabulary is the fix. `Bool` has two values and the situation has three, so a guard that
/// correctly refuses to claim a proof from an unmade measurement has only `false` left to refuse
/// it with — and `false` is the defect's value. Everything below is about keeping those three
/// values distinct.
@Suite("A reading that could not be taken reads as NOT TAKEN, not as a failure")
struct ProbeOutcomeTests {
    /// The property the whole type exists for. `notTaken` is not a failure, and it is not a pass
    /// either — it must be distinguishable from both, or the next round reinvents this.
    @Test("not taken is neither the defect nor a measurement")
    func notTakenIsNeitherPassNorFail() {
        let notTaken = ProbeOutcome.notTaken(.frontmostApplicationUnavailable)
        #expect(!notTaken.isBroken, "an unmade measurement was reported as the defect")
        #expect(!notTaken.wasTaken, "an unmade measurement was reported as a measurement")

        #expect(ProbeOutcome.holds.wasTaken)
        #expect(!ProbeOutcome.holds.isBroken)

        #expect(ProbeOutcome.broken("the panel took the front").isBroken)
        #expect(ProbeOutcome.broken("the panel took the front").wasTaken)
    }

    /// **`isBroken` is the only thing a call site asserts on**, so it is the only thing that can
    /// turn a run red. If `notTaken` ever satisfied it, this whole exercise would have moved the
    /// defect rather than fixed it.
    @Test("only a measured falsehood can fail a run", arguments: ReadingObstacle.allCases)
    func onlyAMeasuredFalsehoodFails(obstacle: ReadingObstacle) {
        #expect(!ProbeOutcome.notTaken(obstacle).isBroken)
    }

    /// A NOT TAKEN run has to be **loud**. The whole risk of a third value is that it becomes a
    /// way to make an inconvenient assertion go quiet, so the banner is a fixed, greppable string
    /// that a reader of the stage log finds by searching — and the two outcomes that *were*
    /// measured have none, so a clean run's log contains no such line at all.
    @Test("a not-taken outcome carries a greppable banner and a measured one does not")
    func notTakenIsLoud() {
        for obstacle in ReadingObstacle.allCases {
            let banner = ProbeOutcome.notTaken(obstacle).banner
            #expect(banner != nil, "a reading nobody took said nothing about it")
            #expect(banner?.hasPrefix("NOT TAKEN [") == true)
            #expect(banner?.contains(obstacle.rawValue) == true)
            #expect(banner?.contains(obstacle.sentence) == true)
        }
        #expect(ProbeOutcome.holds.banner == nil)
        #expect(ProbeOutcome.broken("anything").banner == nil)
    }

    /// Every obstacle names itself. A NOT TAKEN reading that did not say *which* reading was not
    /// taken would be the same absence in a new costume.
    @Test("every obstacle has a distinct sentence naming it")
    func everyObstacleNamesItself() {
        let sentences = Set(ReadingObstacle.allCases.map(\.sentence))
        #expect(sentences.count == ReadingObstacle.allCases.count)
        #expect(!sentences.contains(""))
        let identifiers = Set(ReadingObstacle.allCases.map(\.rawValue))
        #expect(identifiers.count == ReadingObstacle.allCases.count)
    }

    /// The summary is what a failure message prints, so the measured falsehood has to arrive
    /// intact rather than as a category name.
    @Test("the summary carries the reason a probe was broken")
    func theSummaryCarriesTheReason() {
        #expect(ProbeOutcome.broken("the panel became key").summary == "the panel became key")
        #expect(
            ProbeOutcome.notTaken(.noDisplayAttached).summary
                .hasPrefix("NOT TAKEN: ")
        )
    }

    /// The same shape `SelfCheck` already publishes for its own unmade readings, so a probe's
    /// outcome and a self-check's reading are read the same way by whoever is reading the
    /// evidence.
    @Test("a not-taken outcome serialises as not taken, never as a value")
    func itSerialisesAsNotTaken() {
        let report = ProbeOutcome.notTaken(.noKeyWindow).dictionary
        #expect(report["wasTaken"] as? Bool == false)
        #expect(report["holds"] as? Bool == false)
        #expect(report["notTakenBecause"] as? String == ReadingObstacle.noKeyWindow.rawValue)

        let held = ProbeOutcome.holds.dictionary
        #expect(held["wasTaken"] as? Bool == true)
        #expect(held["holds"] as? Bool == true)
        #expect(held["notTakenBecause"] as? String == "")
    }
}
