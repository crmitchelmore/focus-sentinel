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
    /// **Whether the daily ritual banner is offered at all** (focus-d3g). Handed in, never a
    /// stored `Bool` this pane keeps: the value is a column, and a pane that remembered its own
    /// answer would go on saying "on" after the store was deleted.
    private let ritualEnabled: Bool
    /// **The combination quick capture is bound to** (focus-d3g).
    private let quickCaptureShortcut: HotKeySpec
    private let onCaptureAction: (CaptureSettingsAction) -> Void

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @FocusState private var focus: FocusField?
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    public init(
        preference: Binding<AppearancePreference>,
        appVersion: String = AppVersion.rendered(bundle: .main),
        launchAtLogin: LaunchAtLogin = .unregistered,
        onLaunchAtLogin: @escaping (LaunchAtLoginAction) -> Void = { _ in },
        ritualEnabled: Bool = true,
        quickCaptureShortcut: HotKeySpec = .quickCaptureDefault,
        onCaptureAction: @escaping (CaptureSettingsAction) -> Void = { _ in }
    ) {
        self._preference = preference
        self.appVersion = appVersion
        self.launchAtLogin = launchAtLogin
        self.onLaunchAtLogin = onLaunchAtLogin
        self.ritualEnabled = ritualEnabled
        self.quickCaptureShortcut = quickCaptureShortcut
        self.onCaptureAction = onCaptureAction
    }

    /// Every option the picker offers, in the order it offers them.
    ///
    /// `AppearancePreference.allCases` rather than a hand-written list: an option added to
    /// the domain enum appears here automatically, and cannot be silently omitted.
    nonisolated public static var options: [AppearancePreference] { AppearancePreference.allCases }

    public var body: some View {
        // **A column, not a `Form`** (focus-exdi). The columns-style `Form` this pane used to be
        // laid its labels in a gutter to the left of a content column, and at the window's
        // committed 460 points the long footnotes under each control pushed that gutter off the
        // left edge — "Quick capture shortcut" drew as "uick capture shortcut" — and clipped the
        // notes on the right. A `.grouped` form is List-backed and rasterises as a solid
        // rectangle, so the pane is drawn the way Privacy and Intervention already are: a
        // section per setting, its name as a heading, the control under it, the note under that.
        VStack(alignment: .leading, spacing: spacing) {
            section(.settingsAppearanceLabel, note: .settingsAppearanceNote) {
                Picker(selection: $preference) {
                    ForEach(Self.options, id: \.self) { option in
                        ShellText(option.settingsTitleKey)
                            .tag(option)
                    }
                } label: {
                    ShellText(.settingsAppearanceLabel)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .focused($focus, equals: .generalAppearancePicker)
            }
            Divider()
            launchAtLoginRow
            Divider()
            ritualRow
            Divider()
            quickCaptureRow
            Divider()
            HStack(spacing: spacing / 2) {
                ShellText(.settingsGeneralVersion, role: .footnote)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                Text(verbatim: appVersion)
                    .font(DesignTokens.font(.footnote, scale: textScale))
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(spacing * 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .defaultFocus($focus, .generalAppearancePicker)
        .shellRendered(.appearancePreference, preference.rawValue)
        .shellRendered(.appVersion, appVersion)
        .shellRendered(.launchAtLoginStatus, launchAtLogin.status.rawValue)
        .shellRendered(.ritualEnabled, ritualEnabled ? "on" : "off")
        .shellRendered(.quickCaptureShortcut, quickCaptureShortcut.glyphs)
    }

    /// One setting: its name as a heading, the control, and the note that explains it.
    private func section<Control: View>(
        _ heading: ShellStringKey,
        note: ShellStringKey?,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing / 2) {
            ShellText(heading, role: .headline)
            control()
            if let note {
                ShellText(note, role: .footnote)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The start-of-day question, on or off. A switch under its own name: the label the
    /// toggle would draw is the heading above it.
    private var ritualRow: some View {
        section(.settingsRitualEnabled, note: .settingsRitualEnabledNote) {
            Toggle(isOn: Binding(
                get: { ritualEnabled },
                set: { onCaptureAction(.setRitualEnabled($0)) }
            )) {
                ShellText(.settingsRitualEnabled)
            }
            .toggleStyle(.switch)
            .labelsHidden()
            .focused($focus, equals: .generalRitualEnabled)
        }
    }

    /// The quick-capture key, chosen from the combinations macOS lets the app bind.
    private var quickCaptureRow: some View {
        section(.settingsQuickCaptureShortcut, note: .settingsQuickCaptureShortcutNote) {
            Picker(selection: Binding(
                get: { quickCaptureShortcut },
                set: { onCaptureAction(.setQuickCaptureShortcut($0)) }
            )) {
                ForEach(HotKeySpec.quickCaptureChoices, id: \.self) { option in
                    Text(verbatim: option.glyphs)
                        .monospaced()
                        .tag(option)
                }
            } label: {
                ShellText(.settingsQuickCaptureShortcut)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .focused($focus, equals: .generalQuickCaptureShortcut)
        }
    }

    /// Open at login (D-12): the switch, disabled where the system will not let the app
    /// register, and the footnote that says why — or, when approval is pending, the button
    /// that opens the System Settings pane where it is granted.
    private var launchAtLoginRow: some View {
        VStack(alignment: .leading, spacing: spacing / 2) {
            ShellText(.settingsLaunchAtLogin, role: .headline)
            Toggle(isOn: Binding(
                get: { launchAtLogin.isOn },
                set: { onLaunchAtLogin(.setEnabled($0)) }
            )) {
                ShellText(.settingsLaunchAtLogin)
            }
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(!launchAtLogin.isAdjustable)
            .focused($focus, equals: .generalLaunchAtLogin)
            launchAtLoginFootnote
        }
    }

    @ViewBuilder
    private var launchAtLoginFootnote: some View {
        switch launchAtLogin.footnote {
        case .approval:
            ShellText(.settingsLaunchAtLoginApproval, role: .footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                onLaunchAtLogin(.openSystemSettings)
            } label: {
                ShellText(.settingsLaunchAtLoginOpenSettings)
            }
        case .unavailable:
            ShellText(.settingsLaunchAtLoginUnavailable, role: .footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        case nil:
            EmptyView()
        }
    }
}
