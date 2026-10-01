import AppKit
import SwiftUI

/// **A control the tour can point at** (focus-u6de).
///
/// A closed vocabulary of the places in the cockpit a coach mark lands on. The cockpit's
/// sections report their frames under these names as they are laid out, the tour reads them
/// back as screen rectangles, and `WalkthroughTests` holds that every step names anchors that
/// exist. A control that is not on screen — the Details tab's sections while Now is open, the
/// capture field while a priority is set — reports nothing, which is how a step knows to point
/// at the control that opens it instead.
public enum WalkthroughAnchor: String, Sendable, CaseIterable, Hashable {
    /// The capture field, open when there is no priority or after *Change priority*.
    case captureField
    /// The *Change priority* verb, shown while a priority is set and the field is closed.
    case changePriorityButton
    /// The definition-of-done field under the hero.
    case doneWhenField
    /// The timebox control on the Now tab.
    case timeboxControl
    /// The session controls: Start, Pause, Finish and the rest.
    case sessionControls
    /// The Details tab's button in the tab bar.
    case detailsTab
    /// The context pack on the Details tab.
    case contextPack
    /// The rules section on the Details tab.
    case rules
    /// The *Open Settings* button in the footer.
    case openSettingsButton
}

/// **Where every anchored control is, in its window** (focus-u6de).
///
/// One registry, for `FocusCommandCenter`'s reason: the cockpit is one window and the tour is
/// one panel, and the view that lays a control out is the only thing that knows where it went.
/// Frames are kept in SwiftUI's global space — the window's content area, y down — and
/// converted to the screen only when asked, against the window as it is at that moment, so a
/// window that moved does not leave a stale rectangle behind.
///
/// Nothing here needs a window server to be constructed: the snapshot lane renders the cockpit
/// through `ImageRenderer`, its reports land here and are read by nobody.
@MainActor
public final class WalkthroughAnchorRegistry {
    public static let shared = WalkthroughAnchorRegistry()

    private(set) var windowRects: [WalkthroughAnchor: CGRect] = [:]
    /// Called after any report or removal. The tour re-anchors on it.
    public var onChange: (() -> Void)?

    public init() {}

    /// Record where a control was laid out, in the window's content space.
    public func report(_ anchor: WalkthroughAnchor, rect: CGRect) {
        guard windowRects[anchor] != rect else { return }
        windowRects[anchor] = rect
        onChange?()
    }

    /// The control left the screen.
    public func clear(_ anchor: WalkthroughAnchor) {
        guard windowRects.removeValue(forKey: anchor) != nil else { return }
        onChange?()
    }

    /// Whether the control is currently laid out.
    public func isPresent(_ anchor: WalkthroughAnchor) -> Bool {
        windowRects[anchor] != nil
    }

    /// The control's rectangle on the screen, given the window it is in.
    ///
    /// SwiftUI's global space is the window's content view with the origin at the top left; AppKit's
    /// is the same view with the origin at the bottom left, and `convertToScreen` takes the latter.
    public func screenRect(of anchor: WalkthroughAnchor, in window: NSWindow?) -> CGRect? {
        guard let rect = windowRects[anchor], let window, let content = window.contentView else {
            return nil
        }
        let flipped = NSRect(
            x: rect.minX,
            y: content.bounds.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        return window.convertToScreen(flipped)
    }
}

private struct WalkthroughAnchorModifier: ViewModifier {
    let anchor: WalkthroughAnchor
    let registry: WalkthroughAnchorRegistry

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { rect in
                registry.report(anchor, rect: rect)
            }
            .onDisappear {
                registry.clear(anchor)
            }
    }
}

extension View {
    /// Report this view's frame under an anchor name, for the tour to point at.
    public func walkthroughAnchor(
        _ anchor: WalkthroughAnchor,
        registry: WalkthroughAnchorRegistry = .shared
    ) -> some View {
        modifier(WalkthroughAnchorModifier(anchor: anchor, registry: registry))
    }
}
