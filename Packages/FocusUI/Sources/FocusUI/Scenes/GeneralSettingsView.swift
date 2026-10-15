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
    /// Where the walkthrough button's command goes (focus-u6de). The shared centre in the app;
    /// injectable so a test can watch the command arrive without a menu bar.
    private let commandCenter: FocusCommandCenter
    /// **What the pane draws about software updates** (focus-h8jf). Handed in, never read from
    /// an updater here: the pane renders a value and the composition root owns the updater.
    private let softwareUpdates: SoftwareUpdateStatus
    private let onSoftwareUpdateAction: (SoftwareUpdateSettingsAction) -> Void

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
        onCaptureAction: @escaping (CaptureSettingsAction) -> Void = { _ in },
        commandCenter: FocusCommandCenter = .shared,
        softwareUpdates: SoftwareUpdateStatus = .off,
        onSoftwareUpdateAction: @escaping (SoftwareUpdateSettingsAction) -> Void = { _ in }
    ) {
        self._preference = preference
        self.appVersion = appVersion
        self.launchAtLogin = launchAtLogin
        self.onLaunchAtLogin = onLaunchAtLogin
        self.ritualEnabled = ritualEnabled
        self.quickCaptureShortcut = quickCaptureShortcut
        self.onCaptureAction = onCaptureAction
        self.commandCenter = commandCenter
        self.softwareUpdates = softwareUpdates
        self.onSoftwareUpdateAction = onSoftwareUpdateAction
    }

    /// Every option the picker offers, in the order it offers them.
    ///
    /// `AppearancePreference.allCases` rather than a hand-written list: an option added to
    /// the domain enum appears here automatically, and cannot be silently omitted.
    nonisolated public static var options: [AppearancePreference] { AppearancePreference.allCases }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            VStack(alignment: .leading, spacing: spacing) {
                CompanionSectionHeading(key: .settingsAppearanceLabel, symbol: "paintpalette")
                ViewThatFits(in: .horizontal) {
                    HStack { appearanceButtons }
                    VStack(alignment: .leading) { appearanceButtons }
                }
                ShellText(.settingsAppearanceNote, role: .footnote)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .companionSurface()

            VStack(alignment: .leading, spacing: spacing) {
                launchAtLoginRow
                Divider()
                ritualRow
            }
            .companionSurface()

            VStack(alignment: .leading, spacing: spacing) {
                quickCaptureRow
            }
            .companionSurface()

            VStack(alignment: .leading, spacing: spacing) {
                walkthroughRow
            }
            .companionSurface()

            VStack(alignment: .leading, spacing: spacing) {
                softwareUpdatesSection
            }
            .companionSurface()

            LabeledContent {
                Text(verbatim: appVersion)
                    .font(DesignTokens.font(.footnote, scale: textScale))
                    .textSelection(.enabled)
            } label: {
                ShellText(.settingsGeneralVersion, role: .footnote)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            }
        }
        // The one dialog margin every pane and sheet draws (focus-udn9).
        .dialogInset()
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(CompanionButtonStyle())
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
        // The two columns that had a launch reader and no writer, reported by the pane that now
        // writes them: a receipt taken anywhere else would be blind to a control handed a
        // constant (focus-7ow, focus-d3g).
        .shellRendered(.ritualEnabled, ritualEnabled ? "on" : "off")
        .shellRendered(.quickCaptureShortcut, quickCaptureShortcut.glyphs)
        // **The whole update status, as the pane drew it** (focus-h8jf). The digest rather than
        // the switch position: the train and the manual-check availability are drawn too, and a
        // pane handed the other train's status draws the same switch.
        .shellRendered(.softwareUpdates, ShellValueDigest.describe(softwareUpdates))
    }

    /// **Software updates, opt-in** (focus-h8jf).
    ///
    /// The switch is the only route by which the updater is ever started on a schedule, and the
    /// manual check (here or in File) is the only other route by which it is started at all.
    /// Off is the shipped state,
    /// and the footnote says what on costs: one request a day carrying the app's name and
    /// version. The Privacy pane's two disclosure sentences point here.
    @ViewBuilder
    private var softwareUpdatesSection: some View {
        CompanionSectionHeading(key: .settingsUpdatesHeading, symbol: "arrow.down.circle")

        Button { onSoftwareUpdateAction(.setAutomaticChecks(!softwareUpdates.checksAutomatically)) } label: {
            settingToggleLabel(
                .settingsUpdatesAutomatic,
                isOn: softwareUpdates.checksAutomatically,
                symbol: "clock.arrow.2.circlepath"
            )
        }
        .buttonStyle(CompanionButtonStyle(selected: softwareUpdates.checksAutomatically))
        .accessibilityAddTraits(softwareUpdates.checksAutomatically ? .isSelected : [])
        .focused($focus, equals: .generalSoftwareUpdates)
        // Every control carries a tooltip, and a disabled one says why (focus-8ski).
        .shellHelp(.settingsUpdatesAutomaticHelp)

        Button { onSoftwareUpdateAction(.checkNow) } label: {
            ShellText(.settingsUpdatesCheckNow, role: .callout)
        }
        .disabled(!softwareUpdates.canCheckNow)
        .focused($focus, equals: .generalCheckForUpdates)
        .shellHelp(
            .settingsUpdatesCheckNowHelp,
            disabled: .settingsUpdatesCheckNowDisabledHelp,
            when: !softwareUpdates.canCheckNow
        )

        if let failure = softwareUpdates.failure {
            ShellText(Self.updateFailureKey(failure), role: .footnote)
                .foregroundStyle(DesignTokens.Palette.role(.kiln, for: traits))
                .fixedSize(horizontal: false, vertical: true)
        }

        ShellText(.settingsUpdatesNote, role: .footnote)
            .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)

        if softwareUpdates.train == .alpha {
            ShellText(.settingsUpdatesAlpha, role: .footnote)
                .foregroundStyle(DesignTokens.Palette.role(.kiln, for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    nonisolated static func updateFailureKey(_ failure: SoftwareUpdateFailure) -> ShellStringKey {
        switch failure {
        case .configuration: .settingsUpdatesConfigurationError
        case .feedUnavailable: .settingsUpdatesFeedUnavailable
        case .network: .settingsUpdatesNetworkError
        case .other: .settingsUpdatesError
        }
    }

    /// **The daily ritual banner's switch** (focus-d3g).
    ///
    /// The column's own comment says *"whether the daily ritual banner is offered at all"*, and
    /// until now nothing in the application could set it — so the banner could not be turned off
    /// by anybody who did not want it. A different fact from `lastRitualLocalDay`, which records
    /// that today's ritual has been answered: one is a preference, the other is a diary entry.
    private var appearanceButtons: some View {
        ForEach(Self.options, id: \.self) { option in
            let button = Button { preference = option } label: {
                Label {
                    ShellText(option.settingsTitleKey, role: .callout)
                } icon: {
                    Image(systemName: option == .matchSystem ? "circle.lefthalf.filled" : (option == .light ? "sun.max" : "moon"))
                }
            }
            .buttonStyle(CompanionButtonStyle(selected: preference == option))
            .accessibilityAddTraits(preference == option ? .isSelected : [])
            .shellHelp(Self.helpKey(option))
            if option == Self.options.first {
                button.focused($focus, equals: .generalAppearancePicker)
            } else { button }
        }
    }

    /// Each appearance choice's tooltip: a total switch, so a fourth option is a compile error
    /// here rather than a button with nothing to say.
    nonisolated static func helpKey(_ option: AppearancePreference) -> ShellStringKey {
        switch option {
        case .matchSystem: .settingsAppearanceMatchSystemHelp
        case .light: .settingsAppearanceLightHelp
        case .dark: .settingsAppearanceDarkHelp
        }
    }

    private var shortcutButtons: some View {
        ForEach(HotKeySpec.quickCaptureChoices, id: \.self) { option in
            let button = Button { onCaptureAction(.setQuickCaptureShortcut(option)) } label: {
                Text(verbatim: option.glyphs)
                    .monospaced()
            }
            .buttonStyle(CompanionButtonStyle(selected: quickCaptureShortcut == option))
            .accessibilityAddTraits(quickCaptureShortcut == option ? .isSelected : [])
            .shellHelp(.settingsQuickCaptureShortcutHelp)
            if option == HotKeySpec.quickCaptureChoices.first {
                button.focused($focus, equals: .generalQuickCaptureShortcut)
            } else { button }
        }
    }

    private func settingToggleLabel(_ key: ShellStringKey, isOn: Bool, symbol: String) -> some View {
        HStack(spacing: spacing) {
            Image(systemName: symbol).accessibilityHidden(true)
            ShellText(key, role: .callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var ritualRow: some View {
        Button { onCaptureAction(.setRitualEnabled(!ritualEnabled)) } label: {
            settingToggleLabel(.settingsRitualEnabled, isOn: ritualEnabled, symbol: "sun.max")
        }
        .buttonStyle(CompanionButtonStyle(selected: ritualEnabled))
        .accessibilityAddTraits(ritualEnabled ? .isSelected : [])
        .focused($focus, equals: .generalRitualEnabled)
        .shellHelp(.settingsRitualEnabledHelp)

        ShellText(.settingsRitualEnabledNote, role: .footnote)
            .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// **The quick-capture shortcut** (focus-d3g, P-55/P-56).
    ///
    /// A picker over a committed list rather than a key-capture recorder. The defect was that
    /// somebody whose Mac already binds ⌃⌥⌘Space had **no route to a different combination** —
    /// `RegisterEventHotKey` takes the clash without complaint — and four options close that.
    /// A recorder is a different piece of work and nobody stuck needs it in order to be unstuck.
    ///
    /// Every option is `HotKeySpec.isRegistrable`, asserted over the whole list in `FocusCore`,
    /// so the picker cannot offer a combination the platform would take and not bind.
    @ViewBuilder
    private var quickCaptureRow: some View {
        CompanionSectionHeading(key: .settingsQuickCaptureShortcut, symbol: "keyboard")
        ViewThatFits(in: .horizontal) {
            HStack { shortcutButtons }
            VStack(alignment: .leading) { shortcutButtons }
        }


        ShellText(.settingsQuickCaptureShortcutNote, role: .footnote)
            .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// **The walkthrough, on demand** (focus-u6de).
    ///
    /// The same command the Help menu sends, so the button and the menu item are one act with
    /// one title key. The centre brings the cockpit forward and the cockpit presents the sheet;
    /// this pane holds no state about it. The delivery result is discarded for the reason
    /// `ShellCommands.perform` discards it: `showWalkthrough` opens the cockpit, and a process
    /// with nothing able to open one is a unit process.
    @ViewBuilder
    private var walkthroughRow: some View {
        Button {
            _ = commandCenter.send(.showWalkthrough)
        } label: {
            Label {
                ShellText(.commandShowWalkthrough, role: .callout)
            } icon: {
                Image(systemName: "book")
            }
        }
        .focused($focus, equals: .generalShowWalkthrough)
        .shellHelp(.commandShowWalkthroughHelp)

        ShellText(.settingsShowWalkthroughNote, role: .footnote)
            .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
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
        Button { onLaunchAtLogin(.setEnabled(!launchAtLogin.isOn)) } label: {
            settingToggleLabel(.settingsLaunchAtLogin, isOn: launchAtLogin.isOn, symbol: "power")
        }
        .buttonStyle(CompanionButtonStyle(selected: launchAtLogin.isOn))
        .accessibilityAddTraits(launchAtLogin.isOn ? .isSelected : [])
        .disabled(!launchAtLogin.isAdjustable)
        .focused($focus, equals: .generalLaunchAtLogin)
        // The disabled reason is the footnote's own sentence: the two states that disable the
        // switch are exactly the two that draw one, so the tooltip and the footnote cannot
        // disagree.
        .shellHelp(
            .settingsLaunchAtLoginHelp,
            disabled: launchAtLogin.footnote == .approval
                ? .settingsLaunchAtLoginApproval
                : .settingsLaunchAtLoginUnavailable,
            when: !launchAtLogin.isAdjustable
        )

        // The footnote is a value on `LaunchAtLogin` rather than a chain of `if`s here, so that
        // "the four statuses draw four distinct things" (H7.3) is a fold somebody can run rather
        // than a property of this view's shape.
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
            .shellHelp(.settingsLaunchAtLoginOpenSettingsHelp)
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
