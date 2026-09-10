import FocusCore
import FocusUI
import Foundation
import Testing
@testable import FocusHost

/// **The observer switches reach the sensing host and the store** (focus-exdi.3).
@Suite("Observer switches through the composition root", .serialized)
@MainActor
struct ObserverSwitchesHostTests {
    @Test("the away threshold, the microphone rule and the launch-context switch are stored and applied")
    func switchesAreStoredAndApplied() throws {
        let root = CompositionRootTests.root()
        defer { root.stop() }
        let before = root.sensingHost.settings
        #expect(before.mediaSuppressionEnabled)
        #expect(!before.launchContextOnSessionStart)

        root.perform(PrivacySettingsAction.setIdleThreshold(seconds: 300))
        root.perform(PrivacySettingsAction.setMediaSuppression(false))
        root.perform(PrivacySettingsAction.setLaunchContextOnSessionStart(true))

        let live = root.sensingHost.settings
        #expect(live.idleThresholdSeconds == 300)
        #expect(!live.mediaSuppressionEnabled)
        #expect(live.launchContextOnSessionStart)
        let stored = FocusStore.sensingSettings(in: root.modelContainer.mainContext)
        #expect(stored.idleThresholdSeconds == 300)
        #expect(!stored.mediaSuppressionEnabled)
        #expect(stored.launchContextOnSessionStart)
        // The settings window is handed the same value the host runs on.
        #expect(root.settingsConnection().sensing == live)
    }
}
