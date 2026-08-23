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

    /// The output path, if this process was asked for a self-check.
    static var requestedOutputPath: String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: argument) else { return nil }
        let next = arguments.index(after: index)
        guard next < arguments.endIndex else { return nil }
        return arguments[next]
    }

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
        let claims = keyEquivalentClaims()

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
        return root
    }

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
    @MainActor
    static func undoReport() -> [String: Any] {
        var report: [String: Any] = [:]

        let manager = AppComposition.shared.priorityHost.journalUndoManager
            ?? NSApp.keyWindow?.undoManager
        guard let manager else {
            report["available"] = false
            return report
        }
        report["available"] = true
        report["groupsByEvent"] = manager.groupsByEvent
        report["applicationIsActive"] = NSApp.isActive
        report["hasKeyWindow"] = NSApp.keyWindow != nil

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

    // MARK: - Running it

    @MainActor
    static func runAndTerminate(writingTo path: String, activation: Activation) {
        // The key-equivalent probes perform real commands, and one of them can open a file
        // importer. A sheet still up when `NSApp.terminate` runs is how a self-check turns into
        // a hung gate stage, so every attached sheet is dismissed first.
        for window in NSApp.windows {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
        }

        do {
            let data = try JSONSerialization.data(
                withJSONObject: report(activation: activation),
                options: [.prettyPrinted, .sortedKeys]
            )
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
final class FocusAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let path = SelfCheck.requestedOutputPath else { return }

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
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
