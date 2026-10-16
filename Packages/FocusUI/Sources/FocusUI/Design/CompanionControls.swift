import SwiftUI

/// Shared native controls for the companion identity. State still belongs to each feature.
///
/// Drawn as interactive Liquid Glass wherever summoned glass is drawn (`DesignTokens.drawsGlass`):
/// a prominent or selected control is glass tinted Spruce, the rest are clear glass. Under Reduce
/// Transparency or Increase Contrast they keep the opaque fills and hairlines they had before.
struct CompanionButtonStyle: ButtonStyle {
    var prominent = false
    var selected = false
    @State private var isHovered = false
    @Environment(\.appearanceTraits) private var traits
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.shellTextScale) private var textScale

    func makeBody(configuration: Configuration) -> some View {
        let filled = prominent || selected
        let shape = RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous)
        let emphasis = DesignTokens.emphasis(for: traits)
        let glass = DesignTokens.drawsGlass(for: traits)
        surface(
            configuration.label
                .font(DesignTokens.font(.callout, scale: textScale))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .foregroundStyle(configuration.role == .destructive
                    ? Color(nsColor: .systemRed)
                    : DesignTokens.Palette.role(filled ? .bench : .slate, for: traits)),
            filled: filled,
            glass: glass,
            shape: shape
        )
        .overlay(shape.strokeBorder(
            DesignTokens.Palette.role(isHovered && isEnabled ? .spruce : .mist, for: traits)
                .opacity(strokeOpacity(glass: glass, emphasis: emphasis)),
            lineWidth: emphasis.promotesSecondaryText ? 2 : 1
        ))
        .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
        .contentShape(shape)
        .scaleEffect(configuration.isPressed && isEnabled && !traits.reduceMotion ? 0.97 : 1)
        .animation(DesignTokens.liquidAnimation(for: traits), value: configuration.isPressed)
        .animation(DesignTokens.animation(for: traits), value: isHovered)
        .animation(DesignTokens.liquidAnimation(for: traits), value: selected)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private func surface(
        _ label: some View,
        filled: Bool,
        glass: Bool,
        shape: RoundedRectangle
    ) -> some View {
        if glass {
            label.glassEffect(
                filled
                    ? Glass.regular.tint(DesignTokens.Palette.role(.spruce, for: traits)).interactive(isEnabled)
                    : Glass.regular.interactive(isEnabled),
                in: shape
            )
        } else {
            label.background(shape.fill(DesignTokens.Palette.role(filled ? .spruce : .inlay, for: traits)))
        }
    }

    /// Glass draws its own rim, so at rest a glass control carries no hairline; hover still
    /// lights the edge Spruce, so the pointer's target is never only a change of shimmer.
    private func strokeOpacity(glass: Bool, emphasis: Emphasis) -> Double {
        if emphasis.promotesSecondaryText { return 1 }
        let lit = isHovered && isEnabled
        if glass { return lit ? 0.55 : 0 }
        return lit ? 0.7 : 0.25
    }
}

/// A title with an SF Symbol marker: consistent navigation cues, never a new status signal.
struct CompanionSectionHeading: View {
    let key: ShellStringKey
    let symbol: String
    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(DesignTokens.font(.callout, scale: textScale))
                .accessibilityHidden(true)
            ShellText(key, role: .sectionHeading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(DesignTokens.Palette.role(.spruce, for: traits))
    }
}

/// A card: a borderless soft pane with a gentle lift over the window's ambient ground, and the
/// accented card carries a faint Spruce wash rather than an outline. Not glass — the buttons and
/// chips inside are, and glass on glass turns muddy. The opaque Bench card with a hairline when
/// glass is not drawn.
private struct CompanionSurface: ViewModifier {
    var accent: Bool
    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
        let padded = content
            .padding(DesignTokens.spacing(18, scale: textScale))
            .frame(maxWidth: .infinity, alignment: .leading)
        if DesignTokens.drawsGlass(for: traits) {
            padded.background {
                shape
                    .fill(DesignTokens.Palette.role(.bench, for: traits).opacity(DesignTokens.softPaneOpacity))
                    .overlay(shape.fill(
                        DesignTokens.Palette.role(.spruce, for: traits)
                            .opacity(accent ? DesignTokens.accentWashOpacity : 0)
                    ))
                    .shadow(
                        color: DesignTokens.Palette.role(.slate, for: traits)
                            .opacity(DesignTokens.paneLiftOpacity(for: traits)),
                        radius: 14,
                        y: 4
                    )
            }
        } else {
            padded
                .background(DesignTokens.Palette.role(.bench, for: traits), in: shape)
                .overlay(shape.strokeBorder(
                    DesignTokens.Palette.role(accent ? .spruce : .mist, for: traits)
                        .opacity(DesignTokens.emphasis(for: traits).promotesSecondaryText ? 1 : (accent ? 0.5 : 0.22)),
                    lineWidth: accent ? 2 : 1
                ))
        }
    }
}

extension View {
    func companionSurface(accent: Bool = false) -> some View {
        modifier(CompanionSurface(accent: accent))
    }
}
