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
public struct PrivacySettingsView: View {
    private let storeURL: URL
    private let summary: SensingSummary
    private let capabilities: CapabilityMatrix
    private let verdict: VerdictSnapshot?
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
        screens: ShellScreens = nil
    ) {
        self.storeURL = storeURL
        self.summary = summary
        self.capabilities = capabilities
        self.verdict = verdict
        self.screens = screens
    }

    /// The strings this pane draws. Non-empty by construction, and asserted so: a Settings
    /// tab that renders nothing is a defect, not a design.
    nonisolated public static let contentKeys: [ShellStringKey] =
        [
            .settingsPrivacyStatement,
            .settingsPrivacyStoreLabel,
            .settingsPrivacyReveal,
            .sensingHeading,
            .sensingLimitationScreenSharing,
            .capabilityHeading,
            .capabilityExplanation
        ] + VerdictInspectorView.contentKeys

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
                DesignTokens.material(for: traits),
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
