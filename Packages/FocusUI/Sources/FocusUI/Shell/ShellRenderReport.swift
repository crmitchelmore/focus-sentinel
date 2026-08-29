import FocusCore
import SwiftUI

/// **How a window says what it actually drew** (focus-h7h).
///
/// ## Why the view reports rather than being asserted about
///
/// `App/` is not a package, and the only instrument that can observe it is `--focus-self-check`.
/// Every wire in the scene graph now says its own name when it fires, and that was measured to be
/// worth nothing on its own: an eight-part mutation that left every receipt firing and replaced
/// every *value* with a constant passed the whole nineteen-stage gate, 262 ok-assertions against
/// 262, with an empty diff between the clean run's assertion list and the mutant's. The cockpit
/// showed a frozen placeholder, the Privacy pane always said nothing was watched, the three
/// windows ignored dark mode and every accessibility setting, the Keyboard Shortcuts window was
/// empty — and every stage stayed green.
///
/// The root cause is one sentence: **a receipt that fires when a closure runs cannot distinguish
/// a closure that produced the right value from one that produced a constant.** The wire was
/// proved connected; nothing was proved to have travelled down it.
///
/// `DecisionSurfaceReachability` had already solved this exact shape for the nudge panel, and
/// this is the same mechanism pointed at the windows: the **view** reports, through a SwiftUI
/// preference carrying a generation, and the host reads it. Nothing outside the layout knows what
/// a window put on the screen — so the window says, and `AppComposition` holds the answer up
/// beside what the application actually knows.
///
/// The generation is `NudgeActionFrameSet`'s, and it is here for the same measured reason plus
/// one more. `onPreferenceChange` fires when the *value* changes, so a window laid out twice with
/// the same content never delivers the second pass; and a report stamped with a connection the
/// composition root has already replaced is a window drawing from something stale, which is its
/// own defect and has to be legible as one.
///
/// All of it is in-process and needs no grant of any kind: a `PreferenceKey` and one closure.
public struct ShellRenderedValuesKey: PreferenceKey {
    public static let defaultValue = ShellRenderedValues.nothing

    public static func reduce(
        value: inout ShellRenderedValues,
        nextValue: () -> ShellRenderedValues
    ) {
        let next = nextValue()
        value.generation = max(value.generation, next.generation)
        value.values.merge(next.values) { _, latest in latest }
    }
}

extension EnvironmentValues {
    /// Which connection the window is drawing from. Injected by the top-level view out of the
    /// connection the composition root supplied, read by every reporting site, and carried in the
    /// preference value so that two identical layouts are two distinguishable readings.
    @Entry public var shellRenderGeneration: Int = 0
}

extension View {
    /// **Report one value this view actually put on the screen.**
    ///
    /// Attached at the site that draws it, so a section the window did not draw reports nothing
    /// rather than reporting a value nobody can see — which is the difference between
    /// `unreportedFields` and `staleFields` in the reading.
    public func shellRendered(_ field: ShellRenderedField, _ value: String) -> some View {
        modifier(ShellRenderedValue(field: field, value: value))
    }

    /// The same, for a count. `Int` rather than a formatted string so no call site has to decide
    /// how to spell a number.
    public func shellRendered(_ field: ShellRenderedField, _ value: Int) -> some View {
        modifier(ShellRenderedValue(field: field, value: String(value)))
    }
}

/// One value, reporting itself.
///
/// A `ViewModifier` so the environment read is declared once: the generation has to reach the
/// preference **value**, and a report without one could not be told apart from the previous
/// connection's.
///
/// ## Why the value goes through `background(_:)` rather than straight onto the content
///
/// `NudgeActionTarget` does the same thing, and measurement here says why it has to.
/// `View.preference(key:value:)` **sets** the preference for the node it is applied to;
/// `reduce(value:nextValue:)` only ever runs across *children*. So two stamps chained on one view
/// are not merged — the outer one replaces the inner — and a window reporting six values through
/// a chain reports exactly one. Measured in the built app on the first run of this mechanism: the
/// Keyboard Shortcuts window reported its traits and no row count, the Settings window reported
/// its traits and nothing else, and the cockpit reported one field out of nine.
///
/// A `Color.clear` background is a separate child per stamp, so every one of them reaches the
/// reduction. It proposes no size of its own, so nothing about any layout moves.
struct ShellRenderedValue: ViewModifier {
    let field: ShellRenderedField
    let value: String

    @Environment(\.shellRenderGeneration) private var generation

    func body(content: Content) -> some View {
        content.background(
            Color.clear.preference(
                key: ShellRenderedValuesKey.self,
                value: ShellRenderedValues(
                    generation: generation,
                    values: [field.rawValue: value]
                )
            )
        )
    }
}

extension View {
    /// **Collect everything the window below this reported, and hand it to the host.**
    ///
    /// Applied by each of the three top-level window views, and by nothing else: the generation
    /// is injected here so every reporting site below is stamped with it, and the collection
    /// happens here so a value reported by any depth of subview reaches the composition root
    /// through the one closure only the root can supply.
    ///
    /// `report` is `nil` for every caller that builds the view out of loose values — the snapshot
    /// lane, the previews, the unit tests — and a window rendered with no host reports to nobody,
    /// which is right: nothing is claiming anything about a layout that is not in the app.
    public func shellRenderReport(
        generation: Int,
        _ report: (@MainActor (ShellRenderedValues) -> Void)?
    ) -> some View {
        environment(\.shellRenderGeneration, generation)
            .onPreferenceChange(ShellRenderedValuesKey.self) { values in
                // SwiftUI delivers preference changes on the main actor; the assumption is
                // stated rather than hidden behind a hop, because a hop would make the reading
                // arrive one turn after the draw and the self-check would read the previous
                // connection's values — which is the very confusion the generation exists to
                // make visible.
                MainActor.assumeIsolated { report?(values) }
            }
    }
}
