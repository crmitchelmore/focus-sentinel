import AppKit
import FocusCore
import SwiftUI

/// What the quick-capture panel produced.
public struct QuickCaptureResult: Sendable, Equatable, Hashable {
    /// The sentence, exactly as the user typed it.
    public let intent: String
    /// A definition of done, if the refinement strip offered one and the user took it.
    public let doneWhen: String?
    /// Whether the user asked to be returned to the app the hot key interrupted (⌘Return).
    public let returnsToPreviousApp: Bool

    public init(intent: String, doneWhen: String?, returnsToPreviousApp: Bool) {
        self.intent = intent
        self.doneWhen = doneWhen
        self.returnsToPreviousApp = returnsToPreviousApp
    }
}

/// The global capture panel — built at launch, shown from the hot-key handler.
///
/// **Built at launch is the whole performance story.** Probe P-57 measured 34 ms from the hot
/// key to a visible panel with the text field as first responder, against F-06's budget of
/// two seconds — three orders of magnitude of headroom — and the *only* way to lose that is
/// to construct the window on demand. So the panel, its hosting view and its SwiftUI content
/// all exist before the first key press; `show()` does no building at all.
///
/// **It activates, deliberately.** A capture field the user cannot type into is not capture,
/// so `show()` calls `NSApp.activate()`. This is the exact opposite of e05's nudge panel,
/// which must *not* steal focus — and that is why the two are different objects rather than
/// one object with a flag.
///
/// **It gives the interruption back.** The frontmost application is remembered on the way in,
/// so ⌘Return can commit the sentence and put the user back where they were in one gesture.
/// Escape closes without saving anything.
@MainActor
public final class QuickCapturePanelController {
    /// Called when the user commits. `nil` until the composition root wires the store in.
    public var onCommit: ((QuickCaptureResult) -> Void)?

    private let panel: QuickCapturePanel
    private let model: QuickCaptureModel
    /// The app that was frontmost when the panel was summoned, so ⌘Return can hand control
    /// back to it.
    private var interruptedApplication: NSRunningApplication?
    /// Whether the panel has ever been positioned. Centred once; after that the user's own
    /// placement is theirs to keep.
    private var hasBeenPositioned = false

    public init(traits: AppearanceTraits = .systemDefault) {
        let model = QuickCaptureModel()
        model.traits = traits
        self.model = model

        panel = QuickCapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 140),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = ShellStrings.string(.capturePanelTitle)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        // Never released by a close: this object *is* the panel's owner, and a released panel
        // would have to be rebuilt — which is the one thing the 34 ms depends on not doing.
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: QuickCaptureView(model: model))
        panel.contentMinSize = NSSize(width: 520, height: 120)

        panel.onCancel = { [weak self] in self?.hide() }
        model.onCancel = { [weak self] in self?.hide() }
        model.onCommit = { [weak self] intent, doneWhen, returnsToPreviousApp in
            self?.finish(
                QuickCaptureResult(
                    intent: intent,
                    doneWhen: doneWhen,
                    returnsToPreviousApp: returnsToPreviousApp
                )
            )
        }
    }

    /// Whether the panel and its content already exist. Reported by `--focus-self-check`,
    /// because "built at launch" is a claim that has to be checkable at runtime.
    public var isPrebuilt: Bool {
        panel.contentView != nil
    }

    public var isVisible: Bool {
        panel.isVisible
    }

    /// Show the panel, focused and ready to type.
    ///
    /// Everything here is a state change on objects that already exist. Nothing is allocated,
    /// laid out for the first time, or loaded from a nib.
    public func show() {
        interruptedApplication = NSWorkspace.shared.frontmostApplication
        if !hasBeenPositioned {
            panel.center()
            hasBeenPositioned = true
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        // Tells the SwiftUI content to take first responder. A panel the user has to click
        // into before typing has not really been summoned.
        model.showToken &+= 1
    }

    public func hide() {
        panel.orderOut(nil)
    }

    /// Update the appearance the panel draws with — the same injected traits every other
    /// surface in this package uses.
    public func update(traits: AppearanceTraits) {
        model.traits = traits
    }

    private func finish(_ result: QuickCaptureResult) {
        hide()
        onCommit?(result)
        if result.returnsToPreviousApp {
            interruptedApplication?.activate()
        }
        interruptedApplication = nil
    }
}

/// The panel itself.
///
/// A subclass for exactly two reasons: a utility panel must be told it can become key, or the
/// field in it can never be typed into; and Escape has to close it even while a text field
/// has first responder, which is what `cancelOperation(_:)` is for.
private final class QuickCapturePanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
