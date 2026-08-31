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

/// The category a recommitment notification was delivered under.
///
/// **Kept, and deliberately not renamed** (focus-wy0). Nothing registers it any more — this app
/// posts no notifications — but a banner an earlier build posted can still be sitting in
/// Notification Centre with this identifier on it, for as long as the person leaves it there.
/// Renaming it would orphan those banners: the press would arrive naming a category this build
/// does not recognise, and `NudgeHost.resolveFromNotification(…)` could no longer say what it was
/// refusing. focus-5ab, which brings the recommitment rung back, registers it again.
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

    /// **The raw statuses the fold below covers**, and the reason it is a range rather than the
    /// five cases the framework declares today.
    ///
    /// `UNAuthorizationStatus` is an `NSInteger` at the boundary, so the number that arrives is
    /// whatever the running OS decides to send — including one no build of this app has seen. The
    /// fold therefore covers the declared five, the two sentinels either side of them (a negative
    /// status and one past the end, which is what a future case looks like on arrival), and four
    /// more of the room a future release has to grow into.
    public static let foldedRawStatuses: [Int] = Array(-2...8)

    /// **The whole decode, folded once and written down once** (focus-652).
    ///
    /// This exists because the gate used to assert that the decoded value was one of the four the
    /// decoder is *total over* — a restatement of the codomain, which no change to the decode
    /// could make red. The subject of a reading about this boundary is the **mapping**, not the
    /// enum, so the mapping is what is published and what is pinned: one string, compared against
    /// one committed literal in `NotificationDeliveryTests`, in both directions.
    ///
    /// A `|`-separated `raw:state` table rather than a digest, so a red gate prints the cell that
    /// moved instead of two hexadecimal numbers a reader has to go and decode by hand.
    public static var decodeTable: String {
        foldedRawStatuses
            .map { "\($0):\(decode(authorizationStatus: $0).rawValue)" }
            .joined(separator: "|")
    }

    /// How many cells the table above folded. Asserted **before** the table it qualifies, for
    /// R-96o's reason: a fold that quietly shrinks is invisible in an unchanged verdict.
    public static var decodeTableCells: Int { foldedRawStatuses.count }
}

/// The seam over `UNUserNotificationCenter`.
///
/// A protocol, so the unit lane can drive every authorisation state **without a grant, a prompt
/// or a notification centre**. It described three calls; two of them — `setCategories` and
/// `add(_:)`, with the `NotificationAddResult` the second answered in — went with the rung they
/// served (focus-wy0), and a seam that still offered them would be a seam over a capability the
/// app had stopped having.
@MainActor
public protocol NotificationCentring: AnyObject {
    /// `getNotificationSettings`, as a raw status.
    ///
    /// P-134 measured this obtainable at zero grants, **never prompting**, and answering
    /// completely. It is the only thing this app ever asks the notification centre, and since
    /// focus-wy0 the answer decides nothing: it is reported by the self-check so the
    /// `notification-denied` gate stage can say what grant state this Mac was in while it proved
    /// the product works without one.
    func authorizationStatus(_ completion: @escaping @MainActor (Int) -> Void)
}

/// **What is left of the notification boundary once the app stopped posting notifications**
/// (U-2, focus-wy0, P-134).
///
/// It delivered the recommitment rung, and that rung is deferred to focus-5ab. Three things went
/// with it, in two rounds:
///
/// 1. **`deliver(…)`** (U-2). No rung routes to a notification, so there is nothing to deliver,
///    no `UNErrorDomain` 1 failure to demote, and no route change to record.
/// 2. **The category registration** (focus-wy0). It ran at every launch that found a grant, and
///    registered three actions — Return, Snooze, "This is relevant" — onto a category no banner
///    would ever carry. An app that registers buttons for notifications it does not send is
///    telling the system something untrue about itself.
/// 3. **The permission request** (focus-wy0). It was never in this file; it was the settings
///    pane's "Turn on notifications" button, offered to every fresh install. It is now nowhere in
///    the repository, which is what makes `requestAuthorizationCallCount == 0` a fact about the
///    call graph rather than about a counter somebody remembered to leave alone.
///
/// Two things remain, and both still have work to do: **reading** the authorisation, which P-134
/// measured never prompts and which the `notification-denied` stage reports; and **decoding** a
/// press on a banner an earlier build posted, which `NudgeHost` must be able to refuse.
@MainActor
public final class NotificationDelivery {
    private let centre: any NotificationCentring
    /// What the person tapped, **and which delivery they tapped it on** (focus-zrs). Wired by the
    /// composition root, exactly as every other surface's callback is.
    public var onAction: ((NudgeNotificationResponse) -> Void)?

