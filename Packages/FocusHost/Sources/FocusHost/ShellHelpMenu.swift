import AppKit
import FocusUI

/// **Where AppKit's automatic Help item goes, so that it is nowhere** (focus-h7h).
///
/// ## The defect
///
/// `FocusCommands` replaces SwiftUI's `.help` command group with the registry's own action, and
/// the comment there says that is the fix for *"SwiftUI's default Help item opens a help book
/// this app does not ship"*. It is half of it. The other half is AppKit's, and AppKit does not
/// consult SwiftUI: `NSApplication` installs an **automatic** *"<App> Help"* item, bound to
/// `showHelp:` and to ⌘?, into whichever menu it takes to be the Help menu. Our registry action
/// is titled *"Focus Sentinel Help"* as well, so the menu ends up holding two items a person
/// cannot tell apart, and the one AppKit put first is the one ⌘? reaches.
///
/// `showHelp:` on an application with no help book runs a **modal alert** — *"Help isn't
/// available for Focus Sentinel"* — through `-[NSAlert runModal]`. Measured here at HEAD, in
/// isolation, twice: the zero-grant self-check performs ⌘? as one of its five key-equivalent
/// probes, AppKit's item claims it, `runModal` takes the main thread, and the process never
/// returns to write its report. Both times the lane had to be killed after ten minutes. So this
/// is not only a menu item leading nowhere — it is the one that stops the *only* instrument in
/// the programme that can observe `App/` from ever finishing.
///
/// ## The fix, and why it is this one
///
/// `NSApplication.helpMenu` is the property that says where the automatic item is installed.
/// Pointing it at a menu that is **not in the menu bar** does not suppress the item — nothing
/// documented does — but it does put it somewhere no person and no key-equivalent search can
/// reach: `performKeyEquivalent(with:)` walks `NSApp.mainMenu`, and a detached `NSMenu` is not in
/// it. The registry's own item is then the only ⌘? in the menu bar, which is what both the help
/// window and `CommandRegistryTests` already assume.
///
/// Removing the item instead would be the obvious move and it is the wrong one: AppKit installs
/// it again, and the moment it chooses is *activation*, which is exactly what the self-check does
/// immediately after launch. Redirecting the destination survives every re-installation, because
/// AppKit re-reads `helpMenu` each time.
///
/// Both halves run, in this order, because either can be first depending on when AppKit got
/// there: the destination is redirected, **then** anything already installed in the menu bar is
/// removed. A second insertion after that lands in the detached menu.
///
/// It lives in `FocusHost` rather than in `App/` for the reason everything else moved here: a
/// statement in the application target is a statement no test bundle can import, and this one is
/// the difference between a gate that runs and a gate that hangs.
public enum ShellHelpMenu {
    /// The selector AppKit binds its automatic item to. Named once, because it is matched on in
    /// two places and a typo would silently match nothing.
    public static let automaticItemAction = Selector(("showHelp:"))

    /// Where AppKit's automatic item is sent instead.
    ///
    /// Held for the process's lifetime rather than built per call: `NSApplication.helpMenu` does
    /// not retain strongly enough to be handed a temporary, and a deallocated help menu would put
    /// AppKit straight back to searching the menu bar. Main-actor-isolated because `NSMenu` is not
    /// `Sendable` and this one is only ever touched from the one thread AppKit touches menus on.
    @MainActor
    private static let detached = NSMenu(title: "Help (unused)")

    /// Redirect AppKit's automatic Help item, and take down any copy already in the menu bar.
    ///
    /// Idempotent, and cheap enough to call again after anything that might have let AppKit
    /// re-install: it assigns one property and walks one menu one level deep.
    ///
    /// - Returns: how many automatic items were found in the menu bar and removed. `0` on the
    ///   second call and on every call after it, which is what makes "it was removed" and "there
    ///   was never one" distinguishable in a report.
    @MainActor
    @discardableResult
    public static func detachAutomaticItem() -> Int {
        NSApp.helpMenu = detached
        return removeAutomaticItems(from: NSApp.mainMenu)
    }

    /// Every automatic help item in this menu bar, removed, one level deep.
    ///
    /// One level, because that is where a menu-bar menu's items live and because the registry's
    /// own Help action is at the same level: a recursive walk would be reaching into submenus
    /// this function has no business rewriting.
    ///
    /// Internal rather than private so `ShellHelpMenuTests` can drive it against a menu it built,
    /// which is the only way to test it without a running application.
    @MainActor
    @discardableResult
    static func removeAutomaticItems(from mainMenu: NSMenu?) -> Int {
        guard let mainMenu else { return 0 }
        var removed = 0
        for top in mainMenu.items {
            guard let submenu = top.submenu else { continue }
            for item in submenu.items where item.action == automaticItemAction {
                submenu.removeItem(item)
                removed += 1
            }
        }
        return removed
    }

    /// Every item in the menu bar still bound to `showHelp:`, by the menu that holds it.
    ///
    /// The reportable form of the claim, for `--focus-self-check`: an empty list is *"⌘? reaches
    /// the Keyboard Shortcuts window"*, and a non-empty one names the menu that would open an
    /// alert instead. Read rather than asserted here, because the assertion belongs to the gate.
    @MainActor
    public static func automaticItemsRemaining(in mainMenu: NSMenu?) -> [String] {
        guard let mainMenu else { return [] }
        return mainMenu.items.compactMap { top -> String? in
            guard let submenu = top.submenu else { return nil }
            guard submenu.items.contains(where: { $0.action == automaticItemAction }) else {
                return nil
            }
            return top.title
        }
    }
}
