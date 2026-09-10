import AppKit
import FocusCore

/// **A second renderer of the ambient rung, and not a fifth surface** (e08a, `focus-26b`).
///
/// ## What it draws, and what it is forbidden to draw
///
/// One line, one to two points tall, the width of `NotchLanding.Landing.collapsed`, flush under
/// the housing on the built-in display. No glyph, no capsule, no text, no timer, no shape mark.
/// The marks half of the subset invariant is therefore held **by construction** in e08a: the
/// companion's mark is `.unmarked` in every state, which is the floor of the legal subset rather
/// than a value chosen for it. Marks, pulse and expansion are e08b and wait on the receipts
/// `README` names — none of them may be built from this file until those arrive.
///
/// ## The two conjuncts, and why the second one is new law
///
/// `NotchCompanionPresentation.derive(…)` is the whole decision, and it holds two things:
///
/// 1. **marks** — `companion.mark ∈ {.unmarked, presentation.attention}`;
/// 2. **visibility** — `companion != nil ⟹ menuBarVisible && itemVisible`.
///
/// The second is the review's §3 finding. `SurfaceRouter` defers the ambient rung on
/// `menuBarVisible == false` alone, and `MenuBarController.redraw(force:)` early-returns on
/// `guard isItemVisible || force`, so `glyphWriteCount` and `markOnTheItem` never move when the
/// item is off screen — and `PerceptibleChange.proven` needs exactly that increment plus that
/// transition. Status-item overflow is not a suppression, is invisible to `suppressesOverlays`,
/// and is **more likely on a notched Mac** because the housing eats the centre of the bar. Without
/// conjunct 2 the companion becomes the only surface a rung reaches, which is focus-mkk inverted:
/// a `noticing` line in plain view beside a ledger row reading *"deferred, menuBarHidden"*.
///
/// If any later slice lets the companion draw where the glyph could not, the notch has stopped
/// being a renderer and has become a fifth surface — which needs its own `PerceptionChannel`, its
/// own difference arithmetic and its own `surfacesARungCanReach` row. That is the tripwire, and
/// `NudgeUnseenAttemptTests` is where it is pulled.
///
/// ## The window, and the two flags that are rulings
///
/// * `level = .floating`, **explicitly not `.statusBar`**. Nothing in `Packages/*/Sources` uses
///   `.statusBar`; `NudgePanelController` and `QuickCapturePanelController` are both `.floating`,
///   so the e08 plan's "verified in this repo already" was false. `.statusBar` is unmeasured here
///   and waits on P-e08-A.
/// * `collectionBehavior` is `[.canJoinAllSpaces, .stationary, .ignoresCycle]` and **never**
///   `.fullScreenAuxiliary`. P-130 measured a `.fullScreenAuxiliary` panel drawn plainly over a
///   real full-screen space and the frame was read; R-96n permits the union in `NudgePanel.swift`
///   alone, so a second adder is a lint failure as well as a defect. On a full-screen space the
///   companion is simply absent — which conjunct 2 demands anyway, because the menu bar is not
///   visible there.
///
/// It ignores mouse events entirely: there is no tracking area until e08b, and a strip that
/// swallowed a click over the menu bar would be a theft with no affordance behind it.
final class NotchCompanionPanel: NSPanel {
    /// **`false`, both of them.** The companion has nothing to answer and nothing to type into,
    /// so a window that could take the keyboard or become the application's main window would be
    /// taking something for nothing — which is R-89's whole subject seen from the quietest surface
    /// the app has.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The behaviour the companion starts and ends with. Deliberately a `let` and deliberately not
    /// a function of the presentation gate: unlike `NudgePanel`, there is no state in which this
    /// window may join a full-screen space, because there is no state in which the menu bar it
    /// belongs to is visible there.
    static let collectionBehavior: NSWindow.CollectionBehavior =
        [.canJoinAllSpaces, .stationary, .ignoresCycle]

