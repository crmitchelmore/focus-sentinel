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
    /// The hosting view whose root is the bounded content, kept so a text-size or display change
    /// can be laid out again rather than only at construction.
    private let hosting: NSHostingView<AnyView>
    /// The displays this panel bounds itself against; `nil` for the live ones. Injectable for the
    /// reason every other surface's is: no lane can hand a panel a 13-inch laptop otherwise.
    private let screens: ShellScreens
    /// The app that was frontmost when the panel was summoned, so ⌘Return can hand control
    /// back to it.
    private var interruptedApplication: NSRunningApplication?
    /// Whether the panel has ever been positioned. Centred once; after that the user's own
    /// placement is theirs to keep.
    private var hasBeenPositioned = false

    /// **The traits the shell has actually handed it, or `nil` if nothing ever has**
    /// (focus-cp2).
    ///
    /// A sentinel rather than a copy of `model.traits`, and the distinction is the whole point:
    /// the model is initialised with `.systemDefault`, so "the panel has the right traits" and
    /// "nobody ever told the panel anything" are indistinguishable on a machine whose appearance
    /// happens to be the default. This is the second fact, and it can only become non-`nil` by
    /// somebody calling `update(traits:)` — which, in the shipping application, only the cockpit
    /// scene's own wiring does.
    public private(set) var adoptedTraits: AppearanceTraits?

    public init(traits: AppearanceTraits = .systemDefault, screens: ShellScreens = nil) {
        self.screens = screens
        let model = QuickCaptureModel()
        model.traits = traits
        self.model = model

        panel = QuickCapturePanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: ShellSurfaceBounds.capturePanelWidth,
                height: ShellSurfaceBounds.capturePanelMinimumHeight
            ),
            // **`.resizable`, which this style mask did not have** (focus-nu6). Without it the
            // panel could neither grow nor be dragged, so at the largest accessibility text size
            // its two fields and its Save button were laid out past the bottom of a 140-point
            // window and there was no gesture in macOS that reached them.
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
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
        // Built now, bounded, so `show()` is state changes on objects that already exist. The
        // size is committed in `layOutContent()`, which `show()` runs: it depends on the person's
        // text size and on which display the panel is being centred on, and both of those change
        // while the process lives.
        let hosting = NSHostingView(rootView: Self.bounded(model: model, screens: screens))
        self.hosting = hosting
        panel.contentView = hosting

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

    /// **The panel's content, bounded** (focus-nu6).
    ///
    /// A `static` over the model rather than a method on the live controller, so the size the
    /// shipping panel is built at is a size a test can take — at either text size, against any
    /// display — without a window server.
    @MainActor
    static func bounded(model: QuickCaptureModel, screens: ShellScreens) -> AnyView {
        AnyView(
            BoundedSurface(
                width: ShellSurfaceBounds.capturePanelWidth,
                ceiling: ShellSurfaceBounds.capturePanelCeiling(
                    screens: screens ?? NudgePanelController.currentScreens()
                )
            ) {
                QuickCaptureView(model: model)
            }
        )
    }

    /// **Size the panel to what its content actually measures** (focus-nu6).
    ///
    /// The panel used to be built at a constant 560 × 140 with a `contentMinSize` and no way to
    /// grow — which is the same defect the nudge panel had before focus-kby, arriving through a
    /// style mask instead of a frame: at the largest accessibility text size the content needed
    /// more than 140 points, got 140, and the Save button was laid out below the bottom edge.
    ///
    /// Run again on every `show()` rather than once at construction, because the two things it
    /// depends on both change while the process lives: the person's text size, and which display
    /// the panel is being centred on.
    private func layOutContent() {
        let measured = hosting.fittingSize
        let ceiling = ShellSurfaceBounds.capturePanelCeiling(
            screens: screens ?? NudgePanelController.currentScreens()
        )
        let commitment = SurfaceSizeCommitments.commit(
            measuredHeight: Double(measured.height),
            width: ShellSurfaceBounds.capturePanelWidth,
            ceiling: ceiling,
            minimum: ShellSurfaceBounds.capturePanelMinimumHeight
        )
        let size = NSSize(width: commitment.width, height: commitment.height)
        // A floor and a ceiling rather than a pin: this panel is a typing surface, so a person who
        // wants it larger may drag it — up to what the display can hold, past which the content
        // scrolls rather than the window running off the screen.
        panel.contentMinSize = NSSize(
            width: ShellSurfaceBounds.capturePanelWidth,
            height: ShellSurfaceBounds.capturePanelMinimumHeight
        )
        panel.contentMaxSize = NSSize(
            width: ShellSurfaceBounds.capturePanelWidth,
            height: ceiling ?? .greatestFiniteMagnitude
        )
        panel.setContentSize(size)
        panel.layoutIfNeeded()
    }

    /// The size the panel is actually at, as opposed to any size anybody committed to.
    public var contentSize: CGSize {
        panel.contentRect(forFrameRect: panel.frame).size
    }

    /// **Whether a person can drag this panel larger.** Reported rather than assumed, because the
    /// missing `.resizable` was invisible to every lane in the programme: a style mask is not a
    /// frame, and no size assertion can see one.
    public var isResizable: Bool {
        panel.styleMask.contains(.resizable)
    }

    /// Show the panel, focused and ready to type.
    ///
    /// Everything here is a state change on objects that already exist. Nothing is allocated,
    /// laid out for the first time, or loaded from a nib.
    public func show() {
        interruptedApplication = NSWorkspace.shared.frontmostApplication
        layOutContent()
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
        adoptedTraits = traits
        // The traits carry Reduce Motion and the contrast settings, any of which can change the
        // content's height. A panel already on screen has to follow.
        layOutContent()
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
