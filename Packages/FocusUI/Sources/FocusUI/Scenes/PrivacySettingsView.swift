import AppKit
import FocusCore
import SwiftUI

/// The Privacy settings pane.
///
/// It says true things plainly and then proves them: this is where the data lives, here is the
/// button that shows you the file, here is what this Mac lets the app do and what it does
/// instead where it cannot. Nothing here is a promise about a future feature — deleting
/// everything is e07's surface and the full capability disclosure is e10's, and neither is
/// announced here.
///
/// **There is no call to action in the capability half, and that is the requirement rather than
/// a style choice.** F-126 asks the surface to show what is active, what is reduced and what the
/// reduced behaviour actually is, *with no call to action that would be an ask in disguise*. In
/// this epic the app could not ask even if somebody added a button: every prompting API is
/// banned from the shipping graph by lint (R-33).
///
/// The one limitation that is easy to hide is stated here instead: a person working over Screen
/// Sharing produces only synthetic input events, which never reach the HID counter, so once that
/// counter has climbed past the threshold the app considers them away whatever the session counter
/// says. That is a real consequence of taking the longer of the two idle silences (R-36,
/// focus-7az), and the honest place for it is the pane about what the app can and cannot see.
/// **What the Privacy pane can be asked to do** (e07a, focus-6pr.3).
///
/// One case, and a vocabulary rather than a bare closure so the pane's reach is a closed set a
/// test can fold: the review's I-4 asks that a person be able to see the pane offers *exactly*
/// this and nothing that would be an ask in disguise. It is the one action in the application
/// no self-check may press — it deletes the person's own store — so its effect is witnessed in
/// the unit lane against a store the test owns, and the running app is asked only to declare it.
public enum PrivacySettingsAction: Sendable, Equatable, Hashable {
    /// Delete every row the app holds about the person, and the file they were in, and start
    /// again with a store that never held them. Confirmed on a sheet first; never undoable.
    case deleteEverything
    /// **How long the app keeps what it wrote down** (F-115, focus-l7n). Not confirmed on a
    /// sheet: shortening the window is reversible in the sense that matters — the person can
    /// lengthen it again — and the rows it takes go on the next daily sweep rather than under
    /// the click, which is the same promise the pane's sentence makes.
    case setRetentionWindow(RetentionWindow)
    /// **Give me my data** (F-110, focus-ix9). One JSON file, through a save panel the person
    /// opened themselves, carrying only fields `Config/export-field-classification.txt` allows.
    case exportData
    /// **Set my other Mac up like this one** (F-134). A second, separate document: preferences
    /// and the person's own exclusion rows, with a version stamp and no history in it.
    case exportSettings
    /// The other direction, through an open panel. Validated whole and applied whole; a document
    /// this build cannot read is refused with a stated reason and applies nothing.
    case importSettings
    /// **The observers, switchable** (focus-exdi.3). Stored on `AppSettingsRecord` since v3 and
    /// never given a control until now: pause every observer, the away threshold, whether a
    /// running microphone keeps the app quiet, and whether a session opens the context pack.
    case setSensingPaused(Bool)
    case setIdleThreshold(seconds: Int)
    case setMediaSuppression(Bool)
    case setLaunchContextOnSessionStart(Bool)
    /// **Switch one macOS grant's ask on or off** (focus-exdi.4). Switching on is what permits
    /// the app to ask at all; macOS then asks the person. Switching off withdraws the
    /// permission to ask and returns the capability to `notRequested`.
    case setGrantOptIn(GrantOptIn, Bool)

