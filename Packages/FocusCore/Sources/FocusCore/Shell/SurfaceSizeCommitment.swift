import Foundation

/// **The size one surface commits to for one content, and whether that content scrolls**
/// (focus-nu6).
///
/// Two numbers and a flag, and the flag is the half that matters: a surface that clamps its
/// height without scrolling has not bounded its content, it has **cut it off** — which is the
/// defect `DecisionSurfaceReachability` was built to name, arriving by a different door.
public struct SurfaceSizeCommitment: Sendable, Equatable, Hashable {
    /// The width the surface committed to. Text wraps into it; the surface never grows sideways.
    public let width: Double
    /// The height the surface will actually be: the wrapped height, floored at the surface's own
    /// minimum and clamped to what the display can hold.
    public let height: Double
    /// Whether the content is taller than the clamp, and must therefore scroll.
    public let scrolls: Bool

    public init(width: Double, height: Double, scrolls: Bool) {
        self.width = width
        self.height = height
        self.scrolls = scrolls
    }

    public var size: (width: Double, height: Double) { (width, height) }
}

/// **The four commitments every surface in this application owes its content** (focus-nu6).
///
/// A surface commits a **width**, measures the content's **wrapped height** at that width,
/// **clamps** the height to what the display can actually hold, and **scrolls** past the clamp.
/// The nudge panel and the menu-bar popover each grew their own copy of this arithmetic — for
/// good reasons, one measurement at a time — and five other surfaces got none of it: the Settings
/// window, the quick-capture panel and the three sheets each committed a `minWidth` and nothing
/// else, so at the shipping text size the Privacy pane grew taller than any display and its
/// lower half was unreachable on every Mac.
///
/// This is that arithmetic, once, as a pure function of measured values. Nothing here touches
/// `NSScreen`, `NSWindow` or SwiftUI: the callers take the readings — `sizeThatFits(in:)` for the
/// wrapped height, `NudgePanelController.currentScreens()` for the displays — and hand them over,
/// which is what makes the whole cross product of {content height} × {display} testable on a
/// machine with no window server.
///
/// **The ceiling is deliberately two-sided.** A ceiling taken from a constant alone puts a tall
/// surface off the bottom of a small display; one taken from the display alone lets a surface
/// fill a laptop screen, which for an interruption is a surface that has stopped being
/// proportionate. So it is the smaller of the two, floored at the surface's own minimum so the
/// arithmetic can never ask for a negative window.
public enum SurfaceSizeCommitments {
    /// How far over the ceiling a content may measure before it is given a scroll view.
    ///
    /// One point, for the reason `DecisionSurfaceReachability.tolerance` is one point: a layout
    /// escape is measured in tens or thousands of points and a rounding difference between a
    /// SwiftUI frame and an AppKit content rect is measured in fractions of one. Without the
    /// slack, a content that measures a hair over its ceiling acquires a scroll bar it has no
    /// use for.
    public static let tolerance: Double = 1

    /// **How tall a surface may be on the display it is being placed on.**
    ///
    /// - Parameters:
    ///   - screens: every display, as the shell reports them.
    ///   - reserving: how much vertical space the surface must leave alone — its own margins,
    ///     plus whatever chrome it wears. The panel reserves a margin at the top and the bottom;
    ///     the popover reserves one margin and the arrow-and-corner allowance above it, which is
    ///     why this is one number rather than a symmetric margin.
    ///   - absoluteMaximum: the surface's own proportionality limit, independent of the display.
    ///     `nil` when the surface has none — the popover's case, where a person clicked and
    ///     shortening what they asked to see would answer a question they did not ask.
    ///   - minimum: the shortest the surface is ever allowed to be, so a tiny display cannot
    ///     produce a ceiling below the surface's own chrome — or a negative one, which is a
    ///     window the layout cannot build at all.
    /// - Returns: `nil` only when nothing bounds the surface at all: no display to read *and* no
    ///   limit of its own. A caller handed `nil` commits what it measured and scrolls nothing.
    public static func ceiling(
        screens: [DisplayGeometry],
        reserving: Double,
        absoluteMaximum: Double?,
        minimum: Double
    ) -> Double? {
        guard let display = DisplayMapper.primaryScreen(in: screens) else { return absoluteMaximum }
        let usable = display.visibleFrame.height - reserving
        let bounded = min(absoluteMaximum ?? usable, usable)
        return max(bounded, minimum)
    }

    /// **The commitment itself**: a measured content, a committed width and a ceiling, in.
    ///
    /// - Parameters:
    ///   - measuredHeight: the content's **wrapped** height at `width`, from
    ///     `NSHostingController.sizeThatFits(in:)` with an unbounded height proposal. Never
    ///     `NSView.fittingSize`, which is the *unconstrained* fitting size and is the reading
    ///     that produced a 2 212-point nudge panel.
    ///   - width: the width the surface commits to.
    ///   - ceiling: `nil` when nothing bounds the surface — the popover's case, where a person
    ///     clicked and shortening what they asked to see would answer a question they did not
    ///     ask. The measured height is then committed whole and nothing scrolls.
    ///   - minimum: the shortest this surface may be.
    public static func commit(
        measuredHeight: Double,
        width: Double,
        ceiling: Double?,
        minimum: Double = 0
    ) -> SurfaceSizeCommitment {
        let floored = max(measuredHeight, minimum)
        guard let ceiling else {
            return SurfaceSizeCommitment(width: width, height: floored, scrolls: false)
        }
        return SurfaceSizeCommitment(
            width: width,
            height: min(floored, ceiling),
            scrolls: measuredHeight > ceiling + tolerance
        )
    }
}
