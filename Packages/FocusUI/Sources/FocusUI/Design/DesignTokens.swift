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
/// 1. **No colour literal at a call site. Colours resolve from asset-catalogue Color Sets or
///    from system semantic colours** (focus-w41, e11 direction §5.1). This rule used to read
///    "no hardcoded colour values — every colour resolves from a semantic system colour", and
///    the amendment is deliberate rather than a relaxation. What the old wording was *for* was
///    the promise that the shell follows the user's accent colour and both appearance modes
///    without knowing anything about either; a Color Set with a light value, a dark value and a
///    High Contrast pair keeps exactly that promise, because the appearance still decides which
///    of the four cells is drawn. What it buys is that the app may own two hues of its own —
///    Spruce for a question and Kiln for drift — which the system palette cannot express: the
///    system's only "not this" colour is `systemRed`, and under U-1 an unrelated verdict is
///    neither an error nor destructive.
///
///    The rule's teeth are unchanged in the place they matter. A call site still may not write a
///    colour: `Palette.role(_:for:)` is the only way to reach one of the six, every value lives
///    in `Palette.Role.value(for:)` and in `Resources/Palette.xcassets`, and
///    `PaletteTests` compares the two **in both directions** so neither can drift.
///    Destructive actions keep `systemRed` and the running session keeps `controlAccentColor`;
///    the app ships no red of its own and no accent of its own.
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

    // MARK: - The leading-edge rule: which surface a person is looking at (focus-0nm, U-1)

    /// The width of the rule down the leading edge of a decision surface.
    ///
    /// Three points, and it is a rule rather than a border: a border says "this is a box", and
    /// what this has to say is "this is a question" or "this is a statement", at a glance, before
    /// a word is read.
    public static let decisionRuleWidth: CGFloat = 3

    /// How far the content is held off the rule.
    ///
    /// **Measured, not chosen** (focus-0nm). Drawn as a bare overlay the rule sits on the column's
    /// own leading edge, and the first render showed it painted straight through the "S" of
    /// "Safari" and the "Q" of "Quiet for" — a mark meant to say which surface this is, obscuring
    /// the words that say the same thing. The content is inset by the rule and a gap, so the two
    /// channels never occupy the same pixels.
    public static let decisionRuleInset: CGFloat = 12

    /// The tint of that rule, which is what tells the two surfaces apart.
    ///
    /// **The question and the accusation must not look alike.** U-1's whole shape is that "I
    /// cannot tell" and "this is not on your list" are different acts, and a person who has
    /// learned to answer the first must never mistake the second for it. R-96v gives them
    /// different grammar; this gives them different colour, so the distinction survives being
    /// glanced at.
    ///
    /// The status palette, not a new one: `uncertain` is already what this app's vocabulary
    /// means by "cannot tell", and `unrelated` by "not part of this". e11b remapped those two
    /// hues to Spruce and Kiln, and this function is where the remap landed — the panels were
    /// not touched for it.
    /// The popover keeps no rule — it is summoned, and the person already knows why it is there.
    public static func decisionRuleTint(
        for surface: DecisionSurface,
        traits: AppearanceTraits
    ) -> Color? {
        switch surface {
        case .accusationPanel: tint(for: .unrelated, traits: traits)
        case .questionPanel: tint(for: .uncertain, traits: traits)
        case .menuBarPopover: nil
        }
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

        /// Whether this role is drawn semibold or heavier.
        ///
        /// Read by `tintMayCarryText(_:at:traits:)`: WCAG's large-text threshold is 14 pt **bold**
        /// or 18 pt regular, so the weight is half the question and cannot be inferred from the
        /// size. Spelled as a membership test rather than a comparison because `Font.Weight` is
        /// `Equatable` and not `Comparable` — there is no `>=` to write.
        var drawsSemiboldOrHeavier: Bool {
            guard let weight else { return false }
            return [Font.Weight.semibold, .bold, .heavy, .black].contains(weight)
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

        // MARK: - The six roles (focus-w41, e11 direction §1.2)

        /// **A role in the app's own palette — named for what it does, never for what it looks
        /// like.**
        ///
        /// Five of the six are hues the system cannot express, and the sixth is the quiet ground
        /// they sit on. `Bench` and `Inlay` are grounds; `Slate`, `Mist`, `Spruce` and `Kiln` are
        /// inks. The user's accent is deliberately **not** a role here: it stays
        /// `controlAccentColor` (see `accent(for:)`), because it is the person's colour and not
        /// the app's, and a Color Set would freeze it.
        ///
        /// The neutral is biased cool, about five degrees toward green. Warm neutrals flatter,
        /// and a *friend* who accuses you forty times a day is a bad friend where an *instrument*
        /// that reports forty times is just an instrument. macOS chrome is itself a cool grey, so
        /// a cool-green ground lets an uninvited panel read as furniture of the operating system
        /// rather than as a third-party skin.
        public enum Role: String, Sendable, CaseIterable, Hashable {
            /// The ground: window and panel backgrounds.
            case bench
            /// The ink: primary text and glyph strokes.
            case slate
            /// Supporting text, hairlines, separators.
            case mist
            /// **The question.** Query-panel rule, query glyph, query body text.
            case spruce
            /// **The drift.** Accusation rule, drift glyph tint, timer digits. A lamp, never a
            /// voice — see `tintMayCarryText(_:at:traits:)`.
            case kiln
            /// The quiet inset ground: the ritual strip, and chips that must not read as buttons.
            case inlay

            /// The Color Set's name in `Resources/Palette.xcassets`.
            ///
            /// Capitalised because that is the asset-catalogue convention, and deliberately **not**
            /// a dotted name under a known namespace: `check-strings.sh` keys its "this looks like
            /// a catalog key" heuristic on dotted names under `nudge.`, `shell.` and `status.`, and
            /// an asset name that tripped it would be hunted for in a String Catalog for ever.
            public var assetName: String {
                switch self {
                case .bench: "Bench"
                case .slate: "Slate"
                case .mist: "Mist"
                case .spruce: "Spruce"
                case .kiln: "Kiln"
                case .inlay: "Inlay"
                }
            }

            /// Whether this role is a ground rather than an ink. Grounds move *away* from the ink
            /// under Increase Contrast; inks move toward it.
            public var isGround: Bool { self == .bench || self == .inlay }

            /// **The declared value of this role in this appearance.**
            ///
            /// This table and `Resources/Palette.xcassets` are the same six colours written twice,
            /// and `PaletteCatalogTests` compares them cell by cell in both directions. Two
            /// spellings are needed because they are read on different lanes: the compiled catalogue
            /// is what the *running app* draws, and it is what lets the system pick the cell for the
            /// person's own appearance and contrast settings — but SwiftPM copies an `.xcassets`
            /// rather than compiling it (the same split `LocalizationLane` records for String
            /// Catalogs), so on `swift test` there is no `Assets.car` to read and `NSColor(named:)`
            /// answers `nil`. A table that resolves in every lane is what keeps the palette
            /// *assertable* rather than only viewable.
            ///
            /// **The High Contrast pair is a measured step, not a taste.** Every role moves 18 % of
            /// the remaining distance toward its own scheme's extreme — inks toward the ink, grounds
            /// toward the ground — and 18 % is the smallest such step that carries all three text
            /// roles to 7:1 against the High Contrast ground in *both* schemes: light Mist 7.05,
            /// light Spruce 7.48, dark Mist 8.36, dark Spruce 7.96. At 16 % light Mist is 7.02 and
            /// the margin is a rounding error; at 14 % it is 6.80 and the promise is broken.
            public func value(for traits: AppearanceTraits) -> PaletteValue {
                switch (traits.colorScheme, traits.increasedContrast) {
                case (.light, false): lightValue
                case (.dark, false): darkValue
                case (.light, true): lightHighContrastValue
                case (.dark, true): darkHighContrastValue
                }
            }

            /// The light value.
            public var lightValue: PaletteValue {
                switch self {
                case .bench: PaletteValue(0xF2, 0xF4, 0xF3)
                case .slate: PaletteValue(0x1E, 0x24, 0x27)
                case .mist: PaletteValue(0x5E, 0x68, 0x66)
                case .spruce: PaletteValue(0x17, 0x6B, 0x73)
                case .kiln: PaletteValue(0xB0, 0x6A, 0x10)
                case .inlay: PaletteValue(0xE3, 0xE7, 0xE5)
                }
            }

            /// The dark value.
            public var darkValue: PaletteValue {
                switch self {
                case .bench: PaletteValue(0x19, 0x1D, 0x1F)
                case .slate: PaletteValue(0xED, 0xF1, 0xF0)
                case .mist: PaletteValue(0x98, 0xA2, 0xA0)
                case .spruce: PaletteValue(0x57, 0xA9, 0xAF)
                case .kiln: PaletteValue(0xE3, 0x9A, 0x2E)
                case .inlay: PaletteValue(0x2A, 0x30, 0x33)
                }
            }

            /// The light value under Increase Contrast.
            public var lightHighContrastValue: PaletteValue {
                switch self {
                case .bench: PaletteValue(0xF4, 0xF6, 0xF5)
                case .slate: PaletteValue(0x19, 0x1E, 0x20)
                case .mist: PaletteValue(0x4D, 0x55, 0x54)
                case .spruce: PaletteValue(0x13, 0x58, 0x5E)
                case .kiln: PaletteValue(0x90, 0x57, 0x0D)
                case .inlay: PaletteValue(0xE8, 0xEB, 0xEA)
                }
            }

            /// The dark value under Increase Contrast.
            public var darkHighContrastValue: PaletteValue {
                switch self {
                case .bench: PaletteValue(0x14, 0x18, 0x19)
                case .slate: PaletteValue(0xF0, 0xF4, 0xF3)
                case .mist: PaletteValue(0xAB, 0xB3, 0xB1)
                case .spruce: PaletteValue(0x75, 0xB8, 0xBD)
                case .kiln: PaletteValue(0xE8, 0xAC, 0x54)
                case .inlay: PaletteValue(0x22, 0x27, 0x2A)
                }
            }
        }

        /// **The one way a call site reaches one of the six.**
        ///
        /// Resolved against the injected traits for the reason the three system colours above are
        /// (focus-pq8): a dynamic `NSColor` resolves against `NSAppearance.current` at draw time,
        /// not against the traits, and the last time this file let that happen the nudge surfaces
        /// drew white text on a white background.
        public static func role(_ role: Role, for traits: AppearanceTraits) -> Color {
            Color(nsColor: nsColor(role, for: traits))
        }

        /// The same colour as an `NSColor`, for AppKit call sites and for the contrast arithmetic.
        ///
        /// The compiled catalogue first, because that is what the *shipped* app draws and what the
        /// system re-resolves when the person changes appearance mid-flight; the declared table
        /// when there is no `Assets.car` to read, which is every SwiftPM lane.
        public static func nsColor(_ role: Role, for traits: AppearanceTraits) -> NSColor {
            if let named = NSColor(named: NSColor.Name(role.assetName), bundle: .module) {
                return named.resolved(for: traits)
            }
            return role.value(for: traits).nsColor
        }

        /// **Whether this build is drawing the palette from the compiled catalogue.**
        ///
        /// The sibling of `LocalizationLane.catalogsAreCompiled`, and it exists for the same
        /// reason: SwiftPM copies an `.xcassets` into the resource bundle verbatim and there is no
        /// `Assets.car` for `NSColor(named:)` to read, while xcodebuild compiles it. Everything
        /// still *draws* — the declared table answers — but only the compiled catalogue lets the
        /// system re-resolve a colour when the person changes appearance or contrast while the app
        /// is running. Published by the self-check so the shipped build is asked the question
        /// rather than assumed to pass it.
        public static var catalogIsCompiled: Bool {
            NSColor(named: NSColor.Name(Role.bench.assetName), bundle: .module) != nil
        }
    }

    /// One palette value: eight bits per channel, sRGB, opaque.
    ///
    /// Integer channels rather than `Double`s because this is what an asset catalogue stores and
    /// what `PaletteCatalogTests` compares — a float round trip would make "the two spellings
    /// agree" a question about tolerances instead of a question about the palette.
    public struct PaletteValue: Sendable, Equatable, Hashable {
        public let red: Int
        public let green: Int
        public let blue: Int

        public init(_ red: Int, _ green: Int, _ blue: Int) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// The eight-bit sRGB components of an already-resolved colour.
        ///
        /// For the three statuses that keep a system colour: they have no declared table, so the
        /// only honest source for their components is the colour the machine is about to draw.
        /// A colour that cannot be converted to sRGB reads as black, which is a value the
        /// contrast fold will notice rather than one it will wave through.
        public init(_ color: NSColor) {
            let srgb = color.usingColorSpace(.sRGB)
            self.init(
                Int(((srgb?.redComponent ?? 0) * 255).rounded()),
                Int(((srgb?.greenComponent ?? 0) * 255).rounded()),
                Int(((srgb?.blueComponent ?? 0) * 255).rounded())
            )
        }

        /// This value as an opaque sRGB `NSColor`.
        public var nsColor: NSColor {
            NSColor(
                srgbRed: CGFloat(red) / 255,
                green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255,
                alpha: 1
            )
        }

        /// The WCAG relative luminance of this value.
        public var relativeLuminance: Double {
            func linear(_ channel: Int) -> Double {
                let value = Double(channel) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }

        /// The WCAG contrast ratio between this value and another, 1…21.
        public func contrastRatio(against other: PaletteValue) -> Double {
            let mine = relativeLuminance
            let theirs = other.relativeLuminance
            return (max(mine, theirs) + 0.05) / (min(mine, theirs) + 0.05)
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
    /// Read this together with `FocusStatus.markAssetName` and `FocusStatus.shape`: the tint is
    /// the third channel, never the first.
    ///
    /// **Two of the five moved off the system palette in e11b** (focus-w41, direction §1.2), and
    /// both moves are rulings rather than preferences:
    ///
    /// - **`unrelated` moves off `systemRed` onto Kiln.** Red is macOS's error-and-destructive
    ///   semantic, and an unrelated verdict is neither: by the app's own content rules the person
    ///   has done nothing wrong. Under U-1 the app also speaks when it is *not confident*, so the
    ///   loudest colour available would be spent on a verdict the app itself concedes it may have
    ///   got wrong.
    /// - **`uncertain` moves off `systemYellow` onto Spruce.** Yellow and amber are not a legible
    ///   distinction at 16 pt, and the one distinction that must never fail is question versus
    ///   accusation. Teal against amber is hue-opposed and survives the common colour vision
    ///   deficiencies.
    ///
    /// The other three keep their system colours, and now take the traits for the reason
    /// focus-pq8 gave: a dynamic `NSColor` read outside `resolved(for:)` follows whatever
    /// appearance happens to be current when SwiftUI rasterises it, which is not necessarily the
    /// one these traits name.
    public static func tint(for status: FocusStatus, traits: AppearanceTraits) -> Color {
        switch status {
        case .relevant: Color(nsColor: NSColor.systemGreen.resolved(for: traits))
        case .uncertain: Palette.role(.spruce, for: traits)
        case .unrelated: Palette.role(.kiln, for: traits)
        case .paused: Color(nsColor: NSColor.systemGray.resolved(for: traits))
        case .onBreak: Color(nsColor: NSColor.systemTeal.resolved(for: traits))
        }
    }

    /// **Whether this status's tint may be the colour of *text*, at this role, under these
    /// traits.**
    ///
    /// The rule the direction states in one line — *Kiln carries no body text on the light
    /// ground; it is a lamp, never a voice* — expressed as arithmetic over the palette that
    /// actually ships, so it cannot become a claim that outlives the values it was made about.
    ///
    /// Measured on the committed values: Kiln on Bench in the light scheme is **3.87:1**, which
    /// clears WCAG's 3:1 large-text threshold and misses the 4.5:1 body-text one. (The direction
    /// says "about 4.4:1" at §1.2; that figure is wrong, and wrong in the unsafe direction — the
    /// real number makes the ban *more* necessary, not less.) Spruce measures 5.61:1 and may
    /// carry text at any size.
    ///
    /// "Large text" is WCAG's own definition, which is also the one the direction uses when it
    /// says the timer digits may be Kiln at ≥ 17 pt semibold: 14 pt bold or 18 pt regular, which
    /// in points-not-CSS-pixels is **≥ 17 pt when the role is drawn semibold or heavier**, and
    /// ≥ 22 pt otherwise.
    public static func tintMayCarryText(
        _ status: FocusStatus,
        at role: FontRole,
        traits: AppearanceTraits
    ) -> Bool {
        let size = pointSize(role)
        let threshold = (role.drawsSemiboldOrHeavier && size >= 17) || size >= 22 ? 3.0 : 4.5
        return contrastAgainstBench(of: status, traits: traits) >= threshold
    }

    /// The measured contrast between a status tint and the ground it is drawn on.
    ///
    /// Public because the number is the argument: a reviewer asking "why may Kiln not carry body
    /// text" gets an answer they can check rather than a rule they have to trust.
    public static func contrastAgainstBench(
        of status: FocusStatus,
        traits: AppearanceTraits
    ) -> Double {
        paletteValue(of: status, traits: traits)
            .contrastRatio(against: Palette.Role.bench.value(for: traits))
    }

    /// A status tint as a measurable value.
    ///
    /// The two palette roles answer from the declared table; the three system colours are
    /// resolved and read back through sRGB, because a system colour has no declared table and
    /// the only honest source for its components is the one the machine will draw.
    static func paletteValue(of status: FocusStatus, traits: AppearanceTraits) -> PaletteValue {
        switch status {
        case .uncertain: Palette.Role.spruce.value(for: traits)
        case .unrelated: Palette.Role.kiln.value(for: traits)
        case .relevant: PaletteValue(NSColor.systemGreen.resolved(for: traits))
        case .paused: PaletteValue(NSColor.systemGray.resolved(for: traits))
        case .onBreak: PaletteValue(NSColor.systemTeal.resolved(for: traits))
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
    ///
    /// **The opaque branch is Bench** (focus-w41, direction §1.2). It used to be
    /// `windowBackgroundColor`, and the swap is the one place the ground the app owns is
    /// actually drawn. It reaches both kinds of opacity on purpose: an uninvited panel is opaque
    /// because it landed over whatever the person was doing, and a summoned surface goes opaque
    /// because the person asked for Reduce Transparency — and in both cases what should appear
    /// underneath the app's words is the app's own ground, cool-biased so it reads as furniture
    /// of the operating system rather than as a third-party skin.
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
            background(DesignTokens.Palette.role(.bench, for: traits), in: shape)
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
    ///
    /// **Increase Contrast is part of the appearance, not a separate switch** (focus-w41). It was
    /// not, until e11b: the four-cell Color Sets this file now resolves keep their High Contrast
    /// pair behind `NSAppearance.Name.accessibilityHighContrast{Aqua,DarkAqua}`, so a resolution
    /// that only ever named `.aqua` and `.darkAqua` could never reach two of the four cells and
    /// the High Contrast half of the palette would have been dead the day it was committed. The
    /// same correction reaches the three system colours above, which had the same hole for the
    /// same reason — `increasedContrast` traits were resolving them in plain aqua.
    func resolved(for traits: AppearanceTraits) -> NSColor {
        let name: NSAppearance.Name = switch (traits.colorScheme, traits.increasedContrast) {
        case (.light, false): .aqua
        case (.dark, false): .darkAqua
        case (.light, true): .accessibilityHighContrastAqua
        case (.dark, true): .accessibilityHighContrastDarkAqua
        }
        guard let appearance = NSAppearance(named: name) else { return self }
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(cgColor: self.cgColor)
        }
        return resolved ?? self
    }
}
