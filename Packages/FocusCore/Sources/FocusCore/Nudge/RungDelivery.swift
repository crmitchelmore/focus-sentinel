import Foundation

/// Why a rung the app *tried* to show could not be seen.
///
/// P-131 is the measurement that makes this type necessary. While `FocusDecoy.app` owned a real
/// full-screen space, the windows in the menu-bar layer band collapsed from **eleven** owners to
/// **one** — and our own status-item window stayed *listed* as on screen the whole time. A
/// ladder that treated "I called `orderFront`" as delivery would escalate through rungs nobody
/// saw and arrive at the notification with its whole proportionality story already spent.
///
/// **A window being listed on screen is not a window being visible.**
public enum DeferralReason: String, Sendable, CaseIterable, Codable, Hashable {
    /// A full-screen space is up, so the system menu bar is hidden and the ambient rung has
    /// nowhere to appear (P-131).
    case menuBarHidden
    /// F-35's presentation gate is closed. The panel is suppressed and the ambient rung is
    /// deferred; the app is **mute**, not quietly escalating. When the presentation ends the
    /// ladder resumes at the rung it never left.
    case presentationActive
    /// `UNUserNotificationCenter.add(_:)` came back with an error *after* a positive settings
    /// read — P-134 measured `UNErrorDomain` code 1, "Notifications are not allowed for this
    /// application". Delivery failure is a **route change**, not a log line (R-82.4).
    ///
    /// **Unreachable at HEAD, and gated as such** (U-2). No rung routes to a notification since
    /// the recommitment rung was deferred to focus-5ab, so nothing can produce this reason; the
    /// self-check asserts `"notification" not in surfacesARungCanReach` in every run. It is
    /// declared, rather than deleted with its string, for the reason `NudgeSurface.notification`
    /// is: `SurfaceRoute` is switched over totally in the settings pane and in the router, and a
    /// missing case buys a `default:` arm — which is how an unreachable path becomes an
    /// unnoticed one. The claim to check is the gate's, not this comment's.
    case notificationDeliveryFailed
    /// No surface exists that can carry this rung in the state the app is actually in.
    case noSurfaceAvailable

    // **It carried four sentences a person could never be in a position to read** (focus-pzl).
    //
    // A deferral is defined by nobody being able to see the surface: the menu bar is hidden, or a
    // presentation is up. Every one of `nudge.deferred.*` described the *inside* of a moment
    // whose whole content is that the app is not on screen, and by the time there is a screen to
    // read it on the ladder has resumed at the rung it never left. The number that matters —
    // `deferredRungShare` — is a diagnostic for e08's over-firing presentation gate, and a
    // diagnostic is not a sentence.
    //
    // The type stays. It is the discriminator that keeps `RungDelivery` from collapsing into a
    // `Bool`, and `SurfaceRoute.unavailable` carries it.
}

/// **What happened when the app tried to speak** — and the reason it is not a `Bool`.
///
/// Three outcomes, and the middle one is the whole of R-81:
///
/// | case | meaning | advances the ladder | spends a cap | starts the escalation clock |
/// |---|---|---|---|---|
/// | `delivered` | it reached a surface that can be seen | yes | yes | yes |
/// | `deferred` | the surface exists but cannot be seen now | **no** | **no** | **no** |
/// | `suppressed` | the app chose not to speak (R-84) | no | no | no |
///
/// **There is deliberately no `Bool` projection** — no `isDelivered`, no `succeeded`, no
/// `asBool`. A `Bool` is exactly the collapse this type exists to prevent: `if delivered {
/// escalate() }` would treat a deferral as a delivery the first time somebody wrote it that
/// way, and the failure would be invisible in review because the line reads correctly. Every
/// accessor below returns the **payload**, optionally, so a call site has to say which of the
/// three it is handling. `nudge.escalationsFromDeferred == 0` asserts the same invariant as a
/// number.
///
/// A deferral is recorded in `InterventionRecord` with `disposition == "deferred"` and reported
/// as `deferredRungShare`, so the number is visible rather than inferred — a rising one means
/// the presentation gate is over-firing, which is a signal for e08 rather than a silent loss.
public enum RungDelivery: Sendable, Equatable, Hashable {
    /// It reached a surface a person could actually see.
    case delivered(NudgeSurface)
    /// The surface exists but cannot be seen now.
    case deferred(DeferralReason)
    /// The app chose not to speak at all.
    case suppressed(NudgeSuppressionReason)

    /// The surface that took it, when one did. `nil` is not "failure" — it is "ask which of the
    /// other two this was".
    public var surface: NudgeSurface? {
        switch self {
        case .delivered(let surface): surface
        case .deferred, .suppressed: nil
        }
    }

    /// Why it could not be seen, when it could not.
    public var deferralReason: DeferralReason? {
        switch self {
        case .deferred(let reason): reason
        case .delivered, .suppressed: nil
        }
    }

    /// Why the app stayed quiet, when it did.
    public var suppressionReason: NudgeSuppressionReason? {
        switch self {
        case .suppressed(let reason): reason
        case .delivered, .deferred: nil
        }
    }
}
