import AppKit
import FocusUI
import Foundation

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
        // **How delete-everything replaces the process** (e07a, focus-6pr.3). Installed here
        // because this is the file that imports AppKit: a new instance of this bundle is asked
        // for, and this one leaves once the request has been accepted. Guarded the way the
        // termination hook is, so a reduced self-check mode never builds a composition root to
        // hand it a closure it will not use.
        if AppComposition.isRunning {
            AppComposition.shared.relaunch = {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.createsNewApplicationInstance = true
                NSWorkspace.shared.openApplication(
                    at: Bundle.main.bundleURL,
                    configuration: configuration
                ) { _, _ in
                    DispatchQueue.main.async { NSApp.terminate(nil) }
                }
            }
        }
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
                // **"No prompt of any kind", measured rather than counted** (focus-p3dl). This is
                // the launch `check-notification-denied.sh` drives every rung of the ladder in,
                // and the only thing that said no permission dialog appeared during it was a
                // counter the app increments itself. The scan is a delta against the baseline the
                // launching script took before this process existed, so a dialog belonging to
                // somebody else's tool is excused by name and one that ARRIVED is not.
                report["authorisationSurfaceScan"] = SelfCheck.authorisationSurfaceReport()
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
        // **Nothing is written into a store that has just been destroyed** (e07a, focus-6pr.3).
        // Delete-everything ends in a relaunch, and the two writes below would be the first
        // rows in the rebuilt file — a record of the quit, and the window list — written by
        // contexts built on the container that no longer exists.
        guard !AppComposition.shared.hasDeletedEverything else { return }
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
