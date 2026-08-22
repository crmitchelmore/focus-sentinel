import AppKit
import FocusCore
import FocusSensing
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
@main
struct FocusSentinelApp: App {
    /// Hosts the zero-grant `--focus-self-check` mode. Nothing else.
    @NSApplicationDelegateAdaptor(FocusAppDelegate.self) private var appDelegate

    @State private var composition = AppComposition.shared
    @State private var appearance = AppearanceObserver()

    /// Builds the quick-capture panel and registers the global hot key, at launch.
    ///
    /// Here rather than in a scene's `.task` because "built at launch" is a *measured* claim
    /// the app has to keep: probe P-57 timed 34 ms from the hot key to a visible, focused
    /// panel, and building it on first use is the only way to lose that. `start()` is
    /// idempotent, so a re-created `App` value cannot offer the same combination twice.
    init() {
        AppComposition.shared.start()
    }

    var body: some Scene {
        Window(Text(ShellStrings.resource(ShellWindow.cockpit.titleKey)), id: ShellWindow.cockpit.id) {
            CockpitHost(composition: composition, appearance: appearance)
                .appearanceTraits(appearance.traits)
        }
        .commands { ShellCommands() }
        .modelContainer(composition.modelContainer)

        Window(Text(ShellStrings.resource(ShellWindow.help.titleKey)), id: ShellWindow.help.id) {
            ShortcutsHelpView()
                .appearanceTraits(appearance.traits)
        }

        Settings {
            SettingsHost(appearance: appearance, dateProvider: composition.dateProvider)
                .appearanceTraits(appearance.traits)
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
    let appearance: AppearanceObserver

    @Environment(\.undoManager) private var undoManager

    var body: some View {
        CockpitView(
            state: composition.priorityHost.state,
            actions: composition.priorityHost
        )
        .onAppear {
            composition.priorityHost.adoptUndoManager(undoManager)
            composition.quickCapturePanel.update(traits: appearance.traits)
        }
        .onChange(of: undoManager) { _, manager in
            composition.priorityHost.adoptUndoManager(manager)
        }
        .onChange(of: appearance.traits) { _, traits in
            composition.quickCapturePanel.update(traits: traits)
        }
        .onOpenURL { url in
            composition.priorityHost.receive(url)
        }
    }
}

/// Persists the appearance preference the Settings window edits.
///
/// This is glue, not a screen: it holds the `ModelContext` the Settings scene was given,
/// hands `FocusUI` a plain `Binding<AppearancePreference>`, and writes every change through
/// `FocusStore` — the same call the round-trip test exercises. Keeping it here rather than
/// in `FocusUI` is what lets the UI package stay to SwiftUI, AppKit and `FocusCore`, with no
/// knowledge of SwiftData at all.
private struct SettingsHost: View {
    let appearance: AppearanceObserver
    let dateProvider: any DateProvider

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ShellSettingsView(
            preference: preferenceBinding,
            storeURL: FocusStore.applicationSupportURL
        )
        .task {
            // The window may be opened long after launch, so the stored value is read here
            // rather than assumed to still match what the observer was built with.
            appearance.preference = FocusStore.appearancePreference(in: modelContext)
        }
    }

    private var preferenceBinding: Binding<AppearancePreference> {
        Binding(
            get: { appearance.preference },
            set: { newValue in
                // The observer is updated first so the shell re-renders immediately even if
                // the write fails; a store that cannot be written is a reason to tell the
                // user, never a reason to ignore what they just chose.
                appearance.preference = newValue
                try? FocusStore.setAppearancePreference(
                    newValue,
                    in: modelContext,
                    now: dateProvider.now
                )
            }
        )
    }
}
