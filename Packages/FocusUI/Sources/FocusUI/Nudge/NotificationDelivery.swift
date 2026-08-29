import FocusCore
import Foundation
import UserNotifications

/// **The three things a person can do from the notification**, and no more.
///
/// The same economy the panel carries, minus everything that needs a window: a notification's
/// actions are buttons on somebody else's surface, so "change priority" — which opens e02's
/// confirm surface — and "not this time" — which needs the panel's explanation beside it — stay
/// where they can be done properly. What is here is the three that are complete in one tap.
public enum NudgeNotificationAction: String, Sendable, CaseIterable, Hashable {
    case returnToTask
    case snooze
    case thisIsRelevant

    /// The identifier `UNNotificationAction` is registered under and reports back.
    public var identifier: String { "nudge.action.\(rawValue)" }

    /// The deck line that names it. The **same** lines the panel draws, so the notification and
    /// the panel cannot say two different things about one action.
    public var copyKey: NudgeCopyKey {
        switch self {
        case .returnToTask: .accusationActionReturn
        case .snooze: .accusationActionSnooze
        case .thisIsRelevant: .accusationActionRelevant
        }
    }

    /// The correction this action performs, so one function still turns a click into a write.
    public var correction: CorrectionAction {
        switch self {
        case .returnToTask: .returnToTask
        case .snooze: .snooze
        case .thisIsRelevant: .thisIsRelevant
        }
    }
}

/// The category the recommitment notification is registered under.
public enum NudgeNotificationCategory {
    public static let identifier = "nudge.recommitment"
}

/// **A press on a notification's button, with the delivery it belongs to** (focus-zrs).
///
/// The action alone was not enough, and the reason is a property of the surface rather than of the
/// code: a banner is not a window. It does not close when the moment it was about ends, and its
/// buttons stay live in Notification Centre for as long as the person leaves it there — hours,
/// days, across a relaunch. `NotificationDelivery.onAction` handed the loop a bare
/// `NudgeNotificationAction`, so *"return to task"* pressed on an hour-old banner was
/// indistinguishable from the same press a second after delivery, and reached
/// `NudgeHost.resolve(…)` with nothing to check it against.
///
/// `deliveryID` is the `UNNotificationRequest` identifier the banner was delivered under. It is
/// minted by the loop when the rung goes out, held for exactly as long as that rung is open, and
/// compared here on the way back: a press naming any other delivery is a click on a rung that is
/// over, and there is no correct thing to do with it but refuse it.
public struct NudgeNotificationResponse: Sendable, Equatable, Hashable {
    public let action: NudgeNotificationAction
    /// The `UNNotificationRequest` identifier: **which delivery** this press came from.
    public let deliveryID: String

    public init(action: NudgeNotificationAction, deliveryID: String) {
        self.action = action
        self.deliveryID = deliveryID
    }
}

/// **The mapping from the framework's status to the app's**, at the boundary and nowhere else.
///
/// `FocusCore` imports no UserNotifications — the package matrix forbids it — so
/// `NotificationAuthorisation` is a plain four-case enum there and this is the one place the
/// framework's number becomes one of them.
///
/// Decoded by an **exhaustive switch over the raw value**, never `init(rawValue:)`, in the shape
/// e03's R-49 established: an unknown status is a status this build has never seen, and the only
/// safe reading of one is that the app has **no** permission. Treating an unrecognised number as
/// permission is how a future OS release turns a silent app into a noisy one.
extension NotificationAuthorisation {
    public static func decode(authorizationStatus raw: Int) -> NotificationAuthorisation {
        switch raw {
        case 0: .notRequested          // .notDetermined — P-134 measured exactly this at zero grants
        case 1: .denied
        case 2: .authorised
        case 3: .provisional
        case 4: .provisional           // .ephemeral: quiet delivery, and the system still delivers
        default: .denied
        }
    }
}

