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

    @Test("each grant names a capability, and only the calendar claims a reading this build makes")
    func theVocabularyIsClosedAndHonest() {
        #expect(GrantOptIn.allCases.count == 3)
        #expect(GrantOptIn.accessibilityWindowContext.capability == .accessibilityWindowContext)
        #expect(GrantOptIn.screenCapture.capability == .screenCapture)
        #expect(GrantOptIn.calendarEvents.capability == .calendarEvents)
        #expect(Set(GrantOptIn.allCases.map(\.capability)).count == GrantOptIn.allCases.count)
        // Nothing in this build reads what the first two unlock; the pane says so beside the
        // switch. The calendar is read — by the timebox control and by gate 13 (focus-cal) — so
        // it is the one grant that may claim it.
        #expect(GrantOptIn.allCases.filter(\.isConsumedByThisBuild) == [.calendarEvents])
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
