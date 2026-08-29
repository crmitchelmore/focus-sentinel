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
    /// `UNUserNotificationCenter`. **Declared, and reached by nothing** (U-2, focus-wy0). It was
    /// the recommitment rung's surface and that rung is deferred to focus-5ab, which needs this
    /// case back; and `NudgeHost.resolveFromNotification(…)` must still be able to name the
    /// surface a banner an earlier build posted came from, in order to refuse a press on it.
    /// P-134 measured that at zero grants every setting reads `.notSupported` and `add(_:)` fails
    /// with `UNErrorDomain` code 1 — which is why nothing routes here and nothing asks to.
    case notification
    /// A badge and a row in the menu-bar popover. Where the panel rungs and the query go when
    /// reduced interruption is on, or when the voice is `silentVisual` — quiet, legible, and
    /// still answerable.
    case popoverBadge

    /// **Whether a nudge placed here offers the person something to press.**
    ///
    /// | surface | offers a correction | what is actually drawn |
    /// |---|---|---|
    /// | `panel` | **yes** | `AccusationPanelView`, with the rung's full action set |
    /// | `notification` | **yes** | the presentation's actions, as notification buttons |
    /// | `menuBar` | no | a glyph. There is nothing on it to press |
    /// | `popoverBadge` | no | a badge row. It carries a *question*, not the correction ladder |
    ///
    /// It arrived as `PreemptionCredit`'s test for whether a displaced question had been handed
    /// something richer in its place, and it outlived preemption because it answers a question the
    /// interruption slot needs answered too: **a rung standing on a surface with nothing to press
    /// is not occupying the screen** (focus-k42). Nothing can ever take an ambient glyph down —
    /// it carries no actions, so `resolve(…)` is unreachable from it — so a glyph that held the
    /// slot would hold it for the life of the session.
    public var offersACorrection: Bool {
        switch self {
        case .panel, .notification: true
        case .menuBar, .popoverBadge: false
        }
    }

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
/// prompts**, and answers completely — so what this app knows about notifications, it knows
/// without ever asking anybody anything.
///
/// **It decides nothing, and that is the whole of its remaining job** (focus-wy0). This app posts
/// no notifications: since U-2 no rung routes to one, and `SurfaceRouter` does not take this type
/// at all. What is left is a *reading* — reported by the self-check so the `notification-denied`
/// gate stage can say what grant state this Mac was actually in when it proved the app works
/// without one. A reading is evidence. It is not a switch, and this type deliberately no longer
/// offers one:
///
/// * `permitsDelivery` went with `deliver(…)`. An app that delivers nothing has no business
///   publishing a belief about whether it may.
/// * `mayOfferToEnable` went with the button it gated. It answered `true` for `notRequested`
///   alone — which is **every fresh install** — so the pane offered a system permission prompt to
///   everybody who had never seen one, for a capability the router could not spend.
public enum NotificationAuthorisation: String, Sendable, CaseIterable, Codable, Hashable {
    /// The user said yes.
    case authorised
    /// The user said no.
    case denied
    /// Nobody has asked, and since focus-wy0 nothing in this app ever will. P-134 measured
    /// `authorizationStatus == 0` from an ad-hoc-signed bundle that never called
    /// `requestAuthorization`, with every setting `.notSupported`.
    case notRequested
    /// Provisional (quiet) delivery.
    case provisional
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
