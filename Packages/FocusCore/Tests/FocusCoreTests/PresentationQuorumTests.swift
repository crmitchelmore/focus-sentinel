import Foundation
import Testing

@testable import FocusCore

/// The rig's own display, as measured: `2490W1`, frame `1920×1080 @ (0,0)` (probe P-90).
private let primaryFrame = ScreenRect(x: 0, y: 0, width: 1_920, height: 1_080)
private let primaryMaxY: Double = 1_080

/// An injected second display, to the right of the first. The rig has one screen, so every
/// multi-display claim in this programme is a fixture rather than an observation.
private let secondaryFrame = ScreenRect(x: 1_920, y: 0, width: 1_920, height: 1_080)

private let frontmostPID: pid_t = 501

private func window(
    owner: String,
    pid: pid_t,
    layer: Int,
    bounds: ScreenRect
) -> WindowMetadataValue {
    WindowMetadataValue(
        ownerName: owner,
        ownerPID: pid,
        layer: layer,
        number: Int.random(in: 1...9_999),
        bounds: bounds,
        isOnScreen: true,
        alpha: 1
    )
}

/// The Dock's window, exactly as measured: pid 418, **layer 20**, and permanently the size of
/// the whole display (probe P-78). This is the decoy the PID filter exists for.
private let dockWindow = window(
    owner: "Dock",
    pid: 418,
    layer: 20,
    bounds: ScreenRect(x: 0, y: 0, width: 1_920, height: 1_080)
)

/// Window Server's menu-bar window: layer 24, `1920×30 @ (0,0)` (probe P-78).
private let menuBarWindow = window(
    owner: "Window Server",
    pid: 167,
    layer: 24,
    bounds: ScreenRect(x: 0, y: 0, width: 1_920, height: 30)
)

/// The frontmost application's own full-screen window, in **Quartz** coordinates.
private let frontmostFullScreenWindow = window(
    owner: "Keynote",
    pid: frontmostPID,
    layer: 0,
    bounds: ScreenRect(x: 0, y: 0, width: 1_920, height: 1_080)
)

/// The same application, windowed: the measured case from probe P-91 — AppKit
/// `(200, 200) 640×432` arrives as Quartz `(200, 448) 640×432`.
private let frontmostWindowedWindow = window(
    owner: "Keynote",
    pid: frontmostPID,
    layer: 0,
    bounds: ScreenRect(x: 200, y: 448, width: 640, height: 432)
)

@Suite("The presentation quorum")
struct PresentationQuorumTests {
    /// One signal is never enough. Two of the three were measured unreliable on their own —
    /// the presentation-options read *lagged* the transition, and the menu-bar read is also
    /// false for a screen saver.
    @Test("one signal never decides")
    func oneSignalNeverDecides() {
        let singles = [
            PresentationSignals(
                frontmostWindowFillsAScreen: true,
                presentationOptionsSayFullScreen: false,
                menuBarHidden: false
            ),
            PresentationSignals(
                frontmostWindowFillsAScreen: false,
                presentationOptionsSayFullScreen: true,
                menuBarHidden: false
            ),
            PresentationSignals(
                frontmostWindowFillsAScreen: false,
                presentationOptionsSayFullScreen: false,
                menuBarHidden: true
            )
        ]
        for signals in singles {
            #expect(signals.agreementCount == 1)
            let state = PresentationQuorum.evaluate(signals: signals, isUserExcluded: false)
            #expect(!state.isPresenting)
            #expect(!state.suppressesOverlays)
        }
    }

    @Test("no signal at all decides nothing")
    func noSignalDecidesNothing() {
        let state = PresentationQuorum.evaluate(signals: .none, isUserExcluded: false)
        #expect(state.signals.agreementCount == 0)
        #expect(!state.isPresenting)
        #expect(PresentationState.notPresenting.isPresenting == false)
    }

    /// Any two of the three. All three pairs, individually.
    @Test("any two signals reach the quorum")
    func anyTwoSignalsDecide() {
        let pairs = [
            PresentationSignals(
                frontmostWindowFillsAScreen: true,
                presentationOptionsSayFullScreen: true,
                menuBarHidden: false
            ),
            PresentationSignals(
                frontmostWindowFillsAScreen: true,
                presentationOptionsSayFullScreen: false,
                menuBarHidden: true
            ),
            PresentationSignals(
                frontmostWindowFillsAScreen: false,
                presentationOptionsSayFullScreen: true,
                menuBarHidden: true
            )
        ]
        for signals in pairs {
            #expect(signals.agreementCount == 2)
            #expect(PresentationQuorum.evaluate(signals: signals, isUserExcluded: false).isPresenting)
        }
        #expect(PresentationQuorum.requiredAgreement == 2)
    }

