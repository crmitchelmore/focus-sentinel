import SwiftUI

/// Shared native controls for the companion identity. State still belongs to each feature.
///
/// **Solid, never glass** (`Design/LiquidGlass.md`). A button inside content is content's
/// control: a prominent or selected one is a solid Spruce fill with Bench ink — above 5:1 in both
/// schemes — and the rest are a neutral ink wash with Slate ink. Hover deepens the fill; Increase
/// Contrast adds a firm edge. Being glass-free is also what makes it safe on the uninvited nudge
/// panels, which must never draw glass.
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
        let lit = isHovered && isEnabled
        let firmEdges = DesignTokens.emphasis(for: traits).promotesSecondaryText
        configuration.label
            .font(DesignTokens.font(.callout, scale: textScale))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(configuration.role == .destructive
                ? Color(nsColor: .systemRed)
                : DesignTokens.Palette.role(filled ? .bench : .slate, for: traits))
            .background {
                if filled {
                    shape
                        .fill(DesignTokens.Palette.role(.spruce, for: traits))
                        .overlay(shape.fill(
                            DesignTokens.Palette.role(.slate, for: traits).opacity(lit ? 0.12 : 0)
                        ))
                } else {
                    shape.fill(
                        DesignTokens.Palette.role(.slate, for: traits)
                            .opacity(lit ? DesignTokens.controlHoverWashOpacity : DesignTokens.controlWashOpacity)
                    )
                }
            }
            .overlay {
                if firmEdges {
                    shape.strokeBorder(
                        DesignTokens.Palette.role(filled ? .slate : .mist, for: traits),
                        lineWidth: 2
                    )
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && isEnabled && !traits.reduceMotion ? 0.97 : 1)
            .animation(DesignTokens.liquidAnimation(for: traits), value: configuration.isPressed)
            .animation(DesignTokens.animation(for: traits), value: isHovered)
            .animation(DesignTokens.liquidAnimation(for: traits), value: selected)
            .onHover { isHovered = $0 }
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

/// A card: an opaque pane one step above the window's ground (`DesignTokens.paneRole`), with a
/// soft lift in Light and a faint rim in Dark. The accented card carries a faint Spruce wash over
/// that opaque fill rather than an outline. Never glass — a card holds sentences, and Apple keeps
/// glass off the content layer. Where the person asked for firm edges, a hairline (Spruce and
/// two points on the accented card).
private struct CompanionSurface: ViewModifier {
    var accent: Bool
    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
        let soft = DesignTokens.drawsGlass(for: traits)
        let firm = DesignTokens.emphasis(for: traits).promotesSecondaryText
        content
            .padding(DesignTokens.spacing(18, scale: textScale))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape
                    .fill(DesignTokens.Palette.role(DesignTokens.paneRole(for: traits), for: traits))
                    .overlay(shape.fill(
                        DesignTokens.Palette.role(.spruce, for: traits)
                            .opacity(accent ? DesignTokens.accentWashOpacity : 0)
                    ))
                    .shadow(
                        color: DesignTokens.Palette.role(.slate, for: traits)
                            .opacity(soft ? DesignTokens.paneLiftOpacity(for: traits) : 0),
                        radius: 14,
                        y: 4
                    )
            }
            .overlay {
                if soft {
                    shape.strokeBorder(
                        DesignTokens.Palette.role(.slate, for: traits)
                            .opacity(DesignTokens.paneRimOpacity(for: traits)),
                        lineWidth: 1
                    )
                } else {
                    shape.strokeBorder(
                        DesignTokens.Palette.role(accent ? .spruce : .mist, for: traits)
                            .opacity(firm ? 1 : (accent ? 0.5 : 0.22)),
                        lineWidth: accent ? 2 : 1
                    )
                }
            }
    }
}

extension View {
    func companionSurface(accent: Bool = false) -> some View {
        modifier(CompanionSurface(accent: accent))
    }
}
