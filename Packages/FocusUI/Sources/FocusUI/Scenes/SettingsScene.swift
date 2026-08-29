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

    public init(
        preference: AppearancePreference,
        setPreference: @escaping @MainActor (AppearancePreference) -> Void,
        storeURL: URL,
        summary: SensingSummary,
        capabilities: CapabilityMatrix,
        verdict: VerdictSnapshot?,
        intervention: InterventionSettings,
        onInterventionAction: @escaping @MainActor (InterventionSettingsAction) -> Void,
        didRender: @escaping @MainActor () -> Void = {}
    ) {
        self.preference = preference
        self.setPreference = setPreference
        self.storeURL = storeURL
        self.summary = summary
        self.capabilities = capabilities
        self.verdict = verdict
        self.intervention = intervention
        self.onInterventionAction = onInterventionAction
        self.didRender = didRender
    }
}

/// The Settings window: standard chrome, a toolbar-style tab switcher, each pane sized to
/// its own content.
///
/// Reached by ⌘, and by `Settings…` in the app menu — both of which SwiftUI provides for
/// free from the `Settings` scene, which is exactly why the app declares one rather than
/// building a preferences window by hand.
public struct ShellSettingsView: View {
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
        // Escape backs out of Settings, which is what `CancelBehaviour.dismissWindow`
        // declares for both panes and what a Mac user expects of a preferences window.
        .onExitCommand {
            NSApp.keyWindow?.performClose(nil)
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
