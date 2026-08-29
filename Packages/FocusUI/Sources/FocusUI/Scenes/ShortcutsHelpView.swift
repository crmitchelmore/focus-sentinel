import FocusCore
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

    /// **What the view drew**, reported when its body is evaluated. `nil` for every caller that
    /// builds it for a snapshot or a preview; the composition root's own closure for the scene in
    /// `App/`.
    ///
    /// The Keyboard Shortcuts window's content is otherwise unobservable from the one lane that
    /// can see `App/`: replacing `ShortcutsHelpView()` with `EmptyView()` left a window with a
    /// correct title, a correct identifier, correct appearance traits and nothing inside it, and
    /// the whole gate stayed green (focus-2er).
    ///
    /// A receipt that merely says the body ran does not close that, and the measurement is
    /// unambiguous (focus-h7h): a window handed an **empty registry** fires it exactly as loudly
    /// as one drawing the committed table, and 262 ok-assertions stayed at 262. So the receipt
    /// carries the row count the window actually laid out.
    private let didRender: (@MainActor (ShellRenderedValues) -> Void)?

    public init(registry: CommandRegistry = .shell) {
        self.registry = registry
        self.didRender = nil
    }

    /// The application scene's initialiser: the same window, with a receipt that carries a value.
    ///
    /// **The one issue.** Unlike the cockpit and the Settings window this reference has no
    /// connection to be stamped, because it reads nothing from the graph — it draws
    /// `CommandRegistry.shell`, a committed value that cannot change while the process lives. So
    /// there is exactly one issue of it, and `ShellRenderedValues.singleIssue` is what both ends
    /// use rather than a counter that would only ever reach one.
    public init(
        registry: CommandRegistry = .shell,
        didRender: @escaping @MainActor (ShellRenderedValues) -> Void
    ) {
        self.registry = registry
        self.didRender = didRender
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
        // The scroll view is the *window's* affordance: at the largest accessibility text
        // size the reference can outgrow a small window, and scrolling is how a Mac window
        // handles that. The content itself is a separate view so the snapshot lane can
        // measure the thing that must never clip, rather than measuring a scroll view's
        // fixed frame and learning nothing.
        ScrollView {
            ShortcutsHelpContent(registry: registry)
        }
        .frame(minWidth: 360, minHeight: 240)
        .background(DesignTokens.Palette.windowBackground(for: traits))
        // **How many rows it actually drew, and which traits reached it** (focus-h7h).
        //
        // The row count is the value that tells the shipping window from an empty one. It is
        // counted off the same `groups(for:)` the content draws, so the number reported and the
        // number on the screen are one derivation rather than two.
        .shellRendered(.shortcutRowCount, Self.groups(for: registry).reduce(0) { $0 + $1.rows.count })
        .shellRendered(.appearanceTraits, traits.renderedDescription)
        .shellRenderReport(generation: ShellRenderedValues.singleIssue, didRender)
    }
}

/// The shortcut reference's content, without the window's scrolling.
struct ShortcutsHelpContent: View {
    let registry: CommandRegistry

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    var body: some View {
        let groups = ShortcutsHelpView.groups(for: registry)

        return VStack(alignment: .leading, spacing: spacing * 2) {
            VStack(alignment: .leading, spacing: spacing / 2) {
                ShellText(.helpHeading, role: .title2)
                    .fontWeight(.semibold)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                ShellText(.helpIntroduction, role: .callout)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: spacing / 2) {
                    ShellText(group.headingKey, role: .headline)
                        .lineLimit(nil)

                    Grid(
                        alignment: .leading,
                        horizontalSpacing: spacing * 2,
                        verticalSpacing: spacing / 2
                    ) {
                        GridRow {
                            ShellText(.helpColumnAction, role: .caption)
                                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                            ShellText(.helpColumnShortcut, role: .caption)
                                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                        }

                        ForEach(group.rows) { row in
                            GridRow {
                                ShellText(row.titleKey)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                // The glyph string is the shortcut itself, not prose:
                                // `verbatim` because it must never be sent through a
                                // catalog, and `monospaced` so ⌘, ⌥ and ⇧ line up down
                                // the column.
                                Text(verbatim: row.glyphs ?? "—")
                                    .font(DesignTokens.font(.body, scale: textScale))
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
}
