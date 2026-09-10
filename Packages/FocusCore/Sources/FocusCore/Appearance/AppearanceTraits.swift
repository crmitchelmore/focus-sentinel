import Foundation

/// The colour scheme, expressed as a domain value.
///
/// This is **not** `SwiftUI.ColorScheme`, and it may not be. `FocusCore` imports only
/// Foundation, SwiftData and os; a Foundation-only module cannot even name
/// `SwiftUI.ColorScheme` ("cannot find type 'ColorScheme' in scope"). The one mapping
/// between the two types lives in `FocusUI`, is covered by a test, and is the only place
/// in the repository where they meet.
public enum AppearanceColorScheme: String, Sendable, CaseIterable, Codable, Hashable {
    case light
    case dark
}

/// Everything the UI needs to know about how it should look, as a plain value.
///
/// The five fields are read at runtime from `NSWorkspace.shared.accessibilityDisplay*`
/// plus the resolved colour scheme, republished on
/// `accessibilityDisplayOptionsDidChangeNotification`, and injected into the SwiftUI
/// environment by the app.
///
/// Why a value type rather than letting views read the system directly: on the machine
/// this app is built on, every accessibility setting is `false`. If views read the system,
/// four of the five appearance variants could never be exercised without mutating the
/// developer's own System Settings. Injected as a value, the snapshot lane sets each
/// variant in one line, deterministically, and the live app behaves identically.
public struct AppearanceTraits: Sendable, Equatable, Hashable, Codable {
    public var colorScheme: AppearanceColorScheme
    /// System Settings → Accessibility → Display → Increase contrast.
    public var increasedContrast: Bool
    /// System Settings → Accessibility → Display → Reduce transparency.
    /// When true, materials collapse to opaque fills.
    public var reduceTransparency: Bool
    /// System Settings → Accessibility → Display → Reduce motion.
    /// When true, no animation may be the sole carrier of meaning.
    public var reduceMotion: Bool
    /// System Settings → Accessibility → Display → Differentiate without colour.
    /// When true, a status label is always shown alongside its glyph.
    public var differentiateWithoutColor: Bool

    public init(
        colorScheme: AppearanceColorScheme = .light,
        increasedContrast: Bool = false,
        reduceTransparency: Bool = false,
        reduceMotion: Bool = false,
        differentiateWithoutColor: Bool = false
    ) {
        self.colorScheme = colorScheme
        self.increasedContrast = increasedContrast
        self.reduceTransparency = reduceTransparency
        self.reduceMotion = reduceMotion
        self.differentiateWithoutColor = differentiateWithoutColor
    }

    /// A light appearance with every accessibility setting off — what an untouched Mac
    /// reports.
    public static let systemDefault = AppearanceTraits()
}

extension AppearanceTraits {
    /// The `light` variant of the snapshot matrix.
    public static let light = AppearanceTraits(colorScheme: .light)
    /// The `dark` variant of the snapshot matrix.
    public static let dark = AppearanceTraits(colorScheme: .dark)
    /// The `increasedContrast` variant of the snapshot matrix.
    public static let increasedContrast = AppearanceTraits(
        colorScheme: .light,
        increasedContrast: true
    )
    /// The `reduceTransparency` variant of the snapshot matrix.
    public static let reduceTransparency = AppearanceTraits(
        colorScheme: .light,
        reduceTransparency: true
    )
    /// The `reduceMotion` variant of the snapshot matrix.
    public static let reduceMotion = AppearanceTraits(
        colorScheme: .light,
        reduceMotion: true
    )
}

/// A named point in the appearance matrix. Named rather than anonymous so a snapshot file
/// name and a test failure both say which variant they mean.
public struct AppearanceVariant: Sendable, Equatable, Hashable {
    public let name: String
    public let traits: AppearanceTraits

    public init(name: String, traits: AppearanceTraits) {
        self.name = name
        self.traits = traits
    }
}

extension AppearanceTraits {
    /// The five variants every shell component is rendered under. Ordered, so snapshot
    /// output is stable.
    public static let namedVariants: [AppearanceVariant] = [
        AppearanceVariant(name: "light", traits: .light),
        AppearanceVariant(name: "dark", traits: .dark),
        AppearanceVariant(name: "increasedContrast", traits: .increasedContrast),
        AppearanceVariant(name: "reduceTransparency", traits: .reduceTransparency),
        AppearanceVariant(name: "reduceMotion", traits: .reduceMotion)
    ]
}
