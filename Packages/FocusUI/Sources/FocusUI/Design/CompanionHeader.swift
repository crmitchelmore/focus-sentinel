import SwiftUI

/// The same quiet companion on every surface. Artwork carries no status or action;
/// the live heading remains localised, scalable text, never pixels inside the image.
struct CompanionHeader<Title: View>: View {
    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .body) private var inset: CGFloat = 20
    let title: Title

    init(@ViewBuilder title: () -> Title) {
        self.title = title()
    }

    private var plain: Bool { traits.increasedContrast || textScale != .standard }

    var body: some View {
        CompanionHeaderLayout(inset: inset, plain: plain) {
            title
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(plain
                ? DesignTokens.Palette.role(.bench, for: traits)
                : DesignTokens.companionLettering)
        }
            .frame(maxWidth: .infinity)
            .background {
                if plain {
                    DesignTokens.Palette.role(.slate, for: traits)
                } else {
                    GeometryReader { geometry in
                        Image(geometry.size.width > 500 ? "CompanionHeaderWide" : "CompanionHeader", bundle: .module)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .accessibilityHidden(true)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius + 4, style: .continuous))
    }
}

/// Reserve the illustration's leading quarter at any window width. The title sets
/// its own height, so longer translations never collide with the character or clip.
private struct CompanionHeaderLayout: Layout {
    let inset: CGFloat
    let plain: Bool

    private func leading(_ width: CGFloat) -> CGFloat {
        plain ? inset : max(inset, width * 0.26)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 300
        let title = subviews.first?.sizeThatFits(
            ProposedViewSize(width: max(0, width - leading(width) - inset), height: nil)
        ) ?? .zero
        return CGSize(width: width, height: max(plain ? 0 : width / (width > 500 ? 7 : 3), title.height + inset * 2))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let left = leading(bounds.width)
        subviews.first?.place(
            at: CGPoint(x: bounds.minX + left, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: max(0, bounds.width - left - inset), height: nil)
        )
    }
}
