import AppKit
import ApplicationServices
import FocusCore
import FocusSensing
import FocusUI
import Foundation
import SwiftData

/// The zero-grant shell self-check.
///
/// Run the built binary with `--focus-self-check <path>` and it launches normally, brings
/// itself to the front and **waits until it is really there**, gives AppKit one run-loop
/// second to finish installing the menu bar and ordering its window in, writes a JSON report
/// describing its own shell, and terminates.
///
/// Why this exists: every interesting claim about a Mac shell — the menu bar is exactly
/// these six menus, Help has exactly one item and it is not the broken default, ⌘W is
/// actually claimed, the window is a standard titled window with three standard buttons —
/// used to be checkable only by driving the app from outside with `osascript`, which needs
/// Accessibility granted to the *driving shell*. No acceptance criterion may depend on a
/// TCC grant, so those claims moved in here: the app reports on itself, in its own process,
/// from a plain `exec`, with no permission of any kind.
///
/// What it deliberately cannot see: the Apple menu (owned by the system, not part of
/// `NSApp.mainMenu`) and the View-menu items AppKit inserts lazily when a real user opens
/// the menu. Those stay evidence gathered by the TCC-gated live lane.
enum SelfCheck {
    /// The launch argument that turns this mode on. An ordinary argument, not a `#if DEBUG`
    /// path, so the Release product answers exactly the same questions as the Debug one.
    static let argument = "--focus-self-check"

    /// How long to let the run loop turn *after* the app is frontmost, before reading the
    /// shell. Measured, not guessed: with no delay the submenus read as empty because AppKit
    /// has not populated them yet.
    static let settleDelay: TimeInterval = 1.0

    /// How long the nudge panel stays on screen inside `panelReport()` (focus-x7d).
    ///
    /// Long enough for two different things. **AppKit's** — a window whose size is being driven
    /// by SwiftUI's fitting size is still correct at the instant it is ordered front and wrong
    /// one layout pass later, so a report written without this turn describes the moment before
    /// the defect. And **an outside observer's** — `Tools/windowid` can measure the same window
    /// from another process while it is up, which is what stops the claim resting on the app's
    /// own report of itself.
    static let panelSettleSeconds: TimeInterval = 2.5

    /// How long to keep asking to come forward before reading the shell anyway.
    ///
    /// Reaching this deadline is a *reported failure*, not a fallback: `self-check.sh` asserts
    /// that the app was active with a key window when the shell was read, so a machine that
    /// never lets the app forward fails loudly and by name instead of failing later, in the
    /// undo assertion, for a reason that looks like a defect in the journal.
    static let activationDeadline: TimeInterval = 15.0

    /// How often to re-ask. Measured over eight consecutive runs on this machine, the
    /// activation lands on the **second** poll — the first issues it, the next observes it —
    /// about 73 ms after launch. The interval costs nothing on a machine that takes longer.
    static let activationPollInterval: TimeInterval = 0.05

    /// Seed a session into a store of its own and exit (R-46).
    static let seedArgument = "--focus-session-seed"

    /// Open a store somebody else seeded, reconcile it, and report what came back (R-46).
    static let restoreArgument = "--focus-session-restore"

    /// Export the local event stream, for the live evidence lane to read.
    static let exportArgument = "--focus-export-events"

    /// **The nudge channel** (§4.5, §4.7).
    ///
    /// Present as well as the ordinary report rather than instead of it, because the two gate
    /// stages e05 adds want different things: `focus-steal` wants the panel shown and its four
    /// grant-free readings taken, and `notification-denied` wants every rung's surface at zero
    /// grants. Both are in the `nudge` block of the ordinary report; this flag runs **only**
    /// that block, headlessly, without waiting to come forward — which is what makes it cheap
    /// enough for a gate stage rather than an evidence lane.
    static let nudgeArgument = "--focus-self-check-nudge"

    /// Whether this process was asked for the nudge block alone.
    static var wantsNudgeOnly: Bool { CommandLine.arguments.contains(nudgeArgument) }

    /// How far back the seeded session's `startedAt` is dated. Ninety minutes, which is what
    /// §4.6 asserts the restoring launch reports to within two seconds.
    static let seedBackdateSeconds: Double = 5_400

    /// The value that follows a flag on the command line, or `nil` when the flag is absent or
    /// carries nothing after it.
    static func value(after flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let next = arguments.index(after: index)
        guard next < arguments.endIndex else { return nil }
        return arguments[next]
    }

    /// The output path, if this process was asked for a self-check.
    static var requestedOutputPath: String? { value(after: argument) }

    /// The store to seed, if this process was asked to seed one.
    static var requestedSeedStorePath: String? { value(after: seedArgument) }

    /// The store to restore from, if this process was asked to restore one.
    static var requestedRestoreStorePath: String? { value(after: restoreArgument) }

    /// Where to write the exported event stream, if this process was asked for one.
    static var requestedEventExportPath: String? { value(after: exportArgument) }

    // MARK: - Coming to the front, deterministically

    /// How the app got to the front, and how long it took.
    ///
    /// This is a precondition of most of what the report claims, not a curiosity. AppKit
    /// validates a menu item by walking the **key window's** responder chain, and an
    /// application that is not active has no key window at all — so a self-check that reads
    /// the Edit menu while the app is in the background reads `Undo`, disabled, however many
    /// operations the journal holds. Recording the activation makes that failure legible.
    struct Activation {
        var isActive: Bool
        var hasKeyWindow: Bool
        var cockpitIsKey: Bool
        var attempts: Int
        var waitedMilliseconds: Double

        var dictionary: [String: Any] {
            [
                "isActive": isActive,
                "hasKeyWindow": hasKeyWindow,
                "cockpitIsKey": cockpitIsKey,
                "attempts": attempts,
                "waitedMilliseconds": waitedMilliseconds
            ]
        }
    }

    /// Bring the app forward and **wait until it really is forward**, then continue.
    ///
    /// Measured on this machine, with a plain `exec`'d binary and a poll every 100 ms for four
    /// seconds: `NSApp.activate()` — the cooperative macOS 14+ API — never activates
    /// (`isActive == false`, `keyWindow == nil`, 41 attempts), and neither does
    /// `NSRunningApplication.current.activate(options:)`. `activate(ignoringOtherApps: true)`
    /// activates immediately, every time — the app is frontmost with the cockpit key about
    /// 73 ms after launch. Cooperative activation is a request another app has to yield to,
    /// and a process launched from a shell has nobody to yield to it, which is why the old
    /// fixed one-second delay passed or failed depending on what happened to be frontmost.
    ///
    /// So: ask the un-cooperative way, poll until it is true, and time out loudly rather than
    /// reading a background app's menu bar and reporting the answer as though it meant
    /// something. Nothing here runs in the ordinary app — `requestedOutputPath` is `nil`
    /// unless `--focus-self-check` was passed.
    @MainActor
    static func comeForward(then continuation: @escaping @MainActor (Activation) -> Void) {
        let started = ProcessInfo.processInfo.systemUptime
        var attempts = 0

        func attempt() {
            attempts += 1
            NSApp.activate(ignoringOtherApps: true)
            liveCockpitWindow()?.makeKeyAndOrderFront(nil)

            let elapsed = ProcessInfo.processInfo.systemUptime - started
            let state = Activation(
                isActive: NSApp.isActive,
                hasKeyWindow: NSApp.keyWindow != nil,
                cockpitIsKey: NSApp.keyWindow != nil && NSApp.keyWindow === liveCockpitWindow(),
                attempts: attempts,
                waitedMilliseconds: elapsed * 1_000
            )

            // The cockpit is the window whose `UndoManager` the journal was registered on, so
            // "some window is key" is not enough when the cockpit exists: the quick-capture
            // panel is also a titled window, built at launch, and its manager is a different
            // object with nothing registered on it.
            let ready = state.isActive
                && state.hasKeyWindow
                && (liveCockpitWindow() == nil || state.cockpitIsKey)

            if ready || elapsed >= activationDeadline {
                continuation(state)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + activationPollInterval) {
                MainActor.assumeIsolated { attempt() }
            }
        }

        attempt()
    }

