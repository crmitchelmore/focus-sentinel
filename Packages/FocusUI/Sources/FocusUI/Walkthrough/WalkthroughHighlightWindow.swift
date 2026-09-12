import AppKit
import FocusCore
import SwiftUI

/// **The coach mark: an outline around the control the step is about** (focus-u6de).
///
/// A borderless, transparent window that ignores every mouse event, drawn over the control's
/// screen rectangle with a rounded Spruce outline and a pointer nub on the side the tour panel
/// sits on. It takes nothing: it cannot become key or main, and a click on it lands on the
/// control underneath, which is the point — the person acts on the real control while the mark
/// says which one.
@MainActor
public final class WalkthroughHighlightWindow {
    private let window: NSWindow
    private let hosting: NSHostingView<AnyView>
    private let model = HighlightModel()

    /// How far the outline sits outside the control.
    public nonisolated static let padding: CGFloat = 8
    /// The nub's length beyond the outline.
    public nonisolated static let nubLength: CGFloat = 12

    public init() {
        window = HighlightPanel(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        // With the application, for the tour panel's reason: the ring is around a control in
        // this application's window, and means nothing over another application's.
        window.hidesOnDeactivate = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hosting = NSHostingView(rootView: AnyView(HighlightView(model: model)))
        window.contentView = hosting
    }

    public var isVisible: Bool { window.isVisible }

    /// Draw the mark around a screen rectangle, with the nub toward `side`.
    public func show(around target: CGRect, nubToward side: WalkthroughSide, traits: AppearanceTraits) {
        model.traits = traits
        model.side = side
        let inset = -Self.padding
        var frame = target.insetBy(dx: inset, dy: inset)
        switch side {
        case .right: frame.size.width += Self.nubLength
        case .left: frame.origin.x -= Self.nubLength; frame.size.width += Self.nubLength
        case .above: frame.size.height += Self.nubLength
        case .below: frame.origin.y -= Self.nubLength; frame.size.height += Self.nubLength
        }
        window.setFrame(frame, display: true)
        window.orderFront(nil)
    }

    public func hide() {
        window.orderOut(nil)
    }
}

/// Which side of the control the tour panel is on, and therefore which way the nub points.
public enum WalkthroughSide: String, Sendable, CaseIterable, Hashable {
    case right, left, above, below
}

@MainActor
@Observable
final class HighlightModel {
    var traits: AppearanceTraits = .systemDefault
    var side: WalkthroughSide = .right
}

/// A window that never takes anything: not key, not main, no mouse.
private final class HighlightPanel: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The outline and its nub. Pure drawing: no text, no control.
private struct HighlightView: View {
    let model: HighlightModel

    var body: some View {
        GeometryReader { proxy in
            let nub = WalkthroughHighlightWindow.nubLength
            let ring: CGRect = {
                var rect = CGRect(origin: .zero, size: proxy.size)
                switch model.side {
                case .right: rect.size.width -= nub
                case .left: rect.origin.x += nub; rect.size.width -= nub
                // SwiftUI's y grows downward: "above" the control on the screen is the top edge.
                case .above: rect.origin.y += nub; rect.size.height -= nub
                case .below: rect.size.height -= nub
                }
                return rect
            }()
            let colour = DesignTokens.Palette.role(.spruce, for: model.traits)
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(colour, lineWidth: 3)
                    .frame(width: ring.width, height: ring.height)
                    .position(x: ring.midX, y: ring.midY)
                    .shadow(color: colour.opacity(model.traits.reduceTransparency ? 0 : 0.45), radius: 8)
                Nub(side: model.side, ring: ring, length: nub)
                    .fill(colour)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The triangle on the ring's edge that faces the panel.
private struct Nub: Shape {
    let side: WalkthroughSide
    let ring: CGRect
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let half: CGFloat = 8
        switch side {
        case .right:
            let y = ring.midY
            path.move(to: CGPoint(x: ring.maxX - 1, y: y - half))
            path.addLine(to: CGPoint(x: ring.maxX + length, y: y))
            path.addLine(to: CGPoint(x: ring.maxX - 1, y: y + half))
        case .left:
            let y = ring.midY
            path.move(to: CGPoint(x: ring.minX + 1, y: y - half))
            path.addLine(to: CGPoint(x: ring.minX - length, y: y))
            path.addLine(to: CGPoint(x: ring.minX + 1, y: y + half))
        case .above:
            let x = ring.midX
            path.move(to: CGPoint(x: x - half, y: ring.minY + 1))
            path.addLine(to: CGPoint(x: x, y: ring.minY - length))
            path.addLine(to: CGPoint(x: x + half, y: ring.minY + 1))
        case .below:
            let x = ring.midX
            path.move(to: CGPoint(x: x - half, y: ring.maxY - 1))
            path.addLine(to: CGPoint(x: x, y: ring.maxY + length))
            path.addLine(to: CGPoint(x: x + half, y: ring.maxY - 1))
        }
        path.closeSubpath()
        return path
    }
}

/// **Where the tour panel goes for a given target** (focus-u6de), as a pure function the unit
/// lane can hold: beside the control, on whichever side has room, never over it, always on the
/// screen.
public enum WalkthroughPlacement {
    public static let gap: CGFloat = 20

    /// The panel's origin and the side of the target it ended up on.
    public static func place(
        panel: CGSize,
        beside target: CGRect,
        within visible: CGRect
    ) -> (origin: CGPoint, side: WalkthroughSide) {
        let gap = Self.gap + WalkthroughHighlightWindow.padding
        // Vertically centred on the target, then clamped to the screen.
        func clampY(_ y: CGFloat) -> CGFloat {
            max(visible.minY, min(y, visible.maxY - panel.height))
        }
        func clampX(_ x: CGFloat) -> CGFloat {
            max(visible.minX, min(x, visible.maxX - panel.width))
        }
        let centredY = clampY(target.midY - panel.height / 2)
        let right = target.maxX + gap
        if right + panel.width <= visible.maxX {
            return (CGPoint(x: right, y: centredY), .right)
        }
        let left = target.minX - gap - panel.width
        if left >= visible.minX {
            return (CGPoint(x: left, y: centredY), .left)
        }
        let centredX = clampX(target.midX - panel.width / 2)
        let below = target.minY - gap - panel.height
        if below >= visible.minY {
            return (CGPoint(x: centredX, y: below), .below)
        }
        let above = target.maxY + gap
        if above + panel.height <= visible.maxY {
            return (CGPoint(x: centredX, y: above), .above)
        }
        // Nowhere beside it fits: the corner of the screen, on the right, not over the target
        // if that can be helped.
        return (CGPoint(x: clampX(visible.maxX - panel.width), y: clampY(visible.maxY - panel.height)), .right)
    }
}
