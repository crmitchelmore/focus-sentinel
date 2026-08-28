import Foundation

/// **The wires that live in the application target, named** (focus-cp2).
///
/// ## Why this type exists
///
/// `App/` is not a package. No test bundle can import it, so every closure in the scene graph is
/// unreachable from the unit lane — and four no-op mutations to those closures survived the whole
/// nineteen-stage gate byte for byte, with an empty diff between the clean run's ok-assertions
/// and the mutant's.
///
/// One of `App/`'s wires is not like the others: deleting
/// `AppComposition.shared.start()` from `FocusSentinelApp.init()` is caught loudly, seven
/// self-check assertions at once. That is the shape the rest have to be brought into — because
/// the self-check is the only lane in the programme that runs the shipping scene graph in the
/// shipping process, which is what `App/` *is*.
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
/// handoff sitting in `CockpitState` waiting for a person to press Replace. The receipt says
/// *which* wire, the effect says *whether*.
/// ## Three, where there were five
///
/// The cockpit scene used to carry an `.onAppear` beside each `.onChange` doing the same thing.
/// Two statements with one effect are two statements no lane can tell apart — gutting either one
/// changes nothing anybody can observe — so the pairs are now single `.onChange(…, initial: true)`
/// wires, which is exactly what the pair was emulating and which every declared case below can
/// therefore be asserted to have fired.
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
}
