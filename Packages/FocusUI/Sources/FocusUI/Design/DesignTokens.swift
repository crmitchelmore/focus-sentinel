import AppKit
import FocusCore
import SwiftUI

/// How a raised surface is filled.
///
/// A value rather than a `ShapeStyle`, because the choice has to be *assertable*: "materials
/// collapse to opaque fills under Reduce Transparency" is a promise, and a promise that can
/// only be checked by looking at a screenshot is not one the gate can keep.
public enum SurfaceFill: String, Sendable, Equatable, Hashable, CaseIterable {
    /// The system's regular material — translucent, vibrant, the default.
    case material
    /// A flat opaque fill. What Reduce Transparency asks for.
    case opaque
}

/// How strongly the shell draws its own structure.
///
/// Under Increase Contrast, borders thicken and text that would otherwise be secondary is
/// drawn at full strength. Both are values so a test can compare them.
public struct Emphasis: Sendable, Equatable, Hashable {
    /// Stroke width for outlines the shell draws itself.
    public var borderWidth: CGFloat
    /// Opacity of those outlines.
    public var outlineOpacity: Double
    /// Whether supporting text is promoted from secondary to primary.
    public var promotesSecondaryText: Bool

    public init(borderWidth: CGFloat, outlineOpacity: Double, promotesSecondaryText: Bool) {
        self.borderWidth = borderWidth
        self.outlineOpacity = outlineOpacity
        self.promotesSecondaryText = promotesSecondaryText
    }
}

/// The design-token layer.
///
/// Three rules hold everywhere in this file:
///
/// 1. **No hardcoded colour values.** Every colour resolves from a semantic system colour, so
///    the shell follows the user's accent colour and both appearance modes without knowing
///    anything about either.
/// 2. **No fixed point sizes.** Type comes from the system text styles; spacing that must
///    grow with text is `@ScaledMetric` at the call site.
/// 3. **Every accessibility setting is read from injected `AppearanceTraits`, never from
///    `NSWorkspace` at the point of use.** On this machine every such setting is off, so
///    views that read the system directly could only ever be tested by changing the
///    developer's own System Settings. Injected, the snapshot lane sets each variant in one
///    line and the running app behaves identically.
public enum DesignTokens {
    // MARK: - Surfaces

    /// The fill a raised surface should use under these traits.
    ///
    /// Reduce Transparency is not a suggestion: a material that stays translucent when the
    /// user has asked for opacity is a defect, not a style choice.
    public static func material(for traits: AppearanceTraits) -> SurfaceFill {
        traits.reduceTransparency ? .opaque : .material
    }

    // MARK: - Emphasis

    /// How hard to draw structure under these traits.
    public static func emphasis(for traits: AppearanceTraits) -> Emphasis {
        traits.increasedContrast
            ? Emphasis(borderWidth: 2, outlineOpacity: 1.0, promotesSecondaryText: true)
            : Emphasis(borderWidth: 1, outlineOpacity: 0.6, promotesSecondaryText: false)
    }

    // MARK: - Motion

    /// The animation to use for a shell transition, or `nil` when motion must not carry it.
    ///
    /// `nil` means "change the state with no animation at all". Nothing in the shell may use
    /// animation as the *only* signal that something changed — under Reduce Motion the
    /// change still has to be visible, it just arrives instantly.
    public static func animation(for traits: AppearanceTraits) -> Animation? {
        traits.reduceMotion ? nil : .smooth(duration: 0.2)
    }

    // MARK: - Colour

    /// Semantic colours, resolved from the system.
    ///
    /// Colour is always an *additional* channel in this shell — every status also carries a
    /// distinct symbol, a distinct silhouette and a label — so nothing here is load-bearing
    /// on its own.
    public enum Palette {
        /// Primary label colour.
        public static var primaryText: Color { .primary }
        /// Supporting label colour.
        public static var secondaryText: Color { .secondary }
        /// The user's own accent colour. Never overridden by an asset-catalog accent.
        public static var accent: Color { Color(nsColor: .controlAccentColor) }
        /// The window's own background.
        public static var windowBackground: Color { Color(nsColor: .windowBackgroundColor) }
        /// The system separator.
        public static var separator: Color { Color(nsColor: .separatorColor) }
    }

    /// The colour for supporting text under these traits.
    ///
    /// Under Increase Contrast, "secondary" text is drawn primary: the whole point of the
    /// setting is that low-contrast greys stop being legible.
    public static func supportingTextColor(for traits: AppearanceTraits) -> Color {
        emphasis(for: traits).promotesSecondaryText ? Palette.primaryText : Palette.secondaryText
    }

    /// The tint for a status token.
    ///
    /// System colours, so they track the user's appearance and accessibility settings. Read
    /// this together with `FocusStatus.symbolName` and `FocusStatus.shape`: the tint is the
    /// third channel, never the first.
    public static func tint(for status: FocusStatus) -> Color {
        switch status {
        case .relevant: Color(nsColor: .systemGreen)
        case .uncertain: Color(nsColor: .systemYellow)
        case .unrelated: Color(nsColor: .systemRed)
        case .paused: Color(nsColor: .systemGray)
        case .onBreak: Color(nsColor: .systemTeal)
        }
    }
}

extension View {
    /// Fill a surface behind this view according to the resolved token.
    ///
    /// The two branches are deliberately different *views*, not one view with an opacity
    /// tweak: `.regularMaterial` blurs what is behind it, and the point of the opaque branch
    /// is that nothing shows through at all.
    @ViewBuilder
    public func shellSurface(_ fill: SurfaceFill, in shape: some Shape) -> some View {
        switch fill {
        case .material:
            background(.regularMaterial, in: shape)
        case .opaque:
            background(DesignTokens.Palette.windowBackground, in: shape)
        }
    }
}
