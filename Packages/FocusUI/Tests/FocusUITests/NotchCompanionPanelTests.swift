import AppKit
import FocusCore
import Foundation
import Testing

@testable import FocusUI

/// **The companion is a subset of the item, in marks and in visibility** (e08a, `focus-26b`).
///
/// The fold is `{landed} ∪ NotchLanding.Refusal.allCases` × menu bar visible or not × item visible
/// or not × paused or running, and every cell answers three questions: is there a companion at
/// all, what frame is its ink, and what mark does it carry.
///
/// Two of those answers are invariants rather than expectations:
///
/// 1. `companion.mark ∈ NotchCompanionPresentation.legalMarks(for:)`, which in e08a is satisfied at
///    the floor — the companion is always `.unmarked`, because it draws a line and a line says
///    nothing;
/// 2. `companion != nil ⟹ menuBarVisible && itemVisible` — the review's §3 finding, and the one
///    that stops the notch becoming the only surface a rung reaches.
///
/// The landed cell is **synthetic** and stays so until P-e08-B: this Mac has no built-in panel, so
/// every cell here that draws is a value somebody wrote down. What is not synthetic is the window
/// itself, which is a real `NSPanel` with the real flags on it.
@Suite("The notch companion draws a subset of what the item draws")
@MainActor
struct NotchCompanionPanelTests {
    /// A 14″ MacBook Pro's built-in panel, synthetic until P-e08-B.
    static let notched = DisplayGeometry(
        displayID: 1,
        screenIndex: 0,
        isPrimary: true,
        frame: ScreenRect(x: 0, y: 0, width: 1_512, height: 982),
        visibleFrame: ScreenRect(x: 0, y: 0, width: 1_512, height: 944),
        backingScaleFactor: 2.0,
        safeAreaTopInset: 32,
        auxiliaryTopLeft: ScreenRect(x: 0, y: 950, width: 663.5, height: 32),
        auxiliaryTopRight: ScreenRect(x: 848.5, y: 950, width: 663.5, height: 32),
        isBuiltIn: true
    )

    /// This rig: a Mac mini and one external display.
    static let theRealRig = DisplayGeometry(
        displayID: 2,
        screenIndex: 0,
        isPrimary: true,
        frame: ScreenRect(x: 0, y: 0, width: 1_920, height: 1_080),
        visibleFrame: ScreenRect(x: 0, y: 81, width: 1_920, height: 969),
        backingScaleFactor: 1.0
    )

    /// One landing per column of the fold: the synthetic notched one, plus a geometry that
    /// produces each refusal by name.
    static let landings: [(name: String, landing: NotchLanding)] = {
        var rows: [(String, NotchLanding)] = [("landed", notched.notchLanding)]
        for refusal in NotchLanding.Refusal.allCases {
            rows.append((refusal.rawValue, .refused(refusal)))
        }
        return rows
    }()

