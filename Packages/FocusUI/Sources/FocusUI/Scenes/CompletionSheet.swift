import FocusCore
import SwiftUI

/// Finishing the one thing (F-22).
///
/// Two optional fields — what shipped, and where to pick it up next time — and a Complete
/// button that **is enabled with both of them empty**. Reflection is offered, never extracted:
/// a sheet that will not let you finish until you have written something teaches people to
/// type a full stop and move on.
///
/// Nothing here summarises, infers or asks a model anything. The two fields are local text on
/// the task, and that is all they ever are.
public struct CompletionSheet: View {
    /// The sentence being completed, shown so the sheet is about something rather than
    /// floating free of it.
    public let intent: String
    /// Complete: what shipped, where to restart. Either may be `nil`.
    public let complete: (String?, String?) -> Void
    public let cancel: () -> Void

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @FocusState private var focus: FocusField?
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    @State private var shipped: String = ""
    @State private var restartPoint: String = ""

    public init(
        intent: String,
        complete: @escaping (String?, String?) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.intent = intent
        self.complete = complete
        self.cancel = cancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ShellText(.priorityCompleteHeading, role: .title3)
                .fontWeight(.semibold)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            // The user's own sentence, verbatim.
            Text(verbatim: intent)
                .font(DesignTokens.font(.body, scale: textScale))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            field(
                label: .priorityCompleteShippedLabel,
                prompt: .priorityCompleteShippedPrompt,
                text: $shipped,
                identity: .completionShipped
            )

            field(
                label: .priorityCompleteRestartLabel,
                prompt: .priorityCompleteRestartPrompt,
                text: $restartPoint,
                identity: .completionRestartPoint
            )

            ShellText(.priorityCompleteNote, role: .caption)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: spacing) {
                Spacer(minLength: 0)

                Button(action: cancel) {
                    ShellText(.priorityCompleteActionCancel)
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    complete(trimmed(shipped), trimmed(restartPoint))
                } label: {
                    ShellText(.priorityCompleteActionConfirm)
                }
                .keyboardShortcut(.defaultAction)
                .focused($focus, equals: .completionConfirm)
            }
        }
        .padding(spacing * 2)
        .frame(minWidth: 420, alignment: .leading)
        .background(DesignTokens.Palette.windowBackground)
        .defaultFocus($focus, .completionShipped)
    }

    private func field(
        label: ShellStringKey,
        prompt: ShellStringKey,
        text: Binding<String>,
        identity: FocusField
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing / 3) {
            ShellText(label, role: .caption)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))

            TextField(text: text, prompt: Text(ShellStrings.resource(prompt))) {
                ShellText(label)
            }
            .labelsHidden()
            .font(DesignTokens.font(.body, scale: textScale))
            .focused($focus, equals: identity)
            .accessibilityLabel(Text(ShellStrings.resource(label)))
        }
    }

    /// An empty field is an absent answer, not an empty string. Storing `""` would make a row
    /// that says "the user answered nothing" indistinguishable from one that says "the user
    /// answered with nothing".
    private func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
