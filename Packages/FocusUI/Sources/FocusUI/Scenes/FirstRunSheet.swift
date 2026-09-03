import FocusCore
import SwiftUI

/// **The one screen that says what this app looks at, before it has looked at anything**
/// (focus-odz.7).
///
/// ## What it is for
///
/// A first launch installed a status item and started recording activations with nothing on
/// screen saying so. Every claim the product rests on — it reads the frontmost application and
/// nothing else, it asks for no permissions, everything stays on this Mac — was true, written
/// down in `README.md`, and reachable only by opening Settings and choosing the Privacy tab. An
/// app that observes without saying so is asking to be trusted on the strength of a file nobody
/// reads.
///
/// ## What is on it, and why each line is there
///
/// Four sentences and a path, and each answers a question somebody would otherwise have to guess
/// at:
///
/// * **what it observes** — the frontmost application, and a browser's host name where one is
///   offered without a permission grant;
/// * **what it never observes** — window titles, addresses, file paths, document names, anything
///   typed. The list is exhaustive on purpose: a vaguer sentence would be a promise nobody could
///   check against the code, and every item on it is a symbol `check-boundaries.sh` proves absent
///   from the shipped binary;
/// * **that it asks for no permissions**, which is the zero-grant doctrine in one line;
/// * **where the store lives** — the same path Settings ▸ Privacy draws, so the two cannot
///   disagree about it.
///
/// ## Shown once, and never on the nudge path
///
/// It is a sheet on the cockpit, presented from `CockpitState`, which means it can only ever
/// appear over the window a person opened. Nothing on the nudge path can raise it: a panel that
/// interrupted somebody to explain itself would be the opposite of what U-1 and F-81 are for.
///
/// One button, and no `onExitCommand`. Escape not dismissing it is `StoreUnavailableSheet`'s rule
/// and its reason: this is shown exactly once, and somebody who pressed Escape has not read it.
public struct FirstRunSheet: View {
    /// Where this app's store lives — the same path the Privacy pane draws.
    public let storeLocation: String
    /// What the button does. The one caller is the cockpit, which routes it to the composition
    /// root's own verb.
    public let dismiss: () -> Void
    /// The displays this sheet bounds itself against; `nil` for the live ones. Injectable for
    /// `StoreUnavailableSheet`'s reason: no lane can hand a sheet a 13-inch laptop otherwise.
    private let screens: ShellScreens

    @Environment(\.appearanceTraits) private var traits
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    public init(
        storeLocation: String,
        dismiss: @escaping () -> Void,
        screens: ShellScreens = nil
    ) {
        self.storeLocation = storeLocation
        self.dismiss = dismiss
        self.screens = screens
    }

    public var body: some View {
        content.boundedSheet(width: ShellSurfaceBounds.handoffSheetWidth, screens: screens)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Label {
                ShellText(.firstRunTitle, role: .title3)
                    .fontWeight(.semibold)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "eye")
            }

            paragraph(.firstRunObserves)
            paragraph(.firstRunNever)
            paragraph(.firstRunPermissions)

            ShellText(.firstRunStoreLabel, role: .callout)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            // **The path, drawn as a value and never as prose** — the same decision the Privacy
            // pane and the store-failure sheet make, and it is the same path. Monospaced because
            // it is a path, and selectable because somebody being told where their data lives
            // will want to go and look at it.
            Text(verbatim: storeLocation)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            HStack(spacing: spacing) {
                Spacer(minLength: 0)
                Button(action: dismiss) {
                    ShellText(.firstRunDismiss)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(spacing * 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Palette.windowBackground(for: traits))
        // **No `onExitCommand`**, for `StoreUnavailableSheet`'s reason: this is shown exactly
        // once, and somebody who pressed Escape has not read it.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(ShellStrings.resource(.firstRunTitle)))
    }

    private func paragraph(_ key: ShellStringKey) -> some View {
        ShellText(key, role: .callout)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }
}
