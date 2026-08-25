import Foundation
import Testing

@testable import FocusCore

/// **The full matrix**, and the two properties that decide whether F-73's degraded path is real
/// (R-82, F-73, F-148).
///
///     LadderRung.Kind (3) × NotificationAuthorisation (4) × presentation (2) × media (2)
///         × reducedInterruption (2) × menuBarVisible (2) × NudgeVoice (5) = 960 cells
///
/// Two of them are asserted in **every** cell rather than at a chosen point: `denied` and
/// `notRequested` deliver identically, and no cell reaches a notification unless the system will
/// actually carry one. P-134 measured what happens otherwise — every setting `.notSupported` and
/// `add(_:)` failing with `UNErrorDomain` code 1 — so a route to a notification in any other
/// state is a route to nothing at all.
@Suite("Surface router")
struct SurfaceRouterTests {
    static let presenting = PresentationState(
        signals: PresentationSignals(
            frontmostWindowFillsAScreen: true,
            presentationOptionsSayFullScreen: true,
            menuBarHidden: true
        ),
        isUserExcluded: false,
        isPresenting: true
    )

    static let onACall = MediaActivity(microphoneRunning: true)

    static func route(
        rung: LadderRung.Kind,
        authorisation: NotificationAuthorisation = .notRequested,
        presentation: PresentationState = .notPresenting,
        media: MediaActivity = .idle,
        reducedInterruption: Bool = false,
        menuBarVisible: Bool = true,
        voice: NudgeVoice = .standard
    ) -> SurfaceRoute {
        SurfaceRouter.route(
            rung: rung,
            authorisation: authorisation,
            presentation: presentation,
            media: media,
            reducedInterruption: reducedInterruption,
            menuBarVisible: menuBarVisible,
            voice: voice
        )
    }

