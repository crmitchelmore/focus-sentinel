import AppKit
import Testing

@testable import FocusHost

/// **The menu item that hung the only lane able to observe `App/`** (focus-h7h).
///
/// AppKit installs a *"<App> Help"* item bound to `showHelp:` and to ⌘? into whichever menu it
/// takes to be the Help menu, beside the registry's own action — which is titled the same thing.
/// `showHelp:` on an application with no help book runs `-[NSAlert runModal]`, and the zero-grant
/// self-check performs ⌘? as one of its five key-equivalent probes. Measured at HEAD, in
/// isolation, twice: the process took the main thread inside the alert and never wrote its
/// report.
///
/// These drive `removeAutomaticItems(from:)` against menus built here rather than against
/// `NSApp.mainMenu`, because a unit process has no menu bar of its own and a test that needed one
/// would be a test that only ran inside the app.
@MainActor
struct ShellHelpMenuTests {
    /// A menu bar with one Help menu holding whatever items are asked for.
    private func menuBar(helpItems: [NSMenuItem]) -> NSMenu {
        let bar = NSMenu(title: "MainMenu")
        let helpTop = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        let help = NSMenu(title: "Help")
        for item in helpItems { help.addItem(item) }
        helpTop.submenu = help
        bar.addItem(helpTop)
        return bar
    }

    private func automaticItem() -> NSMenuItem {
        NSMenuItem(
            title: "Focus Sentinel Help",
            action: ShellHelpMenu.automaticItemAction,
            keyEquivalent: "?"
        )
    }

    /// The registry's own action, which is titled **the same thing** and must survive.
    ///
    /// That collision is the whole reason the removal matches on the *action* rather than on the
    /// title: a removal keyed to "Focus Sentinel Help" would take down the item that actually
    /// opens the Keyboard Shortcuts window and leave the alert behind it.
    private func registryItem() -> NSMenuItem {
        NSMenuItem(
            title: "Focus Sentinel Help",
            action: Selector(("focusSentinelOpenShortcutsWindow:")),
            keyEquivalent: "?"
        )
    }

    @Test("AppKit's automatic help item is removed and the registry's identically titled one is not")
    func removesOnlyTheAutomaticItem() {
        let bar = menuBar(helpItems: [automaticItem(), registryItem()])

        #expect(ShellHelpMenu.removeAutomaticItems(from: bar) == 1)

        let remaining = bar.items[0].submenu?.items ?? []
        #expect(remaining.count == 1)
        #expect(
            remaining.first?.action != ShellHelpMenu.automaticItemAction,
            "the item left behind is the one that opens an alert"
        )
        #expect(
            remaining.first?.keyEquivalent == "?",
            "the registry's action keeps ⌘?, which is what the help window is reached by"
        )
    }

    /// Idempotent, because it is called three times in one launch — at
    /// `applicationDidFinishLaunching`, at activation, and immediately before the ⌘? probe — and
    /// a second call that removed something would mean the first had not worked.
    @Test("removing twice removes nothing the second time")
    func isIdempotent() {
        let bar = menuBar(helpItems: [automaticItem(), registryItem()])
        #expect(ShellHelpMenu.removeAutomaticItems(from: bar) == 1)
        #expect(ShellHelpMenu.removeAutomaticItems(from: bar) == 0)
    }

    /// A menu bar AppKit never touched. `0` and *"there was one and it is gone"* have to be
    /// distinguishable, which is why the function returns a count rather than a `Bool`.
    @Test("a menu bar with no automatic item is left exactly as it was")
    func leavesACleanMenuBarAlone() {
        let bar = menuBar(helpItems: [registryItem()])
        #expect(ShellHelpMenu.removeAutomaticItems(from: bar) == 0)
        #expect(bar.items[0].submenu?.items.count == 1)
        #expect(ShellHelpMenu.automaticItemsRemaining(in: bar).isEmpty)
    }

    /// The reportable form, which is what the gate asserts on: the **menu** that would open an
    /// alert is named, so a failure says where rather than that one exists somewhere.
    @Test("a remaining automatic item is reported by the menu that holds it")
    func namesTheMenuThatStillHoldsOne() {
        let bar = menuBar(helpItems: [automaticItem()])
        #expect(ShellHelpMenu.automaticItemsRemaining(in: bar) == ["Help"])
    }

    /// One level deep, deliberately: menu-bar items live there and so does the registry's action.
    /// A recursive walk would be reaching into submenus this has no business rewriting.
    @Test("an item nested inside a submenu of the Help menu is left alone")
    func doesNotRecurse() {
        let nested = NSMenu(title: "More")
        nested.addItem(automaticItem())
        let holder = NSMenuItem(title: "More", action: nil, keyEquivalent: "")
        holder.submenu = nested

        let bar = menuBar(helpItems: [holder])
        #expect(ShellHelpMenu.removeAutomaticItems(from: bar) == 0)
        #expect(nested.items.count == 1)
    }

    @Test("a nil menu bar is answered rather than crashed on")
    func toleratesNoMenuBar() {
        #expect(ShellHelpMenu.removeAutomaticItems(from: nil) == 0)
        #expect(ShellHelpMenu.automaticItemsRemaining(in: nil).isEmpty)
    }
}
