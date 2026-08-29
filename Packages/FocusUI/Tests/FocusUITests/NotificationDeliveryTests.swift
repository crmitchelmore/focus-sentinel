import FocusCore
import Foundation
import Testing

@testable import FocusUI

/// A notification centre that answers whatever the test tells it to.
///
/// It exists so this whole suite runs **at zero grants, with no prompt and no notification
/// centre**. Since focus-wy0 the seam it stands in for has one call left — the settings read —
/// so this stub answers that and nothing else: there is no `setCategories` to count and no
/// `add(_:)` to fail, because the app makes neither.
@MainActor
final class StubNotificationCentre: NotificationCentring {
    var status: Int

    init(status: Int) {
        self.status = status
    }

    func authorizationStatus(_ completion: @escaping @MainActor (Int) -> Void) {
        completion(status)
    }
}

/// **What the notification boundary still does, and the three things it no longer does**
/// (R-82, P-134, §4.5, U-2, focus-wy0).
@Suite("The notification boundary, which now only listens")
@MainActor
struct NotificationDeliveryTests {
    /// The delivery token these drives mint. A fixed string rather than a `UUID`, so a failing
    /// line names something a person can read.
    private static let deliveryID = "the rung under test"

    // MARK: - Every authorisation state, decoded by an exhaustive switch

    @Test("the framework's status decodes to exactly one authorisation, in every case")
    func statusDecoding() {
        #expect(NotificationAuthorisation.decode(authorizationStatus: 0) == .notRequested)
        #expect(NotificationAuthorisation.decode(authorizationStatus: 1) == .denied)
        #expect(NotificationAuthorisation.decode(authorizationStatus: 2) == .authorised)
        #expect(NotificationAuthorisation.decode(authorizationStatus: 3) == .provisional)
        #expect(NotificationAuthorisation.decode(authorizationStatus: 4) == .provisional)
    }

    /// **An unknown status is never permission.** A future OS that adds a fifth case must not be
    /// able to turn a silent app into a noisy one, so the default is the conservative reading —
    /// which matters for focus-5ab, when there is something to be noisy with again.
    @Test("an unrecognised status decodes to denied, never to a grant", arguments: [5, 99, -1])
    func unknownStatusIsNeverAGrant(raw: Int) {
        #expect(NotificationAuthorisation.decode(authorizationStatus: raw) == .denied)
    }

    @Test("refreshing reads the state and never asks for it", arguments: [0, 1, 2, 3])
    func refreshReadsTheState(raw: Int) {
        let centre = StubNotificationCentre(status: raw)
        let delivery = NotificationDelivery(centre: centre)

        var reported: NotificationAuthorisation?
        delivery.refresh { reported = $0 }

        #expect(reported == NotificationAuthorisation.decode(authorizationStatus: raw))
        #expect(delivery.authorisation == reported)
        // **The number that discharges standing condition 5 for this file.**
        #expect(delivery.requestAuthorizationCallCount == 0)
    }

    // MARK: - Nothing is registered, at any grant (focus-wy0)

    /// **The seam offers no way to register a category, so no grant can cause one.**
    ///
    /// It used to: registration ran on every launch that found a grant, and put three actions
    /// onto a category no banner would ever carry, because U-2 had already removed the only rung
    /// that posts one. This is the assertion that replaces "registered exactly once, and only
    /// after a grant" — the honest count is now zero, at every grant, and it is enforced by the
    /// protocol rather than by a branch somebody could restore.
    @Test("the boundary can register nothing, whatever the grant says", arguments: [0, 1, 2, 3])
    func nothingIsEverRegistered(raw: Int) {
        let delivery = NotificationDelivery(centre: StubNotificationCentre(status: raw))
        delivery.refresh()

        let calls = Set(
            Mirror(reflecting: StubNotificationCentre(status: raw))
                .children.compactMap(\.label)
        )
        #expect(calls == ["status"], "the notification seam grew a capability: \(calls.sorted())")
        #expect(delivery.requestAuthorizationCallCount == 0)
    }

