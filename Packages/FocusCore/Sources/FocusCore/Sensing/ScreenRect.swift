import Foundation

/// A rectangle, in whichever screen coordinate space its holder documents.
///
/// ## Why this is not `CGRect`
///
/// `CGRect` lives in CoreGraphics, and `FocusCore` may import Foundation, SwiftData and `os`
/// and nothing else — the boundary ruling that keeps the domain layer free of the platform is
/// the same ruling that makes every value here snapshot-testable with no window server
/// running. Measured rather than assumed: with `import Foundation` alone, `CGRect(x:y:width:
/// height:)`, `CGRect(origin:size:)` and `NSRect(x:y:width:height:)` all fail to compile with
/// *"argument passed to call that takes no arguments"* — the C struct is visible, its Swift
/// overlay is not. `pid_t` **is** available through Foundation, and is used as-is.
///
/// So the domain owns four `Double`s, and the one file in the shipping graph that talks to
/// `CGWindowListCopyWindowInfo` converts at the boundary. That is the seam working, not a
/// workaround for it.
///
/// ## Two coordinate spaces, and which is which
///
/// The window list reports **Quartz** coordinates: the origin is the *top* left of the primary
/// display and y grows downward. `NSScreen` reports **AppKit** coordinates: the origin is the
/// *bottom* left and y grows upward. The two are not interchangeable and a value of this type
/// does not know which it holds — its holder documents that, and `flippedFromQuartz` is the
/// one sanctioned conversion. Measured against a real window (probe P-91): an `NSWindow` at
/// AppKit `(200, 200) 640×432` appeared in the window list as Quartz `(200, 448) 640×432`, and
/// `1080 − 448 − 432 = 200` ✓.
public struct ScreenRect: Sendable, Equatable, Hashable, Codable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let zero = ScreenRect(x: 0, y: 0, width: 0, height: 0)

    public var minX: Double { min(x, x + width) }
    public var maxX: Double { max(x, x + width) }
    public var minY: Double { min(y, y + height) }
    public var maxY: Double { max(y, y + height) }
    public var area: Double { abs(width * height) }
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    /// The area the two rectangles share. Zero when they do not overlap — which is what makes
    /// "largest intersection area" a total function rather than one with a special case.
    public func intersectionArea(with other: ScreenRect) -> Double {
        let overlapWidth = min(maxX, other.maxX) - max(minX, other.minX)
        let overlapHeight = min(maxY, other.maxY) - max(minY, other.minY)
        guard overlapWidth > 0, overlapHeight > 0 else { return 0 }
        return overlapWidth * overlapHeight
    }

    /// Whether two rectangles are the same to within `tolerance` on every edge.
    ///
    /// A full-screen window's bounds and its display's frame are computed by different
    /// subsystems and agree to a point, not to a bit. One point is the tolerance the
    /// presentation quorum uses.
    public func isEqual(to other: ScreenRect, tolerance: Double) -> Bool {
        abs(x - other.x) <= tolerance
            && abs(y - other.y) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }

    /// This rectangle, read as Quartz coordinates, expressed in AppKit coordinates.
    ///
    /// `flippedY = primaryMaxY − y − height`, anchored on the **primary** screen — not on the
    /// screen the window happens to be on, which is the mistake that puts every window on a
    /// secondary display in the wrong place.
    public func flippedFromQuartz(primaryMaxY: Double) -> ScreenRect {
        ScreenRect(
            x: x,
            y: primaryMaxY - y - height,
            width: width,
            height: height
        )
    }
}
