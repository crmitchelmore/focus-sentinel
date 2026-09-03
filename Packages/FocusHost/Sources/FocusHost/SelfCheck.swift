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

    /// How long a probe that **needs the front** may spend getting it back before it declares
    /// its reading NOT TAKEN (focus-jax).
    ///
    /// `comeForward` establishes the front once, at launch, and `activation` records that it
    /// worked. What nothing recovered from is the front being lost *afterwards*: another
    /// application coming forward part-way through a report that takes a second and a half of
    /// run loop is an ordinary event on a Mac, and it left `undoReport` reading a menu bar
    /// nobody had validated. Measured on this machine, activation lands on the second poll —
    /// three seconds is sixty of them, and a probe that still cannot get the front after that
    /// is in a world it cannot take its reading in, which is a different sentence from "the
    /// Edit menu is broken".
    static let frontRecoveryDeadline: TimeInterval = 3.0

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

    /// **The windows the seeded store says were open when its app last quit** (focus-odz.6).
    ///
    /// Both scenes, and each does a different job. The cockpit is the **control**: SwiftUI opens
    /// it itself, so a launch that restored nothing would still have one, and a proof resting on
    /// the cockpit alone would be green against a restoration that never ran. The Keyboard
    /// Shortcuts window is the **claim**: nothing in a `--focus-self-check-cockpit` launch opens
    /// it, so it is on the screen only if the record was read and acted on.
    static let seededOpenWindows = [ShellWindow.cockpit.id, ShellWindow.help.id]

    /// The commitment the seeded store carries.
    ///
    /// A sentence no person would type, for the reason the handoff probe's is: it has to be a
    /// value a frozen placeholder could not be carrying by coincidence.
    static let seededPriorityIntent = "Self-check seeded commitment"

    /// **The appearance the seeded store remembers** (focus-8ry).
    ///
    /// `.light` rather than `.dark` or `.matchSystem`, and the choice is load-bearing twice
    /// over. It is not the type's default, so a launch that never read the store answers
    /// `matchSystem` and the reading separates the two programs on **any** Mac — where a probe
    /// that seeded `matchSystem` would agree with the defect by construction. And it resolves to
    /// one colour scheme whatever the Mac is set to, so `appearanceColorScheme` is a fixed string
    /// this lane can assert rather than a value that depends on the developer's System Settings.
    static let seededAppearancePreference = AppearancePreference.light

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
            // **The setting that has to survive a relaunch, read on the launch after the one
            // that wrote it** (focus-8ry).
            //
            // This is the lane that can see it, and the reason is the same one that put the
            // elapsed figure here: the ordinary self-check opens the *person's* store, whose
            // appearance is whatever they last chose — usually `matchSystem`, which the defect
            // answers correctly by accident. The seeding launch above wrote `light`, so on this
            // launch `matchSystem` is the defect's signature and nothing else's, on every Mac.
            //
            // Three readings and not one, because they fail differently: the preference is what
            // the shell believes, the stored value is what the person chose, and the colour
            // scheme is what the windows are actually drawn in. A wire that read the store and
            // then failed to resolve the traits from it would pass the first two.
            "appearancePreference": composition.appearance.preference.rawValue,
            "storedAppearancePreference": composition.storedAppearancePreference().rawValue,
            "appearanceColorScheme": composition.appearance.traits.colorScheme.rawValue,
            "seededAppearancePreference": seededAppearancePreference.rawValue,
            "windowTitles": NSApp.windows.filter(\.isVisible).map(\.title).sorted(),
            // **What the last quit recorded, and what this launch put back** (focus-odz.6).
            //
            // Three facts because they fail differently: the record is what the store said, the
            // restored list is what this launch actually got a route to, and the visible scene
            // ids are what is really on the screen. A restoration that read the record and asked
            // for nothing passes the first; one that asked and was refused — no scene graph, no
            // opener — passes the first two and not the third.
            "restorationRecord": composition.restorationRecord ?? [],
            "restoredWindows": composition.restoredWindows,
            "hasRestoredWindows": composition.hasRestoredWindows,
            "canOpenWindows": FocusCommandCenter.shared.canOpenWindows,
            "visibleSceneIdentifiers": FocusAppDelegate.visibleSceneIdentifiers().sorted()
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
                // Submitted to the main queue on the line above; the isolation is a fact of
                // this call rather than an assumption about a framework.
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

    /// **Get the front back for a reading that needs it, and say whether it worked** (focus-jax).
    ///
    /// `comeForward` runs once, at launch, and `activation` records what it achieved. This is the
    /// same request re-issued at the moment of a reading that depends on it, because the front is
    /// not a property of the code — it is a property of the machine, and any other application
    /// coming forward takes it away. Returns whether the process is, right now, in the state
    /// AppKit needs to validate a menu item; the caller reports that rather than assuming it.
    @MainActor
    static func regainFront(within seconds: TimeInterval = frontRecoveryDeadline) -> Bool {
        let started = ProcessInfo.processInfo.systemUptime
        while true {
            if editMenuObstacle().isEmpty { return true }
            if ProcessInfo.processInfo.systemUptime - started >= seconds { return false }
            NSApp.activate(ignoringOtherApps: true)
            liveCockpitWindow()?.makeKeyAndOrderFront(nil)
            settle(forSeconds: activationPollInterval)
        }
    }

    /// What stands between this process and a menu reading AppKit would validate — empty when
    /// nothing does.
    ///
    /// One sentence per obstacle, in the order they are reached, so a NOT TAKEN reading names
    /// which of the three it hit instead of leaving a reader to infer it from a false boolean.
    @MainActor
    static func editMenuObstacle() -> String {
        if !NSApp.isActive { return "the application was not frontmost" }
        guard let key = NSApp.keyWindow else { return "the application had no key window" }
        if let cockpit = liveCockpitWindow(), key !== cockpit {
            return "the key window was not the cockpit"
        }
        return ""
    }

    // MARK: - Report

    @MainActor
    static func report(activation: Activation) -> [String: Any] {
        // Order matters. The window survey must happen *before* the key-equivalent probes,
        // because performing ⌘W closes a window and ⌘, opens one — the probes change the
        // very state the survey is describing.
        let menu = menuTree()
        // **Read in the same breath as the menu, and for the same reason the menu is read first**
        // (focus-6uf). The gate asserts each item's `isEnabled` against the answer this predicate
        // gives for the state the app is actually in, so the two have to describe one moment: the
        // key-equivalent probes below close a window and open another, and an availability read
        // taken after them would be a reading of a different app.
        let commands = commandAvailabilityReport()
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
        root["commands"] = commands
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
        // **The vocabulary the states are drawn from, published so it can be PINNED** (focus-gtr).
        //
        // The gate used to assert that each of the twelve states was "one of the five declared
        // states" — a set spelled out in the script and identical to `CapabilityState`'s entire
        // codomain. Every value the type can hold satisfies it, so nothing the app could do turned
        // it red; and it could not see the edit that matters, which is a **case joining or leaving
        // the enum**. That is the same shape focus-652 deleted from the notification reading, still
        // standing twelve rows wide. So the vocabulary itself is the reading, pinned against a
        // committed literal in both directions, and the value is checked against the *rule* that
        // produced it rather than against the set of things it could be.
        root["capabilityStatesDeclared"] = CapabilityState.allCases.map(\.rawValue)
        // The whole scan, including the two facts that say whether it was taken at all and
        // whether it could see this very process's own window. The two flat keys below are kept
        // because the evidence set and the epic's validation section name them.
        root["authorisationSurfaceScan"] = surfaces
        root["authorisationSurfaces"] = surfaces["suspects"] ?? []
        root["onScreenWindowOwners"] = surfaces["owners"] ?? []
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

        root["retention"] = retentionReport()

        // --- e05 -------------------------------------------------------------------------
        let nudge = nudgeReport()
        root["nudge"] = nudge
        // Lifted for the same reason the two above are: these are the values the gate compares
        // against committed literals, and one of them — `requestAuthorizationCallCount` — is
        // the number that discharges standing condition 5 for this epic.
        root["interventionDigest"] = nudge["interventionDigest"] ?? ""
        root["notificationAuthorisation"] = nudge["notificationAuthorisation"] ?? "unread"
        root["notificationAuthorisationReads"] = nudge["notificationAuthorisationReads"] ?? -1
        // **The half the Release lane could not see** (focus-652's sibling). Four of the five keys
        // focus-652 published were lifted here and `…WasRead` was not, so `self-check.sh` — which
        // is the ONLY stage that reads the notification boundary on the **Release** product, since
        // `notification-denied` and `focus-steal` both run against Debug — could assert that a
        // read had *landed* but not that the report had **waited** for it. Those are the two
        // halves of one repair: `Reads >= 1` is satisfied by a completion that arrived while the
        // report was already being assembled, which is the race focus-652 measured four times.
        // A key lifted for one lane and withheld from the other is this programme's commonest
        // defect wearing a dictionary key.
        root["notificationAuthorisationWasRead"] =
            nudge["notificationAuthorisationWasRead"] ?? false
        root["notificationAuthorisationDecodeTable"] =
            nudge["notificationAuthorisationDecodeTable"] ?? ""
        root["notificationAuthorisationDecodeCells"] =
            nudge["notificationAuthorisationDecodeCells"] ?? -1
        root["requestAuthorizationCallCount"] = nudge["requestAuthorizationCallCount"] ?? -1
        root["ladderRungsDeclared"] = nudge["ladderRungsDeclared"] ?? -1
        // The status item's secondary menu, built by the shipping controller (focus-odz.2).
        // Reading it changes nothing: it constructs an `NSMenu` and never shows one.
        root["statusItemMenu"] = statusItemMenuReport()
        // **Last of everything, because it shuts the cockpit and asks for it back**
        // (focus-odz.1). Every reading above describes a window this probe then closes, so it
        // cannot run anywhere else in this function without describing a different app.
        // **What this build calls itself** (focus-odz.3), read straight from the bundle rather
        // than through the Settings connection, so the pin below compares two readings of one
        // artefact rather than one reading of itself.
        root["bundleVersion"] = AppVersion.rendered(bundle: .main)
        root["bundleShortVersionString"] =
            Bundle.main.object(forInfoDictionaryKey: AppVersion.shortVersionKey) as? String ?? ""
        root["bundleBuild"] =
            Bundle.main.object(forInfoDictionaryKey: AppVersion.buildKey) as? String ?? ""
        // **What the About panel is really handed** (focus-odz.3), taken from the option
        // dictionary `AboutPanel.present()` passes rather than from the catalog a second time.
        // The unit lane cannot read this: under `swift test` SwiftPM copies String Catalogs
        // instead of compiling them, so `ShellStrings.string(_:)` answers the key back there and
        // "the credits resolved" is unassertable.
        //
        // What no lane can observe is the SwiftUI `Button` body in `ShellCommands` that calls
        // `present()`: it is a closure in a `Commands` result builder, which is the same
        // unreachable shape `App/` is, and it has no receipt. Stated here rather than implied.
        root["aboutCredits"] = (AboutPanel.options()[.credits] as? NSAttributedString)?.string ?? ""
        root["reopen"] = reopenReport()
        return root
    }

    /// **The status item's secondary menu, as the shipping controller builds it** (focus-odz.2).
    ///
    /// Three facts, and each answers something the others cannot.
    ///
    /// * The **table** — the four items and their titles in both watching states — is the
    ///   vocabulary, resolved against the app's own compiled catalog. The unit lane cannot read
    ///   these: under `swift test` SwiftPM copies String Catalogs rather than compiling them, so
    ///   `ShellStrings.string(_:)` answers the key back. So the sentences a person reads are
    ///   pinned here or nowhere.
    /// * The **drawn menu** is what a right-click would put on the screen — every item's target,
    ///   action and enabled state, from `secondaryMenu()` itself rather than from a second
    ///   rendering of the table. An item with no target performs nothing.
    /// * The **Settings item** the menu's third entry performs, found in this process's own menu
    ///   bar by the key equivalent the system owns. It is *found* and not performed: performing it
    ///   would open a window in the middle of a report about windows.
    ///
    /// Building a menu shows nothing and mutates nothing, so this is safe to read anywhere.
    @MainActor
    static func statusItemMenuReport() -> [String: Any] {
        var report: [String: Any] = [:]
        report["items"] = StatusItemMenuItem.allCases.map(\.rawValue)
        report["titlesWhileWatching"] = StatusItemMenuItem.allCases.map {
            ShellStrings.string($0.titleKey(sensingPaused: false))
        }
        report["titlesWhilePaused"] = StatusItemMenuItem.allCases.map {
            ShellStrings.string($0.titleKey(sensingPaused: true))
        }

        let controller = AppComposition.shared.menuBar
        report["installed"] = controller.isInstalled
        report["sensingPaused"] = !AppComposition.shared.sensingHost.isRunning
        let menu = controller.secondaryMenu()
        report["autoenablesItems"] = menu.autoenablesItems
        report["separators"] = menu.items.filter(\.isSeparatorItem).count
        report["drawn"] = menu.items.filter { !$0.isSeparatorItem }.map { item in
            [
                "identity": item.representedObject as? String ?? "",
                "title": item.title,
                "isEnabled": item.isEnabled,
                "hasTarget": item.target != nil,
                "hasAction": item.action != nil
            ] as [String: Any]
        }
        // The item *Settings…* performs, in this application's real menu bar.
        report["settingsMenuItemTitle"] =
            ShellSettingsMenu.settingsItem(in: NSApplication.shared.mainMenu)?.title ?? ""
        return report
    }

    /// **A Dock click with no window open, driven in the shipping process** (focus-odz.1).
    ///
    /// The delegate method is a `FocusHost` function with a unit test over it, and the test proves
    /// what it *asks for*: `FocusCommandCenter.cockpitRequests` goes up. What no unit process can
    /// prove is that the request produces a **window**, because only a launch with a scene graph
    /// has an `openWindow` to install — `canRaiseCockpit` is `false` in the unit lane by
    /// construction. So this closes the cockpit, calls the delegate the way AppKit calls it, and
    /// reads the window list back.
    ///
    /// It goes through `NSApp.delegate` rather than through a `FocusAppDelegate` this function
    /// constructs, and that is the load-bearing half: with an `@NSApplicationDelegateAdaptor` in
    /// play `NSApp.delegate` is SwiftUI's own forwarding object, so a method the adaptor does not
    /// forward would answer nothing here while a directly-constructed delegate answered
    /// perfectly. `answered` is that fact, reported rather than assumed.
    @MainActor
    static func reopenReport() -> [String: Any] {
        var report: [String: Any] = [:]

        liveCockpitWindow()?.close()
        settle(forSeconds: sceneSettleSeconds)
        let closed = liveCockpitWindow()
        report["cockpitVisibleBeforeReopen"] = closed?.isVisible ?? false
        report["requestsBefore"] = FocusCommandCenter.shared.cockpitRequests
        report["canRaiseCockpit"] = FocusCommandCenter.shared.canRaiseCockpit

        let delegate = NSApp.delegate
        let selector = #selector(NSApplicationDelegate.applicationShouldHandleReopen(_:hasVisibleWindows:))
        let answered = delegate?.responds(to: selector) ?? false
        report["answered"] = answered
        if answered {
            report["returned"] = delegate?.applicationShouldHandleReopen?(
                NSApp,
                hasVisibleWindows: false
            ) ?? true
        }

        settle(forSeconds: sceneSettleSeconds)
        report["requestsAfter"] = FocusCommandCenter.shared.cockpitRequests
        let reopened = liveCockpitWindow()
        report["cockpitVisibleAfterReopen"] = reopened?.isVisible ?? false
        report["cockpitWindowTitleAfterReopen"] = reopened?.title ?? ""
        report["visibleWindowIdentifiers"] = NSApp.windows
            .filter(\.isVisible)
            .map { $0.identifier?.rawValue ?? "" }
            .sorted()
        return report
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
    /// and three counts, so a fold that quietly shrinks is visible as a number rather than as an
    /// unchanged `true` — see `routeAudit(over:)` for why one count was not enough.
    nonisolated static func accusationRouteAudit()
        -> (cells: Int, delivered: Int, deferred: Int, unanswerable: [String]) {
        let audit = routeAudit(over: LadderRung.Kind.allCases.filter(\.makesAnAccusation))
        return (audit.cells, audit.delivered, audit.deferred, audit.unanswerable)
    }

    /// **Every route the requested rungs can take, over the whole input space** (focus-3vb).
    ///
    /// One fold, parameterised by the rungs it visits, because there were two questions being
    /// asked of one space and only one of them was being folded. `accusationRouteAudit()` above is
    /// this fold over the accusing rungs; `surfacesARungCanReach` is this fold's `surfaces` over
    /// **all** of them.
    ///
    /// That second reading used to be `Set(routes.compactMap { $0["surface"] })` — a fold over the
    /// two-cell `routes` table, every rung asked exactly once at `.notPresenting`, `.idle`,
    /// `reducedInterruption: false`, `menuBarVisible: true`, `voice: .standard`. It is the ONLY
    /// "no rung reaches a notification" reading the Release lane takes, and a notification route
    /// reachable under Reduce Motion, a running microphone, `silentVisual` or a hidden menu bar
    /// was invisible to it. Widening it costs nothing — the fold already existed — and it is the
    /// difference between a claim about two cells and a claim about a hundred and sixty.
    ///
    /// Returns the offending cells named, so a red gate says which rung under which conditions;
    /// the surfaces actually reached, sorted, so the set can be pinned rather than searched; and
    /// **three** counts rather than one.
    ///
    /// **`cells` counts loop iterations, and that was the defect** (focus-2uy.4). The gate
    /// asserted `accusationRouteCellsChecked == 80` under a heading about the fold not shrinking,
    /// and 80 is the size of the *space*: a fold in which every single cell deferred would report
    /// exactly the same number, so the anti-vacuity control could not tell a fold that visited
    /// eighty cells from one that answered eighty times. Measured at the Release binary of gate
    /// run `vocabgate-1`: **56 of the 80 deferred**, so the verdict `everyAccusationRouteCanBeAnswered`
    /// was a claim about 24 cells published under a count of 80.
    ///
    /// So the two halves are counted separately and the identity between them is published:
    /// `cells == delivered + deferred`, asserted by `self-check.sh` with a floor under
    /// `delivered`. A conservation law is what makes the two numbers check each other — a fold
    /// that stopped visiting cells and a fold that stopped reaching surfaces are different
    /// failures, and one number could report neither.
    nonisolated static func routeAudit(
        over rungs: [LadderRung.Kind]
    ) -> (cells: Int, delivered: Int, deferred: Int, surfaces: [String], unanswerable: [String]) {
        var unanswerable: [String] = []
        var reached: Set<String> = []
        var cells = 0
        var delivered = 0
        var deferred = 0

        for rung in rungs {
            for cell in routeSpace {
                cells += 1
                let route = SurfaceRouter.route(
                    rung: rung,
                    presentation: cell.presentation,
                    media: cell.media,
                    reducedInterruption: cell.reducedInterruption,
                    menuBarVisible: cell.menuBarVisible,
                    voice: cell.voice
                )
                if let surface = route.surface {
                    delivered += 1
                    reached.insert(surface.rawValue)
                } else {
                    deferred += 1
                }
                guard let surface = route.surface, !surface.offersAnAnswer else { continue }
                unanswerable.append("\(rung.rawValue)/\(cell.name) -> \(surface.rawValue)")
            }
        }
        return (cells, delivered, deferred, reached.sorted(), Set(unanswerable).sorted())
    }

    /// **The same fold, aimed at the question** (focus-3vb's sibling).
    ///
    /// A rung's routes have been folded over the whole input space since focus-3vb, and
    /// `surfacesARungCanReach` is pinned in both directions over all 160 cells. **The question's
    /// were not.** The gate's only claim about where a question goes was
    /// `querySurface in ("panel", "popoverBadge")` — one cell of the space, at `.notPresenting`,
    /// `.idle`, `reducedInterruption: false`, `menuBarVisible: true`, `.standard`, tested for
    /// membership of a two-element set. Two failures in one line, and they are the two the round
    /// that widened the rung's fold was written to end: a membership test cannot see a surface
    /// *appearing* (route every question to a notification and the check stays green as long as
    /// that one cell still answers `panel`), and the space it searched was one cell wide.
    ///
    /// The 30-cell `queryRoutes` table beside it was wider on three axes and blind on two:
    /// it varied deck, `reducedInterruption` and media, and pinned `.notPresenting` and
    /// `menuBarVisible: true` — which are exactly the two axes the rung's fold gained. So each of
    /// the two folds over one router was blind to something the other saw.
    ///
    /// There is **one space** now, `routeSpace`, and both audits are taken over it. Two folds
    /// over one router cannot drift apart when there is one enumeration.
    ///
    /// Returns the surfaces reached, sorted, so the set can be pinned rather than searched; the
    /// cells that reach a surface a question cannot be carried on, named; and the number of cells
    /// visited, so a fold that quietly shrinks is a number rather than an unchanged `true`.
    nonisolated static func queryRouteAudit()
        -> (cells: Int, surfaces: [String], uncarryable: [String], badge: Int, panel: Int) {
        var uncarryable: [String] = []
        var reached: Set<String> = []
        var badge = 0
        var panel = 0

        for cell in routeSpace {
            let route = SurfaceRouter.routeQuery(
                presentation: cell.presentation,
                media: cell.media,
                reducedInterruption: cell.reducedInterruption,
                menuBarVisible: cell.menuBarVisible,
                voice: cell.voice
            )
            guard let surface = route.surface else { continue }
            reached.insert(surface.rawValue)
            if surface == .popoverBadge { badge += 1 }
            if surface == .panel { panel += 1 }
            if !surface.canCarryAQuestion {
                uncarryable.append("\(cell.name) -> \(surface.rawValue)")
            }
        }
        return (routeSpace.count, reached.sorted(), Set(uncarryable).sorted(), badge, panel)
    }

    /// **One enumeration of the router's whole input space, shared by both folds.**
    ///
    /// Five axes — presentation, media, `reducedInterruption`, menu-bar visibility and deck. The
    /// rung fold multiplies it by `LadderRung.Kind.allCases`; the query fold takes it as it is.
    ///
    /// The media axis is two values and not four, and that is a measurement rather than a saving:
    /// `SurfaceRouter` reads media through `MediaActivity.suppressesIntervention` alone, which is
    /// `microphoneRunning || cameraRunning`, so a running camera routes exactly as a running
    /// microphone does. `SelfCheckRouteSpaceTests` asserts that rather than assuming it, which is
    /// what makes two values the whole axis instead of half of it.
    nonisolated static var routeSpace: [
        (
            name: String,
            presentation: PresentationState,
            media: MediaActivity,
            reducedInterruption: Bool,
            menuBarVisible: Bool,
            voice: NudgeVoice
        )
    ] {
        let presenting = PresentationState(
            signals: PresentationSignals(
                frontmostWindowFillsAScreen: true,
                presentationOptionsSayFullScreen: true,
                menuBarHidden: true
            ),
            isUserExcluded: false,
            isPresenting: true
        )
        var space: [
            (
                name: String,
                presentation: PresentationState,
                media: MediaActivity,
                reducedInterruption: Bool,
                menuBarVisible: Bool,
                voice: NudgeVoice
            )
        ] = []
        for presentation in [PresentationState.notPresenting, presenting] {
            for media in [MediaActivity.idle, MediaActivity(microphoneRunning: true)] {
                for reduced in [false, true] {
                    for menuBar in [true, false] {
                        for voice in NudgeVoice.allCases {
                            var name = "\(voice.rawValue)/reduced=\(reduced)"
                            name += "/menuBar=\(menuBar)"
                            name += "/presenting=\(presentation.suppressesOverlays)"
                            name += "/mic=\(media.suppressesIntervention)"
                            space.append(
                                (
                                    name: name,
                                    presentation: presentation,
                                    media: media,
                                    reducedInterruption: reduced,
                                    menuBarVisible: menuBar,
                                    voice: voice
                                )
                            )
                        }
                    }
                }
            }
        }
        return space
    }

    /// One delivered rung of a kind, as the value the two cap predicates are asked of.
    ///
    /// Built once so the floor's two readings cannot be asked about differently-shaped events —
    /// the same reason `InterventionRecord.budgetEvent` exists (focus-d6r).
    static func deliveredRung(_ kind: LadderRung.Kind) -> InterventionEvent {
        InterventionEvent(
            kind: .accusation,
            rung: kind,
            subject: "",
            surface: kind.makesAnAccusation ? .panel : .menuBar,
            disposition: .delivered
        )
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
        //
        // **Three keys, because the old one was three claims wearing one name** (focus-652). The
        // gate used to assert that this value was one of the four strings the decoder is *total
        // over* — including for every unrecognised status, which falls to `.denied` — under a pass
        // line that read *"the authorisation was read through getNotificationSettings"*. It could
        // not see whether the read happened, and it was spelled exactly wide enough to cover both
        // sides of an unsequenced one. So:
        //
        // * `notificationAuthorisationReads` says the read **happened**. Delete
        //   `AppComposition.start()`'s one call and it is zero.
        // * `notificationAuthorisation` says what it **found**, and is `"unread"` when nothing was
        //   found — `notRequested` is a real OS answer and may not double as the absence of one.
        // * `notificationAuthorisationDecodeTable` says how the boundary **decodes**, folded over
        //   every raw status in `foldedRawStatuses` and pinned against a committed literal. That
        //   is the mapping, which is behaviour; the codomain is a property of the type.
        let authorisationWasRead = Self.awaitNotificationAuthorisation()
        report["notificationAuthorisationReads"] = host.notificationAuthorisationReads
        report["notificationAuthorisationWasRead"] = authorisationWasRead
        report["notificationAuthorisation"] = host.notificationAuthorisation?.rawValue ?? "unread"
        report["notificationAuthorisationDecodeTable"] = NotificationAuthorisation.decodeTable
        report["notificationAuthorisationDecodeCells"] = NotificationAuthorisation.decodeTableCells
        report["requestAuthorizationCallCount"] = host.requestAuthorizationCallCount

        // **A nudge on the screen that the loop has forgotten** — always empty (focus-v0u,
        // focus-xix).
        //
        // The invariant `NudgeHost.endOpenQuestion(_:)` and `NudgeHost.endOpenRung(_:)` exist to
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

        // **THE FLOOR, published as a reading rather than asserted in a comment** (focus-d6r).
        //
        // `dispositionsSpendingACap` above is the ceiling's half: it watches for a disposition
        // that starts charging. This is its twin and it was missing, which is exactly the shape
        // this epic keeps producing — the danger is not only that something starts charging but
        // that the wrong thing does, and the day is then spent on nothing.
        //
        // Measured before these lines existed: eight ambient glyph landings drove
        // `interruptionsToday` to `dailyInterruptionCap` with `accusationsToday` at nought, and
        // `remaining(for:)` conjoins the shared budget into BOTH kinds — so `permits(.accusation)`
        // and `permits(.query)` were both false on a day the app had said nothing at all. The
        // panel rung, the only rung that carries a sentence, was unreachable for the rest of it.
        //
        // A **pure** reading of the shipping types, like `surfacePerceptionChannels` beside it:
        // an automated run raises no rung, so a reading of the live budget would be a reading of
        // zero, and a reading that is constant is a reading a gate cannot use.
        report["rungsSpendingTheAccusationCap"] = LadderRung.Kind.allCases
            .filter { Self.deliveredRung($0).spendsTheAccusationCap }
            .map(\.rawValue)
            .sorted()
        report["rungsSpendingTheInterruptionCap"] = LadderRung.Kind.allCases
            .filter { Self.deliveredRung($0).spendsTheInterruptionCap }
            .map(\.rawValue)
            .sorted()

        // **AND WHICH RUNGS EACH REASON FOR SILENCE IS EVEN ABOUT** (focus-0y6, focus-uru).
        //
        // The two readings above say which rungs SPEND something. These are the same rule one
        // level up: which rungs each reason for going quiet may STOP. Three consecutive repairs
        // applied that ruling to one more gate and left the next — focus-2yy's message enumerates
        // "gates 1, 2 and 3 … gate 5" and focus-0y6's triage walked twelve gates and ruled on
        // each, and both skipped gate 4 — because a closed set swept by reading prose is not
        // swept. `SilenceSubject` is where it is decided now, in two exhaustive switches.
        //
        // Named rather than counted, for `rungsSpendingTheAccusationCap`'s reason: the danger is
        // not how many gates there are but WHICH ones take the status item with them. And a
        // **pure** reading of the shipping types, like the two above: an automated run closes no
        // gate, so a reading of live silences would be a reading of zero, and a reading that is
        // constant is a reading a gate cannot use.
        report["gatesSilencingTheGlyph"] = NudgeSuppressionReason.allCases
            .filter { $0.subject.ruling(for: .ambient) == .silences }
            .map(\.rawValue)
            .sorted()
        report["gatesPassingOverTheGlyph"] = NudgeSuppressionReason.allCases
            .filter { $0.subject.ruling(for: .ambient) == .passes }
            .map(\.rawValue)
            .sorted()
        // R-81's cell: wanted, and undeliverable because the menu bar is not on screen.
        report["gatesDeferringTheGlyph"] = NudgeSuppressionReason.allCases
            .filter { reason in
                if case .defers = reason.subject.ruling(for: .ambient) { return true }
                return false
            }
            .map(\.rawValue)
            .sorted()
        // Gate 10's detail, which classifies for it. Exactly one of the six may take the glyph:
        // a correction, which means there is nothing left to be off task about.
        //
        // **Three readings, because the suppression vocabulary nine lines above gets three**
        // (focus-2uy.5). This was one: the set that silences. A partition published as one of its
        // three parts is a partition nothing can check — a seventh refusal ruled
        // `.theAppSpeaking` would join no published set and leave every Release reading exactly
        // as it was, which is the same shape as a fold whose space quietly shrinks. The three are
        // asserted by `self-check.sh` together with the identity that they cover the vocabulary
        // and share no member.
        report["fatigueRefusalsDeclared"] = FatigueRefusal.Kind.allCases.map(\.rawValue).sorted()
        report["fatigueRefusalsSilencingTheGlyph"] = FatigueRefusal.Kind.allCases
            .filter { $0.subject.silences(.ambient) }
            .map(\.rawValue)
            .sorted()
        report["fatigueRefusalsPassingTheGlyph"] = FatigueRefusal.Kind.allCases
            .filter { $0.subject.ruling(for: .ambient) == .passes }
            .map(\.rawValue)
            .sorted()
        // R-81's cell, and it is empty **by ruling**: `FatigueDecision` has two cases and no
        // third, so `FatigueRefusal.Kind.subject` is never `.theSurfaceBeingOnScreen` and a
        // deferral is the suppression stack's answer to give. Published rather than assumed,
        // because "empty because nobody may write it" and "empty because nobody has yet" are
        // different facts and only one of them is a ruling.
        report["fatigueRefusalsDeferringTheGlyph"] = FatigueRefusal.Kind.allCases
            .filter { kind in
                if case .defers = kind.subject.ruling(for: .ambient) { return true }
                return false
            }
            .map(\.rawValue)
            .sorted()
        // **A whole shared budget's worth of landings, priced by the shipping arithmetic — for
        // EVERY rung, and with the number of charges the pricing actually folded** (focus-hqf).
        //
        // THE READING THIS REPLACES WAS TRUE OF AN EMPTY DAY. It folded `dailyInterruptionCap`
        // *ambient* landings and reported `landings: dailyInterruptionCap` as a **constant**.
        // `InterruptionCharge.init?(_:)` guards on `spendsTheInterruptionCap`; an ambient landing
        // does not spend it, by design; so the `compactMap` yielded nothing and the budget being
        // priced was `InterruptionBudget.empty`. All four assertions the gate made on it — nought
        // interruptions, nought accusations, both permissions still true — are what an empty
        // budget answers, for reasons with nothing to do with glyph landings. Measured against the
        // Release `FocusCore.o` of gate run `floorgate-1`: charges folded 0, identical to `.empty`;
        // the same fold over the panel rung folded 8.
        //
        // It is `NudgeFloorTests`' own rule 3 — *non-vacuity asserted in both directions* — written
        // in the same round thirty lines of prose away, and not kept by the binary twin.
        //
        // So: **one fold over the whole rung vocabulary**, `chargesFolded` as `charges.count`
        // rather than a constant, and the rung that DOES spend the cap folded by the same three
        // lines rather than by a control written beside them. A rung added tomorrow gets a row
        // here and fails the gate until somebody says what its day costs.
        var dayByRung: [String: Any] = [:]
        for kind in LadderRung.Kind.allCases {
            let charges = (0..<InterventionPolicy.dailyInterruptionCap).compactMap { _ in
                InterruptionCharge(Self.deliveredRung(kind))
            }
            let day = InterruptionBudget.spent(charges, underPriority: nil)
            dayByRung[kind.rawValue] = [
                "landings": InterventionPolicy.dailyInterruptionCap,
                "chargesFolded": charges.count,
                "interruptionsToday": day.interruptionsToday,
                "accusationsToday": day.accusationsToday,
                "permitsAccusation": day.permits(.accusation),
                "permitsQuery": day.permits(.query),
                "bindingLimit": day.bindingLimit(for: .accusation)?.rawValue ?? ""
            ]
        }
        report["budgetAfterADayOfLandings"] = dayByRung
        // The size of the fold beside the fold, so a vocabulary that shrank is a number rather
        // than a table nobody counted.
        report["budgetAfterADayOfLandingsRungs"] =
            LadderRung.Kind.allCases.map(\.rawValue).sorted()
        // The ambient row lifted under the name the gate has read since focus-d6r.
        report["budgetAfterADayOfGlyphLandings"] =
            dayByRung[LadderRung.Kind.ambient.rawValue] ?? [:]

        report["questionExitsWritingAnExpiry"] = QuestionExit.allCases
            .filter(\.recordsAnExpiry)
            .map(\.rawValue)
            .sorted()

        // **And the other half of the same reading** (focus-s4m). The two lines above have said
        // since focus-h0s that a question's ending is a closed vocabulary with its obligations
        // placed on the exit; the accusation's ending was six hand-written doors and had no
        // reading at all, which is this round's instance of the shape every bead in this sequence
        // has. Two of those doors told the ladder nothing, and one of them — ⌃⌘H — left it standing
        // at a rung `candidate(at:budgetPermits:)` answers `nil` from for ever.
        report["rungExitsDeclared"] = RungExit.allCases.map(\.rawValue).sorted()
        // **Which of them are R-81 take-backs**, named rather than counted, for the reason
        // `questionExitsWritingAnExpiry` is named: an exit quietly joining or leaving the
        // withdrawing set is the edit that matters, and it is the edit the shipping app has no
        // other way to report.
        report["rungExitsTakingBackTheDelivery"] = RungExit.allCases
            .filter(\.takesBackTheDelivery)
            .map(\.rawValue)
            .sorted()
        // **And which of them the two backoffs hear about** (focus-fzf). The third of the three
        // things an ending settles, published for the reason the first two are: this set gained a
        // member this round — a panel the person drifted straight past — and the argument that
        // held it out for a round was a *measurement* on the day shape, not a ruling. A set that
        // can change on a measurement is a set the shipping app should be made to state.
        report["rungExitsCountingAnIgnoredAccusation"] = RungExit.allCases
            .filter(\.countsAsAnIgnoredAccusation)
            .map(\.rawValue)
            .sorted()

        // **The fourth answer to "why did the app go quiet?", which had no vocabulary at all**
        // (focus-628, focus-50m, focus-1ua).
        //
        // `NudgeSuppressionReason` and `FatigueRefusal.Kind` are published above and each declares
        // a `SilenceSubject`. The ladder was the third and was in neither: it silenced by
        // *arithmetic* — `candidate(at:budgetPermits:)` answered `nil`, `NudgeDecider.accuse(…)`
        // reported `.budgetExhausted` for all four reasons alike, and the glyph went with it.
        report["ladderStatesDeclared"] = LadderState.Kind.allCases.map(\.rawValue).sorted()
        report["ladderSilencesDeclared"] = LadderSilence.allCases.map(\.rawValue).sorted()
        // **Which of them still owe the person the rung that says nothing** — the reading the
        // decider makes instead of collapsing a `nil`, named rather than counted, exactly as
        // `gatesPassingOverTheGlyph` is. A silence quietly joining or leaving this set is the edit
        // that decides whether a held ladder marks anybody at all.
        report["ladderSilencesRetainingTheGlyph"] = LadderSilence.allCases
            .filter(\.retainsTheAmbientRung)
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
        // **And whether the seam is actually reached** (focus-my0). `SettledObservation` makes a
        // charge from a mid-turn reading unrepresentable; what no type can hold is that every door
        // into the loop opens a turn, because that is a wrapper somebody has to write. A door
        // added without one does not charge for something imperceptible — it settles at somebody
        // else's seam, which unties the charge from the write that earned it — so this is a
        // reading rather than a refusal, and it is the number that says the plumbing is whole.
        report["proofsOfferedOutsideATurn"] = host.proofsOfferedOutsideATurn

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
        // **Every surface any rung can reach, over the WHOLE input space** (U-2, focus-3vb).
        //
        // Since the recommitment rung was deferred to focus-5ab there is no rung a notification can
        // carry, and this is the reading that says so from inside the running application rather
        // than from a table a reader has to interpret.
        //
        // **It was two cells wide.** `routes` above asks each rung exactly once, pinned at
        // `.notPresenting`, `.idle`, `reducedInterruption: false`, `menuBarVisible: true`,
        // `voice: .standard` — and this is the ONLY "no rung reaches a notification" reading the
        // Release lane takes, because `notification-denied` runs against the Debug product. A
        // notification route reachable under Reduce Motion, a running microphone, `silentVisual`
        // or a hidden menu bar was invisible to it, which is to say: invisible to every reading
        // that gates the artefact this programme ships.
        //
        // It is now the same fold `accusationRouteAudit()` runs, over every rung instead of the
        // accusing ones — 160 cells, two rungs over an 80-cell space, where the accusation fold's
        // is 80 (focus-484) — and the counts are published beside it so a fold that quietly
        // shrinks is a number rather than an unchanged list.
        let rungAudit = routeAudit(over: LadderRung.Kind.allCases)
        report["surfacesARungCanReach"] = rungAudit.surfaces
        report["surfacesARungCanReachCellsChecked"] = rungAudit.cells
        // **And what became of them** (focus-2uy.4). A count of cells visited is satisfied by a
        // fold in which every cell deferred; the two halves and the conservation identity between
        // them are what make the number mean something.
        report["surfacesARungCanReachCellsDelivered"] = rungAudit.delivered
        report["surfacesARungCanReachCellsDeferred"] = rungAudit.deferred
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
        // menu-bar states, presenting and not. **Eighty cells** — `routeSpace` is 2 × 2 × 2 × 2 ×
        // 5 and the accusing rungs are `.panel` alone since U-2, which is what `self-check.sh`
        // has always asserted; this paragraph said 160, the size of the fold over *both* rungs,
        // inside the very passage that exists to explain the anti-vacuity control, so a reader
        // checking the control against its own explanation concluded the fold had halved
        // (focus-484). The count is reported beside the verdict — a fold that quietly shrinks is the
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
        // **The verdict above is a claim about the cells that REACHED a surface** (focus-2uy.4).
        // 56 of these 80 defer — a presentation, a hidden menu bar, a running microphone — and a
        // cell that reached nobody cannot be a cell whose answerability was tested. Published as
        // two numbers with `visited == delivered + deferred` asserted by the gate, so the control
        // that exists to see a shrinking fold can see a fold that stopped reaching surfaces too.
        report["accusationRouteCellsDelivered"] = audit.delivered
        report["accusationRouteCellsDeferred"] = audit.deferred
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
        // notification** (R-82). The single cell the settings pane describes, kept as the table's
        // own row and pinned to a literal — never searched for membership of a set, which is what
        // it used to be and which could not see a surface *appearing*.
        let queryRoute = SurfaceRouter.routeQuery(
            presentation: .notPresenting,
            media: .idle,
            reducedInterruption: false,
            menuBarVisible: true,
            voice: .standard
        )
        report["querySurface"] = queryRoute.surface?.rawValue ?? ""

        // **And the whole space, with the set pinned in both directions** (focus-3vb's sibling).
        //
        // `queryRouteAudit()` is the same fold `surfacesARungCanReach` is taken over — literally
        // the same `routeSpace` enumeration — so the question and the rung can no longer be blind
        // to different axes of one router. What it replaces was a 30-cell table that varied deck,
        // `reducedInterruption` and media while pinning `.notPresenting` and
        // `menuBarVisible: true`: the two axes the rung's fold had just gained.
        let queryAudit = queryRouteAudit()
        report["surfacesAQuestionCanReach"] = queryAudit.surfaces
        report["surfacesAQuestionCanReachCellsChecked"] = queryAudit.cells
        report["queryCellsThatCannotCarryAQuestion"] = queryAudit.uncarryable
        report["everyQueryRouteCanCarryAQuestion"] = queryAudit.uncarryable.isEmpty
        report["queryRoutesReachingTheBadge"] = queryAudit.badge
        report["queryRoutesReachingThePanel"] = queryAudit.panel

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
        // **The mark the item is really drawing, which is not the mark the presentation asked
        // for** (focus-nrl). `menuBarAttention` below is the composed request — the *maximum* of
        // the rung's mark and the badge's — and this is the button's own answer. The two
        // disagreeing is the whole of focus-nrl: a glyph rung asking for `noticing` under a
        // pending badge nudge while the item goes on drawing `waiting`.
        report["markOnTheMenuBarItem"] = composition.menuBar.markOnTheItem.rawValue
        // **The charging invariant, as a join rather than as a counter** (focus-1b5, focus-nrl).
        //
        // `chargesPaidFor` is the list of `PerceptibleChange` receipts the perception path has
        // issued; `deliveredRowsToday` is summed from persisted `InterventionRecord` rows the
        // completely separate way the day's caps are. A delivered row with no receipt behind it
        // is a charge that did not go through the door, which is what three rounds of this defect
        // were. The two published side by side rather than as a single `Bool`, because a `Bool`
        // computed here would be this file marking its own homework.
        //
        // The channels are published with them so the evidence says *what* was perceived: a
        // charge on `menuBarItem` is an assignment to an `NSStatusBarButton`, and one on
        // `popoverContents` is a popover that was open and drawing the nudge.
        report["chargesPaidFor"] = host.chargesPaidFor.count
        report["chargeChannels"] = host.chargesPaidFor.map(\.channel.rawValue).sorted()
        report["deliveredRowsToday"] = (try? host.deliveredRowsToday()) ?? -1
        // The table itself, so a surface that acquired a channel nothing can observe is a diff in
        // the evidence rather than only in a doc comment.
        report["surfacePerceptionChannels"] = NudgeSurface.allCases.map { surface in
            ["surface": surface.rawValue, "channel": surface.perceptionChannel.rawValue]
        }
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
        report["popover"] = popoverReport()
        report["tickFetches"] = tickFetchSurvey()
        report["menuBarInstalled"] = composition.menuBar.isInstalled
        report["decisionCount"] = host.decisionCount
        return report
    }

    /// **That the app forgets, and that it forgets the right things** (F-115, focus-tzj.3).
    ///
    /// ## Two halves, and both are needed
    ///
    /// The first is a fact about **this launch**: the sweep ran, on which local day, and how many
    /// rows it removed. On a machine whose store holds nothing older than the window that is
    /// three zeroes and a date — true, and worth nothing on its own, because a sweep that had
    /// been deleted from the launch path would publish the same three zeroes if the day were
    /// absent, and a day with no rows is the *ordinary* case for a fresh gate machine.
    ///
    /// So the second half is a **seeded** sweep on a store of this survey's own, holding one row
    /// at 89 days and one at 91 in each of the two tables that die of age. It is the non-vacuity
    /// control for the first: the mechanism the launch used is shown removing exactly the rows it
    /// is supposed to remove and exactly none of the others, in the same process, on the same
    /// code, in a run where the answer cannot be zero by accident.
    ///
    /// The receipts are deliberately not in the seed's expected count. They die with their
    /// priority rather than of age (see `RetentionSweep`), and the seed's priority is one the
    /// survey just created — so a receipt under it must survive, which is the third row below.
    @MainActor
    static func retentionReport() -> [String: Any] {
        var report: [String: Any] = [:]
        report["windowDays"] = RetentionPolicy.committedDefault.days
        let live = AppComposition.shared.lastRetentionSweep
        report["ranAtLaunch"] = live != nil
        report["lastRunDay"] = live?.day.key ?? ""
        report["rowsRemoved"] = live?.rowsRemoved ?? -1
        report["activityEventsRemoved"] = live?.activityEvents ?? -1
        report["interventionRowsRemoved"] = live?.interventionRows ?? -1
        report["queryReceiptsRemoved"] = live?.queryReceipts ?? -1

        do {
            let container = try FocusStore.makeContainer(kind: .inMemory)
            let context = ModelContext(container)
            // The one sanctioned wall clock (R-26): the seed's dates are computed from the same
            // reading the sweep will take, so the 89/91-day boundary is exact rather than nearly.
            let clock = SystemDateProvider()
            let now = clock.now
            let calendar = Calendar.autoupdatingCurrent
            let events = ActivityEventStore(context: context, dateProvider: clock)
            let log = InterventionLog(context: context, dateProvider: clock, calendar: calendar)
            let ledger = QueryLedger(context: context, dateProvider: clock)
            let priorities = PriorityStore(context: context, dateProvider: clock)

            func daysAgo(_ days: Int) -> Date {
                calendar.date(byAdding: .day, value: -days, to: now) ?? now
            }
            for days in [89, 91] {
                _ = try events.append(
                    kind: .frontmostApplicationChanged,
                    bundleID: FocusStore.bundleIdentifier,
                    at: daysAgo(days)
                )
                _ = try log.record(
                    InterventionEvent(
                        kind: .query,
                        subject: FocusStore.bundleIdentifier,
                        disposition: .delivered
                    ),
                    at: daysAgo(days)
                )
            }
            let priorityID = try priorities.setPriority(intent: "Self-check retention seed")
            _ = try ledger.record(
                priorityID: priorityID,
                subjectKind: .app,
                subject: FocusStore.bundleIdentifier,
                reason: .noNegativeBasis,
                outcome: .declined,
                askedAt: daysAgo(91),
                at: daysAgo(91)
            )

            let result = try RetentionSweep(
                events: events,
                log: log,
                ledger: ledger,
                priorities: priorities,
                calendar: calendar,
                dateProvider: clock
            ).run()

            report["seededActivityEventsRemoved"] = result.activityEvents
            report["seededInterventionRowsRemoved"] = result.interventionRows
            report["seededQueryReceiptsRemoved"] = result.queryReceipts
            report["seededActivityEventsKept"] = try events.count()
            report["seededInterventionRowsKept"] = try log.count()
            report["seededQueryReceiptsKept"] = try ledger.receipts(priorityID: priorityID).count
            report["seedAvailable"] = true
        } catch {
            report["seedAvailable"] = false
            report["seedError"] = "\(error)"
        }
        return report
    }

    /// **What one corroboration tick costs the store, in three states** (focus-tzj.2).
    ///
    /// ## The defect
    ///
    /// The five-second tick fetched things that could not have moved. `PriorityStore.recentTasks`
    /// read **every** `PriorityTask` in the table and sorted them in Swift to draw a list of
    /// eight; `NudgeMemory.reading` folded **today's whole intervention log** and looked for a
    /// query receipt *before* gate 1 was consulted, so a person with no commitment at all paid
    /// for both on every tick. Measured on this survey's own store before the repair: 3 fetches
    /// per tick with no commitment and 5 with one, every tick, for ever.
    ///
    /// ## What is driven
    ///
    /// The tick's two store-touching halves, on a store of this survey's own: `PriorityHost`'s
    /// projection — which `AppComposition.refreshCockpit()` calls — and `NudgeMemory.reading`,
    /// which is the first thing `NudgeHost.consider` does with a judgement. Nothing else on the
    /// path opens the store on a tick: the sensing host writes only on a transition, and the
    /// relevance host pre-fetches only when the snapshot key moves.
    ///
    /// A store of its own rather than the launch's, for two reasons. The three states are
    /// *"there is no commitment"*, *"there is one"* and *"there is one and the popover is open"*,
    /// and the first two are facts about somebody's real store that a survey may not arrange; and
    /// a reading taken against whatever the person happened to have captured would be a different
    /// number on every machine.
    ///
    /// ## What is published
    ///
    /// Per state: the fetches the **first** tick made — which is the non-vacuity control, because
    /// every claim below is about ticks that fetch nothing and a survey that never fetched at all
    /// would satisfy all of them — and the fetches each of the **nine after it** made, with
    /// nothing changed in between.
    @MainActor
    static func tickFetchSurvey() -> [String: Any] {
        var report: [String: Any] = [:]
        do {
            let container = try FocusStore.makeContainer(kind: .inMemory)
            let context = ModelContext(container)
            let dateProvider = SystemDateProvider()
            let calendar = Calendar.autoupdatingCurrent
            let priorities = PriorityStore(context: context, dateProvider: dateProvider)
            let ledger = QueryLedger(context: context, dateProvider: dateProvider)
            let log = InterventionLog(
                context: context,
                dateProvider: dateProvider,
                calendar: calendar
            )
            // A history to fetch, so "the history is not re-read" is a statement about a list
            // that exists. Ten rows against a limit of eight, so the limit is doing something.
            for index in 0..<10 {
                _ = try priorities.createTask(intent: "Self-check history row \(index)")
            }
            // A day with something in it, so the budget fold has rows to fold.
            _ = try log.record(
                InterventionEvent(kind: .query, subject: FocusStore.bundleIdentifier, disposition: .deferred)
            )

            // A menu bar of the survey's own, for the open-popover state. Deliberately not the
            // launch's: this is a measurement of what building the popover's content costs, and
            // it must not depend on a status item having been installed or on what the live
            // presentation happens to be.
            let menuBar = MenuBarController()

            let host = PriorityHost(
                context: context,
                dateProvider: dateProvider,
                calendar: calendar,
                locale: .autoupdatingCurrent,
                environment: PriorityHost.Environment(
                    status: .uncertain,
                    storeOpened: true,
                    isObservingActivity: false
                )
            )
            // The subject a question would be about, derived the way the loop derives it —
            // `QuerySubject`'s initialiser is fileprivate precisely so that no other route
            // exists. With one in hand the survey pays for gate 11's receipt lookup as well as
            // the budget, which is the more expensive of the two states a tick can be in.
            let subject = QuerySubject.derive(
                judgedSubject: FocusStore.bundleIdentifier,
                explanation: Explanation.make(
                    stage: .heuristic,
                    band: .high,
                    clauses: [.insufficientEvidence(reason: .noNegativeBasis)],
                    stamp: EngineStamp.current
                )
            )

            /// One tick, in three counted parts.
            func tick(commitment: UUID?, popoverIsOpen: Bool) -> (cockpit: Int, nudge: Int, popover: Int) {
                StoreFetchCounter.reset()
                host.update(
                    environment: PriorityHost.Environment(
                        status: .uncertain,
                        storeOpened: true,
                        isObservingActivity: false
                    )
                )
                let cockpit = StoreFetchCounter.count

                StoreFetchCounter.reset()
                _ = try? NudgeMemory.reading(
                    ledger: ledger,
                    log: log,
                    priorityID: commitment,
                    subject: subject
                )
                let nudge = StoreFetchCounter.count

                // The work an open popover adds to a tick. It must touch no store at all — and
                // that is a claim this survey can falsify rather than a remark, because the
                // counter is running while it happens.
                StoreFetchCounter.reset()
                if popoverIsOpen {
                    menuBar.update(popoverSurveyContents[1].1, traits: .systemDefault)
                    menuBar.refreshPopoverContent()
                }
                return (cockpit, nudge, StoreFetchCounter.count)
            }

            let states: [(String, Bool, Bool)] = [
                ("noCommitment", false, false),
                ("commitmentPopoverClosed", true, false),
                ("commitmentPopoverOpen", true, true)
            ]
            var commitment: UUID?
            for (name, needsCommitment, popoverIsOpen) in states {
                if needsCommitment, commitment == nil {
                    commitment = try priorities.setPriority(intent: "Self-check tick survey")
                }
                let key = needsCommitment ? commitment : nil
                let first = tick(commitment: key, popoverIsOpen: popoverIsOpen)
                let steadyTicks = 9
                var cockpit = 0
                var nudge = 0
                var popover = 0
                for _ in 0..<steadyTicks {
                    let next = tick(commitment: key, popoverIsOpen: popoverIsOpen)
                    cockpit += next.cockpit
                    nudge += next.nudge
                    popover += next.popover
                }
                report[name] = [
                    // The non-vacuity control: every row under it is about ticks that fetch
                    // little or nothing, and a survey whose store answered nothing at all would
                    // satisfy all of them.
                    "firstTickFetches": first.cockpit + first.nudge + first.popover,
                    "firstTickCockpitFetches": first.cockpit,
                    "firstTickNudgeFetches": first.nudge,
                    "steadyTicks": steadyTicks,
                    "cockpitFetchesOverSteadyTicks": cockpit,
                    "nudgeFetchesOverSteadyTicks": nudge,
                    "popoverFetchesOverSteadyTicks": popover,
                    "fetchesOverSteadyTicks": cockpit + nudge + popover
                ]
            }
            report["available"] = true
        } catch {
            report["available"] = false
            report["error"] = "\(error)"
        }
        return report
    }

    /// **The badge's own surface, measured** (focus-5yu).
    ///
    /// The Release report carried `panel.contentSize` and **nothing at all** for the popover,
    /// which is the surface the quiet route sends every rung to — Reduce Motion, "Interrupt me
    /// less", the Silent-and-visual deck, a live microphone — and the one that had committed to
    /// no size. Measured before the repair, on a 1920 × 1080 display: 346 × 855 with a
    /// 21-character priority and 346 × 3127 with a long one, both placed as though they were
    /// about 340 tall, so most of each stood above the top of the screen.
    ///
    /// It is a **measurement of the shipping layout function**, not of an open popover: the
    /// popover opens only when a person clicks the status item, and a survey that clicked it
    /// would be reporting a click nobody made. `MenuBarController.popoverLayout(measuring:screens:)`
    /// is what `popoverController()` itself calls, on the same view, so the numbers here are the
    /// numbers the next click will produce.
    ///
    /// The content is the **fullest** the surface can hold — an accusation and a question at once
    /// beside a snooze — at a priority far longer than any interface expects, because
    /// `IntentValidator` bounds that sentence from below only.
    @MainActor
    static func popoverReport() -> [String: Any] {
        var report: [String: Any] = [:]
        let screens = NudgePanelController.currentScreens()
        report["committedWidth"] = MenuBarController.popoverContentWidth
        report["maximumContentHeight"] =
            MenuBarController.popoverMaximumContentHeight(screens: screens) ?? -1
        report["isShown"] = AppComposition.shared.menuBar.isPopoverShown
        // **The vocabulary, so the reading below is a claim and not a restatement of a type**
        // (focus-bkf). `overflow` was asserted by the gate as membership in a three-element set
        // written into the script — the entire codomain of a `CaseIterable` decoder, so no
        // product state could falsify it, which is focus-652's shape verbatim. Publishing the
        // cases lets the gate pin the vocabulary in both directions, as it does for
        // `ladderSilencesDeclared`: a case leaving is as red as a case joining, and the
        // membership test then reads the running binary's own enumeration rather than the
        // script's copy of it.
        report["overflowsDeclared"] = DecisionSurfaceOverflow.allCases.map(\.rawValue).sorted()
        report["rebuild"] = popoverRebuildSurvey()

        for (name, presentation) in popoverSurveyContents {
            let layout = MenuBarController.popoverLayout(
                measuring: MenuBarPopoverView(presentation: presentation).surfaceLayout,
                screens: screens
            )
            report[name] = [
                "width": Double(layout.size.width),
                "height": Double(layout.size.height),
                "scrolls": layout.scrolls,
                // **What gives way, not merely whether something does** (focus-din). A popover
                // that scrolls its own corrections can never be charged, so `scrolls` alone left
                // the report unable to tell a surface a person can decide on from one that has
                // parked the ladder. This names which of the three it is.
                "overflow": layout.overflow.rawValue,
                "decisionIsInTheViewport": layout.overflow.decisionIsInTheViewport,
                "isTheCommittedWidth":
                    Double(layout.size.width) == MenuBarController.popoverContentWidth
            ]
        }
        return report
    }

    /// **What an open popover costs per tick** (focus-tzj.1).
    ///
    /// ## The defect this measures
    ///
    /// `MenuBarController.update(_:)` is called on every accepted activation and every
    /// five-second corroboration tick, and while the popover was open each of those assigned a
    /// freshly built `NSHostingController` — plus the two `popoverLayout(measuring:)` builds to
    /// measure it. Three SwiftUI hosts every five seconds, thirty-six a minute, for a surface
    /// whose every input was the value it already had. It also re-stamped the layout generation,
    /// which throws away the action frames `decisionSurfaceReading(of:)` needs, so a popover the
    /// person was looking at read as unchargeable for the moment after each tick.
    ///
    /// ## Why it is measured this way
    ///
    /// The popover opens only when a person clicks the status item, and this launch clicks
    /// nothing — so the survey drives the two statements a tick makes while the popover is open,
    /// on a controller of its own: `update(_:traits:)`, which is what the composition root calls,
    /// and `refreshPopoverContent()`, which is what `update(_:)` itself calls once the popover is
    /// shown. Same functions, same staleness test, same builder. The counters are the
    /// controller's own — assignments, not requests — so a build that stopped happening shows up
    /// as a number and not as a promise.
    ///
    /// Ten ticks per presentation, two presentations: the first tick of each must build, because
    /// the presentation really did move, and the nine after it must build nothing at all.
    @MainActor
    static func popoverRebuildSurvey() -> [String: Any] {
        let controller = MenuBarController()
        let ticksPerPresentation = 10
        var ticks = 0
        var presentationChanges = 0
        var unchangedTicks = 0
        var buildsOnUnchangedTicks = 0
        for (_, presentation) in popoverSurveyContents {
            presentationChanges += 1
            for tick in 0..<ticksPerPresentation {
                let buildsBefore = controller.popoverContentBuildCount
                // The two statements `update(_:)` makes while the popover is open, in the order
                // it makes them.
                controller.update(presentation, traits: .systemDefault)
                controller.refreshPopoverContent()
                ticks += 1
                guard tick > 0 else { continue }
                unchangedTicks += 1
                buildsOnUnchangedTicks += controller.popoverContentBuildCount - buildsBefore
            }
        }
        return [
            "ticks": ticks,
            "presentationChanges": presentationChanges,
            "unchangedTicks": unchangedTicks,
            "contentBuilds": controller.popoverContentBuildCount,
            "buildsOnUnchangedTicks": buildsOnUnchangedTicks,
            // Three per build, and counted rather than assumed: the content is one host and the
            // two measurements are one each, because a wrapped height is not a number SwiftUI
            // will answer without one. Published so the amplification is visible — the tick's
            // real cost is this, not the build count.
            "hostingConstructions": controller.popoverHostingConstructions
        ]
    }

    /// The two contents the popover survey measures: the plainest thing this surface draws, and
    /// the fullest — with the longest priority, because that sentence is what used to set the
    /// width.
    static let popoverSurveyContents: [(String, MenuBarPresentation)] = {
        let priority = (["Write the Q3 proposal"] + Array(
            repeating: "and send the finance summary to the board before the review", count: 4
        )).joined(separator: " ")
        let subject = NudgeSubject.named(FocusStore.bundleIdentifier, runningName: nil)
        return [
            (
                "empty",
                MenuBarPresentation(status: .uncertain, priorityIntent: priority)
            ),
            (
                "fullest",
                MenuBarPresentation(
                    status: .unrelated,
                    priorityIntent: priority,
                    elapsed: .seconds(1_505),
                    snoozes: subject.map {
                        [MenuBarSnooze(subject: $0, remaining: .seconds(305))]
                    } ?? [],
                    pendingQuery: subject.map {
                        QueryPresentation(
                            task: priority,
                            subject: $0,
                            reason: .noNegativeBasis,
                            dwelled: .seconds(120)
                        )
                    },
                    pendingAccusation: AccusationPresentation(
                        rung: .panel,
                        task: priority,
                        subject: subject,
                        dwelled: .seconds(600),
                        returnTarget: "Pages",
                        hasOpenSession: true
                    ),
                    rung: .panel,
                    rungSurface: .popoverBadge,
                    band: .medium
                )
            )
        ]
    }()

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
        // The sentence the shipping path announces for this very presentation, because that is
        // what a real show does — a probe that showed the panel silently would be driving a
        // different call from the one the app makes (focus-tzj.7).
        panel.show(presentationIsClear: true, announcement: presentation.announcement())

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
        // **Whether reading 1 was taken at all**, which is the conjunct the delta below forgot.
        let frontWasReadBothTimes = before.frontmostWasRead && after.frontmostWasRead
        report["frontmostWasReadBothTimes"] = frontWasReadBothTimes

        // **Whose front moved, and in which direction** (focus-jax, focus-doy set B).
        //
        // The delta assertions below spend `panelSettleSeconds` — two and a half seconds of run
        // loop — between the two readings, and any application coming forward in that window
        // changes `frontmostBundleIdentifier` and flips `applicationIsActive`. Every delta then
        // fails, naming the panel for something a `.nonactivatingPanel` cannot do. focus-doy
        // measured it: the frontmost application went from this app to a Chrome PWA the app under
        // test cannot activate, and the gate reported two failures of R-89.
        //
        // A panel can only ever move the front TOWARD this process, so the direction decides —
        // and **there are four rows, not three** (focus-2uy.3):
        //
        //   the front was never read                nothing was measured — NOT TAKEN
        //   the front did not move                  the readings are about the panel, and taken
        //   the front moved and ended on US         the panel took it — a real R-89 failure
        //   the front moved and ended elsewhere     the world moved, and the reading is NOT TAKEN
        //
        // The first row used to fall into the second. `frontMoved` conjoins *was it read* into
        // *did it move*, so a run in which `NSWorkspace.shared.frontmostApplication` answered
        // `nil` at both ends produced *did not move* and published the delta as **taken** — a
        // reading that was never made, reported as made. Measured, gate run lens6-1:
        // `frontmostBeforeShow` and `frontmostAfterShow` both `null`,
        // `frontmostWasReadBothTimes` false, `deltaReadingWasTaken` **true**, and three
        // assertions failing on `(None, None)` — the gate naming R-89 for the fact that somebody
        // was using the Mac.
        //
        // The table itself is `SurfaceDeltaReading.evaluate(…)`, in `FocusCore`, so it is a pure
        // function of five measured values that a test process with no window server can fold
        // over the whole cross product; and its answer is a `ProbeOutcome`, which is the one
        // mechanism this programme has for a reading a machine may not let it take. What stays
        // here is the reading of the live AppKit values.
        //
        // Reading 3 — the panel is not the key window — needs none of this and stays absolute,
        // and so does §4.5's `focus-steal` stage, which makes R-89's claim from outside the
        // process against an app launched with `open -g -a` and never brought forward at all.
        let ourIdentifier = Bundle.main.bundleIdentifier ?? ""
        let frontMoved = frontWasReadBothTimes
            && before.frontmostBundleIdentifier != after.frontmostBundleIdentifier
        report["frontMovedDuringTheShow"] = frontMoved
        let deltaReading = SurfaceDeltaReading.evaluate(
            frontWasReadBefore: before.frontmostWasRead,
            frontWasReadAfter: after.frontmostWasRead,
            frontBefore: before.frontmostBundleIdentifier,
            frontAfter: after.frontmostBundleIdentifier,
            ourIdentifier: ourIdentifier
        )
        report["deltaReadingWasTaken"] = deltaReading.wasTaken
        // The obstacle's own sentence, and then the two identifiers it is about, so a NOT TAKEN
        // line in the stage log names the case *and* the applications that produced it.
        report["deltaNotTakenBecause"] = deltaReading.obstacle.map { obstacle in
            obstacle.sentence
                + ": \(before.frontmostBundleIdentifier ?? "none") -> "
                + "\(after.frontmostBundleIdentifier ?? "none")"
        } ?? ""
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
        // **One of the four inputs the capability matrix is computed from** (focus-gtr).
        //
        // `PlatformCapabilityProbe` answers `.displayGeometry` with
        // `displays.isEmpty ? .unavailable : .available`. The gate can only check that the matrix
        // agrees with the rule if it can see the rule's inputs, and the other three
        // (`windowMetadata.count`, `idle.hardwareSeconds`, `media.inputDeviceCount`) are already
        // in this report. This is the fourth, read through AppKit rather than through the probe's
        // own `SystemScreenList`, so the comparison is between two readings and not a mirror.
        report["displayCount"] = NSScreen.screens.count
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
        // Always present, `""` when the reading was taken, for the reason the pair exists at all:
        // a gate stage routes every one of these through one mechanism, and a key that appears
        // only on the failing branch is a key that stage cannot fold over (focus-2uy.3).
        windowMetadata["countNotTakenBecause"] = host.frontmostReadingObstacle?.rawValue ?? ""
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
                "isPresenting": state.isPresenting,
                // The same pair every other unavailable reading in this report publishes, so the
                // gate routes this one through the one NOT-TAKEN mechanism rather than through a
                // branch of its own (focus-2uy.3).
                "wasTaken": true,
                "notTakenBecause": ""
            ]
        } else {
            // `suppressed: true` alone said "the gate stood down" about a graph that in the
            // measured failure had simply never been told who was frontmost — the same
            // conflation `-1` made above, in words instead of a number. The reason travels with
            // it now, and a reader can tell the gate working from the graph knowing nothing.
            report["presentation"] = [
                "suppressed": true,
                "wasTaken": false,
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
    /// for the processes macOS puts an authorisation dialog on the screen through. The list of
    /// suspects is asserted **empty** while the app runs.
    ///
    /// It goes through `SystemWindowList` and `WindowMetadataReader.decode`, which are the only
    /// route in this programme to `CGWindowListCopyWindowInfo` and which decode seven keys, none
    /// of them a window name. There is no way to reach a title from here even by accident.
    ///
    /// ## Why it publishes a takenness fact and a control, and did not
    ///
    /// The whole reading used to be two arrays, and the gate asserted `suspects == []`. **An
    /// empty scan satisfies that.** `SystemWindowList.copyWindowInfo()` answers `[]` when the
    /// cast fails or the window server declines, `owners` is then empty, `suspects` is empty, and
    /// the strongest form of R-33 prints a green line for a reading nobody took. That is not
    /// hypothetical here: `sensing.windowMetadata` grew `countWasTaken` in focus-2vi for exactly
    /// this call coming back with nothing, and gate run `lens6-1` recorded the Debug launch
    /// unable to read the window list while the Release launch of the same tree could. One
    /// consumer of `CGWindowListCopyWindowInfo` was given the takenness treatment and the other
    /// was not.
    ///
    /// So two facts travel with the verdict:
    ///
    /// * `wasTaken` — the scan enumerated somebody. Empty is NOT TAKEN, routed through the one
    ///   door with every other reading the machine may refuse (focus-2uy.3), never a pass.
    /// * `windowsOwnedByThisProcess` — **the control, and it is by PID rather than by name.**
    ///   This process has a window on the screen at the moment of the reading by construction:
    ///   the shell self-check has brought the cockpit forward. An instrument that cannot see the
    ///   window it is standing next to cannot be trusted to see an authorisation dialog either,
    ///   and a name comparison would be the wrong instrument — `kCGWindowOwnerName` is the
    ///   *display* name (measured: `Focus Sentinel`, with a space), which is a localisable string
    ///   and would make the control drift with the copy.
    ///
    /// The two seams exist so the **witness suite** can drive every outcome of this reading
    /// without a window server: an empty scan, a scan that cannot see this process, and a scan
    /// that names a dialog owner. A repair whose failing state cannot be produced is the shape
    /// this whole round is about.
    @MainActor
    static func authorisationSurfaceReport(
        rows: [WindowMetadataValue]? = nil,
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> [String: Any] {
        let rows = rows ?? WindowMetadataReader.decode(SystemWindowList().copyWindowInfo())
        let owners = Array(Set(rows.map(\.ownerName))).sorted()
        let suspects = owners.filter { owner in
            authorisationSurfaceOwners.contains { owner.localizedCaseInsensitiveContains($0) }
        }
        let ownWindows = rows.count { $0.ownerPID == ownProcessIdentifier }
        return [
            "wasTaken": !owners.isEmpty,
            "notTakenBecause": owners.isEmpty
                ? "the on-screen window list named no owner at all"
                : "",
            "ownerCount": owners.count,
            "owners": owners,
            "ownProcessIdentifier": Int(ownProcessIdentifier),
            "windowsOwnedByThisProcess": ownWindows,
            "suspects": suspects
        ]
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
        // **Read off the cockpit, never off `NSApp.keyWindow`** (focus-jax).
        //
        // This is the sixth of the six assertions the gate failed twice in five runs on a tree
        // whose wiring was correct. `NSApp.keyWindow` is `nil` in an application that is not
        // active, so a reading taken through it turns "another app came forward" into "the
        // cockpit never handed the journal its manager" — a sentence about a wire, made out of a
        // fact about the machine. The cockpit window exists either way, and it is the window
        // whose manager the claim is about, so it is the one the reading is taken through.
        report["undoManagerIsTheCockpitWindows"] =
            liveCockpitWindow() != nil
            && composition.priorityHost.journalUndoManager === liveCockpitWindow()?.undoManager
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
        //
        // **Both sides of the comparison used to be the same value** (focus-8ry).
        // `appearanceTraitsMatchTheSystem` was `traits.colorScheme ==
        // composition.appearance.preference.resolvedColorScheme(system:)` — the observer's own
        // in-memory preference resolved against the system and compared with the traits that
        // preference had just produced. It reported `true` on the launch that drew a person's
        // stored Light as Dark, and it could not have reported anything else: an equation with
        // one variable on both sides is not a reading. The **stored** preference is the person's
        // choice, so it is the one the shell is judged against.
        let traits = composition.appearance.traits
        let stored = composition.storedAppearancePreference()
        report["appearancePreference"] = composition.appearance.preference.rawValue
        report["appearanceRefreshCount"] = composition.appearance.refreshCount
        report["appearanceColorScheme"] = traits.colorScheme.rawValue
        report["appearanceSystemColorScheme"] = AppearanceObserver.systemColorScheme.rawValue
        report["appearanceTraitsMatchTheSystem"] =
            traits.colorScheme == stored.resolvedColorScheme(system: AppearanceObserver.systemColorScheme)
        report["storedAppearancePreference"] = stored.rawValue
        // **The two values that were printed side by side and never compared** (focus-8ry). The
        // note under them said "(recorded, never asserted)" in as many words, and they disagreed
        // on every seeded launch of the defect. Asserting it here is what makes the shell's live
        // preference answerable to the store on the ordinary launch as well as the seeded one.
        report["appearancePreferenceIsTheStored"] = composition.appearance.preference == stored

        // **Something in this process can open the cockpit** (focus-mwm).
        //
        // The popover's *"Open Focus Sentinel"* button, whose string's comment reads "bring the
        // main window forward", asks `FocusCommandCenter.requestCockpit()` for one — and the only
        // thing that can answer is the closure `ShellCommands` installs out of SwiftUI's
        // `openWindow`. It has to be SwiftUI's: this lane measured a launch inheriting a closed
        // cockpit where `NSApp.windows` held only the menu-bar item, so there was no `NSWindow`
        // for AppKit to order front and only `openWindow(id:)` could make one.
        //
        // A `Commands` body is evaluated when AppKit builds the main menu, at launch, whether the
        // cockpit is open or not — which is the property the wire needs and the property this
        // reading is about. Nothing else in the programme can observe it: `ShellCommands` lives in
        // a scene, and a unit process has no scene.
        report["canRaiseCockpit"] = FocusCommandCenter.shared.canRaiseCockpit

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
        // **The version the General pane really drew** (focus-odz.3).
        //
        // `drewWhatTheAppKnows` already says the pane agreed with the composition root, and that
        // is not the whole claim: the root and the pane could agree on a constant. This is the
        // string on the screen, and the gate pins it against `Bundle.main`'s own answer read
        // outside the connection — two independent readings of one artefact.
        report["settingsDrewnVersion"] =
            composition.shellRenderings[.settings]?[.appVersion] ?? ""

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
    /// **And the one it did not press** (focus-z7g). This probed `.setVoice` and
    /// `.setReducedInterruption` and skipped `.setQuietHours` — precisely the action that did
    /// nothing — so the pane's dead button was the one control in the pane no lane touched.
    /// Every case of `InterventionSettingsAction` a person can reach is driven here now.
    ///
    /// Quiet hours is read at **three** depths, because two of them were separately capable of
    /// being green over a dead control: the loop's own field, the `NudgeSurroundings` the
    /// suppression stack is actually handed, and the row on disk. A setting that reaches the
    /// first and not the second is a gate that can never fire; one that reaches the first two
    /// and not the third is a setting the person loses when they quit.
    ///
    /// **All three write the person's row and are put back** (focus-40i), which is the same
    /// shape `pressTheAppearancePicker()` uses and for the same reason: the claim is about a
    /// store, and no in-process read-back can make it. The voice and the flag were read only
    /// out of the running loop here — a reading a plain in-memory property satisfies perfectly,
    /// which is exactly how "never persisted" survived every gate this probe has ever run in.
    ///
    /// The stored flag is compared against **what the person chose**, never against
    /// `preferences.reducedInterruption`: that value is the choice *or* what Reduce Motion
    /// forces, so on a Mac with Reduce Motion on the two are legitimately different and a probe
    /// that conflated them would report a defect on somebody's accessibility setting.
    @MainActor
    static func driveInterventionSink() -> [String: Any] {
        let composition = AppComposition.shared
        var report: [String: Any] = [:]

        guard let sinks = composition.settingsSinks else {
            report["available"] = false
            return report
        }
        report["available"] = true

        // **What the person chose**, which is what has to be put back at the end. Read off the
        // host's own statement of it rather than off `preferences`, whose reduced-interruption
        // field is the choice OR what Reduce Motion forces: restoring that would write the Mac's
        // accessibility setting into the person's row as though they had picked it.
        let chosenBefore = composition.nudgeHost.chosen
        let voiceBefore = composition.nudgeHost.preferences.voice
        let reducedBefore = composition.nudgeHost.preferences.reducedInterruption
        let voiceProbe: NudgeVoice = voiceBefore == .standard ? .silentVisual : .standard
        let reducedProbe = !reducedBefore

        sinks.onInterventionAction(.setVoice(voiceProbe))
        report["voiceProbe"] = voiceProbe.rawValue
        report["voiceAfter"] = composition.nudgeHost.preferences.voice.rawValue
        report["voiceReachedTheLoop"] = composition.nudgeHost.preferences.voice == voiceProbe
        report["voiceStored"] = FocusStore
            .interventionPreferences(in: composition.modelContainer.mainContext).voice.rawValue
        report["voiceReachedTheStore"] = FocusStore
            .interventionPreferences(in: composition.modelContainer.mainContext).voice == voiceProbe

        sinks.onInterventionAction(.setReducedInterruption(reducedProbe))
        report["reducedProbe"] = reducedProbe
        report["reducedAfter"] = composition.nudgeHost.preferences.reducedInterruption
        report["reducedReachedTheLoop"] =
            composition.nudgeHost.preferences.reducedInterruption == reducedProbe
        report["reducedStored"] = FocusStore
            .interventionPreferences(in: composition.modelContainer.mainContext)
            .reducedInterruption
        report["reducedReachedTheStore"] = FocusStore
            .interventionPreferences(in: composition.modelContainer.mainContext)
            .reducedInterruption == reducedProbe

        // **Gate 8's own input, driven** (focus-z7g). The probe is the window the pane's own
        // button emits, so this is the shipping path rather than a value invented here.
        let quietBefore = composition.nudgeHost.quietHours.window
        let quietProbe: QuietHoursWindow? =
            quietBefore == nil ? InterventionSettingsView.startingWindow : nil

        report["quietHoursStoredBefore"] = FocusStore
            .interventionPreferences(in: composition.modelContainer.mainContext)
            .quietHours?.encoded ?? "none"

        sinks.onInterventionAction(.setQuietHours(quietProbe))
        report["quietHoursProbe"] = quietProbe?.encoded ?? "none"
        report["quietHoursAfter"] = composition.nudgeHost.quietHours.window?.encoded ?? "none"
        report["quietHoursReachedTheLoop"] = composition.nudgeHost.quietHours.window == quietProbe
        // The value the twelve-gate stack is handed, not the field the loop stores it in.
        report["quietHoursInSurroundings"] =
            composition.nudgeSurroundings().quietHours.window?.encoded ?? "none"
        report["quietHoursReachedTheGate"] =
            composition.nudgeSurroundings().quietHours.window == quietProbe
        // The row on disk, which is the only reading that can tell a stored setting from a
        // remembered one.
        report["quietHoursStored"] = FocusStore
            .interventionPreferences(in: composition.modelContainer.mainContext)
            .quietHours?.encoded ?? "none"
        report["quietHoursReachedTheStore"] = FocusStore
            .interventionPreferences(in: composition.modelContainer.mainContext)
            .quietHours == quietProbe

        composition.perform(.setVoice(chosenBefore.voice))
        composition.perform(.setReducedInterruption(chosenBefore.reducedInterruption))
        composition.perform(.setQuietHours(chosenBefore.quietHours))
        let stored = FocusStore.interventionPreferences(
            in: composition.modelContainer.mainContext
        )
        report["restored"] = composition.nudgeHost.chosen == chosenBefore
            && stored == chosenBefore
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

    /// How long a self-check will wait for `getNotificationSettings` to answer before it reports
    /// the authorisation as unread. P-134 measured the call answering in single-digit
    /// milliseconds at zero grants; this is two orders of magnitude of headroom, and running out
    /// of it is a reportable fact rather than a hang.
    static let notificationReadDeadline: TimeInterval = 3

    /// **Wait for the notification read to land before reporting what it said** (focus-652).
    ///
    /// `AppComposition.start()` fires `NotificationDelivery.refresh()` and returns; the completion
    /// arrives on a later turn of the main run loop. Nothing sequenced that against report
    /// assembly, so `notificationAuthorisation` was not this Mac's grant state at all — it was
    /// **which side of a race the report was assembled on**. Measured across five gate runs at one
    /// commit on one machine: `notRequested`, `notRequested`, `authorised`, `notRequested`, with
    /// the two reports of a single run disagreeing with each other, and nineteen green stages
    /// every time.
    ///
    /// So the report waits. It re-issues the read rather than assuming the launch one is still in
    /// flight — a completion that already landed makes this return on the first line — and it
    /// spins the run loop rather than sleeping, because the completion is delivered *on* that run
    /// loop and `Thread.sleep` would guarantee the timeout it is trying to avoid.
    ///
    /// Returns whether a read landed. The caller publishes that; it never guesses on its behalf.
    @MainActor
    @discardableResult
    static func awaitNotificationAuthorisation(
        within seconds: TimeInterval = notificationReadDeadline
    ) -> Bool {
        let host = AppComposition.shared.nudgeHost
        if host.notificationAuthorisationReads > 0 { return true }
        AppComposition.shared.refreshNotificationAuthorisation()
        let started = ProcessInfo.processInfo.systemUptime
        while host.notificationAuthorisationReads == 0 {
            if ProcessInfo.processInfo.systemUptime - started >= seconds { return false }
            settle(forSeconds: notificationReadPollInterval)
        }
        return true
    }

    /// One turn of the run loop per poll, no more: the completion is dispatched onto it.
    static let notificationReadPollInterval: TimeInterval = 0.02

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
    ///
    /// ## The two preconditions beside that one, which were reported and never asked (focus-jax)
    ///
    /// The paragraph above stated *one* precondition — the field editor — and the gate asserts it.
    /// `applicationIsActive` and `hasKeyWindow` sat in the same dictionary, reported and asserted
    /// by nobody, and they are the two that failed: five gate runs on one tree, runs 2 and 3 red
    /// on the same six assertions, `undoManagerTitle` reading `Undo Change Priority` in all ten
    /// readings. The wiring was correct every time. The app had come forward at launch — the
    /// `activation` block passed — and had lost the front again by the time this probe ran, which
    /// is a fact about the Mac and not about the Edit menu.
    ///
    /// So the reading is split in two, and each half says what it needs:
    ///
    /// * **Front-free.** `cockpitUndoManagerIsJournal`, `undoManagerTitle` and
    ///   `undoManagerTitleAfterUndo` are facts about objects. They are taken and asserted in every
    ///   run, and a regression in `adoptUndoManager` or in the journal's action name fails on them
    ///   whatever this machine was doing with its front.
    /// * **Front-bound.** Only AppKit's own validation — the four title and enablement readings off
    ///   the live menu item — needs the app active with the cockpit key. Those state their
    ///   precondition through `menuReadingWasTaken`, the front is *asked for again* immediately
    ///   before they are taken, and an obstacle that outlasts `frontRecoveryDeadline` makes them
    ///   **NOT TAKEN** rather than six failures of unrelated code. A machine that never lets the
    ///   app forward at all still fails, loudly, on the `activation` block — this is only about
    ///   losing a front that was already won.
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
        // Before the guard, so a run in which the journal holds nothing still says whether the
        // window it should have come from was there.
        let cockpit = liveCockpitWindow()
        report["cockpitWindowExists"] = cockpit != nil

        let manager = AppComposition.shared.priorityHost.journalUndoManager
        guard let manager else {
            report["available"] = false
            report["menuReadingWasTaken"] = false
            report["menuReadingNotTakenBecause"] = "the priority journal has no undo manager"
            return report
        }
        report["available"] = true
        report["groupsByEvent"] = manager.groupsByEvent

        // --- the half of F-93 that needs nothing from the window server ----------------------
        //
        // **Taken in every run, including one where the menu cannot be read** (focus-jax). The
        // claim "the journal is the manager the cockpit hands to the responder chain" is a fact
        // about objects, not about who is frontmost, and it is the half a regression in
        // `adoptUndoManager` breaks. Reading it off `liveCockpitWindow()` rather than off
        // `NSApp.keyWindow` is what makes it front-free: the cockpit exists whether or not this
        // process is active, and the key window does not.
        report["cockpitUndoManagerIsJournal"] = cockpit != nil && cockpit?.undoManager === manager

        // --- the preconditions of the half that does, asked before it is taken ---------------
        //
        // `comeForward` established the front at launch and `activation` records that it worked;
        // by the time this probe runs, a second and a half of run loop later, another application
        // may have taken it back. That is an ordinary event on a Mac and it is not a defect in
        // the Edit menu, so it is asked for again and then **stated**.
        let frontRegained = regainFront()
        report["frontRegained"] = frontRegained
        report["applicationIsActive"] = NSApp.isActive
        report["hasKeyWindow"] = NSApp.keyWindow != nil
        let obstacleBefore = editMenuObstacle()

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

            // Front-free, and therefore asserted in every run: the action name P-50 measured is
            // one the *manager* carries, and `undoMenuItemTitle` is the sentence AppKit would
            // build out of it. A journal that stopped naming its operations fails here whether
            // or not this Mac let the app keep the front.
            report["actionName"] = manager.undoActionName
            report["undoManagerTitle"] = manager.undoMenuItemTitle
            report["canUndo"] = manager.canUndo
            let afterMutation = editMenuUndoItem()
            report["menuItemTitle"] = afterMutation?.title ?? ""
            report["enabled"] = afterMutation?.isEnabled ?? false

            if manager.canUndo { manager.undo() }

            report["undoManagerTitleAfterUndo"] = manager.undoMenuItemTitle
            report["canUndoAfterUndo"] = manager.canUndo
            let afterUndo = editMenuUndoItem()
            report["menuItemTitleAfterUndo"] = afterUndo?.title ?? ""
            report["enabledAfterUndo"] = afterUndo?.isEnabled ?? false
        } catch {
            report["available"] = false
            report["error"] = "\(error)"
        }

        // **Asked again at the far end, because the front can be lost mid-reading** (focus-jax).
        //
        // Everything between the two questions is one `menuItemTitle` after another, and the
        // obstacle that matters is the one that was in the way when they were taken — not the one
        // in the way when the probe started. Both ends clear is the only state in which the four
        // title-and-enablement readings below describe an Edit menu somebody validated; anything
        // else, and they describe a background application's menu bar, which is `Undo`, disabled,
        // however many operations the journal holds.
        let obstacleAfter = editMenuObstacle()
        let obstacle = obstacleBefore.isEmpty ? obstacleAfter : obstacleBefore
        report["menuReadingWasTaken"] = obstacle.isEmpty
        report["menuReadingNotTakenBecause"] = obstacle

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

    /// **What the app would accept right now, per registered action** (focus-6uf).
    ///
    /// The other half of the menu reading. `menuTree()` says what the menu bar *drew*; this says
    /// what `ShellAction.isAvailable(in:)` answered for the world the app is in — the same
    /// predicate `ShellActionButton` disabled on, the same one `CockpitView.perform(_:)` and
    /// `NudgeHost.perform(_:)` refuse on. The gate holds the two up beside each other, per item,
    /// over the whole registry.
    ///
    /// It reports the **world** as well as the verdict, because a per-item comparison against a
    /// predicate is satisfied by a predicate that answers the same thing for every state. The
    /// world is what lets a reader see which state was measured, and it is what the gate's floor
    /// on "some item is withdrawn" is read against.
    @MainActor
    static func commandAvailabilityReport() -> [String: Any] {
        let world = FocusCommandCenter.shared.world
        let registry = CommandRegistry.shell
        return [
            "world": [
                "hasPriority": world.hasPriority,
                // `"none"` rather than a null, so the field is a string in both cases and a gate
                // reading it never has to decide what an absent phase means.
                "sessionPhase": world.sessionPhase?.rawValue ?? "none",
                "hasOpenNudge": world.hasOpenNudge
            ],
            "actions": registry.actions.map { action in
                [
                    "id": action.id,
                    // The resolved title, because that is the only key the menu tree can be
                    // joined on: `NSMenuItem.title` is a `String` and a registry entry is a
                    // `ShellStringKey`, and a gate matching them by hand would be a third table.
                    "title": String(localized: action.title),
                    "placement": action.placement.rawValue,
                    "isAvailable": action.isAvailable(in: world)
                ]
            }
        ]
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

        // **An appearance as well as a session** (focus-8ry).
        //
        // The setting the person changes and the app has to hand back at the next launch. It is
        // written here, into the same store, because the *only* reading that can tell "restored"
        // from "never read" is a second process opening a store the first one wrote — and this
        // lane already spans two. Written through the shipping verb, so a store this seed
        // produces is one the app could have produced.
        try FocusStore.setAppearancePreference(
            seededAppearancePreference,
            in: context,
            now: wallNow
        )

        // **And a record of which windows were open when this store's app last quit**
        // (focus-odz.6).
        //
        // The same trick as the appearance above, for the same reason: the only reading that can
        // tell "restored" from "never asked" is a second process opening a store the first one
        // wrote, and this lane already spans two. The list names **both** scenes on purpose. The
        // cockpit is the control — SwiftUI opens it itself, so a launch that restored nothing at
        // all would still have one — and the Keyboard Shortcuts window is the claim, because
        // nothing else in a `--focus-self-check-cockpit` launch opens it.
        try FocusStore.recordOpenWindows(
            seededOpenWindows,
            in: context,
            now: wallNow
        )

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
            "openWindows": seededOpenWindows,
            "sessionID": sessionID.uuidString,
            "priorityIntent": seededPriorityIntent,
            "appearancePreference": seededAppearancePreference.rawValue,
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
        // **Put back the scenes the person left open** (focus-odz.6). One turn of the run loop
        // later, because the opener it needs lives in a `Commands` body SwiftUI has not evaluated
        // yet and the cockpit window it must not re-ask for does not exist yet either. It runs in
        // every mode, including the self-check's, which is the only lane that can observe it.
        DispatchQueue.main.async {
            // Submitted to the main queue on the line above.
            MainActor.assumeIsolated { FocusAppDelegate.restoreWindowsAfterLaunch() }
        }

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
                    // Submitted to the main queue on the line above.
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
                // Submitted to the main queue on the line above.
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

    /// **Clicking the Dock icon with every window shut opens the cockpit** (focus-odz.1, D5).
    ///
    /// The pair of decisions above left a hole a person falls into on their first ⌘W: the app
    /// keeps a Dock icon (D5 — the cockpit has menus and Undo, so an accessory app would be the
    /// wrong shape), and `applicationShouldTerminateAfterLastWindowClosed` answers `false`, so
    /// after ⌘W the application is running with no window and nothing on the Dock icon brings one
    /// back. AppKit's own reopen behaviour cannot help: a SwiftUI `Window` scene whose window has
    /// been closed has **no `NSWindow` at all** for AppKit to unminiaturise or order front — the
    /// same measurement `FocusCommandCenter.registerCockpitOpener` is written against — so the
    /// only thing that can make one is `openWindow(id:)`.
    ///
    /// So the reopen goes down the **same route the popover's "Open Focus Sentinel" takes**:
    /// `requestCockpit()`, which is the one place in the application that holds SwiftUI's opener.
    /// Not `NSApp.activate` and not `makeKeyAndOrderFront` — R-96e and R-96m ban both outside two
    /// pinned files, and neither would help anyway when there is no window to order.
    ///
    /// **`false` in both arms, and both are decisions.** With windows already visible there is
    /// nothing to do and AppKit's default (unminiaturise the front window) is the right one to
    /// decline, because this app's windows are never miniaturised into a document proxy somebody
    /// is waiting on. With none visible, this has just asked for the window itself, and answering
    /// `true` would ask AppKit to perform its own untitled-window behaviour on top of it.
    public func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        guard !hasVisibleWindows else { return false }
        FocusCommandCenter.shared.requestCockpit()
        return false
    }

    /// **Quit is an exit of the nudge loop, and it was the only one with no door** (focus-gmr).
    ///
    /// Nothing in the programme reached `NudgeHost` from a termination, so an unopened badge
    /// invitation at quit wrote no `unopened` row and a nudge on screen at quit left its record at
    /// `delivered` with no outcome for ever. A day on which the app raised its top rung and the
    /// person quit without looking read exactly like a day the ladder never left the glyph.
    ///
    /// The guard is `AppComposition.isRunning` and not `AppComposition.shared`: `shared` is a
    /// `static let`, so reading it here would build a whole composition root — a store, a graph,
    /// an observer set — in the reduced self-check modes that never started one, at the moment
    /// the process is trying to leave.
    public func applicationWillTerminate(_ notification: Notification) {
        guard AppComposition.isRunning else { return }
        AppComposition.shared.nudgeHost.applicationWillTerminate()
        // **Which scenes were on screen when they left** (focus-odz.6). AppKit restores a
        // window's frame and not whether a SwiftUI `Window(id:)` scene exists at all, so the
        // existence half is written down here and asked for again at launch. The window list is
        // read here because this is the file that imports AppKit; what counts as a scene worth
        // recording is `ShellWindowRestoration.recordable(_:)`.
        AppComposition.shared.recordOpenWindows(Self.visibleSceneIdentifiers())
    }

    /// Every scene identifier currently on screen.
    ///
    /// `isVisible` and not merely present: a `Window` scene that has been closed can linger in
    /// `NSApp.windows` as an invisible object, and recording it would restore a window the person
    /// had shut.
    @MainActor
    static func visibleSceneIdentifiers() -> [String] {
        NSApp.windows.filter(\.isVisible).compactMap { $0.identifier?.rawValue }
    }

    /// **Ask for the scenes that were open at the last quit** (focus-odz.6).
    ///
    /// Scheduled a run-loop turn after launch rather than run inside
    /// `applicationDidFinishLaunching`, and the delay is load-bearing twice over. SwiftUI has not
    /// installed `NSApp.mainMenu` at that notification — which is the measurement
    /// `applicationDidBecomeActive` above is written against — and the opener this needs is
    /// installed by a `Commands` body, which is evaluated when that menu is built. Reading the
    /// window list is the same story from the other end: the cockpit scene does not exist yet, so
    /// "already open" would answer empty and the restoration would ask for a window that is on its
    /// way.
    ///
    /// Guarded on `AppComposition.isRunning` for `applicationWillTerminate`'s reason: `shared` is
    /// a `static let`, so reading it in a reduced self-check mode that never started a root would
    /// build a whole store and observer graph to restore a window that mode has no scene for.
    @MainActor
    static func restoreWindowsAfterLaunch() {
        guard AppComposition.isRunning else { return }
        AppComposition.shared.restoreWindows(alreadyOpen: visibleSceneIdentifiers())
    }
}
