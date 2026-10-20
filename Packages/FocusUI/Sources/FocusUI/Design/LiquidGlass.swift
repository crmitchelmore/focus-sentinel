import FocusCore
import SwiftUI

// MARK: - Liquid Glass, used where it means something (the owner's legibility ruling, 16 October 2026)
//
// The first glass pass put glass on buttons, chips and the tab bar over a blooming ground; the
// owner found the writing illegible (Spruce ink on a Spruce-tinted glass tab, grey glass buttons
// on a grey-green bloom). This file now carries the strategy in `Design/LiquidGlass.md`,
// from Apple's HIG ("don't use Liquid Glass in the content layer… use it sparingly") and its
// *Adopting Liquid Glass* guide:
//
// * **Ground** — solid, scheme-aware (`groundRole`). No blooms behind words.
// * **Content** — opaque panes one step lighter than the ground (`paneRole`), neutral inset
//   washes for fields and chips (`contentInset`), solid buttons (`CompanionButtonStyle`).
// * **Function** — Liquid Glass, regular and untinted, only on navigation: the system's own
//   window, toolbar, popover and sheet chrome, and the cockpit's tab-switcher track.
//
// Text never sits on tinted glass. Every glass surface falls back to an opaque one under Reduce
// Transparency and Increase Contrast, and the uninvited nudge panels never draw glass at all.

extension DesignTokens {
    /// **Whether the navigation layer is drawn as Liquid Glass under these traits.**
    ///
    /// Reduce Transparency already resolves `material(for:provenance:)` to `.opaque`; Increase
    /// Contrast is added here because glass softens edges and lets the ground tint the ink,
    /// which is the opposite of what that setting asks for.
    public static func drawsGlass(for traits: AppearanceTraits) -> Bool {
        material(for: traits, provenance: .summoned) == .material && !traits.increasedContrast
    }

    /// **The window's ground.** Inlay in Light and Bench in Dark: the darker of the two in
    /// either scheme, so a content pane always rises one step off it. (Bench is the lighter role
    /// in Light and the darker in Dark; a card that was Bench in both recessed into Dark's ground.)
    public static func groundRole(for traits: AppearanceTraits) -> Palette.Role {
        traits.colorScheme == .dark ? .bench : .inlay
    }

    /// **A content pane's fill** — the step above `groundRole` in either scheme.
    public static func paneRole(for traits: AppearanceTraits) -> Palette.Role {
        traits.colorScheme == .dark ? .inlay : .bench
    }

    /// The corner radius of a card. Generous, so a card reads as a soft pane rather than a box.
    public static let cardRadius: CGFloat = 24

    /// The corner radius of a control or an inset field — capsule-like on one line, still
    /// graceful when an accessibility size wraps the label onto two.
    public static let controlRadius: CGFloat = 16

    /// The Spruce wash that marks the accented card, in place of a border. Over an opaque pane,
    /// so it tints the ground the words sit on by a few counts and never their ink.
    public static let accentWashOpacity: Double = 0.07

    /// The neutral ink wash an inset field or chip carries inside a pane.
    public static let insetWashOpacity: Double = 0.06

    /// A secondary button's neutral ink wash at rest, and under the pointer.
    public static let controlWashOpacity: Double = 0.08
    public static let controlHoverWashOpacity: Double = 0.14

    /// A rule inside a card: present, but quieter than the whitespace around it.
    public static let quietRuleOpacity: Double = 0.16

    /// The soft lift under a content pane in Light; Dark separates panes by fill and a faint
    /// rim, since a shadow on a dark ground reads as a glow.
    public static func paneLiftOpacity(for traits: AppearanceTraits) -> Double {
        traits.colorScheme == .dark ? 0 : 0.08
    }

    /// The rim a Dark pane carries where Light has a lift.
    public static func paneRimOpacity(for traits: AppearanceTraits) -> Double {
        traits.colorScheme == .dark ? 0.10 : 0
    }

    /// **The liquid motion**: a soft spring for a control moving between states, or `nil` under
    /// Reduce Motion, where the change arrives instantly.
    public static func liquidAnimation(for traits: AppearanceTraits) -> Animation? {
        traits.reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82)
    }
}

/// An inset's ground inside content: a faint neutral ink wash, or the opaque ground role where
/// the person asked for solid grounds (Reduce Transparency, Increase Contrast). Never glass —
/// fields and chips are content.
struct ContentInset<S: InsettableShape>: ViewModifier {
    let shape: S
    let traits: AppearanceTraits

    func body(content: Content) -> some View {
        content.background(
            DesignTokens.drawsGlass(for: traits)
                ? DesignTokens.Palette.role(.slate, for: traits).opacity(DesignTokens.insetWashOpacity)
                : DesignTokens.Palette.role(DesignTokens.groundRole(for: traits), for: traits),
            in: shape
        )
    }
}

/// **The quiet separator** inside a card: a faint Mist rule, because whitespace and the headline
/// under it already do the separating; the system divider wherever the person asked for firm
/// edges.
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
    /// The summoned window's solid ground (`DesignTokens.groundRole`).
    func contentGround(_ traits: AppearanceTraits) -> some View {
        background(DesignTokens.Palette.role(DesignTokens.groundRole(for: traits), for: traits))
    }

    /// An inset field's ground (see `ContentInset`).
    func softField(_ traits: AppearanceTraits) -> some View {
        modifier(ContentInset(
            shape: RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous),
            traits: traits
        ))
    }

    /// A chip, badge or quoted block inside content (see `ContentInset`).
    func contentInset(in shape: some InsettableShape, traits: AppearanceTraits) -> some View {
        modifier(ContentInset(shape: shape, traits: traits))
    }

    /// A summoned row on an opaque pane — the content layer's ground, so it can sit inside the
    /// menu-bar popover, which the system already draws as glass.
    func softSlab(_ traits: AppearanceTraits, radius: CGFloat = DesignTokens.controlRadius) -> some View {
        background(
            DesignTokens.Palette.role(DesignTokens.paneRole(for: traits), for: traits),
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
    }
}
