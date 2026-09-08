import AppIntents
import AppKit
import FocusCore
import FocusHost
import FocusUI
import SwiftData
import SwiftUI

/// The application.
///
/// Scenes and wiring only. Three scenes, chosen deliberately:
///
/// * `Window(id: "cockpit")` rather than `WindowGroup` — this is a single-instance cockpit,
///   and a `WindowGroup` would put "New Window ⌘N" in the File menu of an app that has no
///   second window. `Window` also gives correct Window-menu membership for free.
/// * `Window(id: "help")` — the Keyboard Shortcuts reference, which is the Help menu's real
///   destination. SwiftUI's default Help item opens a help book that does not exist; that
///   is a defect, and replacing it is one of this epic's jobs.
/// * `Settings` — the ⌘, idiom, which is where the Settings… item in the app menu comes
///   from.
///
/// No custom title bar, no `.windowStyle(.hiddenTitleBar)`, no borderless main window, and
/// no `NavigationSplitView`: a sidebar ships when it has a last real destination to point
/// at, not before.
///
/// ## Every statement in this file is one the gate can see (focus-2er)
///
/// `App/` is not a package: no test bundle can import it, and the only instrument that can
/// observe it is `--focus-self-check`, which runs this scene graph in the shipping process. So
/// the rule this file is now written to is that **there is nothing here for a lane to miss**.
/// Every value handed to a view is one `AppComposition` call, not five property reads; every
/// call is recorded as a named `ShellWire` and asserted by name; and no statement in this file
/// computes anything. What was here before — five cockpit arguments, seven settings arguments, a
/// hand-built `Binding` with a store write inside it, an `AppearanceObserver` nothing could
/// reach — is in `FocusHost` and `FocusUI`, under test targets.
@main
struct FocusSentinelApp: App {
    /// Hosts the zero-grant `--focus-self-check` mode. Nothing else.
    @NSApplicationDelegateAdaptor(FocusAppDelegate.self) private var appDelegate

    /// The composition root, and the only object this file names.
    ///
    /// There is deliberately no second `@State` here for the appearance observer. It used to be
    /// one — `AppearanceObserver()`, built by the scene — and a scene that builds its own would
    /// theme the cockpit from one object while the composition root themed the quick-capture
    /// panel from another, which no lane in the programme can see. The observer is the root's,
    /// reached through it, and SwiftUI's observation follows the property access wherever it is
    /// read from (focus-2er).
    @State private var composition = AppComposition.shared