    @Test("all three agreeing is presenting, obviously")
    func allThreeAgree() {
        let signals = PresentationSignals(
            frontmostWindowFillsAScreen: true,
            presentationOptionsSayFullScreen: true,
            menuBarHidden: true
        )
        #expect(signals.agreementCount == 3)
        #expect(PresentationQuorum.evaluate(signals: signals, isUserExcluded: false).isPresenting)
    }

    /// The exclusion list is an **override**, not a vote: the person said so, and no quorum
    /// of heuristics outranks that.
    @Test("the user exclusion list overrides on its own, against every signal")
    func exclusionOverridesAlone() {
        let state = PresentationQuorum.evaluate(signals: .none, isUserExcluded: true)
        #expect(state.isPresenting)
        #expect(state.isUserExcluded)
        #expect(state.suppressesOverlays)
        #expect(state.signals.agreementCount == 0, "it did not need a single signal")
    }
}

@Suite("Signal 1: the frontmost application's window filling a screen")
struct PresentationSignalOneTests {
    /// **The decoy the PID filter exists for.** The Dock's window is permanently the size of
    /// the whole display, so a bounds-equals-screen test without the filter matches it for
    /// ever (probe P-78).
    @Test("the Dock's display-sized layer-20 window never matches")
    func dockNeverMatches() {
        #expect(
            !PresentationQuorum.frontmostWindowFillsAScreen(
                windows: [dockWindow, menuBarWindow, frontmostWindowedWindow],
                frontmostPID: frontmostPID,
                screenFrames: [primaryFrame],
                primaryMaxY: primaryMaxY
            )
        )
    }

    /// `.optionOnScreenOnly` is **not** scoped to the current Space (probe P-77), so a
    /// full-screen application on another Space is in the very same list. Any heuristic that
    /// asks "is *some* window full-screen" is therefore wrong.
    @Test("a full-screen window belonging to a non-frontmost PID never matches")
    func otherApplicationsFullScreenWindowNeverMatches() {
        let someoneElsesFullScreen = window(
            owner: "Google Chrome",
            pid: 4_242,
            layer: 0,
            bounds: ScreenRect(x: 0, y: 0, width: 1_920, height: 1_080)
        )
        #expect(
            !PresentationQuorum.frontmostWindowFillsAScreen(
                windows: [someoneElsesFullScreen, frontmostWindowedWindow],
                frontmostPID: frontmostPID,
                screenFrames: [primaryFrame],
                primaryMaxY: primaryMaxY
            )
        )
    }

    @Test("the frontmost application's own full-screen window matches")
    func frontmostFullScreenWindowMatches() {
        #expect(
            PresentationQuorum.frontmostWindowFillsAScreen(
                windows: [dockWindow, menuBarWindow, frontmostFullScreenWindow],
                frontmostPID: frontmostPID,
                screenFrames: [primaryFrame],
                primaryMaxY: primaryMaxY
            )
        )
    }

    @Test("the frontmost application's windowed window does not match")
    func windowedWindowDoesNotMatch() {
        #expect(
            !PresentationQuorum.frontmostWindowFillsAScreen(
                windows: [frontmostWindowedWindow],
                frontmostPID: frontmostPID,
                screenFrames: [primaryFrame],
                primaryMaxY: primaryMaxY
            )
        )
    }

    /// A window on layer 3 is a floating panel — this app's own quick-capture panel, for
    /// instance — and is never the application's window, whatever size it is.
    @Test("a non-zero layer never matches, even at exactly the screen's size")
    func nonZeroLayerNeverMatches() {
        let panel = window(
            owner: "Focus Sentinel",
            pid: frontmostPID,
            layer: 3,
            bounds: ScreenRect(x: 0, y: 0, width: 1_920, height: 1_080)
        )
        #expect(
            !PresentationQuorum.frontmostWindowFillsAScreen(
                windows: [panel],
                frontmostPID: frontmostPID,
                screenFrames: [primaryFrame],
                primaryMaxY: primaryMaxY
            )
        )
    }

    /// The flip is anchored on the **primary** display, so a full-screen window on a secondary
    /// one is still recognised. The rig has one screen; this is a fixture, as every
    /// multi-display claim in this programme must be.
    @Test("a full-screen window on an injected secondary display matches")
    func fullScreenOnASecondaryDisplayMatches() {
        // Quartz for a window filling the second display: same y, x offset by the first.
        let onSecondary = window(
            owner: "Keynote",
            pid: frontmostPID,
            layer: 0,
            bounds: ScreenRect(x: 1_920, y: 0, width: 1_920, height: 1_080)
        )
        #expect(
            PresentationQuorum.frontmostWindowFillsAScreen(
                windows: [onSecondary],
                frontmostPID: frontmostPID,
                screenFrames: [primaryFrame, secondaryFrame],
                primaryMaxY: primaryMaxY
            )
        )
    }

    /// One point, because the two figures come from different subsystems.
    @Test("the bounds comparison tolerates a point and not ten")
    func toleranceIsAPoint() {
        let offByOne = window(
            owner: "Keynote",
            pid: frontmostPID,
            layer: 0,
            bounds: ScreenRect(x: 0, y: 0, width: 1_919, height: 1_080)
        )
        #expect(
            PresentationQuorum.frontmostWindowFillsAScreen(
                windows: [offByOne],
                frontmostPID: frontmostPID,
                screenFrames: [primaryFrame],
                primaryMaxY: primaryMaxY
            )
        )

        let offByTen = window(
            owner: "Keynote",
            pid: frontmostPID,
            layer: 0,
            bounds: ScreenRect(x: 0, y: 0, width: 1_910, height: 1_080)
        )
        #expect(
            !PresentationQuorum.frontmostWindowFillsAScreen(
                windows: [offByTen],
                frontmostPID: frontmostPID,
                screenFrames: [primaryFrame],
                primaryMaxY: primaryMaxY
            )
        )
        #expect(PresentationQuorum.boundsTolerance == 1)
    }

    @Test("no windows and no screens both answer no rather than crashing")
    func emptyInputsAnswerNo() {
        #expect(
            !PresentationQuorum.frontmostWindowFillsAScreen(
                windows: [],
                frontmostPID: frontmostPID,
                screenFrames: [primaryFrame],
                primaryMaxY: primaryMaxY
            )
        )
        #expect(
            !PresentationQuorum.frontmostWindowFillsAScreen(
                windows: [frontmostFullScreenWindow],
                frontmostPID: frontmostPID,
                screenFrames: [],
                primaryMaxY: primaryMaxY
            )
        )
    }
}

