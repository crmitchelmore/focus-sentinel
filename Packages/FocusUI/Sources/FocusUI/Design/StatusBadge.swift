import FocusCore
import SwiftUI

/// The silhouette a `FocusStatus` is drawn inside.
///
/// This is the second of the status's three channels. It exists so that a user who cannot
/// tell the SF Symbols apart — or a surface too small to draw one, like e08's notch — still
/// has an outline that differs from every other status.
public struct StatusOutline: Shape {
    public let shape: StatusShape

    public init(_ shape: StatusShape) {
        self.shape = shape
    }

    public func path(in rect: CGRect) -> Path {
        switch shape {
        case .circle:
            return Path(ellipseIn: squareInscribed(in: rect))
        case .diamond:
            let square = squareInscribed(in: rect)
            var path = Path()
            path.move(to: CGPoint(x: square.midX, y: square.minY))
            path.addLine(to: CGPoint(x: square.maxX, y: square.midY))
            path.addLine(to: CGPoint(x: square.midX, y: square.maxY))
            path.addLine(to: CGPoint(x: square.minX, y: square.midY))
            path.closeSubpath()
            return path
        case .triangle:
            let square = squareInscribed(in: rect)
            var path = Path()
            path.move(to: CGPoint(x: square.midX, y: square.minY))
            path.addLine(to: CGPoint(x: square.maxX, y: square.maxY))
            path.addLine(to: CGPoint(x: square.minX, y: square.maxY))
            path.closeSubpath()
            return path
        case .rectangle:
            return Path(squareInscribed(in: rect))
        case .capsule:
            return Path(roundedRect: rect, cornerRadius: rect.height / 2)
        }
    }

    /// The largest centred square inside `rect`. Keeps circle, diamond, triangle and
    /// rectangle the same visual weight however wide the badge is.
    private func squareInscribed(in rect: CGRect) -> CGRect {
        let side = min(rect.width, rect.height)
        return CGRect(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2,
            width: side,
            height: side
        )
    }
}

/// A status, drawn.
///
/// Three independent channels, always: the SF Symbol, the silhouette it sits in, and the
/// short label. Colour is a fourth, and it is never alone — which is what makes the badge
/// legible to someone who cannot use colour, and what makes "differentiate without colour"
/// a behaviour rather than a claim.
public struct StatusBadge: View {
    /// **How much furniture the badge draws around itself** (focus-w41, direction §5.1).
    ///
    /// The two styles carry the same four channels — glyph, silhouette, label, tint — and differ
    /// only in whether the badge is a *thing* or a *line*. That is the whole of the cockpit
    /// density change at this control: a chip beside the priority reads as an object competing
    /// with the sentence, and the sentence is the one thing on the screen the person wrote.
    public enum Style: String, Sendable, CaseIterable, Hashable {
        /// A capsule with its own fill and border. What a badge inside a list or a popover is:
        /// the surface around it is busy, so the badge has to hold itself together.
        case chip
        /// Glyph and label on the line, with no fill and no border. What sits beside the hero.
        case compact
    }

    public let status: FocusStatus
    /// Whether the caller wants the label drawn. See `showsLabel(requested:traits:)`: the
    /// answer is not simply this value.
    public let labelRequested: Bool
    /// How much furniture to draw. `chip` is what every surface but the cockpit header asks for.
    public let style: Style

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .title2) private var glyphSize: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 8

    public init(status: FocusStatus, showsLabel: Bool = true, style: Style = .chip) {
        self.status = status
        self.labelRequested = showsLabel
        self.style = style
    }

    /// Whether the label is drawn.
    ///
    /// A caller may ask for a glyph-only badge — a compact surface has a legitimate reason
    /// to. It may not have one when the user has asked to differentiate without colour: at
    /// that point the label stops being decoration and becomes the channel the user is
    /// relying on, so it is forced back on.
    nonisolated public static func showsLabel(requested: Bool, traits: AppearanceTraits) -> Bool {
        requested || traits.differentiateWithoutColor
    }

    public var body: some View {
        let emphasis = DesignTokens.emphasis(for: traits)

        return HStack(spacing: spacing) {
            ZStack {
                StatusOutline(status.shape)
                    .stroke(
                        DesignTokens.tint(for: status, traits: traits).opacity(emphasis.outlineOpacity),
                        lineWidth: emphasis.borderWidth
                    )
                // **The app's own mark, not an SF Symbol** (focus-w41). `resizable()` because
                // it is a 16 pt asset and the badge's glyph box is a scaled metric — the
                // silhouette is what carries the meaning and it survives being scaled; a fixed
                // 16 pt picture in a growing box would shrink against its own label at
                // accessibilityLarge.
                StatusMark.image(for: status)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(DesignTokens.tint(for: status, traits: traits))
                    .padding(DesignTokens.spacing(2, scale: textScale))
            }
            .frame(
                width: DesignTokens.spacing(glyphSize * style.glyphScale, scale: textScale),
                height: DesignTokens.spacing(glyphSize * style.glyphScale, scale: textScale)
            )
            .accessibilityHidden(true)

            if Self.showsLabel(requested: labelRequested, traits: traits) {
                ShellText(resource: status.shortLabelResource, role: style.labelRole)
                    .foregroundStyle(DesignTokens.Palette.primaryText)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // **The compact style draws no furniture at all** (focus-w41). Not a chip with its
        // padding turned down: the capsule and its border are the thing being removed, because a
        // bordered object beside the priority reads as a second heading. What is left is the
        // glyph, the silhouette and the label — the three channels that were always the ones
        // carrying the meaning — set on the line beside the sentence they are about.
        .modifier(ChipChrome(drawn: style == .chip, spacing: spacing, traits: traits))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(status.shortLabelResource))
    }
}

extension StatusBadge.Style {
    /// How large the glyph is drawn, as a factor of the badge's own metric.
    ///
    /// The compact badge sits beside body text on one line, so it is drawn at the size of the
    /// text it is beside rather than at the chip's own. Not a separate metric: one number, scaled,
    /// so the `@ScaledMetric` the chip already grows by still governs both.
    var glyphScale: CGFloat {
        switch self {
        case .chip: 1
        case .compact: 0.72
        }
    }

    /// The type role the label is set in.
    ///
    /// `.callout` for the compact form, because it is a supporting line beside the hero and not
    /// a heading of its own. The chip keeps whatever `ShellText` defaults to, which is `.body`.
    var labelRole: DesignTokens.FontRole {
        switch self {
        case .chip: .body
        case .compact: .callout
        }
    }
}

/// The chip's capsule and border, or nothing at all.
///
/// A modifier rather than an `if` around the whole badge, so the two styles share one
/// accessibility element and one label — the compact badge is the same control drawn quieter, and
/// a branch that rebuilt it would be a second control that happened to look similar.
private struct ChipChrome: ViewModifier {
    let drawn: Bool
    let spacing: CGFloat
    let traits: AppearanceTraits

    func body(content: Content) -> some View {
        if drawn {
            let emphasis = DesignTokens.emphasis(for: traits)
            content
                .padding(.horizontal, spacing)
                .padding(.vertical, spacing / 2)
                .shellSurface(
                    DesignTokens.material(for: traits, provenance: .summoned),
                    in: Capsule(),
                    traits: traits
                )
                .overlay {
                    Capsule()
                        .strokeBorder(
                            DesignTokens.Palette.separator(for: traits)
                                .opacity(emphasis.outlineOpacity),
                            lineWidth: emphasis.borderWidth
                        )
                }
        } else {
            content
        }
    }
}
