import AppKit
import FocusUI
import Testing

/// Opening a real `NSPopover` on a real `NSStatusItem`, from a test process.
///
/// `NSPopover.show(relativeTo:of:preferredEdge:)` does nothing unless the application is active,
/// and a test bundle's process is not — so the lane has to make it one. This is the only place
/// in the repository outside the two user-summoned call sites that activates the application,
/// and `check-forbidden.sh`'s R-96e allow-list names this file for that reason: the ban is on the
/// *shipping* app stealing focus, and a test bundle is not shipped.
@MainActor
enum MenuBarStage {
    /// Install the item, hand it a presentation and open the popover on it.
    ///
    /// The first `show` after an activation is routinely refused while AppKit catches up, so this
    /// asks until the popover is really open rather than assuming the first attempt took.
    ///
    /// - Parameters:
    ///   - install: whether to call `install()` here. `false` for a controller the composition
    ///     root has already installed, because installing twice would replace the status item
    ///     the root is holding.
    ///   - onDidShow: what to run when the popover opens, or `nil` to **leave whatever is already
    ///     wired alone**. `nil` is what a composition-root test passes: a stage that installed a
    ///     closure of its own would be proving that its own closure runs, which is the defect
    ///     `thePopoverWireReachesTheLoop` had rather than a test of the shipping wire.
    /// **The item in the real menu bar, on screen, with the popover left shut** (focus-mkk).
    ///
    /// `MenuBarController.redraw(force:)` refuses to write to an item nobody can see (F-163), and
    /// the status bar hands out a visible item only to an active application — so a suite that
    /// counts writes to the glyph has to make this process one, exactly as opening the popover
    /// does. It lives here rather than in that suite because this file is the one place outside
    /// the two user-summoned call sites where `check-forbidden.sh`'s R-96e permits an activation:
    /// the ban is on the *shipping* app stealing focus, and every activation in the test lane
    /// belongs where the allow-list can see it.
    ///
    /// The popover is deliberately **not** opened. A rung on the glyph is not behind a click, and
    /// a stage that opened one would be measuring the badge's path.
    static func install(_ controller: MenuBarController) throws {
        activate()
        controller.install()
        try #require(
            controller.isItemVisible,
            "the status item is not on screen, so no count of writes to it is a reading"
        )
    }

    /// **The same, for an item the composition root has already installed** (focus-d6r).
    ///
    /// `AppComposition.startNudgeLoop()` calls `install()` itself, so a suite driving the
    /// shipping root must not call it again — that would replace the status item the root is
    /// holding, and every wire the root made would then be pointing at an item nobody redraws.
    /// What such a suite still needs is the activation, for `install(_:)`'s own reason: an
    /// inactive process is handed an invisible item, `redraw(force:)` refuses to write to one
    /// (F-163), and a glyph rung whose whole content is that item would correctly reach nobody.
    static func reveal(_ controller: MenuBarController) throws {
        activate()
        try #require(
            controller.isItemVisible,
            "the root's status item is not on screen, so no count of writes to it is a reading"
        )
    }

    /// The activation both routes above need, in one place.
    private static func activate() {
        _ = NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NudgeHostFixture.settle(0.2)
    }

    static func open(
        _ controller: MenuBarController,
        showing presentation: MenuBarPresentation,
        install: Bool = true,
        onDidShow: (() -> Void)? = nil
    ) throws {
        let application = NSApplication.shared
        _ = application.setActivationPolicy(.accessory)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NudgeHostFixture.settle(0.2)

        if install { controller.install() }
        if let onDidShow { controller.onPopoverDidShow = onDidShow }
        controller.update(presentation)

        for _ in 0..<6 where !isAnchored(controller) {
            if controller.isPopoverShown { controller.closePopover() }
            NudgeHostFixture.settle(0.2)
            controller.togglePopover()
            NudgeHostFixture.settle(0.2)
        }
        try #require(controller.isPopoverShown, "the popover never opened, so nothing below is a reading")
        try #require(
            isAnchored(controller),
            "the popover opened at \(controller.popoverFrame), which is not on any display"
        )
    }

    /// **Whether the popover AppKit placed is on a display at all** (focus-5yu).
    ///
    /// Measured on this rig: a popover shown on a status item the same process installed
    /// milliseconds earlier is placed at (0, -4, 326, 816) in roughly three runs in four, while
    /// the button reads (1493, 1050, 70, 30) — AppKit anchored it to nothing and dropped it in the
    /// corner, four points below the bottom edge of the screen. In the shipping app `install()` and
    /// the person's click are separated by the life of the application; here they are separated by
    /// one settle, so the stage asks again rather than handing a suite a popover to measure that
    /// the window server never placed.
    ///
    /// It is deliberately the **weakest** placement question — is this window on a display —
    /// rather than the reading the suites take. A stage that asserted reachability would be a
    /// stage that could not produce the unreadable popover `MenuBarPopoverReadingTests` drives.
    static func isAnchored(_ controller: MenuBarController) -> Bool {
        guard controller.isPopoverShown else { return false }
        let frame = controller.popoverFrame
        guard !frame.isEmpty else { return false }
        return NudgePanelController.currentScreens().contains { screen in
            frame.minX >= screen.frame.minX
                && frame.maxX <= screen.frame.maxX
                && frame.minY >= screen.frame.minY
                && frame.maxY <= screen.frame.maxY
        }
    }
}
