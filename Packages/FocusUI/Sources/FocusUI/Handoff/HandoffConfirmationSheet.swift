import FocusCore
import SwiftUI

/// The surface every `focus://` URL lands on, and the only route from one to a stored
/// priority (F-142, F-21).
///
/// **This sheet is the binding condition made visible.** The parser's only non-rejection
/// outcome is `.confirm`, and the only thing that turns a `.confirm` into a mutation is a
/// person pressing *Replace Priority* here. A script can put a sentence in front of someone;
/// it cannot put one in their store.
///
/// Three things it always shows:
///
/// * **What is there now, beside what is arriving.** Side by side while they fit, stacked when
///   they do not. A person deciding whether to give up their current commitment has to be able
///   to see it — a sheet that shows only the incoming sentence is asking them to accept
///   something in exchange for they-cannot-remember-what.
/// * **Every bound the parser applied.** A 5,000-character task that arrived as 500 says so; a
///   duplicate key that lost says so; unknown query items are named. Showing a truncated
///   sentence as though it were what the script sent is the quiet kind of lie.
/// * **A way out that changes nothing.** Cancel, and Escape.
///
/// Replace is `.destructive`-styled and is **not** the default action: Return does not replace
/// the user's priority. Cancel is.
///
/// A `focus://context` handoff uses the same sheet in a second mode: it names the current
/// priority, lists the apps, sites and keywords that would be added to it, and offers Add
/// beside Cancel. Cancel stays the default there too — adding is quieter than replacing, but a
/// script still does not get to change the desk without a person agreeing.
public struct HandoffConfirmationSheet: View {
    public let request: HandoffRequest
    /// The displays this sheet bounds itself against; `nil` for the live ones. Injectable for
    /// the reason every other surface's is: no lane can hand a sheet a 13-inch laptop otherwise.
    private let screens: ShellScreens
    /// What is in the store right now, or `nil` if nothing is.
    public let current: PrioritySnapshot?
    public let replace: () -> Void
    public let cancel: () -> Void

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @FocusState private var focus: FocusField?
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    public init(
        request: HandoffRequest,
        current: PrioritySnapshot?,
        replace: @escaping () -> Void,
        cancel: @escaping () -> Void,
        screens: ShellScreens = nil
    ) {
        self.request = request
        self.current = current
        self.replace = replace
        self.cancel = cancel
        self.screens = screens
    }

