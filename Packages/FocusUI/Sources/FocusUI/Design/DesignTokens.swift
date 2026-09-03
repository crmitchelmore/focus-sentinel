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

/// **Who asked for this surface to be on the screen.**
///
/// The axis exists because Reduce Transparency is not the only reason a fill must be opaque
/// (focus-0nm, U-1). A window the person opened sits over whatever they left behind and a
/// material reading through it is the system's own idiom. A window the *app* raised sits over
/// whatever happened to be in front — a video at full screen, a bright document, another app's
/// dark chrome — and the same material makes the app's own words compete with the very thing it
/// is interrupting the person about. This app interrupts more than most software; a nudge that
/// is hard to read over a decoy is a nudge that costs the person twice.
///
/// It is a fact about the surface, not about the person's settings, which is why it is a
/// separate parameter rather than another trait: no accessibility switch should be able to turn
/// it off, and no future trait should be able to make an uninvited surface translucent again.
public enum SurfaceProvenance: String, Sendable, Equatable, Hashable, CaseIterable {
    /// The person asked for it: a settings pane, a popover under the status item they clicked,
    /// a badge inside a window they opened.
    case summoned
    /// The app raised it. Today that is the nudge panel and nothing else.
    case uninvited
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

    /// The fill a raised surface should use, given who raised it and under these traits.
    ///
    /// Two independent reasons to be opaque, and the axes are `or`-ed rather than ranked.
    ///
    /// Reduce Transparency is not a suggestion: a material that stays translucent when the user
    /// has asked for opacity is a defect, not a style choice. And an **uninvited** surface is
    /// opaque whatever the traits say (focus-0nm): it appears over whatever was in front, which
    /// under U-1 is by definition the thing the app is interrupting the person about, and a
    /// material lets that thing read through the sentence explaining it.
    ///
    /// So `uninvited` resolves `.opaque` in all four cells of {provenance} × {reduceTransparency}
    /// and `summoned` keeps the answer this token has always given. There is **no default** for
    /// the provenance: a surface that did not say who raised it is a surface nobody decided
    /// about, and the next uninvited one would inherit the summoned answer in silence.
    public static func material(
        for traits: AppearanceTraits,
        provenance: SurfaceProvenance
    ) -> SurfaceFill {
        if provenance == .uninvited { return .opaque }
        return traits.reduceTransparency ? .opaque : .material
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

    // MARK: - Typography

    /// The shell's type roles. Semantic, never a point size at a call site.
    ///
    /// `priorityHero` is the only role that is not one of the system's text styles, and it is
    /// declared here rather than written at a call site for exactly the reason the rest of
    /// this file exists: F-02 promises that the priority is *always* more prominent than
    /// anything else on the screen, and a promise that lives in one view's modifier chain is
    /// one refactor away from being false. Declared as a role, it is comparable — and
    /// `TypeHierarchyTests` asserts `priorityHero > largeTitle ≥ every other role`, so no
    /// later epic can give a secondary surface a bigger font without failing the gate.
    public enum FontRole: String, Sendable, CaseIterable, Hashable {
        /// The priority intent, and nothing else in the whole package.
        case priorityHero
        case largeTitle
        case title2
        case title3
        case headline
        case body
        case callout
        case caption
        case footnote

        /// The system's own font for this role — what the shell draws normally.
        ///
        /// Every role but the hero is a semantic system font, so the shell follows the Mac's
        /// own typography — including the system-wide Text Size setting — with no point size
        /// written down. The hero cannot be one: there is no system text style larger than
        /// `.largeTitle`, so it is derived *from* `.largeTitle`'s current size rather than
        /// hardcoded, and grows with the system setting for the same reason the others do.
        var system: Font {
            switch self {
            case .priorityHero:
                .system(
                    size: NSFont.preferredFont(forTextStyle: .largeTitle).pointSize * Self.heroScale,
                    weight: .semibold
                )
            case .largeTitle: .largeTitle
            case .title2: .title2
            case .title3: .title3
            case .headline: .headline
            case .body: .body
            case .callout: .callout
            case .caption: .caption
            case .footnote: .footnote
            }
        }

        /// The AppKit text style this role corresponds to, used to ask the system for the
        /// role's current point size rather than hardcoding one.
        var appKitStyle: NSFont.TextStyle {
            switch self {
            case .priorityHero, .largeTitle: .largeTitle
            case .title2: .title2
            case .title3: .title3
            case .headline: .headline
            case .body: .body
            case .callout: .callout
            case .caption: .caption1
            case .footnote: .footnote
            }
        }

        /// How much larger than its AppKit text style this role is drawn. `1` everywhere but
        /// the hero.
        var pointSizeMultiplier: CGFloat {
            switch self {
            case .priorityHero: Self.heroScale
            default: 1
            }
        }

        /// The weight this role forces, or `nil` to inherit — which is what every system
        /// role does, so that a call site's own `.fontWeight(_:)` still wins.
        var weight: Font.Weight? {
            switch self {
            case .priorityHero: .semibold
            default: nil
            }
        }

        /// The hero's factor over `largeTitle`. One number, in one place, named.
        static let heroScale: CGFloat = 1.6
    }

    /// The point size a role resolves to right now, at a given scale.
    ///
    /// Public because the type hierarchy is an *assertion*, not a taste: the hero has to be
    /// provably larger than every other role, and the app's own `--focus-self-check` reports
    /// the same two numbers at runtime. Comparing `Font` values could never do either — two
    /// `Font`s are opaque and only equatable, never ordered.
    public static func pointSize(_ role: FontRole, scale: ShellTextScale = .standard) -> CGFloat {
        NSFont.preferredFont(forTextStyle: role.appKitStyle).pointSize
            * role.pointSizeMultiplier
            * scale.multiplier
    }

    /// The font for a role at a given text scale.
    ///
    /// At `.standard` this is the *semantic* system font — `Font.body`, `Font.largeTitle` —
    /// so the shell follows the Mac's own typography, including the system-wide Text Size
    /// setting, with no point size written down anywhere.
    ///
    /// At a larger scale the base size is asked of the system
    /// (`NSFont.preferredFont(forTextStyle:).pointSize`) and multiplied, so there is still
    /// no hardcoded size — the scale is a factor applied to whatever the system says the
    /// role is worth today.
    ///
    /// **Why this exists at all.** macOS has no injectable Dynamic Type: measured on this
    /// machine, `.environment(\.dynamicTypeSize, .accessibility5)` and
    /// `.dynamicTypeSize(.accessibility5)` change neither text size nor `@ScaledMetric`
    /// output — a paragraph renders at exactly the same pixel height at `.large` and at
    /// `.accessibility5`. Injecting a scale is therefore the only way to prove that the
    /// shell survives large text without mutating the developer's own System Settings, and
    /// proving it by injection is the same doctrine `AppearanceTraits` already follows.
    public static func font(_ role: FontRole, scale: ShellTextScale = .standard) -> Font {
        guard scale != .standard else { return role.system }
        let size = pointSize(role, scale: scale)
        // The weight is applied only where the role forces one. Passing `.regular` for the
        // system roles would override a call site's own `.fontWeight(.semibold)`, which is
        // how the cockpit heading and the help headings are drawn.
        guard let weight = role.weight else { return .system(size: size) }
        return .system(size: size, weight: weight)
    }

    /// Spacing that grows with the text around it.
    ///
    /// `@ScaledMetric` is the documented mechanism and is used throughout the shell, but it
    /// is inert on macOS for the same reason the fonts are: it keys on `dynamicTypeSize`.
    /// Where spacing must visibly track the injected scale, it goes through here.
    public static func spacing(_ base: CGFloat, scale: ShellTextScale = .standard) -> CGFloat {
        base * scale.multiplier
    }

    // MARK: - Colour

    /// Semantic colours, resolved from the system.
    ///
    /// Colour is always an *additional* channel in this shell — every status also carries a
    /// distinct symbol, a distinct silhouette and a label — so nothing here is load-bearing
    /// on its own.
    public enum Palette {
        /// Primary label colour.
        ///
        /// A SwiftUI semantic colour, so it resolves against the environment's `colorScheme` —
        /// which `appearanceTraits(_:)` sets. It needs no traits argument because it already
        /// follows the injected value.
        public static var primaryText: Color { .primary }
        /// Supporting label colour. SwiftUI semantic, as above.
        public static var secondaryText: Color { .secondary }

        /// **The AppKit-backed colours, resolved against the injected traits** (focus-pq8).
        ///
        /// These three wrap AppKit *dynamic* system colours, and a dynamic `NSColor` resolves
        /// against `NSAppearance.current` at draw time — not against SwiftUI's `colorScheme`, and
        /// so not against `AppearanceTraits` at all. That split is the defect: under `.dark`
        /// traits the labels above went white while `windowBackgroundColor` stayed light, and the
        /// nudge surfaces drew **white text on a white background**.
        ///
        /// It is not only a test-lane artefact. The rule this file states at the top is that every
        /// appearance value is read from injected traits and never from the system; these were the
        /// three that quietly read the system, so the moment the app's own traits and the window's
        /// `NSAppearance` disagreed — which is exactly what happened while the nudge panel was
        /// pinned to `.systemDefault` — the person got a panel drawn half in one scheme and half
        /// in the other.
        ///
        /// Taking the traits is what makes them obey the same rule as everything else.
        public static func accent(for traits: AppearanceTraits) -> Color {
            Color(nsColor: NSColor.controlAccentColor.resolved(for: traits))
        }

        /// The window's own background.
        public static func windowBackground(for traits: AppearanceTraits) -> Color {
            Color(nsColor: NSColor.windowBackgroundColor.resolved(for: traits))
        }

        /// The system separator.
        public static func separator(for traits: AppearanceTraits) -> Color {
            Color(nsColor: NSColor.separatorColor.resolved(for: traits))
        }
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

    /// The tint for a session phase.
    ///
    /// Read this together with `SessionPhaseBadge.symbolName(for:)` and the badge's label, which
    /// is never hidden: the tint is the third channel here too, and never the first. `.focus`
    /// takes the user's own accent colour because it is the state the app exists to protect;
    /// every other phase takes a system colour rather than a shade of it, so the six are told
    /// apart by hue as well as by glyph for anyone who does use colour.
    public static func tint(for phase: SessionPhase, traits: AppearanceTraits) -> Color {
        switch phase {
        case .focus: Palette.accent(for: traits)
        case .intentionalDetour: Color(nsColor: .systemOrange)
        case .onBreak: Color(nsColor: .systemTeal)
        case .paused: Color(nsColor: .systemGray)
        case .interrupted: Color(nsColor: .systemRed)
        case .complete: Color(nsColor: .systemGreen)
        }
    }

    /// The tint for a capability state.
    ///
    /// Four of the five are drawn in supporting grey on purpose. Only `.available` is coloured,
    /// because the Privacy surface must not turn "you said no" into a red warning the person is
    /// invited to fix — a coloured alarm beside a denial is a call to action in disguise, which
    /// F-126 forbids outright. `.denied`, `.restricted`, `.unavailable` and `.notRequested` are
    /// facts stated plainly, and the surface offers nothing to press.
    public static func tint(for state: CapabilityState) -> Color {
        switch state {
        case .available: Color(nsColor: .systemGreen)
        case .denied, .restricted, .unavailable, .notRequested: Palette.secondaryText
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
    public func shellSurface(
        _ fill: SurfaceFill,
        in shape: some Shape,
        traits: AppearanceTraits
    ) -> some View {
        switch fill {
        case .material:
            background(.regularMaterial, in: shape)
        case .opaque:
            background(DesignTokens.Palette.windowBackground(for: traits), in: shape)
        }
    }
}

extension NSColor {
    /// **This dynamic colour, resolved for the scheme the traits name** (focus-pq8).
    ///
    /// `NSAppearance.performAsCurrentDrawingAppearance` makes the appearance current for the
    /// duration of the block, and reading `cgColor` inside it collapses a dynamic colour to the
    /// concrete one that appearance would draw. Round-tripping that through `NSColor(cgColor:)`
    /// is what produces a colour that no longer depends on whatever appearance happens to be
    /// current when SwiftUI later rasterises it.
    ///
    /// Falls back to `self` when the appearance cannot be made or the round trip fails: an
    /// unresolvable colour is better drawn in the system's own scheme than not at all.
    func resolved(for traits: AppearanceTraits) -> NSColor {
        let name: NSAppearance.Name = traits.colorScheme == .dark ? .darkAqua : .aqua
        guard let appearance = NSAppearance(named: name) else { return self }
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(cgColor: self.cgColor)
        }
        return resolved ?? self
    }
}
