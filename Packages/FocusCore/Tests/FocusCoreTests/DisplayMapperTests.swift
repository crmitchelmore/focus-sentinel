import Foundation
import Testing

@testable import FocusCore

/// The rig's own display, as measured: `2490W1`, `frame 1920×1080 @ (0,0)`,
/// `visibleFrame 1920×961 @ (0,89)`, `backingScaleFactor 1`, `displayID 3` (probe P-90).
private let primary = DisplayGeometry(
    displayID: 3,
    screenIndex: 0,
    isPrimary: true,
    frame: ScreenRect(x: 0, y: 0, width: 1_920, height: 1_080),
    visibleFrame: ScreenRect(x: 0, y: 89, width: 1_920, height: 961),
    backingScaleFactor: 1
)

/// An injected second display, to the right. **The rig has one screen**, so every multi-display
/// assertion below is a fixture — which is exactly the point: this behaviour has to be written
/// correctly and tested, because this machine cannot confirm it.
private let secondary = DisplayGeometry(
    displayID: 4,
    screenIndex: 1,
    isPrimary: false,
    frame: ScreenRect(x: 1_920, y: 0, width: 1_920, height: 1_080),
    visibleFrame: ScreenRect(x: 1_920, y: 0, width: 1_920, height: 1_080),
    backingScaleFactor: 2
)

private let bothScreens = [primary, secondary]

