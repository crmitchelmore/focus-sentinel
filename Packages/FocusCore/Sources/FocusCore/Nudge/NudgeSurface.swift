import Foundation

/// **Where a nudge can actually appear.** Four surfaces, and no fifth.
///
/// The set is closed on purpose. F-148's "reduced interruption" is a **routing flag inside the
/// existing router**, not a parallel surface stack (R-92), and the `silentVisual` voice is a
/// routing deck rather than a copy deck — both of them remap rungs onto the surfaces below
/// rather than adding one. e08's notch is a second *renderer* for the ambient rung, not a fifth
/// surface. That is what keeps the routing table a table a person can read.
public enum NudgeSurface: String, Sendable, CaseIterable, Codable, Hashable {
    /// The status-item glyph. Silent: no panel, no sound, no motion beyond the glyph change.
    /// The only surface the ambient rung has, and the only one a full-screen space can hide
    /// (P-131) — which is why an ambient rung over a presentation is `deferred`, never
    /// `delivered`.
    case menuBar
    /// The non-activating `NSPanel` (R-89), shown with `orderFrontRegardless()` and never made
    /// key programmatically. Carries the whole correction economy, because a nudge you cannot
    /// answer back to is the anti-pattern the product boundary forbids.
    case panel
    /// `UNUserNotificationCenter`. **Reachable only when authorisation is `authorised` or
    /// `provisional`** — P-134 measured that at zero grants every setting reads `.notSupported`
    /// and `add(_:)` fails with `UNErrorDomain` code 1, so a route here in any other state is a
    /// route to nothing.
    case notification
    /// A badge and a row in the menu-bar popover. Where the panel rungs and the query go when
    /// reduced interruption is on, or when the voice is `silentVisual` — quiet, legible, and
    /// still answerable.
    case popoverBadge

    /// Whether this surface belongs to the application itself rather than to the system.
    ///
    /// The three in-app surfaces are what make the `notification-denied` gate stage possible:
    /// every rung is deliverable with no grant of any kind, which is what discharges standing
    /// condition 5 for this epic.
    public var isInApp: Bool { self != .notification }

    /// Whether reaching this surface needs a TCC-style authorisation the user may refuse.
    public var requiresNotificationAuthorisation: Bool { self == .notification }
}

/// Whether the system will deliver a notification for us.
///
/// A **plain** enum. `FocusCore` imports no UserNotifications — the R-14 matrix forbids it —
/// so this package does not name `UNAuthorizationStatus` and does not pretend to read it. The
/// mapping from the framework's raw status lives at the boundary, in `NotificationDelivery`
/// (T137), where the import is permitted; here it is four cases and their two rulings.
///
/// P-134 settles the shape: `getNotificationSettings` is obtainable at zero grants, **never
/// prompts**, and answers completely, so the whole surface router can be decided from it and
/// `requestAuthorization` is never on the routing path (R-82.1, R-96g).
public enum NotificationAuthorisation: String, Sendable, CaseIterable, Codable, Hashable {
    /// The user said yes.
    case authorised
    /// The user said no.
    case denied
    /// Nobody has asked. P-134 measured `authorizationStatus == 0` from an ad-hoc-signed
    /// bundle that never called `requestAuthorization`, with every setting `.notSupported`.
    case notRequested
    /// Provisional (quiet) delivery.
    case provisional

    /// **Whether the app may deliver a notification.**
    ///
    /// `denied` and `notRequested` differ in what the app may *offer*, never in what it may
    /// *deliver* (R-82.2) — so both answer `false` here, and both route rung 3 to the in-app
    /// recommitment panel. A user who has never been asked and a user who said no get exactly
    /// the same behaviour; the only difference is one line in a settings pane.
    public var permitsDelivery: Bool {
        switch self {
        case .authorised, .provisional: true
        case .denied, .notRequested: false
        }
    }

    /// Whether the settings pane may show the one-line "you can turn notifications on"
    /// affordance.
    ///
    /// `notRequested` **only**, and never inside a nudge. Offering it to somebody who has
    /// already said no is the re-prompt F-127's policy forbids; offering it inside a nudge
    /// would be asking for a permission at the moment a person is least inclined to think
    /// about it.
    public var mayOfferToEnable: Bool { self == .notRequested }
}

/// **Which surface a rung reaches, or why none can.**
///
/// The router's answer. It is deliberately not a `NudgeSurface?`: an absent surface has a
/// reason, the reason is what the record carries and what a person is told, and an `Optional`
/// would throw it away at exactly the moment R-81 needs it — `deferred` must be
/// distinguishable from `delivered`, and a `nil` surface with no reason attached cannot be.
public enum SurfaceRoute: Sendable, Equatable, Hashable {
    /// The rung reaches this surface.
    case surface(NudgeSurface)
    /// No surface can carry it in the state the app is actually in. The payload becomes
    /// `RungDelivery.deferred(_:)` and `InterventionRecord.disposition == "deferred"`.
    case unavailable(DeferralReason)

    /// The surface, when there is one.
    public var surface: NudgeSurface? {
        switch self {
        case .surface(let surface): surface
        case .unavailable: nil
        }
    }

    /// Why there is none, when there is none.
    public var deferralReason: DeferralReason? {
        switch self {
        case .surface: nil
        case .unavailable(let reason): reason
        }
    }

    /// The delivery this route produces once it has been acted on.
    ///
    /// The one sanctioned bridge between the router's answer and the ladder's input, so that
    /// "the route said no surface" and "the rung was deferred" cannot drift apart.
    public var delivery: RungDelivery {
        switch self {
        case .surface(let surface): .delivered(surface)
        case .unavailable(let reason): .deferred(reason)
        }
    }
}
