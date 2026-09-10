import FocusCore
import SwiftUI
import Testing

@testable import FocusUI

/// The Help menu's destination is rendered from the same registry that builds the menu bar.
/// This suite is what makes "cannot drift" a fact: the rows the window renders are compared,
/// value for value and in order, against the registry itself.
@Suite("Keyboard shortcuts reference")
struct ShortcutsHelpTests {
    private let registry = CommandRegistry.shell

    @Test("the rendered rows are exactly the registry's actions, in registry order")
    func rowsMatchTheRegistryExactly() {
        let rows = ShortcutsHelpView.groups(for: registry).flatMap(\.rows)

        #expect(rows.map(\.id) == registry.actions.map(\.id))
        #expect(rows.count == registry.actions.count)

        for (row, action) in zip(rows, registry.actions) {
            #expect(row.titleKey == action.titleKey)
            #expect(row.glyphs == action.shortcut?.glyphs)
        }
    }

    @Test("the reference lists every shipped action with the glyphs a Mac user expects")
    func rowsAreTheShippedActions() {
        let rows = ShortcutsHelpView.groups(for: registry).flatMap(\.rows)

        #expect(rows.map(\.glyphs) == [
            "⌘N", "⌘O", "⌃⌘↩", "⌃⌘S", "⌃⌘P", "⌃⌘F", "⌃⌘E",
            // e09b's three portability verbs. Their base characters are `x`, `b` and `i`
            // because no other action had them: this registry's rule is that no two actions
            // share a base character whatever their modifiers (F-110, F-134).
            "⇧⌘X", "⇧⌘B", "⇧⌘I",
            "⌘W",
            "⌃⌘R", "⌃⌘Z", "⌃⌘H", "⌃⌘M",
            "⌃⌘Y", "⌃⌘U", "⌃⌘L",
            // e09a's destination, in the same modifier family as every other View-menu verb.
            "⌃⌘D",
            "⌘?",
            // focus-u6de: the walkthrough, on the one free base character that names it.
            "⇧⌘T"
        ])
        #expect(rows.map(\.titleKey) == [
            .commandNewPriority,
            .commandAddFilesToContext,
            .priorityActionComplete,
            .sessionActionStart,
            .sessionActionPause,
            .sessionActionComplete,
            .commandPauseSensing,
            // e09b: the same three titles the Privacy pane's buttons draw, so a person finds
            // them in both places under one name.
            .settingsPrivacyExportData,
            .settingsPrivacyExportSettings,
            .settingsPrivacyImportSettings,
            .commandCloseWindow,
            // e05's four View-menu verbs, so every action on a nudge surface is discoverable
            // here as well as reachable (F-145).
            .commandThisIsRelevant,
            .commandSnoozeNudge,
            .commandHideOverlays,
            .commandShowMenuBar,
            // e07a's three answers to a question, discoverable here because the panel that
            // draws them can never carry a keystroke (U-1).
            .commandAnswerYes,
            .commandAnswerNo,
            .commandAnswerNotNow,
            // e09a's History, which is a destination rather than a verb but is bound and
            // therefore listed like everything else that is.
            .commandShowHistory,
            .commandHelp,
            .commandShowWalkthrough
        ])
    }

    @Test("rows are grouped by menu, in menu-bar order, with no empty group")
    func groupsFollowTheMenuBar() {
        let groups = ShortcutsHelpView.groups(for: registry)

        #expect(groups.map(\.placement) == [.file, .view, .help])
        #expect(groups.map(\.headingKey) == [.helpGroupFile, .helpGroupView, .helpGroupHelp])
        for group in groups {
            #expect(!group.rows.isEmpty)
        }
    }

    @Test("nothing is invented: a row exists only if the registry declares the action")
    func noRowIsInvented() {
        let rows = ShortcutsHelpView.groups(for: registry).flatMap(\.rows)
        let declaredIDs = Set(registry.actions.map(\.id))

        for row in rows {
            #expect(declaredIDs.contains(row.id))
        }
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    @Test("an action with no key equivalent still gets a row")
    func unboundActionsAreStillListed() {
        // Per the Court's ruling, not every action needs a shortcut — but every action must
        // stay reachable and discoverable. A row with no glyphs is how the reference says
        // "this exists, and it has no shortcut" instead of hiding the action.
        let unbound = ShellAction(
            id: "shell.test.unbound",
            titleKey: .cockpitOpenSettings,
            shortcut: nil,
            placement: .file,
            effect: .openWindow(.cockpit)
        )
        let extended = CommandRegistry(actions: registry.actions + [unbound])
        let rows = ShortcutsHelpView.groups(for: extended).flatMap(\.rows)

        #expect(rows.count == registry.actions.count + 1)
        // Grouped by menu, so the new File action sits with the other File actions rather
        // than at the end of the whole reference.
        #expect(rows.map(\.id) == [
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
            "shell.test.unbound",
            "nudge.relevant",
            "nudge.snooze",
            "nudge.hideOverlays",
            "nudge.menuBar",
            "nudge.answerYes",
            "nudge.answerNo",
            "nudge.answerNotNow",
            "shell.history",
            "shell.help",
            "help.walkthrough"
        ])
        #expect(rows.first { $0.id == "shell.test.unbound" }?.glyphs == nil)
    }

    @Test(
        "every string the reference draws resolves to real text",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func referenceStringsResolve() {
        let keys: [ShellStringKey] = [
            .helpHeading, .helpIntroduction, .helpColumnAction, .helpColumnShortcut,
            .helpGroupFile, .helpGroupHelp
        ]
        for key in keys {
            let resolved = ShellStrings.string(key)
            #expect(!resolved.isEmpty)
            #expect(resolved != key.rawValue)
        }
    }

    @Test(
        "the cockpit's own strings resolve too",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func cockpitStringsResolve() {
        let keys: [ShellStringKey] = [
            .cockpitWindowTitle, .helpWindowTitle, .cockpitHeading, .cockpitStoreReady,
            .cockpitStoreUnavailable, .cockpitOpenSettings
        ]
        for key in keys {
            let resolved = ShellStrings.string(key)
            #expect(!resolved.isEmpty)
            #expect(resolved != key.rawValue)
        }
    }

    @Test("the cockpit reports paused while nothing is being observed")
    func cockpitStateIsHonestAboutSensing() {
        // `paused` is the truthful answer for a build with no sensing adapters: the app has
        // observed nothing, so it has judged nothing. Anything else would be a verdict it
        // has no basis for.
        #expect(CockpitState.ready.status == .paused)
        #expect(!CockpitState.ready.isObservingActivity)
        #expect(CockpitState.ready.storeIsReady)
        #expect(!CockpitState.storeUnavailable.storeIsReady)
        #expect(!CockpitState.ready.status.permitsIntervention)
    }
}
