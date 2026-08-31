import Foundation
import Testing

@testable import FocusCore

/// **The four commitments, over the cross product of contents and displays** (focus-nu6).
///
/// The arithmetic is the same one the nudge panel and the popover each grew a copy of. What is
/// new is that it is now *one* copy, and that the five surfaces which had none of it — the
/// Settings window, the quick-capture panel and the three sheets — are held to it by the same
/// function rather than by five more comments.
///
/// Every case here is a defect somebody could ship: a ceiling that goes negative on a small
/// display, a clamp with no scroll (which is a clip wearing a clamp's clothes), and a surface
/// that acquires a scroll bar because it measured a rounding fraction over its ceiling.
@Suite("A surface commits a width, clamps to the display, and scrolls past the clamp")
struct SurfaceSizeCommitmentTests {
    static func display(height: Double, visibleHeight: Double? = nil) -> DisplayGeometry {
        DisplayGeometry(
            displayID: 1,
            screenIndex: 0,
            isPrimary: true,
            frame: ScreenRect(x: 0, y: 0, width: 1920, height: height),
            visibleFrame: ScreenRect(x: 0, y: 25, width: 1920, height: visibleHeight ?? height - 85),
            backingScaleFactor: 2
        )
    }

    // MARK: - The ceiling

    @Test("the ceiling is the smaller of the surface's own limit and what the display can hold")
    func theCeilingIsTheSmallerOfTheTwo() {
        // A large display: the surface's own proportionality limit binds.
        let large = SurfaceSizeCommitments.ceiling(
            screens: [Self.display(height: 2160)],
            reserving: 48,
            absoluteMaximum: 800,
            minimum: 32
        )
        #expect(large == 800)

        // A small one: the display binds. 900 visible − 48 reserved.
        let small = SurfaceSizeCommitments.ceiling(
            screens: [Self.display(height: 1000, visibleHeight: 900)],
            reserving: 48,
            absoluteMaximum: 5000,
            minimum: 32
        )
        #expect(small == 852)
    }

    /// The floor is not decoration. A display shorter than what the surface reserves makes
    /// `visibleFrame.height − reserving` **negative**, and a negative ceiling is a window the
    /// layout cannot build at all.
    @Test("a display smaller than what the surface reserves still yields a usable ceiling")
    func theCeilingNeverGoesBelowTheMinimum() {
        let ceiling = SurfaceSizeCommitments.ceiling(
            screens: [Self.display(height: 40, visibleHeight: 30)],
            reserving: 48,
            absoluteMaximum: 800,
            minimum: 32
        )
        #expect(ceiling == 32, "the arithmetic produced a ceiling of \(String(describing: ceiling))")
        #expect((ceiling ?? 0) > 0)
    }

    /// A headless rig, or a Mac between display configurations. Nothing bounds a surface nobody
    /// can point at, so the surface's own limit is all that is left — and `nil` for the one
    /// surface that has no limit of its own.
    @Test("with no display to read, the surface's own limit is the ceiling")
    func noDisplayFallsBackToTheSurfacesOwnLimit() {
        #expect(
            SurfaceSizeCommitments.ceiling(
                screens: [],
                reserving: 48,
                absoluteMaximum: 800,
                minimum: 32
            ) == 800
        )
        #expect(
            SurfaceSizeCommitments.ceiling(
                screens: [],
                reserving: 50,
                absoluteMaximum: nil,
                minimum: 0
            ) == nil,
            "a surface with no limit and no display was given one anyway"
        )
    }

    // MARK: - The commitment

    @Test("content that fits is committed whole and does not scroll")
    func contentThatFitsIsCommittedWhole() {
        let commitment = SurfaceSizeCommitments.commit(
            measuredHeight: 262,
            width: 380,
            ceiling: 800,
            minimum: 32
        )
        #expect(commitment.width == 380)
        #expect(commitment.height == 262)
        #expect(!commitment.scrolls)
    }

    /// **The half that is the whole point.** Clamping without scrolling is clipping: the actions
    /// below the clamp are laid out and unreachable, which is exactly what
    /// `DecisionSurfaceReachability` reports as `unreachableActions`. So a clamped surface must
    /// always come back with `scrolls`.
    @Test("content taller than the ceiling is clamped AND scrolls")
    func contentOverTheCeilingScrolls() {
        let commitment = SurfaceSizeCommitments.commit(
            measuredHeight: 2699,
            width: 460,
            ceiling: 852,
            minimum: 32
        )
        #expect(commitment.height == 852, "the surface did not clamp to the display")
        #expect(commitment.scrolls, "the surface clamped its content and cut off the remainder")
    }

    @Test("a clamped surface always scrolls, over every content and every display")
    func clampingAlwaysImpliesScrolling() {
        for measured in stride(from: 0.0, through: 3000.0, by: 37.0) {
            for displayHeight in [400.0, 900.0, 1080.0, 2160.0] {
                let ceiling = SurfaceSizeCommitments.ceiling(
                    screens: [Self.display(height: displayHeight)],
                    reserving: 48,
                    absoluteMaximum: 800,
                    minimum: 32
                )
                let commitment = SurfaceSizeCommitments.commit(
                    measuredHeight: measured,
                    width: 460,
                    ceiling: ceiling,
                    minimum: 32
                )
                let wasClamped = commitment.height < measured - SurfaceSizeCommitments.tolerance
                #expect(
                    !wasClamped || commitment.scrolls,
                    """
                    \(measured) points of content on a \(displayHeight)-point display was cut to \
                    \(commitment.height) with no scroll view
                    """
                )
                #expect(commitment.height <= (ceiling ?? .infinity))
            }
        }
    }

    /// The slack, and why it is there: without it a content measuring a fraction over its ceiling
    /// acquires a scroll bar for a difference nobody can see.
    @Test("a content a rounding fraction over the ceiling does not acquire a scroll view")
    func aRoundingFractionDoesNotScroll() {
        let commitment = SurfaceSizeCommitments.commit(
            measuredHeight: 800.5,
            width: 380,
            ceiling: 800,
            minimum: 32
        )
        #expect(!commitment.scrolls)
        #expect(commitment.height == 800)
    }

    /// The popover's case: a person clicked, and shortening what they asked to see would be
    /// answering a question they did not ask.
    @Test("an unbounded surface commits the measured height whole")
    func anUnboundedSurfaceCommitsWhatItMeasured() {
        let commitment = SurfaceSizeCommitments.commit(
            measuredHeight: 1_400,
            width: 320,
            ceiling: nil,
            minimum: 32
        )
        #expect(commitment.height == 1_400)
        #expect(!commitment.scrolls)
    }

    @Test("a content shorter than the surface's own chrome is floored, not shrunk to nothing")
    func aShortContentIsFloored() {
        let commitment = SurfaceSizeCommitments.commit(
            measuredHeight: 4,
            width: 380,
            ceiling: 800,
            minimum: 32
        )
        #expect(commitment.height == 32)
        #expect(!commitment.scrolls)
    }
}
