import Foundation

/// One cell of the committed routing table.
///
/// R-82 requires the table to be a value rather than a shape buried in a function, for one
/// concrete reason: the Intervention settings pane renders **this** to answer "what does this app
/// do if I say no", so the copy cannot drift from the behaviour. A pane that described the
/// routing in prose would be a pane somebody has to remember to edit.
public struct SurfaceRoutingRow: Sendable, Equatable, Hashable {
    public let rung: LadderRung.Kind
    public let authorisation: NotificationAuthorisation
    public let route: SurfaceRoute

    public init(rung: LadderRung.Kind, authorisation: NotificationAuthorisation, route: SurfaceRoute) {
        self.rung = rung
        self.authorisation = authorisation
        self.route = route
    }
}

/// What a failed notification produces: **a route change, not a log line** (R-82.4).
///
/// P-134 measured `add(_:)` failing with `UNErrorDomain` code 1 — "Notifications are not allowed
/// for this application" — and it can arrive *after* a positive settings read, because
/// authorisation can be revoked between the two calls. Two things follow, and this type carries
/// both so a call site cannot take one and forget the other:
///
/// * the attempt is recorded as `.deferred(.notificationDeliveryFailed)` — it reached nobody, so
///   it spends no cap and advances no ladder (R-81);
/// * the rung is **re-routed** to the in-app recommitment surface, so the person still hears the
///   sentence the ladder had decided to say.
public struct NotificationFailure: Sendable, Equatable, Hashable {
    /// What the failed attempt is written down as.
    public let recorded: RungDelivery
    /// Where the rung goes instead.
    public let demotedTo: SurfaceRoute

    fileprivate init(demotedTo: SurfaceRoute) {
        self.recorded = .deferred(.notificationDeliveryFailed)
        self.demotedTo = demotedTo
    }
}

/// **Which surface a rung reaches, and why none can** — a pure function of typed inputs (R-82).
///
/// ## Four rulings live inside it
///
/// 1. **`requestAuthorization` is never on the routing path.** P-134 measured that
///    `getNotificationSettings` is obtainable at zero grants, **never prompts**, and answers
///    completely — so the whole router is decidable from it. Authorisation is requested only
///    from an explicit user action in the settings pane (R-96g), which is why no acceptance
///    criterion in this epic depends on a grant.
/// 2. **`denied` and `notRequested` differ in what the app may *offer*, never in what it may
///    *deliver*.** Both route the top rung to the in-app recommitment surface. A person who has
///    never been asked and a person who said no get **identical** behaviour; the only difference
///    is one line in a settings pane, and `SurfaceRouterTests` asserts the identity in every cell
///    of the matrix rather than at one point.
/// 3. **Reduced interruption is a flag in here, not a second surface stack** (R-92, F-148).
///    Panel rungs become menu-bar badges, the question becomes a popover row, and the
///    notification rung is unchanged — it is already quiet by construction. `silentVisual` is the
///    same mechanism spelled as a deck: `NudgeVoice.renderedRung(for:)` maps the panel rung onto
///    the ambient one before this function reads it.
/// 4. **A delivery failure is a route change** — `afterNotificationFailure(…)`, above.
///
/// ## A badge is a menu-bar thing, and the menu bar can be hidden
///
/// P-131 measured the menu-bar layer's owners collapsing from eleven to one during a full-screen
/// space while our own status item stayed *listed* as on screen. So **every** route that lands in
/// the menu bar — the ambient rung's glyph and the popover badge alike — is checked against
/// `menuBarVisible`, and answers `.unavailable(.menuBarHidden)` when it is not. A badge routed
/// into a hidden menu bar would be R-81's failure wearing a different costume: an "escalation"
/// nobody could see.
public struct SurfaceRouter: Sendable {
    /// **Where this rung goes.**
    ///
    /// - Parameters:
    ///   - rung: the ladder rung the machine decided on, *before* any deck remapping.
    ///   - authorisation: from `getNotificationSettings`, which never prompts.
    ///   - presentation: e03's `PresentationState`, read through `suppressesOverlays`.
    ///   - media: e03's `MediaActivity`, read through `suppressesIntervention`. In practice gate
    ///     6 has already suppressed the interruption; this is the backstop that makes a panel
    ///     over a call unreachable even from a caller who skipped the stack, because a panel over
    ///     a call is a panel everybody on the call can see.
    ///   - reducedInterruption: F-148's flag, forced on by Reduce Motion.
    ///   - menuBarVisible: whether the system menu bar is actually on screen (P-131).
    ///   - voice: the deck. `silentVisual` is a **routing** deck, not a copy deck.
    public static func route(
        rung: LadderRung.Kind,
        authorisation: NotificationAuthorisation,
        presentation: PresentationState,
        media: MediaActivity,
        reducedInterruption: Bool,
        menuBarVisible: Bool,
        voice: NudgeVoice
    ) -> SurfaceRoute {
        switch voice.renderedRung(for: rung) {
        case .ambient:
            // The glyph, and nothing else. Its only failure mode is a menu bar that is not
            // there — which is a deferral, never a suppression, because the rung was wanted and
            // merely undeliverable (R-81).
            return resolve(.menuBar, presentation: presentation, menuBarVisible: menuBarVisible)

        case .panel:
            // F-35, and the reason it is active code rather than a hope about window levels:
            // P-130 measured a `.fullScreenAuxiliary` panel drawn plainly on top of a real
            // full-screen space, and the captured frame was read. The window server will not
            // protect a presentation for us.
            guard !presentation.suppressesOverlays else {
                return .unavailable(.presentationActive)
            }
            if reducedInterruption || media.suppressesIntervention {
                return resolve(
                    .popoverBadge, presentation: presentation, menuBarVisible: menuBarVisible
                )
            }
            return .surface(.panel)

        case .recommitment:
            // The one rung a system surface can carry — and only where the system will actually
            // carry it. Neither a presentation nor a call demotes it: a notification is quiet by
            // construction, and `UNUserNotificationCenter` honours the system Focus for free,
            // which is the only Focus claim this app makes (P-137, R-85).
            if authorisation.permitsDelivery { return .surface(.notification) }

            guard !presentation.suppressesOverlays else {
                return .unavailable(.presentationActive)
            }
            if reducedInterruption || voice.isRoutingDeck || media.suppressesIntervention {
                return resolve(
                    .popoverBadge, presentation: presentation, menuBarVisible: menuBarVisible
                )
            }
            return .surface(.panel)
        }
    }

