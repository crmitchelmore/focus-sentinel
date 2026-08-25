import Foundation
import Testing

@testable import FocusCore

/// The surfaces, the authorisation states, and the ruling that a refusal changes what the app
/// *offers* and never what it *delivers* (R-82, F-73, P-134).
@Suite("Nudge surfaces")
struct NudgeSurfaceTests {
    @Test("there are exactly four surfaces, three of them in-app")
    func fourSurfaces() {
        #expect(NudgeSurface.allCases.count == 4)
        #expect(
            Set(NudgeSurface.allCases) == [.menuBar, .panel, .notification, .popoverBadge]
        )

        let inApp = NudgeSurface.allCases.filter(\.isInApp)
        #expect(Set(inApp) == [.menuBar, .panel, .popoverBadge])
        #expect(inApp.count == 3)
    }

    /// **The reason the `notification-denied` gate stage can exist at all.** Every rung has an
    /// in-app surface, so all three are deliverable with no grant of any kind — which is what
    /// discharges standing condition 5 for this epic.
    @Test("exactly one surface needs an authorisation, and it is the notification")
    func onlyOneSurfaceNeedsAGrant() {
        let gated = NudgeSurface.allCases.filter(\.requiresNotificationAuthorisation)
        #expect(gated == [.notification])
        for surface in NudgeSurface.allCases where surface.isInApp {
            #expect(!surface.requiresNotificationAuthorisation)
        }
    }

    // MARK: - The authorisation states

    @Test("there are exactly four authorisation states")
    func fourAuthorisationStates() {
        #expect(NotificationAuthorisation.allCases.count == 4)
        #expect(
            Set(NotificationAuthorisation.allCases)
                == [.authorised, .denied, .notRequested, .provisional]
        )
    }

    /// **R-82.2, the ruling this suite exists for.** `denied` and `notRequested` are identical
    /// in what may be delivered. A user who has never been asked and a user who said no get
    /// exactly the same behaviour.
    @Test("denied and notRequested deliver identically")
    func deniedAndNotRequestedDeliverIdentically() {
        #expect(
            NotificationAuthorisation.denied.permitsDelivery
                == NotificationAuthorisation.notRequested.permitsDelivery
        )
        #expect(!NotificationAuthorisation.denied.permitsDelivery)
        #expect(!NotificationAuthorisation.notRequested.permitsDelivery)
        #expect(NotificationAuthorisation.authorised.permitsDelivery)
        #expect(NotificationAuthorisation.provisional.permitsDelivery)
    }

    /// …and differ in exactly one thing: whether a settings pane may show a one-line offer.
    /// Never inside a nudge, and never to somebody who has already said no (F-127).
    @Test("only notRequested may be offered an enable affordance")
    func onlyNotRequestedMayBeOffered() {
        let offerable = NotificationAuthorisation.allCases.filter(\.mayOfferToEnable)
        #expect(offerable == [.notRequested])
        #expect(!NotificationAuthorisation.denied.mayOfferToEnable)
        #expect(!NotificationAuthorisation.authorised.mayOfferToEnable)
        #expect(!NotificationAuthorisation.provisional.mayOfferToEnable)
    }

    /// The two states that permit delivery are the two the framework calls authorised and
    /// provisional, and P-134's measured zero-grant state is neither.
    @Test("the zero-grant state this Mac was measured in delivers nothing")
    func measuredZeroGrantState() {
        // P-134: authorizationStatus == 0 (.notDetermined), every setting .notSupported,
        // add(_:) failing with UNErrorDomain code 1.
        let measured = NotificationAuthorisation.notRequested
        #expect(!measured.permitsDelivery)
        #expect(measured.mayOfferToEnable)
    }

    // MARK: - SurfaceRoute

    /// A route is not an `Optional<NudgeSurface>`: an absent surface has a reason, and the
    /// reason is what the record carries and what a person is told.
    @Test("a route answers exactly one of surface and deferral reason")
    func routeAnswersOneQuestion() {
        let routes: [SurfaceRoute] =
            NudgeSurface.allCases.map { .surface($0) }
            + DeferralReason.allCases.map { .unavailable($0) }

        for route in routes {
            let present = [route.surface != nil, route.deferralReason != nil].filter { $0 }
            #expect(present.count == 1, "\(route) answered more or fewer than one question")
        }
    }

    /// The one sanctioned bridge from a route to a delivery, so "no surface" and "deferred"
    /// cannot drift apart.
    @Test("a route becomes the delivery it describes, and a deferral is never a delivery")
    func routeBecomesItsDelivery() {
        for surface in NudgeSurface.allCases {
            #expect(SurfaceRoute.surface(surface).delivery == .delivered(surface))
            #expect(SurfaceRoute.surface(surface).delivery.deferralReason == nil)
        }
        for reason in DeferralReason.allCases {
            #expect(SurfaceRoute.unavailable(reason).delivery == .deferred(reason))
            #expect(SurfaceRoute.unavailable(reason).delivery.surface == nil)
        }
    }

    @Test("surfaces and authorisation states round-trip through Codable on their raw values")
    func codableRoundTrip() throws {
        for surface in NudgeSurface.allCases {
            let data = try JSONEncoder().encode(surface)
            #expect(try JSONDecoder().decode(NudgeSurface.self, from: data) == surface)
        }
        for state in NotificationAuthorisation.allCases {
            let data = try JSONEncoder().encode(state)
            #expect(try JSONDecoder().decode(NotificationAuthorisation.self, from: data) == state)
        }
    }
}
