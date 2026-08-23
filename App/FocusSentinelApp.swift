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
    }

    var body: some Scene {
        Window(Text(ShellStrings.resource(ShellWindow.cockpit.titleKey)), id: ShellWindow.cockpit.id) {
            CockpitHost(composition: composition, appearance: appearance)
                .appearanceTraits(appearance.traits)
        }
        .commands { ShellCommands() }
        // Tall enough for the whole column at the default text size, measured against the real
        // window: with e03's session controls and sensing status added, the cockpit outgrew the
        // 704-point window e02 shipped and the footer was clipped below the fold. A window whose
        // last two lines are unreachable is a defect however good the lines are.
        .defaultSize(width: 560, height: 900)
        .modelContainer(composition.modelContainer)

        Window(Text(ShellStrings.resource(ShellWindow.help.titleKey)), id: ShellWindow.help.id) {
            ShortcutsHelpView()
                .appearanceTraits(appearance.traits)
        }

        Settings {
            SettingsHost(
                appearance: appearance,
                dateProvider: composition.dateProvider,
                sensing: composition.sensingHost,
                relevance: composition.relevanceHost
            )
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
        .background(DesignTokens.Palette.windowBackground)
    }

    private var cockpit: some View {
        CockpitView(
            state: composition.priorityHost.state,
            actions: composition.priorityHost,
            // The session host is the app's only `SessionActing`, and it is what the cockpit's
            // session controls and the four e03 menu commands both call — one code path for a
            // click and for a key equivalent.
            sessionActions: composition.sessionHost,
            sessionElapsedSeconds: composition.priorityHost.state.session
                .map { $0.elapsedWallSeconds(now: composition.dateProvider.now) },
            lastActiveBundleID: composition.sensingHost.lastForeignBundleIdentifier
        )
        .onAppear {
            composition.priorityHost.adoptUndoManager(undoManager)
            // The session journal drives the same Edit menu. Only the operations a *person*
            // performed reach it: an auto-pause for a screen lock is not something they meant
            // to do, and offering to undo it would be offering to undo the world.
            composition.sessionHost.adoptUndoManager(undoManager)
            composition.quickCapturePanel.update(traits: appearance.traits)
        }
        .onChange(of: undoManager) { _, manager in
            composition.priorityHost.adoptUndoManager(manager)
            composition.sessionHost.adoptUndoManager(manager)
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
    /// The live observer graph, so the Privacy pane draws what is actually attached.
    let sensing: SensingHost
    /// The live relevance runtime, so the Privacy pane's verdict inspector draws what the
    /// engine actually concluded rather than a value assembled for the occasion (R-71).
    let relevance: RelevanceHost

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ShellSettingsView(
            preference: preferenceBinding,
            storeURL: FocusStore.applicationSupportURL,
            // What is being watched, and what this Mac lets the app do — read from the graph
            // rather than probed again here, so the Privacy pane and the cockpit's status line
            // are one answer rather than two opinions.
            summary: sensing.summary,
            capabilities: sensing.capabilities,
            verdict: relevance.verdict
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
