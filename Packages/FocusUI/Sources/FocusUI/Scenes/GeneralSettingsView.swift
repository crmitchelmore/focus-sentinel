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
    /// **Which build this is** (focus-odz.3). Handed in, never read from `Bundle.main` here: a
    /// pane that read its own would draw the test runner's version in the unit lane and Xcode's
    /// in a preview, so the one bundle that matters is read by the composition root.
    private let appVersion: String
    /// **What the system says about opening this app at login** (D-12, focus-odz.4). Read from
    /// the service by the composition root every time this pane is built, never a stored `Bool`:
    /// a person who removes the app from Login Items in System Settings has changed the truth.
    private let launchAtLogin: LaunchAtLogin
    private let onLaunchAtLogin: (LaunchAtLoginAction) -> Void

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @FocusState private var focus: FocusField?
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    public init(
        preference: Binding<AppearancePreference>,
        appVersion: String = AppVersion.rendered(bundle: .main),
        launchAtLogin: LaunchAtLogin = .unregistered,
        onLaunchAtLogin: @escaping (LaunchAtLoginAction) -> Void = { _ in }
    ) {
        self._preference = preference
        self.appVersion = appVersion
        self.launchAtLogin = launchAtLogin
        self.onLaunchAtLogin = onLaunchAtLogin
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

            ShellText(.settingsAppearanceNote, role: .footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            launchAtLoginRow

            // **The build a person can quote in a defect report** (focus-odz.3).
            //
            // `LabeledContent` rather than two `Text`s in an `HStack`: it is the Settings idiom,
            // it aligns with the picker above it, and it gives VoiceOver a label for the number.
            // The number itself is `verbatim` because it is data, not prose — the same reason the
            // Privacy pane's store path is (registered in `Config/verbatim-sites.txt`).
            LabeledContent {
                Text(verbatim: appVersion)
                    .font(DesignTokens.font(.footnote, scale: textScale))
                    .textSelection(.enabled)
            } label: {
                ShellText(.settingsGeneralVersion, role: .footnote)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            }
        }
        // The *columns* form style — SwiftUI's default on macOS — rather than `.grouped`.
        // Measured: a grouped form is List-backed and rasterises to a solid rectangle under
        // `ImageRenderer`, so a grouped pane could never be snapshot-verified at all. The
        // columns style is equally standard Settings chrome and is drawn by SwiftUI itself.
        .padding(spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .defaultFocus($focus, .generalAppearancePicker)
        // What this pane drew, reported by this pane rather than by the window that built it
        // (focus-7ow). The picker's selection *is* the binding, so this is the value on screen.
        .shellRendered(.appearancePreference, preference.rawValue)
        // Reported by the pane that drew it, not by the window that built it: a mutation that
        // hands this pane a constant is invisible to a receipt taken anywhere else (focus-7ow).
        .shellRendered(.appVersion, appVersion)
        // The **status**, not the switch position: two of the four states draw the same position,
        // and only one of them is true yet (focus-odz.4).
        .shellRendered(.launchAtLoginStatus, launchAtLogin.status.rawValue)
    }

    /// **Opening at login, opt-in and read from the service** (D-12, focus-odz.4).
    ///
    /// Three things about this row are decisions rather than layout.
    ///
    /// * The switch's position comes from `LaunchAtLogin`, which is derived from
    ///   `SMAppService.status` on every build of this pane. A stored `Bool` would go on saying
    ///   "on" after somebody removed the app from Login Items in System Settings.
    /// * It is **disabled** while approval is outstanding, and the footnote says why. Nothing
    ///   this app does moves that state, so a switch that could be flicked there would be a
    ///   control that does nothing — *"a shortcut that silently does nothing is a shortcut people
    ///   stop trusting"*, which `CockpitView` states about the menu and is the same rule.
    /// * The button beside the footnote is the honest response to a permission this app cannot
    ///   grant itself: it opens the one place the person can.
    @ViewBuilder
    private var launchAtLoginRow: some View {
        Toggle(isOn: Binding(
            get: { launchAtLogin.isOn },
            set: { onLaunchAtLogin(.setEnabled($0)) }
        )) {
            ShellText(.settingsLaunchAtLogin)
        }
        .disabled(!launchAtLogin.isAdjustable)
        .focused($focus, equals: .generalLaunchAtLogin)

        if launchAtLogin.needsApproval {
            ShellText(.settingsLaunchAtLoginApproval, role: .footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onLaunchAtLogin(.openSystemSettings)
            } label: {
                ShellText(.settingsLaunchAtLoginOpenSettings)
            }
        } else if launchAtLogin.status == .notFound {
            ShellText(.settingsLaunchAtLoginUnavailable, role: .footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
