import Foundation
import Testing

@testable import FocusCore

/// The surfaces, and the notification authorisation reduced to what it now is: **four names for
/// a reading, with no behaviour attached to any of them** (R-82, F-73, P-134, focus-wy0).
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

    /// **Two questions that were one predicate, and the cell where they part company**
    /// (focus-uru, focus-k42).
    ///
    /// `offersAnAnswer` asks *"can a person looking at this surface answer the nudge on it?"*;
    /// `holdsTheInterruptionSlot` asks *"is this surface occupied the moment a nudge lands on
    /// it?"*. They agree on three surfaces and differ on the badge, for one reason: the popover
    /// opens only when somebody clicks the status item, so a nudge routed there is answerable
    /// once looked at and has reached nobody until then.
    ///
    /// Asserted as an enumeration with the difference named, so that collapsing them back into
    /// one predicate — in either direction — is a red run. Collapsing towards the slot brings
    /// back focus-uru's unanswerable badge; collapsing towards the answer brings back focus-k42's
    /// badge that withholds every accusation for the rest of the session.
    @Test("answerability and slot ownership are different questions, and differ only on the badge")
    func answerabilityIsNotSlotOwnership() {
        #expect(Set(NudgeSurface.allCases.filter(\.offersAnAnswer))
            == [.panel, .popoverBadge, .notification])
        #expect(Set(NudgeSurface.allCases.filter(\.holdsTheInterruptionSlot))
            == [.panel, .notification])

        let disagree = NudgeSurface.allCases.filter {
            $0.offersAnAnswer != $0.holdsTheInterruptionSlot
        }
        #expect(disagree == [.popoverBadge], "the two predicates parted company somewhere new")

        // The glyph is the one surface that is neither, and that is R-87: it is a state rather
        // than a sentence, it stays on through a snooze, and there is nothing on it to press.
        #expect(!NudgeSurface.menuBar.offersAnAnswer)
        #expect(!NudgeSurface.menuBar.holdsTheInterruptionSlot)
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

    /// **R-82.2 in its final form** (focus-wy0). The ruling was that `denied` and `notRequested`
    /// are identical in what may be *delivered* and differ only in what may be *offered*. Both
    /// halves are now vacuous by construction, and the type says so rather than a test asserting
    /// it: nothing is delivered, so `permitsDelivery` is gone; nothing is offered, so
    /// `mayOfferToEnable` is gone with the button it gated. All four states behave identically
    /// because none of them reaches any behaviour at all.
    ///
    /// What is left is a name for a reading, and this is the assertion that keeps it that way: a
    /// property added back here would be a decision taken on a value nothing is entitled to
    /// decide on.
    @Test("no authorisation state carries any behaviour, in any of the four")
    func theAuthorisationDecidesNothing() {
        let fields = Set(
            NotificationAuthorisation.allCases.flatMap {
                Mirror(reflecting: $0).children.compactMap(\.label)
            }
        )
        #expect(fields.isEmpty, "an authorisation state grew a stored fact: \(fields.sorted())")

        // The one thing it still does: name itself, stably, for a report to print.
        #expect(
            NotificationAuthorisation.allCases.map(\.rawValue)
                == ["authorised", "denied", "notRequested", "provisional"]
        )
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
