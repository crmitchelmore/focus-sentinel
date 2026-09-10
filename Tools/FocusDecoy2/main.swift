// FocusDecoy2 — the neutral subject, and the keystroke sink (R-97, finding 1, finding 4).
//
// Two jobs, and each of them is a scenario the live lane could not otherwise reach.
//
// ## 1 · It is the only way an `uncertain` verdict is reachable on demand
//
// `FocusDecoy` is seeded `unrelated` for the ladder scenarios, so it can never produce the
// `uncertain` verdict U-1's query affordance needs. This one carries a deliberately **neutral**
// bundle identity — `com.chrismitchelmore.FocusDecoy2`, which matches no seed row, no rule and no
// token of any priority the lane sets — so the cascade falls through to the heuristic and declines
// with `noNegativeBasis`, which is exactly the 32-of-72 case U-1 exists to speak about. Without
// this application scenario S6 is not under-specified, it is unreachable.
//
// ## 2 · It is where the keystrokes have to land
//
// Adversarial review's finding 1 asked for a keystroke sink: type a unique token while the nudge
// panel is on screen and assert the **decoy** received it. That is the single most important
// behavioural property of the epic — a panel that quietly took the keyboard would be a panel
// nobody could work beside — and it cannot be gated, because synthesising a key event needs an
// Accessibility grant and no T1 criterion may depend on one (SC-5). So it is read evidence in the
// live lane, with the *driver* holding the grant and the app under test holding none.
//
// `--echo <path>` writes the field's contents to a file on every keystroke, so the driver reads
// what arrived rather than photographing a field and squinting at it. The field takes first
// responder at launch, which is what makes "the keystrokes went to the decoy" a claim about a real
// focused text field rather than about a window that merely happened to be frontmost.
//
// ## It reads nothing and reaches for nothing
//
// No sensing, no window list, no networking, no accessibility. It draws a field and writes what
// somebody typed into it to a path it was told about.

import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())

func argumentValue(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
        return nil
    }
    return arguments[index + 1]
}

final class Decoy2Delegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    let window: NSWindow
    let field = NSTextField(frame: .zero)
    let echoPath: String?

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 300, y: 300, width: 820, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        echoPath = argumentValue(after: "--echo")
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window.title = "Focus Decoy 2"
        window.collectionBehavior = [.fullScreenPrimary, .managed]

        let content = NSView(frame: window.contentLayoutRect)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.systemTeal.cgColor
        content.autoresizingMask = [.width, .height]

        let label = NSTextField(labelWithString: "Type here — this is where the keystrokes must land")
        label.font = .systemFont(ofSize: 20, weight: .medium)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)

        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = .monospacedSystemFont(ofSize: 22, weight: .regular)
        field.placeholderString = "the token arrives here"
        field.delegate = self
        content.addSubview(field)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor, constant: -60),
            field.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            field.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            field.widthAnchor.constraint(equalToConstant: 640)
        ])
        window.contentView = content

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // First responder, so a keystroke that reaches this application reaches the FIELD. A
        // window that is merely frontmost proves much less: the claim frame 17 makes is that the
        // person's typing went where they were typing.
        window.makeFirstResponder(field)
        echo()
    }

    func controlTextDidChange(_ notification: Notification) {
        echo()
    }

    /// Write what the field currently holds, so the driver reads the sink rather than a picture
    /// of it. Failures are ignored on purpose: this is an evidence convenience, and a decoy that
    /// died because a path was unwritable would abort a scenario for the wrong reason.
    private func echo() {
        guard let echoPath else { return }
        try? Data(field.stringValue.utf8).write(to: URL(fileURLWithPath: echoPath))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let application = NSApplication.shared
let delegate = Decoy2Delegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
