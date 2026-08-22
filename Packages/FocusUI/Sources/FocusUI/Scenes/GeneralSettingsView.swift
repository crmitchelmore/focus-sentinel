import FocusCore
import SwiftUI

extension AppearancePreference {
    /// How this preference is named in Settings.
    ///
    /// Declared here rather than in `FocusCore`, because the domain type must not know what
    /// a String Catalog is — and because this is the package that owns the shell's text.
    public var settingsTitleKey: ShellStringKey {
        switch self {
        case .matchSystem: .settingsAppearanceMatchSystem
        case .light: .settingsAppearanceLight
        case .dark: .settingsAppearanceDark
        }
    }
}

/// The General settings pane: the appearance preference, and what the app does with it.
///
/// The preference is a binding rather than a store read, and that is deliberate. The pane
/// renders and edits a value; the app's composition root decides that the value is persisted
/// in `AppSettingsRecord` through `FocusStore`. Keeping the persistence out of the view is
/// what lets `FocusUI` stay to SwiftUI, AppKit and `FocusCore`, and what lets the snapshot
/// lane render this pane with no store at all.
public struct GeneralSettingsView: View {
    @Binding private var preference: AppearancePreference

    @Environment(\.appearanceTraits) private var traits
    @FocusState private var focus: FocusField?
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    public init(preference: Binding<AppearancePreference>) {
        self._preference = preference
    }

    /// Every option the picker offers, in the order it offers them.
    ///
    /// `AppearancePreference.allCases` rather than a hand-written list: an option added to
    /// the domain enum appears here automatically, and cannot be silently omitted.
    nonisolated public static var options: [AppearancePreference] { AppearancePreference.allCases }

    public var body: some View {
        Form {
            Picker(selection: $preference) {
                ForEach(Self.options, id: \.self) { option in
                    ShellText(option.settingsTitleKey)
                        .tag(option)
                }
            } label: {
                ShellText(.settingsAppearanceLabel)
            }
            .pickerStyle(.inline)
            .focused($focus, equals: .generalAppearancePicker)

            ShellText(.settingsAppearanceNote)
                .font(.footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
        .padding(spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .defaultFocus($focus, .generalAppearancePicker)
    }
}
