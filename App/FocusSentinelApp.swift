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
        Window(Text(LocalizedStringResource("shell.window.cockpit.title")), id: ShellWindow.cockpit.id) {
            CockpitScreen(composition: composition)
                .appearanceTraits(appearance.traits)
        }
        .commands { ShellCommands() }
        .modelContainer(composition.modelContainer)

        Window(Text(LocalizedStringResource("shell.window.help.title")), id: ShellWindow.help.id) {
            ShortcutsScreen()
                .appearanceTraits(appearance.traits)
        }

        Settings {
            ShellSettingsScreen(appearance: appearance)
                .appearanceTraits(appearance.traits)
        }
        .modelContainer(composition.modelContainer)
    }
}

// MARK: - Scenes' content
//
// The views below are the shell's real e01 content. They move into `FocusUI` when the
// design-token layer and the command registry land; until then they live here so that the
// app that ships at every commit is a working, HIG-correct shell rather than an empty
// window.

/// The cockpit: one column, no sidebar, no custom chrome.
private struct CockpitScreen: View {
    let composition: AppComposition

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.openSettings) private var openSettings
    @ScaledMetric(relativeTo: .body) private var rowSpacing: CGFloat = 12
    @ScaledMetric(relativeTo: .largeTitle) private var sectionSpacing: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: rowSpacing) {
                    heading
                    Spacer(minLength: rowSpacing)
                    StatusRow(status: composition.currentStatus)
                }
                VStack(alignment: .leading, spacing: rowSpacing) {
                    heading
                    StatusRow(status: composition.currentStatus)
                }
            }

            VStack(alignment: .leading, spacing: rowSpacing) {
                detail(
                    systemImage: composition.storeStatus.isReady
                        ? "internaldrive.fill" : "exclamationmark.triangle.fill",
                    text: composition.storeStatus.isReady
                        ? Text(LocalizedStringResource("shell.cockpit.store.ready"))
                        : Text(LocalizedStringResource("shell.cockpit.store.unavailable"))
                )
                detail(
                    systemImage: "eye.slash",
                    text: Text(LocalizedStringResource("shell.cockpit.sensing.unavailable"))
                )
            }

            Button {
                openSettings()
            } label: {
                Text(LocalizedStringResource("shell.cockpit.openSettings"))
            }
            .keyboardShortcut(.defaultAction)

            Spacer(minLength: 0)
        }
        .padding(sectionSpacing)
        .frame(minWidth: 420, minHeight: 260, alignment: .topLeading)
    }

    private var heading: some View {
        Text(LocalizedStringResource("shell.cockpit.heading"))
            .font(.largeTitle)
            .fontWeight(.semibold)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func detail(systemImage: String, text: Text) -> some View {
        Label {
            text
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
        }
        .foregroundStyle(traits.increasedContrast ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
    }
}

/// A status, encoded by glyph **and** shape **and** label — never by colour alone.
private struct StatusRow: View {
    let status: FocusStatus

    @Environment(\.appearanceTraits) private var traits
    @ScaledMetric(relativeTo: .title2) private var spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
            Image(systemName: status.symbolName)
                .symbolRenderingMode(.hierarchical)
                .font(.title2)
                .accessibilityHidden(true)
            Text(status.shortLabelResource)
                .font(.title3)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, spacing)
        .padding(.vertical, spacing / 2)
        .background(
            Capsule().strokeBorder(
                .secondary,
                lineWidth: traits.increasedContrast ? 2 : 1
            )
        )
        .accessibilityElement(children: .combine)
    }
}

/// The Help menu's real destination: the shortcut reference, rendered from the same action
/// table that builds the menu bar.
private struct ShortcutsScreen: View {
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(LocalizedStringResource("shell.help.heading"))
                .font(.title2)
                .fontWeight(.semibold)
                .lineLimit(nil)

            Grid(alignment: .leading, horizontalSpacing: spacing * 2, verticalSpacing: spacing) {
                ForEach(CommandRegistry.shell.actions) { action in
                    GridRow {
                        Text(action.title)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: action.shortcut?.glyphs ?? "")
                            .monospaced()
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(spacing * 2)
        .frame(minWidth: 320, minHeight: 180, alignment: .topLeading)
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
