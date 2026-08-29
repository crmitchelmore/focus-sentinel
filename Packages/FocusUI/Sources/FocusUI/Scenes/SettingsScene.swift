import AppKit
import FocusCore
import SwiftUI

/// The tabs the Settings window offers.
///
/// Three from e05, and all three are full. No "coming soon" pane, no empty tab reserved for a
/// feature that does not exist: a surface ships when it has content, not before — which is why
/// the Intervention tab arrives in the epic that gives it something to configure rather than in
/// the one that first imagined it.
public enum SettingsTab: String, Sendable, CaseIterable, Hashable, Identifiable {
    case general
    case intervention
    case privacy

    public var id: String { rawValue }

    public var titleKey: ShellStringKey {
        switch self {
        case .general: .settingsGeneralTitle
        case .intervention: .interventionTitle
        case .privacy: .settingsPrivacyTitle
        }
    }

    /// The tab's SF Symbol. Standard Settings chrome draws these above the tab titles.
    public var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .intervention: "bell.badge"
        case .privacy: "hand.raised"
        }
    }
}

/// **Everything the Settings scene hands the Settings window, as one value** (focus-2er).
///
/// The scene passed seven separate arguments and built a `Binding` by hand, all inside a view
/// body in `App/` — which is not a package, so no test bundle can reach any of it. Two of the
/// epic's four acceptance mutations lived there and survived the whole gate: replacing
/// `onInterventionAction` with `{ _ in }`, which is what decides whether the app may speak at
/// all under U-1, and deleting the store write from the appearance binding's setter, so the
/// person's choice was forgotten the moment they quit.
///
/// Both are now `FocusHost` verbs on this value, assembled by `AppComposition.settingsConnection()`
/// where `AppCompositionSettingsTests` drives them, and the `Binding` is built here in `FocusUI`
/// rather than in a scene. What is left in `App/` is one argument that cannot be fabricated with
/// a placeholder — it carries two closures only the composition root can supply — and one
/// `.task`.
@MainActor
public struct ShellSettingsConnection {
    /// The appearance the person last chose, as the observer currently holds it.
    public let preference: AppearancePreference
    /// What a click on the Appearance picker performs: update the observer **and** write the
    /// store. One verb, in `FocusHost`, so there is nothing left in the scene to forget.
    public let setPreference: @MainActor (AppearancePreference) -> Void
    public let storeURL: URL
    public let summary: SensingSummary
    public let capabilities: CapabilityMatrix
    public let verdict: VerdictSnapshot?
    public let intervention: InterventionSettings
    /// What the Intervention pane's controls reach. Under U-1 this is what decides whether the
    /// app may speak, and it was `{ _ in }`-able in a file no lane could read.
    public let onInterventionAction: @MainActor (InterventionSettingsAction) -> Void
    /// Called from the window's body: the far end of the scene's one wire.
    public let didRender: @MainActor () -> Void

    /// Which issue of this connection the window is drawing from (focus-h7h). See
    /// `CockpitConnection.generation`.
    public let generation: Int

    /// **What the window drew, and the two sinks its controls will actually reach**
    /// (focus-h7h).
    ///
    /// The values half is the preference channel, as everywhere else. The two closures are the
    /// half that could not be done any other way: `setPreference` and `onInterventionAction` are
    /// only ever called by a **click**, and no lane in this programme holds the Accessibility
    /// grant it would take to press a button headlessly — which is exactly why `{ _ in }` in
    /// their place survived two rounds of gates. So the window hands back the closures it is
    /// holding, and the composition root drives them itself and watches its own graph move. A
    /// sink that was replaced with a no-op reaches nothing, and the graph does not move.
    public let didDraw: @MainActor (ShellSettingsRendering) -> Void

    public init(
        preference: AppearancePreference,
        setPreference: @escaping @MainActor (AppearancePreference) -> Void,
        storeURL: URL,
        summary: SensingSummary,
        capabilities: CapabilityMatrix,
        verdict: VerdictSnapshot?,
        intervention: InterventionSettings,
        onInterventionAction: @escaping @MainActor (InterventionSettingsAction) -> Void,
        generation: Int = 0,
        didRender: @escaping @MainActor () -> Void = {},
        didDraw: @escaping @MainActor (ShellSettingsRendering) -> Void = { _ in }
    ) {
        self.preference = preference
        self.setPreference = setPreference
        self.storeURL = storeURL
        self.summary = summary
        self.capabilities = capabilities
        self.verdict = verdict
        self.intervention = intervention
        self.onInterventionAction = onInterventionAction
        self.generation = generation
        self.didRender = didRender
        self.didDraw = didDraw
    }
}

