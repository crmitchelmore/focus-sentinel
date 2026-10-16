import AppKit
import FocusCore
import SwiftUI

/// **The tour's own state** (focus-u6de): which step is up, and which have been done.
///
/// `@Observable` so the panel's SwiftUI content redraws when the host records a step as done,
/// for the reason `QuickCaptureModel` is one.
@MainActor
@Observable
public final class WalkthroughTourModel {
    public var step: WalkthroughAction = .firstStep
    public var done: Set<WalkthroughAction> = []
    public var traits: AppearanceTraits = .systemDefault

    public init() {}
}

/// **The floating panel the tour lives in, and the coach mark it drags with it** (focus-u6de).
///
/// ## Why a panel and not the sheet
///
/// The sheet covers the cockpit, and the point of the tour is that the person acts on the
/// cockpit: types the priority, presses Start, configures its context. So the tour is a floating utility
/// panel that moves beside whichever control the step is about, with the app fully visible and
/// fully usable, and `WalkthroughHighlightWindow` outlines that control.
///
/// ## What it may and may not do to focus
///
/// It is shown once with `makeKeyAndOrderFront`, which `QuickCapturePanelController` also uses
/// and R-96m permits outside the nudge module, and **without** `NSApp.activate()` (R-96e): the
/// tour is only ever started from a control inside this application, so the application is
/// already active. Every later move is `orderFront`, never a key change — the person is typing
/// into the cockpit, and a panel that took the keyboard back on each step would be a panel that
/// stopped them doing what it asked.
@MainActor
public final class WalkthroughPanelController {
    public let model: WalkthroughTourModel
    public let highlight = WalkthroughHighlightWindow()
    private let panel: WalkthroughPanel
    private let hosting: NSHostingView<AnyView>
    private var hasBeenShown = false
    /// What the panel was last placed beside, so a resize can put it back there: the content
    /// grows when a step is recorded done, after SwiftUI has updated and after `present` has
    /// measured it, and a panel that kept its top-left through that growth ran off the bottom
    /// of the screen — measured on this machine, under the Dock.
    private var lastTarget: CGRect?
    private weak var lastWindow: NSWindow?
    /// Kept for the controller's life, which is the process's: the tour is built once and
    /// reused on every replay, so there is nothing to remove it for. The closure holds `self`
    /// weakly.
    private var resizeObserver: NSObjectProtocol?

    /// The fallback button on the current step. Wired by the host that owns the tour.
    public var onAction: ((WalkthroughAction) -> Void)?
    /// Back or Next was pressed, naming the step to go to. The host decides what arriving means.
    public var onNavigate: ((WalkthroughAction) -> Void)?
    /// The panel was closed by its close affordance or Escape. The host treats that as *Finish
    /// the demo*: a tour abandoned halfway must still put the person's own priority back.
    public var onClose: (() -> Void)?

    public init(traits: AppearanceTraits = .systemDefault) {
        let model = WalkthroughTourModel()
        model.traits = traits
        self.model = model

        panel = WalkthroughPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 240),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = ShellStrings.string(.walkthroughPanelTitle)
        panel.isFloatingPanel = true
        panel.level = .floating
        // The panel goes with the application. The popover and the Settings window are this
        // application's, so opening them from a step keeps the panel; another application coming
        // forward takes it away with the cockpit, and it returns with the cockpit — a coach mark
        // drawn over somebody else's window would be pointing at nothing (focus-u6de).
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: AnyView(EmptyView()))
        self.hosting = hosting
        panel.contentView = hosting
        hosting.rootView = Self.content(model: model, controller: self)
        panel.onCancel = { [weak self] in self?.close() }
        panel.onClose = { [weak self] in self?.close() }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
    }

    /// The panel's committed width: enough for an instruction at standard type without a wrap on
    /// every line, narrow enough to sit beside the cockpit on a 1440-point display.
    public static let width: Double = 360

    @MainActor
    static func content(model: WalkthroughTourModel, controller: WalkthroughPanelController) -> AnyView {
        AnyView(WalkthroughStepContent(model: model, controller: controller))
    }

    public var isVisible: Bool { panel.isVisible }

    /// Open the tour on its first step. Where it goes is decided by the first `present`.
    public func show() {
        model.step = .firstStep
        model.done = []
        hasBeenShown = false
    }

    /// Draw a step beside its target, or beside a window when the step has no control on
    /// screen, and mark the target.
    ///
    /// - Parameters:
    ///   - step: the step to draw.
    ///   - target: the control's screen rectangle, or `nil` for a step with none.
    ///   - window: the window to sit beside when there is no target.
    public func present(step: WalkthroughAction, target: CGRect?, beside window: NSWindow?) {
        model.step = step
        lastTarget = target
        lastWindow = window
        layOutContent()
        place()
        if hasBeenShown {
            panel.orderFront(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
            hasBeenShown = true
        }
    }

    /// Put the panel beside what it was last presented for, at its size now, and draw the mark.
    /// Called by `present` and again whenever the panel's size changes.
    private func place() {
        let screen = lastWindow?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if let target = lastTarget {
            let placement = WalkthroughPlacement.place(panel: panel.frame.size, beside: target, within: visible)
            panel.setFrameOrigin(placement.origin)
            highlight.show(around: target, nubToward: placement.side, traits: model.traits)
        } else {
            highlight.hide()
            if let window = lastWindow {
                let placement = WalkthroughPlacement.place(panel: panel.frame.size, beside: window.frame, within: visible)
                panel.setFrameOrigin(placement.origin)
            } else {
                panel.center()
            }
        }
    }

    /// Take the panel and the mark down. Writes nothing; the host has already done what closing
    /// means.
    public func hide() {
        highlight.hide()
        panel.orderOut(nil)
    }

    /// The close affordance's path: hide, then tell the host.
    func close() {
        hide()
        onClose?()
    }

    public func update(traits: AppearanceTraits) {
        model.traits = traits
        layOutContent()
    }

    private func layOutContent() {
        // Ask SwiftUI to lay out for the model as it is now before measuring, so the size read
        // is the step's own and not the previous step's.
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let ceiling = (panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        let height = max(200, min(size.height, ceiling))
        panel.setContentSize(NSSize(width: Self.width, height: height))
    }
}

/// The step, read off the model so the panel redraws when the host records it done.
private struct WalkthroughStepContent: View {
    let model: WalkthroughTourModel
    let controller: WalkthroughPanelController

    var body: some View {
        WalkthroughStepView(
            step: model.step,
            isDone: model.done.contains(model.step),
            onAction: { [weak controller] action in controller?.onAction?(action) },
            onNavigate: { [weak controller] step in controller?.onNavigate?(step) }
        )
        .frame(width: WalkthroughPanelController.width)
        .appearanceTraits(model.traits)
        .preferredColorScheme(model.traits.colorScheme.swiftUI)
    }
}

/// The panel: a utility window that can become key so its buttons take a click, and that
/// reports Escape and its close button to the controller.
final class WalkthroughPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func performClose(_ sender: Any?) {
        // The title bar's close button. Hide rather than close, for `isReleasedWhenClosed`'s
        // reason, and tell the host so it can finish the demo.
        orderOut(nil)
        onClose?()
    }
}
