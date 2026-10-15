import FocusCore
import FocusUI
import Foundation
import Testing
@testable import FocusHost

/// **What macOS allows, read without asking and followed while the person is away in System
/// Settings** (issue #24 follow-up).
@Suite("Grant access watch")
@MainActor
struct GrantAccessWatchTests {
    final class FakeRequester: GrantRequesting {
        var answers: [GrantOptIn: CapabilityState] = [:]
        private(set) var reads = 0
        private(set) var requestCount = 0
        func requestGrant(_ grant: GrantOptIn) -> CapabilityState {
            requestCount += 1
            return answers[grant] ?? .denied
        }
        func grantState(_ grant: GrantOptIn) -> CapabilityState {
            reads += 1
            return answers[grant] ?? .denied
        }
    }

    @Test("with nothing switched on, nothing is read and every grant is notRequested")
    func nothingSwitchedOnReadsNothing() {
        let requester = FakeRequester()
        let watch = GrantAccessWatch(requester: requester)
        watch.apply(.none)
        watch.refresh()
        #expect(requester.reads == 0)
        for grant in GrantOptIn.allCases {
            #expect(watch.state(of: grant) == .notRequested)
        }
        watch.watchUntilAllowed()
        #expect(!watch.isWatching)
    }

    @Test("a grant given in System Settings is noticed on the next read, and only a change reports")
    func aGrantGivenElsewhereIsNoticed() {
        let requester = FakeRequester()
        let watch = GrantAccessWatch(requester: requester)
        var changes = 0
        watch.onChange = { changes += 1 }
        watch.apply(GrantOptIns(enabled: [.accessibilityWindowContext]))
        #expect(watch.state(of: .accessibilityWindowContext) == .denied)
        #expect(watch.state(of: .screenCapture) == .notRequested)
        #expect(changes == 1)

        requester.answers[.accessibilityWindowContext] = .available
        #expect(watch.refresh())
        #expect(watch.state(of: .accessibilityWindowContext) == .available)
        #expect(changes == 2)
        #expect(!watch.refresh())
        #expect(changes == 2)
        // Reading is never asking.
        #expect(requester.requestCount == 0)

        watch.apply(.none)
        #expect(watch.state(of: .accessibilityWindowContext) == .notRequested)
    }

    @Test("a watch stops by itself once every switched-on grant is allowed")
    func aWatchStopsWhenAllowed() async throws {
        let requester = FakeRequester()
        let watch = GrantAccessWatch(requester: requester)
        watch.apply(GrantOptIns(enabled: [.accessibilityWindowContext]))
        watch.watchUntilAllowed()
        #expect(watch.isWatching)

        requester.answers[.accessibilityWindowContext] = .available
        for _ in 0..<40 where watch.isWatching {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!watch.isWatching)
        #expect(watch.state(of: .accessibilityWindowContext) == .available)
        #expect(requester.requestCount == 0)
    }

    @Test("each grant opens its own System Settings list")
    func theDeepLinksNameTheRightList() {
        #expect(
            GrantAccessWatch.systemSettingsURL(for: .accessibilityWindowContext).absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        #expect(
            GrantAccessWatch.systemSettingsURL(for: .screenCapture).absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }

    @Test("Open System Settings is refused for a grant the person did not switch on")
    func openingSettingsNeedsTheSwitch() {
        let root = CompositionRootTests.root()
        defer {
            root.grantAccess.stopWatching()
            root.stop()
        }
        var opened: [URL] = []
        root.openSystemSettings = { opened.append($0) }

        root.perform(PrivacySettingsAction.openGrantSettings(.accessibilityWindowContext))
        #expect(opened.isEmpty)

        // The switch, applied without the ask the pane's switch would also make.
        root.grantAccess.apply(GrantOptIns(enabled: [.accessibilityWindowContext]))
        root.perform(PrivacySettingsAction.openGrantSettings(.accessibilityWindowContext))
        #expect(opened == [GrantAccessWatch.systemSettingsURL(for: .accessibilityWindowContext)])
        root.perform(PrivacySettingsAction.openGrantSettings(.screenCapture))
        #expect(opened.count == 1)
        #expect(root.grantRequester.requestCount == 0)
    }
}