/// **What the Settings window drew, and what its controls are wired to** (focus-h7h).
///
/// Two halves, because the Settings window has two kinds of thing that can silently stop working
/// and only one of them is visible. What the panes *show* is a value, reported through the
/// preference channel like every other window's. What the panes *do* is a closure nobody can
/// press without a grant — so it is handed back, and driven.
@MainActor
public struct ShellSettingsRendering {
    /// Everything the three panes reported drawing.
    public let values: ShellRenderedValues
    /// What the General pane's Appearance picker writes through — the binding's own setter,
    /// which is the path a click takes and nothing beside it.
    ///
    /// Plain closures rather than `@Sendable` ones: this whole type is `@MainActor`, so there is
    /// nowhere else they can be called from, and requiring `@Sendable` would mean the view could
    /// not hand back the very closure its controls hold — which is the only thing this type is
    /// for.
    public let setPreference: (AppearancePreference) -> Void
    /// What the Intervention pane's Voice and Reduced-Interruption controls reach.
    public let onInterventionAction: (InterventionSettingsAction) -> Void

    public init(
        values: ShellRenderedValues,
        setPreference: @escaping (AppearancePreference) -> Void,
        onInterventionAction: @escaping (InterventionSettingsAction) -> Void
    ) {
        self.values = values
        self.setPreference = setPreference
        self.onInterventionAction = onInterventionAction
    }
}

/// The Settings window: standard chrome, a toolbar-style tab switcher, each pane sized to
/// its own content.
///
/// Reached by ⌘, and by `Settings…` in the app menu — both of which SwiftUI provides for
/// free from the `Settings` scene, which is exactly why the app declares one rather than
/// building a preferences window by hand.
public struct ShellSettingsView: View {
    /// The traits the window resolved, so it can report which ones actually reached it
    /// (focus-h7h). Read from the environment rather than from the connection, because the
    /// injection is a separate wire from the connection and is separately guttable.
    @Environment(\.appearanceTraits) private var traits

    @Binding private var preference: AppearancePreference
    private let storeURL: URL
    private let summary: SensingSummary
    private let capabilities: CapabilityMatrix
    private let verdict: VerdictSnapshot?
    private let intervention: InterventionSettings
    private let onInterventionAction: (InterventionSettingsAction) -> Void
    /// What the window reports when its body is evaluated. `nil` for every caller that builds
    /// it out of loose values — the snapshot lane, the preview, the unit tests.
    private let didRender: (@MainActor () -> Void)?

    /// Which issue of the connection this window is drawing from, and where what it drew is
    /// delivered (focus-h7h).
    private let generation: Int
    private let didDraw: (@MainActor (ShellSettingsRendering) -> Void)?

    public init(
        preference: Binding<AppearancePreference>,
        storeURL: URL,
        summary: SensingSummary = .inactive,
        capabilities: CapabilityMatrix = CapabilityMatrix(),
        verdict: VerdictSnapshot? = nil,
        intervention: InterventionSettings = InterventionSettings(),
        onInterventionAction: @escaping (InterventionSettingsAction) -> Void = { _ in }
    ) {
        self._preference = preference
        self.storeURL = storeURL
        self.summary = summary
        self.capabilities = capabilities
        self.verdict = verdict
        self.intervention = intervention
        self.onInterventionAction = onInterventionAction
        self.didRender = nil
        self.generation = 0
        self.didDraw = nil
    }

