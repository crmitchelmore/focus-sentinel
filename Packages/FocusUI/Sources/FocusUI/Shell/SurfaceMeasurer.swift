import AppKit
import FocusCore
import SwiftUI

/// **The readings a decision surface takes of itself, once** (focus-tzj.6).
///
/// `SurfaceSizeCommitments` is the arithmetic — a pure function of measured values, in
/// `FocusCore`, which may not import SwiftUI. This is the other half: the **instrument** that
/// produces those values, and the one mapping from a surface's frames to
/// `DecisionSurfaceReachability`'s vocabulary. It lives in `FocusUI` because taking a wrapped
/// height means building an `NSHostingController`, and beside the commitments in spirit if not
/// in module: nothing here decides anything, and every number it returns is a measurement.
///
/// The nudge panel and the menu-bar popover each grew their own copy of all three, one
/// measurement at a time, and the copies had drifted into being byte-identical — which is the
/// state in which a repair to one of them silently stops being a repair to the surface a person
/// is actually looking at. The differences that remain between the two surfaces are the
/// parameters: a committed width, a content inset, a ceiling, and a minimum height.
@MainActor
enum SurfaceMeasurer {
    /// **The size a surface commits to for one content, and what gives way if it will not fit.**
    ///
    /// **Two measurements, not one** (focus-din). The whole surface is measured, and then its
    /// **decision** — the pending accusation's corrections and the pending question's answers —
    /// on its own at the same committed width. A surface that will not fit gives way in whichever
    /// of the two ways those numbers permit, and a caller that hands in something with no
    /// decision at all measures a zero for it, which is the honest height of nothing.
    ///
    /// The order is load-bearing for the tally: the whole first, then the decision, so a caller
    /// counting hosting controllers counts them in the order the shipping surface builds them.
    ///
    /// - Parameters:
    ///   - surface: the content, split into what the decision is and what it is about.
    ///   - width: the width the surface commits to. Text wraps into it; it never grows sideways.
    ///   - inset: the padding the surface wears around its content, in points.
    ///   - ceiling: how tall the surface may be on the display it is being placed on, or `nil`
    ///     when nothing bounds it — a headless rig, or a surface with no proportionality limit.
    ///   - minimum: the shortest the surface is ever allowed to be.
    ///   - constructions: incremented once per `NSHostingController` built, so the cost of a
    ///     measurement is readable by whoever is paying it (focus-tzj.1).
    static func layout(
        measuring surface: DecisionSurfaceLayout,
        width: Double,
        inset: Double,
        ceiling: Double?,
        minimum: Double = 0,
        constructions: inout Int
    ) -> (size: CGSize, overflow: DecisionSurfaceOverflow) {
        let measured = measureAtCommittedWidth(
            surface.whole,
            width: width,
            inset: inset,
            constructions: &constructions
        )
        let commitment = SurfaceSizeCommitments.commit(
            measuredHeight: measured,
            width: width,
            ceiling: ceiling,
            minimum: minimum
        )
        return (
            size: CGSize(width: commitment.width, height: commitment.height),
            overflow: SurfaceSizeCommitments.overflow(
                measuredHeight: measured,
                decisionHeight: measureAtCommittedWidth(
                    surface.decision,
                    width: width,
                    inset: inset,
                    constructions: &constructions
                ),
                ceiling: ceiling,
                minimumContextHeight: DecisionSurfaceLayout.minimumContextHeight
            )
        )
    }

    /// The wrapped height of one part of a surface's content, at the width it commits to.
    ///
    /// `NSHostingController.sizeThatFits(in:)` answers "how tall is this content when it is
    /// **given this width**" — the wrapped truth, which is the only number worth having. It is
    /// not `NSView.fittingSize`, which is SwiftUI's *unconstrained* fitting size: that is the
    /// number that drove the nudge panel to 380 × 2212, because the minimum width of a paragraph
    /// is roughly its longest word and at that width the paragraph is two thousand points tall.
    ///
    /// A hosting object of its own rather than the live one, because measuring must not disturb
    /// the view a person is looking at and because the live one carries the frame reporter —
    /// asking *it* to measure would collect the frames of a layout nobody was shown.
    ///
    /// `nothingScrolls` deliberately: this is the *unclamped* height, and a measurement taken
    /// through a scroll view would answer whatever it was proposed.
    static func measureAtCommittedWidth(
        _ part: AnyView,
        width: Double,
        inset: Double,
        constructions: inout Int
    ) -> Double {
        constructions += 1
        let measurer = NSHostingController(
            rootView: AnyView(
                NudgePanelContent(
                    inset: inset,
                    overflow: .nothingScrolls,
                    layout: .undivided(part),
                    onFrames: { _ in }
                )
            )
        )
        return measurer.sizeThatFits(
            in: CGSize(width: width, height: .greatestFiniteMagnitude)
        ).height
    }

    /// **Whether a surface is one a person could actually decide on** (focus-5yu, focus-vpu,
    /// focus-kby, U-1).
    ///
    /// The geometry each controller holds is its own — a popover's window is placed by AppKit
    /// under the menu bar and a panel's by this application — so what is shared is not the
    /// reading's inputs but its **shape**: the content bounds are the size the surface was laid
    /// out at, with its origin at zero, and the action targets are the frames the layout itself
    /// reported, under the identifiers the presentation says it is offering. Both surfaces
    /// answered exactly that, in two copies, and a difference between the copies could only ever
    /// have been a defect.
    static func reading(
        isVisible: Bool,
        surfaceFrame: ScreenRect,
        screens: [DisplayGeometry],
        contentSize: CGSize,
        actionFrames: [String: CGRect],
        offering identifiers: [String]
    ) -> DecisionSurfaceReading {
        DecisionSurfaceReachability.evaluate(
            isVisible: isVisible,
            surfaceFrame: surfaceFrame,
            screens: screens,
            contentBounds: ScreenRect(
                x: 0,
                y: 0,
                width: contentSize.width,
                height: contentSize.height
            ),
            actionTargets: actionFrames.map { identifier, rect in
                ActionHitTarget(
                    identifier: identifier,
                    frame: ScreenRect(
                        x: rect.origin.x,
                        y: rect.origin.y,
                        width: rect.width,
                        height: rect.height
                    )
                )
            },
            offering: identifiers
        )
    }
}