/// What a `UNUserNotificationCenter.add(_:)` came back with.
public enum NotificationAddResult: Sendable, Equatable {
    case delivered
    /// P-134 measured `UNErrorDomain` code **1**, "Notifications are not allowed for this
    /// application", arriving from `add(_:)` at zero grants. It can also arrive **after** a
    /// positive settings read, because authorisation can be revoked between the two calls —
    /// which is exactly why R-82.4 makes a failure a route change rather than a log line.
    case failed(domain: String, code: Int)

    public var isDelivered: Bool { self == .delivered }
}

/// The seam over `UNUserNotificationCenter`.
///
/// A protocol, so the unit lane can drive every authorisation state, every category-registration
/// order and the `UNErrorDomain` 1 failure **without a grant, a prompt or a notification centre**
/// — which is what lets the whole of R-82 be a T1 claim.
@MainActor
public protocol NotificationCentring: AnyObject {
    /// `getNotificationSettings`, as a raw status.
    ///
    /// P-134 measured this obtainable at zero grants, **never prompting**, and answering
    /// completely — which is the entire reason `requestAuthorization` is not on the routing path
    /// (R-82.1) and why R-96g can pin it to one file that is not this one.
    func authorizationStatus(_ completion: @escaping @MainActor (Int) -> Void)

    /// Register the notification's actions.
    func setCategories(_ identifiers: Set<String>)

    /// What is registered right now. P-134 measured `setNotificationCategories` silently taking
    /// **zero** categories while unauthorised, so this is read back rather than assumed.
    var registeredCategoryIdentifiers: Set<String> { get }

    func add(
        identifier: String,
        title: String,
        body: String,
        categoryIdentifier: String,
        completion: @escaping @MainActor (NotificationAddResult) -> Void
    )
}

/// **The top rung as a notification, and the route around every refusal** (R-82, P-134, F-58).
///
/// Four rulings live in here, and three of them are things P-134 measured rather than things the
/// documentation says:
///
/// 1. **`requestAuthorization` is never called from this file.** The router reads
///    `getNotificationSettings`, which never prompts. Authorisation is requested only from an
///    explicit user action in the Intervention settings pane, which is the single call site
///    R-96g pins — and it is why no acceptance criterion in this epic depends on a grant.
/// 2. **Categories are registered *after* authorisation, never at launch.**
///    `setNotificationCategories` silently takes zero categories while unauthorised, so an app
///    that registered once at launch would ship a notification rung with no Return, no Snooze
///    and no "This is relevant" — a notification a person could not answer, which is the
///    anti-pattern the whole correction economy exists to avoid.
/// 3. **A delivery failure is a route change.** `add(_:)`'s completion demotes the rung to the
///    in-app recommitment surface through `SurfaceRouter.afterNotificationFailure(…)` and
///    records `.deferred(.notificationDeliveryFailed)` — so nothing advances and nothing is
///    spent, because nobody saw it (R-81).
/// 4. **`denied` and `notRequested` are identical in delivery.** That is the router's ruling and
///    this type never second-guesses it: it asks the router where the rung goes and does what it
///    is told.
@MainActor
public final class NotificationDelivery {
    private let centre: any NotificationCentring
    /// What the person tapped, **and which delivery they tapped it on** (focus-zrs). Wired by the
    /// composition root, exactly as every other surface's callback is.
    public var onAction: ((NudgeNotificationResponse) -> Void)?

    /// The last status read from `getNotificationSettings`. `notRequested` until the first read,
    /// which is the honest default: the app has not looked, and it has certainly not asked.
    public private(set) var authorisation: NotificationAuthorisation = .notRequested

    /// **Must stay zero in every automated run** (§3.F.37, §4.5). Nothing in this file can
    /// increment it, because nothing in this file calls the API that would — it is published
    /// here so the self-check can report the number that proves it.
    public private(set) var requestAuthorizationCallCount = 0

    /// How many times the categories have actually been registered. Read by the unit lane:
    /// "exactly once, and only after authorisation" is a count, not a promise.
    public private(set) var categoryRegistrationCount = 0

