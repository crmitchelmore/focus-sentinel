import FocusCore
import SwiftUI
import Testing

@testable import FocusUI

/// The colour-scheme mapping is the only place the domain vocabulary and the SwiftUI
/// vocabulary meet, so it is the only place they can drift. This suite pins it shut.
@Suite("Appearance environment")
struct AppearanceEnvironmentTests {
    @Test("domain scheme maps to the SwiftUI scheme it names")
    func domainSchemeMapsToSwiftUI() {
        #expect(AppearanceColorScheme.dark.swiftUI == .dark)
        #expect(AppearanceColorScheme.light.swiftUI == .light)
    }

    @Test("SwiftUI scheme maps back to the domain scheme it names")
    func swiftUISchemeMapsToDomain() {
        #expect(AppearanceColorScheme(.dark) == .dark)
        #expect(AppearanceColorScheme(.light) == .light)
    }

    @Test("the mapping round-trips in both directions for every case")
    func mappingRoundTrips() {
        for scheme in AppearanceColorScheme.allCases {
            #expect(AppearanceColorScheme(scheme.swiftUI) == scheme)
        }
        for scheme in [ColorScheme.light, .dark] {
            #expect(AppearanceColorScheme(scheme).swiftUI == scheme)
        }
    }

    @Test("the environment default is the system default, not a live system reading")
    func environmentDefaultIsSystemDefault() {
        var values = EnvironmentValues()
        #expect(values.appearanceTraits == AppearanceTraits.systemDefault)

        values.appearanceTraits = .dark
        #expect(values.appearanceTraits.colorScheme == .dark)
    }

    @Test("every snapshot variant can be injected and read back")
    func everyVariantIsInjectable() {
        for variant in AppearanceTraits.namedVariants {
            var values = EnvironmentValues()
            values.appearanceTraits = variant.traits
            #expect(values.appearanceTraits == variant.traits)
        }
    }
}
