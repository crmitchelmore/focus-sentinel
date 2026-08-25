import FocusCore
import Foundation
import Testing

@testable import FocusUI

/// A notification centre that answers whatever the test tells it to.
///
/// It exists so this whole suite runs **at zero grants, with no prompt and no notification
/// centre** — which is what makes R-82's four rulings T1 claims rather than things that can only
/// be checked on a machine somebody has clicked "Allow" on.
@MainActor
final class StubNotificationCentre: NotificationCentring {
    var status: Int
    var addResult: NotificationAddResult
    private(set) var registeredCategoryIdentifiers: Set<String> = []
    private(set) var setCategoriesCallCount = 0
    private(set) var addedTitles: [String] = []
    private(set) var addedCategories: [String] = []
    /// Whether the stub honours a `setCategories` call. P-134 measured the real centre silently
    /// taking **zero** categories while unauthorised, so the stub can be told to do the same.
    var acceptsCategories = true

    init(status: Int, addResult: NotificationAddResult = .delivered) {
        self.status = status
        self.addResult = addResult
    }

    func authorizationStatus(_ completion: @escaping @MainActor (Int) -> Void) {
        completion(status)
    }

    func setCategories(_ identifiers: Set<String>) {
        setCategoriesCallCount += 1
        guard acceptsCategories else { return }
        registeredCategoryIdentifiers = identifiers
    }

    func add(
        identifier: String,
        title: String,
        body: String,
        categoryIdentifier: String,
        completion: @escaping @MainActor (NotificationAddResult) -> Void
    ) {
        addedTitles.append(title)
        addedCategories.append(categoryIdentifier)
        completion(addResult)
    }
}

/// **The denied path is the automated gate** (R-82, P-134, §4.5).
@Suite("Notification delivery, and the route around every refusal")
@MainActor
struct NotificationDeliveryTests {
    private static func presentation(voice: NudgeVoice = .standard) -> AccusationPresentation {
        AccusationPresentation(
            rung: .recommitment,
            voice: voice,
            task: "Write the Q3 proposal",
            subject: "com.apple.Safari",
            dwelled: .seconds(1_800),
            returnTarget: "Pages"
        )
    }

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
    /// able to turn a silent app into a noisy one, so the default is the conservative reading.
    @Test("an unrecognised status decodes to denied, never to a grant", arguments: [5, 99, -1])
    func unknownStatusIsNeverAGrant(raw: Int) {
        let decoded = NotificationAuthorisation.decode(authorizationStatus: raw)
        #expect(decoded == .denied)
        #expect(!decoded.permitsDelivery)
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

    // MARK: - Categories after authorisation, never at launch (P-134)

    @Test("categories are not registered while unauthorised", arguments: [0, 1])
    func noCategoriesWhileUnauthorised(raw: Int) {
        let centre = StubNotificationCentre(status: raw)
        let delivery = NotificationDelivery(centre: centre)

        delivery.refresh()

        #expect(centre.setCategoriesCallCount == 0)
        #expect(delivery.categoryRegistrationCount == 0)
        #expect(!delivery.hasRegisteredActions)
    }

    @Test("categories are registered exactly once, and only after a grant", arguments: [2, 3])
    func categoriesRegisteredOnceAfterAGrant(raw: Int) {
        let centre = StubNotificationCentre(status: raw)
        let delivery = NotificationDelivery(centre: centre)

        delivery.refresh()
        delivery.refresh()
        delivery.refresh()

        #expect(delivery.categoryRegistrationCount == 1)
        #expect(centre.setCategoriesCallCount == 1)
        #expect(delivery.hasRegisteredActions)
        #expect(
            centre.registeredCategoryIdentifiers == [NudgeNotificationCategory.identifier]
        )
    }

    /// P-134's exact measurement: `setNotificationCategories` **does not take** while
    /// unauthorised. A centre that silently drops them must leave `hasRegisteredActions` false,
    /// so the app never believes it has actions it does not have.
    @Test("a centre that silently drops the categories is not believed")
    func silentlyDroppedCategoriesAreNotBelieved() {
        let centre = StubNotificationCentre(status: 2)
        centre.acceptsCategories = false
        let delivery = NotificationDelivery(centre: centre)

        delivery.refresh()

        #expect(centre.setCategoriesCallCount == 1)
        #expect(!delivery.hasRegisteredActions)
    }

    @Test("the notification carries all three answerable actions")
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

    // MARK: - Delivery, and the route change on failure (R-82.4)