    /// **The pane's vocabulary, as verbs.**
    ///
    /// One row per verb rather than per value: `setRetentionWindow` is one thing the pane can
    /// ask for, four times over, and a list that grew by four when a window was added would be
    /// a list nobody could read the review's I-4 out of — *the pane offers exactly these and
    /// nothing that would be an ask in disguise*.
    ///
    /// Derived from an exhaustive `switch`, so a case added without a name does not compile.
    public var verb: String {
        switch self {
        case .deleteEverything: "deleteEverything"
        case .setRetentionWindow: "setRetentionWindow"
        case .exportData: "exportData"
        case .exportSettings: "exportSettings"
        case .importSettings: "importSettings"
        case .setSensingPaused: "setSensingPaused"
        case .setIdleThreshold: "setIdleThreshold"
        case .setMediaSuppression: "setMediaSuppression"
        case .setLaunchContextOnSessionStart: "setLaunchContextOnSessionStart"
        case .setGrantOptIn: "setGrantOptIn"
        }
    }

    /// Every action the pane can produce, one per value it can produce it with. The self-check
    /// folds this to `verb`; the unit lane folds it to check nothing here is unreachable.
    public static var allDeclared: [PrivacySettingsAction] {
        [.deleteEverything]
            + RetentionWindow.ordered.map(PrivacySettingsAction.setRetentionWindow)
            + [.exportData, .exportSettings, .importSettings]
            + [
                .setSensingPaused(true), .setIdleThreshold(seconds: PrivacySettingsView.awayStep),
                .setMediaSuppression(false), .setLaunchContextOnSessionStart(true)
            ]
            + GrantOptIn.allCases.map { PrivacySettingsAction.setGrantOptIn($0, true) }
    }

    /// The vocabulary the self-check publishes, in the order the pane draws it.
    public static let vocabulary: [String] = [
        "deleteEverything", "setRetentionWindow", "exportData", "exportSettings", "importSettings",
        "setSensingPaused", "setIdleThreshold", "setMediaSuppression", "setLaunchContextOnSessionStart",
        "setGrantOptIn"
    ]

    /// **The title of the one alert this vocabulary can raise**, resolved here.
    ///
    /// The composition root runs the open panel and applies the document, so it is the object
    /// that learns an import was refused — but every word a person reads belongs to `FocusUI`
    /// and to its catalog (F-149: `FocusHost` declares and references no keys). So the sentence
    /// is drawn from here and handed over already resolved, and the reason beside it comes from
    /// `SettingsImportRefusal`, which is a closed vocabulary rather than a caught error's
    /// description.
    public static var importRefusedTitle: String {
        ShellStrings.string(.settingsPrivacyImportRefused)
    }
}

public struct PrivacySettingsView: View {
    private let storeURL: URL
    /// What the pane's one destructive control reaches. `{ _ in }` in a preview and in the
    /// snapshot lane; the composition root's `perform(_:)` in the shipping window.
    private let onAction: (PrivacySettingsAction) -> Void
    @State private var isConfirmingDeletion = false
    private let summary: SensingSummary
    private let capabilities: CapabilityMatrix
    private let verdict: VerdictSnapshot?
    /// **How long the app keeps what it wrote down, as the store holds it** (F-115, focus-l7n).
    ///
    /// Passed in rather than read here, for the reason every other stored value on this pane is:
    /// a control answering from its own memory would go on saying *90 days* after a
    /// delete-everything rebuilt the store.
    private let retention: RetentionWindow
    private let sensing: SensingSettingsValue
    private let grants: GrantOptIns
    /// **Which half of this pane to draw**, or `nil` for the whole of it, which is what the
    /// application always asks for (focus-u3w).
    ///
    /// It exists for the snapshot lane and it is not a product state. The pane is photographed
    /// unclamped — a bounded one is a `ScrollView`, which `ImageRenderer` cannot rasterise at
    /// all — and unclamped it now runs to roughly sixteen thousand rows at the largest text size
    /// under pseudo-localisation, which is past where CoreGraphics stops producing a picture:
    /// measured, an encode succeeded at 984×15 950 and the next render, a hundred rows taller,
    /// came back with neither bytes nor ink. Two halves are two pictures of the same pane, and
    /// each of them is a picture.
    private let half: Half?

