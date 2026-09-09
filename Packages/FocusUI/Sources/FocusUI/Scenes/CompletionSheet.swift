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
    /// The displays this sheet bounds itself against; `nil` for the live ones. Injectable for
    /// the reason every other surface's is: no lane can hand a sheet a 13-inch laptop otherwise.
    private let screens: ShellScreens
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
        cancel: @escaping () -> Void,
        screens: ShellScreens = nil
    ) {
        self.intent = intent
        self.complete = complete
        self.cancel = cancel
        self.screens = screens
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            CompanionSectionHeading(key: .priorityCompleteHeading, symbol: "checkmark.seal")
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
                    let reflection = Self.reflection(shipped: shipped, restartPoint: restartPoint)
                    complete(reflection.shipped, reflection.restartPoint)
                } label: {
                    ShellText(.priorityCompleteActionConfirm)
                }
                .buttonStyle(CompanionButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
                .focused($focus, equals: .completionConfirm)
                // The promise, made structural. The button consults one function, that
                // function is always true, and `CockpitActionsTests` holds it to that — so a
                // later "just require what shipped" has to change a documented rule and fail a
                // test, rather than adding a condition here that nobody notices.
                .disabled(!Self.isCompleteEnabled(shipped: shipped, restartPoint: restartPoint))
            }
        }
        .padding(spacing * 2)
        .buttonStyle(CompanionButtonStyle())
        .boundedSheet(width: ShellSurfaceBounds.completionSheetWidth, screens: screens)
        .background(DesignTokens.Palette.windowBackground(for: traits))
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
            .textFieldStyle(.plain)
            .padding(10)
            .background(DesignTokens.Palette.role(.inlay, for: traits), in: RoundedRectangle(cornerRadius: 10))
            .focused($focus, equals: identity)
            .accessibilityLabel(Text(ShellStrings.resource(label)))
        }
    }

    // MARK: - The two rules this sheet keeps

    /// Whether Complete may be pressed. **Always.**
    ///
    /// Both fields are reflection, and reflection is offered rather than extracted (F-22,
    /// acceptance criterion 21): finishing is a fact about the work, not a payment the app
    /// collects for letting you finish. The parameters are here so that a future condition
    /// would have to be written against the actual field contents — and would fail the test
    /// that asserts this is true for every combination of empty, blank and filled.
    static func isCompleteEnabled(shipped: String, restartPoint: String) -> Bool {
        true
    }

    /// What the two fields mean to the store.
    ///
    /// An empty field is an absent answer, not an empty string. Storing `""` would make a row
    /// that says "the user answered nothing" indistinguishable from one that says "the user
    /// answered with nothing".
    static func reflection(
        shipped: String,
        restartPoint: String
    ) -> (shipped: String?, restartPoint: String?) {
        (trimmed(shipped), trimmed(restartPoint))
    }

    private static func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
