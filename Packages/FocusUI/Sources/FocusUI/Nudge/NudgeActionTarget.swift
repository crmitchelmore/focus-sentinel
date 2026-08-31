import FocusCore
import SwiftUI

/// **Where every action the panel offers actually landed** (focus-vpu, focus-kby).
///
/// ## Why the layout reports itself rather than being asserted about
///
/// "The window is the size it says it is" was the claim the last fix made, and a panel can
/// satisfy it while three of its six buttons are below the clip. The only honest form of the
/// claim is about the **actions**: a decision surface whose Pause button a person cannot reach
/// is not a decision surface. Nothing outside the layout knows where a button ended up — SwiftUI
/// draws no `NSView` a caller can ask — so the layout says, through a preference, and
/// `NudgePanelController` reads it.
///
/// The frames are reported in the panel's own named coordinate space, which the controller
/// declares around the whole content area. A view rendered outside a panel — the snapshot lane,
/// a preview — has no such space, and `GeometryReader` answers `.zero` for it, which is exactly
/// right: nothing is claiming anything about a layout that is not in a panel.
struct NudgeActionFrameSet: Equatable {
    /// Which layout these frames came from. **The whole reason the value is a struct.**
    ///
    /// `onPreferenceChange` fires when the *value* changes, and a panel laid out twice with the
    /// same content produces the same frames — so a controller that cleared its collection before
    /// each layout would never hear the second one and would read an empty set for a panel that
    /// is drawn perfectly. Measured: exactly that, on every one of the six cross-product cells.
    /// The generation makes each layout's value distinguishable from the last, and it also lets
    /// the controller refuse frames that belong to a layout it has already replaced.
    var generation: Int
    var frames: [String: CGRect]

    static let empty = NudgeActionFrameSet(generation: 0, frames: [:])
}

struct NudgeActionFramesKey: PreferenceKey {
    static let defaultValue = NudgeActionFrameSet.empty

    static func reduce(value: inout NudgeActionFrameSet, nextValue: () -> NudgeActionFrameSet) {
        let next = nextValue()
        value.generation = max(value.generation, next.generation)
        value.frames.merge(next.frames) { _, latest in latest }
    }
}

extension EnvironmentValues {
    /// Which layout pass the panel is on. Injected by `NudgePanelController`, read by every
    /// action target, and present in the preference value so that two identical layouts are two
    /// distinguishable readings.
    @Entry var nudgeLayoutGeneration: Int = 0
}

extension View {
    /// Report this control's frame as the hit target for one offered action.
    ///
    /// - Parameter identifier: the action's own `rawValue` — `CorrectionAction.pause` is
    ///   `"pause"`, `QueryAnswer.yesAddIt` is `"yesAddIt"` — so the set the layout reports and
    ///   the set the presentation offers are the same vocabulary rather than two that have to be
    ///   kept in step.
    func nudgeActionTarget(_ identifier: String) -> some View {
        modifier(NudgeActionTarget(identifier: identifier))
    }
}

/// One action, reporting its own frame.
///
/// A `ViewModifier` rather than a closure over `background(_:)` so that the environment read is
/// declared once: the generation has to reach the preference *value*, and a view that reported a
/// frame without one would be a reading nobody could tell apart from the previous layout's.
struct NudgeActionTarget: ViewModifier {
    let identifier: String

    @Environment(\.nudgeLayoutGeneration) private var generation

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: NudgeActionFramesKey.self,
                    value: NudgeActionFrameSet(
                        generation: generation,
                        frames: [
                            identifier: proxy.frame(
                                in: .named(NudgePanelContent.coordinateSpace)
                            )
                        ]
                    )
                )
            }
        )
    }
}

/// The panel's content, wrapped in the two things that make its layout measurable.
///
/// Kept as a type rather than a chain of modifiers in the controller so that the coordinate
/// space the frames are reported in and the reader that collects them are declared in one place —
/// a space declared at one level and read at another is a bug that reports plausible-looking
/// frames measured from the wrong origin.
struct NudgePanelContent: View {
    /// The name every action frame is measured against.
    static let coordinateSpace = "focus.nudge.panel"

    let inset: Double
    /// **What gives way when the surface will not fit** (focus-din).
    ///
    /// It was a `Bool` — *does this scroll?* — and a surface that scrolls its own actions is a
    /// surface whose reading can never say they are reachable, so a nudge on one was never
    /// charged and the ladder parked. The question is not whether the surface scrolls but **what
    /// scrolls**, and there are three answers rather than two:
    ///
    /// * `nothingScrolls` draws the column exactly as it was written, which is what a surface that
    ///   fits has always done;
    /// * `theContextScrolls` puts the scroll around what the decision is *about* and leaves the
    ///   actions in the viewport, so a person who never scrolls can still reach every one of them
    ///   and a person who does cannot move them out of reach;
    /// * `everythingScrolls` is the residual — the actions alone do not fit — and the reading
    ///   then refuses the charge, which is the truth about that surface.
    let overflow: DecisionSurfaceOverflow
    let layout: DecisionSurfaceLayout
    let onFrames: (NudgeActionFrameSet) -> Void

    var body: some View {
        Group {
            switch overflow {
            case .nothingScrolls:
                padded(layout.whole)
            case .theContextScrolls:
                // `spacing: 0` because each half carries its own inset: the gap between the last
                // line of the context and the first action is the two insets, which is the gap the
                // undivided column already draws between its sections.
                VStack(spacing: 0) {
                    // The scroll view is fully flexible and the decision is not, so a `VStack`
                    // gives the decision its ideal height first and hands the scroll whatever is
                    // left — which is the arithmetic `SurfaceSizeCommitments.overflow(…)` already
                    // proved fits before choosing this branch.
                    ScrollView(.vertical) { padded(layout.context) }
                    padded(layout.decision)
                }
            case .everythingScrolls:
                ScrollView(.vertical) { padded(layout.whole) }
            }
        }
        // **No `maxHeight` here, and that is a measurement decision.** This same view is what
        // `NudgePanelController` measures at the committed width with an unbounded height
        // proposal; a `maxHeight: .infinity` inside it would expand to that proposal and answer
        // `greatestFiniteMagnitude`, which is the fitting-size defect wearing a new hat. The
        // panel's own fill frame is applied outside, where it governs the live layout only.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .coordinateSpace(name: Self.coordinateSpace)
        .onPreferenceChange(NudgeActionFramesKey.self) { frames in
            // SwiftUI delivers preference changes on the main actor; the assumption is stated
            // rather than hidden behind a hop, because a hop would make the reading arrive one
            // turn after the show and every caller would read the frames of the previous nudge.
            MainActor.assumeIsolated { onFrames(frames) }
        }
    }

    private func padded(_ view: AnyView) -> some View {
        view
            .padding(inset)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension AccusationPresentation {
    /// The actions this panel is offering, as the identifiers the layout reports them under.
    ///
    /// Two of the six are conditional, and this is derived from `offeredActions` rather than
    /// from `actionOrder` for exactly that reason: a panel with no return target does not draw
    /// "Back to …", and failing it for the button it deliberately did not draw would make the
    /// invariant unsatisfiable (R-88).
    public var offeredActionIdentifiers: [String] { offeredActions.map(\.rawValue) }
}

extension QueryPresentation {
    /// The three answers, as the identifiers the layout reports them under. Never conditional:
    /// a question with an answer missing is the U-1 defect this whole invariant exists to catch.
    public var offeredAnswerIdentifiers: [String] { Self.actionOrder.map(\.rawValue) }
}
