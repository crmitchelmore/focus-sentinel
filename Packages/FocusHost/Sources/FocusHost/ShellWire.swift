import Foundation

/// **The wires that live in the application target, named** (focus-cp2, focus-2er).
///
/// ## Why this type exists
///
/// `App/` is not a package. No test bundle can import it, so every closure in the scene graph is
/// unreachable from the unit lane — and four no-op mutations to those closures survived the whole
/// nineteen-stage gate byte for byte, with an empty diff between the clean run's ok-assertions
/// and the mutant's. A second pass found eight more, applied together: the cockpit's whole live
/// state frozen into a placeholder, the session timer always zero, the Privacy pane always saying
/// nothing is watched, dark mode and every accessibility setting ignored, the Intervention pane's
/// Voice and Reduced-Interruption controls reaching nothing, the theme never persisted. Every
/// stage still passed.
///
/// One of `App/`'s wires was never in that state: deleting `AppComposition.shared.start()` from
/// `FocusSentinelApp.init()` is caught loudly, seven self-check assertions at once. That is the
/// shape the rest have to be brought into — because the self-check is the only lane in the
/// programme that runs the shipping scene graph in the shipping process, which is what `App/`
/// *is*.
///
/// So each wire says its own name when it fires, the composition root remembers which names it
/// has heard, and `--focus-self-check` reports the set. A wire mutated to a no-op stops saying
/// its name, and the gate fails by that name rather than by a symptom three objects away.
///
/// ## What a receipt is not
///
/// It is not the assertion. A wire that fires and does nothing would still report itself, so
/// every receipt below is checked **beside** the effect it is supposed to have had: the journal
/// holding the window's own undo manager, the capture panel holding traits somebody gave it, the
/// handoff sitting in `CockpitState` waiting for a person to press Replace, the connection
/// carrying the live projections rather than a placeholder. The receipt says *which* wire, the
/// effect says *whether*.
///
/// ## The two shapes a wire can have, and why the second one exists
///
/// * A **verb** the scene calls — `undoManagerChanged`, `handoffReceived`, `settingsAppeared`.
///   Gutting it is deleting a call, and the name stops arriving.
/// * A **connection** the scene asks for and hands to a view — `cockpit…`, `settings…`. Gutting
///   *that* would mean fabricating the value instead, so the pair is reported: the root records
///   `…Connected` when it is asked, and the **view body** records `…Rendered` through a closure
///   only the root can supply. Asking and not using it fails the second; using something else
///   fails both.
public enum ShellWire: String, CaseIterable, Sendable {
    /// `@Environment(\.undoManager)` arrived or changed. It is `nil` until a window exists, and
    /// this is what hands it to both journals so ⌘Z in the standard Edit menu drives them (F-93).
    case undoManagerChanged
    /// The Mac's appearance or accessibility settings changed, or the person chose a different
    /// appearance in Settings. This is what themes the pre-built quick-capture panel.
    case appearanceChanged
    /// A `focus://` URL arrived. It **shows** and never mutates: there is no route from here to
    /// a stored priority that does not pass through a person pressing Replace (F-142).
    case handoffReceived

    /// The cockpit scene asked the composition root for the window's live connection — the
    /// state, both mutation hosts, the elapsed figure and the last foreign bundle identifier.
    case cockpitConnected
    /// …and that connection reached `CockpitView.body`. Recorded by the view, through a closure
    /// the composition root supplied, so a scene that asked and then drew a placeholder is
    /// caught as well as one that never asked.
    case cockpitRendered
    /// The Settings scene asked for its connection: the appearance preference and the verb that
    /// stores it, the Privacy pane's three live projections, and the Intervention pane's
    /// settings and action sink.
    case settingsConnected
    /// …and that connection reached `ShellSettingsView.body`.
    case settingsRendered
    /// The Settings window appeared, so the stored appearance preference was re-read. The window
    /// may be opened long after launch, and the observer was built before the person last chose.
    case settingsAppeared

    /// The Keyboard Shortcuts reference reached its window. Its `.appearanceTraits` injection
    /// fires whatever is inside the scene, so without this a window with a correct title and
    /// nothing in it is indistinguishable from the shipping one.
    case helpRendered

    /// The cockpit scene injected the live `AppearanceTraits` into its window's environment.
    /// Without it the cockpit ignores dark mode and every accessibility setting.
    case cockpitThemed
    /// The Keyboard Shortcuts window did the same.
    case helpThemed
    /// The Settings window did the same.
    case settingsThemed
}

/// **Which window is being themed** (focus-2er).
///
/// Three scenes each inject `AppearanceTraits`, and three separate injections need three separate
/// receipts: one shared name would be satisfied by whichever scene happened to draw first, and
/// gutting the other two would be invisible. The enum exists so the call sites cannot drift from
/// the receipts — a surface with no case cannot be themed, and a case with no surface fails the
/// self-check for want of anybody to fire it.
public enum ShellThemedSurface: String, CaseIterable, Sendable {
    case cockpit
    case help
    case settings

    /// The receipt this surface's injection records.
    public var wire: ShellWire {
        switch self {
        case .cockpit: .cockpitThemed
        case .help: .helpThemed
        case .settings: .settingsThemed
        }
    }
}
