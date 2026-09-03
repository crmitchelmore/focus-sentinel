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
        }
    }

    /// Every action the pane can produce, one per value it can produce it with. The self-check
    /// folds this to `verb`; the unit lane folds it to check nothing here is unreachable.
    public static var allDeclared: [PrivacySettingsAction] {
        [.deleteEverything] + RetentionWindow.ordered.map(PrivacySettingsAction.setRetentionWindow)
    }

    /// The vocabulary the self-check publishes, in the order the pane draws it.
    public static let vocabulary: [String] = ["deleteEverything", "setRetentionWindow"]
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
        screens: ShellScreens = nil,
        onAction: @escaping (PrivacySettingsAction) -> Void = { _ in }
    ) {
        self.storeURL = storeURL
        self.summary = summary
        self.capabilities = capabilities
        self.verdict = verdict
        self.retention = retention
        self.screens = screens
        self.onAction = onAction
    }

    /// The strings this pane draws. Non-empty by construction, and asserted so: a Settings
    /// tab that renders nothing is a defect, not a design.
    nonisolated public static let contentKeys: [ShellStringKey] =
        [
            .settingsPrivacyStatement,
            .settingsPrivacyStoreLabel,
            .settingsPrivacyReveal,
            .settingsPrivacyRetentionHeading,
            .settingsPrivacyRetentionExplanation,
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

    private var content: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ShellText(.settingsPrivacyStatement)
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
                HStack(spacing: spacing / 2) {
                    ForEach(RetentionWindow.ordered, id: \.self) { window in
                        Button {
                            onAction(.setRetentionWindow(window))
                        } label: {
                            ShellText(window.titleKey)
                        }
                        .buttonStyle(.bordered)
                        // The same tint the timebox presets use for the same job — and, because
                        // a tint is a colour, the accessibility trait beside it carries the
                        // selection where colour cannot (F-146, F-144).
                        .tint(window == retention ? DesignTokens.Palette.accent(for: traits) : nil)
                        .accessibilityAddTraits(window == retention ? [.isSelected] : [])
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(ShellStrings.resource(.settingsPrivacyRetentionHeading))
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

            Divider()

            // What is being watched right now, with its working shown — including the lines
            // whose answer is "no". A surface that only reported the interesting half would be
            // showing half of it.
            VStack(alignment: .leading, spacing: spacing / 2) {
                ShellText(.sensingHeading, role: .headline)
                SensingStatusView(summary: summary, showsDetail: true)

                ShellText(.sensingLimitationScreenSharing, role: .footnote)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            CapabilityMatrixView(capabilities: capabilities)

            Divider()

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