    /// The last status read from `getNotificationSettings` — **`nil` until one has landed**
    /// (focus-652).
    ///
    /// It used to be `.notRequested` before the first read, and that made one value mean two
    /// different things: the OS's *"nobody has ever asked"* and this object's *"the completion has
    /// not come back yet"*. `refresh(_:)` is asynchronous and nothing sequenced it against the
    /// self-check's report assembly, so the reported authorisation was in fact **which side of a
    /// race the report landed on** — measured across five gate runs on one machine at one commit,
    /// the two reports of a single run disagreed with each other, and every stage was green.
    ///
    /// An `Optional` is the honest shape: *unread* is not an authorisation state, and a reader who
    /// needs to know the read happened can now find out.
    public private(set) var authorisation: NotificationAuthorisation?

    /// **How many reads have completed.** The reading that says the read *happened* — which is
    /// what the `notification-denied` stage's pass line has always claimed and never tested.
    /// `AppComposition.start()` has exactly one call to `refresh()`; delete it and this goes to
    /// zero and the stage goes red, which is the whole point of counting it.
    public private(set) var authorisationReadCount = 0

    /// **Must stay zero in every automated run** (§3.F.37, §4.5), and since focus-wy0 it cannot
    /// be anything else in any run at all: `requestAuthorization(` appears in **no** file of this
    /// repository, so there is no code path — sanctioned, accidental or future — that could
    /// increment it. Published so the self-check can report the number rather than a lint's
    /// opinion of it.
    public private(set) var requestAuthorizationCallCount = 0

    public init(centre: any NotificationCentring) {
        self.centre = centre
    }

    // MARK: - Reading the state, without ever asking for it

    /// Re-read `getNotificationSettings`.
    ///
    /// Called once at launch. It never prompts (P-134), and what it learns changes nothing about
    /// how the app behaves — it is the reading the `notification-denied` stage prints so that
    /// "this Mac was at *x* and every rung still landed in-app" is one measurement rather than
    /// two assumptions.
    public func refresh(_ completion: (@MainActor (NotificationAuthorisation) -> Void)? = nil) {
        centre.authorizationStatus { [weak self] raw in
            guard let self else { return }
            let decoded = NotificationAuthorisation.decode(authorizationStatus: raw)
            self.authorisation = decoded
            self.authorisationReadCount += 1
            completion?(decoded)
        }
    }

    // MARK: - A press on a banner an earlier build posted

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

/// The real `UNUserNotificationCenter`, behind the seam.
///
/// The **only** file in the package that imports UserNotifications, and it now contains exactly
/// two calls: `getNotificationSettings`, which P-134 measured never prompting, and a delegate
/// that receives a press. Neither can raise a permission dialog, and neither can post a banner —
/// `setNotificationCategories` and `add(_:)` went with the rung they served (focus-wy0), so the
/// app's whole relationship with the notification centre is now *listening*.
@MainActor
public final class SystemNotificationCentre: NSObject, NotificationCentring {
    private let centre: UNUserNotificationCenter
    /// Forwarded to `NotificationDelivery.handle(actionIdentifier:requestIdentifier:)` by the
    /// composition root. Both identifiers, because *which button* and *which banner* are two
    /// different facts and only the second one can tell a live press from a stale one (focus-zrs).
    public var onAction: ((_ actionIdentifier: String, _ requestIdentifier: String) -> Void)?

    public override init() {
        self.centre = UNUserNotificationCenter.current()
        super.init()
        centre.delegate = self
    }

    public func authorizationStatus(_ completion: @escaping @MainActor (Int) -> Void) {
        centre.getNotificationSettings { settings in
            let raw = settings.authorizationStatus.rawValue
            Task { @MainActor in completion(raw) }
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
