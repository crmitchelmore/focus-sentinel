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
        // Thirteen, in **menu-bar order** — File, then View, then Help. The array order is the
        // reference window's row order, so the registry is written in the order a person reads
        // the menu bar rather than in the order the epics arrived. Thirteen, and every one of
        // them does something: three priority commands, three session
        // verbs, F-119's watching switch, the window close the Court's HIG review required, the
        // Help item that replaces SwiftUI's link to a help book this app does not ship, and
        // e05's four nudge verbs — which exist because F-145's rule is that a click is never the
        // *only* way to reach an affordance.
        // Sixteen since e07a: the three answers to a question, which exist because the panel
        // that draws them can never carry a keystroke (U-1, F-145).
        // Seventeen since e09a: History, which is a destination rather than a verb — the shell
        // has no split view, so a window opened from the View menu is the route that exists.
        // Twenty since e09b: the three portability verbs, in the File menu because that is where
        // a Mac user looks for export and import (F-110, F-134). `deleteEverything` is
        // deliberately **not** among them: a destructive verb one keystroke from ⌘W is a verb
        // somebody presses by mistake, and its confirmation sheet is the point.
        #expect(registry.actions.count == 20)
        #expect(registry.actions.map(\.id) == [
            "priority.new",
            "context.addFiles",
            "priority.complete",
            "session.start",
            "session.pause",
            "session.complete",
            "sensing.pause",
            "data.export",
            "settings.export",
            "settings.import",
            "shell.closeWindow",
            "nudge.relevant",
            "nudge.snooze",
            "nudge.hideOverlays",
            "nudge.menuBar",
            "nudge.answerYes",
            "nudge.answerNo",
            "nudge.answerNotNow",
            "shell.history",
            "shell.help"
        ])
    }

    // MARK: - e05: the nudge verbs

    /// **Every action on a nudge surface is reachable from the keyboard** (F-145).
    ///
    /// Six actions live on the accusation panel. Two of them are commands this registry already
    /// had — "Pause" is `session.pause` and "Change priority" is `priority.new`, which opens
    /// e02's capture surface — and a second command for either would be a second name for one
    /// act. The other four are here, plus F-81's one command to clear the screen.
    @Test("the nudge verbs are in the View menu and none duplicates an existing command")
    func nudgeVerbsAreInTheViewMenu() {
        #expect(registry.actions(in: .view).map(\.id) == [
            "nudge.relevant",
            "nudge.snooze",
            "nudge.hideOverlays",
            "nudge.menuBar",
            "nudge.answerYes",
            "nudge.answerNo",
            "nudge.answerNotNow",
            "shell.history"
        ])

        // Pause and Change priority reach the panel's own actions through the commands that
        // already exist, so the registry names each act exactly once.
        #expect(registry.action(id: "session.pause") != nil)
        #expect(registry.action(id: "priority.new") != nil)
        #expect(registry.actions.filter { $0.id.hasPrefix("nudge.") }.count == 7)
    }

    /// **The question's three answers are three View-menu commands** (e07a, U-1, F-145).
    ///
    /// Red before the registry carried them: `nudge.answerYes` had no action at all. Each one is
    /// pinned to its answer, its key and its base character — Y, U, L, none of which any other
    /// action uses — so the mapping is a fact and not a coincidence of order.
    @Test("the three answers to a question are View-menu commands on their own base characters")
    func theThreeAnswersAreCommands() throws {
        let expected: [(id: String, key: Character, command: PriorityCommand, answer: QueryAnswer)] = [
            ("nudge.answerYes", "y", .answerYes, .yesAddIt),
            ("nudge.answerNo", "u", .answerNo, .no),
            ("nudge.answerNotNow", "l", .answerNotNow, .notNow)
        ]
        for row in expected {
            let action = try #require(registry.action(id: row.id), "\(row.id) is not registered")
            #expect(action.placement == .view)
            #expect(action.shortcut == Shortcut(row.key, modifiers: [.control, .command]))
            #expect(action.effect == .priority(row.command))
            #expect(row.command.queryAnswer == row.answer)
            #expect(!row.command.opensCockpit)
        }
        // Every answer has a command and every answering command has an answer, in both
        // directions: a fourth `QueryAnswer` added without a command is a hole here.
        let answered = Set(PriorityCommand.allCases.compactMap(\.queryAnswer))
        #expect(answered == Set(QueryAnswer.allCases))
        #expect(PriorityCommand.allCases.filter { $0.queryAnswer != nil }.count == QueryAnswer.allCases.count)
    }

    /// A nudge lands while somebody is typing, so every nudge verb costs two modifiers — the
    /// same argument `priority.complete` makes about ⌃⌘⏎ rather than ⌘⏎.
    @Test("every nudge verb costs a Control as well as a Command")
    func nudgeVerbsCostTwoModifiers() throws {
        for action in registry.actions(in: .view) {
            let shortcut = try #require(action.shortcut)
            #expect(shortcut.modifiers.contains(.command))
            #expect(shortcut.modifiers.contains(.control))
        }
    }

    /// **F-81's command is not a bare Escape**, and it must not become one: Escape already
    /// reaches the panel through `NudgePanel.cancelOperation(_:)`, where it dismisses the
    /// surface the person is looking at. Binding it as a *menu* key equivalent would take the
    /// Escape key away from every text field in the application.
    @Test("no action claims a bare, unmodified key")
    func noActionIsUnmodified() throws {
        for action in registry.actions {
            let shortcut = try #require(action.shortcut)
            #expect(!shortcut.modifiers.isEmpty)
            #expect(shortcut.character != "\u{1b}")
        }
    }

    /// Every command the centre can carry either opens the cockpit or deliberately does not,
    /// and the nudge verbs are exactly the ones that do not: hiding an overlay by raising a
    /// window on top of somebody's work would be the opposite of what it says.
    @Test("the nudge verbs are exactly the commands that do not raise the cockpit")
    func nudgeVerbsDoNotOpenTheCockpit() {
        let quiet = PriorityCommand.allCases.filter { !$0.opensCockpit }
        #expect(quiet == [
            .thisIsRelevant, .snoozeNudge, .hideOverlays, .showMenuBar,
            .answerYes, .answerNo, .answerNotNow
        ])
        for command in PriorityCommand.allCases where quiet.contains(command) == false {
            #expect(command.opensCockpit)
        }
    }

    /// One queue, one order, two listeners. The buffer is still the handler's alone — an
    /// observer that received a *pending* command would be receiving one out of order.
    @Test("an observer sees every command the handler sees, and never the buffered one")
    @MainActor
    func observersSeeEveryCommand() {
        let centre = FocusCommandCenter()
        var observed: [PriorityCommand] = []
        centre.observe { observed.append($0) }
        // A window really is on its way, which since focus-mwm is what arms the buffer.
        var raises = 0
        centre.registerCockpitOpener { raises += 1 }

        // Nothing is registered yet, so this one is buffered for the window that will arrive.
        #expect(centre.send(.newPriority) == .awaitingCockpit)
        #expect(raises == 1)
        #expect(observed == [.newPriority])

        var handled: [PriorityCommand] = []
        centre.register { handled.append($0) }
        // The buffered command is delivered to the handler — and not a second time to the
        // observer, which already saw it.
        #expect(handled == [.newPriority])
        #expect(observed == [.newPriority])

        #expect(centre.send(.hideOverlays) == .delivered)
        #expect(handled == [.newPriority, .hideOverlays])
        #expect(observed == [.newPriority, .hideOverlays])
        // `hideOverlays` does not open the cockpit, so nothing was raised for it.
        #expect(raises == 1)
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
            "session.start",
            "session.pause",
            "session.complete",
            "sensing.pause",
            "data.export",
            "settings.export",
            "settings.import",
            "shell.closeWindow"
        ])
        #expect(registry.actions(in: .help).map(\.id) == ["shell.help"])
        #expect(registry.actions(in: .view).count == 8)
    }

    @Test("every populated placement has a heading for the shortcut reference")
    func populatedPlacementsAreNamed() {
        // e05 is the first epic to put an action in the View menu, so `view` gains a heading
        // rather than shipping an unnamed group — which is exactly what this assertion is for.
        #expect(registry.populatedPlacements == [.file, .view, .help])
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
        // **The window is on its way because this asked for it** (focus-mwm). The centre raises
        // the cockpit itself now, and holds a command only when it did — so the opener is not
        // scaffolding around the reading, it is the precondition the reading is about.
        var raises = 0
        centre.registerCockpitOpener { raises += 1 }

        #expect(centre.send(.newPriority) == .awaitingCockpit)
        #expect(raises == 1)
        var received: [PriorityCommand] = []
        centre.register { received.append($0) }

        #expect(centre.isConnected)
        #expect(received == [.newPriority])

        #expect(centre.send(.completePriority) == .delivered)
        #expect(received == [.newPriority, .completePriority])
        // Raised again even though the cockpit was listening: ⌘N with the window open but behind
        // the Settings window has to bring it forward, which is what the caller this replaced did.
        #expect(raises == 2)

        // Only the most recent unheard command is kept: someone who presses ⌘N and then ⌘O
        // before the window appears meant the second one.
        centre.unregister()
        #expect(centre.send(.newPriority) == .awaitingCockpit)
        #expect(centre.send(.addFilesToContext) == .awaitingCockpit)
        var later: [PriorityCommand] = []
        centre.register { later.append($0) }
        #expect(later == [.addFilesToContext])
    }

    /// **Nothing is held for a window that is not coming** (focus-mwm).
    ///
    /// The buffer's whole justification is that the cockpit takes a run-loop turn to exist. With
    /// nothing able to open one, a stored command is a command stored for ever — which is what
    /// the menu-bar popover's four buttons and the nudge panel's Pause and Change priority did
    /// with the main window shut. A refusal is the honest answer, and it is in the return value
    /// rather than in a log, so a caller that records an effect afterwards has to ignore it on
    /// purpose.
    ///
    /// Folded over `PriorityCommand.allCases`, because the previous repair of this shape was
    /// correct for the one command in the bead: every verb the app has is driven here, in both
    /// states, and the case that is added next is driven by the same loop.
    @Test("with no cockpit to open, a command is refused rather than stored for ever")
    @MainActor
    func nothingIsBufferedWithoutAWindowComing() {
        for command in PriorityCommand.allCases {
            let centre = FocusCommandCenter()
            #expect(!centre.canRaiseCockpit)

            let outcome = centre.send(command)
            #expect(outcome == .undeliverable, "\(command.rawValue) was not refused")
            #expect(!outcome.willLand)
            // The request was still made and is still countable, so "nothing could raise it" is
            // distinguishable from "nothing asked".
            #expect(centre.cockpitRequests == (command.opensCockpit ? 1 : 0))

            // …and nothing was kept: a handler arriving later must not be handed a command from
            // a moment that has passed.
            var received: [PriorityCommand] = []
            centre.register { received.append($0) }
            #expect(received.isEmpty, "\(command.rawValue) was held in the buffer")
        }
    }

    /// The other half of the same fold: with a listener present, every command lands.
    @Test("every command lands when a surface is listening")
    @MainActor
    func everyCommandLandsWhenSomethingIsListening() {
        for command in PriorityCommand.allCases {
            let centre = FocusCommandCenter()
            var received: [PriorityCommand] = []
            centre.register { received.append($0) }
            #expect(centre.send(command) == .delivered)
            #expect(received == [command])
        }
    }

    /// …and with only the nudge loop listening — which is the state the app is in whenever the
    /// cockpit is closed — the four e05 verbs still land, because the loop observes for the life
    /// of the process rather than registering with a window.
    @Test("the nudge verbs land on an observer with no window anywhere")
    @MainActor
    func theNudgeVerbsLandOnAnObserver() {
        for command in PriorityCommand.allCases where !command.opensCockpit {
            let centre = FocusCommandCenter()
            var observed: [PriorityCommand] = []
            centre.observe { observed.append($0) }
            #expect(centre.send(command) == .delivered)
            #expect(observed == [command])
        }
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
        #expect(ShellStrings.string(.commandCloseWindow) == "Close window")
        #expect(ShellStrings.string(.commandHelp) == "Focus Sentinel Help")
        #expect(ShellStrings.string(.commandNewPriority) == "New priority")
        #expect(ShellStrings.string(.commandAddFilesToContext) == "Add files to context…")
        #expect(ShellStrings.string(.priorityActionComplete) == "Complete priority")
        #expect(ShellStrings.string(.sessionActionStart) == "Start session")
        #expect(ShellStrings.string(.sessionActionPause) == "Pause session")
        #expect(ShellStrings.string(.sessionActionComplete) == "Finish session")
        #expect(ShellStrings.string(.commandPauseSensing) == "Pause watching")
    }

    @Test("the e03 verbs are bound where a stray Return cannot reach them")
    func sessionCommandsAreBound() {
        // All three session verbs are ⌃⌘ combinations for the reason `priority.complete`
        // already gives: this window is full of text fields, plain Return commits whichever one
        // has focus, and a session verb one modifier away from typing is one somebody triggers
        // by accident.
        #expect(registry.action(id: "session.start")?.shortcut == Shortcut("s", modifiers: [.control, .command]))
        #expect(registry.action(id: "session.start")?.effect == .priority(.startSession))
        #expect(registry.action(id: "session.pause")?.shortcut == Shortcut("p", modifiers: [.control, .command]))
        #expect(registry.action(id: "session.pause")?.effect == .priority(.pauseSession))
        #expect(registry.action(id: "session.complete")?.shortcut == Shortcut("f", modifiers: [.control, .command]))
        #expect(registry.action(id: "session.complete")?.effect == .priority(.completeSession))

        // The watching switch is ⌃⌘E and **not** ⇧⌘W, which is what it was first bound to: the
        // app's own self-check measured a plain ⌘W reaching that item and flipping the stored
        // switch on three consecutive runs. An app that takes ⌘W away from a person because it
        // wanted a nearby shortcut is a defect, so the base character moved off `w` entirely.
        let sensing = registry.action(id: "sensing.pause")
        #expect(sensing?.shortcut == Shortcut("e", modifiers: [.control, .command]))
        #expect(sensing?.effect == .priority(.pauseSensing))
        #expect(sensing?.shortcut?.glyphs == "⌃⌘E")
        #expect(sensing?.shortcut != Shortcut("w", modifiers: [.shift, .command]))

        // …and no two actions share a base character at all, whatever their modifiers, because
        // that pairing is the one the measurement caught colliding.
        let characters = registry.actions.compactMap(\.shortcut?.character)
        #expect(
            Set(characters).count == characters.count,
            "two actions share a base character: \(characters)"
        )

        // The three session items reuse the cockpit controls' own title keys — one action, one
        // key — exactly as Complete Priority already does.
        #expect(registry.action(id: "session.start")?.titleKey == .sessionActionStart)
        #expect(registry.action(id: "session.pause")?.titleKey == .sessionActionPause)
        #expect(registry.action(id: "session.complete")?.titleKey == .sessionActionComplete)
    }

    @Test("every window the shell can open has a title key")
    func everyWindowIsNamed() {
        #expect(ShellWindow.allCases.map(\.id) == ["cockpit", "help", "history"])
        #expect(Set(ShellWindow.allCases.map(\.titleKey)).count == ShellWindow.allCases.count)
    }

    /// **The cockpit's opening size, where a test can read it** (focus-2er).
    ///
    /// It was two literals in the scene, and `App/` is not a package: a number nobody can reach
    /// is a number nobody can defend. The height is the measured one — with e03's session
    /// controls and sensing status added the cockpit outgrew the 704-point window e02 shipped
    /// and clipped its footer — so it is asserted to be at least that, rather than pinned to a
    /// value a later epic may legitimately grow.
    @Test("the cockpit opens tall enough for the column it draws")
    func theCockpitHasAMeasuredDefaultSize() throws {
        let size = try #require(ShellWindow.cockpit.defaultSize)
        #expect(size.width == 560)
        #expect(
            size.height >= 900,
            "the cockpit opens shorter than the window that was measured to clip its footer"
        )
    }

    /// **The reference opens at the size its own baseline measures** (focus-odz.6).
    ///
    /// It had no default size at all, on the argument that a content-sized window should choose
    /// its own — and the alternative to this app choosing is not the person choosing, it is AppKit
    /// choosing, which it does badly for a content-sized SwiftUI scene. The numbers are read off
    /// `shortcutsHelp.light.standard`, which is 520 × 689.5 points since e07a's three View-menu
    /// answers (it was 623.5), so nothing wraps and the whole reference is on screen at standard
    /// type.
    @Test("the Keyboard Shortcuts window opens at the size its baseline measures")
    func theHelpWindowHasAMeasuredDefaultSize() throws {
        let size = try #require(ShellWindow.help.defaultSize)
        #expect(size.width == 520)
        #expect(
            size.height >= 690,
            "the reference opens shorter than the column its committed baseline draws"
        )
        // Every declared window opens at a size somebody wrote down. A scene added without one
        // gets AppKit's guess, which is the defect this pair of assertions exists to stop.
        for window in ShellWindow.allCases {
            #expect(window.defaultSize != nil, "\(window) opens at a size nobody chose")
        }
    }
}
