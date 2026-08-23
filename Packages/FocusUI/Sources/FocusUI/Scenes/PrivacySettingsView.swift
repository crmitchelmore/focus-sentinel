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
/// Sharing produces only synthetic input events, so the hardware idle source will consider them
/// away. That is a real consequence of choosing the more pessimistic of the two idle sources
/// (R-36), and the honest place for it is the pane about what the app can and cannot see.
public struct PrivacySettingsView: View {
    private let storeURL: URL
    private let summary: SensingSummary
    private let capabilities: CapabilityMatrix
    private let verdict: VerdictSnapshot?

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @FocusState private var focus: FocusField?
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    public init(
        storeURL: URL = FocusStore.applicationSupportURL,
        summary: SensingSummary = .inactive,
        capabilities: CapabilityMatrix = CapabilityMatrix(),
        verdict: VerdictSnapshot? = nil
    ) {
        self.storeURL = storeURL
        self.summary = summary
        self.capabilities = capabilities
        self.verdict = verdict
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

    public var body: some View {
        content
            .defaultFocus($focus, .privacyRevealStore)
    }

    /// Laid out as one column with no scroll view, and that is a rendering decision with a
    /// measurement behind it: a `ScrollView` reports no intrinsic height, so under
    /// `ImageRenderer` this pane rasterised as a blank 1040×2699 rectangle with 1 040 ink pixels
    /// — the committed baseline would have been a picture of nothing. Measured here, on this
    /// machine, the first time the capability table was put inside one. The Settings window
    /// sizes itself to the tab's content instead.
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
                Text(verbatim: storeURL.path(percentEncoded: false))
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
                in: RoundedRectangle(cornerRadius: spacing / 2, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: spacing / 2, style: .continuous)
                    .strokeBorder(
                        DesignTokens.Palette.separator
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
    }
}
