import Foundation

/// Where a window is, in displays.
///
/// Pure, over **injected** screens, because the rig this programme is built on has exactly one
/// display and no notch (probe P-90). Multi-display behaviour is therefore code that must be
/// written correctly and unit-tested with fixtures — never a claim this machine can confirm.
///
/// ## The two rules, both measured
///
/// * **Flip on the primary.** Window bounds arrive in Quartz coordinates (origin at the top
///   left of the primary display, y growing downward); screen frames are AppKit's (origin at
///   the bottom left, y growing upward). The conversion is
///   `primary.frame.maxY − y − height`, anchored on the **primary** screen and not on
///   whichever screen the window happens to be near — anchoring it locally is the mistake that
///   puts every window on a secondary display in the wrong place. Verified against a real
///   window (probe P-91): AppKit `(200, 200) 640×432` appeared as Quartz `(200, 448)`, and
///   `1080 − 448 − 432 = 200` ✓.
/// * **Largest intersection area.** Origin-containment is wrong for a window straddling two
///   displays: its origin is on one and most of it is on the other, and the person is looking
///   at the other. Area is the only answer that matches what they see.
public enum DisplayMapper {
    /// One window's place in the display arrangement.
    public struct Mapping: Sendable, Equatable, Hashable {
        public let display: DisplayGeometry
        /// The window's bounds in **AppKit** coordinates, after the flip.
        public let flippedBounds: ScreenRect
        /// How much of the window is on that display. Always greater than zero — a mapping
        /// with no overlap is not produced at all.
        public let intersectionArea: Double

        public init(display: DisplayGeometry, flippedBounds: ScreenRect, intersectionArea: Double) {
            self.display = display
            self.flippedBounds = flippedBounds
            self.intersectionArea = intersectionArea
        }
    }

    /// The display a window is on, or `nil` if it is on none of them.
    ///
    /// `nil` is a real answer and is deliberately **not** display zero: a window that is on no
    /// screen — minimised off-canvas, on a display that has just been unplugged, or at
    /// coordinates no display covers — must not be reported as being on the primary, because
    /// a caller would then weigh it as if the person were looking at it.
    ///
    /// - Parameters:
    ///   - quartzBounds: the window's bounds **as the window list reports them**.
    ///   - screens: every display, in `NSScreen.screens` order — index `0` is the primary.
    public static func map(
        quartzBounds: ScreenRect,
        screens: [DisplayGeometry]
    ) -> Mapping? {
        guard let primary = primaryScreen(in: screens) else { return nil }

        let flipped = quartzBounds.flippedFromQuartz(primaryMaxY: primary.frame.maxY)

        var best: Mapping?
        for screen in screens {
            let area = flipped.intersectionArea(with: screen.frame)
            guard area > 0 else { continue }
            if let current = best, current.intersectionArea >= area {
                // A strict `>` keeps the earliest screen — and therefore the primary — when a
                // window is split exactly down the middle. Ties have to break somewhere, and
                // breaking toward the primary is the answer that surprises nobody.
                continue
            }
            best = Mapping(display: screen, flippedBounds: flipped, intersectionArea: area)
        }
        return best
    }

    /// The display alone, for callers that do not need the working.
    public static func display(
        quartzBounds: ScreenRect,
        screens: [DisplayGeometry]
    ) -> DisplayGeometry? {
        map(quartzBounds: quartzBounds, screens: screens)?.display
    }

    /// The screen the flip is anchored on: the one flagged primary, or failing that the first.
    ///
    /// Both, because `NSScreen.screens.first` **is** the primary by contract and the flag is
    /// how a fixture says so; a mapper that trusted only one of the two would be brittle in a
    /// test or wrong in production.
    public static func primaryScreen(in screens: [DisplayGeometry]) -> DisplayGeometry? {
        screens.first(where: \.isPrimary) ?? screens.first
    }
}
