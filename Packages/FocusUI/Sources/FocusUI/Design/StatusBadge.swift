import FocusCore
import SwiftUI

/// The silhouette `FocusStatus.shape` names, as a drawable path.
///
/// **It is no longer drawn by `StatusBadge`** (focus-w41.6). It was the second of the status's
/// three channels while the first was an SF Symbol; with e11b's drawn family the mark *is* the
/// silhouette, and stroking an outline around it put a three-quarter arc inside a triangle. It
/// stays for a surface with no room for a glyph — e08's notch — and as the geometry
/// `StatusShape` names, which is what `DesignTokenTests` holds to being five distinct paths.
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
/// Two independent channels, always: **the app's own mark**, whose silhouette is unalike every
/// other by a measured distance rather than by assertion, and the short label. Colour is a third
/// and it is never alone — which is what makes the badge legible to someone who cannot use
/// colour, and what makes "differentiate without colour" a behaviour rather than a claim.
///
/// It was three (focus-w41.6): the glyph, an outline stroked *behind* it, and the label. That was
/// coherent while the glyph was an SF Symbol and is two silhouettes for one state now that the
/// glyph is the family's own mark.
public struct StatusBadge: View {
    /// **How much furniture the badge draws around itself** (focus-w41, direction §5.1).
    ///
    /// The two styles carry the same three channels — mark, label, tint — and differ
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

    /// The unscaled side of the chip's glyph box, published so a surface laying the badge out
    /// beside something else can measure the row it is about to draw (focus-6pr.5).
    public static let chipGlyphBox: CGFloat = 22

    /// The chip's own horizontal padding around that box, each side. `@ScaledMetric` in the view
    /// and therefore inert on macOS, which is why it is a constant here and not a scaled one.
    public static let chipHorizontalPadding: CGFloat = 8

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .title2) private var glyphSize: CGFloat = Self.chipGlyphBox
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = StatusBadge.chipHorizontalPadding

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
        HStack(spacing: spacing) {
            // **The app's own mark, not an SF Symbol, and it IS the silhouette** (focus-w41,
            // focus-w41.6). `resizable()` because it is a 16 pt asset and the badge's glyph box
            // is a scaled metric — the silhouette is what carries the meaning and it survives
            // being scaled; a fixed 16 pt picture in a growing box would shrink against its own
            // label at accessibilityLarge.
            //
            // **The outline is not drawn here, and that is a ruling** (focus-w41.6). This used to
            // be a `ZStack` of `StatusOutline(status.shape)` and the mark, which was coherent
            // while the glyph was an SF Symbol — a filled triangle inside a triangular outline.
            // With the drawn family it is two different marks for one state: `statusUnrelated`
            // rendered its three-quarter arc and dot *inside a triangle*, and the accusation
            // panel's badge did the same. The direction's whole point is one ring, one family.
            //
            // `FocusStatus.shape`'s doctrine — "silhouettes are deliberately unalike, even in
            // monochrome at small sizes" — is satisfied by the marks themselves and it is a
            // number rather than a sentence: `scripts/glyph-distance.py` holds all ten images the
            // menu bar can draw above `Config/glyph-distance-floor.txt`, and the tightest pair
            // measures 10.75 against a floor of 9.0. So `shape` stays as the vocabulary that
            // *describes* each mark's outline — the accessibility description and the distance
            // gate's naming both read it — and `StatusOutline` stays for a surface with no room
            // for a glyph. Neither is drawn on top of the mark.
            StatusMark.image(for: status)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(DesignTokens.tint(for: status, traits: traits))
                .padding(DesignTokens.spacing(2, scale: textScale))
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
                .contentInset(in: Capsule(), traits: traits)
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
