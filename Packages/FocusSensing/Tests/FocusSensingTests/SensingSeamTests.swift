import FocusCore
import Foundation
import Testing

@testable import FocusSensing

@Suite("Sensing seam")
struct SensingSeamTests {
    @Test("NullActivityObserver reports itself unavailable rather than throwing")
    func nullObserverReportsUnavailable() {
        let observer = NullActivityObserver()

        #expect(observer.availability == .unavailable(reason: .notImplemented))
        #expect(observer.availability.isAvailable == false)
    }

    @Test("NullActivityObserver emits no events and finishes immediately")
    func nullObserverEmitsNothing() async {
        let observer = NullActivityObserver()
        var collected: [ActivityEventValue] = []

        // If the stream did not finish, this loop would never return and the test would
        // time out — which is exactly the failure mode a "null" source must not have.
        for await event in observer.events() {
            collected.append(event)
        }

        #expect(collected.isEmpty)
    }

    @Test("NullActivityObserver satisfies both observation protocols")
    func nullObserverSatisfiesBothSeams() {
        let activity: any ActivityObserving = NullActivityObserver()
        let idle: any IdleObserving = NullActivityObserver()

        #expect(activity.availability.isAvailable == false)
        #expect(idle.availability.isAvailable == false)
        #expect(idle.idleDuration() == .zero)
    }

    @Test("event kinds have stable string raw values")
    func eventKindsHaveStableRawValues() {
        #expect(ActivityEventKind.allCases.count == 5)
        #expect(ActivityEventKind.frontmostApplicationChanged.rawValue == "frontmostApplicationChanged")
        #expect(ActivityEventKind.contextChanged.rawValue == "contextChanged")
        #expect(ActivityEventKind.userIdle.rawValue == "userIdle")
        #expect(ActivityEventKind.userActive.rawValue == "userActive")
        #expect(ActivityEventKind.displayInactive.rawValue == "displayInactive")
    }

    @Test("an event stamped from an injected clock carries that clock's instant")
    func eventUsesInjectedClock() {
        let clock = FixedDateProvider.reference
        let event = ActivityEventValue(
            kind: .frontmostApplicationChanged,
            bundleIdentifier: "com.apple.dt.Xcode",
            dateProvider: clock
        )

        #expect(event.at == clock.now)
        #expect(event.detail == nil)
    }

    @Test("an unavailability reason always names something the UI can explain")
    func unavailabilityReasonsAreExplainable() {
        #expect(ObservationAvailability.UnavailabilityReason.allCases.count == 3)
        for reason in ObservationAvailability.UnavailabilityReason.allCases {
            #expect(!reason.rawValue.isEmpty)
            #expect(ObservationAvailability.unavailable(reason: reason).isAvailable == false)
        }
        #expect(ObservationAvailability.available.isAvailable)
    }

    @Test("events round-trip through Codable")
    func eventsRoundTrip() throws {
        let event = ActivityEventValue(
            at: FixedDateProvider.reference.now,
            kind: .contextChanged,
            bundleIdentifier: "com.apple.Safari",
            detail: "https://developer.example"
        )
        let data = try JSONEncoder().encode(event)
        #expect(try JSONDecoder().decode(ActivityEventValue.self, from: data) == event)
    }
}
