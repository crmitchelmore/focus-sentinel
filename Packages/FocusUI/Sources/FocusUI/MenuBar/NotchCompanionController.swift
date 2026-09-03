import AppKit
import FocusCore

/// **The object that puts the hairline on the screen, and the counter that says whether it ever
/// did** (e08a, `focus-26b`).
///
/// ## Why there is a write count at all
///
/// The same reason `MenuBarController.glyphWriteCount` exists (focus-mkk). A predicate saying *the
/// companion draws nothing on a Mac with no notch* cannot fail; a number can. On this rig the
/// number is `0` for the life of the process, `isVisible` is `false`, and the self-check publishes
/// both beside the refusal that explains them — so "the hairline is never drawn here" is a
/// measurement rather than an inspection. `NudgeUnseenAttemptTests` reads the same two values in
/// every deferred cell of its fold, which is where the visibility conjunct is actually held.
///
/// ## The display-parameter change
///
/// Every placement is taken down and recomputed when the display configuration moves, following
/// `NudgePanelController`'s pattern: a strip placed under a housing on a display that has been
/// unplugged is ink on a screen that is not there. There is no state to preserve across the
/// change — the companion carries nothing — so the teardown is unconditional.
@MainActor
public final class NotchCompanionController {
    /// The panel, built lazily. **It does not exist on this rig**, and that is deliberate: a
    /// borderless window created at launch and never ordered in would still be a window in the
    /// window list, which is a thing `windowReports()` would have to explain.
    private var panel: NotchCompanionPanel?

    /// How many times the strip has actually been drawn — assigned a frame and ordered in. Never
    /// incremented for a request, for `glyphWriteCount`'s reason.
    public private(set) var writeCount = 0

    /// Whether the strip is on the screen right now.
    public private(set) var isVisible = false

    /// The frame the strip was last drawn at, or `nil` when it has never been drawn or has been
    /// taken down. Reported so a refusal and an ink frame cannot disagree.
    public private(set) var ink: ScreenRect?

    /// The displays this controller reads, injectable exactly as `NudgePanelController.displays`
    /// is and for the same reason: this rig has one display with no built-in panel and cannot be
    /// made to grow one.
    public var displays: @MainActor () -> [DisplayGeometry] = {
        NudgePanelController.currentScreens()
    }

    public init() {}

    /// **The landing this Mac actually offers**, or the first refusal among its displays.
    ///
    /// A Mac has at most one built-in panel, so "the built-in display's answer" is well defined.
    /// When there is none the answer is the first display's refusal — which on every Mac with an
    /// external monitor and no built-in panel is `.noBuiltInDisplay`, and on a Mac with no
    /// displays at all is that same refusal produced from an empty list rather than a crash.
    public func landing() -> NotchLanding {
        let screens = displays()
        if let builtIn = screens.first(where: \.isBuiltIn) { return builtIn.notchLanding }
        return .refused(.noBuiltInDisplay)
    }

    /// Draw, or take down, from the one derivation.
    ///
    /// Called wherever the menu bar is redrawn, with the same presentation the item was handed —
    /// which is what makes this a second renderer of one state rather than a second state.
    public func update(
        presentation: MenuBarPresentation,
        menuBarVisible: Bool,
        itemVisible: Bool,
        landing: NotchLanding? = nil
    ) {
        let resolved = landing ?? self.landing()
        guard
            let companion = NotchCompanionPresentation.derive(
                landing: resolved,
                presentation: presentation,
                menuBarVisible: menuBarVisible,
                itemVisible: itemVisible
            )
        else {
            remove()
            return
        }
        show(companion)
    }

    /// Take the strip down. Idempotent, and the whole of what happens on this rig.
    public func remove() {
        panel?.orderOut(nil)
        isVisible = false
        ink = nil
    }

    /// Put the strip up at the frame the derivation gave, building the window on first use.
    private func show(_ companion: NotchCompanion) {
        let frame = NSRect(
            x: companion.ink.x,
            y: companion.ink.y,
            width: companion.ink.width,
            height: companion.ink.height
        )
        let window = panel ?? makePanel(frame)
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        // Last, and only on a real assignment, for `MenuBarController.redraw(force:)`'s reason:
        // the reading a listener takes back is a reading of the pass it is being told about.
        if ink != companion.ink || !isVisible { writeCount += 1 }
        ink = companion.ink
        isVisible = true
    }

    private func makePanel(_ frame: NSRect) -> NotchCompanionPanel {
        let window = NotchCompanionPanel(
            contentRect: frame,
            styleMask: NotchCompanionPanel.companionStyleMask,
            backing: .buffered,
            defer: false
        )
        window.isFloatingPanel = true
        // **`.floating`, and never `.statusBar`** — see `NotchCompanionPanel`. Unmeasured levels
        // wait on P-e08-A.
        window.level = .floating
        window.collectionBehavior = NotchCompanionPanel.collectionBehavior
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // No tracking area until e08b, so nothing here may consume a click over the menu bar.
        window.ignoresMouseEvents = true
        window.contentView = NotchCompanionLineView(frame: NSRect(origin: .zero, size: frame.size))
        // It is decoration and carries no sentence: a VoiceOver user hears the ambient rung from
        // the status item's own label, and a second unlabelled window in the hierarchy would be a
        // stop on the rotor with nothing in it.
        window.setAccessibilityElement(false)
        panel = window
        return window
    }
}
