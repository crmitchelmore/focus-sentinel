import Foundation

/// **Which windows a relaunch should put back** (focus-odz.6).
///
/// ## What AppKit does and does not do here
///
/// macOS restores a window's *frame* through `NSWindow`'s own autosave, and that part works: a
/// cockpit dragged to the left of the screen comes back on the left. What it does not do for a
/// SwiftUI `Window(id:)` scene is decide whether the window exists at all. Measured in this
/// application's own self-check: a launch that inherits a closed cockpit has **no `NSWindow` for
/// it in `NSApp.windows`** — the same measurement `FocusCommandCenter.registerCockpitOpener` is
/// written against — so there is nothing for AppKit's restoration to restore. The Keyboard
/// Shortcuts window a person left open therefore never came back.
///
/// So the app records which scenes were open when it quit and asks for them again at launch.
///
/// ## Additive only, and that is the decision
///
/// This answers *"what should be opened"* and never *"what should be closed"*. A person who quit
/// with the cockpit shut gets it back at the next launch, because SwiftUI's `Window` scene opens
/// itself and the alternative — closing it a moment after launch because a stored flag said so —
/// is a window that vanishes for a reason nobody can see. The half that was missing is the
/// additive half, and it is the half AppKit does not do.
///
/// A pure function over two lists so that the rule is testable without a window server, which is
/// the same division `DecisionSurfaceReachability` and `ShellRenderFidelity` are built on.
public enum ShellWindowRestoration {
    /// The scenes to ask for, in declaration order.
    ///
    /// - Parameters:
    ///   - recorded: the scene ids stored at the last quit, or `nil` when no quit has been
    ///     recorded — a first launch, or one after a crash. **`nil` and `[]` are different**: with
    ///     nothing recorded there is nothing to restore and the scene graph is left alone; with an
    ///     empty list the person really had closed everything, which is also nothing to open. They
    ///     agree here and disagree in the store, where the distinction is what stops a first
    ///     launch being read as "they closed everything".
    ///   - alreadyOpen: the scene ids that exist right now. SwiftUI opens the cockpit itself, so
    ///     asking for it again would be asking for a window that is already there.
    public static func windowsToReopen(
        recorded: [String]?,
        alreadyOpen: [String]
    ) -> [ShellWindow] {
        guard let recorded else { return [] }
        let wanted = Set(recorded)
        let open = Set(alreadyOpen)
        // Declaration order rather than the recorded order, so two runs that recorded the same set
        // in different orders ask for the same thing — and so the cockpit, if it is ever in this
        // list, comes back before the reference that sits on top of it.
        return ShellWindow.allCases.filter { wanted.contains($0.id) && !open.contains($0.id) }
    }

    /// The scene ids worth recording, out of whatever the window server lists.
    ///
    /// AppKit's `NSApp.windows` holds a great deal that is not a scene — the status item's own
    /// window, the quick-capture panel, a nudge panel, an About panel — so the record is filtered
    /// down to the ids the app **declares**. An unrecognised window is not a scene this app can
    /// ask for again, and storing its identifier would put a value in the column that nothing
    /// could ever act on.
    ///
    /// Sorted and de-duplicated, so the stored value is a fact about the set rather than about the
    /// order AppKit happened to list them in.
    public static func recordable(_ identifiers: [String]) -> [String] {
        let declared = Set(ShellWindow.allCases.map(\.id))
        return Array(Set(identifiers).intersection(declared)).sorted()
    }
}
