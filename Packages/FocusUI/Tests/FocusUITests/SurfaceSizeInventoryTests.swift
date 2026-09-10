import AppKit
import FocusCore
import SwiftUI
import Testing

@testable import FocusUI

/// **Every surface the app can show, held to the same four commitments** (focus-nu6).
///
/// A surface lens inventoried eleven of them. Two — the nudge panel and the menu-bar popover —
/// commit a width, measure the wrapped height, clamp to the display and scroll past the clamp,
/// and each has its own suite proving it. **Five had none of the four**: the Settings window, the
/// quick-capture panel and the three sheets each committed a `minWidth` and stopped there.
///
/// A `minWidth` is a floor. It says how small a surface may be and never how large, so it cannot
/// fail: whatever a surface grew to, it was wider than its minimum, and every existing assertion
/// about these five was satisfied by a window taller than the display it was on.
///
/// This suite is the ceiling. It is deliberately one suite over all five rather than five suites
/// one surface at a time, because *"a treatment one half received and the other did not"* is the
/// shape every finding in this epic has had — the fix that guarded the accusation cap and left the
/// interruption cap one line above it, the proof that drove the popover wire and not the glyph
/// wire two lines below. A surface added to the app and not to `Self.surfaces` is a surface with
/// no size commitment, and `everySurfaceIsListed` is what makes that visible.
@Suite("Every surface commits a width and fits on a display", .serialized)
@MainActor
struct SurfaceSizeInventoryTests {
    /// A 13-inch laptop. The display this family of defects is worst on, and the one that makes
    /// the readings the same on every machine that runs the gate.
    static let laptop = DisplayGeometry(
        displayID: 1,
        screenIndex: 0,
        isPrimary: true,
        frame: ScreenRect(x: 0, y: 0, width: 1470, height: 956),
        visibleFrame: ScreenRect(x: 0, y: 0, width: 1470, height: 918),
        backingScaleFactor: 2
    )

    /// One surface, its committed width, and the ceiling it is held to.
    struct Surface {
        let name: String
        let width: Double
        let ceiling: Double?
        let view: AnyView
    }

    static var sheetCeiling: Double? { ShellSurfaceBounds.sheetCeiling(screens: [Self.laptop]) }
    static var settingsCeiling: Double? {
        ShellSurfaceBounds.settingsCeiling(screens: [Self.laptop])
    }

    /// A sentence long enough that no surface can pretend its content is short. Every one of these
    /// surfaces draws something the person wrote, and none of them bounds it except the handoff
    /// sheet, which stops at 500 characters.
    static let longIntent = String(
        repeating: "Write the Q3 proposal for Acme and then review it end to end. ",
        count: 12
    )

    static var surfaces: [Surface] {
        [
            Surface(
                name: "completionSheet",
                width: ShellSurfaceBounds.completionSheetWidth,
                ceiling: Self.sheetCeiling,
                view: AnyView(
                    CompletionSheet(
                        intent: Self.longIntent,
                        complete: { _, _ in },
                        cancel: {},
                        screens: [Self.laptop]
                    )
                )
            ),
            Surface(
                name: "interruptionSheet",
                width: ShellSurfaceBounds.interruptionSheetWidth,
                ceiling: Self.sheetCeiling,
                view: AnyView(
                    InterruptionSheet(
                        lastActiveBundleID: "com.apple.Safari",
                        stop: { _, _ in },
                        cancel: {},
                        screens: [Self.laptop]
                    )
                )
            ),
            Surface(
                name: "handoffSheet",
                width: ShellSurfaceBounds.handoffSheetWidth,
                ceiling: Self.sheetCeiling,
                view: AnyView(
                    HandoffConfirmationSheet(
                        request: HandoffRequest(
                            verb: .start,
                            task: String(Self.longIntent.prefix(500)),
                            doneWhen: "the draft is sent",
                            flags: []
                        ),
                        current: nil,
                        replace: {},
                        cancel: {},
                        screens: [Self.laptop]
                    )
                )
            ),
            Surface(
                name: "privacySettings",
                width: ShellSurfaceBounds.settingsWidth,
                ceiling: Self.settingsCeiling,
                view: AnyView(PrivacySettingsView(screens: [Self.laptop]))
            ),
            Surface(
                name: "interventionSettings",
                width: ShellSurfaceBounds.settingsWidth,
                ceiling: Self.settingsCeiling,
                view: AnyView(
                    InterventionSettingsView(settings: .init(), screens: [Self.laptop])
                )
            )
        ]
    }

