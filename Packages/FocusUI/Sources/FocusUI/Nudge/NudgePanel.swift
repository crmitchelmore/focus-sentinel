import AppKit
import FocusCore

/// **The window a nudge appears in, and the six properties that are load-bearing** (R-89).
///
/// Every one of them is the difference between a nudge and a theft, and each was measured on
/// this machine rather than taken from documentation (P-127, P-128, P-139):
///
/// | property | value | what breaks without it |
/// |---|---|---|
/// | `styleMask` contains `.nonactivatingPanel` | required | the application takes focus when the panel is shown |
/// | `canBecomeMain` | `false` | the panel becomes the app's main window and the app activates |
/// | `canBecomeKey` | `true` | the buttons cannot be clicked |
/// | `becomesKeyOnlyIfNeeded` | `true` | the panel takes the keyboard from somebody who is typing |
/// | `hidesOnDeactivate` | `false` | the nudge vanishes the instant the person clicks back to their work — i.e. exactly when it is needed |
/// | `collectionBehavior` | `[.canJoinAllSpaces, .stationary, .ignoresCycle]`, **and `.fullScreenAuxiliary` only when the presentation gate has cleared** | with the flag always on the panel stomps a presentation (P-130, and the captured frame proves it); with it never on the panel is invisible on a full-screen space where the person may legitimately be working |
///
/// ## This panel is not the capture panel, and the difference is deliberate
///
/// `QuickCapturePanelController` activates the application on purpose: a capture field the
/// person cannot type into is not capture. This one must never take anything. They are two
/// objects rather than one object with a flag precisely because the safe call and the unsafe
/// call are one word apart, and a flag would put both behaviours in one show path.
///
/// ## Escape is an answer — once the panel has been clicked into
///
/// `cancelOperation(_:)` rather than a key handler in the SwiftUI content: a panel whose
/// content holds first responder swallows Escape before any view sees it, and D-07 requires
/// **every** surface — including the top rung — to be dismissible.
///
/// What `cancelOperation(_:)` does **not** do is reach this panel from another application
/// (e07a). It travels the *key* window's responder chain; this panel is shown with
/// `orderFrontRegardless()` and never made key (R-96m), and a nudge fires while the person is
/// in the application it is about — so until they click the panel, their Escape goes to their
/// editor. That is not a defect to fix here: making the panel key on show is exactly the focus
/// theft R-89 forbids. The keyboard route from another application is the View menu's three
/// answers (`CommandRegistry.shell`), reached after one ⌘-Tab.
final class NudgePanel: NSPanel {
    /// Escape, or the close affordance. `.declined` for a question and `.dismissed` for an
    /// accusation; which of the two it is belongs to the caller, not to the window.
    var onCancel: (() -> Void)?

    /// **`true`, and it has to be.** A `.nonactivatingPanel` that cannot become key cannot have
    /// its buttons clicked at all — and a nudge nobody can answer back to is the anti-pattern
    /// the product boundary forbids.
    ///
    /// Becoming key is not the same as *being made* key. The panel is shown with
    /// `orderFrontRegardless()` and becomes key only when the person clicks it, which is exactly
    /// what `.nonactivatingPanel` exists to make safe: mouse events reach a non-activating panel
    /// without activating the owning application.
    override var canBecomeKey: Bool { true }

    /// **`false`, and it has to be.** A main window is the application's window, and an
    /// application with a main window is an application AppKit will happily bring forward.
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// The collection behaviour every nudge panel starts from.
    ///
    /// `.canJoinAllSpaces` so a person who switches desktops does not lose the nudge;
    /// `.stationary` so it does not slide with a space transition; `.ignoresCycle` so ⌘` never
    /// lands on it. **`.fullScreenAuxiliary` is not here**, and that absence is R-84: P-130
    /// measured a `.fullScreenAuxiliary` panel drawn plainly on top of a real full-screen space,
    /// and the frame was read. The window server will not protect a presentation for us, so the
    /// flag is added by `collectionBehavior(presentationIsClear:)` and only when the gate has
    /// already cleared.
    static let baseCollectionBehavior: NSWindow.CollectionBehavior =
        [.canJoinAllSpaces, .stationary, .ignoresCycle]

    /// The behaviour to apply given what the presentation gate said.
    ///
    /// - Parameter presentationIsClear: `true` when e03's `PresentationState.suppressesOverlays`
    ///   is `false` — nothing is being presented, so a panel joining a full-screen space is the
    ///   person's own full-screen work rather than somebody else's slide deck.
    static func collectionBehavior(presentationIsClear: Bool) -> NSWindow.CollectionBehavior {
        presentationIsClear
            ? baseCollectionBehavior.union(.fullScreenAuxiliary)
            : baseCollectionBehavior
    }

    /// The style mask every nudge panel carries.
    ///
    /// `.nonactivatingPanel` is the load-bearing bit. `.titled` + `.fullSizeContentView` with a
    /// hidden title give a compact HUD-shaped panel with the standard Mac window machinery
    /// underneath it — rather than a borderless window, which would have to re-implement
    /// shadowing, corner radius and key handling by hand.
    static let nudgeStyleMask: NSWindow.StyleMask =
        [.nonactivatingPanel, .titled, .fullSizeContentView]
}
