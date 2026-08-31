import AppKit
import SwiftUI

/// The menu bar, built from the command registry.
///
/// Two groups, and both exist because a measurement said so:
///
/// * `.newItem` is replaced by the registry's `file` actions. With that group left empty —
///   or holding only a `Divider()`, or left at SwiftUI's defaults — a `Window`-scene app has
///   **no File menu at all** and ⌘W is unclaimed. Putting one real action in it materialises
///   the menu, after which AppKit contributes its own `Close` and `Close All ⌥⌘W`.
/// * `.help` is replaced by the registry's `help` actions, because SwiftUI's default Help
///   item opens a help book this app does not ship. A menu item that leads nowhere is a
///   defect, and this is the fix.
///
/// Nothing else is customised. Edit, View and Window are the system's, and an app that
/// rewrites them for no reason is less Mac-native, not more.
public struct ShellCommands: Commands {
    private let registry: CommandRegistry
    private let commandCenter: FocusCommandCenter

    @Environment(\.openWindow) private var openWindow

    public init(
        registry: CommandRegistry = .shell,
        commandCenter: FocusCommandCenter = .shared
    ) {
        self.registry = registry
        self.commandCenter = commandCenter
    }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            // **The application's one route to the cockpit window, handed to the one object that
            // needs it** (focus-mwm).
            //
            // `openWindow` is an environment value, so it exists only while something is being
            // evaluated — and a `Commands` body is evaluated when AppKit builds the main menu,
            // at launch, whether the cockpit is open or not. That is the property this needs: the
            // menu-bar popover and the nudge panel are reachable with the main window shut, and
            // neither of them is anywhere SwiftUI's environment reaches.
            //
            // It is a declaration in a result builder rather than a statement in `perform`,
            // because `perform` runs on a click and the surfaces that need the opener are not
            // this one. `CockpitView.body` records its render through the same idiom.
            //
            // Idempotent: the same closure over the same scene, re-installed on every evaluation.
            let _ = commandCenter.registerCockpitOpener { openWindow(id: ShellWindow.cockpit.id) }
            actionButtons(in: .file)
        }

        // The View menu, materialised the same way the File menu is. `after: .sidebar` puts the
        // group where a person looks for "hide this" — under the system's own view items rather
        // than above them, because the system's are the ones they already know.
        CommandGroup(after: .sidebar) {
            actionButtons(in: .view)
        }

        CommandGroup(replacing: .help) {
            actionButtons(in: .help)
        }
    }

    @ViewBuilder
    private func actionButtons(in placement: MenuPlacement) -> some View {
        ForEach(registry.actions(in: placement)) { action in
            ShellActionButton(action: action, perform: perform)
        }
    }

    /// Carries out an action's declared effect.
    ///
    /// `performClose(nil)` rather than `close()`: it runs the standard close path, so a
    /// window that wants to intervene still can, which is what every other Mac app's ⌘W
    /// does.
    private func perform(_ effect: ShellActionEffect) {
        switch effect {
        case .closeKeyWindow:
            NSApp.keyWindow?.performClose(nil)
        case .openWindow(let window):
            openWindow(id: window.id)
        case .priority(let command):
            // The window comes forward first and the command follows. If the cockpit was
            // closed it is not listening yet, so the centre holds the command until it is —
            // which is what makes ⌘N from a closed window land in the capture field rather
            // than doing nothing visible.
            //
            // **The nudge verbs do not open it**, and that is the whole of `opensCockpit`:
            // answering a nudge from the keyboard must not raise a window on top of the work
            // the person was asked to go back to, and "hide all overlays" that opened one would
            // be doing the opposite of what it says.
            //
            // Both of those sentences are still true and neither is written here any more
            // (focus-mwm). `if command.opensCockpit { openWindow(…) }` was on this line and on
            // no other, so it was a rule this one caller kept and the two callers a person
            // reaches with the cockpit shut did not. It is the centre's now, which is why this
            // is one statement: a menu item sends, and what a send *means* is one definition.
            //
            // The result is discarded here and nowhere else in the application. A menu item can
            // always be carried out: every `ShellActionEffect.priority` command either opens the
            // cockpit or is one of the nudge verbs the loop observes for the life of the process.
            _ = commandCenter.send(command)
        }
    }
}

/// One menu item, drawn from one registry entry.
///
/// Split out so that the title, the key equivalent and the action all come from the same
/// `ShellAction` value — there is no second place where a menu item's shortcut is written
/// down, which is what stops the menu bar and the shortcut reference from disagreeing.
private struct ShellActionButton: View {
    let action: ShellAction
    let perform: (ShellActionEffect) -> Void

    var body: some View {
        Button {
            perform(action.effect)
        } label: {
            Text(action.title)
        }
        .modifier(ShortcutModifier(shortcut: action.shortcut))
    }
}

/// Applies a key equivalent when the action declares one, and nothing when it does not.
private struct ShortcutModifier: ViewModifier {
    let shortcut: Shortcut?

    func body(content: Content) -> some View {
        if let shortcut {
            content.keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.modifiers)
        } else {
            content
        }
    }
}
