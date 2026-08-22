import FocusCore
import SwiftUI
import Testing

@testable import FocusUI

/// The registry is the single source of truth for every shell action: the menu bar is built
/// from it and the Keyboard Shortcuts window is rendered from it. These tests are the reason
/// that claim is structural rather than aspirational — they assert the properties a menu bar
/// has to have, over the one table both consumers read.
///
/// The runtime half of the same contract lives in the app's `--focus-self-check`, which
/// hands synthesised key events to `NSApp.mainMenu` and reports which the menu bar actually
/// claimed. This suite proves the intent; that proves the effect.
@Suite("Command registry")
struct CommandRegistryTests {
    private let registry = CommandRegistry.shell

    @Test("e01 registers exactly the two actions that have real behaviour")
    func registryHoldsTheTwoRealActions() {
        #expect(registry.actions.count == 2)
        #expect(registry.actions.map(\.id) == ["shell.closeWindow", "shell.help"])
    }

    @Test("every action has a menu placement")
    func everyActionHasAPlacement() {
        for action in registry.actions {
            #expect(MenuPlacement.allCases.contains(action.placement))
        }
        #expect(registry.actions(in: .file).map(\.id) == ["shell.closeWindow"])
        #expect(registry.actions(in: .help).map(\.id) == ["shell.help"])
    }

    @Test("every populated placement has a heading for the shortcut reference")
    func populatedPlacementsAreNamed() {
        #expect(registry.populatedPlacements == [.file, .help])
        for placement in registry.populatedPlacements {
            #expect(placement.headingKey != nil)
        }
    }

    @Test("no two actions share a key equivalent")
    func keyEquivalentsAreUnique() {
        let shortcuts = registry.actions.compactMap(\.shortcut)
        #expect(Set(shortcuts).count == shortcuts.count)
    }

    @Test("no action claims a system-owned key equivalent")
    func noSystemShortcutIsClaimed() {
        for action in registry.actions {
            guard let shortcut = action.shortcut else { continue }
            #expect(!CommandRegistry.systemReservedShortcuts.contains(shortcut))
        }
    }

    @Test("Cmd-W is the app's to claim, and it is claimed")
    func closeWindowClaimsCommandW() {
        // Measured, not assumed: a `Window`-scene app that does not register a File action
        // has no File menu at all and leaves Cmd-W unbound — a closable window with no
        // keyboard close. Cmd-W is deliberately absent from the system-reserved set.
        let closeWindow = registry.action(id: "shell.closeWindow")
        #expect(closeWindow?.shortcut == Shortcut("w", modifiers: .command))
        #expect(closeWindow?.placement == .file)
        #expect(closeWindow?.effect == .closeKeyWindow)
        #expect(!CommandRegistry.systemReservedShortcuts.contains(Shortcut("w", modifiers: .command)))
    }

    @Test("the Help action opens a window the app actually declares")
    func helpActionTargetsADeclaredScene() {
        let help = registry.action(id: "shell.help")
        #expect(help?.shortcut == Shortcut("?", modifiers: .command))
        #expect(help?.placement == .help)
        #expect(help?.effect == .openWindow(.help))

        // `ShellWindow` is the table `FocusSentinelApp` declares its scenes from, so an
        // action can only point at a window id that a scene exists for.
        guard case .openWindow(let window)? = help?.effect else {
            Issue.record("the Help action must open a window")
            return
        }
        #expect(ShellWindow.allCases.contains(window))
        #expect(window.id == "help")
    }

    @Test("shortcut glyphs are drawn the way the Mac draws them")
    func shortcutGlyphsAreCorrect() {
        #expect(Shortcut("w", modifiers: .command).glyphs == "⌘W")
        #expect(Shortcut("?", modifiers: .command).glyphs == "⌘?")
        #expect(Shortcut("w", modifiers: [.command, .option]).glyphs == "⌥⌘W")
        #expect(Shortcut("n", modifiers: [.command, .shift, .option, .control]).glyphs == "⌃⌥⇧⌘N")
        #expect(Shortcut(" ", modifiers: .command).glyphs == "⌘Space")
    }

    @Test("a shortcut converts to the SwiftUI key equivalent it names")
    func shortcutConvertsToKeyEquivalent() {
        #expect(Shortcut("w", modifiers: .command).keyEquivalent.character == "w")
        #expect(Shortcut("?", modifiers: .command).modifiers == .command)
    }

    @Test(
        "every action title resolves to real text rather than echoing its key",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func actionTitlesResolve() {
        // Lane-gated: SwiftPM copies String Catalogs verbatim, so under `swift test` a
        // lookup returns the key itself and this assertion would be guaranteed false. It
        // runs for real under `xcodebuild test`, which compiles the catalog.
        for action in registry.actions {
            let resolved = String(localized: action.title)
            #expect(!resolved.isEmpty)
            #expect(resolved != action.titleKey.rawValue)
        }
        #expect(ShellStrings.string(.commandCloseWindow) == "Close Window")
        #expect(ShellStrings.string(.commandHelp) == "Focus Sentinel Help")
    }

    @Test("every window the shell can open has a title key")
    func everyWindowIsNamed() {
        #expect(ShellWindow.allCases.map(\.id) == ["cockpit", "help"])
        #expect(Set(ShellWindow.allCases.map(\.titleKey)).count == ShellWindow.allCases.count)
    }
}