    /// Builds the quick-capture panel, registers the global hot key, **reconciles whatever
    /// session was running**, and attaches the observer graph — at launch.
    ///
    /// Here rather than in a scene's `.task` for two measured reasons. "Built at launch" is a
    /// claim the app has to keep: probe P-57 timed 34 ms from the hot key to a visible, focused
    /// panel, and building it on first use is the only way to lose that. And restoration has to
    /// happen **before the first frame**, or the cockpit's first paint would show a session
    /// that had not yet been reconciled — a number the app knows is wrong, drawn once and then
    /// corrected, which is worse than drawing it right.
    ///
    /// `start()` is idempotent, so a re-created `App` value cannot offer the same shortcut to
    /// the platform twice or attach the observer graph twice.
    init() {
        AppComposition.shared.start()
        FocusAppShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        Window(Text(ShellStrings.resource(ShellWindow.cockpit.titleKey)), id: ShellWindow.cockpit.id) {
            CockpitHost(composition: composition)
                .appearanceTraits(composition.appearanceTraits(for: .cockpit))
        }
        .commands { ShellCommands() }
        // The measured size, read from the one place it is written down. Two literals in a
        // scene are two numbers no test can reach (focus-2er); `ShellWindowTests` holds these.
        .defaultSize(
            width: ShellWindow.cockpit.defaultSize?.width ?? 0,
            height: ShellWindow.cockpit.defaultSize?.height ?? 0
        )
        .modelContainer(composition.modelContainer)

        Window(Text(ShellStrings.resource(ShellWindow.help.titleKey)), id: ShellWindow.help.id) {
            // The reference reads nothing from the graph — it draws the committed
            // `CommandRegistry` — so the only thing distinguishing this window from a correctly
            // titled empty one is that the view says it drew (focus-2er).
            ShortcutsHelpView(didRender: composition.helpWindowRendered)
                .appearanceTraits(composition.appearanceTraits(for: .help))
        }
        // The measured size, from the one place both windows' sizes are written down
        // (focus-odz.6). This window had none, so it opened at AppKit's guess for a
        // content-sized SwiftUI scene — a narrow column with the shortcut glyphs wrapped under
        // their labels. `ShellWindowTests` holds these; `App/` computes nothing.
        .defaultSize(
            width: ShellWindow.help.defaultSize?.width ?? 0,
            height: ShellWindow.help.defaultSize?.height ?? 0
        )

        // e09a. The day's ledger. A window rather than a sidebar row: the shell has no split
        // view and `ShellActionEffect` has no "select destination" member, so this is the
        // destination that exists today (see `ShellWindow.history`).
        Window(Text(ShellStrings.resource(ShellWindow.history.titleKey)), id: ShellWindow.history.id) {
            HistoryHost(composition: composition)
                .appearanceTraits(composition.appearanceTraits(for: .cockpit))
        }
        // The measured size, from the one place every window's size is written down.
        .defaultSize(
            width: ShellWindow.history.defaultSize?.width ?? 0,
            height: ShellWindow.history.defaultSize?.height ?? 0
        )
        .modelContainer(composition.modelContainer)

        Settings {
            SettingsHost(composition: composition)
                .appearanceTraits(composition.appearanceTraits(for: .settings))
        }
        .modelContainer(composition.modelContainer)
    }
}

/// The cockpit, connected to the store.
///
/// A view of its own rather than a `CockpitView` built inline in the scene, because three
/// things have to happen inside a view body and cannot happen in a `Scene`:
///
/// * reading `host.state` where SwiftUI can observe it, so a mutation redraws the window;
/// * reading `@Environment(\.undoManager)`, which is the window's own manager and is `nil`
///   until there is a window — it is what the system Edit menu drives, and handing it to the
///   store's journal is the whole of F-93's menu integration (P-50);
/// * `.onOpenURL`, which is where an incoming `focus://` handoff arrives (P-60). It goes to
///   `receive(_:)`, which parses and **shows**. There is no route from here to a store
///   mutation that does not pass through a person pressing Replace (F-142).
private struct CockpitHost: View {
    let composition: AppComposition

    @Environment(\.undoManager) private var undoManager
    /// The live traits, so the window's own background is drawn in the scheme the shell was
    /// injected with rather than in whatever `NSAppearance.current` happens to be (focus-pq8).
    @Environment(\.appearanceTraits) private var traits

    /// The cockpit, in a scroll view.
    ///
    /// **The wrapper is here rather than inside `CockpitView`, and that is deliberate.** Measured
    /// on this machine: a `ScrollView` reports no intrinsic height, so under `ImageRenderer` a
    /// view inside one rasterises as a blank rectangle — the Privacy pane did exactly that the
    /// first time the capability table was put in one, 1 040 ink pixels in a 1040×2699 frame. Put
    /// the wrapper in the view and every committed cockpit baseline becomes a picture of nothing.
    ///
    /// So the view stays a plain column that renders whole, and the *scene* gives it somewhere to
    /// scroll. The person gets a window whose content is always reachable; the snapshot lane gets
    /// a picture of the whole column. Neither is traded for the other.
    var body: some View {
        ScrollView {
            cockpit
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DesignTokens.Palette.windowBackground(for: traits))
    }

