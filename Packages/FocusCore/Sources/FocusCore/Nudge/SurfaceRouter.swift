import Foundation

/// One cell of the committed routing table.
///
/// R-82 requires the table to be a value rather than a shape buried in a function, for one
/// concrete reason: the Intervention settings pane renders **this** to answer "where does a nudge
/// appear", so the copy cannot drift from the behaviour. A pane that described the routing in
/// prose would be a pane somebody has to remember to edit.
///
/// **It carried an `authorisation` and no longer does** (focus-wy0). The column was the honest
/// answer to *"what does this app do if I say no"* for as long as saying no could change an
/// answer. Since U-2 took the notification rung out of the ladder it changed nothing, so the pane
/// drew four identical rows per rung under four different headings — a table that looked like a
/// consequence and was a repetition.
public struct SurfaceRoutingRow: Sendable, Equatable, Hashable {
    public let rung: LadderRung.Kind
    public let route: SurfaceRoute

    public init(rung: LadderRung.Kind, route: SurfaceRoute) {
        self.rung = rung
        self.route = route
    }
}

/// **Which surface a rung reaches, and why none can** — a pure function of typed inputs (R-82).
///
/// ## Three rulings live inside it
///
/// 1. **This function does not take an authorisation, and that is now the ruling** (U-2,
///    focus-wy0). The notification was the recommitment rung's surface and nothing else's, so
///    deferring that rung to focus-5ab took the whole system surface out of the ladder with it.
///    The parameter survived the cut and went on being passed, read by nothing — and three
///    tables computed at `authorised`, `denied` and `notRequested` came back byte-identical in
///    every gate run, which is what the settings pane was rendering as a *consequence*.
///    Removing it makes R-82.2's *"denied and notRequested behave identically"* a fact about the
///    type rather than a property a matrix has to re-prove, and no notification authorisation —
///    granted, refused or never asked — can change where a nudge appears.
/// 2. **`requestAuthorization` is nowhere in this repository** (focus-wy0). It used to be pinned
///    to one file, the settings pane's enable button. That button asked for a permission this
///    router could not spend, so it went with the rung it was for. R-96g's `count_at_most … 1`
///    now passes at zero.
/// 3. **Reduced interruption is a flag in here, not a second surface stack** (R-92, F-148).
///    Panel rungs become menu-bar badges and the question becomes a popover row. `silentVisual` is
///    the same mechanism spelled as a deck: `NudgeVoice.renderedRung(for:)` maps the panel rung
///    onto the ambient one before this function reads it.
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

        }
    }

    /// **Where a question goes.**
    ///
    /// **A question is never a notification.** U-1's affordance is "one click teaches the app",
    /// and a notification's actions are the system's to collapse, defer and summarise — a question
    /// answered from a notification summary three hours later would be a question about a moment
    /// that has passed. The three in-app surfaces are also what make the `notification-denied`
    /// gate stage possible at zero grants.
    ///
    /// It has always taken no authorisation. Since focus-wy0 neither does `route(rung:…)`, so the
    /// two are the same shape and the distinction this note used to draw no longer exists.
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

    // MARK: - The committed table

    /// One row per rung, under the conditions a settings pane describes: nothing presenting, no
    /// microphone running, the menu bar where it usually is.
    ///
    /// This is what the Intervention pane renders, and what a snapshot test pins — so "where does
    /// a nudge appear" is answered by the same value that decides it.
    ///
    /// It was a rung × authorisation cross product (focus-wy0). Four rows per rung, and since U-2
    /// the four were identical, because `route(…)` had already stopped reading the authorisation.
    public static func table(
        reducedInterruption: Bool = false,
        voice: NudgeVoice = .standard
    ) -> [SurfaceRoutingRow] {
        LadderRung.Kind.allCases.map { rung in
            SurfaceRoutingRow(
                rung: rung,
                route: route(
                    rung: rung,
                    presentation: .notPresenting,
                    media: .idle,
                    reducedInterruption: reducedInterruption,
                    menuBarVisible: true,
                    voice: voice
                )
            )
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
