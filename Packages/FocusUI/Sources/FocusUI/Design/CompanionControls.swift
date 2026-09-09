import SwiftUI

/// Shared native controls for the companion identity. State still belongs to each feature.
struct CompanionButtonStyle: ButtonStyle {
    var prominent = false
    var selected = false
    @Environment(\.appearanceTraits) private var traits
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.shellTextScale) private var textScale

    func makeBody(configuration: Configuration) -> some View {
        let filled = prominent || selected
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        configuration.label
            .font(DesignTokens.font(.callout, scale: textScale))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .foregroundStyle(configuration.role == .destructive
                ? Color(nsColor: .systemRed)
                : DesignTokens.Palette.role(filled ? .bench : .slate, for: traits))
            .background(shape.fill(DesignTokens.Palette.role(filled ? .spruce : .inlay, for: traits)))
            .overlay(shape.strokeBorder(
                DesignTokens.Palette.role(.mist, for: traits)
                    .opacity(DesignTokens.emphasis(for: traits).promotesSecondaryText ? 1 : 0.25),
                lineWidth: DesignTokens.emphasis(for: traits).promotesSecondaryText ? 2 : 1
            ))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .contentShape(shape)
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
                .frame(width: 30, height: 30)
                .background(DesignTokens.Palette.role(.inlay, for: traits), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            ShellText(key, role: .sectionHeading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(DesignTokens.Palette.role(.spruce, for: traits))
    }
}

private struct CompanionSurface: ViewModifier {
    var accent: Bool
    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        content
            .padding(DesignTokens.spacing(18, scale: textScale))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Palette.role(.bench, for: traits), in: shape)
            .overlay(shape.strokeBorder(
                DesignTokens.Palette.role(accent ? .spruce : .mist, for: traits)
                    .opacity(DesignTokens.emphasis(for: traits).promotesSecondaryText ? 1 : (accent ? 0.5 : 0.22)),
                lineWidth: accent ? 2 : 1
            ))
    }
}

extension View {
    func companionSurface(accent: Bool = false) -> some View {
        modifier(CompanionSurface(accent: accent))
    }
}
