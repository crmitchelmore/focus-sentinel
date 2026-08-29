import FocusCore
import SwiftUI

/// The daily priority ritual (F-19).
///
/// **A banner, not a modal.** A modal on launch is a toll booth: it stops a person doing the
/// thing they opened the app to do, in order to ask them what they were going to do. This sits
/// above the hero, asks once, and can be dismissed with one click.
///
/// **It asks once per local day.** Answering *and* dismissing both write the day key, so it
/// never nags — and the key is computed from an injected calendar, not the runner's, which is
/// what makes "once per local day" the same statement in London and in Auckland.
///
/// **No notification authorisation is requested for this feature, ever** (Court). The ritual
/// must not depend on a grant, so it lives inside the window the user already opened.
public struct RitualBanner: View {
    /// Answer it: put focus in the capture field so the sentence can be typed straight away.
    public let answer: () -> Void
    /// Dismiss it. Writes the day key too — being asked twice is the failure mode.
    public let dismiss: () -> Void

    @Environment(\.appearanceTraits) private var traits
    @FocusState.Binding var focus: FocusField?
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    public init(
        answer: @escaping () -> Void,
        dismiss: @escaping () -> Void,
        focus: FocusState<FocusField?>.Binding
    ) {
        self.answer = answer
        self.dismiss = dismiss
        self._focus = focus
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            Label {
                ShellText(.priorityRitualMessage, role: .callout)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "sunrise")
            }

            Spacer(minLength: spacing)

            Button(action: answer) {
                ShellText(.priorityRitualActionSet, role: .callout)
            }

            Button(action: dismiss) {
                ShellText(.priorityRitualActionDismiss, role: .callout)
            }
            .focused($focus, equals: .cockpitRitualDismiss)
        }
        .padding(spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
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
    }
}