@Suite("Mapping a window to a display")
struct DisplayMapperTests {
    /// **The measured case** (probe P-91), end to end: a real `NSWindow` placed at AppKit
    /// `(200, 200) 640×432` appeared in the grant-free window list at Quartz `(200, 448)`, and
    /// the intersection test picked screen index 0.
    @Test("the measured case: Quartz (200, 448) 640×432 flips to AppKit (200, 200) on screen 0")
    func measuredCase() throws {
        let mapping = try #require(
            DisplayMapper.map(
                quartzBounds: ScreenRect(x: 200, y: 448, width: 640, height: 432),
                screens: [primary]
            )
        )
        #expect(mapping.flippedBounds.y == 200, "1080 − 448 − 432 = 200")
        #expect(mapping.flippedBounds.x == 200)
        #expect(mapping.flippedBounds.width == 640)
        #expect(mapping.flippedBounds.height == 432)
        #expect(mapping.display.screenIndex == 0)
        #expect(mapping.display.displayID == 3)
        #expect(mapping.display.isPrimary)
        #expect(mapping.intersectionArea == 640 * 432)
    }

    /// Origin-containment would put this window on the primary, because its origin is there.
    /// Most of it is not, and the person is looking at the part that is not.
    @Test("a straddling window picks the display with the larger intersection")
    func straddlingWindowPicksTheLargerIntersection() throws {
        // 1000 points wide, starting 200 points before the boundary: 200 on the primary and
        // 800 on the secondary.
        let straddling = ScreenRect(x: 1_720, y: 448, width: 1_000, height: 432)

        let mapping = try #require(
            DisplayMapper.map(quartzBounds: straddling, screens: bothScreens)
        )
        #expect(mapping.display.screenIndex == 1)
        #expect(mapping.display.isPrimary == false)
        #expect(mapping.intersectionArea == 800 * 432)

        // And the mirror image lands on the primary, so the rule is area and not a preference
        // for the second screen.
        let mostlyPrimary = ScreenRect(x: 1_120, y: 448, width: 1_000, height: 432)
        let primaryMapping = try #require(
            DisplayMapper.map(quartzBounds: mostlyPrimary, screens: bothScreens)
        )
        #expect(primaryMapping.display.screenIndex == 0)
        #expect(primaryMapping.intersectionArea == 800 * 432)
    }

    /// F-34's secondary-display fairness promise is a **value** carried on the activation.
    /// e03 records it; e04's engine weighs it.
    @Test("a window wholly on the secondary display reports isPrimary == false")
    func windowWhollyOnTheSecondaryDisplay() throws {
        let mapping = try #require(
            DisplayMapper.map(
                quartzBounds: ScreenRect(x: 2_200, y: 448, width: 640, height: 432),
                screens: bothScreens
            )
        )
        #expect(mapping.display.screenIndex == 1)
        #expect(!mapping.display.isPrimary)
        #expect(mapping.display.isSecondary)
        #expect(mapping.display.displayID == 4)
        #expect(mapping.display.backingScaleFactor == 2)
    }

    /// `nil`, and deliberately not display zero. A window on no screen — minimised off-canvas,
    /// or on a display that has just been unplugged — must not be reported as being where the
    /// person is looking, because a caller would weigh it as if it were.
    @Test("a window off every screen returns nil rather than index 0")
    func windowOffEveryScreenReturnsNil() {
        // Far to the right of both displays.
        #expect(
            DisplayMapper.map(
                quartzBounds: ScreenRect(x: 9_000, y: 448, width: 640, height: 432),
                screens: bothScreens
            ) == nil
        )
        // And far below: Quartz y beyond the primary's height flips to a negative AppKit y.
        #expect(
            DisplayMapper.map(
                quartzBounds: ScreenRect(x: 200, y: 5_000, width: 640, height: 432),
                screens: bothScreens
            ) == nil
        )
        #expect(
            DisplayMapper.display(
                quartzBounds: ScreenRect(x: 9_000, y: 448, width: 640, height: 432),
                screens: bothScreens
            ) == nil
        )
    }

    /// A window touching a display edge-on shares no area with it, and zero area is not a
    /// match — otherwise every window would be on every display it happened to abut.
    @Test("a zero-area overlap is not a match")
    func zeroAreaOverlapIsNotAMatch() {
        // Exactly at the boundary, zero width into the secondary.
        let atTheEdge = ScreenRect(x: 1_920, y: 448, width: 0, height: 432)
        #expect(DisplayMapper.map(quartzBounds: atTheEdge, screens: bothScreens) == nil)
    }

    /// The flip is anchored on the **primary**. Anchoring it on the screen the window is near
    /// is the mistake that puts every secondary-display window in the wrong place, so the
    /// anchor is asserted directly.
    @Test("the flip is anchored on the primary, whatever screen the window is on")
    func flipIsAnchoredOnThePrimary() throws {
        // A shorter secondary display, to make a locally-anchored flip give a different answer.
        let shortSecondary = DisplayGeometry(
            displayID: 5,
            screenIndex: 1,
            isPrimary: false,
            frame: ScreenRect(x: 1_920, y: 0, width: 1_280, height: 720),
            visibleFrame: ScreenRect(x: 1_920, y: 0, width: 1_280, height: 720),
            backingScaleFactor: 1
        )
        let mapping = try #require(
            DisplayMapper.map(
                quartzBounds: ScreenRect(x: 2_000, y: 448, width: 640, height: 200),
                screens: [primary, shortSecondary]
            )
        )
        // Anchored on the primary: 1080 − 448 − 200 = 432. Anchored on the short secondary it
        // would have been 720 − 448 − 200 = 72, which is a different display region entirely.
        #expect(mapping.flippedBounds.y == 432)
        #expect(mapping.display.screenIndex == 1)
    }

    /// A tie has to break somewhere, and breaking toward the primary surprises nobody.
    @Test("a window split exactly in half stays on the primary")
    func exactTieStaysOnThePrimary() throws {
        let split = ScreenRect(x: 1_420, y: 448, width: 1_000, height: 432)
        let mapping = try #require(DisplayMapper.map(quartzBounds: split, screens: bothScreens))
        #expect(mapping.display.screenIndex == 0)
        #expect(mapping.intersectionArea == 500 * 432)
    }

    @Test("with no screens at all there is nothing to map to")
    func noScreensMapsToNothing() {
        #expect(
            DisplayMapper.map(
                quartzBounds: ScreenRect(x: 0, y: 0, width: 100, height: 100),
                screens: []
            ) == nil
        )
        #expect(DisplayMapper.primaryScreen(in: []) == nil)
    }

    /// `NSScreen.screens.first` **is** the primary by contract, and the flag is how a fixture
    /// says so. Trusting only one of the two would be brittle in a test or wrong in production.
    @Test("the primary is found by its flag, and by position when nothing is flagged")
    func primaryIsFoundEitherWay() {
        #expect(DisplayMapper.primaryScreen(in: bothScreens)?.displayID == 3)
        #expect(DisplayMapper.primaryScreen(in: [secondary, primary])?.displayID == 3)

        let unflagged = DisplayGeometry(
            displayID: 9,
            screenIndex: 0,
            isPrimary: false,
            frame: primary.frame,
            visibleFrame: primary.visibleFrame,
            backingScaleFactor: 1
        )
        #expect(DisplayMapper.primaryScreen(in: [unflagged, secondary])?.displayID == 9)
    }

    /// **Nothing anywhere persists a Space identity**, because no public API exposes a stable
    /// one. The geometry value is the whole of what this epic remembers about where a window
    /// was, and it holds displays and nothing else.
    @Test("DisplayGeometry carries no Space identity of any kind")
    func noSpaceIdentityIsCarried() {
        let mirror = Mirror(reflecting: primary)
        let labels = Set(mirror.children.compactMap(\.label))
        #expect(labels == [
            "displayID", "screenIndex", "isPrimary", "frame", "visibleFrame",
            "backingScaleFactor"
        ])
        for label in labels {
            #expect(!label.localizedCaseInsensitiveContains("space"))
        }
    }
}
