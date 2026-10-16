import FocusCore
import SwiftUI

// MARK: - Liquid Glass (the owner's softness pass, 16 October 2026)
//
// The companion identity read as hard: opaque ivory cards with hairline borders on a flat
// Inlay ground, and buttons that were small filled rectangles. The owner asked for the summoned
// surfaces to be "more liquid glassy so we have some softness". macOS 26's own Liquid Glass is
// the material that word names, so the cockpit, the Settings panes and the popover now draw
// their cards, buttons, chips and tab bar as glass over a soft ambient ground.
//
// Glass is a summoned-surface material and nothing more. The uninvited nudge panels stay opaque
// for the reason `DesignTokens.material(for:provenance:)` gives, and every glass surface falls
// back to the opaque identity under Reduce Transparency and Increase Contrast, where a person
// has asked the screen for solid grounds and firm edges.

extension DesignTokens {
    /// **Whether summoned surfaces are drawn as Liquid Glass under these traits.**
    ///
    /// Reduce Transparency already resolves `material(for:provenance:)` to `.opaque`; Increase
    /// Contrast is added here because glass softens edges and lets the ground tint the ink,
    /// which is the opposite of what that setting asks for.
    public static func drawsGlass(for traits: AppearanceTraits) -> Bool {
        material(for: traits, provenance: .summoned) == .material && !traits.increasedContrast
    }

    /// The corner radius of a card. Generous, so a card reads as a soft pane rather than a box.
    public static let cardRadius: CGFloat = 24

    /// The corner radius of a control or an inset field — capsule-like on one line, still
    /// graceful when an accessibility size wraps the label onto two.
    public static let controlRadius: CGFloat = 16

    /// How much of the Bench ground a glass card carries, so ink on it keeps its contrast over
    /// whatever colour the ambient ground lends the glass.
    public static let glassGroundTint: Double = 0.4

    /// How strongly the ambient ground blooms toward Spruce behind the glass.
    public static let ambientBloomOpacity: Double = 0.26

    /// **The liquid motion**: a soft spring for a control moving between states, or `nil` under
    /// Reduce Motion, where the change arrives instantly.
    public static func liquidAnimation(for traits: AppearanceTraits) -> Animation? {
        traits.reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82)
    }
}

/// **The ambient ground a summoned window's glass sits on.**
///
/// Glass with nothing behind it but a flat fill reads as a grey card. Two broad radial blooms —
/// Spruce from the top leading corner, Mist from the bottom trailing one, with a Bench light
/// between them — give the glass something to bend, and that is where the softness comes from.
/// Gradients rather than blurred shapes, so the ground costs one fill and renders identically
/// in every lane. Opaque Inlay whenever glass is not drawn.
struct GlassBackdrop: View {
    let traits: AppearanceTraits

    var body: some View {
        let inlay = DesignTokens.Palette.role(.inlay, for: traits)
        if DesignTokens.drawsGlass(for: traits) {
            GeometryReader { geometry in
                let reach = max(geometry.size.width, geometry.size.height)
                ZStack {
                    inlay
                    RadialGradient(
                        colors: [
                            DesignTokens.Palette.role(.spruce, for: traits)
                                .opacity(DesignTokens.ambientBloomOpacity),
                            DesignTokens.Palette.role(.spruce, for: traits).opacity(0),
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: reach * 0.85
                    )
                    RadialGradient(
                        colors: [
                            DesignTokens.Palette.role(.mist, for: traits)
                                .opacity(DesignTokens.ambientBloomOpacity * 0.7),
                            DesignTokens.Palette.role(.mist, for: traits).opacity(0),
                        ],
                        center: .bottomTrailing,
                        startRadius: 0,
                        endRadius: reach * 0.75
                    )
                    RadialGradient(
                        colors: [
                            DesignTokens.Palette.role(.bench, for: traits).opacity(0.55),
                            DesignTokens.Palette.role(.bench, for: traits).opacity(0),
                        ],
                        center: UnitPoint(x: 0.62, y: 0.38),
                        startRadius: 0,
                        endRadius: reach * 0.5
                    )
                }
            }
            .accessibilityHidden(true)
        } else {
            inlay
        }
    }
}

/// A round glyph well: a soft Spruce wash rather than a boxed tile. Not glass — it sits on glass
/// cards, and glass stacked on glass turns muddy.
struct GlyphWell: ViewModifier {
    let traits: AppearanceTraits

    func body(content: Content) -> some View {
        content
            .frame(width: 30, height: 30)
            .background(
                DesignTokens.drawsGlass(for: traits)
                    ? DesignTokens.Palette.role(.spruce, for: traits).opacity(0.14)
                    : DesignTokens.Palette.role(.inlay, for: traits),
                in: Circle()
            )
    }
}

/// An inset text field's ground: soft glass when glass is drawn, the old Inlay fill otherwise.
struct SoftField: ViewModifier {
    let traits: AppearanceTraits

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous)
        if DesignTokens.drawsGlass(for: traits) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(DesignTokens.Palette.role(.inlay, for: traits), in: shape)
        }
    }
}

extension View {
    /// The summoned window's ambient ground (see `GlassBackdrop`).
    func glassBackdrop(_ traits: AppearanceTraits) -> some View {
        background(GlassBackdrop(traits: traits))
    }

    /// A section or sheet heading's round glyph well.
    func glyphWell(_ traits: AppearanceTraits) -> some View {
        modifier(GlyphWell(traits: traits))
    }

    /// An inset field's soft ground.
    func softField(_ traits: AppearanceTraits) -> some View {
        modifier(SoftField(traits: traits))
    }

    /// A summoned row drawn as a glass slab, or the old Inlay fill when glass is not drawn.
    @ViewBuilder
    func glassSlab(_ traits: AppearanceTraits, radius: CGFloat = DesignTokens.controlRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if DesignTokens.drawsGlass(for: traits) {
            glassEffect(.regular, in: shape)
        } else {
            background(DesignTokens.Palette.role(.inlay, for: traits), in: shape)
        }
    }
}