    /// Every cell of the matrix, as a sequence a test can fold over.
    static func everyCell(
        _ body: (
            LadderRung.Kind, NotificationAuthorisation, PresentationState, MediaActivity,
            Bool, Bool, NudgeVoice, SurfaceRoute
        ) -> Void
    ) {
        for rung in LadderRung.Kind.allCases {
            for authorisation in NotificationAuthorisation.allCases {
                for presentation in [PresentationState.notPresenting, presenting] {
                    for media in [MediaActivity.idle, onACall] {
                        for reduced in [false, true] {
                            for menuBar in [true, false] {
                                for voice in NudgeVoice.allCases {
                                    let route = SurfaceRouter.route(
                                        rung: rung,
                                        authorisation: authorisation,
                                        presentation: presentation,
                                        media: media,
                                        reducedInterruption: reduced,
                                        menuBarVisible: menuBar,
                                        voice: voice
                                    )
                                    body(
                                        rung, authorisation, presentation, media,
                                        reduced, menuBar, voice, route
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - The two matrix-wide properties

    @Test("960 cells: denied and notRequested produce identical delivery in every one")
    func deniedIsNotRequested() {
        var cells = 0
        for rung in LadderRung.Kind.allCases {
            for presentation in [PresentationState.notPresenting, Self.presenting] {
                for media in [MediaActivity.idle, Self.onACall] {
                    for reduced in [false, true] {
                        for menuBar in [true, false] {
                            for voice in NudgeVoice.allCases {
                                cells += 1
                                let denied = Self.route(
                                    rung: rung, authorisation: .denied,
                                    presentation: presentation, media: media,
                                    reducedInterruption: reduced, menuBarVisible: menuBar,
                                    voice: voice
                                )
                                let notRequested = Self.route(
                                    rung: rung, authorisation: .notRequested,
                                    presentation: presentation, media: media,
                                    reducedInterruption: reduced, menuBarVisible: menuBar,
                                    voice: voice
                                )
                                #expect(
                                    denied == notRequested,
                                    "\(rung)/\(voice): denied \(denied) vs notRequested \(notRequested)"
                                )
                            }
                        }
                    }
                }
            }
        }
        #expect(cells == 240)
    }

    @Test("no cell routes to a notification unless the system will carry one")
    func noUnauthorisedNotification() {
        var cells = 0
        var notifications = 0
        Self.everyCell { _, authorisation, _, _, _, _, _, route in
            cells += 1
            guard route.surface == .notification else { return }
            notifications += 1
            #expect(authorisation.permitsDelivery, "a notification under \(authorisation)")
        }
        #expect(cells == 960)
        #expect(notifications > 0, "the matrix never reached a notification at all")
    }

    @Test("a question is never a notification, in any cell")
    func aQuestionIsNeverANotification() {
        for presentation in [PresentationState.notPresenting, Self.presenting] {
            for media in [MediaActivity.idle, Self.onACall] {
                for reduced in [false, true] {
                    for menuBar in [true, false] {
                        for voice in NudgeVoice.allCases {
                            let route = SurfaceRouter.routeQuery(
                                presentation: presentation,
                                media: media,
                                reducedInterruption: reduced,
                                menuBarVisible: menuBar,
                                voice: voice
                            )
                            #expect(route.surface != .notification, "\(voice)")
                        }
                    }
                }
            }
        }
    }

    @Test("every unavailable cell names a reason a person could be told")
    func everyUnavailableCellHasAReason() {
        Self.everyCell { _, _, presentation, _, _, menuBar, _, route in
            guard case .unavailable(let reason) = route else { return }
            switch reason {
            case .menuBarHidden:
                #expect(!menuBar || presentation.suppressesOverlays)
            case .presentationActive:
                #expect(presentation.suppressesOverlays)
            case .notificationDeliveryFailed, .noSurfaceAvailable:
                Issue.record("the router invented \(reason), which only a delivery can produce")
            }
        }
    }

    // MARK: - The ambient rung

    @Test("the ambient rung is the glyph, and a hidden menu bar defers it rather than suppressing it")
    func theAmbientRung() {
        #expect(Self.route(rung: .ambient) == .surface(.menuBar))
        #expect(Self.route(rung: .ambient, menuBarVisible: false)
            == .unavailable(.menuBarHidden))

        // P-131: during a full-screen space the menu bar is hidden, so the rung is
        // *undeliverable* rather than unwanted — which is exactly what the suppression stack
        // answers for the same cell, and why it defers rather than suppressing.
        #expect(Self.route(rung: .ambient, presentation: Self.presenting)
            == .unavailable(.menuBarHidden))
    }

    @Test("nothing quietens the glyph: not a call, not reduced interruption, not the silent deck")
    func theGlyphIsAlreadyTheQuietestThing() {
        #expect(Self.route(rung: .ambient, media: Self.onACall) == .surface(.menuBar))
        #expect(Self.route(rung: .ambient, reducedInterruption: true) == .surface(.menuBar))
        #expect(Self.route(rung: .ambient, voice: .silentVisual) == .surface(.menuBar))
    }

    // MARK: - The panel rung

    @Test("the panel rung is a panel, and never over a presentation")
    func thePanelRung() {
        #expect(Self.route(rung: .panel) == .surface(.panel))
        #expect(Self.route(rung: .panel, presentation: Self.presenting)
            == .unavailable(.presentationActive))
    }

    @Test("reduced interruption turns the panel rung into a badge, and the silent deck into a glyph")
    func thePanelRungGoesQuiet() {
        #expect(Self.route(rung: .panel, reducedInterruption: true) == .surface(.popoverBadge))
        #expect(Self.route(rung: .panel, voice: .silentVisual) == .surface(.menuBar))

        // A badge is a menu-bar thing, so a hidden menu bar takes it away too. Routing a badge
        // into a menu bar nobody can see would be R-81's failure in a different costume.
        #expect(Self.route(rung: .panel, reducedInterruption: true, menuBarVisible: false)
            == .unavailable(.menuBarHidden))
    }

    @Test("a running microphone demotes the panel, because a panel over a call is a panel everybody sees")
    func aCallDemotesThePanel() {
        #expect(Self.route(rung: .panel, media: Self.onACall) == .surface(.popoverBadge))
    }

    // MARK: - The recommitment rung — F-73's degraded path

    @Test("the top rung is a notification where authorised, and the in-app panel where not")
    func theRecommitmentRung() {
        #expect(Self.route(rung: .recommitment, authorisation: .authorised)
            == .surface(.notification))
        #expect(Self.route(rung: .recommitment, authorisation: .provisional)
            == .surface(.notification))
        #expect(Self.route(rung: .recommitment, authorisation: .denied) == .surface(.panel))
        #expect(Self.route(rung: .recommitment, authorisation: .notRequested) == .surface(.panel))
    }

    @Test("an authorised notification is not demoted by a presentation or a call")
    func theNotificationIsAlreadyQuiet() {
        #expect(Self.route(
            rung: .recommitment, authorisation: .authorised, presentation: Self.presenting
        ) == .surface(.notification))
        #expect(Self.route(rung: .recommitment, authorisation: .authorised, media: Self.onACall)
            == .surface(.notification))
        #expect(Self.route(
            rung: .recommitment, authorisation: .authorised, reducedInterruption: true
        ) == .surface(.notification))
    }

    @Test("the silent deck keeps the top rung out of a window even when it must stay in the app")
    func theSilentDeckDemotesTheRecommitment() {
        #expect(Self.route(rung: .recommitment, authorisation: .denied, voice: .silentVisual)
            == .surface(.popoverBadge))
        #expect(Self.route(
            rung: .recommitment, authorisation: .denied, reducedInterruption: true
        ) == .surface(.popoverBadge))
    }

    @Test("every rung is deliverable in-app at zero grants, which is what the denied gate proves")
    func everyRungIsDeliverableWithoutAGrant() {
        for rung in LadderRung.Kind.allCases {
            for authorisation in [NotificationAuthorisation.denied, .notRequested] {
                let route = Self.route(rung: rung, authorisation: authorisation)
                #expect(route.surface?.isInApp == true, "\(rung)/\(authorisation)")
            }
        }
    }

    // MARK: - The delivery failure

    @Test("a delivery failure is a route change, recorded as a deferral")
    func aDeliveryFailureIsARouteChange() {
        let failure = SurfaceRouter.afterNotificationFailure(
            rung: .recommitment,
            presentation: .notPresenting,
            media: .idle,
            reducedInterruption: false,
            menuBarVisible: true,
            voice: .standard
        )

        #expect(failure.recorded == .deferred(.notificationDeliveryFailed))
        #expect(failure.demotedTo == .surface(.panel))

        // The record's disposition is a deferral, so nothing is spent and nothing advances.
        #expect(failure.recorded.surface == nil)
        #expect(failure.recorded.deferralReason == .notificationDeliveryFailed)
    }

    @Test("a failed notification demotes exactly as a refusal routes")
    func theDemotionIsTheDeniedRoute() {
        for reduced in [false, true] {
            for voice in NudgeVoice.allCases {
                let failure = SurfaceRouter.afterNotificationFailure(
                    rung: .recommitment,
                    presentation: .notPresenting,
                    media: .idle,
                    reducedInterruption: reduced,
                    menuBarVisible: true,
                    voice: voice
                )
                let denied = Self.route(
                    rung: .recommitment, authorisation: .denied,
                    reducedInterruption: reduced, voice: voice
                )
                #expect(failure.demotedTo == denied, "\(voice)/\(reduced)")
            }
        }
    }

    // MARK: - The question

    @Test("a question is a panel, a badge under reduced interruption, and nothing over a presentation")
    func theQueryRoute() {
        func query(
            presentation: PresentationState = .notPresenting,
            media: MediaActivity = .idle,
            reducedInterruption: Bool = false,
            menuBarVisible: Bool = true,
            voice: NudgeVoice = .standard
        ) -> SurfaceRoute {
            SurfaceRouter.routeQuery(
                presentation: presentation,
                media: media,
                reducedInterruption: reducedInterruption,
                menuBarVisible: menuBarVisible,
                voice: voice
            )
        }

        #expect(query() == .surface(.panel))
        #expect(query(reducedInterruption: true) == .surface(.popoverBadge))
        #expect(query(voice: .silentVisual) == .surface(.popoverBadge))
        #expect(query(media: Self.onACall) == .surface(.popoverBadge))
        #expect(query(presentation: Self.presenting) == .unavailable(.presentationActive))
        #expect(query(reducedInterruption: true, menuBarVisible: false)
            == .unavailable(.menuBarHidden))
    }

    @Test("the question's surface follows the deck's own answer")
    func theQuerySurfaceFollowsTheDeck() {
        for voice in NudgeVoice.allCases {
            let route = SurfaceRouter.routeQuery(
                presentation: .notPresenting,
                media: .idle,
                reducedInterruption: false,
                menuBarVisible: true,
                voice: voice
            )
            #expect(route.surface == voice.querySurface, "\(voice)")
        }
    }

    // MARK: - The committed table

    @Test("the table is the whole matrix, and it is what a settings pane may render")
    func theTableIsComplete() {
        let table = SurfaceRouter.table()

        #expect(table.count
            == LadderRung.Kind.allCases.count * NotificationAuthorisation.allCases.count)

        for row in table {
            #expect(row.route == Self.route(rung: row.rung, authorisation: row.authorisation))
        }

        // The answer to "what does this app do if I say no", read out of the same value that
        // decides it.
        let denied = table.filter { $0.authorisation == .denied }.map(\.route)
        let notRequested = table.filter { $0.authorisation == .notRequested }.map(\.route)
        #expect(denied == notRequested)
        #expect(denied == [.surface(.menuBar), .surface(.panel), .surface(.panel)])
    }

    @Test("the reduced-interruption table is the same shape with quieter surfaces")
    func theReducedTable() {
        let table = SurfaceRouter.table(reducedInterruption: true)
        let denied = table.filter { $0.authorisation == .denied }.map(\.route)

        #expect(denied == [
            .surface(.menuBar), .surface(.popoverBadge), .surface(.popoverBadge)
        ])
        #expect(table.first { $0.authorisation == .authorised && $0.rung == .recommitment }?.route
            == .surface(.notification))
    }

    @Test("routes turn into deliveries without a second opinion about what happened")
    func aRouteBecomesADelivery() {
        #expect(SurfaceRoute.surface(.panel).delivery == .delivered(.panel))
        #expect(SurfaceRoute.unavailable(.menuBarHidden).delivery
            == .deferred(.menuBarHidden))
    }
}