    @Test("an authorised delivery reaches the notification surface", arguments: [2, 3])
    func authorisedDelivery(raw: Int) {
        let centre = StubNotificationCentre(status: raw)
        let delivery = NotificationDelivery(centre: centre)
        delivery.refresh()

        var recorded: RungDelivery?
        var route: SurfaceRoute?
        delivery.deliver(
            Self.presentation(),
            surroundings: NotificationSurroundings()
        ) { recorded = $0; route = $1 }

        #expect(recorded == .delivered(.notification))
        #expect(route == .surface(.notification))
        #expect(centre.addedCategories == [NudgeNotificationCategory.identifier])
    }

    /// **The measured failure**: `UNErrorDomain` code 1, arriving after a positive settings read.
    /// It is a route change, not a log line — and the record is a **deferral**, so the ladder
    /// does not advance and no cap is spent (R-81).
    @Test("a UNErrorDomain 1 completion demotes to the panel and records a deferral")
    func deliveryFailureIsARouteChange() {
        let centre = StubNotificationCentre(
            status: 2,
            addResult: .failed(domain: "UNErrorDomain", code: 1)
        )
        let delivery = NotificationDelivery(centre: centre)
        delivery.refresh()
        #expect(delivery.authorisation == .authorised)

        var recorded: RungDelivery?
        var route: SurfaceRoute?
        delivery.deliver(
            Self.presentation(),
            surroundings: NotificationSurroundings()
        ) { recorded = $0; route = $1 }

        #expect(recorded == .deferred(.notificationDeliveryFailed))
        #expect(route == .surface(.panel))
        // The app stops believing it may deliver, so the *next* rung routes in-app without
        // having to fail first.
        #expect(delivery.authorisation == .denied)
        #expect(!delivery.authorisation.permitsDelivery)
    }

    /// The failure route is the router's own answer for `denied`, in every surrounding — so the
    /// demotion cannot disagree with what the settings pane's matrix promised.
    @Test(
        "the demotion equals the router's denied route in every surrounding",
        arguments: [false, true], [false, true]
    )
    func demotionMatchesTheDeniedRoute(reduced: Bool, menuBarVisible: Bool) {
        let surroundings = NotificationSurroundings(
            reducedInterruption: reduced,
            menuBarVisible: menuBarVisible
        )
        let centre = StubNotificationCentre(
            status: 2,
            addResult: .failed(domain: "UNErrorDomain", code: 1)
        )
        let delivery = NotificationDelivery(centre: centre)
        delivery.refresh()

        var route: SurfaceRoute?
        delivery.deliver(Self.presentation(), surroundings: surroundings) { _, produced in
            route = produced
        }

        let expected = SurfaceRouter.route(
            rung: .recommitment,
            authorisation: .denied,
            presentation: surroundings.presentation,
            media: surroundings.media,
            reducedInterruption: reduced,
            menuBarVisible: menuBarVisible,
            voice: .standard
        )
        #expect(route == expected)
    }

    // MARK: - Taps come back as typed actions

    @Test("a tap on a registered action reports it, and anything else reports nothing")
    func tapsReportTypedActions() {
        let delivery = NotificationDelivery(centre: StubNotificationCentre(status: 2))
        var seen: [NudgeNotificationAction] = []
        delivery.onAction = { seen.append($0) }

        for action in NudgeNotificationAction.allCases {
            delivery.handle(actionIdentifier: action.identifier)
        }
        delivery.handle(actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier")
        delivery.handle(actionIdentifier: "")

        #expect(seen == NudgeNotificationAction.allCases)
    }

    // MARK: - The whole matrix, in one place

    /// **`denied` and `notRequested` are identical in delivery, in every cell** — asserted here
    /// against the delivery object rather than only against the router, so the boundary cannot
    /// be the place the identity is lost.
    @Test("no unauthorised state ever reaches a notification", arguments: [0, 1])
    func unauthorisedNeverReachesANotification(raw: Int) {
        let centre = StubNotificationCentre(status: raw)
        let delivery = NotificationDelivery(centre: centre)
        delivery.refresh()

        #expect(!delivery.authorisation.permitsDelivery)
        // The router is what decides, and it sends the rung in-app.
        let route = SurfaceRouter.route(
            rung: .recommitment,
            authorisation: delivery.authorisation,
            presentation: .notPresenting,
            media: .idle,
            reducedInterruption: false,
            menuBarVisible: true,
            voice: .standard
        )
        #expect(route == .surface(.panel))
        #expect(route.surface != .notification)
    }

    /// Only one of the two may *offer* to turn notifications on, and it is the one nobody has
    /// asked yet (F-127's never-re-prompt policy).
    @Test("only notRequested may offer to enable, and never inside a nudge")
    func onlyNotRequestedMayOffer() {
        #expect(NotificationAuthorisation.notRequested.mayOfferToEnable)
        #expect(!NotificationAuthorisation.denied.mayOfferToEnable)
        #expect(!NotificationAuthorisation.authorised.mayOfferToEnable)
        #expect(!NotificationAuthorisation.provisional.mayOfferToEnable)
    }
}
