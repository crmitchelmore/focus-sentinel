import Foundation
import Testing

@testable import FocusCore

/// The bands are ordinal and nothing else. These assertions are what stop the word
/// "confidence" creeping back onto the intervention path (R-56, F-47).
@Suite("Evidence bands and the reasons for declining")
struct EvidenceBandTests {
    @Test("there are exactly three bands, ordered low < medium < high")
    func bandsAreOrdinal() {
        #expect(EvidenceBand.allCases == [.low, .medium, .high])
        #expect(EvidenceBand.low < EvidenceBand.medium)
        #expect(EvidenceBand.medium < EvidenceBand.high)
        #expect(EvidenceBand.low < EvidenceBand.high)
        #expect(EvidenceBand.allCases.map(\.rank) == [0, 1, 2])
        #expect(EvidenceBand.allCases.max() == .high)
    }

    /// The comparison the eligibility function actually performs, at the value the policy
    /// actually commits. `.low` is *below* the floor; that single fact is what makes a
    /// similarity-only judgement incapable of interrupting anybody.
    @Test("only medium and high reach the intervention floor")
    func lowSortsBelowTheFloor() {
        let floor = EvidenceBand.medium
        #expect(!(EvidenceBand.low >= floor))
        #expect(EvidenceBand.medium >= floor)
        #expect(EvidenceBand.high >= floor)
    }

    /// Reflection over the declaration: a band that carried a `Double` would be a calibration
    /// claim this app cannot support, so the type must have no associated values at all.
    /// A string-raw enum has exactly one child per case and no payload.
    @Test("no band carries a number")
    func noBandCarriesANumber() {
        for band in EvidenceBand.allCases {
            let mirror = Mirror(reflecting: band)
            #expect(mirror.children.isEmpty, "\(band) carries a payload")
            #expect(Double(band.rawValue) == nil)
        }
    }

    @Test("every band carries its own copy key")
    func everyBandHasCopy() {
        let keys = EvidenceBand.allCases.map(\.labelKey)
        #expect(Set(keys).count == keys.count)
        for band in EvidenceBand.allCases {
            #expect(band.labelKey == "evidence.band.\(band.rawValue)")
        }
    }

    @Test("a classification outcome bands as low unless it says otherwise")
    func outcomeBandsLowByDefault() {
        let outcome = ClassificationOutcome(verdict: .unrelated, source: .heuristic, confidence: 1)
        #expect(outcome.band == .low, "the safe default is the band that cannot mandate")
        #expect(ClassificationOutcome.undecided.band == .low)

        let banded = ClassificationOutcome(
            verdict: .unrelated, source: .userRule, confidence: 1, band: .high
        )
        #expect(banded.band == .high)
    }

    @Test("an outcome round-trips through Codable with its band")
    func outcomeRoundTripsWithItsBand() throws {
        for band in EvidenceBand.allCases {
            let outcome = ClassificationOutcome(
                verdict: .relevant, source: .heuristic, confidence: 0.5, band: band
            )
            let decoded = try JSONDecoder().decode(
                ClassificationOutcome.self, from: JSONEncoder().encode(outcome)
            )
            #expect(decoded == outcome)
            #expect(decoded.band == band)
        }
    }

    /// Every route to `uncertain` is named. A reason that cannot be named is a route nobody
    /// can audit, and `evaluation.json` counts these by name.
    @Test("every uncertainty reason is a distinct, stable string")
    func uncertaintyReasonsAreNamed() {
        let raws = UncertaintyReason.allCases.map(\.rawValue)
        #expect(Set(raws).count == raws.count)
        #expect(raws.allSatisfy { !$0.isEmpty })
        #expect(UncertaintyReason.allCases.contains(.noNegativeBasis))
        #expect(UncertaintyReason.allCases.contains(.noEvidence))
        #expect(UncertaintyReason.allCases.contains(.insufficientPriorityEvidence))
    }

    /// The nine of R-55, in the order `decide(…)` evaluates its guards. The order is asserted
    /// because the invariant test predicts a reason from the guard sequence, and a reordered
    /// enum with an unchanged test would be a test that no longer says what it claims.
    @Test("the nine suppression reasons are declared in guard order, each with copy")
    func suppressionReasonsAreCompleteAndOrdered() {
        #expect(SuppressionReason.allCases == [
            .verdictRelevant, .verdictUncertain, .evidenceBandTooLow, .withinGracePeriod,
            .withinMandateCooldown, .sessionPhaseForbids, .statusForbids, .userIdle,
            .noActivePriority
        ])

        let keys = SuppressionReason.allCases.map(\.copyKey)
        #expect(Set(keys).count == keys.count)
        for reason in SuppressionReason.allCases {
            #expect(reason.copyKey == "suppression.reason.\(reason.rawValue)")
        }
    }
}
