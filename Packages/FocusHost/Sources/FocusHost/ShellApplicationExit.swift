import AppKit

/// **Leaving, as a verb something other than the app menu can call** (focus-odz.2).
///
/// One line of AppKit, in a file of its own, because `AppComposition` deliberately does not
/// import AppKit: the composition root wires hosts together and a root able to talk to
/// `NSApplication` directly is a root that will grow a second surface. It imports `FocusUI` for
/// the views and this package's own AppKit files for the two things a menu bar needs — the Help
/// menu's automatic item, and now the way out.
///
/// It is a stored closure on the root rather than a call at the point of use so that
/// `MenuBarActionTotalityTests` can drive **every** `MenuBarAction` through the wire the status
/// item calls without terminating its own test runner. Leaving Quit out of that fold would be
/// exactly the hole the suite exists to close.
///
/// `NSApp.terminate(nil)` rather than `exit(0)`: it runs the ordinary termination sequence, so
/// `applicationWillTerminate` still fires and the nudge loop still writes the outcome of anything
/// that was on screen (focus-gmr). Quitting from the status item is the same exit as quitting
/// from anywhere else, which is the whole reason the item is allowed to exist.
public enum ShellApplicationExit {
    @MainActor
    public static func terminate() {
        NSApp.terminate(nil)
    }
}