    /// **The application scene's initialiser, and the only one it can reach** (focus-2er).
    ///
    /// The `Binding` the Appearance picker writes through is built **here**, from the
    /// connection's value and its verb, rather than by hand in a scene body no lane can read.
    /// That is what moves the store write out of `App/`: the setter is one closure the
    /// composition root supplies, and a scene has nothing left to get wrong.
    public init(connection: ShellSettingsConnection) {
        self._preference = Binding(
            get: { connection.preference },
            set: { connection.setPreference($0) }
        )
        self.storeURL = connection.storeURL
        self.summary = connection.summary
        self.capabilities = connection.capabilities
        self.verdict = connection.verdict
        self.intervention = connection.intervention
        self.onInterventionAction = connection.onInterventionAction
        self.didRender = connection.didRender
        self.generation = connection.generation
        self.didDraw = connection.didDraw
    }

    public var body: some View {
        // The far end of the scene's one wire (focus-2er), for the reason `CockpitView`'s is
        // where it is: a scene that asked the composition root and then drew something else must
        // fail the same assertion as one that never asked.
        let _ = didRender?()
        TabView {
            GeneralSettingsView(preference: $preference)
                .tabItem { tabLabel(.general) }
                .tag(SettingsTab.general)

            InterventionSettingsView(
                settings: intervention,
                onAction: onInterventionAction
            )
            .tabItem { tabLabel(.intervention) }
            .tag(SettingsTab.intervention)

            PrivacySettingsView(
                storeURL: storeURL,
                summary: summary,
                capabilities: capabilities,
                verdict: verdict
            )
            .tabItem { tabLabel(.privacy) }
            .tag(SettingsTab.privacy)
        }
        .frame(minWidth: 460, minHeight: 520)
        // **The six values this window built its three panes out of** (focus-h7h).
        //
        // Reported here, from the window, rather than from inside each pane — and that is a
        // measurement, not a preference. A macOS `TabView` builds only the pane a person has
        // selected: on the first run of this mechanism the Privacy pane's own stamps never
        // arrived at all, because nobody had clicked Privacy, and the General pane's were
        // swallowed by the tab hosting the selected pane sits in. A report that depended on which
        // tab happened to be in front would be a report that silently stopped asserting.
        //
        // What is claimed is therefore exactly what can be claimed: these are the values the
        // window constructed each pane from, in the same expression that constructs it. A
        // connection carrying a placeholder changes them, which is the whole of what the three
        // Settings mutations do.
        .shellRendered(.appearancePreference, preference.rawValue)
        .shellRendered(.interventionVoice, intervention.voice.rawValue)
        .shellRendered(.reducedInterruption, intervention.reducedInterruption ? "on" : "off")
        .shellRendered(.privacyCapabilities, capabilities.renderedDescription)
        .shellRendered(.verdictBand, verdict?.band?.rawValue ?? "none")
        .shellRendered(
            .privacySummary,
            SensingStatusView.renderedDescription(
                summary: summary,
                capabilities: capabilities,
                showsReducedCapabilities: false
            )
        )
        // Escape backs out of Settings, which is what `CancelBehaviour.dismissWindow`
        // declares for both panes and what a Mac user expects of a preferences window.
        .onExitCommand {
            NSApp.keyWindow?.performClose(nil)
        }
        // The traits this window resolved out of its own environment — the far end of the
        // Settings scene's own `.appearanceTraits` injection, which is a third wire and was
        // separately guttable (focus-h7h).
        .shellRendered(.appearanceTraits, traits.renderedDescription)
        // **The collection point, and the two sinks handed back with it** (focus-h7h).
        //
        // `$preference.wrappedValue = $0` is the path a click on the Appearance picker takes and
        // nothing beside it: the binding this view holds, whose setter is the connection's
        // `setPreference`. `onInterventionAction` is the closure the Intervention pane's controls
        // were actually given. Neither can be pressed by a lane with no Accessibility grant, so
        // the composition root drives them and watches its own graph move.
        .environment(\.shellRenderGeneration, generation)
        .onPreferenceChange(ShellRenderedValuesKey.self) { values in
            MainActor.assumeIsolated {
                didDraw?(
                    ShellSettingsRendering(
                        values: values,
                        setPreference: { preference = $0 },
                        onInterventionAction: onInterventionAction
                    )
                )
            }
        }
    }

    private func tabLabel(_ tab: SettingsTab) -> some View {
        Label {
            ShellText(tab.titleKey)
        } icon: {
            Image(systemName: tab.systemImage)
        }
    }
}