    /// The five names above, plus the quick-capture panel, which is an `NSPanel` and is measured
    /// through its controller rather than as a view. Spelled out so that a surface added to one
    /// list and not the other is a failure rather than a silence.
    static let inventory = [
        "completionSheet",
        "interruptionSheet",
        "handoffSheet",
        "privacySettings",
        "interventionSettings",
        "quickCapturePanel"
    ]

    static func measure(
        _ view: some View,
        textScale: ShellTextScale,
        offeringWidth width: Double
    ) -> CGSize {
        NSHostingController(
            rootView: AnyView(view.appearanceTraits(.light).shellTextScale(textScale))
        )
        .sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
    }

    static func scrolls(_ view: some View, textScale: ShellTextScale, at size: CGSize) -> Bool {
        let controller = NSHostingController(
            rootView: AnyView(view.appearanceTraits(.light).shellTextScale(textScale))
        )
        controller.view.frame = NSRect(origin: .zero, size: size)
        controller.view.layoutSubtreeIfNeeded()
        var found = false
        func walk(_ view: NSView) {
            if view is NSScrollView { found = true }
            view.subviews.forEach(walk)
        }
        walk(controller.view)
        return found
    }

    // MARK: - The width is a commitment, not a floor

    /// Offered four thousand points, a surface with a committed width takes the width it committed
    /// to. A `minWidth` takes all four thousand — which is what "no size commitment" meant in
    /// practice, and why a lens reported the Privacy pane unreadable *at any window width*.
    @Test(
        "no surface grows sideways when it is offered the room to",
        arguments: ShellTextScale.allCases
    )
    func everySurfaceCommitsItsWidth(textScale: ShellTextScale) {
        for surface in Self.surfaces {
            let size = Self.measure(surface.view, textScale: textScale, offeringWidth: 4_000)
            #expect(
                abs(Double(size.width) - surface.width) <= SurfaceSizeCommitments.tolerance,
                """
                offered 4000 points, \(surface.name) took \(Double(size.width)) rather than the \
                \(surface.width) it commits to
                """
            )
        }
    }

    // MARK: - The height fits on a display

    @Test(
        "no surface is ever taller than the display it is drawn on",
        arguments: ShellTextScale.allCases
    )
    func noSurfaceExceedsItsCeiling(textScale: ShellTextScale) {
        for surface in Self.surfaces {
            guard let ceiling = surface.ceiling else { continue }
            let size = Self.measure(
                surface.view,
                textScale: textScale,
                offeringWidth: surface.width
            )
            #expect(
                Double(size.height) <= ceiling + SurfaceSizeCommitments.tolerance,
                """
                \(surface.name) opens \(Double(size.height)) points tall at \(textScale.rawValue) \
                on a display that can show \(ceiling)
                """
            )
        }
    }

    /// **Clamping without scrolling is clipping.** Every surface that had to be clamped must come
    /// back with a scroll view, or its buttons are laid out below the fold — which is the same
    /// defect `DecisionSurfaceReachability` reports for the nudge panel, reached from the other
    /// side.
    @Test(
        "a surface that had to be clamped scrolls rather than cutting off",
        arguments: ShellTextScale.allCases
    )
    func aClampedSurfaceScrolls(textScale: ShellTextScale) {
        for surface in Self.surfaces {
            guard let ceiling = surface.ceiling else { continue }
            let size = Self.measure(
                surface.view,
                textScale: textScale,
                offeringWidth: surface.width
            )
            guard Double(size.height) >= ceiling - SurfaceSizeCommitments.tolerance else { continue }
            let scrolls = Self.scrolls(surface.view, textScale: textScale, at: size)
            #expect(
                scrolls,
                """
                \(surface.name) is at its \(ceiling)-point ceiling at \(textScale.rawValue) and \
                drew no scroll view: whatever is past the clamp is unreachable
                """
            )
        }
    }

    // MARK: - The quick-capture panel

    /// The one of the five that is an `NSPanel`. Its style mask had no `.resizable`, so it could
    /// neither grow nor be dragged: at the largest accessibility text size its content needed more
    /// than the 140 points it was built at, and the Save button was laid out below the bottom edge
    /// with no gesture in macOS that reached it.
    @Test("the quick-capture panel can be resized, and commits a size that fits the display")
    func theCapturePanelIsBounded() {
        let controller = QuickCapturePanelController(screens: [Self.laptop])
        defer { controller.hide() }
        controller.show()

        let ceiling = ShellSurfaceBounds.capturePanelCeiling(screens: [Self.laptop]) ?? .infinity
        let size = controller.contentSize
        #expect(
            abs(Double(size.width) - ShellSurfaceBounds.capturePanelWidth)
                <= SurfaceSizeCommitments.tolerance,
            "the capture panel opened \(Double(size.width)) points wide"
        )
        #expect(
            Double(size.height) <= ceiling + SurfaceSizeCommitments.tolerance,
            "the capture panel opened \(Double(size.height)) points tall against a \(ceiling) ceiling"
        )
        #expect(
            Double(size.height) >= ShellSurfaceBounds.capturePanelMinimumHeight
                - SurfaceSizeCommitments.tolerance,
            "the capture panel opened \(Double(size.height)) points tall, below its own floor"
        )
        #expect(
            controller.isResizable,
            "the capture panel cannot be resized, so content it outgrows can never be reached"
        )
    }

    /// **The reading that keeps the two assertions above from being vacuous.**
    ///
    /// Both skip a surface that fits, which is right — a short sheet has nothing to scroll — and
    /// which means a suite where nothing ever reached its ceiling would be green and prove
    /// nothing. Measured on a 13-inch laptop, four of the five surfaces reach it: the Privacy pane
    /// at **both** text sizes, which is the lens's report that it cannot be read at the shipping
    /// text size, as a number.
    ///
    /// If this goes red the surfaces have shrunk, and `noSurfaceExceedsItsCeiling` and
    /// `aClampedSurfaceScrolls` have quietly stopped asserting anything.
    @Test("the clamp is actually exercised, so the assertions above are not vacuous")
    func theClampIsReached() {
        var reached: [String] = []
        for scale in ShellTextScale.allCases {
            for surface in Self.surfaces {
                guard let ceiling = surface.ceiling else { continue }
                let size = Self.measure(
                    surface.view,
                    textScale: scale,
                    offeringWidth: surface.width
                )
                if Double(size.height) >= ceiling - SurfaceSizeCommitments.tolerance {
                    reached.append("\(surface.name)@\(scale.rawValue)")
                }
            }
        }
        #expect(
            reached.contains("privacySettings@standard"),
            """
            the Privacy pane no longer reaches its ceiling at the standard text size on a laptop.             That was the defect this round is about; if it is genuinely gone, the assertions that             skip a surface which fits are now proving less than they read as
            """
        )
        #expect(
            reached.count >= 4,
            "only \(reached.count) surface/size pairs reach a ceiling: \(reached)"
        )
    }

    // MARK: - The inventory itself

    /// A surface added to the application and not to this file is a surface with no size
    /// commitment, and nothing else in the programme would say so. This is the assertion that
    /// makes the list a list rather than a sample.
    @Test("every surface named in the inventory is actually measured here")
    func everySurfaceIsListed() {
        let measured = Set(Self.surfaces.map(\.name) + ["quickCapturePanel"])
        #expect(
            measured == Set(Self.inventory),
            """
            the inventory and the surfaces this suite measures disagree: \
            \(Set(Self.inventory).symmetricDifference(measured).sorted())
            """
        )
    }
}