    /// **The sheet, bounded** (focus-nu6).
    public var body: some View {
        content.boundedSheet(width: ShellSurfaceBounds.handoffSheetWidth, screens: screens)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ShellText(isContext ? .handoffContextHeading : .handoffHeading, role: .title3)
                .fontWeight(.semibold)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            ShellText(isContext ? .handoffContextExplanation : .handoffExplanation, role: .callout)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: spacing * 2) {
                    currentColumn
                    if isContext { contextColumn } else { incomingColumn }
                }
                VStack(alignment: .leading, spacing: spacing) {
                    currentColumn
                    if isContext { contextColumn } else { incomingColumn }
                }
            }

            if !request.flags.isEmpty {
                flagList
            }

            HStack(spacing: spacing) {
                Spacer(minLength: 0)

                Button(action: cancel) {
                    ShellText(.handoffActionCancel)
                }
                .shellHelp(.handoffActionCancelHelp)
                // Cancel is the default action, deliberately. Return must never be the key
                // that gives away the thing the user was working on.
                .keyboardShortcut(.defaultAction)
                .focused($focus, equals: .handoffCancel)

                if isContext {
                    // Same focus slot as Replace: the sheet still has exactly two stops.
                    Button(action: replace) {
                        ShellText(.handoffContextActionAdd)
                    }
                    .shellHelp(.handoffContextActionAddHelp)
                    .buttonStyle(.borderedProminent)
                    .focused($focus, equals: .handoffReplace)
                } else {
                    Button(action: replace) {
                        ShellText(.handoffActionReplace)
                    }
                    .shellHelp(.handoffActionReplaceHelp)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(nsColor: .systemRed))
                    .focused($focus, equals: .handoffReplace)
                }
            }
        }
        .dialogInset()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Palette.windowBackground(for: traits))
        .defaultFocus($focus, .handoffCancel)
        .onExitCommand(perform: cancel)
    }

    // MARK: - The two sides

    private var isContext: Bool { request.verb == .context }

    private var currentColumn: some View {
        column(
            titleKey: .handoffCurrentLabel,
            intent: current?.intent,
            doneWhen: current?.doneWhen,
            emptyKey: .handoffCurrentNone
        )
    }

    private var incomingColumn: some View {
        VStack(alignment: .leading, spacing: spacing / 2) {
            column(
                titleKey: .handoffIncomingLabel,
                intent: request.task,
                doneWhen: request.doneWhen,
                emptyKey: nil
            )
            if !request.context.isEmpty {
                contextList(titleKey: .handoffIncomingContextLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var contextColumn: some View {
        contextList(titleKey: .handoffContextLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The items a script sent, one line each. Values are data, drawn verbatim.
    private func contextList(titleKey: ShellStringKey) -> some View {
        VStack(alignment: .leading, spacing: spacing / 3) {
            ShellText(titleKey, role: .caption)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            ForEach(Array(request.context.enumerated()), id: \.offset) { _, item in
                Label {
                    Text(verbatim: item.value)
                        .font(DesignTokens.font(.callout, scale: textScale))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: item.kind.symbolName)
                }
            }
        }
    }

    @ViewBuilder
    private func column(
        titleKey: ShellStringKey,
        intent: String?,
        doneWhen: String?,
        emptyKey: ShellStringKey?
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing / 3) {
            ShellText(titleKey, role: .caption)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))

            if let intent, !intent.isEmpty {
                // Both sentences are data — one the user's, one a script's — and neither is
                // ever routed through a String Catalog or abbreviated.
                Text(verbatim: intent)
                    .font(DesignTokens.font(.body, scale: textScale))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                if let doneWhen, !doneWhen.isEmpty {
                    Text(verbatim: doneWhen)
                        .font(DesignTokens.font(.caption, scale: textScale))
                        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let emptyKey {
                ShellText(emptyKey, role: .body)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - What the parser had to do to it

    private var flagList: some View {
        VStack(alignment: .leading, spacing: spacing / 3) {
            ForEach(Array(request.flags.enumerated()), id: \.offset) { _, flag in
                Label {
                    flagText(flag)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            }
        }
    }

    /// One disclosure line.
    ///
    /// Every one is a catalog entry whose only argument is material that came in with the URL
    /// — a length, a list of key names. Nothing is composed at runtime.
    @ViewBuilder
    private func flagText(_ flag: HandoffFlag) -> some View {
        switch flag {
        case .taskTruncated(let originalLength):
            ShellText(
                .handoffFlagTaskTruncated,
                role: .caption,
                argument: originalLength.formatted()
            )
        case .doneWhenTruncated(let originalLength):
            ShellText(
                .handoffFlagDoneWhenTruncated,
                role: .caption,
                argument: originalLength.formatted()
            )
        case .controlCharactersStripped:
            ShellText(.handoffFlagControlCharacters, role: .caption)
        case .duplicateKeysIgnored(let keys):
            ShellText(
                .handoffFlagDuplicateKeys,
                role: .caption,
                argument: keys.formatted(.list(type: .and))
            )
        case .unknownQueryItems(let keys):
            ShellText(
                .handoffFlagUnknownItems,
                role: .caption,
                argument: keys.formatted(.list(type: .and))
            )
        case .contextItemsIgnored(let count):
            ShellText(
                .handoffFlagContextIgnored,
                role: .caption,
                argument: count.formatted()
            )
        }
    }
}
