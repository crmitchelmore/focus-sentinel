import SwiftUI

/// One line of the Keyboard Shortcuts reference.
///
/// A value, and public, because the test lane asserts that the rendered rows are exactly the
/// registry's actions in registry order. Comparing values is how "the help window and the
/// menu bar cannot drift" is proved rather than asserted.
public struct ShortcutRow: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let titleKey: ShellStringKey
    /// The shortcut as it is drawn — `⌘W` — or `nil` for an action with no key equivalent.
    public let glyphs: String?

    public init(action: ShellAction) {
        self.id = action.id
        self.titleKey = action.titleKey
        self.glyphs = action.shortcut?.glyphs
    }
}

/// The rows of one menu.
public struct ShortcutGroup: Sendable, Equatable, Hashable, Identifiable {
    public let placement: MenuPlacement
    public let headingKey: ShellStringKey
    public let rows: [ShortcutRow]

    public var id: String { placement.rawValue }
}

/// The Help menu's real destination.
///
/// This window exists because SwiftUI's default Help item opens a help book that does not
/// exist — a menu item leading nowhere is a defect, and the honest fix is a destination with
/// real content rather than a removed menu item.
///
/// Its content is rendered from the **same** `CommandRegistry` that builds the menu bar. One
/// table, one test, two consumers: a shortcut cannot appear in the menu bar and be missing
/// here, and nothing can be listed here that is not really bound.
public struct ShortcutsHelpView: View {
    private let registry: CommandRegistry

    @Environment(\.appearanceTraits) private var traits
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    public init(registry: CommandRegistry = .shell) {
        self.registry = registry
    }

    /// The groups the window renders, in menu-bar order.
    ///
    /// A placement with no shell action of its own never becomes an empty heading, and a
    /// placement the registry populates but has no heading for is dropped rather than drawn
    /// nameless — the registry test requires every populated placement to be named, so that
    /// case is a test failure, not a silent omission.
    nonisolated public static func groups(for registry: CommandRegistry) -> [ShortcutGroup] {
        registry.populatedPlacements.compactMap { placement in
            guard let headingKey = placement.headingKey else { return nil }
            return ShortcutGroup(
                placement: placement,
                headingKey: headingKey,
                rows: registry.actions(in: placement).map(ShortcutRow.init)
            )
        }
    }

    public var body: some View {
        let groups = Self.groups(for: registry)

        return ScrollView {
            VStack(alignment: .leading, spacing: spacing * 2) {
                VStack(alignment: .leading, spacing: spacing / 2) {
                    ShellText(.helpHeading)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    ShellText(.helpIntroduction)
                        .font(.callout)
                        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: spacing / 2) {
                        ShellText(group.headingKey)
                            .font(.headline)
                            .lineLimit(nil)

                        Grid(
                            alignment: .leading,
                            horizontalSpacing: spacing * 2,
                            verticalSpacing: spacing / 2
                        ) {
                            GridRow {
                                ShellText(.helpColumnAction)
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                                ShellText(.helpColumnShortcut)
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                            }

                            ForEach(group.rows) { row in
                                GridRow {
                                    ShellText(ShellStrings.resource(row.titleKey))
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                    // The glyph string is the shortcut itself, not prose:
                                    // `verbatim` because it must never be sent through a
                                    // catalog, and `monospaced` so ⌘, ⌥ and ⇧ line up down
                                    // the column.
                                    Text(verbatim: row.glyphs ?? "—")
                                        .monospaced()
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(spacing * 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 360, minHeight: 240)
        .background(DesignTokens.Palette.windowBackground)
    }
}
