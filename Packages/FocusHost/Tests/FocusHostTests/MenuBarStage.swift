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
        _ = NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NudgeHostFixture.settle(0.2)
        controller.install()
        try #require(
            controller.isItemVisible,
            "the status item is not on screen, so no count of writes to it is a reading"
        )
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

        for _ in 0..<6 where !controller.isPopoverShown {
            controller.togglePopover()
            NudgeHostFixture.settle(0.2)
        }
        try #require(controller.isPopoverShown, "the popover never opened, so nothing below is a reading")
    }
}
