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

    @State private var composition = AppComposition()
    @State private var appearance = AppearanceObserver()

    var body: some Scene {
        Window(Text(ShellStrings.resource(ShellWindow.cockpit.titleKey)), id: ShellWindow.cockpit.id) {
            CockpitView(state: composition.cockpitState)
                .appearanceTraits(appearance.traits)
        }
        .commands { ShellCommands() }
        .modelContainer(composition.modelContainer)

        Window(Text(ShellStrings.resource(ShellWindow.help.titleKey)), id: ShellWindow.help.id) {
            ShortcutsHelpView()
                .appearanceTraits(appearance.traits)
        }

        Settings {
            ShellSettingsScreen(appearance: appearance)
                .appearanceTraits(appearance.traits)
        }
        .modelContainer(composition.modelContainer)
    }
}

/// Settings: two tabs, both real.
private struct ShellSettingsScreen: View {
    let appearance: AppearanceObserver

    var body: some View {
        TabView {
            GeneralSettingsPane(appearance: appearance)
                .tabItem {
                    Label {
                        Text(LocalizedStringResource("settings.general.title"))
                    } icon: {
                        Image(systemName: "gearshape")
                    }
                }
            PrivacySettingsPane()
                .tabItem {
                    Label {
                        Text(LocalizedStringResource("settings.privacy.title"))
                    } icon: {
                        Image(systemName: "hand.raised")
                    }
                }
        }
        .frame(minWidth: 420)
    }
}

private struct GeneralSettingsPane: View {
    let appearance: AppearanceObserver

    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRows: [FocusSchemaV1.AppSettingsRecord]
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    var body: some View {
        Form {
            Picker(selection: preferenceBinding) {
                Text(LocalizedStringResource("settings.appearance.matchSystem"))
                    .tag(AppearancePreference.matchSystem)
                Text(LocalizedStringResource("settings.appearance.light"))
                    .tag(AppearancePreference.light)
                Text(LocalizedStringResource("settings.appearance.dark"))
                    .tag(AppearancePreference.dark)
            } label: {
                Text(LocalizedStringResource("settings.appearance.label"))
            }
            .pickerStyle(.inline)

            Text(LocalizedStringResource("settings.appearance.note"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
        .padding(spacing)
        .task {
            appearance.preference = storedPreference
        }
    }

    private var storedPreference: AppearancePreference {
        settingsRows.first?.appearancePreference ?? .matchSystem
    }

    private var preferenceBinding: Binding<AppearancePreference> {
        Binding(
            get: { storedPreference },
            set: { newValue in
                if let row = settingsRows.first {
                    row.appearancePreference = newValue
                    row.schemaTouchedAt = Date()
                } else {
                    modelContext.insert(
                        FocusSchemaV1.AppSettingsRecord(
                            appearancePreferenceRaw: newValue.rawValue,
                            schemaTouchedAt: Date()
                        )
                    )
                }
                try? modelContext.save()
                appearance.preference = newValue
            }
        )
    }
}

private struct PrivacySettingsPane: View {
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(LocalizedStringResource("settings.privacy.statement"))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: FocusStore.applicationSupportURL.path(percentEncoded: false))
                .font(.footnote)
                .monospaced()
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([FocusStore.applicationSupportURL])
            } label: {
                Text(LocalizedStringResource("settings.privacy.reveal"))
            }

            Spacer(minLength: 0)
        }
        .padding(spacing * 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
