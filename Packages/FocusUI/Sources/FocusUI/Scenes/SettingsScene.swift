import AppKit
import FocusCore
import SwiftUI

/// The tabs the Settings window offers.
///
/// Two, and both are full. No "coming soon" pane, no empty third tab reserved for a feature
/// that does not exist: a surface ships when it has content, not before.
public enum SettingsTab: String, Sendable, CaseIterable, Hashable, Identifiable {
    case general
    case privacy

    public var id: String { rawValue }

    public var titleKey: ShellStringKey {
        switch self {
        case .general: .settingsGeneralTitle
        case .privacy: .settingsPrivacyTitle
        }
    }

    /// The tab's SF Symbol. Standard Settings chrome draws these above the tab titles.
    public var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .privacy: "hand.raised"
        }
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

    public init(
        preference: Binding<AppearancePreference>,
        storeURL: URL,
        summary: SensingSummary = .inactive,
        capabilities: CapabilityMatrix = CapabilityMatrix()
    ) {
        self._preference = preference
        self.storeURL = storeURL
        self.summary = summary
        self.capabilities = capabilities
    }

    public var body: some View {
        TabView {
            GeneralSettingsView(preference: $preference)
                .tabItem { tabLabel(.general) }
                .tag(SettingsTab.general)

            PrivacySettingsView(
                storeURL: storeURL,
                summary: summary,
                capabilities: capabilities
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
