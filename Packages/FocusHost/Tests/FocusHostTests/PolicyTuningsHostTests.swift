import FocusCore
import FocusUI
import Foundation
import Testing
@testable import FocusHost

/// **A dial turned in Settings reaches both engines and the store** (focus-exdi).
@Suite("Policy dials through the composition root", .serialized)
@MainActor
struct PolicyTuningsHostTests {
    @Test("turning a dial reaches the nudge loop, the relevance engine and the store; reset clears all three")
    func aDialReachesEverything() throws {
        let root = CompositionRootTests.root()
        defer { root.stop() }
        root.startNudgeLoop()
        #expect(root.nudgeHost.tunings.isShipped)
        #expect(root.relevanceHost.tunings.isShipped)
        #expect(root.interventionSettings.tunings.isShipped)

        root.perform(InterventionSettingsAction.setPolicyTuning(.dailyInterruptionCap, 12))
        root.perform(InterventionSettingsAction.setPolicyTuning(.sustainedDriftThreshold, 120))

        #expect(root.nudgeHost.tunings.count(.dailyInterruptionCap) == 12)
        #expect(root.relevanceHost.tunings.duration(.sustainedDriftThreshold) == .seconds(120))
        #expect(root.interventionSettings.tunings.count(.dailyInterruptionCap) == 12)
        let stored = FocusStore.policyTunings(in: root.modelContainer.mainContext)
        #expect(stored.count(.dailyInterruptionCap) == 12)
        #expect(stored.duration(.sustainedDriftThreshold) == .seconds(120))
        // An untouched dial is still the constant, in every reader.
        #expect(root.nudgeHost.tunings.duration(.queryCooldown) == InterventionPolicy.queryCooldown)

        root.perform(InterventionSettingsAction.resetPolicyTunings)
        #expect(root.nudgeHost.tunings.isShipped)
        #expect(root.relevanceHost.tunings.isShipped)
        #expect(FocusStore.policyTunings(in: root.modelContainer.mainContext).isShipped)
    }

    @Test("a stored dial is read at launch")
    func storedDialsAreReadAtLaunch() throws {
        let root = CompositionRootTests.root()
        defer { root.stop() }
        try FocusStore.setPolicyTuning(.mandateCooldown, to: 900, in: root.modelContainer.mainContext, now: NudgeHostFixture.reference)
        root.startNudgeLoop()
        #expect(root.nudgeHost.tunings.duration(.mandateCooldown) == .seconds(900))
        #expect(root.relevanceHost.tunings.duration(.mandateCooldown) == .seconds(900))
    }
}
