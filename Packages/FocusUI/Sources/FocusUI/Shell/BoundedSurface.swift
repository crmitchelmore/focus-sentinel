import AppKit
import FocusCore
import SwiftUI

/// **The four commitments, for a surface that has no window controller to measure it**
/// (focus-nu6).
///
/// The nudge panel and the popover are `NSWindow`s owned by a controller, so each can measure its
/// content with `NSHostingController.sizeThatFits(in:)` and set a content size. The Settings panes
/// and the three sheets are plain SwiftUI hosted by somebody else, and there is no moment in their
/// lives at which anything measures them. They committed a `minWidth` and nothing else, so at the
/// shipping text size the Privacy pane laid out 2 699 points tall — taller than any display made —
/// and its lower half was unreachable on every Mac, at every window width.
///
/// This is the same four commitments expressed declaratively:
///
/// * the **width** is committed, and text wraps into it rather than the surface growing sideways;
/// * the **wrapped height** is what `ViewThatFits` measures when it tries the plain column first;
/// * it is **clamped** to `ceiling`, which `SurfaceSizeCommitments` derives from the display;
/// * and content over the clamp **scrolls**, so nothing is ever cut off.
///
/// ## Why it is built exactly this way
///
/// Measured on this machine, over the four candidate constructions, because SwiftUI's answer to
/// "how tall are you" depends on what it was proposed and the surfaces here are proposed different
/// things — a sheet proposes an unbounded height, a window proposes its own:
///
/// | construction | short content | tall content |
/// |---|---|---|
/// | `ScrollView { column }` | greedy: fills whatever it is offered | greedy |
/// | `ViewThatFits { … }.frame(maxHeight:)` | **400 for 64 points of content** | 400, scrolls |
/// | `ViewThatFits { … }` alone | 64, correct | **952: no clamp under an unbounded proposal** |
/// | this one | 64, correct | 400, scrolls |
///
/// The `fixedSize` is what undoes `frame(maxHeight:)`'s greediness — a `maxHeight` frame reports
/// the whole proposal, so without it every short sheet would open at the height of the display —
/// and the `frame(height:)` on the scrolling branch is what gives `ViewThatFits` a second
/// candidate that is *not* greedy, so the choice between them is decided by the content rather
/// than by whichever branch expands furthest.
///
/// ## What this does **not** do, and where the proof lives instead
///
/// `ImageRenderer` cannot rasterise a `ScrollView` at all — not "it reports no intrinsic height",
/// which is what the two Settings panes recorded when they deleted their scroll views to make the
/// snapshot lane work. Measured here, twice: a 40-row column renders 1040 × 1968 with 295 654 ink
/// pixels; the same column inside a `ScrollView` renders **at exactly the same size** — so the
/// height was never the problem — with **zero** ink, and it still renders zero ink when the scroll
/// view is handed its content's measured height explicitly.
///
/// So the baseline lane measures a different subject: it renders the surface's `content`, which is
/// the column that carries every pixel of ink, and this container is proved structurally instead —
/// `BoundedSurfaceTests` lays it out at a real ceiling and asserts an `NSScrollView` appears in
/// the hierarchy exactly when the content exceeds it. The product keeps its overflow behaviour and
/// the harness stops dictating it.
public struct BoundedSurface<Content: View>: View {
    /// The width the surface commits to.
    public let width: Double
    /// The tallest this surface may be. Past it, the content scrolls.
    ///
    /// `nil` when nothing bounds it — no display to read, on a headless rig or a Mac between
    /// display configurations. The column is then drawn whole and nothing scrolls, which is the
    /// same answer `SurfaceSizeCommitments.commit(ceiling: nil)` gives: a surface nobody can
    /// point at cannot be clamped to a screen that is not there.
    public let ceiling: Double?
    private let content: () -> Content

    public init(
        width: Double,
        ceiling: Double?,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.width = width
        self.ceiling = ceiling
        self.content = content
    }

    public var body: some View {
        if let ceiling {
            ViewThatFits(in: .vertical) {
                column
                ScrollView(.vertical) { column }
                    .frame(height: ceiling)
            }
            .frame(maxHeight: ceiling)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            column
        }
    }

    private var column: some View {
        content()
            .frame(width: width, alignment: .leading)
    }
}

/// **Which displays a hosted surface bounds itself against** (focus-nu6).
///
/// The panel takes its displays through an injectable `displays` closure and the popover takes
/// them as an argument, precisely so a test can hand either one a 13-inch laptop and read what it
/// does. A surface that reads `NSScreen.screens` itself can only ever be measured against whatever
/// display the machine running the gate happens to have — which means the interesting case, the
/// small display this defect is worst on, is unreachable from every lane.
///
/// So each hosted surface takes an optional display list. `nil` means the live screens, so the
/// shipping app is bounded whether or not anybody remembers to inject anything, and a test that
/// hands over a laptop gets a deterministic ceiling.
public typealias ShellScreens = [DisplayGeometry]?

