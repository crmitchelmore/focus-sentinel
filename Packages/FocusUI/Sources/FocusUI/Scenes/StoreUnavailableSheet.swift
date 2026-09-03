import FocusCore
import SwiftUI

/// **The sheet that says a day's work will not survive quitting** (focus-tzj.4, F-115).
///
/// ## What it is for
///
/// When the on-disk store will not open, `AppComposition` falls back to an **in-memory**
/// container so the shell still runs and can report the failure. What it reported was one
/// footnote at the bottom of the window, drawn from a boolean that a *transient write failure*
/// was OR-ed into — so the sentence a person saw when their store was gone was the same one they
/// saw when a single save had been refused, in the same eight-point grey, and they went on
/// capturing priorities into memory all day.
///
/// The three things somebody in that state has to be told, and they are the three paragraphs
/// below: **what happened**, **where the store is** so they can go and look at it, and **what it
/// costs** — that nothing captured from here survives quitting.
///
/// ## Why it has a button rather than a dismiss
///
/// `PriorityHost` refuses to capture a new priority while `CockpitState.capturingIsRefused`, and
/// that reading is `!storeOpened && !storeFailureAcknowledged` — so the button is not an
/// acknowledgement in the decorative sense. It is the thing that lifts the refusal. The app does
/// not decide for the person that they must not work; it declines to take a commitment it cannot
/// keep until it has said so and been answered.
///
/// The button's own words say what pressing it means — *"Continue without saving"* — rather than
/// *OK*, for the reason every destructive affordance in this programme is named for its effect.
public struct StoreUnavailableSheet: View {
    /// Where the store the app tried to open lives.
    public let storeLocation: String
    /// What the button does. The one caller is the cockpit, which routes it to
    /// `PriorityActing.acknowledgeStoreFailure()`.
    public let acknowledge: () -> Void
    /// The displays this sheet bounds itself against; `nil` for the live ones. Injectable for
    /// `HandoffConfirmationSheet`'s reason: no lane can hand a sheet a 13-inch laptop otherwise.
    private let screens: ShellScreens

    @Environment(\.appearanceTraits) private var traits
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    public init(
        storeLocation: String,
        acknowledge: @escaping () -> Void,
        screens: ShellScreens = nil
    ) {
        self.storeLocation = storeLocation
        self.acknowledge = acknowledge
        self.screens = screens
    }

    public var body: some View {
        content.boundedSheet(width: ShellSurfaceBounds.handoffSheetWidth, screens: screens)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Label {
                ShellText(.cockpitStoreSheetTitle, role: .title3)
                    .fontWeight(.semibold)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(nsColor: .systemOrange))
            }

            ShellText(.cockpitStoreSheetWhatHappened, role: .callout)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            // **The path, drawn as a value and never as prose.** The sentence around it is
            // authored, translated text from the catalog with one argument; the argument is a
            // file path this machine produced. Monospaced because it is a path, and selectable
            // because somebody told their store is unreachable will want to go and look at it.
            Text(ShellStrings.string(.cockpitStoreSheetLocation, argument: storeLocation))
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            ShellText(.cockpitStoreSheetConsequence, role: .callout)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: spacing) {
                Spacer(minLength: 0)
                Button(action: acknowledge) {
                    ShellText(.cockpitStoreSheetAcknowledge)
                }
                .buttonStyle(.borderedProminent)
                // The only action, and therefore the default one — but note what the default is
                // doing here: Return means "I have read this", never "throw my work away".
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(spacing * 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Palette.windowBackground(for: traits))
        // **No `onExitCommand`.** Escape must not dismiss this: the dismissal is what lifts the
        // capture refusal, and a person who pressed Escape has not been told anything.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(ShellStrings.resource(.cockpitStoreSheetTitle)))
    }
}