    private var cockpit: some View {
        // **One argument, and it cannot be replaced with a placeholder** (focus-2er).
        //
        // This used to be five arguments read off the composition root, each an independently
        // guttable one-line no-op: `state:` alone froze the whole window — priority, session,
        // recents, verdict, capabilities, handoff sheet — and the nineteen-stage gate stayed at
        // PASS with an empty ok-assertion diff. `CockpitConnection` is assembled in `FocusHost`,
        // where every field is asserted against the live host, and a scene cannot build one: it
        // needs the app's only `PriorityActing` and its only `SessionActing`. The call is
        // recorded as `cockpitConnected`, and `CockpitView.body` records `cockpitRendered`
        // through a closure only the root supplies — so asking and drawing something else fails
        // as loudly as never asking.
        CockpitView(connection: composition.cockpitConnection())
            // **Three wires, each of which says its own name, and each of which fires**
            // (focus-cp2).
            //
            // Each calls **one named verb** on the composition root, which remembers that it was
            // called; `--focus-self-check` reports the set beside the effect each wire was
            // supposed to have, so a dead wire fails the gate by its own name rather than by a
            // symptom three objects away.
            //
            // And there is no longer an `.onAppear` beside each `.onChange` doing the same
            // thing. `initial: true` is exactly what that pair was emulating — run now, and
            // again whenever the value moves — and collapsing them is not tidiness: two
            // statements with one effect are two statements no lane can tell apart, so gutting
            // either was unobservable however hard the gate looked. `@Environment(\.undoManager)`
            // is still `nil` until there is a window, and this still adopts it when it arrives.
            .onChange(of: undoManager, initial: true) { _, manager in
                composition.undoManagerChanged(manager)
            }
            .onChange(of: composition.appearance.traits, initial: true) { _, traits in
                composition.appearanceChanged(traits)
            }
            // F-142's handoff. It parses and **shows**: there is no route from here to a stored
            // priority that does not pass through a person pressing Replace.
            .onOpenURL { url in
                composition.receive(url)
            }
    }
}

/// The Settings window, connected to the graph.
///
/// This is glue, not a screen, and it holds **no logic of its own** (focus-cp2, focus-2er). It
/// asks the composition root for one value and tells it when the window appears; both verbs live
/// on the root, under `AppCompositionSettingsTests`.
///
/// That matters because the Settings pane's controls need a click, and no lane in this programme
/// holds the Accessibility grant it would take to press a button in a headless run. What was
/// achievable before was "there is nothing in the wire left to assert"; what is achievable now is
/// stronger — the two mutations that survived the last round, `onInterventionAction` gutted to
/// `{ _ in }` and the appearance store write deleted, are no longer statements in this file at
/// all. They are `FocusHost` verbs with tests over them, reached through a value this scene
/// cannot fabricate.
private struct SettingsHost: View {
    let composition: AppComposition

    var body: some View {
        ShellSettingsView(connection: composition.settingsConnection())
            // The window may be opened long after launch, so the stored appearance preference is
            // re-read rather than assumed to still match what the observer was built with. The
            // read **and** the assignment are the composition root's; this is the trigger.
            //
            // `.onAppear` rather than `.task`, and the reason is the boundary this file is
            // written to (focus-2er). Measured here, in the built app: the Settings scene's
            // `.task` does not run in the self-check's process — ⌘, opens the window, the body
            // is evaluated, `settingsRendered` arrives, and the task's receipt never does, on a
            // run loop given a turn and a half of a second. A wire the only lane able to observe
            // `App/` cannot see is a wire nobody can defend, and there is nothing asynchronous
            // to do here: one stored read on the main actor.
            .onAppear {
                composition.settingsWindowAppeared()
            }
    }
}

/// The day's ledger, connected to the store.
///
/// A view of its own rather than a `HistoryView` built inline in the scene, for `CockpitHost`'s
/// reason: `@Environment(\.undoManager)` is the window's own manager and is `nil` until there is
/// a window, and a correction has to be undoable like every other rule the person writes.
///
/// The ledger is rebuilt on every body evaluation rather than cached. It is a read of four
/// tables over one local day — the same order of work `refreshCockpit` already does per tick —
/// and a cached one would be a window that quietly stopped agreeing with the store the moment
/// anything else in the app wrote a row.
private struct HistoryHost: View {
    let composition: AppComposition

    @Environment(\.undoManager) private var undoManager

    var body: some View {
        HistoryView(
            history: composition.todaysHistory(),
            corrected: composition.correctedHistoryRows
        ) { silence in
            composition.correctHistorySilence(silence, undo: undoManager)
        }
    }
}