/// The ceilings the surfaces without a window controller are held to.
///
/// Each is `SurfaceSizeCommitments.ceiling` with that surface's own three facts: what it reserves
/// on the display, what proportionality limit it sets itself, and how short it may ever be. They
/// are gathered here rather than spelled at five call sites so that "which surfaces have a size
/// commitment" is a question this file answers.
public enum ShellSurfaceBounds {
    /// The margin a hosted surface leaves at the top and the bottom of the display, so a window
    /// flush against the edge of the screen never reads as clipped. The panel's own `edgeMargin`.
    public static let edgeMargin: Double = 24

    /// What a titled window's own chrome costs above its content, so the *window* — not just its
    /// content — fits on the display. Measured against the shipping Settings window: a title bar
    /// and a tab strip.
    public static let windowChromeAllowance: Double = 96

    /// **The Settings window's committed width**, up from the `minWidth: 460` that was all it had.
    public static let settingsWidth: Double = 460

    /// The shortest a Settings pane may be, so a tiny display cannot produce a window with no
    /// room for its own tab strip.
    public static let settingsMinimumHeight: Double = 240

    /// A sheet is modal over the window that raised it, so it reserves more of the display than a
    /// window does: it must sit inside its parent, not merely inside the screen.
    public static let sheetChromeAllowance: Double = 160

    public static let completionSheetWidth: Double = 420
    /// The context sheet (focus-g9iw): wide enough for a row of chips and a rule's verdict
    /// buttons beside its subject, which is what the Details tab gave them.
    public static let contextSheetWidth: Double = 520
    public static let interruptionSheetWidth: Double = 420
    public static let handoffSheetWidth: Double = 480
    public static let sheetMinimumHeight: Double = 160

    /// **The quick-capture panel's committed width.** The panel was built at 560 × 140 with a
    /// `contentMinSize` and a style mask without `.resizable`, which is a window that cannot grow
    /// and cannot scroll: at the largest accessibility text size its Save button was below the
    /// bottom of the panel and there was no gesture in macOS that would reach it.
    public static let capturePanelWidth: Double = 560
    /// The shortest the capture panel may be — its two fields and its buttons at the standard
    /// text size.
    public static let capturePanelMinimumHeight: Double = 120
    /// A capture panel is a small typing surface a person raised deliberately, so its own limit is
    /// generous; the display is what usually binds it.
    public static let capturePanelMaximumHeight: Double = 640

    /// How tall a Settings pane may be on the display it is being drawn on.
    @MainActor
    public static func settingsCeiling(
        screens: [DisplayGeometry] = NudgePanelController.currentScreens()
    ) -> Double? {
        SurfaceSizeCommitments.ceiling(
            screens: screens,
            reserving: windowChromeAllowance + edgeMargin + edgeMargin,
            absoluteMaximum: nil,
            minimum: settingsMinimumHeight
        )
    }

    /// How tall a sheet may be on the display it is being raised over.
    @MainActor
    public static func sheetCeiling(
        screens: [DisplayGeometry] = NudgePanelController.currentScreens()
    ) -> Double? {
        SurfaceSizeCommitments.ceiling(
            screens: screens,
            reserving: sheetChromeAllowance + edgeMargin + edgeMargin,
            absoluteMaximum: nil,
            minimum: sheetMinimumHeight
        )
    }

    /// How tall the quick-capture panel's content may be.
    @MainActor
    public static func capturePanelCeiling(
        screens: [DisplayGeometry] = NudgePanelController.currentScreens()
    ) -> Double {
        SurfaceSizeCommitments.ceiling(
            screens: screens,
            reserving: edgeMargin + edgeMargin,
            absoluteMaximum: capturePanelMaximumHeight,
            minimum: capturePanelMinimumHeight
        ) ?? capturePanelMaximumHeight
    }
}

extension View {
    /// **Bound a sheet to the display it is being raised over** (focus-nu6).
    ///
    /// The three sheets each committed a `minWidth` and nothing else — a floor, which says how
    /// small they may be and never how large. A sheet is modal over the window that raised it, so
    /// content that outgrows the display cannot be scrolled to, dragged into view, or dismissed
    /// past: `HandoffConfirmationSheet` bounds its input at 500 characters and the other two do
    /// not bound theirs at all.
    ///
    /// Applied where the `minWidth` was, so the width becomes a commitment rather than a floor and
    /// the height gains the ceiling and the scroll it never had.
    @MainActor
    public func boundedSheet(width: Double, screens: ShellScreens = nil) -> some View {
        BoundedSurface(
            width: width,
            ceiling: ShellSurfaceBounds.sheetCeiling(
                screens: screens ?? NudgePanelController.currentScreens()
            )
        ) {
            self
        }
    }
}
