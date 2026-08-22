import FocusCore
import SwiftUI

/// The one and only place in this repository where `FocusCore.AppearanceColorScheme` and
/// `SwiftUI.ColorScheme` meet.
///
/// `FocusCore` cannot name `SwiftUI.ColorScheme` at all — it is a Foundation-only module
/// and the compiler rejects the type outright — so the domain owns its own two-case enum
/// and the translation lives here, in the only package that is allowed to import SwiftUI
/// *and* the domain. Keeping it to one file, covered by one test, is what stops the two
/// vocabularies drifting.
extension AppearanceColorScheme {
    /// The SwiftUI colour scheme this domain value denotes.
    public var swiftUI: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }

    /// The domain value denoted by a SwiftUI colour scheme.
    ///
    /// `ColorScheme` is a non-frozen system enum, so a future macOS could add a case. It
    /// maps to `.light` here, which is the safe default: a shell that renders light on an
    /// unknown scheme is legible; one that renders dark on a light background is not.
    public init(_ scheme: ColorScheme) {
        switch scheme {
        case .light: self = .light
        case .dark: self = .dark
        @unknown default: self = .light
        }
    }
}

/// Carries `AppearanceTraits` down the view tree.
///
/// The default is `systemDefault` rather than a reading of the live system, and that is
/// the point: the traits are *injected*. On this machine every accessibility setting is
/// off, so if views read `NSWorkspace` directly, four of the five appearance variants could
/// never be rendered without changing the developer's own System Settings. Injected, the
/// snapshot lane sets each variant in one line and the live app behaves identically.
extension EnvironmentValues {
    @Entry public var appearanceTraits: AppearanceTraits = .systemDefault
}

extension View {
    /// Inject a complete set of appearance traits. Used by the app's appearance observer
    /// and, identically, by the snapshot harness.
    public func appearanceTraits(_ traits: AppearanceTraits) -> some View {
        environment(\.appearanceTraits, traits)
            .environment(\.colorScheme, traits.colorScheme.swiftUI)
    }
}
