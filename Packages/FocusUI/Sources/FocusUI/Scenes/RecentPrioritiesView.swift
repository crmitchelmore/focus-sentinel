import FocusCore
import SwiftUI

/// Previous commitments, newest first (F-15).
///
/// **This is history, not a backlog.** There is no queue, no auto-promotion and no second
/// commitment: the only thing a row can do is *become* the current priority. That is what
/// keeps F-13 and F-20 parked rather than half-shipped.
///
/// "Work on this again" re-points the store's single pointer row at the existing task and
/// clears its completion — it does not copy. The stored context pack and rules therefore come
/// back with it by construction, which is a property of the data model rather than a feature
/// this view has to implement.
///
/// The whole list is `.callout` and smaller. Nothing here competes with the hero.
public struct RecentPrioritiesView: View {
    public let rows: [RecentPriority]
    /// Make one of them current again.
    public let activate: ((UUID) -> Void)?

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 8

    public init(rows: [RecentPriority], activate: ((UUID) -> Void)? = nil) {
        self.rows = rows
        self.activate = activate
    }

    public var body: some View {
        // An empty history is not worth a heading and an empty box. A person with no previous
        // commitments should see no evidence that this section exists.
        Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: spacing) {
                    CompanionSectionHeading(key: .priorityRecentHeading, symbol: "clock.arrow.circlepath")
                        .foregroundStyle(DesignTokens.Palette.role(.spruce, for: traits))

                    ForEach(rows) { row in
                        entry(row)
                            .padding(.vertical, spacing)
                        if row.id != rows.last?.id { Divider() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func entry(_ row: RecentPriority) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            Image(systemName: row.isActive ? "scope" : (row.completedAt != nil ? "checkmark.circle" : "clock"))
                .foregroundStyle(DesignTokens.Palette.role(.spruce, for: traits))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: spacing / 4) {
                // The user's own sentence, verbatim and free to wrap. A previous commitment is
                // no more abbreviable than the current one.
                Text(verbatim: row.intent)
                    .font(DesignTokens.font(.callout, scale: textScale))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                if let doneWhen = row.doneWhen, !doneWhen.isEmpty {
                    Text(verbatim: doneWhen)
                        .font(DesignTokens.font(.caption, scale: textScale))
                        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: spacing) {
                    if row.contextItemCount > 0 {
                        Label {
                            // A count is a number, not prose.
                            Text(verbatim: row.contextItemCount.formatted())
                                .font(DesignTokens.font(.caption, scale: textScale))
                        } icon: {
                            Image(systemName: "paperclip")
                        }
                        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                        .accessibilityLabel(Text(ShellStrings.resource(.priorityRecentContextItems)))
                    }

                    if row.completedAt != nil {
                        Label {
                            ShellText(.priorityRecentCompleted, role: .caption)
                        } icon: {
                            Image(systemName: "checkmark.circle")
                        }
                        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    }
                }
            }

            Spacer(minLength: spacing)

            if !row.isActive {
                Button {
                    activate?(row.id)
                } label: {
                    ShellText(.priorityRecentActionAgain, role: .callout)
                }
                .disabled(activate == nil)
                // Tooltip from the catalog (focus-8ski).
                .shellHelp(.priorityRecentActionAgainHelp)
            }
        }
    }
}