    /// Borderless and non-activating. There is no title, no chrome and nothing to drag: the strip
    /// is positioned by geometry and by nothing a person does.
    static let companionStyleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
}

/// The view that draws the one line.
///
/// AppKit rather than SwiftUI, and a fill rather than a `Text`: this is the only view in the shell
/// with nothing to lay out, and hosting a SwiftUI view to fill two points would be a hosting view,
/// an environment and a renderer for a rectangle.
final class NotchCompanionLineView: NSView {
    /// **The ambient rung's existing tint.** `labelColor` is what a template menu-bar image
    /// resolves to in the bar it is drawn in — `MenuBarController.glyph(for:attention:)` sets
    /// `isTemplate = true` precisely so the system tints it — so the strip follows the menu bar
    /// through appearance changes for the same reason the glyph does, without a second colour
    /// table to keep in step.
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.setFill()
        bounds.fill()
    }
}

/// **What the companion would draw, derived from what the item is already drawing.**
///
/// A pure value with no window in it, so the whole table — every refusal × menu bar visible or not
/// × item visible or not × paused or running — is a unit test rather than a screenshot.
public struct NotchCompanion: Sendable, Equatable, Hashable {
    /// Where the line goes, in AppKit coordinates on the display the landing came from.
    public let ink: ScreenRect
    /// **`.unmarked` in every state e08a can produce.** The field exists so the subset invariant
    /// has something to be about and so e08b's marks arrive as a change to one derivation rather
    /// than as a new type; it is not a placeholder for a value this epic sets.
    public let mark: MenuBarAttention

    public init(ink: ScreenRect, mark: MenuBarAttention) {
        self.ink = ink
        self.mark = mark
    }
}

/// The one derivation. Every reading the companion rests on passes through here.
public enum NotchCompanionPresentation {
    /// What the companion draws, or `nil` for *nothing at all*.
    ///
    /// - Parameters:
    ///   - landing: the geometry's own answer. A refusal of any of the six kinds is `nil` here,
    ///     which is why this rig never draws a hairline and why that is a fact about the display
    ///     rather than a flag somebody set.
    ///   - presentation: what the status item is drawing, read for its `attention` and for
    ///     F-119's switch. Never for a mark to copy in e08a.
    ///   - menuBarVisible: `NudgeSurroundings`' own reading — the full-screen space P-131
    ///     measured, and the uninstalled item focus-zeq added.
    ///   - itemVisible: `MenuBarController.isItemVisible`, the overflow case. **A separate
    ///     question**, and the one the review's §3 is about.
    public static func derive(
        landing: NotchLanding,
        presentation: MenuBarPresentation,
        menuBarVisible: Bool,
        itemVisible: Bool
    ) -> NotchCompanion? {
        // Conjunct 2, first, and stated as a guard rather than as a property somebody asserts
        // afterwards: there is no path through this function that reaches an ink frame without
        // passing this line.
        guard menuBarVisible, itemVisible else { return nil }
        // F-119's one global switch, honoured by absence (the pane's own vocabulary). A person who
        // has turned watching off is not shown a line saying the app is watching.
        guard !presentation.sensingPaused else { return nil }
        guard let ink = landing.collapsed else { return nil }

        // Conjunct 1's floor. Written as a constant with the invariant beside it rather than as a
        // computed mark, because e08a draws no mark at all and a derivation that *looked* like it
        // chose one would invite the next round to widen it without widening the proof.
        let mark = MenuBarAttention.unmarked
        guard mark == .unmarked || mark == presentation.attention else { return nil }
        return NotchCompanion(ink: ink, mark: mark)
    }

    /// The marks the companion is **ever** allowed to carry, given what the item is carrying.
    ///
    /// Published so the invariant is a value the test folds over rather than a sentence in a
    /// comment: `{.unmarked, presentation.attention}` is the legal set, and e08a sits on its floor.
    public static func legalMarks(for presentation: MenuBarPresentation) -> Set<MenuBarAttention> {
        [.unmarked, presentation.attention]
    }
}
