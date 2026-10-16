import FocusCore
import SwiftUI

// MARK: - Liquid Glass (the owner's softness pass, 16 October 2026)
//
// The companion identity read as hard: opaque ivory cards with hairline borders on a flat
// Inlay ground, and buttons that were small filled rectangles. The owner asked for the summoned
// surfaces to be "more liquid glassy so we have some softness". macOS 26's own Liquid Glass is
// the material that word names, so the cockpit, the Settings panes and the popover now draw
// their buttons, chips and tab bar as glass over a soft ambient ground.
//
// The cleanliness pass (same day) took glass back off the *content* layer, per Apple's Tahoe
// guidance — glass is for controls and navigation, never glass on glass — and the 2026
// productivity-app consensus (Things, Linear, Raycast): cards are borderless soft panes with a
// gentle lift, separation comes from whitespace and type, and colour is the one Spruce accent.
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

    /// How much Bench a soft content pane carries over the ambient ground: enough that ink keeps
    /// its contrast, little enough that the ground's bloom still shows through.
    public static let softPaneOpacity: Double = 0.72

    /// The Spruce wash that marks the accented card, in place of a border.
    public static let accentWashOpacity: Double = 0.07

    /// The neutral ink wash an inset field carries.
    public static let insetWashOpacity: Double = 0.06

    /// A rule inside a soft card: present, but quieter than the whitespace around it.
    public static let quietRuleOpacity: Double = 0.16

    /// The soft lift under a content pane in Light; Dark separates panes by fill alone, since a
    /// light shadow on a dark ground reads as a glow.
    public static func paneLiftOpacity(for traits: AppearanceTraits) -> Double {
        traits.colorScheme == .dark ? 0 : 0.07
    }

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

/// An inset field's ground. A faint neutral inset rather than glass: a field sits inside
/// content, and Apple's Tahoe guidance keeps glass to the control and navigation layer.
struct SoftField: ViewModifier {
    let traits: AppearanceTraits

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous)
        content.background(
            DesignTokens.drawsGlass(for: traits)
                ? DesignTokens.Palette.role(.slate, for: traits).opacity(DesignTokens.insetWashOpacity)
                : DesignTokens.Palette.role(.inlay, for: traits),
            in: shape
        )
    }
}

/// **The quiet separator** inside a card. Over the soft ground it is a faint Mist rule, because
/// whitespace and the headline under it already do the separating; wherever glass is not drawn
/// it is the system divider, since a person who asked for contrast asked for firm edges.
struct CompanionSeparator: View {
    @Environment(\.appearanceTraits) private var traits

    var body: some View {
        if DesignTokens.drawsGlass(for: traits) {
            Rectangle()
                .fill(DesignTokens.Palette.role(.mist, for: traits).opacity(DesignTokens.quietRuleOpacity))
                .frame(height: 1)
                .accessibilityHidden(true)
        } else {
            Divider()
        }
    }
}

extension View {
    /// The summoned window's ambient ground (see `GlassBackdrop`).
    func glassBackdrop(_ traits: AppearanceTraits) -> some View {
        background(GlassBackdrop(traits: traits))
    }

    /// An inset field's soft ground.
    func softField(_ traits: AppearanceTraits) -> some View {
        modifier(SoftField(traits: traits))
    }

    /// A summoned row on a soft Bench slab — the content layer's ground, not glass, so it can sit
    /// inside a popover or window that is already glass. The old Inlay fill when glass is off.
    func softSlab(_ traits: AppearanceTraits, radius: CGFloat = DesignTokens.controlRadius) -> some View {
        background(
            DesignTokens.drawsGlass(for: traits)
                ? DesignTokens.Palette.role(.bench, for: traits).opacity(DesignTokens.softPaneOpacity)
                : DesignTokens.Palette.role(.inlay, for: traits),
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
    }
}