    public init(centre: any NotificationCentring) {
        self.centre = centre
    }

    // MARK: - Reading the state, without ever asking for it

    /// Re-read `getNotificationSettings` and register the categories if — and only if — the
    /// answer permits delivery.
    ///
    /// Called at launch and whenever the settings pane's one sanctioned `requestAuthorization`
    /// returns, so a grant that arrives mid-session brings the actions with it.
    public func refresh(_ completion: (@MainActor (NotificationAuthorisation) -> Void)? = nil) {
        centre.authorizationStatus { [weak self] raw in
            guard let self else { return }
            self.authorisation = NotificationAuthorisation.decode(authorizationStatus: raw)
            self.registerCategoriesIfPermitted()
            completion?(self.authorisation)
        }
    }

    /// P-134's second consequence, as code: registration happens **after** a positive read, and
    /// only once.
    private func registerCategoriesIfPermitted() {
        guard authorisation.permitsDelivery else { return }
        guard !centre.registeredCategoryIdentifiers.contains(NudgeNotificationCategory.identifier)
        else { return }
        centre.setCategories([NudgeNotificationCategory.identifier])
        categoryRegistrationCount += 1
    }

    /// Whether the actions are actually installed. A notification rung offered without them
    /// would be a sentence with no way to answer it.
    public var hasRegisteredActions: Bool {
        centre.registeredCategoryIdentifiers.contains(NudgeNotificationCategory.identifier)
    }

    // MARK: - Delivering, and routing around a refusal

    /// Deliver the recommitment rung as a notification, and say what actually happened.
    ///
    /// - Parameters:
    ///   - presentation: the same value the panel would have drawn, so the notification and the
    ///     panel say the same sentence in the same deck.
    ///   - surroundings: the facts the router needs to pick the fallback surface if this fails.
    ///   - deliveryID: **the rung this banner belongs to**, minted by the caller and used as the
    ///     `UNNotificationRequest` identifier (focus-zrs). It used to be `UUID().uuidString`
    ///     generated here and thrown away, so nothing that came back could be tied to anything —
    ///     and a press on a banner from an hour ago reached the live loop unchallenged. The caller
    ///     mints it because the caller is the only object that knows when the rung is over.
    /// - Returns: `.delivered(.notification)` when the system took it, or the **route change**
    ///   R-82.4 requires — a `.deferred(.notificationDeliveryFailed)` record and a demotion to an
    ///   in-app surface.
    // **`deliver(…)` is gone** (U-2). The notification was the recommitment rung's surface and
    // nothing else's, and that rung is deferred to focus-5ab — so this app posts no notifications
    // at all. What is kept is the half that still has work to do: reading the authorisation for
    // the settings pane, registering the action categories, and decoding a press on a banner that
    // an earlier build posted and the person has not yet cleared.

    /// A tap came back from the notification centre.
    ///
    /// - Parameter requestIdentifier: `UNNotificationResponse.notification.request.identifier` —
    ///   which banner was pressed. Passed through untouched: this boundary decodes, it never
    ///   decides, and whether the delivery is still open is the loop's question to answer
    ///   (focus-zrs).
    public func handle(actionIdentifier: String, requestIdentifier: String) {
        guard let action = NudgeNotificationAction.allCases.first(
            where: { $0.identifier == actionIdentifier }
        ) else { return }
        onAction?(NudgeNotificationResponse(action: action, deliveryID: requestIdentifier))
    }
}

/// The facts the router needs to choose a fallback, gathered once so `deliver(…)` does not have
/// to reach for e03's types itself.
public struct NotificationSurroundings: Sendable, Equatable {
    public let presentation: PresentationState
    public let media: MediaActivity
    public let reducedInterruption: Bool
    public let menuBarVisible: Bool

    public init(
        presentation: PresentationState = .notPresenting,
        media: MediaActivity = .idle,
        reducedInterruption: Bool = false,
        menuBarVisible: Bool = true
    ) {
        self.presentation = presentation
        self.media = media
        self.reducedInterruption = reducedInterruption
        self.menuBarVisible = menuBarVisible
    }
}

