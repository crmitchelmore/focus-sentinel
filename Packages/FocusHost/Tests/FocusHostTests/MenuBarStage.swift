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
    static func open(
        _ controller: MenuBarController,
        showing presentation: MenuBarPresentation,
        onDidShow: @escaping () -> Void
    ) throws {
        let application = NSApplication.shared
        _ = application.setActivationPolicy(.accessory)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NudgeHostFixture.settle(0.2)

        controller.install()
        controller.onPopoverDidShow = onDidShow
        controller.update(presentation)

        for _ in 0..<6 where !controller.isPopoverShown {
            controller.togglePopover()
            NudgeHostFixture.settle(0.2)
        }
        try #require(controller.isPopoverShown, "the popover never opened, so nothing below is a reading")
    }
}
