import Foundation
import Testing
@testable import FocusCore

/// **The conditional zero-grant doctrine, asserted** (focus-exdi.4).
@Suite("Grant opt-ins")
@MainActor
struct GrantOptInTests {
    /// Records every ask, and answers whatever it is told to.
    final class RecordingRequester: GrantRequesting {
        var granted: Set<GrantOptIn> = []
        private(set) var asked: [GrantOptIn] = []
        var requestCount: Int { asked.count }

        func requestGrant(_ grant: GrantOptIn) -> CapabilityState {
            asked.append(grant)
            return granted.contains(grant) ? .available : .denied
        }

        func grantState(_ grant: GrantOptIn) -> CapabilityState {
            granted.contains(grant) ? .available : .denied
        }
    }

    @Test("with nothing switched on, nothing is ever asked and every state is notRequested")
    func theDefaultInstallAsksForNothing() {
        let requester = RecordingRequester()
        requester.granted = Set(GrantOptIn.allCases)
        let optIns = GrantOptIns.none
        #expect(optIns.asksForNothing)

        for grant in GrantOptIn.allCases {
            #expect(GrantGate.request(grant, optIns: optIns, using: requester) == .notRequested)
            // Even on a Mac where the grant was given by hand, the app does not take it up.
            #expect(GrantGate.state(of: grant, optIns: optIns, using: requester) == .notRequested)
        }
        #expect(requester.requestCount == 0, "the app asked for a grant nobody switched on")
    }

    @Test("a grant switched on may be asked for, and only that one")
    func onlyTheSwitchedGrantIsAsked() {
        let requester = RecordingRequester()
        requester.granted = [.accessibilityWindowContext]
        var optIns = GrantOptIns.none
        optIns.set(.accessibilityWindowContext, to: true)

        #expect(GrantGate.request(.accessibilityWindowContext, optIns: optIns, using: requester) == .available)
        #expect(GrantGate.request(.screenCapture, optIns: optIns, using: requester) == .notRequested)
        #expect(requester.asked == [.accessibilityWindowContext])
        #expect(GrantGate.state(of: .accessibilityWindowContext, optIns: optIns, using: requester) == .available)
        #expect(GrantGate.state(of: .screenCapture, optIns: optIns, using: requester) == .notRequested)
    }

    @Test("a grant switched on and refused reads denied, and switching it off returns it to notRequested")
    func refusedAndWithdrawn() {
        let requester = RecordingRequester()
        var optIns = GrantOptIns.none
        optIns.set(.screenCapture, to: true)
        #expect(GrantGate.request(.screenCapture, optIns: optIns, using: requester) == .denied)
        #expect(GrantGate.state(of: .screenCapture, optIns: optIns, using: requester) == .denied)

        optIns.set(.screenCapture, to: false)
        #expect(optIns.asksForNothing)
        #expect(GrantGate.state(of: .screenCapture, optIns: optIns, using: requester) == .notRequested)
    }

    @Test("each grant names a capability, and only Accessibility claims a reading this build makes")
    func theVocabularyIsClosedAndHonest() {
        #expect(GrantOptIn.allCases.count == 2)
        #expect(GrantOptIn.accessibilityWindowContext.capability == .accessibilityWindowContext)
        #expect(GrantOptIn.screenCapture.capability == .screenCapture)
        #expect(Set(GrantOptIn.allCases.map(\.capability)).count == GrantOptIn.allCases.count)
        // Accessibility is read by the selected-item reader (issue #24); Screen Recording is
        // still read by nothing, and the pane says so beside its switch. A case that flips
        // this has to bring the reading with it.
        #expect(GrantOptIn.accessibilityWindowContext.isConsumedByThisBuild)
        #expect(!GrantOptIn.screenCapture.isConsumedByThisBuild)
        #expect(GrantOptIn.decode("accessibilityWindowContext") == .accessibilityWindowContext)
        #expect(GrantOptIn.decode("somethingRetired") == nil)
    }

    @Test("the opt-ins round-trip through Codable")
    func codable() throws {
        var optIns = GrantOptIns.none
        optIns.set(.accessibilityWindowContext, to: true)
        let data = try JSONEncoder().encode(optIns)
        #expect(try JSONDecoder().decode(GrantOptIns.self, from: data) == optIns)
    }
}