    /// The pane's three parts, in the order a person reads them: **what is mine and what
    /// happens to it**, **what the app can see**, then **what it made of it**.
    ///
    /// Three since focus-exdi.4, and the reason is a measurement rather than a taste. These
    /// exist so the snapshot lane can photograph the pane at all: `ImageRenderer` degrades on a
    /// very tall render and hands back a picture with no ink in it. The grants section pushed
    /// the insight part to 6 603 rows pseudo-localised — where the text roughly doubles — and
    /// that render came back blank. Splitting the judgement out puts every piece back inside the
    /// renderer's range. The live window is unaffected: it draws `nil`, which is all three.
    public enum Half: String, Sendable, CaseIterable, Hashable {
        case ownership
        case insight
        case judgement
    }
    /// The displays this pane bounds itself against; `nil` for the live ones. Injectable for the
    /// reason `NudgePanelController.displays` is: the display this defect is worst on is a 13-inch
    /// laptop, and no lane can hand the pane one if it reads `NSScreen` for itself.
    private let screens: ShellScreens

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @FocusState private var focus: FocusField?
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    public init(
        storeURL: URL = FocusStore.applicationSupportURL,
        summary: SensingSummary = .inactive,
        capabilities: CapabilityMatrix = CapabilityMatrix(),
        verdict: VerdictSnapshot? = nil,
        retention: RetentionWindow = .committedDefault,
        sensing: SensingSettingsValue = .defaults,
        grants: GrantOptIns = .none,
        half: Half? = nil,
        screens: ShellScreens = nil,
        onAction: @escaping (PrivacySettingsAction) -> Void = { _ in }
    ) {
        self.storeURL = storeURL
        self.summary = summary
        self.capabilities = capabilities
        self.verdict = verdict
        self.retention = retention
        self.sensing = sensing
        self.grants = grants
        self.half = half
        self.screens = screens
        self.onAction = onAction
    }

    /// The strings this pane draws. Non-empty by construction, and asserted so: a Settings
    /// tab that renders nothing is a defect, not a design.
    nonisolated public static let contentKeys: [ShellStringKey] =
        [
            .settingsPrivacyStatement,
            .settingsPrivacyNoNetwork,
            .settingsPrivacyNoUpdateCheck,
            .settingsPrivacyStoreLabel,
            .settingsPrivacyReveal,
            .settingsPrivacyRetentionHeading,
            .settingsPrivacyRetentionExplanation,
            .settingsPrivacyPortabilityHeading,
            .settingsPrivacyPortabilityExplanation,
            .settingsPrivacyExportData,
            .settingsPrivacyExportSettings,
            .settingsPrivacyImportSettings,
            .settingsPrivacyDeleteHeading,
            .settingsPrivacyDeleteExplanation,
            .settingsPrivacyDeleteEverything,
            .sensingHeading,
            .sensingLimitationScreenSharing,
            .capabilityHeading,
            .capabilityExplanation
        ] + RetentionWindow.ordered.map(\.titleKey) + VerdictInspectorView.contentKeys

    /// **The pane, bounded** (focus-nu6).
    ///
    /// This used to be `content` and nothing else — one column, no scroll view, no height of any
    /// kind — inside a window whose only commitment was `minWidth: 460`. The column measures
    /// 2 699 points at the shipping text size, which is taller than any display made, so the
    /// capability table and the verdict inspector below it were off the bottom of the screen on
    /// every Mac at every window width, and no gesture in macOS reached them.
    ///
    /// The scroll view that would have fixed that was **deleted on purpose**, and the note left
    /// behind said why: a pane inside one rendered blank under `ImageRenderer`, so the committed
    /// baseline would have been a picture of nothing. That is the product being reshaped to suit
    /// the harness. The scroll is back; what changed instead is the harness's subject, which is
    /// `content` below — and the reason is now a test that re-measures it every run rather than a
    /// comment, because the note's diagnosis was also wrong. See `BoundedSurfaceTests`.
    public var body: some View {
        BoundedSurface(
            width: ShellSurfaceBounds.settingsWidth,
            ceiling: ShellSurfaceBounds.settingsCeiling(
                screens: screens ?? NudgePanelController.currentScreens()
            )
        ) {
            content
        }
        .defaultFocus($focus, .privacyRevealStore)
    }

