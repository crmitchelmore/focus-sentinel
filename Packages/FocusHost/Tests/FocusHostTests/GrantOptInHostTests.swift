import FocusCore
import FocusUI
import Foundation
import Testing
@testable import FocusHost

/// **The conditional doctrine, through the live composition root** (focus-exdi.4).
@Suite("Grant opt-ins through the composition root", .serialized)
@MainActor
struct GrantOptInHostTests {
    @Test("a fresh root asks for nothing and reads both grants as notRequested")
    func theDefaultInstallAsksForNothing() {
        let root = CompositionRootTests.root()
        defer { root.stop() }
        #expect(root.grantOptIns.asksForNothing)
        #expect(root.grantRequester.requestCount == 0)
        for grant in GrantOptIn.allCases {
            #expect(root.capabilities.state(of: grant.capability) == .notRequested)
        }
        // The window that draws the pane is handed the same "nothing" the store holds.
        #expect(root.settingsConnection().grants.asksForNothing)
    }

    @Test("switching a grant on stores it, and switching it off withdraws it")
    func aSwitchIsStoredAndWithdrawn() {
        let root = CompositionRootTests.root()
        defer { root.stop() }

        root.perform(PrivacySettingsAction.setGrantOptIn(.screenCapture, true))
        #expect(root.grantOptIns.isEnabled(.screenCapture))
        #expect(!root.grantOptIns.isEnabled(.accessibilityWindowContext))
        #expect(FocusStore.grantOptIns(in: root.modelContainer.mainContext).isEnabled(.screenCapture))
        // The one grant that was switched on is the only one that may have been asked for.
        #expect(root.grantRequester.requestCount == 1)
        // The capability it names is no longer `notRequested`: the person answered, and the
        // answer — whichever way macOS went — is what the table now says.
        #expect(root.capabilities.state(of: .screenCapture) != .notRequested)
        #expect(root.capabilities.state(of: .accessibilityWindowContext) == .notRequested)

        root.perform(PrivacySettingsAction.setGrantOptIn(.screenCapture, false))
        #expect(root.grantOptIns.asksForNothing)
        #expect(FocusStore.grantOptIns(in: root.modelContainer.mainContext).asksForNothing)
        // Switching off asks for nothing more, and the table goes back to "not asked for".
        #expect(root.grantRequester.requestCount == 1)
        #expect(root.capabilities.state(of: .screenCapture) == .notRequested)
    }

    @Test("a grant survives a relaunch, and a relaunch on its own asks for nothing")
    func aGrantSurvivesARelaunch() {
        let url = AppCompositionSettingsTests.temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        do {
            let first = AppCompositionSettingsTests.root(storeKind: .temporary(url))
            defer { first.stop() }
            first.perform(PrivacySettingsAction.setGrantOptIn(.accessibilityWindowContext, true))
            #expect(first.grantOptIns.isEnabled(.accessibilityWindowContext))
        }
        let second = AppCompositionSettingsTests.root(storeKind: .temporary(url))
        defer {
            second.stop()
            second.menuBar.remove()
        }
        #expect(second.grantOptIns.isEnabled(.accessibilityWindowContext))
        // **The half that matters.** A launch is not an ask: the switch is remembered, and the
        // state is read without a prompt.
        #expect(second.grantRequester.requestCount == 0)
    }
}