    @Test("every cell of the fold is a subset of the item, in marks and in visibility")
    func theWholeFold() {
        var cells = 0
        var drew = 0
        var refusedToDraw = 0

        for (name, landing) in Self.landings {
            for menuBarVisible in [true, false] {
                for itemVisible in [true, false] {
                    for paused in [false, true] {
                        cells += 1
                        let cell =
                            "\(name)/bar=\(menuBarVisible)/item=\(itemVisible)/paused=\(paused): "
                        let presentation = MenuBarPresentation(
                            status: .unrelated,
                            rung: .ambient,
                            rungSurface: .menuBar,
                            sensingPaused: paused
                        )
                        let companion = NotchCompanionPresentation.derive(
                            landing: landing,
                            presentation: presentation,
                            menuBarVisible: menuBarVisible,
                            itemVisible: itemVisible
                        )

                        guard let companion else {
                            refusedToDraw += 1
                            continue
                        }
                        drew += 1

                        // — conjunct 2, the one that is new law —
                        #expect(
                            menuBarVisible && itemVisible,
                            """
                            \(cell)the companion drew where the glyph could not — the notch has \
                            become a fifth surface and needs its own PerceptionChannel
                            """
                        )
                        // — conjunct 1, held at its floor —
                        #expect(
                            NotchCompanionPresentation.legalMarks(for: presentation)
                                .contains(companion.mark),
                            "\(cell)the companion carried a mark the item is not carrying"
                        )
                        #expect(
                            companion.mark == .unmarked,
                            """
                            \(cell)e08a draws a hairline and nothing else; a mark here is e08b \
                            arriving without P-e08-A and P-e08-B
                            """
                        )
                        // — F-119, honoured by absence —
                        #expect(!paused, "\(cell)a paused app drew a line saying it was watching")
                        // — the ink is the landing's own strip, never a frame computed here —
                        #expect(companion.ink == landing.collapsed)
                    }
                }
            }
        }

        #expect(cells == Self.landings.count * 2 * 2 * 2)
        #expect(drew > 0, "nothing ever drew, so a derivation returning nil always would pass")
        #expect(refusedToDraw > 0, "everything drew, so the guards prove nothing")
    }

    /// **Every refusal is a silence, whatever else is true.** The fold above would be satisfied by
    /// a refusal that drew under some other combination of flags; this says the six names are six
    /// silences, over the whole rest of the space.
    @Test("no refusal draws anything, under any combination of the other three readings")
    func everyRefusalIsSilent() {
        for refusal in NotchLanding.Refusal.allCases {
            for menuBarVisible in [true, false] {
                for itemVisible in [true, false] {
                    for paused in [false, true] {
                        #expect(
                            NotchCompanionPresentation.derive(
                                landing: .refused(refusal),
                                presentation: MenuBarPresentation(
                                    status: .unrelated,
                                    rung: .ambient,
                                    rungSurface: .menuBar,
                                    sensingPaused: paused
                                ),
                                menuBarVisible: menuBarVisible,
                                itemVisible: itemVisible
                            ) == nil,
                            """
                            \(refusal.rawValue)/bar=\(menuBarVisible)/item=\(itemVisible)/\
                            paused=\(paused) drew a strip the geometry refused
                            """
                        )
                    }
                }
            }
        }
    }

    /// The positive cell, as a specific frame. `982 − 32 = 950` is the housing's bottom edge, and
    /// the strip's two points sit under it.
    @Test("the landed cell draws exactly the strip the geometry named")
    func theLandedFrame() {
        let companion = NotchCompanionPresentation.derive(
            landing: Self.notched.notchLanding,
            presentation: MenuBarPresentation(status: .unrelated),
            menuBarVisible: true,
            itemVisible: true
        )

        #expect(companion?.ink == ScreenRect(x: 663.5, y: 948, width: 185, height: 2))
        #expect(companion?.mark == .unmarked)
    }

    // MARK: - The window itself

    /// **The behaviour that is a ruling** (P-130, R-96n). `NudgePanelTests`' pin restated for the
    /// second window: `.fullScreenAuxiliary` is absent, and unlike the nudge panel there is no
    /// gate that may add it — the companion belongs to a menu bar that is not visible on a
    /// full-screen space, so the flag would only ever let it draw where conjunct 2 forbids.
    @Test("the companion's collection behaviour can never carry fullScreenAuxiliary")
    func behaviourTable() {
        #expect(!NotchCompanionPanel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(NotchCompanionPanel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(NotchCompanionPanel.collectionBehavior.contains(.stationary))
        #expect(NotchCompanionPanel.collectionBehavior.contains(.ignoresCycle))
    }

    /// A real window, with the flags the plan's recipe got wrong read off the object.
    @Test("the window is floating, borderless, and takes nothing")
    func theWindow() {
        let panel = NotchCompanionPanel(
            contentRect: NSRect(x: 0, y: 0, width: 185, height: 2),
            styleMask: NotchCompanionPanel.companionStyleMask,
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = NotchCompanionPanel.collectionBehavior
        defer { panel.orderOut(nil) }

        #expect(!panel.canBecomeKey, "the companion could take the keyboard")
        #expect(!panel.canBecomeMain, "the companion could become the application's main window")
        #expect(panel.level == .floating)
        #expect(
            panel.level != .statusBar,
            "the plan's .statusBar recipe is unmeasured on this rig and waits on P-e08-A"
        )
        #expect(!panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
    }

    // MARK: - The controller, on this rig and on a synthetic notched one

    /// **The measurement this whole epic rests on, on this machine.** Not an inspection: the
    /// controller is driven with the real display list and the counter is read back.
    @Test("on a Mac with no built-in display the companion is never drawn")
    func thisRigNeverDraws() {
        let controller = NotchCompanionController()
        controller.displays = { [Self.theRealRig] }
        defer { controller.remove() }

        #expect(controller.landing() == .refused(.noBuiltInDisplay))

        for menuBarVisible in [true, false] {
            for itemVisible in [true, false] {
                controller.update(
                    presentation: MenuBarPresentation(
                        status: .unrelated, rung: .ambient, rungSurface: .menuBar
                    ),
                    menuBarVisible: menuBarVisible,
                    itemVisible: itemVisible
                )
            }
        }

        #expect(controller.writeCount == 0, "a strip was drawn on a Mac with no built-in display")
        #expect(!controller.isVisible)
        #expect(controller.ink == nil)
    }

    /// The controller's non-vacuity: given a notched display it does draw, and given an item that
    /// went off screen it takes the strip down again.
    @Test("the controller draws on a notched display and takes it down when the item goes")
    func theControllerFollowsTheItem() {
        let controller = NotchCompanionController()
        controller.displays = { [Self.notched] }
        defer { controller.remove() }
        let presentation = MenuBarPresentation(
            status: .unrelated, rung: .ambient, rungSurface: .menuBar
        )

        controller.update(presentation: presentation, menuBarVisible: true, itemVisible: true)
        #expect(controller.isVisible)
        #expect(controller.writeCount == 1)
        #expect(controller.ink == ScreenRect(x: 663.5, y: 948, width: 185, height: 2))

        // The same state again: a request is not a write.
        controller.update(presentation: presentation, menuBarVisible: true, itemVisible: true)
        #expect(controller.writeCount == 1, "an unchanged strip was redrawn")

        // The item overflows out of the menu bar. The glyph cannot be written, so neither may the
        // companion be — this is the arrangement the review's §3 is about.
        controller.update(presentation: presentation, menuBarVisible: true, itemVisible: false)
        #expect(!controller.isVisible, "the companion outlived the glyph")
        #expect(controller.ink == nil)

        // And the menu bar itself going away, which is the full-screen space P-131 measured.
        controller.update(presentation: presentation, menuBarVisible: true, itemVisible: true)
        #expect(controller.isVisible)
        controller.update(presentation: presentation, menuBarVisible: false, itemVisible: true)
        #expect(!controller.isVisible)
    }

    /// A Mac with a notched built-in panel **and** an external display: the strip belongs to the
    /// built-in one, whichever is primary. This is the docked-MacBook case
    /// `SurfaceSizeCommitment.ceiling` gets wrong (review §1, S4) and e08b must fix before it may
    /// expand anything.
    @Test("the landing is the built-in display's, not the primary's")
    func theBuiltInDisplayDecides() {
        let external = DisplayGeometry(
            displayID: 9,
            screenIndex: 0,
            isPrimary: true,
            frame: ScreenRect(x: 0, y: 0, width: 1_920, height: 1_080),
            visibleFrame: ScreenRect(x: 0, y: 81, width: 1_920, height: 969),
            backingScaleFactor: 1.0
        )
        let controller = NotchCompanionController()
        controller.displays = { [external, Self.notched] }

        #expect(controller.landing() == Self.notched.notchLanding)
        #expect(controller.landing().collapsed != nil)
    }

    /// An empty display list is a refusal with a reason, not a crash and not a landing.
    @Test("no displays at all is a named refusal")
    func noDisplays() {
        let controller = NotchCompanionController()
        controller.displays = { [] }

        #expect(controller.landing() == .refused(.noBuiltInDisplay))
    }
}
