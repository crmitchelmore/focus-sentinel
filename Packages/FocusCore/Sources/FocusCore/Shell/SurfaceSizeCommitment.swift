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

/// **How a surface that will not fit gives way** (focus-din).
///
/// A ceiling and a scroll made nothing get cut off, and it left a second question unanswered:
/// *what scrolls?* A surface that scrolls its **decision** is a surface whose actions are below
/// the fold — and `DecisionSurfaceReachability` correctly refuses to count a nudge whose actions
/// a person cannot click, so a nudge on a scrolling surface was never charged at all, however long
/// they looked at it. Measured through the shipping layout: at `accessibilityLarge` on a
/// 1080-point display **every** popover state scrolls, so for a large-text user a badge rung was
/// never delivered, `openRung` stayed unpaid, and the ladder parked for good.
///
/// Three answers, and the middle one is the repair:
public enum DecisionSurfaceOverflow: String, Sendable, Equatable, Hashable, CaseIterable {
    /// The whole surface fits. It is drawn as one column, in the order it was written.
    case nothingScrolls
    /// The surface does not fit, and the **context** gives way: the sentence, the reason and the
    /// countdown scroll, and the actions stay in the viewport where a person who never scrolls can
    /// still reach them. The reading is then a fact about the surface rather than about the scroll
    /// offset, which is what makes it stable for somebody who scrolls too.
    case theContextScrolls
    /// The decision itself does not fit, so there is nothing to pin it against: the surface
    /// scrolls whole. This is the honest residual — a display too small to show the actions at
    /// this text size — and the reading says so rather than charging a rung nobody could answer.
    case everythingScrolls

    /// Whether the surface's own actions are guaranteed to be inside the content the person can
    /// see, without scrolling.
    public var decisionIsInTheViewport: Bool { self != .everythingScrolls }
}

extension SurfaceSizeCommitments {
    /// **Which way a surface gives way**, as a pure function of three measurements (focus-din).
    ///
    /// - Parameters:
    ///   - measuredHeight: the whole surface's wrapped height at the committed width.
    ///   - decisionHeight: the offered actions' own wrapped height at the same width. `0` for a
    ///     surface that is offering nothing, which cannot have its decision cut off.
    ///   - ceiling: what the display can hold, or `nil` when nothing bounds the surface.
    ///   - minimumContextHeight: how much of *what the decision is about* must still be on screen
    ///     for the surface to be one a person could decide on. A row of buttons under nothing is
    ///     not a decision surface, so a decision that would leave less than this behind is not
    ///     pinned — the surface scrolls whole and the reading refuses the charge.
    public static func overflow(
        measuredHeight: Double,
        decisionHeight: Double,
        ceiling: Double?,
        minimumContextHeight: Double
    ) -> DecisionSurfaceOverflow {
        guard let ceiling else { return .nothingScrolls }
        guard measuredHeight > ceiling + tolerance else { return .nothingScrolls }
        guard decisionHeight + minimumContextHeight <= ceiling + tolerance else {
            return .everythingScrolls
        }
        return .theContextScrolls
    }
}
