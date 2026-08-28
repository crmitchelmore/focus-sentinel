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
