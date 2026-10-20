import AppKit
import SwiftUI

/// The menu bar, built from the command registry.
///
/// Three groups, and each exists because a measurement or a product claim said so:
///
/// * `.newItem` is replaced by the registry's `file` actions. With that group left empty —
///   or holding only a `Divider()`, or left at SwiftUI's defaults — a `Window`-scene app has
///   **no File menu at all** and ⌘W is unclaimed. Putting one real action in it materialises
///   the menu, after which AppKit contributes its own `Close` and `Close All ⌥⌘W`.
/// * `.help` is replaced by the registry's `help` actions, because SwiftUI's default Help
///   item opens a help book this app does not ship. A menu item that leads nowhere is a
///   defect, and this is the fix.
///
/// * `.appInfo` is replaced so the standard About panel is opened with credits from the
///   catalog. SwiftUI's own item already opens that panel; what it opened was an icon, a name
///   and two numbers, for an app whose whole product claim is what it does not look at
///   (focus-odz.3).
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
        // **The About item, replaced rather than left to SwiftUI** (focus-odz.3).
        //
        // SwiftUI's own already opens `orderFrontStandardAboutPanel`, so the defect is not that
        // the item does nothing — it is that the panel it opens says nothing. For an app whose
        // whole product claim is what it does *not* look at, the one screen every Mac user knows
        // how to find carried an icon, a name and two numbers. This is the same standard panel
        // with the credits paragraph from the catalog, and a title that is a catalog key like
        // every other menu item's.
        //
        // It is deliberately **not** a `CommandRegistry` action. The registry is the table the
        // Keyboard Shortcuts window is built from and the table `KeyboardReachabilityTests` folds
        // over key equivalents; About has no shortcut, belongs to no menu the reference groups by,
        // and opens an AppKit panel rather than a declared scene. Adding a `.app` placement for it
        // would give the shortcut reference a heading with one unbound row under it.
        CommandGroup(replacing: .appInfo) {
            Button {
                AboutPanel.present()
            } label: {
                Text(ShellStrings.resource(.commandAbout))
            }
            // Where every Sparkle app puts it: the app menu, straight after About. Like About it
            // is unbound and not a keyboard-reference row.
            CheckForUpdatesButton(commandCenter: commandCenter)
        }

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
            // …and the general one beside it (focus-odz.6). Restoration needs the *other* scene:
            // somebody who left the Keyboard Shortcuts window open and quit should find it open
            // again, and before this nothing in the application could ask for it by id.
            let _ = commandCenter.registerWindowOpener { openWindow(id: $0) }
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
            ShellActionButton(action: action, commandCenter: commandCenter, perform: perform)
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
        case .privacy(let action):
            // Discarded for the reason above and with the same caveat: the composition root
            // installs the performer at launch, and a process that has none is a unit process.
            _ = commandCenter.perform(action)
        }
    }
}

/// One menu item, drawn from one registry entry.
///
/// Split out so that the title, the key equivalent and the action all come from the same
/// `ShellAction` value — there is no second place where a menu item's shortcut is written
/// down, which is what stops the menu bar and the shortcut reference from disagreeing.
///
/// ## And whether it may be offered at all (focus-6uf)
///
/// This drew a plain `Button` with no `.disabled` of any kind, so all thirteen of the app's own
/// menu items were permanently enabled — measured in the running binary, in the same report where
/// AppKit's Edit menu correctly reported Undo, Cut and Paste disabled — and six of them were
/// guarded no-ops in the state a person is in the first time they open the menu. Complete
/// Priority with nothing committed, the three session verbs with no session, and the two nudge
/// verbs with nothing on screen each ran a `guard … else { return }` and vanished.
/// `CockpitView.swift` states the rule that breaks in its own comment — *"a shortcut that
/// silently does nothing is a shortcut people stop trusting"* — and then implemented the silent
/// nothing rather than withdrawing the item.
///
/// The world is read here, in the body, rather than passed in as a value: the provider the
/// composition root installs reads `@Observable` hosts, so SwiftUI tracks the read and rebuilds
/// this item when the answer changes. It is the same predicate `CockpitView.perform(_:)` and
/// `NudgeHost.perform(_:)` refuse on, so a menu item and the control it duplicates cannot
/// disagree about what the app would accept.
private struct ShellActionButton: View {
    let action: ShellAction
    let commandCenter: FocusCommandCenter
    let perform: (ShellActionEffect) -> Void

    var body: some View {
        Button {
            perform(action.effect)
        } label: {
            Text(action.title)
        }
        .modifier(ShortcutModifier(shortcut: action.shortcut))
        .disabled(!action.isAvailable(in: commandCenter.world))
    }
}

/// **The app menu's update check, as a view so its enabled state is observed.**
///
/// A `Commands` body does not track `@Observable` reads, so a `.disabled` evaluated there kept
/// whatever it read when the menu was first built — before the composition registered the
/// updater — and the item stayed greyed out for the life of the process. A `View` body is
/// tracked, the same way `ShellActionButton` follows the command world.
struct CheckForUpdatesButton: View {
    let commandCenter: FocusCommandCenter

    var body: some View {
        Button {
            commandCenter.checkForUpdates()
        } label: {
            Text(ShellStrings.resource(.commandCheckForUpdates))
        }
        .disabled(!commandCenter.canCheckForUpdates)
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
