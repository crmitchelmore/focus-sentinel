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

    /// **Open a store somebody else seeded, as the whole application** (focus-h7h).
    ///
    /// Not the same thing as `--focus-session-restore`, which builds one `SessionStore` and reads
    /// it. This makes the **composition root** open it, so the shipping scene graph draws a state
    /// this lane chose — and it exists for exactly one reason.
    ///
    /// `sessionElapsedSeconds` is the one boundary value that cannot be observed in an ordinary
    /// launch. The mutation that guts it writes `nil`, and a Mac with no session running hands the
    /// window `nil` too: the mutant and the shipping code are then extensionally identical, and no
    /// instrument whatsoever can tell them apart. That is a theorem about the two programs, not a
    /// limitation of the mechanism — so the only fix is to run the check where the value is not
    /// `nil`, which means a launch with a session in it.
    ///
    /// A store of the caller's own, at a path they chose, so this can never touch the person's:
    /// the alternative was starting a session in the real store, which would write a fact about
    /// their day that never happened.
    static let storeArgument = "--focus-store"

    /// Which store `AppComposition.shared` opens.
    ///
    /// Read from the command line at static-initialisation time, which is before any scene exists
    /// — the composition root is first touched by `FocusSentinelApp.init()`. The ordinary launch
    /// passes nothing and gets `.applicationSupport`, which is the only behaviour the shipping app
    /// has ever had.
    public static var requestedStoreKind: FocusStore.Kind {
        guard let path = value(after: storeArgument) else { return .applicationSupport }
        return .temporary(URL(fileURLWithPath: path))
    }

    /// **The cockpit-rendering block alone, against a seeded store** (focus-h7h).
    ///
    /// Comes forward, because a window that is not on screen has not drawn; reports what the
    /// cockpit put on the screen and nothing else, because every other claim in the ordinary
    /// report is about the person's own store and would be answering a different question here.
    static let cockpitArgument = "--focus-self-check-cockpit"

    static var wantsCockpitOnly: Bool { CommandLine.arguments.contains(cockpitArgument) }

    /// How far back the seeded session's `startedAt` is dated. Ninety minutes, which is what
    /// §4.6 asserts the restoring launch reports to within two seconds.
    static let seedBackdateSeconds: Double = 5_400

    /// The commitment the seeded store carries.
    ///
    /// A sentence no person would type, for the reason the handoff probe's is: it has to be a
    /// value a frozen placeholder could not be carrying by coincidence.
    static let seededPriorityIntent = "Self-check seeded commitment"

    /// **What the cockpit drew, against a store somebody seeded** (focus-h7h).
    ///
    /// One block, and one reason for it. The elapsed figure is the only boundary value that
    /// cannot be observed in an ordinary launch: the mutation that guts it hands the window
    /// `nil`, and a Mac with no session running hands it `nil` too, so the mutant and the
    /// shipping code are extensionally identical and nothing can separate them. Here there is a
    /// session — ninety minutes old, in a store this lane wrote — so `nil` is a value the app
    /// never produces and drawing it is a defect the gate can name.
    ///
    /// It reports the cockpit and nothing else. Every other claim in the ordinary report is about
    /// the person's own store, and answering it against a fixture would be answering a different
    /// question.
    @MainActor
    static func cockpitRenderingReport() -> [String: Any] {
        let composition = AppComposition.shared

        // **Open the cockpit the way a person does, because it may not be open.**
        //
        // Measured here: this launch came forward with no cockpit at all — `NSApp.windows` held
        // only the menu-bar item — and waited out the whole deadline reporting nothing drawn. A
        // SwiftUI `Window` scene restores whether it was open, and the *previous* launch in this
        // script is the ordinary self-check, whose ⌘W probe closes it. So the state this lane
        // inherits is "closed", and a window nobody opened has correctly drawn nothing.
        //
        // ⌘N is the File menu's New Priority, whose effect opens the cockpit and puts the cursor
        // in the capture field — the same key equivalent the ordinary report probes, reaching the
        // same `openWindow(id:)`. Pressing it is what a person would do, and it costs nothing.
        _ = claims(characters: "n", modifiers: .command)

        // **Wait until the window has really drawn, and time out loudly rather than early.**
        //
        // The same doctrine `comeForward` is built on, and for the same measured reason. A fixed
        // delay here reported an empty rendering with `generation: 0` — the cockpit's scene body
        // had run, so the appearance-traits injection had been recorded, but `CockpitHost.body`
        // had not, so no connection had been issued and nothing had been drawn. A reading taken
        // then describes a window that has not been asked to draw yet, and it is indistinguishable
        // from a window that refused to.
        let drewInMilliseconds = settle(untilCockpitDrewFor: composition)

        let reading = composition.shellRenderReading(of: .cockpit)
        let drawn = composition.shellRenderings[.cockpit] ?? .nothing
        let session = composition.sessionHost.snapshot

        return [
            "mode": "cockpit",
            "reading": reading.dictionary,
            "drewWhatTheAppKnows": reading.drewWhatTheAppKnows,
            "rendered": drawn.dictionary,
            // The two facts that say the fixture actually arrived. Without them the reading above
            // would pass on a launch whose store failed to open, by comparing two absences.
            "liveSessionElapsedSeconds": composition.sessionElapsedSeconds ?? -1,
            "livePriorityIntent": composition.cockpitState.priority?.intent ?? "",
            "drawnSessionElapsedSeconds": drawn[.sessionElapsedSeconds] ?? "",
            "drawnPriorityIntent": drawn[.priorityIntent] ?? "",
            "seededPriorityIntent": seededPriorityIntent,
            "drewInMilliseconds": drewInMilliseconds,
            "windowTitles": NSApp.windows.filter(\.isVisible).map(\.title).sorted()
        ]
    }

    /// How long to wait for the cockpit to draw before reading what it drew.
    static let cockpitDrawDeadline: TimeInterval = 8.0

    /// Turn the run loop until the cockpit has reported drawing from the connection the
    /// composition root has most recently issued, or until the deadline.
    ///
    /// Reaching the deadline is a **reported failure**, not a fallback: the report carries the
    /// elapsed figure and the visible window titles, so a machine that never draws the cockpit
    /// fails as "the window never drew" rather than later, in the value comparison, for a reason
    /// that looks like a defect in the values.
    @MainActor
    static func settle(untilCockpitDrewFor composition: AppComposition) -> Double {
        let started = ProcessInfo.processInfo.systemUptime
        while ProcessInfo.processInfo.systemUptime - started < cockpitDrawDeadline {
            let issued = composition.shellGeneration(of: .cockpit)
            if issued > 0, composition.shellRenderings[.cockpit]?.generation == issued {
                break
            }
            settle(forSeconds: 0.05)
        }
        return (ProcessInfo.processInfo.systemUptime - started) * 1_000
    }

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
        // **Read the menu bar for an alert, then press it** (focus-h7h).
        //
        // `menuTree()` above called `update()` on every submenu, which is AppKit's last chance to
        // re-install its automatic Help item before ⌘? is performed — and performing that item
        // runs `-[NSAlert runModal]`, takes the main thread and this report is never written.
        // Measured twice at HEAD, in isolation, killed at ten minutes both times.
        //
        // So the reading is taken and the item is taken down in the same call, immediately before
        // the probe. The count is reported rather than swallowed: `0` is *"the registry's action
        // was already the only ⌘?"*, and anything else says AppKit put one back after launch,
        // which is a fact about this build's menu bar and not a detail of the instrument.
        let reinstalledHelpItems = ShellHelpMenu.detachAutomaticItem()
        let claims = keyEquivalentClaims()
        // **After the key probes, and that is the point** (focus-2er). ⌘, opens the Settings
        // window and ⌘? opens the Keyboard Shortcuts window, so the wires those two scenes carry
        // — their connections, their `.task`, their appearance-traits injections — cannot have
        // fired before this line. The run loop is given a turn first, because `.task` is
        // asynchronous and a report written in the same tick would describe the moment before it.
        settle(forSeconds: sceneSettleSeconds)
        let shellAfterProbes = shellWireReport()
        // **Last, because it needs all three windows and it moves the world** (focus-h7h).
        //
        // The Settings and Keyboard Shortcuts windows do not exist until ⌘, and ⌘? have been
        // pressed, so neither can have reported what it drew before this line; and the block
        // drives the appearance and both of the Settings pane's sinks, which changes what every
        // reading above describes. It puts all three back.
        let rendering = shellRenderingReport()

        var root: [String: Any] = [:]
        root["bundleIdentifier"] = Bundle.main.bundleIdentifier ?? ""
        root["displayName"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName")
            as? String ?? ""
        root["menuBarTitles"] = menu.compactMap { $0["title"] as? String }
        root["menu"] = menu
        // **Which menus still hold an item that opens an alert** (focus-h7h).
        //
        // Empty is the claim: ⌘? reaches the Keyboard Shortcuts window, because the registry's
        // action is the only ⌘? left in the menu bar. A non-empty list names the menu whose first
        // item would run `-[NSAlert runModal]` and take the main thread — which is what hung this
        // very report, twice, before `ShellHelpMenu` existed.
        root["menusWithAnAutomaticHelpItem"] =
            ShellHelpMenu.automaticItemsRemaining(in: NSApp.mainMenu)
        // How many AppKit had put back between launch and the probes. Recorded beside the list
        // above so a reader can tell "there was never one" from "there was one and it was taken
        // down in time".
        root["automaticHelpItemsReinstalled"] = reinstalledHelpItems
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
        // What the three windows actually drew, beside what the composition root handed them.
        root["shellRendering"] = rendering
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
    /// 2. **Every rung has a surface, and no notification authorisation can change which.** Read
    ///    from `SurfaceRouter` — the committed table the settings pane renders — so the report
    ///    and the behaviour cannot be two different answers. Since focus-wy0 the router takes no
    ///    authorisation, so this is one table rather than three.
    /// 3. **Nothing asked for a permission, and nothing could.** `requestAuthorizationCallCount`
    ///    is published by the notification boundary; `requestAuthorization(` appears in no file
    ///    of this repository, so the number is a property of the call graph rather than of a
    ///    counter somebody remembered to leave alone.
    /// **Every accusation route in the whole input space, and which of them cannot be answered**
    /// (focus-uru, focus-vxo).
    ///
    /// A named function rather than a loop inside `nudgeReport()`, for the reason focus-vxo turns
    /// on: the same fold with the same exemption existed twice, once here and once in
    /// `SurfaceRouterTests`, and they agreed with each other for as long as they shared the
    /// blind spot. One fold, run by the binary and by the unit lane, cannot do that.
    ///
    /// **The rung is the requested one and every input varies.** It asked the rung a *deck*
    /// claimed to render and pinned an idle microphone and no presentation, so the reading it
    /// produced was true of a space chosen so that it could not be false.
    ///
    /// Returns the offending cells named, so a red gate says which rung under which conditions,
    /// and the number of cells visited, so a fold that quietly shrinks is visible as a number
    /// rather than as an unchanged `true`.
    nonisolated static func accusationRouteAudit() -> (cells: Int, unanswerable: [String]) {
        let presenting = PresentationState(
            signals: PresentationSignals(
                frontmostWindowFillsAScreen: true,
                presentationOptionsSayFullScreen: true,
                menuBarHidden: true
            ),
            isUserExcluded: false,
            isPresenting: true
        )
        var unanswerable: [String] = []
        var cells = 0

        for rung in LadderRung.Kind.allCases where rung.makesAnAccusation {
            for presentation in [PresentationState.notPresenting, presenting] {
                for media in [MediaActivity.idle, MediaActivity(microphoneRunning: true)] {
                    for reduced in [false, true] {
                        for menuBar in [true, false] {
                            for voice in NudgeVoice.allCases {
                                cells += 1
                                let route = SurfaceRouter.route(
                                    rung: rung,
                                    presentation: presentation,
                                    media: media,
                                    reducedInterruption: reduced,
                                    menuBarVisible: menuBar,
                                    voice: voice
                                )
                                guard let surface = route.surface, !surface.offersAnAnswer else {
                                    continue
                                }
                                var cell = "\(rung.rawValue)/\(voice.rawValue)"
                                cell += "/reduced=\(reduced)/menuBar=\(menuBar)"
                                cell += "/presenting=\(presentation.suppressesOverlays)"
                                cell += "/mic=\(media.suppressesIntervention)"
                                cell += " -> \(surface.rawValue)"
                                unanswerable.append(cell)
                            }
                        }
                    }
                }
            }
        }
        return (cells, Set(unanswerable).sorted())
    }

    @MainActor
    static func nudgeReport() -> [String: Any] {
        let composition = AppComposition.shared
        let host = composition.nudgeHost
        var report: [String: Any] = [:]

        report["interventionDigest"] = InterventionPolicy.digestHex
        report["interventionVersion"] = InterventionPolicy.version
        report["ladderRungsDeclared"] = LadderRung.Kind.allCases.count
        // Which surfaces offer the person something to press. Since U-2 this is what decides
        // whether an interruption standing there occupies the one interruption slot — for a
        // **question** exactly as for a rung. A glyph and a badge do not: nothing on either can be
        // pressed to take it down, so either would hold the slot for the whole session. That is
        // the whole of both halves of the defect — a rung on the glyph silencing every question
        // that followed, and a question on the badge silencing every accusation.
        report["surfacesHoldingTheInterruptionSlot"] =
            NudgeSurface.allCases.filter(\.holdsTheInterruptionSlot).map(\.rawValue).sorted()
        // **And the different question: which surfaces a person can answer back on** (focus-uru).
        // It was the same reading under one name, and the two parted company when the popover
        // grew the correction economy: the badge is answerable once looked at and still does not
        // occupy the screen behind an unclicked status item. Reported separately so that a future
        // conflation is visible in the evidence rather than only in a comment.
        report["surfacesOfferingAnAnswer"] =
            NudgeSurface.allCases.filter(\.offersAnAnswer).map(\.rawValue).sorted()
        // **What this Mac's grant state actually is, reported and acted on by nothing**
        // (focus-wy0). It is the reading that makes the `notification-denied` stage a
        // measurement: "this machine was at *x*, and every rung still landed in-app".
        //
        // `permitsNotificationDelivery` was published beside it and is gone. An application that
        // posts no notifications has no business publishing a belief about whether it may — and
        // it read `true` on this Mac in the same run that reported no rung can reach a
        // notification, which is two lines of one report contradicting each other.
        report["notificationAuthorisation"] = host.notificationAuthorisation.rawValue
        report["requestAuthorizationCallCount"] = host.requestAuthorizationCallCount

        // **A nudge on the screen that the loop has forgotten** — always empty (focus-v0u,
        // focus-xix).
        //
        // The invariant `NudgeHost.endOpenQuestion(_:)` and `NudgeHost.setOpenRung(_:)` exist to
        // keep, read off the shipping graph in the shipping process. A non-empty list is the
        // defect itself: a live panel or an open popover offering answers that `answer(_:)` will
        // drop in a `guard` — or, worse, that `resolve(_:snoozeDuration:)` will apply to a
        // different rung. The unit lane drives every exit; this says the running app is not in
        // that state.
        //
        // **The key was `orphanedQuestionSurfaces` and it read half the screen.** The accusation
        // can be orphaned on both of the same surfaces and had no reading at all, which is the
        // shape of this whole round: every treatment the question path received, the accusation
        // path lacked.
        report["orphanedNudgeSurfaces"] = host.orphanedNudgeSurfaces.map(\.rawValue).sorted()
        report["questionExitsDeclared"] = QuestionExit.allCases.map(\.rawValue).sorted()
        // **Which exits owe the record**, read off the type rather than off the call sites
        // (focus-h0s). The record was the one of an exit's three obligations that lived outside
        // the door: four producers of `worldMovedOn` called `expireOpenQuestion()` first and
        // `resolve(_:snoozeDuration:)` did not, so a correction aimed at the menu-bar glyph
        // destroyed a question on the panel and wrote nothing about it. It is inside the door now
        // and this is the reading that says which endings it fires for — an exit that quietly
        // joined or left the writing set is a diff in this line.
        // **The four things that can become of one thing the app said, and the one that costs**
        // (focus-sq7, R-81). `unopened` is the fourth: a nudge that reached the badge and waited
        // behind a click nobody made. It used to write no row at all, so a day on which the app
        // raised its top rung and nobody looked was indistinguishable from a day the ladder never
        // left the glyph — which is the signal that would have shown focus-2xw in the wild.
        report["dispositionsDeclared"] =
            InterventionDisposition.allCases.map(\.rawValue).sorted()
        report["dispositionsSpendingACap"] = InterventionDisposition.allCases
            .filter {
                InterventionEvent(kind: .accusation, subject: "", disposition: $0).spendsBudget
            }
            .map(\.rawValue)
            .sorted()

        report["questionExitsWritingAnExpiry"] = QuestionExit.allCases
            .filter(\.recordsAnExpiry)
            .map(\.rawValue)
            .sorted()

        // **Two readings of one fact, disagreeing** — always zero and always empty (focus-zrs).
        //
        // `orphanedNudgeSurfaces` above reads empty throughout the defect this round is about,
        // which is exactly why these exist: an invariant can only see the contradictions it was
        // built to look for. These three say whether the *active priority* is still one fact.
        //
        // There were four. `preemptionsNamingNoQuestion` — the interruption slot naming a question
        // the loop was not holding — went with the mechanism it watched (U-2). A counter of
        // preemptions that name nothing is not a weaker check once preemption is gone; it is a
        // check of nothing at all, and leaving it reporting a permanent zero would be the kind of
        // green that means nothing.
        //
        // * `commitmentDisagreements` is `PriorityHost` checking its own three statements of it.
        // * `mandatesWithoutACommitment` is the loop being told to speak with no key to write
        //   under — gate 1 and the key having parted company, which is defect A's signature.
        // * `staleNotificationActions` is a press on a banner belonging to a rung that is over,
        //   which is defect C's — and unlike the other two this one is *expected* to be
        //   reachable in the wild, because a person really can press a day-old notification. It is
        //   zero in an automated run because nothing here presses one.
        report["commitmentDisagreements"] = composition.priorityHost.commitmentDisagreements
        report["mandatesWithoutACommitment"] = host.mandatesWithoutACommitment
        report["staleNotificationActions"] = host.staleNotificationActions

        // Every rung, with nothing presenting and no call in progress — which is the state the
        // settings pane's matrix describes.
        //
        // **One table, and it used to be three** (focus-wy0). The two extra ones asked `route(…)`
        // what it would do at `denied` and at `notRequested`, so that the degraded path was
        // asserted whatever this Mac's own grant state happened to be. They were the right answer
        // to the question while the authorisation was an input. It stopped being one at U-2, and
        // the three tables then came back byte-identical in every gate run — the same reading,
        // printed three times under three headings, which reads like corroboration and is
        // repetition. `SurfaceRouter.route(…)` no longer accepts an authorisation at all, so
        // "denied, notRequested and authorised deliver alike" is now a fact about the function's
        // type and there is no cell left for a gate to compare.
        let routes: [[String: Any]] = LadderRung.Kind.allCases.map { rung in
            let route = SurfaceRouter.route(
                rung: rung,
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
        report["routes"] = routes
        report["everyRungHasASurface"] = routes.allSatisfy {
            !(($0["surface"] as? String) ?? "").isEmpty
        }
        report["everyRungIsInApp"] = routes.allSatisfy { ($0["isInApp"] as? Bool) == true }
        // **Every surface any rung can reach** (U-2). Since the recommitment rung was deferred to
        // focus-5ab there is no rung a notification can carry, and this is the reading that says
        // so from inside the running application rather than from a table a reader has to
        // interpret. It was computed across four authorisation states; one is now the whole of it.
        report["surfacesARungCanReach"] = Set(
            routes.compactMap { $0["surface"] as? String }.filter { !$0.isEmpty }
        ).sorted()
        // **Every accusation this app can raise lands somewhere it can be answered** (focus-uru).
        //
        // The table above is computed at `reducedInterruption: false` alone, which is precisely
        // where the defect hid: under macOS Reduce Motion — which the composition root forces
        // this flag on for — the panel rung went to the popover badge, and the popover drew a
        // read-only label. Every reading the gate had said "in-app" and none said "answerable",
        // so a rung nobody could answer was indistinguishable from one they could.
        //
        // Folded over the **whole** input space and reported as a list of the offending cells
        // rather than a bare `true`, so a red run says which rung under which conditions.
        //
        // **It had two exemptions, and between them the reading was a tautology** (focus-vxo).
        // It asked `voice.renderedRung(for: rung)` — the rung a deck *claimed* to draw rather
        // than the rung the ladder climbed to — so under `silentVisual` the top rung was
        // reported as ambient and skipped by the very guard that exists to find it. And it
        // pinned `media: .idle` and `presentation: .notPresenting`, the two conditions under
        // which nothing is demoted at all. `everyAccusationRouteCanBeAnswered = true` was
        // therefore true of a space chosen so that it could not be false, while the running loop
        // put a delivered accusation on the menu-bar glyph.
        //
        // So: the requested rung, every deck, both settings of the flag, both media states, both
        // menu-bar states, presenting and not. Same 160 cells `SurfaceRouterTests` folds over,
        // and the count is reported beside the verdict — a fold that quietly shrinks is the
        // shape both exemptions had, and a number is the only way a gate reading shows it.
        //
        // The fold itself is `accusationRouteAudit()` rather than a loop written out here, so the
        // unit lane runs **this** fold rather than a second one shaped like it. That is the other
        // half of the lesson: the binary's fold and the suite's fold agreed for as long as they
        // shared the exemption and nothing could have told anyone, because they were two copies.
        let audit = accusationRouteAudit()
        report["accusationRoutesWithNoWayToAnswer"] = audit.unanswerable
        report["everyAccusationRouteCanBeAnswered"] = audit.unanswerable.isEmpty
        report["accusationRouteCellsChecked"] = audit.cells
        // **The shape of a row the settings pane draws** (focus-wy0), read off the compiled type
        // with `Mirror` rather than written down here.
        //
        // A route reading cannot catch the defect coming back. If an authorisation were
        // reintroduced as a routing input, every cell would answer exactly what it answers now —
        // that was the whole difficulty: three identical tables under three headings, and a pane
        // rendering the repetition as a consequence. What *would* change is the row, because the
        // pane renders `SurfaceRouter.table(…)` itself. So the row's own field names are the
        // reading, and `notification-denied` asserts the set.
        report["routingRowFields"] = Mirror(
            reflecting: SurfaceRoutingRow(rung: .ambient, route: .surface(.menuBar))
        ).children.compactMap(\.label).sorted()

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

        // **What the status item says a nudge is doing, and how often it has actually said it**
        // (focus-mkk, focus-2xw).
        //
        // Counts of assignments to a real `NSStatusBarButton`, not predicates about a surface.
        // The bead was measured with exactly this reading and it came back `[1,1,1,1,1,1,1]` over
        // seven drifts and six delivered rows — the one write having happened at `install()`,
        // before the first rung existed. A predicate saying the glyph "reaches the person on
        // landing" could not have shown that, and asserting it is what produced the defect.
        //
        // `surfaceAttention` is the whole table rather than the live cell, because the live cell
        // in an automated run is `unmarked` and a reading that is constant is a reading a gate
        // cannot use.
        report["menuBarGlyphWrites"] = composition.menuBar.glyphWriteCount
        report["menuBarTitleWrites"] = composition.menuBar.titleWriteCount
        report["menuBarAnnouncements"] = composition.menuBar.announcementCount
        report["menuBarAttention"] = composition.menuBarPresentation().attention.rawValue
        report["surfaceAttention"] = NudgeSurface.allCases.map { surface in
            [
                "surface": surface.rawValue,
                "attention": surface.menuBarAttention.rawValue,
                "marksTheItem": surface.menuBarAttention.marksTheItem,
                "invitesAClick": surface.menuBarAttention.invitesAClick,
                "holdsTheInterruptionSlot": surface.holdsTheInterruptionSlot
            ]
        }
        // The join focus-mkk and focus-2xw share: a nudge that raises no window must be visible in
        // the menu bar, or it is visible nowhere at all.
        report["surfacesWithNoWindowAndNoMark"] = NudgeSurface.allCases
            .filter { !$0.holdsTheInterruptionSlot && !$0.menuBarAttention.marksTheItem }
            .map(\.rawValue)
            .sorted()

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
    /// **The subject seam, walked over inputs that can FAIL** (focus-2pd).
    ///
    /// ## What was wrong with the reading it joins
    ///
    /// `panelReport()` resolved a subject for `FocusStore.bundleIdentifier` — this process's own
    /// identifier — and reported the sentence. Its own comment said why that is green: the app is
    /// running by definition, so the workspace lookup either produces a name or the fix is not in
    /// the build. That is a fixed point wearing the clothes of ground truth, the same family as
    /// the `everyAccusationRouteCanBeAnswered` tautology. Every branch of `SubjectNaming` that
    /// can go wrong is unreachable from that one input.
    ///
    /// ## The five readings, and why each one can fail
    ///
    /// | reading | the input | what would break it |
    /// |---|---|---|
    /// | `running` | this process | nothing — kept as the control, and labelled as one |
    /// | `installedNotRunning` | a bundle on this disk that is **not** running | focus-7gc's second branch: `applicationURL(for:)` then `applicationName(at:)`. Before e623445 this fell straight through to the identifier |
    /// | `origin` | `https://docs.google.com` | an origin has no application to have a name; the host must be derived and no browser may be named |
    /// | `whitespace` | `"   "` | e04's mixed drift carries `""`; a subject that named nobody must go on naming nobody rather than acquiring a blank name |
    /// | `notInstalled` | an identifier nothing answers to | the last resort. It must be the identifier and never the empty string, because an empty sentence is a bug the person is asked to answer |
    ///
    /// The second is the interesting one and it is the one that **cannot be guaranteed on an
    /// arbitrary Mac**, so it is reported as `skipped` with a named reason rather than passing
    /// when no such bundle is found. A probe that quietly passes when it could not run is the
    /// defect this whole entry is about, one level up.
    @MainActor
    static func subjectNamingReport() -> [String: Any] {
        let workspace = SystemReturnWorkspace()
        let naming = SubjectNaming(workspace: workspace)
        var report: [String: Any] = [:]

        func reading(_ identifier: String?) -> [String: Any] {
            guard let subject = naming.subject(identifier) else {
                return ["namedNobody": true]
            }
            return [
                "namedNobody": false,
                "identifier": subject.identifier,
                "displayName": subject.displayName,
                // The claim the whole seam exists for: the sentence half is a NAME, not a second
                // copy of the storage key.
                "isANameNotTheKey": subject.displayName != subject.identifier
            ]
        }

        report["running"] = reading(FocusStore.bundleIdentifier)
        report["origin"] = reading("https://docs.google.com")
        report["whitespace"] = reading("   ")
        report["empty"] = reading("")
        report["nothing"] = reading(nil)
        report["notInstalled"] = reading("com.example.focus.sentinel.absent")

        // **Installed and not running** — found rather than assumed, from applications every Mac
        // ships. The probe confirms both halves before it believes the answer: the bundle is on
        // this disk, and nothing with that identifier is running right now. Launching one would
        // be the probe changing the world it is measuring, so it does not.
        let candidates = [
            "com.apple.Chess", "com.apple.Stickies", "com.apple.Dictionary",
            "com.apple.Grapher", "com.apple.ScriptEditor2", "com.apple.TextEdit",
            "com.apple.Calculator", "com.apple.Preview", "com.apple.Console"
        ]
        let anchor = candidates.first { identifier in
            workspace.applicationURL(for: identifier) != nil
                && workspace.localizedNameOfRunningApplication(identifier) == nil
        }
        if let anchor {
            var found = reading(anchor)
            found["skipped"] = false
            found["anchor"] = anchor
            // The same seam `ReturnToTask` uses, asked the same question — so a divergence
            // between the sentence and the "Back to …" button shows up as two readings that
            // disagree rather than as a panel nobody photographed.
            found["returnTargetName"] = ReturnToTask
                .target(anchor: anchor, workspace: workspace)?.displayName ?? ""
            report["installedNotRunning"] = found
        } else {
            report["installedNotRunning"] = [
                "skipped": true,
                "reason": "no candidate application is installed on this Mac and not running",
                "candidates": candidates
            ]
        }
        return report
    }

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
        //
        // **And the subject is NAMED, through the shipping seam** (focus-ebv).
        //
        // The panel a person meets said *"Is com.figma.Desktop part of …?"* for the whole of e05
        // and this probe could not have noticed: it drew a panel and measured its window. The
        // subject here is resolved by `SubjectNaming` against the real `SystemReturnWorkspace`.
        //
        // **The identifier below is this process's own, and on its own that proved nothing**
        // (focus-2pd). It is running by definition, so the running branch of `SubjectNaming` is
        // the one input where a name is guaranteed available — a fixed point, green whatever the
        // rest of the seam does. It is kept, because the sentence the panel draws has to come
        // from somewhere and this is the one subject the probe can be certain of; what it is no
        // longer is the *whole* proof. `subjectNamingReport()` below walks the inputs that can
        // fail.
        let naming = SubjectNaming(workspace: SystemReturnWorkspace())
        report["subjectNaming"] = subjectNamingReport()
        guard let subject = naming.subject(FocusStore.bundleIdentifier) else {
            // Unreachable — the identifier is a non-empty constant — and **reported** rather
            // than forced. A probe that trapped here would take the whole self-check with it,
            // and the gate reads an absent key as a failure anyway (`.get(…) is True`).
            report["subjectResolved"] = false
            return report
        }
        report["subjectResolved"] = true
        report["subjectIdentifier"] = subject.identifier
        report["subjectDisplayName"] = subject.displayName

        let presentation = QueryPresentation(
            task: "Write the Q3 proposal for Acme",
            subject: subject,
            reason: .noNegativeBasis,
            dwelled: .seconds(62)
        )
        // The sentence itself, exactly as the panel draws it and VoiceOver speaks it — so the
        // assertion is about what a person meets rather than about a field beside it.
        report["subjectSentence"] = presentation.announcement()

        // **The probe draws in the appearance it is probing** (focus-7wy).
        //
        // This line was `panel.update(QueryPanelView(presentation:))` with no `traits:`, so it
        // took the parameter's default — `AppearanceTraits.systemDefault`, which is *light* with
        // every accessibility setting off. focus-pq8 fixed the panel, which really had been
        // drawing in the default appearance whatever the Mac was set to; and the instrument that
        // was supposed to be able to see that regression came back was built light-pinned, so it
        // would have reported a healthy panel on a dark Mac drawing white on white. That is the
        // white-on-white lesson one layer up: the baseline was not blank this time, the *probe*
        // was.
        //
        // **And it is driven to DARK first, or the reading proves nothing** (focus-7wy).
        //
        // `AppearanceTraits.systemDefault` is light with every accessibility setting off, which
        // is exactly what an untouched Mac reports — so on a light Mac a panel that honours the
        // injection and one that ignores it draw the *same* traits, and no observation can tell
        // them apart. `shellReport()` already learned this and drives the preference before it
        // reads its windows; the nudge surfaces were left out of that lesson.
        //
        // The observer is moved directly rather than through `applyAppearancePreference`, so
        // nothing is written to the person's store, and `appearanceChanged(_:)` is the shipping
        // wire — the same call the real appearance notification makes, which is what carries
        // traits into this panel and the menu bar. Put back below.
        let originalPreference = composition.appearance.preference
        composition.appearance.preference = .dark
        let liveTraits = composition.appearance.traits
        composition.appearanceChanged(liveTraits)
        panel.update(QueryPanelView(presentation: presentation), traits: liveTraits)

        // **Reported so the gate can fail when the traits are ABSENT, rather than defaulting.**
        //
        // `traits:` has a default argument, which is exactly how the probe lost them without
        // anybody noticing — the call still compiled and the panel still drew. So the report
        // carries what the panel actually applied, what the app believes the Mac is set to, and
        // whether the two differ from the default at all; `self-check.sh` fails on any of the
        // three being wrong or missing. A probe that silently falls back to a light default is a
        // probe that cannot fail.
        report["appearanceTraits"] = panel.appliedTraits.renderedDescription
        report["liveAppearanceTraits"] = liveTraits.renderedDescription
        report["panelDrewTheLiveAppearance"] = panel.appliedTraits == liveTraits
        report["defaultAppearanceTraits"] = AppearanceTraits.systemDefault.renderedDescription
        // Non-vacuity, asserted by the gate: if the driven traits ever equalled the default, the
        // line above would pass for a panel that ignores the injection entirely.
        report["drivenTraitsDifferFromTheDefault"] = liveTraits != .systemDefault
        report["panelIsDark"] = panel.appliedTraits.colorScheme == .dark

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
        // `null`, never `""`, for the reason `FocusReadings.dictionary` gives: an empty string
        // is a value, and reading 1 not having been taken is not a value.
        report["frontmostBeforeShow"] = before.frontmostBundleIdentifier.map { $0 as Any } ?? NSNull()
        report["frontmostAfterShow"] = after.frontmostBundleIdentifier.map { $0 as Any } ?? NSNull()
        report["frontmostWasReadBothTimes"] = before.frontmostWasRead && after.frontmostWasRead
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

        // **The appearance is put back**, through the same wire that moved it, so this stage
        // leaves the surfaces as it found them. The panel is already hidden; the menu bar is not,
        // and it took the driven traits too.
        composition.appearance.preference = originalPreference
        composition.appearanceChanged(composition.appearance.traits)
        report["appearanceRestored"] = composition.appearance.preference == originalPreference

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
        //
        // **The count is a reading, and a reading that could not be taken is NOT TAKEN**
        // (focus-2vi). It used to be written as `?? -1`, and that single character is how a
        // missing reading became a numeric answer: the gate compared `-1 > 0`, said "the
        // grant-free window list returned rows: got -1", and named neither of the two entirely
        // different things that produce it. So the value is `null` when it was not taken,
        // `countWasTaken` says so as its own fact, and `countNotTakenBecause` names which of the
        // two reasons it was — a deliberate stand-down, or this graph knowing nothing about the
        // screen at all. No sentinel of any kind may go back into this dictionary.
        let windowCount = host.currentWindowCount()
        var windowMetadata: [String: Any] = [
            "decodedKeys": host.windowDecodedKeys,
            "decodedKeysAreTitleFree": host.windowDecodedKeysAreTitleFree,
            "countWasTaken": windowCount != nil,
            "count": windowCount.map { $0 as Any } ?? NSNull()
        ]
        if let obstacle = host.frontmostReadingObstacle {
            windowMetadata["countNotTakenBecause"] = obstacle.rawValue
        }
        report["windowMetadata"] = windowMetadata

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
            // `suppressed: true` alone said "the gate stood down" about a graph that in the
            // measured failure had simply never been told who was frontmost — the same
            // conflation `-1` made above, in words instead of a number. The reason travels with
            // it now, and a reader can tell the gate working from the graph knowing nothing.
            report["presentation"] = [
                "suppressed": true,
                "notTakenBecause": host.frontmostReadingObstacle?.rawValue ?? ""
            ]
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

        // **The cockpit's content is somewhere a person can scroll** (focus-2er).
        //
        // The `ScrollView` is the *scene's* rather than the view's, deliberately: a `ScrollView`
        // reports no intrinsic height, so a view inside one rasterises as a blank rectangle under
        // `ImageRenderer` and every committed cockpit baseline would become a picture of nothing.
        // That puts it in `App/`, where dropping it left a window whose last lines are
        // unreachable at the default text size and the whole gate green. AppKit backs a SwiftUI
        // `ScrollView` with a real `NSScrollView`, and this process may read its own view
        // hierarchy at no grant at all.
        report["cockpitContentScrolls"] = liveCockpitWindow()
            .flatMap(\.contentView)
            .map(containsScrollView) ?? false

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

        // **What the cockpit drew while the handoff was up** (focus-h7h).
        //
        // The three lines above read the *store's* answer, and a window showing a frozen
        // placeholder passes all three: the handoff really did reach `CockpitState`, and the
        // window really did draw something else. This is the difference, and the handoff is the
        // right moment to take it — it puts a sentence into the live state that no placeholder
        // could be carrying, because no person would ever type it.
        //
        // A turn of the run loop first: SwiftUI redraws on the next one, so a reading taken here
        // without it describes the window as it was before the URL arrived.
        settle(forSeconds: renderSettleSeconds)
        let withHandoff = composition.shellRenderReading(of: .cockpit)
        report["cockpitRenderingWithHandoff"] = withHandoff.dictionary
        report["cockpitDrewnHandoffTask"] =
            composition.shellRenderings[.cockpit]?[.handoffTask] ?? ""
        report["cockpitDrewTheHandoff"] = withHandoff.drewWhatTheAppKnows
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

    /// How long to let the run loop turn after driving something the windows must redraw from.
    ///
    /// A SwiftUI window redraws on the next turn, and the report is written from this one — so a
    /// reading taken without this line describes the moment *before* the drive. Measured here, in
    /// the built app: with no turn at all the three windows report the traits they were drawn
    /// with before the appearance was moved, which reads as a defect in every one of them.
    static let renderSettleSeconds: TimeInterval = 0.6

    // MARK: - What the windows drew, beside what they were handed (focus-h7h)

    /// **The reading this whole task exists to make possible.**
    ///
    /// Every wire in `App/` says its own name when it fires, and that was measured to be worth
    /// nothing on its own: an eight-part mutation that kept every receipt firing and replaced
    /// every value with a constant passed the whole nineteen-stage gate, 262 ok-assertions
    /// against 262, with an empty diff between the clean run's assertion list and the mutant's.
    /// A receipt that fires when a closure runs cannot distinguish a closure that produced the
    /// right value from one that produced a constant.
    ///
    /// So this asks the three windows what they put on the screen and holds it up beside what the
    /// composition root handed them. Two of the eight mutations cannot be reached that way at all,
    /// because what they break is not a value but a **click** — the Appearance picker's writer and
    /// the Intervention pane's action sink — and no lane in this programme holds the Accessibility
    /// grant it would take to press one. Those are driven instead: the window hands back the
    /// closures its controls are actually holding, this calls them, and the composition root's own
    /// graph is watched for the change. Everything is put back.
    ///
    /// Every reading is grant-free and in-process: a SwiftUI preference, three property reads and
    /// four function calls on objects this process already owns.
    @MainActor
    static func shellRenderingReport() -> [String: Any] {
        let composition = AppComposition.shared
        var report: [String: Any] = [:]

        // **Every Settings pane is put in front, in turn** (focus-7ow).
        //
        // A macOS `TabView` builds only the selected pane. Measured on the first run of this
        // mechanism: the Privacy pane's own receipts never arrived, because nobody had clicked
        // Privacy — so every Settings value had to be reported from the *window*, out of the
        // argument it was about to pass in, and a defect **inside** an unselected pane was
        // invisible to every lane in the programme. The selection is the composition root's now,
        // so this walks all three and each pane reports what it drew. They accumulate against one
        // issue of the connection, which is what `generation` establishes.
        report["settingsPanesWalked"] = walkSettingsPanes()

        report["driveSetPreference"] = driveAppearanceSink()
        report["driveInterventionSink"] = driveInterventionSink()

        // **The appearance is moved, and that is what makes the traits reading mean anything.**
        //
        // `AppearanceTraits.systemDefault` is a light appearance with every accessibility setting
        // off — which is exactly what an untouched Mac reports. So on a light Mac a window that
        // ignores the injection and one that honours it draw the *same* traits, and no
        // observation whatsoever can tell them apart. Driving the preference to `.dark` makes the
        // live traits differ from the default whatever this Mac is set to, which is the condition
        // under which the reading is a claim rather than a coincidence.
        //
        // The observer is moved directly rather than through `applyAppearancePreference`, so
        // nothing is written to the person's store: this changes what the windows are drawn with
        // for two-thirds of a second and puts it back.
        let originalPreference = composition.appearance.preference
        composition.appearance.preference = .dark
        settle(forSeconds: renderSettleSeconds)

        report["drivenAppearancePreference"] = AppearancePreference.dark.rawValue
        report["drivenTraits"] = composition.appearance.traits.renderedDescription
        report["defaultTraits"] = AppearanceTraits.systemDefault.renderedDescription
        // Non-vacuity, asserted by the gate: if the driven traits ever equalled the default, the
        // three traits assertions below would pass for a shell that ignores the injection.
        report["drivenTraitsDifferFromTheDefault"] =
            composition.appearance.traits != .systemDefault

        // **The quick-capture panel followed the live change, or it did not** (focus-h7h).
        //
        // `capturePanelTraitsAdopted` was a sentinel — "somebody told the panel something" — and
        // a scene that told it `AppearanceTraits.systemDefault` satisfied it exactly as well as
        // one that told it the truth. This is the value.
        report["capturePanelTraits"] =
            composition.quickCapturePanel.adoptedTraits?.renderedDescription ?? ""
        report["capturePanelFollowedTheLiveTheme"] =
            composition.quickCapturePanel.adoptedTraits == composition.appearance.traits

        var readings: [String: Any] = [:]
        var drewWhatTheAppKnows: [String] = []
        for surface in ShellThemedSurface.allCases {
            let reading = composition.shellRenderReading(of: surface)
            readings[surface.rawValue] = reading.dictionary
            if reading.drewWhatTheAppKnows { drewWhatTheAppKnows.append(surface.rawValue) }
        }
        report["readings"] = readings
        report["surfacesThatDrewWhatTheAppKnows"] = drewWhatTheAppKnows.sorted()

        // **The prior question, answered here so the gate can fail on it by name** (focus-7ow).
        //
        // The readings above answer "did the window draw what it was handed", and they can only
        // answer it about fields somebody thought to list. This is the audit that says there is
        // no field of either connection which **no receipt covers at all** — walked with `Mirror`
        // over the compiled type, so it cannot be written to a known failure.
        var totalities: [String: Any] = [:]
        var totalSurfaces: [String] = []
        for surface in [ShellThemedSurface.cockpit, .settings] {
            let reading = composition.shellTotalityReading(of: surface)
            totalities[surface.rawValue] = reading.dictionary
            if reading.isTotal { totalSurfaces.append(surface.rawValue) }
        }
        report["totalities"] = totalities
        report["connectionsThatAreTotal"] = totalSurfaces.sorted()
        report["surfacesDeclared"] = ShellThemedSurface.allCases.map(\.rawValue).sorted()
        // **Every fact the shell holds in two places at once, and whether they agree**
        // (focus-zrs). The totality readings above answer a question about *fields*; this answers
        // the one this round is about — whether two live values that describe one thing have
        // parted company. See `AppComposition.projectionDisagreements`.
        report["projectionDisagreements"] = composition.projectionDisagreements
        // The values themselves, so a failing gate line can be read without re-running anything.
        report["rendered"] = Dictionary(
            uniqueKeysWithValues: ShellThemedSurface.allCases.map { surface in
                (surface.rawValue, (composition.shellRenderings[surface] ?? .nothing).dictionary)
            }
        )

        composition.appearance.preference = originalPreference
        settle(forSeconds: renderSettleSeconds)
        report["appearancePreferenceRestored"] =
            composition.appearance.preference == originalPreference

        return report
    }

    /// **Press the Appearance picker without a grant** (focus-h7h, focus-cp2 M4).
    ///
    /// Deleting the store write from the picker's binding survived two gates: the person's choice
    /// was forgotten the moment they quit, and nothing anywhere noticed. It cannot be reached by a
    /// value — what broke is what happens on a *click* — and it cannot be clicked, because this
    /// programme's lanes hold no Accessibility grant. So the window hands back the closure its
    /// picker writes through, this calls it, and both halves of the effect are read: the observer
    /// the shell re-renders from, and the row on disk.
    ///
    /// Reversible by construction. Whatever was stored is read first and written back through the
    /// composition root's own verb, so a self-check leaves the person's appearance exactly as it
    /// found it — and `restored` says so rather than leaving it to be assumed.
    @MainActor
    static func driveAppearanceSink() -> [String: Any] {
        let composition = AppComposition.shared
        var report: [String: Any] = [:]

        guard let sinks = composition.settingsSinks else {
            // Not a silent skip. The Settings window is opened by the ⌘, probe, so no sinks means
            // the window never drew — which is a failure of a different wire, and the gate has to
            // be able to say which.
            report["available"] = false
            return report
        }
        report["available"] = true

        let storedBefore = composition.storedAppearancePreference()
        let observedBefore = composition.appearance.preference
        // Anything the picker is not already showing. Two candidates so the probe is never a
        // no-op: writing the value that is already there would prove nothing about the writer.
        let probe: AppearancePreference = storedBefore == .dark ? .light : .dark

        sinks.setPreference(probe)

        report["probe"] = probe.rawValue
        report["storedBefore"] = storedBefore.rawValue
        report["observerAfter"] = composition.appearance.preference.rawValue
        report["storedAfter"] = composition.storedAppearancePreference().rawValue
        // Both halves, because they are two different defects. A picker that updates the observer
        // and never writes is the mutation that survived; one that writes and never updates the
        // observer would leave the shell drawing the old appearance until relaunch.
        report["reachedTheObserver"] = composition.appearance.preference == probe
        report["reachedTheStore"] = composition.storedAppearancePreference() == probe

        composition.applyAppearancePreference(storedBefore)
        composition.appearance.preference = observedBefore
        report["restored"] = composition.storedAppearancePreference() == storedBefore
        return report
    }

    /// **Put every Settings pane in front, in turn, and let each report what it drew**
    /// (focus-7ow).
    ///
    /// The structural residue round 5 named, closed. A macOS `TabView` builds only the selected
    /// pane, so reporting from inside a pane was measured to produce nothing at all for the two
    /// panes nobody had clicked — which is why every Settings value used to be reported from the
    /// *window*, out of the argument it was about to hand over. That bought coverage of the
    /// arguments at the price of the panes: a mutation **inside** the Privacy pane, printing `/`
    /// as the place the person's data lives, was reported as the truth by a window stamping its
    /// own `storeURL`.
    ///
    /// The selection is the composition root's now. This drives it through the same verb a click
    /// takes, gives the run loop a turn so the pane is actually built, and puts it back. The
    /// reports accumulate against one issue of the connection, so the reading at the end holds
    /// what all three panes said.
    ///
    /// Grant-free: one property write per tab and a run-loop turn.
    @MainActor
    static func walkSettingsPanes() -> [String: Any] {
        let composition = AppComposition.shared
        let before = composition.settingsTab
        var visited: [String] = []

        for tab in SettingsTab.allCases {
            composition.selectSettingsTab(tab)
            settle(forSeconds: renderSettleSeconds)
            visited.append(tab.rawValue)
        }

        composition.selectSettingsTab(before)
        settle(forSeconds: renderSettleSeconds)

        return [
            "declared": SettingsTab.allCases.map(\.rawValue).sorted(),
            "visited": visited,
            "restored": composition.settingsTab == before,
            // What each pane reported, keyed by the tab that was in front when it arrived. Read
            // as evidence rather than asserted: the assertion is that the accumulated reading is
            // complete, and this is what a person reads when it is not.
            "reportedAfterTheWalk":
                (composition.shellRenderings[.settings] ?? .nothing).values.keys.sorted()
        ]
    }

    /// **Press the Intervention pane's controls without a grant** (focus-h7h, focus-cp2 M3).
    ///
    /// `onInterventionAction` gutted to `{ _ in }` is, under U-1, the wire that decides whether
    /// the app may speak at all — and it survived two gates for the same reason the one above
    /// did. Both of the pane's controls are driven, because they write different fields and a
    /// sink that carried one and dropped the other would be a real defect.
    ///
    /// Nothing here touches the store: `NudgePreferences` lives in the running loop, so the whole
    /// probe is a pair of in-memory writes and their read-back, put back through the composition
    /// root's own verb rather than through the sink under test.
    @MainActor
    static func driveInterventionSink() -> [String: Any] {
        let composition = AppComposition.shared
        var report: [String: Any] = [:]

        guard let sinks = composition.settingsSinks else {
            report["available"] = false
            return report
        }
        report["available"] = true

        let voiceBefore = composition.nudgeHost.preferences.voice
        let reducedBefore = composition.nudgeHost.preferences.reducedInterruption
        let voiceProbe: NudgeVoice = voiceBefore == .standard ? .silentVisual : .standard
        let reducedProbe = !reducedBefore

        sinks.onInterventionAction(.setVoice(voiceProbe))
        report["voiceProbe"] = voiceProbe.rawValue
        report["voiceAfter"] = composition.nudgeHost.preferences.voice.rawValue
        report["voiceReachedTheLoop"] = composition.nudgeHost.preferences.voice == voiceProbe

        sinks.onInterventionAction(.setReducedInterruption(reducedProbe))
        report["reducedProbe"] = reducedProbe
        report["reducedAfter"] = composition.nudgeHost.preferences.reducedInterruption
        report["reducedReachedTheLoop"] =
            composition.nudgeHost.preferences.reducedInterruption == reducedProbe

        composition.perform(.setVoice(voiceBefore))
        composition.perform(.setReducedInterruption(reducedBefore))
        report["restored"] = composition.nudgeHost.preferences.voice == voiceBefore
            && composition.nudgeHost.preferences.reducedInterruption == reducedBefore
        return report
    }

    /// Whether an `NSScrollView` is anywhere beneath this view.
    ///
    /// A read of this process's own view hierarchy, which needs no permission of any kind — it is
    /// the same kind of reading `NudgePanelController` takes of its own panel.
    @MainActor
    static func containsScrollView(_ view: NSView) -> Bool {
        if view is NSScrollView { return true }
        return view.subviews.contains(where: containsScrollView)
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
    static func claims(characters: String, modifiers: NSEvent.ModifierFlags) -> Bool {
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

        // **A commitment as well as a session** (focus-h7h).
        //
        // The cockpit draws its session controls only where there is a priority — a session is
        // always about one, and offering to time nothing would be a control with nothing behind
        // it. So a store seeded with a session and no priority produces a window that draws no
        // elapsed figure at all, which is exactly the state the figure cannot be observed in.
        // Harmless to the two-launch reconciliation proof, which reads the session row and has
        // never had an opinion about what was committed to.
        let priorities = PriorityStore(context: context)
        let taskID = try priorities.createTask(intent: seededPriorityIntent)
        try priorities.activate(taskID: taskID, undo: nil)

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
            "priorityIntent": seededPriorityIntent,
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

    /// **Take AppKit's alert out of the Help menu, once there is a Help menu** (focus-h7h).
    ///
    /// Here rather than in `applicationDidFinishLaunching`, and the difference is not stylistic.
    /// SwiftUI installs `NSApp.mainMenu` *after* that notification, and reading the property
    /// before it does forces AppKit to build a default menu bar which SwiftUI then leaves alone:
    /// measured here, in the running app, the File menu disappeared outright and ⌘N, ⌘O, ⌘W and
    /// ⌘? were all unclaimed. Becoming active is the first moment the menu bar is the one the
    /// person will actually use, and it is also the moment AppKit installs its automatic item —
    /// so this is both late enough to be safe and early enough to be in time.
    ///
    /// It runs in the ordinary app as well as under `--focus-self-check`, because the defect is
    /// the person's: two identically titled *"Focus Sentinel Help"* items, and the first one
    /// opens an alert saying help is not available.
    public func applicationDidBecomeActive(_ notification: Notification) {
        ShellHelpMenu.detachAutomaticItem()
    }

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

        // **The cockpit block alone, against whatever store `--focus-store` named** (focus-h7h).
        //
        // It comes forward, unlike the other reduced modes, because a window that is not on
        // screen has not drawn — and what this block reports is what the window drew.
        if SelfCheck.wantsCockpitOnly {
            SelfCheck.comeForward { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + SelfCheck.settleDelay) {
                    MainActor.assumeIsolated {
                        SelfCheck.runModeAndTerminate(writingTo: path) {
                            SelfCheck.cockpitRenderingReport()
                        }
                    }
                }
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
