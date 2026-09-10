import Foundation

/// Which test lane is running, as far as localisation is concerned.
///
/// SwiftPM and Xcode treat a String Catalog differently, and the difference is not
/// cosmetic:
///
/// * `swift test` copies `Localizable.xcstrings` into the resource bundle **verbatim**.
///   Nothing compiles it, so a lookup of `status.relevant.short` returns the string
///   `"status.relevant.short"` — the key echoes itself and every localisation assertion is
///   guaranteed false.
/// * `xcodebuild test` **compiles** the catalog to `en.lproj/Localizable.strings` inside
///   the package's resource bundle, so the same lookup returns `"Relevant"`.
///
/// Every localisation-dependent test is therefore written
/// `@Test(.enabled(if: LocalizationLane.catalogsAreCompiled))`: it runs for real under the
/// gate and reports `skipped` in the inner loop. That keeps the inner loop honest instead
/// of green-by-omission, and keeps the gate strict instead of accidentally weak.
public enum LocalizationLane {
    /// True when the running bundle contains a *compiled* strings table, i.e. when the
    /// String Catalog was processed rather than copied.
    public static var catalogsAreCompiled: Bool {
        Bundle.module.url(
            forResource: "Localizable",
            withExtension: "strings",
            subdirectory: "en.lproj"
        ) != nil
            || Bundle.module.url(forResource: "Localizable", withExtension: "strings") != nil
    }

    /// The name the gate injects into the test environment through the committed
    /// `FocusUnitTests` scheme.
    public static let gateLaneEnvironmentKey = "FOCUS_GATE_LANE"

    /// True when this process is the gate lane (`xcodebuild test` via the committed
    /// scheme), rather than the inner loop.
    ///
    /// One test is gated on this and asserts `catalogsAreCompiled == true`. If a future
    /// toolchain ever stops compiling String Catalogs under xcodebuild, that test fails
    /// the gate instead of everything quietly passing.
    public static var isGateLane: Bool {
        ProcessInfo.processInfo.environment[gateLaneEnvironmentKey] == "xcodebuild"
    }
}
