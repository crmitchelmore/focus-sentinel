// FocusDecoy — a real distraction, committed (R-97, F-154).
//
// The charter's live lane says *"simulate distraction by actually opening a decoy app and
// asserting the nudge fires"*. A decoy fabricated at run time is a decoy nobody can re-run, so
// this one is a committed source file that builds into a real ordinary `.regular` application
// with a real window that really enters a real full-screen space.
//
// ## What it is for, and what makes it different from FocusDecoy2
//
// This is the **seeded-unrelated** subject the ladder scenarios need. Its bundle identifier is
// planted as an `unrelated` rule by the driver's fixtures, so it produces the `unrelated` verdict
// that mandates — which means it can never produce the `uncertain` verdict the query scenario
// needs. That is why there are two decoys and not one: adversarial review walked the original
// sixteen-frame list and found scenario S6 unreachable for exactly this reason.
//
// ## Why it can enter a full-screen space
//
// P-130 measured that `.fullScreenAuxiliary` is exactly the flag that lets a panel stomp a
// presentation, and P-131 measured the menu-bar layer's owners collapsing from eleven to one while
// our own status item stayed *listed* as on screen. Both measurements were taken against **this
// application** owning a real full-screen space, and frame 15 re-runs that scenario against the
// shipped build: the decoy's space must be clean, the rung must be recorded as `deferred`, and the
// ladder must not have advanced.
//
// `--fullscreen` puts the window into its own space a moment after launch, so the driver never
// needs Accessibility to get it there — `toggleFullScreen(_:)` is the application asking for
// itself, not another process asking on its behalf.
//
// ## It reads nothing and reaches for nothing
//
// No sensing, no window list, no networking, no accessibility. It draws a coloured view, holds a
// window, and exits when it is told to. Everything it does is something an ordinary application
// does.

import AppKit

let arguments = Set(CommandLine.arguments.dropFirst())

final class DecoyDelegate: NSObject, NSApplicationDelegate {
    let window: NSWindow

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window.title = "Focus Decoy"
        // `.fullScreenPrimary` is what makes `toggleFullScreen(_:)` produce a real space rather
        // than a zoomed window — which is the difference between reproducing P-130 and merely
        // making a large window.
        window.collectionBehavior = [.fullScreenPrimary, .managed]

        let content = NSView(frame: window.contentLayoutRect)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.systemIndigo.cgColor
        content.autoresizingMask = [.width, .height]

        let label = NSTextField(labelWithString: "FocusDecoy — the distraction, on purpose")
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])
        window.contentView = content

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        guard arguments.contains("--fullscreen") else { return }
        // A turn of the run loop first: `toggleFullScreen(_:)` on a window that has not yet been
        // presented is a no-op, and a driver waiting for a space that never arrives would abort a
        // scenario for a reason that has nothing to do with the app under test.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [window] in
            window.toggleFullScreen(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let application = NSApplication.shared
let delegate = DecoyDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