    /// The three actions are **kept** — focus-5ab needs them, and a press on a banner an earlier
    /// build posted still has to decode to one so `NudgeHost` can refuse it.
    @Test("the three answerable actions are still declared, and still decode")
    func threeActions() {
        #expect(NudgeNotificationAction.allCases.count == 3)
        #expect(Set(NudgeNotificationAction.allCases.map(\.identifier)).count == 3)
        for action in NudgeNotificationAction.allCases {
            #expect(action.identifier.hasPrefix("nudge.action."))
            // Every one is a real correction, so a tap goes through the same single function a
            // click does (R-86).
            #expect(CorrectionAction.allCases.contains(action.correction))
            #expect(!action.copyKey.isQueryLine)
        }
    }

    // **The delivery section is gone** (U-2), and so is the registration section (focus-wy0).
    // No rung routes to a notification, so there is no delivery to authorise, no failure to
    // demote, no route change to assert and no category to put buttons on. What remains below is
    // the half that still runs: decoding a press on a banner an earlier build posted.

    // MARK: - Taps come back as typed actions

    @Test("a tap on a registered action reports it, and anything else reports nothing")
    func tapsReportTypedActions() {
        let delivery = NotificationDelivery(centre: StubNotificationCentre(status: 2))
        var seen: [NudgeNotificationResponse] = []
        delivery.onAction = { seen.append($0) }

        for action in NudgeNotificationAction.allCases {
            delivery.handle(
                actionIdentifier: action.identifier, requestIdentifier: Self.deliveryID
            )
        }
        delivery.handle(
            actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier",
            requestIdentifier: Self.deliveryID
        )
        delivery.handle(actionIdentifier: "", requestIdentifier: Self.deliveryID)

        #expect(seen.map(\.action) == NudgeNotificationAction.allCases)
        // **Which banner, carried through untouched** (focus-zrs). This boundary decodes; whether
        // the delivery is still open is the loop's question, and it cannot ask it without this.
        #expect(seen.allSatisfy { $0.deliveryID == Self.deliveryID })
    }

    /// A press names its own delivery, and two deliveries are two different presses.
    @Test("two banners produce two distinguishable presses")
    func pressesNameTheirOwnDelivery() {
        let delivery = NotificationDelivery(centre: StubNotificationCentre(status: 2))
        var seen: [NudgeNotificationResponse] = []
        delivery.onAction = { seen.append($0) }

        delivery.handle(
            actionIdentifier: NudgeNotificationAction.snooze.identifier,
            requestIdentifier: "the rung on screen"
        )
        delivery.handle(
            actionIdentifier: NudgeNotificationAction.snooze.identifier,
            requestIdentifier: "a banner from an hour ago"
        )

        #expect(seen.map(\.deliveryID) == ["the rung on screen", "a banner from an hour ago"])
    }

    // MARK: - What the boundary reads changes nothing about where a rung lands

    /// **The reading and the routing have been disconnected, and this is what says so**
    /// (focus-wy0).
    ///
    /// It used to assert that an unauthorised boundary still routed the rung in-app, by handing
    /// `delivery.authorisation` to `SurfaceRouter.route(…)`. There is nowhere to hand it: the
    /// router takes no authorisation. So the claim is made the only way left to make it — the
    /// boundary reads all four states, and the panel rung lands on the panel throughout.
    @Test("whatever the boundary reads, the rung lands in-app", arguments: [0, 1, 2, 3])
    func theReadingDoesNotMoveTheRung(raw: Int) {
        let delivery = NotificationDelivery(centre: StubNotificationCentre(status: raw))
        delivery.refresh()
        #expect(delivery.authorisation == NotificationAuthorisation.decode(authorizationStatus: raw))

        let route = SurfaceRouter.route(
            rung: .panel,
            presentation: .notPresenting,
            media: .idle,
            reducedInterruption: false,
            menuBarVisible: true,
            voice: .standard
        )
        #expect(route == .surface(.panel))
        #expect(route.surface?.isInApp == true)
    }
}
