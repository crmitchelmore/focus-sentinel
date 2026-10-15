import FocusCore
import Testing

@testable import FocusUI

@Suite("Software update commands")
@MainActor
struct SoftwareUpdateCommandTests {
    @Test("the menu check reaches the settings action without raising a window")
    func menuReachesSettingsAction() {
        let center = FocusCommandCenter()
        #expect(!center.canCheckForUpdates)
        #expect(!center.checkForUpdates())
        var actions: [SoftwareUpdateSettingsAction] = []
        center.registerSoftwareUpdatePerformer(canCheck: true) { actions.append($0) }
        #expect(center.canCheckForUpdates)
        #expect(center.checkForUpdates())
        #expect(actions == [.checkNow])
        #expect(center.cockpitRequests == 0)

        center.updateSoftwareUpdateAvailability(false)
        #expect(!center.canCheckForUpdates)
        #expect(!center.checkForUpdates())
        #expect(actions == [.checkNow])
        center.updateSoftwareUpdateAvailability(true)
        #expect(center.checkForUpdates())
        #expect(actions == [.checkNow, .checkNow])
    }

    @Test("every failure has its own explanation")
    func failureExplanations() {
        #expect(GeneralSettingsView.updateFailureKey(.configuration) == .settingsUpdatesConfigurationError)
        #expect(GeneralSettingsView.updateFailureKey(.feedUnavailable) == .settingsUpdatesFeedUnavailable)
        #expect(GeneralSettingsView.updateFailureKey(.network) == .settingsUpdatesNetworkError)
        #expect(GeneralSettingsView.updateFailureKey(.other) == .settingsUpdatesError)
    }
}
