import FocusCore
import SwiftUI

/// **How Focus decides** — the rule-precedence ladder, rendered from the ladder itself.
///
/// ## Why this pane exists
///
/// The roadmap names the risk precisely: *"Rule precedence is a product contract and must not
/// drift between Settings copy, the explanation builder and the runtime."* A comment saying so
/// is not a mechanism. `CascadePrecedence.rungs` is, and it has exactly four readers (R-54):
///
/// 1. the runtime — `RuleCascade` iterates `executableRungs`;
/// 2. the explanation builder — switches exhaustively over `CascadeStage`;
/// 3. **this pane** — renders `CascadePrecedence.rungs` in `rank` order;
/// 4. `check-strings.sh` — asserts a bijection with the `cascade.rung.*` catalog keys.
///
/// Three of the four are mechanically checked, and there is no fifth place a rung order can be
/// written down. **This view holds no list of its own**: it draws what the ladder contains, in
/// the order the ladder contains it, and the committed snapshot baseline is what makes
/// re-ordering the ladder without re-recording a red gate.
///
/// ## Why the unavailable rung is drawn rather than hidden
///
/// `onDeviceModel` is declared at rank 6 and is **not executable in this build** — e06 supplies
/// the implementation and flips one stored flag. It is drawn anyway, dimmed, with the
/// *not in this version* caption, because the **placement** of the model below every user rule
/// and below the deterministic heuristic is precisely the contract this pane exists to show. A
/// ladder that hid the rung would be a ladder that could quietly acquire it in the wrong place.
///
/// ## What it does not offer
///
/// Nothing to press. This is a statement of how the app behaves, in the pane where the app
/// states how it behaves — not a control surface. Rules are authored where rules are authored.
public struct CascadePrecedenceView: View {
    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    public init() {}

    /// **The** rungs this pane draws, in the order it draws them.
    ///
    /// Exposed so the snapshot suite can compare the rendered order to the ladder itself rather
    /// than to a list written out a second time in a test — which would be the fifth place R-54
    /// says there is not.
    nonisolated public static var drawnRungs: [CascadeRung] { CascadePrecedence.rungs }

    /// The rungs drawn in the secondary style. `rungs.filter { !$0.isExecutable }`, read from
    /// the ladder, so a rung that becomes executable stops being dimmed with no edit here.
    nonisolated public static var dimmedRungs: [CascadeRung] {
        CascadePrecedence.rungs.filter { !$0.isExecutable }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ShellText(resource: CascadePrecedence.headingResource, role: .headline)

            VStack(alignment: .leading, spacing: spacing / 2) {
                ForEach(Self.drawnRungs) { rung in
                    row(rung)
                }
            }

            // *Your own rules always win.* The sentence this whole ladder exists to make true,
            // said out loud in the place a person can check it against the order above.
            ShellText(resource: CascadePrecedence.footnoteResource, role: .footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(CascadePrecedence.headingResource))
    }

    /// One rung: its place in the order, its name, and — when this build cannot consult it —
    /// the caption that says so.
    private func row(_ rung: CascadeRung) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing / 2) {
            // The position in the ladder, as data. Drawn from `rank` rather than from the loop,
            // so the number a person reads is the number the engine sorts by.
            Text(verbatim: (rung.rank + 1).formatted(.number))
                .font(DesignTokens.font(.callout, scale: textScale))
                .monospacedDigit()
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))

            ShellText(resource: rung.settingsCopyResource, role: .callout)
                .foregroundStyle(
                    rung.isExecutable
                        ? DesignTokens.Palette.primaryText
                        : DesignTokens.supportingTextColor(for: traits)
                )
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: spacing / 2)

            if !rung.isExecutable {
                ShellText(resource: CascadePrecedence.unavailableCaptionResource, role: .footnote)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
