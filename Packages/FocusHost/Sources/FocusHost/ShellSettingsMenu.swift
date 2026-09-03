import AppKit
import FocusUI

/// **How something that is not a scene opens the Settings window** (focus-odz.2).
///
/// ## The problem this solves, and the two answers that were rejected
///
/// `Settings` is a SwiftUI scene. The only supported way to open one is the environment's
/// `openSettings` action or the app menu's own item — and neither is reachable from an
/// `NSStatusItem`'s menu, which is AppKit and lives outside every SwiftUI environment. The status
/// item's secondary menu needs a *Settings…* item all the same, because with the cockpit shut it
/// is the only surface the person has.
///
/// Two shorter routes were rejected:
///
/// * `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` — a private
///   selector whose name has already changed once (`showPreferencesWindow:` before macOS 13). A
///   menu item bound to a string Apple may rename is a menu item that will one day do nothing,
///   silently.
/// * Building a Settings window here. That would be a second Settings surface, and this
///   repository's whole shape is that there is one of each.
///
/// So this performs **the item the app menu already has**, found by the key equivalent it is
/// required to carry: ⌘, is on `CommandRegistry.systemReservedShortcuts` precisely because the
/// system owns it, which is what makes it a reliable way to name the item rather than a guess at
/// one. Whatever SwiftUI binds that item to is what gets sent, so a rename inside AppKit changes
/// nothing here.
///
/// It answers **whether it landed**, and the caller records that: an item that found nothing to
/// perform is a menu item that does nothing, and this application's rule is that such a thing
/// fails loudly rather than shrugging (`CommandDelivery` states it for the other channel).
///
/// It lives in `FocusHost` beside `ShellHelpMenu`, for the same reason that one does: a statement
/// in `App/` is a statement no test bundle can import.
public enum ShellSettingsMenu {
    /// The key equivalent the Settings item is required to carry. ⌘, is the Mac's, which is why
    /// `CommandRegistry.systemReservedShortcuts` forbids the registry from claiming it.
    public static let keyEquivalent = ","

    /// Perform the app menu's Settings item, and say whether there was one.
    @MainActor
    @discardableResult
    public static func open() -> Bool {
        perform(in: NSApplication.shared.mainMenu)
    }

    /// The same, against a menu bar the caller supplies.
    ///
    /// Internal rather than private so `ShellSettingsMenuTests` can drive it against a menu it
    /// built — the only way to test it without a running application, which is exactly how
    /// `ShellHelpMenu.removeAutomaticItems(from:)` is held.
    @MainActor
    @discardableResult
    static func perform(in mainMenu: NSMenu?) -> Bool {
        guard let item = settingsItem(in: mainMenu), let action = item.action else { return false }
        // `NSApplication.shared` rather than `NSApp`, which is an implicitly-unwrapped global and
        // is `nil` until something has asked for the application object — true in a unit process,
        // where this function is driven against a menu the test built.
        return NSApplication.shared.sendAction(action, to: item.target, from: item)
    }

    /// The item bound to ⌘, anywhere in the menu bar, one level deep.
    ///
    /// One level, for `ShellHelpMenu.removeAutomaticItems(from:)`'s reason: that is where a
    /// menu-bar menu's items live, and a recursive walk would be reaching into submenus this has
    /// no business performing.
    @MainActor
    static func settingsItem(in mainMenu: NSMenu?) -> NSMenuItem? {
        guard let mainMenu else { return nil }
        for top in mainMenu.items {
            guard let submenu = top.submenu else { continue }
            for item in submenu.items
            where item.keyEquivalent == keyEquivalent
                && item.keyEquivalentModifierMask == .command {
                return item
            }
        }
        return nil
    }
}