    /// The cockpit window itself, by the identifier SwiftUI stamps on its scene.
    @MainActor
    static func liveCockpitWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == ShellWindow.cockpit.id }
    }

    // MARK: - Report

    @MainActor
    static func report(activation: Activation) -> [String: Any] {
        // Order matters. The window survey must happen *before* the key-equivalent probes,
        // because performing ⌘W closes a window and ⌘, opens one — the probes change the
        // very state the survey is describing.
        let menu = menuTree()
        let windows = windowReports()
        let cockpit = cockpitWindow(in: windows)
        // The undo probe reads the *system* Edit menu, so it has to run while the cockpit is
        // still the key window — before the key-equivalent probes close it.
        let undo = undoReport()
        // …and the shell block reads the key window's undo manager for the same reason, and
        // drives the handoff into a cockpit that has to still be there to show it.
        let shell = shellReport()
        // …and the e03 block reads the on-screen window list, so it runs before ⌘, opens a
        // Settings window and ⌘W closes the cockpit. Every read in it is grant-free.
        let sensing = sensingReport()
        let capabilities = capabilityReport()
        // e04's block runs beside e03's, before the key-equivalent probes: it makes one real
        // judgement, and a judgement made after ⌘W closed the cockpit would be a judgement about
        // a different screen.
        let relevance = relevanceReport()
        let surfaces = authorisationSurfaceReport()
        let claims = keyEquivalentClaims()
        // **After the key probes, and that is the point** (focus-2er). ⌘, opens the Settings
        // window and ⌘? opens the Keyboard Shortcuts window, so the wires those two scenes carry
        // — their connections, their `.task`, their appearance-traits injections — cannot have
        // fired before this line. The run loop is given a turn first, because `.task` is
        // asynchronous and a report written in the same tick would describe the moment before it.
        settle(forSeconds: sceneSettleSeconds)
        let shellAfterProbes = shellWireReport()

        var root: [String: Any] = [:]
        root["bundleIdentifier"] = Bundle.main.bundleIdentifier ?? ""
        root["displayName"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName")
            as? String ?? ""
        root["menuBarTitles"] = menu.compactMap { $0["title"] as? String }
        root["menu"] = menu
        root["windows"] = windows
        root["cockpitWindow"] = cockpit ?? [:]
        root["keyEquivalentClaims"] = claims
        root["statusTokens"] = statusTokens()
        root["localizationCatalogsCompiled"] = LocalizationLane.catalogsAreCompiled
        // Recorded *and* asserted: everything the menu survey says is conditional on this.
        root["activation"] = activation.dictionary

        // --- e02 -------------------------------------------------------------------------
        root["urlSchemes"] = urlSchemes()
        root["hotKey"] = hotKeyReport()
        // Recorded, never asserted. Probe P-56: a binary `exec`'d from a shell that holds
        // Accessibility inherits that shell's TCC responsibility and reports `true` — which is
        // exactly how `self-check.sh` launches this process. Requiring `false` here would fail
        // on a granted developer machine for a reason that has nothing to do with the code.
        // The honest grant-free proof is the evidence lane's `open -a` launch after a
        // `tccutil reset`; the *gateable* fact is `hotKey.status == 0`, which no grant touches.
        root["axIsProcessTrusted"] = AXIsProcessTrusted()
        root["undo"] = undo
        root["capturePanel"] = capturePanelReport()
        root["priorityHero"] = priorityHeroReport()
        // The application target's own wiring, which no test bundle can reach (focus-cp2).
        root["shell"] = shell

        // --- e03 -------------------------------------------------------------------------
        root["sensing"] = sensing
        root["capabilities"] = capabilities
        root["authorisationSurfaces"] = surfaces.suspects
        root["onScreenWindowOwners"] = surfaces.owners
        // Read **after** the key-equivalent probes, and asserted equal to the value the sensing
        // block read before them.
        //
        // This is the assertion that caught the shortcut defect rather than a person noticing
        // it: with Pause Watching bound to ⇧⌘W, a synthesised plain ⌘W reached that item as well
        // as Close Window, and three consecutive self-checks reported the stored switch flipped
        // — `true`, `false`, `true`. A shortcut that quietly changes a stored setting somebody
        // else owns is exactly the kind of thing a menu bar can do without anyone seeing it, so
        // the check stays even though the collision is gone.
        // Every scene's wires, re-read once each of the three windows has had the chance to
        // exist. `shell` above describes the cockpit alone, which is the only window open when
        // it runs.
        root["shellAfterProbes"] = shellAfterProbes
        root["settingSensingPausedAfterKeyProbes"] =
            AppComposition.shared.sensingHost.settings.sensingPaused
        root["bootIdentity"] = AppComposition.shared.bootIdentity
        root["uptimeSeconds"] = AppComposition.shared.uptimeClock.uptimeSeconds

        // --- e04 -------------------------------------------------------------------------
        root["relevance"] = relevance
        // Lifted to the root as well, because they are the two values `self-check.sh` compares
        // against the committed literals and a gate assertion should not have to walk a path
        // into a sub-object to find its subject.
        root["engineStamp"] = relevance["engineStamp"] ?? ""
        root["policyDigest"] = relevance["policyDigest"] ?? ""

        // --- e05 -------------------------------------------------------------------------
        let nudge = nudgeReport()
        root["nudge"] = nudge
        // Lifted for the same reason the two above are: these are the values the gate compares
        // against committed literals, and one of them — `requestAuthorizationCallCount` — is
        // the number that discharges standing condition 5 for this epic.
        root["interventionDigest"] = nudge["interventionDigest"] ?? ""
        root["notificationAuthorisation"] = nudge["notificationAuthorisation"] ?? ""
        root["requestAuthorizationCallCount"] = nudge["requestAuthorizationCallCount"] ?? -1
        root["ladderRungsDeclared"] = nudge["ladderRungsDeclared"] ?? -1
        return root
    }

    // MARK: - e05 · the nudge loop, at zero grants (§4.5, §4.7)

    /// **What the running application can say about the nudge without asking for anything.**
    ///
    /// Three claims, and each is what one of the epic's gates needs:
    ///
    /// 1. **The panel takes nothing.** It is really shown — `orderFrontRegardless()`, the one
    ///    show path — and all four of R-89's grant-free readings are taken before and after.
    ///    Reading 1 alone is what an earlier draft asserted, and P-139 measured a focus theft it
    ///    cannot see: `makeKeyAndOrderFront(nil)` flips `NSApp.isActive` to `true` and installs a
    ///    key window while the frontmost application never moves.
    /// 2. **Every rung has a surface at whatever authorisation this Mac actually has.** Read
    ///    from `SurfaceRouter` — the committed table the settings pane renders — so the report
    ///    and the behaviour cannot be two different answers.
    /// 3. **Nothing asked for a permission.** `requestAuthorizationCallCount` is published by
    ///    the notification boundary, which contains no call that could increment it; the number
    ///    is here so a gate can assert the fact rather than infer it from a lint.
    @MainActor
    static func nudgeReport() -> [String: Any] {
        let composition = AppComposition.shared
        let host = composition.nudgeHost
        var report: [String: Any] = [:]

        report["interventionDigest"] = InterventionPolicy.digestHex
        report["interventionVersion"] = InterventionPolicy.version
        report["ladderRungsDeclared"] = LadderRung.Kind.allCases.count
        report["notificationAuthorisation"] = host.notificationAuthorisation.rawValue
        report["permitsNotificationDelivery"] = host.notificationAuthorisation.permitsDelivery
        report["requestAuthorizationCallCount"] = host.requestAuthorizationCallCount

        // Every rung, with nothing presenting and no call in progress — which is the state the
        // settings pane's matrix describes.
        //
        // **Three tables, not one, and the two extra ones are what make the gate honest.** This
        // Mac's own authorisation is whatever a person set it to, and the `notification-denied`
        // stage has to prove F-73's degraded path *whatever that is* — a stage that asserted the
        // in-app path only when the machine happened to be in the degraded state would be a stage
        // that silently stopped asserting the moment somebody granted notifications. `route(…)` is
        // a pure function of typed inputs, so asking it what it would do at `denied` and at
        // `notRequested` costs nothing, prompts nothing and needs no grant (R-82, P-134).
        func table(at authorisation: NotificationAuthorisation) -> [[String: Any]] {
            LadderRung.Kind.allCases.map { rung in
                let route = SurfaceRouter.route(
                    rung: rung,
                    authorisation: authorisation,
                    presentation: .notPresenting,
                    media: .idle,
                    reducedInterruption: false,
                    menuBarVisible: true,
                    voice: .standard
                )
                return [
                    "rung": rung.rawValue,
                    "rank": rung.rank,
                    "surface": route.surface?.rawValue ?? "",
                    "deferralReason": route.deferralReason?.rawValue ?? "",
                    "isInApp": route.surface?.isInApp ?? false
                ]
            }
        }
        func everyRungHasASurface(_ table: [[String: Any]]) -> Bool {
            table.allSatisfy { !(($0["surface"] as? String) ?? "").isEmpty }
        }
        func everyRungIsInApp(_ table: [[String: Any]]) -> Bool {
            table.allSatisfy { ($0["isInApp"] as? Bool) == true }
        }

        let routes = table(at: host.notificationAuthorisation)
        report["routes"] = routes
        report["everyRungHasASurface"] = everyRungHasASurface(routes)
        report["everyRungIsInApp"] = everyRungIsInApp(routes)

        let denied = table(at: .denied)
        let notRequested = table(at: .notRequested)
        report["routesWhenDenied"] = denied
        report["routesWhenNotRequested"] = notRequested
        report["everyRungIsInAppWhenDenied"] = everyRungIsInApp(denied)
        report["everyRungIsInAppWhenNotRequested"] = everyRungIsInApp(notRequested)
        // R-82.2: `denied` and `notRequested` differ in what the app may **offer** and never in
        // what it may **deliver**. Two tables that had drifted apart would mean a person who said
        // "no" and a person who was never asked were getting different products.
        report["deniedAndNotRequestedDeliverAlike"] = denied.map {
            ($0["surface"] as? String) ?? ""
        } == notRequested.map { ($0["surface"] as? String) ?? "" }

        // The query's route, which takes no authorisation at all: **a question is never a
        // notification** (R-82).
        let queryRoute = SurfaceRouter.routeQuery(
            presentation: .notPresenting,
            media: .idle,
            reducedInterruption: false,
            menuBarVisible: true,
            voice: .standard
        )
        report["querySurface"] = queryRoute.surface?.rawValue ?? ""

        // **Every deck and every flag, not just the one cell that always answers `panel`**
        // (focus-kby).
        //
        // This stage used to ask the router exactly one question — the standard deck, reduced
        // interruption off, nothing playing — which always answers `.panel`. The badge route was
        // therefore invisible to every gate in the programme, and the badge route is the one the
        // ledger was burning questions on: `silentVisual`, reduced interruption (forced on by
        // Reduce Motion), and a live microphone or camera, which is anybody on a call. Three
        // ordinary conditions, none of them exotic, none of them ever exercised.
        //
        // `routeQuery(…)` is a pure function of typed inputs, so the whole cross product costs
        // nothing, prompts nothing and needs no grant.
        var queryRoutes: [[String: Any]] = []
        for voice in NudgeVoice.allCases {
            for reduced in [false, true] {
                let mediaStates: [(String, MediaActivity)] = [
                    ("idle", .idle),
                    ("microphone", MediaActivity(microphoneRunning: true)),
                    ("camera", MediaActivity(microphoneRunning: false, cameraRunning: true))
                ]
                for (mediaName, media) in mediaStates {
                    let route = SurfaceRouter.routeQuery(
                        presentation: .notPresenting,
                        media: media,
                        reducedInterruption: reduced,
                        menuBarVisible: true,
                        voice: voice
                    )
                    queryRoutes.append([
                        "voice": voice.rawValue,
                        "reducedInterruption": reduced,
                        "media": mediaName,
                        "surface": route.surface?.rawValue ?? "",
                        "deferralReason": route.deferralReason?.rawValue ?? "",
                        "canCarryAQuestion": route.surface?.canCarryAQuestion ?? false
                    ])
                }
            }
        }
        report["queryRoutes"] = queryRoutes
        report["everyQueryRouteCanCarryAQuestion"] = queryRoutes.allSatisfy {
            ($0["canCarryAQuestion"] as? Bool) == true
        }
        report["queryRoutesReachingTheBadge"] = queryRoutes.count {
            ($0["surface"] as? String) == NudgeSurface.popoverBadge.rawValue
        }
        report["queryRoutesReachingThePanel"] = queryRoutes.count {
            ($0["surface"] as? String) == NudgeSurface.panel.rawValue
        }
        // The badge is only a surface while the menu bar is on screen (P-131), and a question
        // routed to a hidden menu bar is a deferral rather than a question nobody answers.
        let hiddenMenuBar = SurfaceRouter.routeQuery(
            presentation: .notPresenting,
            media: .idle,
            reducedInterruption: true,
            menuBarVisible: false,
            voice: .standard
        )
        report["querySurfaceWhenMenuBarHidden"] = hiddenMenuBar.surface?.rawValue ?? ""
        report["queryDeferralWhenMenuBarHidden"] = hiddenMenuBar.deferralReason?.rawValue ?? ""

        report["panel"] = panelReport()
        report["menuBarInstalled"] = composition.menuBar.isInstalled
        report["decisionCount"] = host.decisionCount
        return report
    }

    /// Show the nudge panel, take the four readings, and put it away again.
    ///
    /// The panel is shown for real. Nothing here activates the application, makes a window key
    /// or brings anything forward — and `check-forbidden.sh` (R-96m) makes that structural by
    /// confining `orderFrontRegardless` to the controller's one show function and banning the
    /// call that would take focus outright.
    @MainActor
    static func panelReport() -> [String: Any] {
        let composition = AppComposition.shared
        let panel = composition.nudgePanel
        var report: [String: Any] = [:]

        // **Real nudge content, and this is not decoration** (focus-x7d).
        //
        // This stage used to show an EMPTY panel. It therefore proved, with great rigour, that a
        // window with nothing in it takes nothing — while the panel a person actually meets grew
        // to 380 × 2212 the moment real content went into it, and the gate had no way to notice.
        // "It takes nothing" and "it shows something" are two different claims, and a stage that
        // only ever made the first is a stage that could not have caught this.
        //
        // The question is used rather than the accusation because it is the surface U-1's whole
        // bargain rests on; the unit lane asserts both.
        let presentation = QueryPresentation(
            task: "Write the Q3 proposal for Acme",
            subject: FocusStore.bundleIdentifier,
            reason: .noNegativeBasis,
            dwelled: .seconds(62)
        )
        panel.update(content: QueryPanelView(presentation: presentation))

        let before = panel.readings()
        panel.show(presentationIsClear: true)

        // **The turn of the run loop, and it is the whole assertion.**
        //
        // A window driven by an `NSHostingView`'s fitting size is still exactly the size it was
        // built as at the instant `show(…)` returns, and the wrong size one pass later. Every
        // reading taken without this line is a reading of the moment before the defect. It also
        // holds the panel on screen long enough for an outside observer — `Tools/windowid` — to
        // measure the same window independently, which is how the live claim is checked against
        // something other than the app's own report.
        RunLoop.current.run(until: .now + panelSettleSeconds)

        let after = panel.readings()

        // Taken while the panel is still up: a frame read after `hide()` is a frame read off a
        // window nobody is being shown.
        let frame = panel.frame
        report["frame"] = [
            "x": frame.x, "y": frame.y, "width": frame.width, "height": frame.height
        ]
        report["contentSize"] = [
            "width": Double(panel.contentSize.width),
            "height": Double(panel.contentSize.height)
        ]
        report["contentWidth"] = NudgePanelController.contentWidth
        report["maximumContentHeight"] = NudgePanelController.maximumContentHeight(
            screens: NudgePanelController.currentScreens()
        )

        // **The invariant that replaced "the frame equals a constant"** (focus-vpu, focus-kby).
        //
        // A size comparison passed a panel measured at y = −1186 — off screen as well as
        // oversized — and passed a panel whose Pause row was below the clip, because the frame
        // really was the constant. What a person being asked to choose needs is that the window
        // is on a display and **every action it offers is somewhere they can click**, and that is
        // what this reads. `offeredAnswerIdentifiers` is the question's own list, so the report
        // and the panel cannot be describing two different sets of buttons.
        let reading = panel.decisionSurfaceReading(offering: presentation.offeredAnswerIdentifiers)
        report["decisionSurface"] = reading.dictionary
        report["everyActionIsReachable"] = reading.everyActionIsReachable
        report["hitTestsEveryAction"] = panel.hitTestsEveryAction(
            offering: presentation.offeredAnswerIdentifiers
        )
        report["offeredActions"] = presentation.offeredAnswerIdentifiers

        panel.hide()

        // Read **after** the show, so the report describes the panel as it was actually
        // presented: `.fullScreenAuxiliary` is applied by the show path and only when the
        // presentation gate has cleared (R-84), so reading the properties first would report a
        // window nobody was ever shown.
        report["properties"] = panel.properties.dictionary

        report["readingsBeforeShow"] = before.dictionary
        report["readingsAfterShow"] = after.dictionary
        report["frontmostBeforeShow"] = before.frontmostBundleIdentifier ?? ""
        report["frontmostAfterShow"] = after.frontmostBundleIdentifier ?? ""
        // Two conjunctions, and the difference between them is the posture this process is in.
        //
        // `tookNothing` is R-89's **absolute** form — frontmost unchanged, `NSApp.isActive`
        // false, the panel not key, no key window at all — and it is what §4.5's `focus-steal`
        // stage asserts, because that stage launches the app with `open -g -a`: an application
        // that has never been frontmost, which is the posture a nudge really fires in (P-128).
        //
        // `changedNothing` is the **delta** form, and it is the honest claim in the ordinary
        // self-check: that survey activates the application on purpose, because AppKit validates
        // a menu item by walking the key window's responder chain and a background application
        // has no key window at all. Asserting `NSApp.isActive == false` there would be asserting
        // something about the self-check's own launch rather than about the panel.
        report["tookNothing"] = after.tookNothing(comparedTo: before)
        report["changedNothing"] = after.changedNothing(comparedTo: before)
        report["wasVisible"] = after.panelIsVisible
        report["hiddenAfter"] = !panel.isVisible
        report["propertiesAreCorrect"] = panel.properties.isCorrect
        report["windowNumber"] = panel.windowNumber
        return report
    }

    // MARK: - e03 · the observer graph (F-119, F-23, F-29, F-32, F-35, F-36)

    /// Everything about the graph that can be checked with no grant at all — including the one
    /// claim that can only be made from *inside* the process.
    ///
    /// ## The pause is exercised for real
    ///
    /// F-119's promise is that the switch **detaches every observer** rather than setting a flag
    /// each handler consults, and the only way to check that is to pause the live graph and
    /// count what is left: `n > 0 → 0 → n`. So this really pauses and really resumes it.
    ///
    /// Two things keep that honest rather than destructive. The **stored** switch is never
    /// touched — `SensingHost.pause()` is called directly rather than through
    /// `setSensingPaused`, so whatever the person chose is still what they chose after this
    /// runs. And the pause and the resume are a matched pair carrying the same cause, so the
    /// session ends where it began: `paused(cause: .globalPause)` followed by
    /// `resumed(cause: .globalPause)` nets to nothing, which is precisely the property the
    /// cause mechanism exists to give. Two rows land in the local timeline saying it happened,
    /// which is the honest record of a thing that did happen.
    @MainActor
    static func sensingReport() -> [String: Any] {
        let host = AppComposition.shared.sensingHost
        var report: [String: Any] = [:]

        report["isRunning"] = host.isRunning
        report["settingSensingPaused"] = host.settings.sensingPaused
        report["redundantActivations"] = host.redundantActivations
        report["cascade"] = host.cascade.map(\.rawValue)
        report["lifecycle"] = host.lifecycleState.rawValue

        // --- everything that describes the world, read while the graph is as the person left it

        // The seven decoded keys, and the assertion that none of them names a *window*.
        // `kCGWindowOwnerName` is the application's name, is public, and was present on 100 % of
        // rows at zero grants (probe P-74) — it is not a title, and it is excluded from the
        // fragment test by name rather than by weakening the test.
        report["windowMetadata"] = [
            "decodedKeys": host.windowDecodedKeys,
            "decodedKeysAreTitleFree": host.windowDecodedKeysAreTitleFree,
            "count": host.currentWindowCount() ?? -1
        ]

        // Both idle sources on every sample. `hardwareSeconds >= sessionSeconds` is a property
        // rather than a coincidence — `.combinedSessionState` counts a superset of the events
        // `.hidSystemState` does — so a violation means the reader swapped its sources (P-85).
        // The two are read microseconds apart, session first, so the elapsed time between them
        // lands on the side the invariant wants it on; see `IdleReader.read()`.
        let idle = host.idleReading
        report["idle"] = [
            "hardwareSeconds": idle.hardwareSeconds,
            "sessionSeconds": idle.sessionSeconds,
            // The gap itself, rather than a verdict computed against a tolerance the checker
            // cannot see. A 21-minute divergence was measured on this machine at one instant
            // (probe P-85), and the number is what makes that legible in a report.
            "hardwareMinusSessionSeconds": idle.hardwareSeconds - idle.sessionSeconds,
            "thresholdSeconds": host.settings.idleThresholdInterval,
            "isIdle": host.isIdle
        ]

        // The quorum's three inputs, recorded whatever the verdict — a surface that only showed
        // its working when it said yes would be showing half of it. `nil` where the frontmost
        // application is one the gate stood down from, which is the honest answer rather than a
        // zero.
        if let signals = host.currentPresentationSignals() {
            let state = PresentationQuorum.evaluate(signals: signals, isUserExcluded: false)
            report["presentation"] = [
                "frontmostWindowFillsAScreen": signals.frontmostWindowFillsAScreen,
                "presentationOptionsSayFullScreen": signals.presentationOptionsSayFullScreen,
                "menuBarHidden": signals.menuBarHidden,
                "agreementCount": signals.agreementCount,
                "isPresenting": state.isPresenting
            ]
        } else {
            report["presentation"] = ["suppressed": true]
        }

        // --- the pause probe, last, because it moves what everything above describes
        //
        // n → 0 → n, in-process, at zero grants.
        //
        // The graph is attached first where it was not already, because the person may have the
        // switch off and a probe reporting `0 → 0 → 0` would have proved nothing about
        // detaching. The **stored** switch is never touched — `pause()` is called directly
        // rather than through `setSensingPaused`, so whatever they chose is still what they
        // chose. The attachment state is put back exactly as it was found, through `stop()`,
        // which detaches without a session event: a self-check finishing is not a pause anybody
        // took.
        //
        // The pause and the resume are a matched pair carrying the same cause, so the session
        // ends where it began — `paused(cause: .globalPause)` followed by
        // `resumed(cause: .globalPause)` nets to nothing, which is precisely the property the
        // cause mechanism exists to give.
        let wasRunning = host.isRunning
        if !wasRunning { host.resume() }

        let before = host.liveObserverCount
        let audioBefore = host.audioListenerCount
        host.pause()
        let afterPause = host.liveObserverCount
        let audioAfterPause = host.audioListenerCount
        let cameraAfterPause = host.cameraListenersInstalled
        host.resume()
        let afterResume = host.liveObserverCount

        report["wasRunningBeforeProbe"] = wasRunning
        report["liveObserverCount"] = before
        report["liveObserverCountAfterPause"] = afterPause
        report["liveObserverCountAfterResume"] = afterResume
        report["audioListenerCountBeforePause"] = audioBefore
        report["audioListenerCountAfterPause"] = audioAfterPause
        report["cameraListenersInstalledAfterPause"] = cameraAfterPause

        // Input and output counted separately, because the microphone verdict is computed from
        // inputs alone: an *output* device flipped to running merely because `say` was speaking
        // (probe P-96), and treating that as a call would be the false positive the Court warned
        // about.
        report["media"] = [
            "inputDeviceCount": host.audioInputDeviceCount,
            "outputDeviceCount": host.audioOutputDeviceCount,
            "microphoneRunning": host.mediaActivity.microphoneRunning,
            "audioListenerCount": host.audioListenerCount,
            // Pinned, on every rig, camera or not. What is asserted is that the held path was
            // never *entered* — not an accident of this Mac having no camera (P-97/P-104).
            "cameraRunning": host.mediaActivity.cameraRunning,
            "cameraState": CapabilityState.unavailable.rawValue,
            "cameraReason": host.cameraUnavailableReason.rawValue,
            "cameraDeviceCount": host.cameraDeviceCount,
            "cameraListenersInstalled": host.cameraListenersInstalled
        ]

        if !wasRunning { host.stop() }

        return report
    }

    /// All twelve capabilities with the state the app itself computed — not a second probe run
    /// for the occasion, which would describe something the person never gets.
    @MainActor
    static func capabilityReport() -> [[String: Any]] {
        AppComposition.shared.sensingHost.capabilities.allStates.map { entry in
            [
                "capability": entry.capability.rawValue,
                "state": entry.state.rawValue
            ]
        }
    }

    // MARK: - e04 · the relevance engine (F-03, F-46, F-53)

    /// What the **running application** believes about the engine it is running.
    ///
    /// This is the third leg of R-75.4's three-way agreement. The unit lane asserts
    /// `EngineStamp.current.cacheKey` and `RelevancePolicy.digest` of the *test process*; stage
    /// 7d asserts the same literals of the *evaluation report*; and `self-check.sh` asserts them
    /// of *this* — on both configurations. All three compare against one committed set of
    /// literals, so a report generated against a different policy version cannot certify this
    /// build and neither can a product built against one.
    ///
    /// `engineStamp` is read from the live engine rather than from `EngineStamp.current`,
    /// because its `embeddingRevision` component is supplied by the OS at runtime (P-117): if
    /// Apple ships a new sentence-embedding asset in a point release, every distance the engine
    /// computes changes, and a stamp that counted only our own edits would not say so.
    ///
    /// Everything below is grant-free. `AXIsProcessTrusted()` is `false` in the evidence lane's
    /// `open -a` launch and the embedding still loads — measured from a zero-grant ad-hoc app
    /// bundle at P-110 — which is why the whole relevance layer is a T1 claim rather than a
    /// TCC-gated one.
    @MainActor
    static func relevanceReport() -> [String: Any] {
        let host = AppComposition.shared.relevanceHost
        var report: [String: Any] = [:]

        report["engineStamp"] = host.stampKey
        report["policyDigest"] = host.policyDigest

        // The seam really is the engine, not a second object built for the occasion.
        report["classifierIsEngine"] =
            (AppComposition.shared.classifier as AnyObject) === host.engine

        // The snapshot the engine judges against, as it stands. `skippedRuleCount` is the
        // R-72.3 drop made visible: a legacy `.session` row has no subject kind, reaches no
        // rung, and is counted rather than guessed at.
        report["snapshotBuildCount"] = host.snapshotBuildCount
        report["skippedRuleCount"] = host.skippedRuleCount
        report["snapshotMatchesRunningPolicy"] = host.snapshot.matchesRunningPolicy

        // One judgement, made here, in this process, at zero grants — so the report says the
        // engine *ran* rather than that it was constructed. The subject is whatever is
        // frontmost, read through the sensitivity gate like every other deeper answer.
        AppComposition.shared.refreshCockpit()
        report["judgementCount"] = AppComposition.shared.relevanceHost.judgementCount

        if let verdict = host.verdict {
            report["verdict"] = [
                "status": verdict.status.rawValue,
                "stage": verdict.stage.rawValue,
                "band": verdict.band?.rawValue ?? "",
                "isMandated": verdict.isMandated,
                "suppressionReason": verdict.eligibility.suppressionReason?.rawValue ?? "",
                "clauses": verdict.explanation.clauseKinds.map(\.rawValue),
                "stampKey": verdict.stampKey
            ]
        } else {
            // A real answer rather than a missing one: nothing has come forward, so nothing has
            // been judged, and the inspector draws "nothing judged yet".
            report["verdict"] = [:]
        }

        // R-72.2. e05 ships the one-click affordance that writes to the box, and a self-check
        // clicks nothing — so a launch that has judged things still finds it empty. That is now
        // an observation about a *reachable* mechanism rather than about an absent one, which
        // makes it a stronger statement than it was.
        report["sessionRuleCount"] = AppComposition.shared.sessionHost.sessionRuleBox.count

        return report
    }

    /// **The gateable form of "the app never triggers a permission prompt".**
    ///
    /// Probe P-95's technique (c), run on the shipped build: enumerate the owners of every
    /// on-screen window — which needs no grant, and which is measured to need none — and look
    /// for the processes macOS puts an authorisation dialog on the screen through. The list is
    /// asserted **empty** while the app runs.
    ///
    /// It goes through `SystemWindowList` and `WindowMetadataReader.decode`, which are the only
    /// route in this programme to `CGWindowListCopyWindowInfo` and which decode seven keys, none
    /// of them a window name. There is no way to reach a title from here even by accident.
    @MainActor
    static func authorisationSurfaceReport() -> (suspects: [String], owners: [String]) {
        let rows = WindowMetadataReader.decode(SystemWindowList().copyWindowInfo())
        let owners = Array(Set(rows.map(\.ownerName))).sorted()
        let suspects = owners.filter { owner in
            authorisationSurfaceOwners.contains { owner.localizedCaseInsensitiveContains($0) }
        }
        return (suspects, owners)
    }

    /// The processes an authorisation dialog belongs to, named one by one.
    ///
    /// Straight from probe P-95(c): the same six the zero-grant instrument watched for while the
    /// media path was exercised, and found none of, before or after.
    static let authorisationSurfaceOwners: [String] = [
        "UserNotificationCenter",
        "SecurityAgent",
        "universalAccessAuthWarn",
        "tccd",
        "TCCAgent",
        "CoreAuthUI"
    ]

    // MARK: - e02 · the URL type (F-142)

    /// Every scheme the built product declares, read from the merged `Info.plist`.
    ///
    /// This is what makes R-15 checkable at runtime rather than by reading the project file:
    /// the partial `Config/FocusSentinel-Info.plist` carries `CFBundleURLTypes`, the generated
    /// plist carries everything else, and only the *product* can say whether the merge worked.
    static func urlSchemes() -> [String] {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes")
            as? [[String: Any]] ?? []
        return types.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }
    }

    // MARK: - e02 · the global hot key (F-06)

    /// What the platform said when the app offered it the stored shortcut, and what it says
    /// when the same combination is offered a second time.
    ///
    /// Both halves are grant-free: `RegisterEventHotKey` is a public Carbon call and no TCC
    /// permission influences its return value either way (P-55, P-56). The duplicate probe
    /// uses a **second** registrar, because one registrar releases its own registration before
    /// making a new one — offering it twice through the same object would measure nothing.
    @MainActor
    static func hotKeyReport() -> [String: Any] {
        let composition = AppComposition.shared
        let spec = composition.hotKeySpec

        var report: [String: Any] = [:]
        report["status"] = status(of: composition.hotKeyRegistration)
        report["outcome"] = outcomeName(of: composition.hotKeyRegistration)
        report["available"] = composition.hotKeyRegistrar.availability.isAvailable
        report["registeredSpecMatches"] = composition.hotKeyRegistrar.registeredSpec == spec
        report["spec"] = [
            "keyCode": spec.keyCode,
            "modifierFlags": spec.modifierFlags,
            "glyphs": spec.glyphs
        ]

        let duplicate = CarbonHotKeyRegistrar()
        let duplicateResult = duplicate.register(spec) {}
        report["duplicateStatus"] = status(of: duplicateResult)
        report["duplicateOutcome"] = outcomeName(of: duplicateResult)
        // Whether it took or not, release it: this process must not leave a second claim on
        // the user's shortcut behind.
        duplicate.unregister()

        return report
    }

    /// The toolbox status a typed registration outcome stands for.
    ///
    /// `HotKeyRegistering` collapses the `OSStatus` into a case, because that is the vocabulary
    /// the settings UI needs. The numbers are put back here, and only here, so the self-check
    /// can assert on the same values probe P-55 measured: `noErr` for a fresh registration and
    /// `eventHotKeyExistsErr` (-9878) for a second claim on the same combination.
    static func status(of registration: HotKeyRegistration?) -> Int {
        switch registration {
        case .registered: 0
        case .alreadyRegistered: -9878
        case .failed(let status): Int(status)
        case .refused: -1
        case nil: -2
        }
    }

    static func outcomeName(of registration: HotKeyRegistration?) -> String {
        switch registration {
        case .registered: "registered"
        case .alreadyRegistered: "alreadyRegistered"
        case .failed: "failed"
        case .refused(let reason): "refused(\(reason))"
        case nil: "notAttempted"
        }
    }

    // MARK: - The application target's own wiring (focus-cp2)

    /// **What `App/` actually did**, read from inside the running application.
    ///
    /// `App/` is not a package. No test bundle can import it, so every closure in the scene graph
    /// is unreachable from the unit lane — and four no-op mutations to those closures survived
    /// the whole nineteen-stage gate byte for byte. One `App/` wire was already caught loudly:
    /// deleting `AppComposition.shared.start()` fails seven assertions here. This is the rest of
    /// them brought into the same shape, in the only lane that runs the shipping scene graph in
    /// the shipping process.
    ///
    /// Two facts per wire, and both are needed. `wiresFired` says **which** closure ran, so a
    /// failure names the line rather than a symptom three objects away; the effect beside it says
    /// **whether** it did anything, so a wire that fired and did nothing is not let through by its
    /// own receipt.
    ///
    /// Every reading here is grant-free: three properties of objects this process already owns,
    /// and one `responds(to:)`.
    @MainActor
    static func shellReport() -> [String: Any] {
        let composition = AppComposition.shared
        var report: [String: Any] = [:]

        report["wiresDeclared"] = ShellWire.allCases.map(\.rawValue).sorted()
        report["wiresFired"] = composition.shellWires.map(\.rawValue).sorted()

        // The cockpit's two `View`-only facts, as effects rather than as receipts.
        //
        // `adoptedTraits` is a sentinel and not a copy of what the panel is drawing with: the
        // model is initialised with `.systemDefault`, so "the shell themed the panel" and
        // "nobody ever told the panel anything" are the same reading on a machine whose
        // appearance happens to be the default.
        report["undoManagerAdopted"] = composition.priorityHost.journalUndoManager != nil
        report["undoManagerIsTheKeyWindows"] =
            composition.priorityHost.journalUndoManager === NSApp.keyWindow?.undoManager
        report["capturePanelTraitsAdopted"] = composition.quickCapturePanel.adoptedTraits != nil

        // **The appearance observer is attached to the Mac, and the shell reads it** (focus-2er).
        //
        // `refreshCount` is the observable half of "these registrations were made": it is `1`
        // after `init` and moves on every notification. The traits beside it are what the three
        // scenes inject, so a shell that stopped injecting them is a shell whose windows ignore
        // dark mode and every accessibility setting — which is what the mutation this block
        // exists for actually does.
        let traits = composition.appearance.traits
        report["appearancePreference"] = composition.appearance.preference.rawValue
        report["appearanceRefreshCount"] = composition.appearance.refreshCount
        report["appearanceColorScheme"] = traits.colorScheme.rawValue
        report["appearanceSystemColorScheme"] = AppearanceObserver.systemColorScheme.rawValue
        report["appearanceTraitsMatchTheSystem"] =
            traits.colorScheme == composition.appearance.preference
                .resolvedColorScheme(system: AppearanceObserver.systemColorScheme)
        report["storedAppearancePreference"] = composition.storedAppearancePreference().rawValue

        // **The handoff, driven through the shell's own delivery point** (F-142).
        //
        // `application(_:open:)` on `NSApp.delegate` is where AppKit hands a `kAEGetURL` event
        // to an application, and with an `@NSApplicationDelegateAdaptor` in play it is also how
        // SwiftUI feeds the cockpit scene's `.onOpenURL`. Calling it here therefore runs the
        // closure in `App/FocusSentinelApp.swift` — the whole point, because no test bundle can.
        //
        // It costs nothing and touches nothing: `PriorityHost.receive(_:)` parses and **shows**,
        // and there is no route from a shown handoff to a stored priority that does not pass
        // through a person pressing Replace. The URL is deliberately one no person would type.
        let delegate = NSApp.delegate
        report["urlHandlerAnswersOpen"] = (delegate as? NSObject)?
            .responds(to: #selector(NSApplicationDelegate.application(_:open:))) ?? false
        report["urlHandlerIsTheAppDelegate"] = delegate is FocusAppDelegate

        let handoff = URL(string: "focus://start?task=Self-check%20handoff%20probe")
        if let handoff {
            delegate?.application?(NSApplication.shared, open: [handoff])
        }
        report["handoffURL"] = handoff?.absoluteString ?? ""
        report["handoffWasShown"] = composition.cockpitState.pendingHandoff != nil
        report["handoffTask"] = composition.cockpitState.pendingHandoff?.task ?? ""
        // **Refused on the way out, and this is load-bearing** (F-142).
        //
        // A shown handoff opens the cockpit's confirmation sheet, and a sheet still attached when
        // `NSApp.terminate` runs is how a self-check turns into a hung gate stage — measured here,
        // twice, at twenty minutes apiece. Cancelling is also the truthful end for a handoff no
        // person asked for: `cancelHandoff()` is the *refuse* half of the surface, so this probe
        // leaves the store exactly as it found it.
        composition.priorityHost.cancelHandoff()
        report["handoffWasDismissed"] = composition.cockpitState.pendingHandoff == nil
        // Re-read after the drive: `handoffReceived` can only be in here because the shell's own
        // URL wire ran.
        report["wiresFired"] = composition.shellWires.map(\.rawValue).sorted()

        return report
    }

    /// How long to let the run loop turn after ⌘, and ⌘? have opened their windows.
    ///
    /// A SwiftUI `.task` is asynchronous, and the Settings window's is what re-reads the stored
    /// appearance preference. Measured here rather than guessed: with no turn at all the wire
    /// report is written in the same tick the window was created in and the task has not run.
    static let sceneSettleSeconds: TimeInterval = 1.5

    /// Give the run loop a turn without blocking it. `CFRunLoopRunInMode` rather than
    /// `Thread.sleep`, because everything this report is about happens on the main run loop.
    @MainActor
    static func settle(forSeconds seconds: TimeInterval) {
        CFRunLoopRunInMode(.defaultMode, seconds, false)
    }

    /// **Which of `App/`'s wires have fired, and which have not** (focus-2er).
    ///
    /// Read twice: once while the cockpit is the only window, and once after the key-equivalent
    /// probes have opened the Settings and Keyboard Shortcuts windows. The declared set is
    /// reported beside the fired one so a wire nobody wired at all is a **missing name** rather
    /// than a silent absence.
    @MainActor
    static func shellWireReport() -> [String: Any] {
        let composition = AppComposition.shared
        let fired = composition.shellWires
        return [
            "wiresDeclared": ShellWire.allCases.map(\.rawValue).sorted(),
            "wiresFired": fired.map(\.rawValue).sorted(),
            "wiresNotFired": ShellWire.allCases
                .filter { !fired.contains($0) }
                .map(\.rawValue)
                .sorted(),
            "themedSurfacesDeclared": ShellThemedSurface.allCases.map(\.rawValue).sorted(),
            // Which windows exist at the moment of the reading. A wire that belongs to a window
            // nobody opened has not failed; it has not been given the chance, and the difference
            // has to be legible in the report rather than guessed at from a missing name.
            "windowTitles": NSApp.windows.filter(\.isVisible).map(\.title).sorted()
        ]
    }

    // MARK: - e02 · undo through the system Edit menu (F-93)

    /// One scripted mutation, then a reading of the real Edit menu.
    ///
    /// F-93's whole claim is that the domain journal plugs into the standard Edit menu **with
    /// no menu code of our own**. That is only believable if it is read from the menu AppKit
    /// built, which is what this does: it registers one `activate` on the window's own
    /// `UndoManager` — the one `PriorityHost` was handed through
    /// `@Environment(\.undoManager)` — and then reads the Undo item's title and enablement,
    /// takes the undo, and reads them again.
    ///
    /// The mutation runs against an **in-memory** container, so a self-check can never touch
    /// the user's priority. The undo manager is the live one on purpose: a manager built for
    /// the occasion would prove nothing about the menu.
    ///
    /// ## The responder chain is reported, and it is why this used to fail (focus-h6d, focus-icq)
    ///
    /// This probe read the Edit menu without saying anything about the chain AppKit walks to
    /// build it, and on this machine it was reading a different undo manager entirely. Measured
    /// here, in the running app: `journalUndoManager === keyWindow.undoManager` is **true** — the
    /// wiring F-93 claims is correct and always was — while the key window's first responder is a
    /// **field editor**, an `NSTextView` AppKit installs for whichever `TextField` in the cockpit
    /// takes focus, and `NSTextView` overrides `undoManager` to return its own. So the item the
    /// menu validated belonged to the text field: `menuItemTitle` came back `Undo`, and on one run
    /// `Undo Typing`, with `enabledAfterUndo` true because that manager still had something in it.
    ///
    /// That is not a defect in the journal and it is not a defect in the menu integration — it is
    /// macOS behaving exactly as it should. While a person is editing text, Undo undoes their
    /// typing; the document's undo is what they get back when they are not. F-93's claim is about
    /// the latter, so the reading is taken in the latter state and **the state is asserted rather
    /// than assumed**: the chain is reported before and after, editing is ended, and
    /// `self-check.sh` fails on the wiring and on the responder rather than on the symptom.
    ///
    /// It also explains why this stage was intermittent — three gate runs on the same code passed
    /// earlier the same day. Whether a field editor exists at all depends on what the cockpit is
    /// drawing, which depends on the store: it is app state, not code, and reading it as a verdict
    /// on the code is what a probe that does not state its preconditions invites.
    @MainActor
    static func undoReport() -> [String: Any] {
        var report: [String: Any] = [:]

        // **The journal's own manager, with no fallback** (focus-cp2).
        //
        // It used to be `?? NSApp.keyWindow?.undoManager`, and that fallback was what made the
        // cockpit scene's `adoptUndoManager` wire invisible: mutated to a no-op, the journal held
        // nothing, this probe quietly picked the key window's manager up off the floor, registered
        // the scripted mutation on it, and every assertion below passed — describing an Edit menu
        // that works for a manager `PriorityStore` would never have written to. What F-93 claims
        // is that the *journal* reaches the standard Edit menu, so the journal's manager is the
        // one the reading is taken through, and its absence is a failure rather than a fallback.
        let manager = AppComposition.shared.priorityHost.journalUndoManager
        guard let manager else {
            report["available"] = false
            return report
        }
        report["available"] = true
        report["groupsByEvent"] = manager.groupsByEvent
        report["applicationIsActive"] = NSApp.isActive
        report["hasKeyWindow"] = NSApp.keyWindow != nil

        // --- the chain this reading is taken through, before anything is done about it --------
        let window = NSApp.keyWindow
        report["keyWindowIsCockpit"] = window != nil && window === liveCockpitWindow()
        // F-93's actual claim, and the one nothing asserted: the journal registers on the manager
        // the key window hands to the responder chain.
        report["windowUndoManagerIsJournal"] = window?.undoManager === manager
        report["firstResponderWasFieldEditor"] = isFieldEditor(window?.firstResponder)
        report["menuItemTitleWhileEditing"] = editMenuUndoItem()?.title ?? ""

        // End text editing, the way clicking outside a field does. A person reaching for Undo to
        // take back a priority change is not mid-word in a text field, and that is the state
        // F-93 describes — so it is the state the reading is taken in, and it is checked.
        let endedEditing = window?.makeFirstResponder(nil) ?? false
        report["editingEnded"] = endedEditing
        report["firstResponderIsFieldEditor"] = isFieldEditor(window?.firstResponder)
        report["responderUndoManagerIsJournal"] = window?.firstResponder?.undoManager === manager

        do {
            let container = try FocusStore.makeContainer(kind: .inMemory)
            let store = PriorityStore(context: ModelContext(container))
            // Created without the journal, then activated *through* it: the activation is the
            // operation whose action name is "Change Priority", which is the string P-50
            // measured arriving in the Edit menu.
            let taskID = try store.createTask(intent: "Self-check scripted mutation")
            try store.activate(taskID: taskID, undo: manager)

            report["actionName"] = manager.undoActionName
            report["undoManagerTitle"] = manager.undoMenuItemTitle
            let afterMutation = editMenuUndoItem()
            report["menuItemTitle"] = afterMutation?.title ?? ""
            report["enabled"] = afterMutation?.isEnabled ?? false

            if manager.canUndo { manager.undo() }

            report["undoManagerTitleAfterUndo"] = manager.undoMenuItemTitle
            let afterUndo = editMenuUndoItem()
            report["menuItemTitleAfterUndo"] = afterUndo?.title ?? ""
            report["enabledAfterUndo"] = afterUndo?.isEnabled ?? false
        } catch {
            report["available"] = false
            report["error"] = "\(error)"
        }

        return report
    }

    /// Whether this responder is a **field editor** — the shared `NSTextView` AppKit installs in
    /// front of whichever text field has focus.
    ///
    /// It matters because `NSTextView` overrides `undoManager` to answer with its own, so a field
    /// editor in the chain is the one thing that can stand between the Edit menu and the window's
    /// manager. Named rather than inlined, because "the first responder is a text view" and "the
    /// first responder is the text field's editor" are different claims and only the second one
    /// explains the reading.
    @MainActor
    private static func isFieldEditor(_ responder: NSResponder?) -> Bool {
        (responder as? NSTextView)?.isFieldEditor ?? false
    }

    /// The Edit menu's Undo item, after asking AppKit to validate the menu.
    ///
    /// Found by its action rather than by its position, because the item's *title* is exactly
    /// what is being measured and matching on it would make the assertion circular.
    @MainActor
    private static func editMenuUndoItem() -> NSMenuItem? {
        for item in NSApp.mainMenu?.items ?? [] {
            guard let submenu = item.submenu else { continue }
            submenu.update()
            if let undoItem = submenu.items.first(where: { $0.action == Selector(("undo:")) }) {
                return undoItem
            }
        }
        return nil
    }

    // MARK: - e02 · the quick-capture panel (F-06)

    /// Whether the panel really was built at launch, and how long showing it takes.
    ///
    /// Probe P-57 measured 34 ms from the hot key to a visible, focused panel — against F-06's
    /// budget of two seconds. The threshold the checker asserts is 250 ms: a regression guard
    /// with two orders of magnitude of slack, not a restatement of the claim. What it really
    /// catches is somebody moving the panel's construction into `show()`, which is the one way
    /// to lose the measurement.
    @MainActor
    static func capturePanelReport() -> [String: Any] {
        let panel = AppComposition.shared.quickCapturePanel
        var report: [String: Any] = [:]
        report["prebuilt"] = panel.isPrebuilt

        let started = ProcessInfo.processInfo.systemUptime
        panel.show()
        let elapsed = ProcessInfo.processInfo.systemUptime - started

        report["showMilliseconds"] = elapsed * 1_000
        report["visibleAfterShow"] = panel.isVisible
        panel.hide()
        report["hiddenAfterHide"] = !panel.isVisible
        return report
    }

    // MARK: - e02 · the priority is the hero, structurally (F-02, F-147)

    /// The hero's point size beside the largest of every other role in the package.
    ///
    /// `TypeHierarchyTests` asserts the same ordering at the unit level; this asserts it in the
    /// **running app**, where the sizes come from `NSFont.preferredFont(forTextStyle:)` on the
    /// user's real system rather than from a test host.
    @MainActor
    static func priorityHeroReport() -> [String: Any] {
        let hero = DesignTokens.pointSize(.priorityHero)
        let others = DesignTokens.FontRole.allCases
            .filter { $0 != .priorityHero }
            .map { (role: $0.rawValue, size: DesignTokens.pointSize($0)) }
        let largest = others.max { $0.size < $1.size }

        return [
            "pointSize": hero,
            "largestOtherRole": largest?.role ?? "",
            "largestOtherPointSize": largest?.size ?? 0,
            "roleCount": DesignTokens.FontRole.allCases.count
        ]
    }

    /// The cockpit, among the windows this process owns.
    ///
    /// Found by the scene's own identifier rather than by "the first titled window", because
    /// from e02 the app owns a **second** titled window from the moment it launches: the
    /// quick-capture panel, which is a titled utility `NSPanel` built at launch so that the
    /// hot key can show it in tens of milliseconds (P-57). It is titled and closable but
    /// neither resizable nor miniaturizable, so the old heuristic would have described the
    /// panel and then failed the cockpit's standard-window assertions.
    ///
    /// The `ShellWindow.cockpit.id` string is what SwiftUI stamps on the window as its
    /// identifier; the shape check is kept as a fallback so a future SwiftUI that stops
    /// stamping it degrades to the old behaviour rather than reporting no cockpit at all.
    @MainActor
    static func cockpitWindow(in windows: [[String: Any]]) -> [String: Any]? {
        if let identified = windows.first(
            where: { ($0["identifier"] as? String) == ShellWindow.cockpit.id }
        ) {
            return identified
        }
        return windows.first {
            ($0["titled"] as? Bool) == true && ($0["resizable"] as? Bool) == true
        }
    }

    /// The whole of `NSApp.mainMenu`, one level deep.
    ///
    /// `NSMenu.update()` on each submenu is load-bearing: without it every submenu reads as
    /// empty, because AppKit populates menus lazily and nothing has opened them.
    @MainActor
    static func menuTree() -> [[String: Any]] {
        guard let mainMenu = NSApp.mainMenu else { return [] }
        return mainMenu.items.map { item in
            var entry: [String: Any] = ["title": item.title]
            if let submenu = item.submenu {
                submenu.update()
                entry["items"] = submenu.items.map(describe)
            } else {
                entry["items"] = [[String: Any]]()
            }
            return entry
        }
    }

    @MainActor
    private static func describe(_ item: NSMenuItem) -> [String: Any] {
        [
            "title": item.title,
            "keyEquivalent": item.keyEquivalent,
            "modifierMask": Int(item.keyEquivalentModifierMask.rawValue),
            "isEnabled": item.isEnabled,
            "hasAction": item.action != nil,
            "isSeparator": item.isSeparatorItem,
            "hasSubmenu": item.submenu != nil
        ]
    }

    /// Every window this process owns, described by the facts that distinguish a standard
    /// Mac window from custom chrome.
    ///
    /// Note what is *not* asserted anywhere downstream: `fullSizeContentView`. A SwiftUI
    /// `Window` scene on macOS 26 sets that bit by default — the style mask reads `32783` —
    /// so reading it as "custom chrome" would fail a perfectly standard window.
    @MainActor
    static func windowReports() -> [[String: Any]] {
        NSApp.windows.map { window in
            let mask = window.styleMask
            return [
                "title": window.title,
                "identifier": window.identifier?.rawValue ?? "",
                "isVisible": window.isVisible,
                "styleMask": Int(mask.rawValue),
                "titled": mask.contains(.titled),
                "closable": mask.contains(.closable),
                "miniaturizable": mask.contains(.miniaturizable),
                "resizable": mask.contains(.resizable),
                "fullSizeContentView": mask.contains(.fullSizeContentView),
                "titlebarAppearsTransparent": window.titlebarAppearsTransparent,
                "hasToolbar": window.toolbar != nil,
                "standardButtons": [
                    "close": window.standardWindowButton(.closeButton) != nil,
                    "miniaturize": window.standardWindowButton(.miniaturizeButton) != nil,
                    "zoom": window.standardWindowButton(.zoomButton) != nil
                ]
            ]
        }
    }

    /// Hands the menu bar a synthesised key event and reports whether it claimed it.
    ///
    /// This is the runtime half of the keyboard contract: the registry test proves the
    /// *intent*, this proves the menu bar actually took the shortcut.
    ///
    /// ⌘Q is never probed. Performing it terminates the app before the report is written —
    /// which was learned the hard way.
    @MainActor
    static func keyEquivalentClaims() -> [String: Bool] {
        // ⌘N and ⌘O are probed first, because ⌘W closes the key window and ⌘, opens another —
        // and a probe that runs after them is measuring a different window's menu bar.
        //
        // Performing a key equivalent really performs it. ⌘N puts the cursor in the capture
        // field, which costs nothing. ⌘O opens the context file importer, but only when there
        // *is* a priority to attach files to — with none, the cockpit asks for one instead of
        // opening a panel whose result would have nowhere to go. `runAndTerminate` closes any
        // sheet these probes leave behind, so a machine whose store already holds a priority
        // still exits cleanly.
        [
            "cmd-n": claims(characters: "n", modifiers: .command),
            "cmd-o": claims(characters: "o", modifiers: .command),
            "cmd-w": claims(characters: "w", modifiers: .command),
            "cmd-comma": claims(characters: ",", modifiers: .command),
            "cmd-question": claims(characters: "?", modifiers: .command)
        ]
    }

    @MainActor
    private static func claims(characters: String, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard
            let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: NSApp.keyWindow?.windowNumber ?? 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: 0
            )
        else {
            return false
        }
        return NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
    }

    /// Take down every attached sheet, so nothing can block `NSApp.terminate`.
    @MainActor
    private static func dismissEverySheet() {
        for window in NSApp.windows {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
        }
    }

    /// The resolved status token table.
    ///
    /// Resolved, not declared: the `label` here is what the running app would actually
    /// render, so the check can prove no label echoes its own key — the failure mode you
    /// get when a String Catalog is copied instead of compiled.
    static func statusTokens() -> [[String: Any]] {
        FocusStatus.allCases.map { status in
            [
                "case": status.rawValue,
                "symbol": status.symbolName,
                "shape": status.shape.rawValue,
                "labelKey": status.shortLabelKey,
                "label": status.shortLabel
            ]
        }
    }

    // MARK: - e03 · the two-launch reconciliation proof (F-97, R-46)

    /// Write a session back-dated ninety minutes into a store of its own, and say what the
    /// world looked like while doing it.
    ///
    /// ## Why the anchor is back-dated too, and by exactly the same amount
    ///
    /// The persisted anchor is `mach_continuous_time` seconds since boot, and the reconciler
    /// compares wall-clock elapsed against uptime elapsed for the current phase. A session whose
    /// wall clock says ninety minutes and whose anchor says *now* would differ by 5 400 s and
    /// would raise `.clockAnomaly` — an anomaly this fixture manufactured rather than one the
    /// world produced. Moving both by the same amount models what actually happened on a Mac
    /// that was up ninety minutes ago: wall and uptime advance **together**, the drift is zero,
    /// and the only note the restoring launch raises is the one it is supposed to
    /// (`restoredStale`).
    ///
    /// A separate container at a path the caller chose, so this can never touch the person's own
    /// store. `SessionStore.start` is called through injected clocks rather than the system
    /// ones, which is the same seam every unit test uses.
    @MainActor
    static func seedSessionReport(storePath: String) throws -> [String: Any] {
        let container = try FocusStore.makeContainer(kind: .temporary(URL(fileURLWithPath: storePath)))
        let context = ModelContext(container)

        let uptimeClock = SystemUptimeClock()
        let bootIdentity = BootIdentity.current()
        // Through the injected provider, like every other timestamp in this programme: a bare
        // `Date()` is banned repository-wide by lint, and the reason applies here too — the
        // seeded fixture has to be reproducible against a clock somebody chose.
        let wallNow = SystemDateProvider().now
        let uptimeNow = uptimeClock.uptimeSeconds
        let startedAt = wallNow.addingTimeInterval(-seedBackdateSeconds)

        let store = SessionStore(
            context: context,
            dateProvider: FixedDateProvider(now: startedAt),
            uptimeClock: TestUptimeClock(uptimeSeconds: uptimeNow - seedBackdateSeconds),
            bootIdentity: bootIdentity
        )
        let sessionID = try store.start(kind: .openEnded)

        return [
            "mode": "seed",
            "store": storePath,
            "sessionID": sessionID.uuidString,
            // ISO-8601 with fractional seconds, so "byte-identical `startedAt`" is a string
            // comparison the checker can make rather than a float it has to round.
            "startedAt": iso8601(startedAt),
            "backdatedSeconds": seedBackdateSeconds,
            "phase": SessionPhase.focus.rawValue,
            "bootIdentity": bootIdentity,
            "uptimeSeconds": uptimeNow,
            "wallSeconds": wallNow.timeIntervalSince1970
        ]
    }

    /// Open the store the seeding launch wrote, reconcile it, and report every figure §4.6
    /// asserts on.
    ///
    /// This is the **only** place the anchor's cross-process comparability can be proved: a unit
    /// test cannot span two processes, and a value that reset per process — which
    /// `MonotonicClock.elapsed` and `ContinuousClock.Instant` both do — would sail through one
    /// and fail here (probes P-105/P-106).
    ///
    /// No timer is started by any of this, because there is none to start.
    @MainActor
    static func restoreSessionReport(storePath: String) throws -> [String: Any] {
        let container = try FocusStore.makeContainer(kind: .temporary(URL(fileURLWithPath: storePath)))
        let context = ModelContext(container)

        let uptimeClock = SystemUptimeClock()
        let bootIdentity = BootIdentity.current()
        let wallNow = SystemDateProvider().now
        let uptimeNow = uptimeClock.uptimeSeconds

        let store = SessionStore(
            context: context,
            dateProvider: SystemDateProvider(),
            uptimeClock: uptimeClock,
            bootIdentity: bootIdentity
        )

        var report: [String: Any] = [
            "mode": "restore",
            "store": storePath,
            "bootIdentity": bootIdentity,
            "uptimeSeconds": uptimeNow,
            "wallSeconds": wallNow.timeIntervalSince1970
        ]

        guard let restored = try store.restore() else {
            report["restored"] = false
            return report
        }

        report["restored"] = true
        report["sessionID"] = restored.sessionID.uuidString
        report["startedAt"] = iso8601(restored.startedAt)
        report["elapsedWallSeconds"] = restored.elapsedWallSeconds
        report["phase"] = restored.phase.rawValue
        report["pauseCauses"] = restored.pauseCauses.sorted().map(\.rawValue)
        report["resumeTo"] = restored.resumeTo?.rawValue ?? ""
        report["notes"] = restored.notes.map(\.rawValue).sorted()
        report["driftSeconds"] = restored.driftSeconds ?? -1
        return report
    }

    /// The local timeline, exported as JSON for the live evidence lane to read.
    ///
    /// It carries only what a `NormalisedDetail` can hold — closed-vocabulary tokens, numbers,
    /// bundle identifiers and timestamps — because there is no `NormalisedDetail(String)` and
    /// therefore no route by which a window title, a URL or a document name could be in it.
    @MainActor
    static func exportEvents(to path: String) throws {
        let data = try AppComposition.shared.eventStore.exportJSON()
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// One format, fixed, for every timestamp this report carries.
    ///
    /// Built per call rather than held as a shared instance: `ISO8601DateFormatter` is a class
    /// with mutable options and is not `Sendable`, and a static one would be a shared mutable
    /// object under Swift 6's checking. Formatting a handful of dates costs nothing.
    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Run one of the headless modes and exit.
    ///
    /// Headless in the sense that matters: nothing here waits for the app to come forward, reads
    /// a menu or touches a window, because none of these claims is about the shell. That is also
    /// what makes the two-launch proof cheap enough to be a gate step.
    @MainActor
    static func runModeAndTerminate(writingTo path: String, body: () throws -> [String: Any]) {
        do {
            let data = try JSONSerialization.data(
                withJSONObject: body(),
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            print("SELF-CHECK WROTE \(path)")
            fflush(stdout)
            NSApp.terminate(nil)
        } catch {
            FileHandle.standardError.write(Data("SELF-CHECK FAILED: \(error)\n".utf8))
            exit(70)
        }
    }

    // MARK: - Running it

    @MainActor
    static func runAndTerminate(writingTo path: String, activation: Activation) {
        // Dismissed **before and after** the report, and the second pass is the one that matters.
        //
        // A sheet still attached when `NSApp.terminate` runs is how a self-check turns into a hung
        // gate stage — measured here, twice, at twenty minutes apiece. The sheets that can be up
        // are the ones `report(activation:)` itself opens: the ⌘O probe's file importer and the
        // handoff probe's confirmation surface. A pass that runs before it therefore cleans up
        // after the *previous* launch and nothing else, which is what this used to be.
        dismissEverySheet()

        do {
            let data = try JSONSerialization.data(
                withJSONObject: report(activation: activation),
                options: [.prettyPrinted, .sortedKeys]
            )
            dismissEverySheet()
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            print("SELF-CHECK WROTE \(path)")
            fflush(stdout)
            NSApp.terminate(nil)
        } catch {
            FileHandle.standardError.write(
                Data("SELF-CHECK FAILED: \(error)\n".utf8)
            )
            exit(70)
        }
    }
}

/// Hosts the self-check. In every other respect the app has no delegate behaviour: the
/// scenes are SwiftUI's.
@MainActor
public final class FocusAppDelegate: NSObject, NSApplicationDelegate {
    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        guard let path = SelfCheck.requestedOutputPath else { return }

        // The headless modes first. None of them has anything to say about the shell, so none of
        // them waits to come forward — which is what makes the two-launch reconciliation proof
        // cheap enough to be a gate step rather than an evidence lane.
        if let store = SelfCheck.requestedSeedStorePath {
            SelfCheck.runModeAndTerminate(writingTo: path) {
                try SelfCheck.seedSessionReport(storePath: store)
            }
            return
        }
        if let store = SelfCheck.requestedRestoreStorePath {
            SelfCheck.runModeAndTerminate(writingTo: path) {
                try SelfCheck.restoreSessionReport(storePath: store)
            }
            return
        }
        if let export = SelfCheck.requestedEventExportPath {
            SelfCheck.runModeAndTerminate(writingTo: path) {
                try SelfCheck.exportEvents(to: export)
                return ["mode": "export", "events": export]
            }
            return
        }
        if SelfCheck.wantsNudgeOnly {
            // Headless in the sense that matters: it never comes forward, never reads a menu and
            // never takes a key window — which is also what makes its focus readings mean
            // something. An application that had activated itself to run this check would be
            // reporting on a state it had just created.
            SelfCheck.runModeAndTerminate(writingTo: path) {
                var report = SelfCheck.nudgeReport()
                report["mode"] = "nudge"
                return report
            }
            return
        }

        // Bring the app forward, for the length of the check and only in this mode, and do not
        // read a single thing about the shell until it really is forward.
        //
        // Menu validation walks the **key window's** responder chain, and a background
        // application has no key window at all — measured here: with the app left inactive the
        // Edit menu's Undo item reads `Undo`, disabled, however many operations the journal
        // has registered. F-93's claim is about the item a person sees, so the item has to be
        // validated the way a person's Mac would validate it. The ordinary app never runs this
        // path: `requestedOutputPath` is `nil` unless `--focus-self-check` was passed.
        //
        // Waiting for the activation to *land* is the load-bearing half. A fixed delay after
        // requesting it made the report a race against whatever else the machine was doing,
        // and the race was lost often enough to fail the gate on a green tree.
        SelfCheck.comeForward { activation in
            // One more turn of the run loop, then read the shell. Reading it inside
            // `applicationDidFinishLaunching` reports empty submenus and no windows.
            DispatchQueue.main.asyncAfter(deadline: .now() + SelfCheck.settleDelay) {
                MainActor.assumeIsolated {
                    SelfCheck.runAndTerminate(writingTo: path, activation: activation)
                }
            }
        }
    }

    /// A single-window cockpit has nothing to keep running once its window is gone.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
