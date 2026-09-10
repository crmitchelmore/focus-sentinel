import AppKit
import FocusCore
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

    /// What `NSApplication`'s activation policy was before this stage first changed it.
    ///
    /// `nil` means "nothing to put back": either the stage has not activated yet, or the last
    /// activation has already been restored. Recorded once rather than per call, because the
    /// second activation's "previous" value is the one the first one installed.
    private static var policyBeforeActivation: NSApplication.ActivationPolicy?

    /// The activation both routes above need, in one place.
    private static func activate() {
        let application = NSApplication.shared
        if policyBeforeActivation == nil {
            policyBeforeActivation = application.activationPolicy()
        }
        _ = application.setActivationPolicy(.accessory)
        application.activate(ignoringOtherApps: true)
        NudgeHostFixture.settle(0.2)
    }

    /// **Put back what the stage changed** (focus-tzj.5).
    ///
    /// The activation policy is process-wide state, and this stage is the only thing in the
    /// bundle that touches it — so a test that activates and never restores hands every later
    /// test in the process an application posture no test asked for, and leaves the machine
    /// running the gate with a foreground `xctest` for the rest of the run.
    ///
    /// A no-op when there is nothing to put back, so a `defer` may be written next to any
    /// stage call without the caller having to know whether it was the one that activated.
    static func restoreActivationPolicy() {
        guard let policy = policyBeforeActivation else { return }
        policyBeforeActivation = nil
        _ = NSApplication.shared.setActivationPolicy(policy)
    }

    /// **The outcome of opening the popover, because a display is a property of the machine**
    /// (focus-39x, and the class `focus-rxc` closed elsewhere).
    ///
    /// This used to end in `try #require(isAnchored(controller), "the popover opened at …, which
    /// is not on any display")`. `isAnchored` reads the live `NSScreen.screens` and answers
    /// `false` when the list is **empty** — a headless rig, or a Mac between display
    /// configurations — so every suite that opens a popover through this stage went red on such a
    /// machine, reporting a placement defect nobody observed.
    ///
    /// It is not converted to a bare green, which would leave every assertion below it passing on
    /// nothing and is a worse defect than the one it fixes. It returns `ProbeOutcome`, and
    /// `taken(_:)` below is what a caller writes: the reading is either taken and the suite goes
    /// on, or it is NOT TAKEN, loudly and by name, and the suite stops before its first assertion.
    ///
    /// **The `notTaken` door is one obstacle wide.** It is returned only when
    /// `NudgePanelController.currentScreens()` is empty, which is a closed machine property in
    /// `ReadingObstacle`. A popover that opened somewhere absurd *on* a display still fails, as
    /// it always did — that is a defect about the tree, and `notTaken` is never a way to make an
    /// inconvenient assertion go quiet.
    static func open(
        _ controller: MenuBarController,
        showing presentation: MenuBarPresentation,
        install: Bool = true,
        onDidShow: (() -> Void)? = nil
    ) throws -> ProbeOutcome {
        // Asked before anything is opened, so a headless run costs no activation and no settle.
        if NudgePanelController.currentScreens().isEmpty { return .notTaken(.noDisplayAttached) }

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
        // Asked again: a display can go away between the two, and the run that loses one mid-stage
        // is the same machine property as the run that never had one.
        if NudgePanelController.currentScreens().isEmpty { return .notTaken(.noDisplayAttached) }
        try #require(controller.isPopoverShown, "the popover never opened, so nothing below is a reading")
        try #require(
            isAnchored(controller),
            "the popover opened at \(controller.popoverFrame), which is not on any display"
        )
        return .holds
    }

    /// **What every caller of `open(_:showing:)` writes**, and the reason the outcome cannot be
    /// dropped: `check-forbidden.sh` R-169 requires the call to be bound and this to be asked.
    ///
    /// Returns `true` when the reading was taken and the suite may go on. On a NOT TAKEN it
    /// prints one fixed, greppable line — the same shape `self-check.sh` prints — so a run that
    /// could not measure says so in the log rather than in an absence a reader has to notice.
    @discardableResult
    static func taken(_ outcome: ProbeOutcome, _ subject: String = "the menu-bar popover") -> Bool {
        if let obstacle = outcome.obstacle {
            print("NOT TAKEN: \(subject) — \(obstacle.sentence)")
            return false
        }
        return true
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
