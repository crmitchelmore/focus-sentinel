import AppKit
import FocusCore
import SwiftUI

/// The Privacy settings pane.
///
/// It says one true thing plainly and then proves it: this is where the data lives, here is
/// the button that shows you the file. Nothing here is a promise about a future feature —
/// deleting everything is e07's surface and the full capability disclosure is e10's, and
/// neither is announced here.
public struct PrivacySettingsView: View {
    private let storeURL: URL

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @FocusState private var focus: FocusField?
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    public init(storeURL: URL = FocusStore.applicationSupportURL) {
        self.storeURL = storeURL
    }

    /// The strings this pane draws. Non-empty by construction, and asserted so: a Settings
    /// tab that renders nothing is a defect, not a design.
    nonisolated public static let contentKeys: [ShellStringKey] = [
        .settingsPrivacyStatement,
        .settingsPrivacyStoreLabel,
        .settingsPrivacyReveal
    ]

    public var body: some View {
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

            Spacer(minLength: 0)
        }
        .padding(spacing * 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .defaultFocus($focus, .privacyRevealStore)
    }
}