    /// **The observers, switchable** (focus-exdi.3). Each row is a setting the store has kept
    /// since v3; the pane is the first place a person can reach it. Bordered buttons for the away
    /// dial rather than a `Stepper`, for the reason every control on this pane is.
    private var observerSwitches: some View {
        VStack(alignment: .leading, spacing: spacing / 2) {
            // The switch reads the summary, the same reading the cockpit's switch and the
            // status line draw: `SensingSummary.isPausedByUser` is what the running host says,
            // where the stored flag is what it was told at launch.
            switchRow(
                .sensingPauseLabel, note: .sensingPauseExplanation, isOn: !summary.isPausedByUser
            ) { onAction(.setSensingPaused(!$0)) }
            HStack(alignment: .firstTextBaseline, spacing: spacing / 2) {
                ShellText(.settingsPrivacyAwayAfter, role: .callout)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: spacing / 2)
                HStack(spacing: spacing / 4) {
                    Button {
                        onAction(.setIdleThreshold(seconds: sensing.idleThresholdSeconds - Self.awayStep))
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(Text(ShellStrings.resource(.settingsTuningsLower)))
                    .disabled(sensing.idleThresholdSeconds <= Self.awayFloor)
                    ShellText(
                        .settingsTuningsUnitMinutes,
                        role: .callout,
                        argument: (sensing.idleThresholdSeconds / Self.awayStep).formatted()
                    )
                    .monospacedDigit()
                    .frame(minWidth: Self.awayColumnWidth, alignment: .trailing)
                    Button {
                        onAction(.setIdleThreshold(seconds: sensing.idleThresholdSeconds + Self.awayStep))
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(Text(ShellStrings.resource(.settingsTuningsRaise)))
                    .disabled(sensing.idleThresholdSeconds >= Self.awayCeiling)
                }
            }
            ShellText(.settingsPrivacyAwayAfterNote, role: .footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            switchRow(
                .settingsPrivacyMicrophoneSuppression,
                note: .settingsPrivacyMicrophoneSuppressionNote,
                isOn: sensing.mediaSuppressionEnabled
            ) { onAction(.setMediaSuppression($0)) }
            switchRow(
                .settingsPrivacyLaunchContext,
                note: .settingsPrivacyLaunchContextNote,
                isOn: sensing.launchContextOnSessionStart
            ) { onAction(.setLaunchContextOnSessionStart($0)) }
        }
        .shellRendered(.sensingSettings, ShellValueDigest.describe(sensing))
    }

    /// **The grants a person may give** (focus-exdi.4, owner's ruling 2026-09-08).
    ///
    /// The programme shipped asking macOS for nothing. This is the only route it has to a grant,
    /// and it is a switch that is off: switching one on is the permission to *ask*, and macOS
    /// then asks the person. Each row says plainly that nothing in this version reads what the
    /// grant would unlock, because a switch that takes a permission and spends it on nothing is
    /// the worst version of this change.
    private var grantSwitches: some View {
        VStack(alignment: .leading, spacing: spacing / 2) {
            ShellText(.settingsPrivacyGrantsHeading, role: .headline)
            ShellText(.settingsPrivacyGrantsExplanation, role: .footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(GrantOptIn.allCases) { grant in
                VStack(alignment: .leading, spacing: spacing / 4) {
                    switchRow(
                        Self.labelKey(grant),
                        note: Self.noteKey(grant),
                        isOn: grants.isEnabled(grant)
                    ) { onAction(.setGrantOptIn(grant, $0)) }
                    if !grant.isConsumedByThisBuild {
                        ShellText(.settingsPrivacyGrantUnused, role: .footnote)
                            .foregroundStyle(DesignTokens.Palette.role(.kiln, for: traits))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .shellRendered(.grantOptIns, ShellValueDigest.describe(grants))
    }

    static func labelKey(_ grant: GrantOptIn) -> ShellStringKey {
        switch grant {
        case .accessibilityWindowContext: .settingsPrivacyGrantAccessibility
        case .screenCapture: .settingsPrivacyGrantScreenCapture
        }
    }

    static func noteKey(_ grant: GrantOptIn) -> ShellStringKey {
        switch grant {
        case .accessibilityWindowContext: .settingsPrivacyGrantAccessibilityNote
        case .screenCapture: .settingsPrivacyGrantScreenCaptureNote
        }
    }

    /// One switch: its name beside a check glyph, its note under it.
    ///
    /// A bordered button carrying its own state rather than a `Toggle`: a switch is AppKit-backed
    /// and rasterises under `ImageRenderer` as the yellow "unrenderable view" placeholder — this
    /// pane has baselines, and the first render of these rows was three yellow bars. The same
    /// shape the Intervention pane's "Interrupt me less" already uses.
    private func switchRow(
        _ label: ShellStringKey,
        note: ShellStringKey,
        isOn: Bool,
        set: @escaping (Bool) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing / 4) {
            Button {
                set(!isOn)
            } label: {
                HStack(spacing: spacing / 2) {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(
                            isOn ? DesignTokens.Palette.accent(for: traits) : DesignTokens.supportingTextColor(for: traits)
                        )
                        .accessibilityHidden(true)
                    ShellText(label, role: .callout)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .accessibilityAddTraits(isOn ? [.isSelected] : [])
            ShellText(note, role: .footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The away dial moves in whole minutes, from one to thirty.
    static let awayStep = 60
    static let awayFloor = 60
    static let awayCeiling = 30 * 60
    private static let awayColumnWidth: CGFloat = 56

    private func retentionButtons(_ windows: [RetentionWindow]) -> some View {
        ForEach(windows, id: \.self) { window in
            Button {
                onAction(.setRetentionWindow(window))
            } label: {
                ShellText(window.titleKey)
            }
            .buttonStyle(.bordered)
            // The same tint the timebox presets use for the same job — and, because a tint
            // is a colour, the accessibility trait beside it carries the selection where
            // colour cannot (F-146, F-144).
            .tint(window == retention ? DesignTokens.Palette.accent(for: traits) : nil)
            .accessibilityAddTraits(window == retention ? [.isSelected] : [])
        }
    }

    var content: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if half == nil || half == .ownership { ownershipContent }
            if half == nil { Divider() }
            if half == nil || half == .insight { insightContent }
            if half == nil { Divider() }
            if half == nil || half == .judgement { judgementContent }
            Spacer(minLength: 0)
        }
        .padding(spacing * 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        // **What this pane drew, reported by this pane** (focus-7ow).
        //
        // Every one of these used to be reported by the Settings *window*, from the argument it
        // was about to pass in — so a defect between the argument and the screen was invisible,
        // and the whole pane was invisible whenever somebody had a different tab selected. The
        // window drives the selection from the composition root now, and these are stamps on the
        // values this view is actually holding.
        .shellRendered(.privacyStorePath, storePath)
        // The number the sweep reads, not the label the button draws (F-115, focus-l7n).
        .shellRendered(.retentionWindow, retention.storedDays)
        .shellRendered(.privacyCapabilities, capabilities.renderedDescription)
        .shellRendered(
            .privacySummary,
            SensingStatusView.renderedDescription(
                summary: summary,
                capabilities: capabilities,
                showsReducedCapabilities: false
            )
        )
        // The whole summary and the whole verdict, derived rather than enumerated: the sentence
        // above is a projection of six facts, and the band is one field of a verdict that also
        // carries its subject, its confidence and its explanation (focus-7ow).
        .shellRendered(.sensingDetail, ShellValueDigest.describe(summary))
        .shellRendered(.verdictBand, verdict?.band?.rawValue ?? "none")
        .shellRendered(.verdictDetail, ShellValueDigest.describe(verdict))
    }

    /// **What is mine, and what happens to it**: where the data lives, the two things the app
    /// does not do, how long it is kept, how to take it away, and how to destroy it.
    @ViewBuilder
    private var ownershipContent: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ShellText(.settingsPrivacyStatement)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            // **The two things this app does not do** (F-122, F-137, focus-6n2). Directly under
            // the statement, because they are the same claim narrowed twice, and with no heading
            // of their own: a section for *"what we do not do"* invites the list to grow, and a
            // list of denials is a surface that reads as defensive rather than plain.
            //
            // Neither is a promise. The first is linted of the shipped binary by the gate's
            // `boundaries` and `boundaries-binary` stages — no networking symbol in any package
            // source, and none in `FocusClassify.o`. The second is linted the same way: no
            // Sparkle symbol, no `SUFeedURL` in the merged Info.plist, and `nm -u` over the
            // product naming neither. D-09 parked Sparkle for the reason this sentence states.
            VStack(alignment: .leading, spacing: spacing / 4) {
                ShellText(.settingsPrivacyNoNetwork, role: .footnote)
                ShellText(.settingsPrivacyNoUpdateCheck, role: .footnote)
            }
            .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: spacing / 3) {
                ShellText(.settingsPrivacyStoreLabel, role: .caption)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))

                // The path itself is data, not prose: it is the user's own file system
                // location and must never be routed through a catalog.
                //
                // One derivation, two consumers (focus-7ow): this is the string the person
                // reads, and it is the string the receipt reports. A mutation that printed `/`
                // here — with Reveal in Finder wired to open it — was invisible to the whole
                // nineteen-stage gate, because the only thing reporting a Settings value was the
                // window, and the window reported its own `storeURL` rather than the pane's.
                Text(verbatim: storePath)
                    .font(DesignTokens.font(.footnote, scale: textScale))
                    .monospaced()
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(spacing / 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The path is quoted material, so it is drawn on its own surface — which is also
            // where Reduce Transparency and Increase Contrast become visible in this pane:
            // the fill goes opaque, and the border thickens.
            .shellSurface(
                DesignTokens.material(for: traits, provenance: .summoned),
                in: RoundedRectangle(cornerRadius: spacing / 2, style: .continuous),
                traits: traits
            )
            .overlay {
                RoundedRectangle(cornerRadius: spacing / 2, style: .continuous)
                    .strokeBorder(
                        DesignTokens.Palette.separator(for: traits)
                            .opacity(DesignTokens.emphasis(for: traits).outlineOpacity),
                        lineWidth: DesignTokens.emphasis(for: traits).borderWidth
                    )
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([storeURL])
            } label: {
                ShellText(.settingsPrivacyReveal)
            }
            .keyboardShortcut(.defaultAction)
            .focused($focus, equals: .privacyRevealStore)

            Divider()

            // **How long any of this is kept** (F-115, focus-l7n). It sits directly above the
            // delete-everything control because the two are the same promise at two speeds: one
            // says what goes on its own, the other says everything, now.
            //
            // Four plain buttons rather than a `Picker`, and the reason is a measured one rather
            // than a taste: an AppKit-backed control does not rasterise under `ImageRenderer`, so
            // a picker here would make the committed baseline a picture of SwiftUI's
            // unrenderable-view placeholder — evidence of nothing. A row of buttons is also the
            // shape that keeps the *chosen* value legible without colour (F-146): the selected
            // one is bordered-prominent and carries the accessibility trait, so VoiceOver and a
            // person with `differentiateWithoutColor` on both get the same answer.
            VStack(alignment: .leading, spacing: spacing / 2) {
                ShellText(.settingsPrivacyRetentionHeading, role: .headline)
                ShellText(.settingsPrivacyRetentionExplanation, role: .footnote)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                // Four buttons on one line where they fit, two by two where they do not
                // (focus-exdi) — the same fallback `PortabilityRow` measured it needed.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: spacing / 2) {
                        retentionButtons(RetentionWindow.ordered)
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: spacing / 2) {
                        HStack(spacing: spacing / 2) {
                            retentionButtons(Array(RetentionWindow.ordered.prefix(2)))
                        }
                        HStack(spacing: spacing / 2) {
                            retentionButtons(Array(RetentionWindow.ordered.dropFirst(2)))
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(ShellStrings.resource(.settingsPrivacyRetentionHeading))
            }

            Divider()

            // **Take it and leave** (F-110, F-134, focus-ix9). Two documents and three verbs,
            // drawn together because the question a person is answering here is one question:
            // what of this is mine, and how do I get it out.
            //
            // No share sheet. `NSSharingService` routes a private file to a network service in
            // one click, at the exact surface whose job is to prove there are none — so the only
            // destination either verb offers is a folder the person picked in a panel they
            // opened themselves.
            VStack(alignment: .leading, spacing: spacing / 2) {
                ShellText(.settingsPrivacyPortabilityHeading, role: .headline)
                ShellText(.settingsPrivacyPortabilityExplanation, role: .footnote)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                PortabilityRow(spacing: spacing, onAction: onAction)
            }

            Divider()

            // **The one thing here a person can undo the app with** (e07a, focus-6pr.3). The
            // statement above says everything lives in one local file; this is the button that
            // makes that a promise with an exit. It confirms on a sheet, because the deletion
            // is not undoable and a destructive control one click from a settings tab would be
            // a control somebody presses by mistake.
            VStack(alignment: .leading, spacing: spacing / 2) {
                ShellText(.settingsPrivacyDeleteHeading, role: .headline)
                ShellText(.settingsPrivacyDeleteExplanation, role: .footnote)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Button(role: .destructive) {
                    isConfirmingDeletion = true
                } label: {
                    ShellText(.settingsPrivacyDeleteEverything)
                }
            }
            .sheet(isPresented: $isConfirmingDeletion) {
                DeleteEverythingSheet(
                    confirm: {
                        isConfirmingDeletion = false
                        onAction(.deleteEverything)
                    },
                    cancel: { isConfirmingDeletion = false }
                )
            }
        }
    }

    /// **What the app can see, and what it made of it**: the sensing summary, the capability
    /// table, the cascade it decides through, and the verdict it reached. Nothing here offers
    /// anything to press — F-126 asks for exactly that, and R-33 makes it structural.
    @ViewBuilder
    private var insightContent: some View {
        VStack(alignment: .leading, spacing: spacing) {
            // What is being watched right now, with its working shown — including the lines
            // whose answer is "no". A surface that only reported the interesting half would be
            // showing half of it.
            VStack(alignment: .leading, spacing: spacing / 2) {
                ShellText(.sensingHeading, role: .headline)
                SensingStatusView(summary: summary, showsDetail: true)
                observerSwitches

                ShellText(.sensingLimitationScreenSharing, role: .footnote)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            CapabilityMatrixView(capabilities: capabilities)

            Divider()

            grantSwitches

        }
    }

    /// **What the app made of what it can see** (focus-exdi.4): the cascade's order of
    /// precedence and the verdict it reached. Its own part, so that no single render grows past
    /// what `ImageRenderer` will draw — see `Half`.
    @ViewBuilder
    private var judgementContent: some View {
        VStack(alignment: .leading, spacing: spacing) {

            // How the app decides, drawn from the one ordered list of rungs in the repository
            // (R-54). It sits between *what the app can see* and *what it made of it*, which is
            // the order a person reads them in. It offers nothing to press either.
            CascadePrecedenceView()

            Divider()

            // What the app concluded about the person, and why (R-71). It sits at the foot of
            // this pane rather than behind a developer flag because it is a *trust* surface:
            // the capability table above says what the app can see, and this says what it made
            // of it. Neither offers anything to press.
            VerdictInspectorView(verdict: verdict)
        }
    }

    /// The store's location, as one string: what the person reads, and what the receipt reports.
    private var storePath: String { storeURL.path(percentEncoded: false) }
}

/// **The confirmation for deleting everything** (e07a, focus-6pr.3).
///
/// Rendered on its own for the interruption sheet's reason: `ImageRenderer` cannot rasterise a
/// `.sheet` presentation, so what a lane photographs is this content. The harmless button comes
/// first and carries Escape; the destructive one is a plain destructive button and is **not** the
/// default action — Return must never delete somebody's data.
public struct DeleteEverythingSheet: View {
    let confirm: () -> Void
    let cancel: () -> Void

    @Environment(\.appearanceTraits) private var traits
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    public init(confirm: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.confirm = confirm
        self.cancel = cancel
    }

    /// The strings the sheet draws, in order.
    nonisolated public static let contentKeys: [ShellStringKey] = [
        .settingsPrivacyDeleteConfirmHeading,
        .settingsPrivacyDeleteConfirmBody,
        .settingsPrivacyDeleteCancel,
        .settingsPrivacyDeleteConfirm
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ShellText(.settingsPrivacyDeleteConfirmHeading, role: .headline)
            ShellText(.settingsPrivacyDeleteConfirmBody, role: .callout)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: spacing / 2) {
                Spacer(minLength: 0)
                Button(action: cancel) {
                    ShellText(.settingsPrivacyDeleteCancel)
                }
                .keyboardShortcut(.cancelAction)
                Button(role: .destructive, action: confirm) {
                    ShellText(.settingsPrivacyDeleteConfirm)
                }
            }
        }
        .padding(spacing * 2)
        .frame(width: ShellSurfaceBounds.settingsWidth)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }
}

/// **The three portability buttons, which do not fit on one line** (F-144 follow-up, focus-1dd,
/// on the precedent of focus-0q4).
///
/// Measured at `accessibilityLarge` on the shipping pane: *Export My Data…*, *Export Settings…*
/// and *Import Settings…* in one `HStack` are handed a third of the 460-point pane each, and a
/// bordered button limits its label to one line — so all three read as an ellipsis with a word in
/// front of it. **A column is never narrower than its longest word**: that is the rule the
/// popover's rows were re-laid out under, and it is the same rule here.
///
/// `ViewThatFits` tries the row first, so at the shipping text size nothing moves and the pane a
/// person opens today is byte-identical. What gives way under pressure is the *arrangement*, never
/// the label: the buttons stack, each takes the full content width, and each reads in full.
struct PortabilityRow: View {
    let spacing: CGFloat
    let onAction: (PrivacySettingsAction) -> Void

    private var exportData: some View {
        Button { onAction(.exportData) } label: { ShellText(.settingsPrivacyExportData) }
    }

    private var exportSettings: some View {
        Button { onAction(.exportSettings) } label: { ShellText(.settingsPrivacyExportSettings) }
    }

    private var importSettings: some View {
        Button { onAction(.importSettings) } label: { ShellText(.settingsPrivacyImportSettings) }
    }

    var body: some View {
        // **No `Spacer` in the horizontal arm.** A `Spacer` makes the row's ideal width infinite,
        // so `ViewThatFits` measures it as never fitting and takes the column in every case —
        // measured: 84 points tall at the shipping text size, where the row is 24. The leading
        // alignment the spacer was there for belongs on the frame, where it costs the measurement
        // nothing.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing / 2) {
                exportData
                exportSettings
                importSettings
            }
            VStack(alignment: .leading, spacing: spacing / 2) {
                exportData
                exportSettings
                importSettings
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
