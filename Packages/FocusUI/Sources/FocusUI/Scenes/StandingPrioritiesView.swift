import FocusCore
import SwiftUI

/// The person's standing priorities: one main and up to two secondaries, set by a planning tool
/// through a confirmed `focus://priorities` handoff.
///
/// **A shortlist, not a backlog** (F-15). Three rows at most, and the only thing a row can do
/// is *become* the current priority — the same "work on this again" the history offers, so the
/// task's context pack comes back with it. Nothing is queued and nothing promotes itself.
///
/// Draws nothing when there are none, so a person who has never set them sees no section.
public struct StandingPrioritiesView: View {
    public let rows: [StandingPriority]
    /// Make one of them current.
    public let activate: ((UUID) -> Void)?

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 8

    public init(rows: [StandingPriority], activate: ((UUID) -> Void)? = nil) {
        self.rows = rows
        self.activate = activate
    }

    public var body: some View {
        Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: spacing) {
                    CompanionSectionHeading(key: .priorityStandingHeading, symbol: "star")
                        .foregroundStyle(DesignTokens.Palette.role(.spruce, for: traits))

                    ForEach(rows) { row in
                        entry(row)
                            .padding(.vertical, spacing / 2)
                        if row.id != rows.last?.id { Divider() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func entry(_ standing: StandingPriority) -> some View {
        let row = standing.row
        return HStack(alignment: .firstTextBaseline, spacing: spacing) {
            Image(systemName: standing.isPrimary ? "star.fill" : "star")
                .foregroundStyle(DesignTokens.Palette.role(.spruce, for: traits))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: spacing / 4) {
                ShellText(
                    standing.isPrimary ? .priorityStandingPrimary : .priorityStandingSecondary,
                    role: .caption
                )
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))

                // The planning tool's sentence for it, verbatim and free to wrap.
                Text(verbatim: row.intent)
                    .font(DesignTokens.font(.callout, scale: textScale))
                    .fontWeight(standing.isPrimary ? .semibold : .regular)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                if let doneWhen = row.doneWhen, !doneWhen.isEmpty {
                    Text(verbatim: doneWhen)
                        .font(DesignTokens.font(.caption, scale: textScale))
                        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: spacing)

            if row.isActive {
                ShellText(.priorityStandingCurrent, role: .caption)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            } else {
                Button {
                    activate?(row.id)
                } label: {
                    ShellText(.priorityStandingActionFocus, role: .callout)
                }
                .disabled(activate == nil)
                .shellHelp(.priorityStandingActionFocusHelp)
            }
        }
    }
}
