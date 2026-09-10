import Foundation
import Testing

@testable import FocusCore

/// `AppearanceColorScheme` is the core-owned stand-in for `SwiftUI.ColorScheme`.
///
/// The reason it exists at all is that `FocusCore` does not — and must not — import
/// SwiftUI: a Foundation-only module fails to typecheck the moment it names `ColorScheme`
/// ("cannot find type 'ColorScheme' in scope"). The mapping between the two types lives in
/// `FocusUI` and is tested there. Here we pin down the domain type's own contract.
@Suite("AppearanceColorScheme")
struct AppearanceColorSchemeTests {
    @Test("has exactly the two cases the shell supports")
    func hasExactlyTwoCases() {
        #expect(AppearanceColorScheme.allCases.count == 2)
        #expect(AppearanceColorScheme.allCases == [.light, .dark])
    }

    @Test("raw values are stable strings, not ordinals")
    func rawValuesAreStableStrings() {
        // Persisted preferences store these. If they were ordinals, reordering the enum
        // would silently reinterpret every stored row.
        #expect(AppearanceColorScheme.light.rawValue == "light")
        #expect(AppearanceColorScheme.dark.rawValue == "dark")
        #expect(AppearanceColorScheme(rawValue: "dark") == .dark)
        #expect(AppearanceColorScheme(rawValue: "sepia") == nil)
    }

    @Test("round-trips through Codable by raw value")
    func roundTripsThroughCodable() throws {
        for scheme in AppearanceColorScheme.allCases {
            let data = try JSONEncoder().encode(scheme)
            #expect(String(decoding: data, as: UTF8.self) == "\"\(scheme.rawValue)\"")
            #expect(try JSONDecoder().decode(AppearanceColorScheme.self, from: data) == scheme)
        }
    }

    @Test("is Sendable, so it can cross the actor boundary into the UI")
    func isSendable() {
        func requireSendable<T: Sendable>(_ value: T) -> T { value }
        #expect(requireSendable(AppearanceColorScheme.dark) == .dark)
    }
}