@Suite("Window metadata filtering")
struct WindowMetadataFilteringTests {
    /// `layer == 0` **and** an owner-PID match. Both halves, asserted against a list that
    /// contains the Dock, the menu bar, another application and a floating panel.
    @Test("applicationWindows keeps only layer-0 windows of the given pid")
    func applicationWindowsFilter() {
        let panel = window(owner: "Focus Sentinel", pid: frontmostPID, layer: 3, bounds: .zero)
        let otherApp = window(owner: "Chrome", pid: 4_242, layer: 0, bounds: .zero)
        let list = [dockWindow, menuBarWindow, panel, otherApp, frontmostWindowedWindow]

        let filtered = list.applicationWindows(of: frontmostPID)
        #expect(filtered.count == 1)
        #expect(filtered.first == frontmostWindowedWindow)

        #expect(WindowMetadataValue.applicationWindowLayer == 0)
        #expect(!dockWindow.isApplicationWindow(of: 418), "the Dock's window is layer 20")
        #expect(!otherApp.isApplicationWindow(of: frontmostPID), "wrong pid")
        #expect(frontmostWindowedWindow.isApplicationWindow(of: frontmostPID))
    }

    /// The measured flip, end to end (probe P-91): Quartz `Y 448` for a window AppKit put at
    /// `y 200`, on a 1080-tall primary display.
    @Test("the Quartz-to-AppKit flip reproduces the measured case exactly")
    func measuredFlip() {
        let flipped = frontmostWindowedWindow.bounds.flippedFromQuartz(primaryMaxY: primaryMaxY)
        #expect(flipped.x == 200)
        #expect(flipped.y == 200, "1080 − 448 − 432 = 200")
        #expect(flipped.width == 640)
        #expect(flipped.height == 432)
    }
}