/// The real `UNUserNotificationCenter`, behind the seam.
///
/// The **only** file in the package that imports UserNotifications, and it contains no call that
/// can raise a prompt: `getNotificationSettings`, `setNotificationCategories`, `add(_:)` and a
/// delegate. `requestAuthorization` is not here — it is the settings pane's one user-initiated
/// action, which is what makes SC-5 structural rather than observed (R-96g).
@MainActor
public final class SystemNotificationCentre: NSObject, NotificationCentring {
    private let centre: UNUserNotificationCenter
    /// Forwarded to `NotificationDelivery.handle(actionIdentifier:requestIdentifier:)` by the
    /// composition root. Both identifiers, because *which button* and *which banner* are two
    /// different facts and only the second one can tell a live press from a stale one (focus-zrs).
    public var onAction: ((_ actionIdentifier: String, _ requestIdentifier: String) -> Void)?
    public private(set) var registeredCategoryIdentifiers: Set<String> = []

    /// The deck the actions are titled from. The notification's buttons are registered once, so
    /// they carry the deck in force at the moment authorisation was granted; changing the voice
    /// re-registers them through `NotificationDelivery.refresh(_:)`.
    private let voice: NudgeVoice

    public init(voice: NudgeVoice = .standard) {
        self.centre = UNUserNotificationCenter.current()
        self.voice = voice
        super.init()
        centre.delegate = self
    }

    public func authorizationStatus(_ completion: @escaping @MainActor (Int) -> Void) {
        centre.getNotificationSettings { settings in
            let raw = settings.authorizationStatus.rawValue
            Task { @MainActor in completion(raw) }
        }
    }

    public func setCategories(_ identifiers: Set<String>) {
        let categories: Set<UNNotificationCategory> = Set(
            identifiers.map { identifier in
                UNNotificationCategory(
                    identifier: identifier,
                    actions: NudgeNotificationAction.allCases.map { action in
                        UNNotificationAction(
                            identifier: action.identifier,
                            title: NudgeCopy.string(
                                voice: voice,
                                action.copyKey,
                                // The return action's template names the target; in a
                                // notification there is no room for one, so the empty string is
                                // substituted and the line reads as the bare verb it is.
                                arguments: action == .returnToTask ? [""] : []
                            ),
                            options: [.foreground]
                        )
                    },
                    intentIdentifiers: []
                )
            }
        )
        centre.setNotificationCategories(categories)
        registeredCategoryIdentifiers = identifiers
    }

    public func add(
        identifier: String,
        title: String,
        body: String,
        categoryIdentifier: String,
        completion: @escaping @MainActor (NotificationAddResult) -> Void
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = categoryIdentifier
        // No trigger: deliver now or not at all. A scheduled nudge is a nudge about a moment
        // that has passed.
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        centre.add(request) { error in
            let result: NotificationAddResult
            if let error = error as NSError? {
                result = .failed(domain: error.domain, code: error.code)
            } else {
                result = .delivered
            }
            Task { @MainActor in completion(result) }
        }
    }
}

extension SystemNotificationCentre: UNUserNotificationCenterDelegate {
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.actionIdentifier
        // Which banner, not only which button (focus-zrs). The request identifier is the delivery
        // token the loop minted when the rung went out; without it a press on a banner the person
        // left in Notification Centre yesterday is indistinguishable from one on the rung that is
        // actually on screen.
        let request = response.notification.request.identifier
        await MainActor.run { self.onAction?(identifier, request) }
    }

    /// Show the nudge even while the app is frontmost.
    ///
    /// `.banner` and nothing else: no sound and no badge. Sound is never the sole channel
    /// (F-146) and this rung already has a visible one; a badge would be a count of unanswered
    /// accusations sitting on the Dock icon, which is a score to defend (D-01).
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}