    /// **Where a question goes.**
    ///
    /// It takes no `authorisation`, and that is the ruling rather than an omission: **a question
    /// is never a notification.** U-1's affordance is "one click teaches the app", and a
    /// notification's actions are the system's to collapse, defer and summarise — a question
    /// answered from a notification summary three hours later would be a question about a moment
    /// that has passed. The three in-app surfaces are also what make the `notification-denied`
    /// gate stage possible at zero grants.
    public static func routeQuery(
        presentation: PresentationState,
        media: MediaActivity,
        reducedInterruption: Bool,
        menuBarVisible: Bool,
        voice: NudgeVoice
    ) -> SurfaceRoute {
        guard !presentation.suppressesOverlays else { return .unavailable(.presentationActive) }

        let quiet = reducedInterruption || media.suppressesIntervention
        let surface: NudgeSurface = quiet ? .popoverBadge : voice.querySurface

        return resolve(surface, presentation: presentation, menuBarVisible: menuBarVisible)
    }

    /// The route a rung takes when the notification the router chose came back with an error.
    ///
    /// Re-routed exactly as if the authorisation had been `denied`, because as far as this
    /// delivery is concerned it was: the system refused. Nothing about the ladder moves, because
    /// the failed attempt is recorded as a deferral.
    public static func afterNotificationFailure(
        rung: LadderRung.Kind,
        presentation: PresentationState,
        media: MediaActivity,
        reducedInterruption: Bool,
        menuBarVisible: Bool,
        voice: NudgeVoice
    ) -> NotificationFailure {
        NotificationFailure(
            demotedTo: route(
                rung: rung,
                authorisation: .denied,
                presentation: presentation,
                media: media,
                reducedInterruption: reducedInterruption,
                menuBarVisible: menuBarVisible,
                voice: voice
            )
        )
    }

    // MARK: - The committed table

    /// The whole rung × authorisation matrix, under the conditions a settings pane describes:
    /// nothing presenting, no microphone running, the menu bar where it usually is.
    ///
    /// This is what the Intervention pane renders, and what a snapshot test pins — so "what
    /// happens if I say no" is answered by the same value that decides it.
    public static func table(
        reducedInterruption: Bool = false,
        voice: NudgeVoice = .standard
    ) -> [SurfaceRoutingRow] {
        LadderRung.Kind.allCases.flatMap { rung in
            NotificationAuthorisation.allCases.map { authorisation in
                SurfaceRoutingRow(
                    rung: rung,
                    authorisation: authorisation,
                    route: route(
                        rung: rung,
                        authorisation: authorisation,
                        presentation: .notPresenting,
                        media: .idle,
                        reducedInterruption: reducedInterruption,
                        menuBarVisible: true,
                        voice: voice
                    )
                )
            }
        }
    }

    // MARK: - Helpers

    /// A chosen surface, checked against whether it can be seen.
    ///
    /// The two menu-bar surfaces are the only ones a full-screen space can hide, and both are
    /// checked here so the rule lives in one place rather than at each of its four call sites.
    private static func resolve(
        _ surface: NudgeSurface,
        presentation: PresentationState,
        menuBarVisible: Bool
    ) -> SurfaceRoute {
        switch surface {
        case .menuBar, .popoverBadge:
            guard menuBarVisible, !presentation.suppressesOverlays else {
                return .unavailable(.menuBarHidden)
            }
            return .surface(surface)
        case .panel, .notification:
            return .surface(surface)
        }
    }
}
