import AppKit
import Testing

@testable import FocusHost

/// **Finding the app menu's Settings item, so a status item can perform it** (focus-odz.2).
///
/// The status item's menu is AppKit and lives outside every SwiftUI environment, so it has no
/// `openSettings` to call. Rather than binding to `showSettingsWindow:` — a private selector
/// already renamed once, in macOS 13 — this finds the item the app menu is *required* to carry:
/// ⌘, is on `CommandRegistry.systemReservedShortcuts` precisely because the system owns it.
///
/// Driven against a menu this suite builds, which is how `ShellHelpMenuTests` holds its sibling:
/// no running application is needed to say whether the search finds the right item, and no
/// running application would make the answer more true.
@Suite("The Settings item, found by the key the system owns")
@MainActor
struct ShellSettingsMenuTests {
    /// A stand-in for whatever SwiftUI binds its Settings item to.
    @MainActor
    final class Recorder: NSObject {
        private(set) var performed = 0
        @objc func openSettings(_ sender: Any?) { performed += 1 }
    }

    static func menuBar(
        settingsTitle: String? = "Settings…",
        keyEquivalent: String = ",",
        modifiers: NSEvent.ModifierFlags = .command,
        target: AnyObject? = nil
    ) -> NSMenu {
        let bar = NSMenu(title: "Main")

        let appItem = NSMenuItem(title: "Focus Sentinel", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "Focus Sentinel")
        appMenu.addItem(
            NSMenuItem(title: "About Focus Sentinel", action: nil, keyEquivalent: "")
        )
        if let settingsTitle {
            let settings = NSMenuItem(
                title: settingsTitle,
                action: #selector(Recorder.openSettings(_:)),
                keyEquivalent: keyEquivalent
            )
            settings.keyEquivalentModifierMask = modifiers
            settings.target = target
            appMenu.addItem(settings)
        }
        appItem.submenu = appMenu
        bar.addItem(appItem)

        // A second menu, holding a ⌘-something that is not ⌘, — so "found the first submenu item
        // it saw" and "found the Settings item" are two different answers.
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        let close = NSMenuItem(title: "Close Window", action: nil, keyEquivalent: "w")
        close.keyEquivalentModifierMask = .command
        fileMenu.addItem(close)
        fileItem.submenu = fileMenu
        bar.addItem(fileItem)

        return bar
    }

    @Test("the item bound to ⌘, is the one that is found")
    func findsTheSettingsItem() {
        let item = ShellSettingsMenu.settingsItem(in: Self.menuBar())
        #expect(item?.title == "Settings…")
    }

    /// The search is by **key equivalent**, not by title: the title is localised and this has to
    /// work in every language the app ships in.
    @Test("a renamed Settings item is still found, because the search is by its key")
    func findsARenamedItem() {
        let item = ShellSettingsMenu.settingsItem(in: Self.menuBar(settingsTitle: "Réglages…"))
        #expect(item?.title == "Réglages…")
    }

    /// Both halves of the key matter. ⌥⌘, is not the Settings item, and neither is a plain comma
    /// somebody typed into a text field's menu.
    @Test("a comma with the wrong modifiers is not the Settings item")
    func modifiersArePartOfTheKey() {
        #expect(ShellSettingsMenu.settingsItem(in: Self.menuBar(modifiers: [.command, .option])) == nil)
        #expect(ShellSettingsMenu.settingsItem(in: Self.menuBar(modifiers: [])) == nil)
        #expect(ShellSettingsMenu.settingsItem(in: Self.menuBar(keyEquivalent: ".")) == nil)
    }

    /// **A menu bar with no Settings item answers `false`, out loud.**
    ///
    /// A menu item that reached nothing is exactly the defect this whole channel was rebuilt to
    /// make visible (`CommandDelivery` states the rule for the other one), so the verb returns
    /// whether it landed and the composition root records the answer.
    @Test("with no Settings item anywhere, performing it says so")
    func absentItemIsRefused() {
        #expect(ShellSettingsMenu.settingsItem(in: Self.menuBar(settingsTitle: nil)) == nil)
        #expect(ShellSettingsMenu.settingsItem(in: nil) == nil)
        #expect(ShellSettingsMenu.perform(in: Self.menuBar(settingsTitle: nil)) == false)
        #expect(ShellSettingsMenu.perform(in: nil) == false)
    }

    /// And with one, the item's own action reaches the item's own target.
    @Test("performing it sends the item's action to the item's target")
    func performsTheItemsOwnAction() {
        let recorder = Recorder()
        #expect(ShellSettingsMenu.perform(in: Self.menuBar(target: recorder)))
        #expect(recorder.performed == 1)
    }
}
