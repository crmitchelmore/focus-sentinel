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
            // Tooltips from the catalog (focus-8ski).
            .shellHelp(.priorityRitualActionSetHelp)

            Button(action: dismiss) {
                ShellText(.priorityRitualActionDismiss, role: .callout)
            }
            .focused($focus, equals: .cockpitRitualDismiss)
            .shellHelp(.priorityRitualActionDismissHelp)
        }
        // **A quiet inset strip, not a raised card** (focus-w41, direction §5.1).
        //
        // It was a material surface with a full stroked border — a floating object above the
        // priority, drawn with more weight than the priority itself. What it actually is, is a
        // strip: a band across the top of the column asking one question once a day. So it takes
        // Inlay, the palette's quiet inset ground, at a small radius, and its outline is drawn
        // only where an outline is what the person asked for.
        //
        // The border is not simply deleted. Under Increase Contrast, Inlay sits close to Bench by
        // construction — the two grounds both move away from the ink — so the fill alone would
        // stop saying "strip" at exactly the setting where structure matters most. `Emphasis`
        // already answers that question everywhere else in the shell, and it answers it here:
        // the outline appears when it is asked for, at the width it is asked for.
        .padding(.horizontal, spacing)
        .padding(.vertical, spacing * 0.75)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            DesignTokens.Palette.role(.inlay, for: traits),
            in: RoundedRectangle(cornerRadius: spacing / 3, style: .continuous)
        )
        .overlay {
            let emphasis = DesignTokens.emphasis(for: traits)
            if emphasis.promotesSecondaryText {
                RoundedRectangle(cornerRadius: spacing / 3, style: .continuous)
                    .strokeBorder(
                        DesignTokens.Palette.role(.mist, for: traits)
                            .opacity(emphasis.outlineOpacity),
                        lineWidth: emphasis.borderWidth
                    )
            }
        }
    }
}
