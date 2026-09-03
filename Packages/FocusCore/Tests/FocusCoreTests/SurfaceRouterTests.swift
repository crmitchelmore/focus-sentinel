import Foundation
import Testing

@testable import FocusCore

/// **The full matrix**, and the properties that decide whether F-73's degraded path is real
/// (R-82, F-73, F-148).
///
///     LadderRung.Kind (2) × presentation (2) × media (2)
///         × reducedInterruption (2) × menuBarVisible (2) × NudgeVoice (5) = 160 cells
///
/// **A `NotificationAuthorisation` dimension is missing, and its absence is the assertion**
/// (focus-wy0). It used to multiply the matrix by four, and the headline property of the suite
/// was that `denied` and `notRequested` agreed in all 640 cells. Since U-2 removed the only rung
/// that could reach a notification, all four values agreed in every cell — and a property that
/// holds because nothing reads the input is not a property, it is a tautology wearing 640
/// assertions. `SurfaceRouter.route(…)` no longer accepts the parameter, so the identity is a
/// fact about the function's type and this suite asserts the shape instead.
///
/// What is still asserted in **every** cell: no cell reaches a notification at all. P-134
/// measured what a route there would be worth — every setting `.notSupported` and `add(_:)`
/// failing with `UNErrorDomain` code 1.
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
        presentation: PresentationState = .notPresenting,
        media: MediaActivity = .idle,
        reducedInterruption: Bool = false,
        menuBarVisible: Bool = true,
        voice: NudgeVoice = .standard
    ) -> SurfaceRoute {
        SurfaceRouter.route(
            rung: rung,
            presentation: presentation,
            media: media,
            reducedInterruption: reducedInterruption,
            menuBarVisible: menuBarVisible,
            voice: voice
        )
    }

    /// How many cells `everyCell` visits, derived from the axes themselves.
    ///
    /// Four booleans, the rung kinds and the decks. Written as a product rather than as a
    /// number so that retiring a deck moves the expectation with the space, and a router
    /// that had quietly stopped folding still fails.
    static var cellCount: Int {
        LadderRung.Kind.allCases.count * 2 * 2 * 2 * 2 * NudgeVoice.allCases.count
    }

    /// Every cell of the matrix, as a sequence a test can fold over.
    static func everyCell(
        _ body: (
            LadderRung.Kind, PresentationState, MediaActivity,
            Bool, Bool, NudgeVoice, SurfaceRoute
        ) -> Void
    ) {
        for rung in LadderRung.Kind.allCases {
            for presentation in [PresentationState.notPresenting, presenting] {
                for media in [MediaActivity.idle, onACall] {
                    for reduced in [false, true] {
                        for menuBar in [true, false] {
                            for voice in NudgeVoice.allCases {
                                let route = SurfaceRouter.route(
                                    rung: rung,
                                    presentation: presentation,
                                    media: media,
                                    reducedInterruption: reduced,
                                    menuBarVisible: menuBar,
                                    voice: voice
                                )
                                body(
                                    rung, presentation, media,
                                    reduced, menuBar, voice, route
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - The matrix-wide properties

    /// **The router does not read a notification authorisation, and this is what says so**
    /// (focus-wy0).
    ///
    /// It replaces "640 cells: denied and notRequested produce identical delivery in every one",
    /// which by the end was asserting that a function ignores an argument 640 times. The honest
    /// form is the shape: one committed row per rung, whose fields are the rung and the route and
    /// nothing else. Reintroducing the column — which is what would bring the defect back, since
    /// every route would still be identical — fails here.
    @Test("the committed row carries a rung and a route, and no authorisation")
    func theRowHasNoAuthorisation() {
        let row = SurfaceRoutingRow(rung: .ambient, route: .surface(.menuBar))
        let fields = Mirror(reflecting: row).children.compactMap(\.label).sorted()

        #expect(fields == ["route", "rung"])
        // …and the table is one row per rung rather than a cross product with anything.
        #expect(SurfaceRouter.table().count == LadderRung.Kind.allCases.count)
        #expect(SurfaceRouter.table().map(\.rung) == LadderRung.Kind.allCases)
    }

    /// **No cell routes to a notification at all** (U-2).
    ///
    /// This used to assert the weaker property that a notification appeared only where the system
    /// would carry one, and it ended with `#expect(notifications > 0)` to stop the whole check
    /// passing vacuously. The recommitment rung was the only rung that could reach a notification
    /// and it is deferred to focus-5ab, so the honest assertion is now the strong one: **zero**
    /// cells, out of every rung × presentation × media × reduced × menu-bar × voice combination
    /// there is.
    ///
    /// That is also what makes the ladder entirely in-app, which is what discharges standing
    /// condition 5 — and it is asserted here over the whole matrix rather than at the one point a
    /// gate script pokes.
    @Test("no cell routes to a notification, in the whole matrix")
    func noCellReachesANotification() {
        var cells = 0
        Self.everyCell { rung, _, _, _, _, voice, route in
            cells += 1
            #expect(
                route.surface != .notification,
                "\(rung)/\(voice) routed an accusation to a notification"
            )
        }
        // Derived, not written down: the deck count is a ruling that has moved once
        // already (`playful`, focus-0nm), and a literal here would have made a retired
        // deck look like a router that had stopped visiting cells.
        #expect(cells == Self.cellCount)
    }

    /// **Every accusation this router can deliver lands somewhere the person can answer it**
    /// (focus-uru).
    ///
    /// The defect this closes was a whole class of user, not a corner: the composition root
    /// forces `reducedInterruption` on under macOS **Reduce Motion**, from `AppearanceObserver`'s
    /// traits through `appearanceChanged(_:)` (focus-w7v); so does the `silentVisual` deck, and so
    /// does a running microphone. This router sends the top rung to
    /// `.popoverBadge` in all three. The popover drew a read-only *"Nudge: Panel"* row — no
    /// dismiss, no "this is relevant", no "not this time", no snooze — so
    /// `CorrectionAction`'s own "every surface, including the top rung, is dismissible" was false
    /// for exactly the people who had asked the system for a calmer product, and U-1's licence to
    /// interrupt had nothing to spend.
    ///
    /// **Enumerated over the routing table, not asserted about one surface.** Every rung, every
    /// deck, both settings of the flag, both media states, both menu-bar states, presenting and
    /// not — 160 cells, the same fold `noCellReachesANotification` uses. A cell either carries no
    /// surface (a deferral, which reaches nobody and is R-81's business) or carries one a person
    /// can answer back on.
    ///
    /// The ambient rung is exempt through `LadderRung.Kind.makesAnAccusation` rather than by
    /// being left out of the loop, and the exemption is a ruling: the glyph says nothing, accuses
    /// nobody, and R-87 keeps it on through a snooze precisely because it is a state rather than
    /// a sentence.
    ///
    /// ## The rung asked is the one the **ladder** asked for (focus-vxo)
    ///
    /// It was `voice.renderedRung(for: rung)`, and that is how this property came to certify the
    /// defect it exists to find. `silentVisual` remapped the panel rung to the ambient one, so
    /// the four cells in which an accusation reached `.menuBar` were **skipped by the guard whose
    /// job was to catch them** — the exemption ran ahead of the assertion and took the evidence
    /// with it. `#expect(accusations > 0)` did not save it either: the other four decks kept the
    /// counter well above zero, so the property was green, loud, and blind in exactly one corner.
    ///
    /// The replacement is not a bigger number, it is a **conservation law**: every cell whose
    /// requested rung makes an accusation is either answered or deferred, and the two counters
    /// must sum to the whole of that half of the matrix — 80 cells, `.panel` × 2 presentations ×
    /// 2 media × 2 flags × 2 menu-bar states × 5 decks. A guard that silently drops cells can
    /// then only fail: it cannot make the sum come out.
    @Test("every surface an accusation can reach offers a way to answer back")
    func everyRouteCanBeAnsweredBack() {
        var accusations = 0
        var deferrals = 0
        var unanswerable: [String] = []

        Self.everyCell { rung, presentation, media, reduced, menuBar, voice, route in
            guard rung.makesAnAccusation else { return }
            guard let surface = route.surface else {
                deferrals += 1
                return
            }
            accusations += 1
            guard !surface.offersAnAnswer else { return }
            unanswerable.append(
                "\(rung)/\(voice)/reduced=\(reduced)/menuBar=\(menuBar)/"
                    + "presenting=\(presentation.suppressesOverlays)/"
                    + "mic=\(media.suppressesIntervention) reached \(surface)"
            )
        }

        #expect(
            unanswerable.isEmpty,
            """
            an accusation reached a surface offering no way to answer it:
            \(Set(unanswerable).sorted().joined(separator: "\n"))
            """
        )

        // **Nothing was skipped**, which is the half of this property that failed before. Every
        // accusing cell was counted exactly once, into one of the two buckets.
        let accusingCells = 2 * 2 * 2 * 2 * NudgeVoice.allCases.count
        #expect(
            accusations + deferrals == accusingCells,
            "the fold visited \(accusations + deferrals) accusing cells, not \(accusingCells)"
        )
        #expect(accusations > 0, "the exemption swallowed the property")
        #expect(deferrals > 0, "no cell deferred, so the deferral branch is untested")

        // And the three quiet routes by name, because they are the ones that were wrong — two of
        // them in focus-uru and the third in focus-vxo. All three are where a person who asked
        // for calm meets the top rung, and all three must be answerable.
        #expect(Self.route(rung: .panel, reducedInterruption: true) == .surface(.popoverBadge))
        #expect(Self.route(rung: .panel, media: Self.onACall) == .surface(.popoverBadge))
        #expect(Self.route(rung: .panel, voice: .silentVisual) == .surface(.popoverBadge))
        #expect(NudgeSurface.popoverBadge.offersAnAnswer)
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
        Self.everyCell { _, presentation, _, _, menuBar, _, route in
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

    /// **The three quiet conditions reach one surface, and it is the answerable one** (focus-vxo).
    ///
    /// The deck used to reach `.menuBar` while the other two reached `.popoverBadge`, which is
    /// how "reduced interruption is one flag inside the existing router, and `silentVisual` is the
    /// same mechanism spelled as a deck" was written down in three files and true in none. A glyph
    /// carrying the top rung is R-81's failure in a different costume: the loop recorded it
    /// delivered against a named application and there was nothing on it to press.
    ///
    /// Asserted for **every** deck rather than for the one that was broken, so a sixth routing
    /// deck cannot arrive with its own private answer.
    @Test("every quiet condition turns the panel rung into a badge, and none into a glyph")
    func thePanelRungGoesQuiet() {
        #expect(Self.route(rung: .panel, reducedInterruption: true) == .surface(.popoverBadge))
        #expect(Self.route(rung: .panel, media: Self.onACall) == .surface(.popoverBadge))

        for voice in NudgeVoice.allCases {
            let quiet: SurfaceRoute =
                voice.isRoutingDeck ? .surface(.popoverBadge) : .surface(.panel)
            #expect(
                Self.route(rung: .panel, voice: voice) == quiet,
                "\(voice) put the top rung somewhere the deck's own promise does not allow"
            )
            // Whatever the deck, the rung it carries is answerable in every quiet condition.
            for reduced in [false, true] {
                for media in [MediaActivity.idle, Self.onACall] {
                    let route = Self.route(
                        rung: .panel, media: media, reducedInterruption: reduced, voice: voice
                    )
                    #expect(route.surface?.offersAnAnswer == true, "\(voice)/\(reduced)/\(media)")
                }
            }
        }

        // A badge is a menu-bar thing, so a hidden menu bar takes it away too. Routing a badge
        // into a menu bar nobody can see would be R-81's failure in a different costume.
        #expect(Self.route(rung: .panel, reducedInterruption: true, menuBarVisible: false)
            == .unavailable(.menuBarHidden))
        #expect(Self.route(rung: .panel, menuBarVisible: false, voice: .silentVisual)
            == .unavailable(.menuBarHidden))
    }

    @Test("a running microphone demotes the panel, because a panel over a call is a panel everybody sees")
    func aCallDemotesThePanel() {
        #expect(Self.route(rung: .panel, media: Self.onACall) == .surface(.popoverBadge))
    }

    /// The claim the `notification-denied` gate stage turns on, and it no longer needs to name a
    /// grant state to make it: **there is no grant state**. Every rung lands in-app, always.
    @Test("every rung is deliverable in-app, which is what the denied gate proves")
    func everyRungIsDeliverableWithoutAGrant() {
        for rung in LadderRung.Kind.allCases {
            #expect(Self.route(rung: rung).surface?.isInApp == true, "\(rung)")
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

    @Test("the table is one row per rung, and it is what a settings pane may render")
    func theTableIsComplete() {
        let table = SurfaceRouter.table()

        #expect(table.count == LadderRung.Kind.allCases.count)

        for row in table {
            #expect(row.route == Self.route(rung: row.rung))
        }

        // The answer to "where does a nudge appear", read out of the same value that decides it.
        #expect(table.map(\.route) == [.surface(.menuBar), .surface(.panel)])
    }

    /// **Every quiet setting draws the same table**, which is what "one flag inside the existing
    /// router" means when it is true (R-92, focus-vxo).
    ///
    /// The routing deck drew `[.menuBar, .menuBar]` — a glyph where the top rung goes — and this
    /// is the row the Intervention pane renders, so the pane said the deck's top rung appeared in
    /// the menu bar. It is the same table now because it is the same mechanism.
    @Test("the reduced-interruption table is the same shape with quieter surfaces")
    func theReducedTable() {
        let quiet: [SurfaceRoute] = [.surface(.menuBar), .surface(.popoverBadge)]

        #expect(SurfaceRouter.table(reducedInterruption: true).map(\.route) == quiet)
        #expect(SurfaceRouter.table(voice: .silentVisual).map(\.route) == quiet)
        #expect(
            SurfaceRouter.table(reducedInterruption: true, voice: .silentVisual).map(\.route)
                == quiet
        )
    }

    @Test("routes turn into deliveries without a second opinion about what happened")
    func aRouteBecomesADelivery() {
        #expect(SurfaceRoute.surface(.panel).delivery == .delivered(.panel))
        #expect(SurfaceRoute.unavailable(.menuBarHidden).delivery
            == .deferred(.menuBarHidden))
    }
}
