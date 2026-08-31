import FocusCore
import SwiftUI

/// **A surface split into what may scroll and what must not** (focus-din).
///
/// ## The defect this exists to end
///
/// `focus-vpu` and `focus-5yu` gave the panel and the popover a ceiling and a scroll, so nothing
/// is ever cut off, and `DecisionSurfaceReachability` refuses to count a nudge whose offered
/// actions are not inside the content the person can see. Both of those are right. Together they
/// produce a surface that can never be charged: an action scrolled below the fold is not
/// reachable, **nothing re-takes the reading when the person scrolls**, and so a nudge on a
/// scrolling surface is never delivered however long they look at it.
///
/// Measured through the shipping layout function, on a 1920 × 1080 display (visible frame 961,
/// popover ceiling 911): at `accessibilityLarge` **every** popover state scrolls — empty,
/// question, accusation, both, and both-with-snoozes. For a large-text user a badge rung was
/// therefore never delivered, `openRung` stayed non-nil and unpaid, `LadderMachine` will not
/// escalate without a delivered rung, and the loop parked for good.
///
/// ## What "reachable" means when a surface scrolls
///
/// Not *"one scroll away"*. A charge taken on that would be a charge for an action the person was
/// never shown, and the reading exists precisely because an action somebody cannot reach is not
/// an action they were offered. And not *"re-take the reading when they scroll"* either: that
/// fixes the surface for a person who scrolls and leaves the ladder parked for a person who does
/// not, which is most people most of the time.
///
/// So the surface changes instead of the predicate. **A decision surface never scrolls its
/// decision.** What the nudge is *about* — the sentence, the reason it is being asked, the
/// countdown — gives way and scrolls; the actions stay in the viewport. Then:
///
/// * a person who never scrolls has every action in front of them from the first frame, so the
///   surface is reachable and the rung is charged;
/// * a person who scrolls moves the context under a decision that does not move, so the reading
///   is the same before, during and after — there is no scroll offset for it to be taken at, and
///   nothing needs re-taking;
/// * and a decision that will not fit at all is `everythingScrolls`, where the reading still
///   refuses the charge, honestly, because that surface really is one nobody can decide on.
///
/// One rule for every surface, because both the panel and the popover draw their content through
/// `NudgePanelContent` and it is the container that decides — not the three views, which only say
/// **which part of themselves is the decision**.
public struct DecisionSurfaceLayout {
    /// The surface as one column, in the order it was written. Drawn whenever nothing scrolls, so
    /// a surface that fits is byte-for-byte what it was before this split existed.
    public let whole: AnyView
    /// Everything the decision is about. This is what gives way.
    public let context: AnyView
    /// The offered actions, and nothing else. Never inside a scroll view.
    public let decision: AnyView

    public init(whole: AnyView, context: AnyView, decision: AnyView) {
        self.whole = whole
        self.context = context
        self.decision = decision
    }

    /// The same split with one modifier applied to all three renderings.
    ///
    /// Environment injections — the appearance traits, the text scale — have to reach every part
    /// of the surface *and* the measurement taken of it, and a modifier applied to only one of the
    /// three would produce a layout measured in one environment and drawn in another. Applying it
    /// through the split is what makes that impossible to get wrong.
    public func modified<Modified: View>(
        _ transform: (AnyView) -> Modified
    ) -> DecisionSurfaceLayout {
        DecisionSurfaceLayout(
            whole: AnyView(transform(whole)),
            context: AnyView(transform(context)),
            decision: AnyView(transform(decision))
        )
    }

    /// A surface with no decision to protect — the popover carrying no nudge, and anything a lane
    /// hands in loose. `context` is the whole of it and `decision` is empty, so `theContextScrolls`
    /// and `everythingScrolls` describe the same picture and either is honest.
    public static func undivided(_ content: AnyView) -> DecisionSurfaceLayout {
        DecisionSurfaceLayout(whole: content, context: content, decision: AnyView(EmptyView()))
    }

    /// **How much of what the decision is about must survive the clamp.**
    ///
    /// A floor chosen for the product rather than measured off a font: below it the surface is a
    /// row of buttons under nothing, and a person handed six corrections with no sentence saying
    /// what they are corrections *of* has not been offered a decision. A decision that would leave
    /// less than this behind is not pinned — the surface scrolls whole, and
    /// `DecisionSurfaceReachability` then says, correctly, that this is not a surface anybody can
    /// decide on.
    ///
    /// Both surfaces share it because both draw the same views at the same committed widths.
    public static let minimumContextHeight: Double = 96
}

/// **Every surface in this application that offers a decision a nudge is charged for**
/// (focus-din).
///
/// A closed set with a name, so *"which surfaces have the rule?"* is a question this file answers
/// rather than a list a reader assembles by grepping. The proof folds over `allCases`: a fourth
/// surface added here and not driven fails, and a fourth `DecisionSurfaceContent` that reuses an
/// existing case fails the bijection beside it.
///
/// The Settings panes, the quick-capture panel and the three sheets are **not** here, and that is
/// a statement rather than an omission. `focus-nu6` gave them a ceiling and a scroll, which is why
/// this bead got wider — but none of them offers an action a rung or a question is charged for, so
/// none of them is read by `DecisionSurfaceReachability` and none can park a ladder. A surface
/// that starts offering one belongs in this enum, and the day it does the fold will say so.
public enum DecisionSurface: String, Sendable, Equatable, Hashable, CaseIterable {
    case accusationPanel
    case questionPanel
    case menuBarPopover
}

/// A view that knows which part of itself is the decision (focus-din).
///
/// Three types conform, one per `DecisionSurface`, and the two controllers take one of these
/// rather than an opaque `View` — so a fourth decision surface cannot be added without answering
/// both questions: which part of it is the decision, and which surface it is.
public protocol DecisionSurfaceContent: View {
    /// Which surface this is. Declared rather than inferred, so the inventory and the conformers
    /// are one list and a proof can fold over it.
    static var decisionSurface: DecisionSurface { get }

    /// This surface, split. `body` draws `surfaceLayout.whole`, so the split and the drawing can
    /// never describe two different surfaces.
    var surfaceLayout: DecisionSurfaceLayout { get }
}
