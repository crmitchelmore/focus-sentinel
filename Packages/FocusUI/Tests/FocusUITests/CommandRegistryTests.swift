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

    @Test("the registry holds exactly the actions that have real behaviour, in menu order")
    func registryHoldsTheRealActions() {
        // Five, and every one of them does something: three priority commands, the window
        // close the Court's HIG review required, and the Help item that replaces SwiftUI's
        // link to a help book this app does not ship.
        #expect(registry.actions.count == 5)
        #expect(registry.actions.map(\.id) == [
            "priority.new",
            "context.addFiles",
            "priority.complete",
            "shell.closeWindow",
            "shell.help"
        ])
    }

    @Test("every action has a menu placement")
    func everyActionHasAPlacement() {
        for action in registry.actions {
            #expect(MenuPlacement.allCases.contains(action.placement))
        }
        #expect(registry.actions(in: .file).map(\.id) == [
            "priority.new",
            "context.addFiles",
            "priority.complete",
            "shell.closeWindow"
        ])
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

    @Test("the priority commands are bound where a Mac user would look for them")
    func priorityCommandsAreBound() {
        // ⌘N is the app's primary act; ⌘O is the Mac's "open something" key, and in an app
        // with no documents the thing being opened is an attachment.
        #expect(registry.action(id: "priority.new")?.shortcut == Shortcut("n", modifiers: .command))
        #expect(registry.action(id: "priority.new")?.effect == .priority(.newPriority))
        #expect(registry.action(id: "context.addFiles")?.shortcut == Shortcut("o", modifiers: .command))
        #expect(registry.action(id: "context.addFiles")?.effect == .priority(.addFilesToContext))

        // Deliberately ⌃⌘⏎ and not ⌘⏎: plain Return commits whatever field has focus, and
        // finishing the thing you are working on must not be one modifier away from typing.
        let complete = registry.action(id: "priority.complete")
        #expect(complete?.shortcut == Shortcut("\r", modifiers: [.control, .command]))
        #expect(complete?.effect == .priority(.completePriority))
        #expect(complete?.shortcut?.glyphs == "⌃⌘↩")

        // The menu item and the cockpit button are the same action, so they share one title
        // key rather than two keys that have to be kept in step.
        #expect(complete?.titleKey == .priorityActionComplete)
    }

    @Test("every priority command is reachable from the menu bar")
    func everyPriorityCommandIsBound() {
        let commanded = registry.actions.compactMap { action -> PriorityCommand? in
            guard case .priority(let command) = action.effect else { return nil }
            return command
        }
        #expect(Set(commanded) == Set(PriorityCommand.allCases))
    }

    @Test("a command sent while nothing is listening is delivered when something is")
    @MainActor
    func commandCentreBuffersUntilTheCockpitExists() {
        // ⌘N with the cockpit closed opens the window and *then* wants the capture field. The
        // window takes a run-loop turn to exist, so the command waits for it rather than being
        // dropped on the floor.
        let centre = FocusCommandCenter()
        #expect(!centre.isConnected)

        centre.send(.newPriority)
        var received: [PriorityCommand] = []
        centre.register { received.append($0) }

        #expect(centre.isConnected)
        #expect(received == [.newPriority])

        centre.send(.completePriority)
        #expect(received == [.newPriority, .completePriority])

        // Only the most recent unheard command is kept: someone who presses ⌘N and then ⌘O
        // before the window appears meant the second one.
        centre.unregister()
        centre.send(.newPriority)
        centre.send(.addFilesToContext)
        var later: [PriorityCommand] = []
        centre.register { later.append($0) }
        #expect(later == [.addFilesToContext])
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
        #expect(ShellStrings.string(.commandNewPriority) == "New Priority")
        #expect(ShellStrings.string(.commandAddFilesToContext) == "Add Files to Context…")
        #expect(ShellStrings.string(.priorityActionComplete) == "Complete Priority")
    }

    @Test("every window the shell can open has a title key")
    func everyWindowIsNamed() {
        #expect(ShellWindow.allCases.map(\.id) == ["cockpit", "help"])
        #expect(Set(ShellWindow.allCases.map(\.titleKey)).count == ShellWindow.allCases.count)
    }
}
