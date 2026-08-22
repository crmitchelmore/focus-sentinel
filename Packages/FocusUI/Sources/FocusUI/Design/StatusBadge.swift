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
    public let status: FocusStatus
    /// Whether the caller wants the label drawn. See `showsLabel(requested:traits:)`: the
    /// answer is not simply this value.
    public let labelRequested: Bool

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .title2) private var glyphSize: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 8

    public init(status: FocusStatus, showsLabel: Bool = true) {
        self.status = status
        self.labelRequested = showsLabel
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
                        DesignTokens.tint(for: status).opacity(emphasis.outlineOpacity),
                        lineWidth: emphasis.borderWidth
                    )
                Image(systemName: status.symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DesignTokens.tint(for: status))
                    .font(DesignTokens.font(.title3, scale: textScale))
            }
            .frame(
                width: DesignTokens.spacing(glyphSize, scale: textScale),
                height: DesignTokens.spacing(glyphSize, scale: textScale)
            )
            .accessibilityHidden(true)

            if Self.showsLabel(requested: labelRequested, traits: traits) {
                ShellText(resource: status.shortLabelResource)
                    .foregroundStyle(DesignTokens.Palette.primaryText)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, spacing)
        .padding(.vertical, spacing / 2)
        .shellSurface(DesignTokens.material(for: traits), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(
                    DesignTokens.Palette.separator.opacity(emphasis.outlineOpacity),
                    lineWidth: emphasis.borderWidth
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(status.shortLabelResource))
    }
}
