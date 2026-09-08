import Foundation
import Testing
@testable import FocusCore

/// **The tunings table is the policy, at rest** (focus-exdi).
@Suite("Policy tunings")
struct PolicyTuningsTests {
    @Test("untouched, every tuning reads exactly the shipped constant")
    func shippedIsTheConstant() {
        let tunings = PolicyTunings.shipped
        #expect(tunings.isShipped)
        #expect(tunings.duration(.queryDwellThreshold) == InterventionPolicy.queryDwellThreshold)
        #expect(tunings.duration(.queryCooldown) == InterventionPolicy.queryCooldown)
        #expect(tunings.duration(.mandateCooldown) == RelevancePolicy.mandateCooldown)
        #expect(tunings.duration(.escalationDwell) == RelevancePolicy.escalationDwell)
        #expect(tunings.duration(.sustainedDriftThreshold) == RelevancePolicy.sustainedDriftThreshold)
        #expect(tunings.duration(.driftResetGrace) == RelevancePolicy.driftResetGrace)
        #expect(tunings.duration(.lookBackSpan) == RelevancePolicy.lookBackSpan)
        #expect(tunings.duration(.backoffSpan) == InterventionPolicy.backoffSpan)
        #expect(tunings.snoozeDurations == InterventionPolicy.snoozeDurations)
        #expect(tunings.count(.dailyQueryCap) == InterventionPolicy.dailyQueryCap)
        #expect(tunings.count(.dailyQueryCapAllPriorities) == InterventionPolicy.dailyQueryCapAllPriorities)
        #expect(tunings.count(.dailyAccusationCap) == InterventionPolicy.dailyAccusationCap)
        #expect(tunings.count(.dailyInterruptionCap) == InterventionPolicy.dailyInterruptionCap)
        #expect(tunings.count(.reservedAccusationUnits) == InterventionPolicy.reservedAccusationUnits)
        #expect(tunings.count(.ignoredQueryBackoff) == InterventionPolicy.ignoredQueryBackoff)
        #expect(tunings.count(.ignoredAccusationBackoff) == InterventionPolicy.ignoredAccusationBackoff)
        #expect(tunings.count(.maximumLookBackEvents) == RelevancePolicy.maximumLookBackEvents)
        #expect(tunings.count(.minimumTokenLength) == RelevancePolicy.minimumTokenLength)
        #expect(tunings.count(.minimumStrongTokenLength) == RelevancePolicy.minimumStrongTokenLength)
        #expect(tunings.count(.minimumOverlapTokens) == RelevancePolicy.minimumOverlapTokens)
        #expect(tunings.count(.minimumPriorityContentTokens) == RelevancePolicy.minimumPriorityContentTokens)
        #expect(tunings.count(.minimumNegativeBasisItems) == RelevancePolicy.minimumNegativeBasisItems)
        #expect(tunings.count(.maximumExplanationTokens) == RelevancePolicy.maximumExplanationTokens)
        #expect(tunings.count(.similarityCacheCapacity) == RelevancePolicy.similarityCacheCapacity)
        #expect(tunings.value(.similarityRelevantCeiling) == RelevancePolicy.similarityRelevantCeiling.value)
        #expect(tunings.value(.languageConfidenceFloor) == RelevancePolicy.languageConfidenceFloor.value)
    }

    @Test("every tuning's shipped value sits inside its own range, on a positive step")
    func rangesHoldTheirDefaults() {
        for tuning in PolicyTuning.allCases {
            #expect(tuning.range.contains(tuning.shippedValue), "\(tuning.rawValue) ships outside its range")
            #expect(tuning.step > 0, "\(tuning.rawValue) has no step")
            #expect(tuning.clamped(tuning.shippedValue) == tuning.shippedValue, "\(tuning.rawValue) is moved by clamping")
        }
    }

    @Test("a value is clamped into range, and setting the shipped value is not an override")
    func clampingAndIdentity() {
        var tunings = PolicyTunings.shipped
        tunings.set(.dailyQueryCap, to: -5)
        #expect(tunings.count(.dailyQueryCap) == Int(PolicyTuning.dailyQueryCap.range.lowerBound))
        tunings.set(.dailyQueryCap, to: 1_000_000)
        #expect(tunings.count(.dailyQueryCap) == Int(PolicyTuning.dailyQueryCap.range.upperBound))
        #expect(!tunings.isShipped)
        tunings.set(.dailyQueryCap, to: Double(InterventionPolicy.dailyQueryCap))
        #expect(tunings.isShipped, "turning the dial back by hand left an override behind")
        tunings.set(.similarityRelevantCeiling, to: 0.5)
        #expect(tunings.value(.similarityRelevantCeiling) == 0.5)
        tunings.set(.queryDwellThreshold, to: 47.6)
        #expect(tunings.duration(.queryDwellThreshold) == .seconds(48), "a span is kept on whole seconds")
        tunings.resetAll()
        #expect(tunings.isShipped)
    }

    @Test("the table round-trips through Codable")
    func codable() throws {
        var tunings = PolicyTunings.shipped
        tunings.set(.mandateCooldown, to: 900)
        tunings.set(.dailyInterruptionCap, to: 12)
        let data = try JSONEncoder().encode(tunings)
        let back = try JSONDecoder().decode(PolicyTunings.self, from: data)
        #expect(back == tunings)
        #expect(back.duration(.mandateCooldown) == .seconds(900))
    }

    @Test("every family has at least one tuning and every tuning has exactly one family")
    func familiesCoverTheTable() {
        for family in PolicyTuning.Family.allCases {
            #expect(PolicyTuning.allCases.contains { $0.family == family }, "\(family.rawValue) is empty")
        }
        #expect(PolicyTuning.allCases.count == 31)
    }
}
