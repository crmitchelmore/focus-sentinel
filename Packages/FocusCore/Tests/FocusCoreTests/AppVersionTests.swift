import Foundation
import Testing

@testable import FocusCore

/// **Which build a person is looking at** (focus-odz.3).
///
/// Nothing in the programme read `CFBundleShortVersionString` before this, so a defect report
/// against "Focus Sentinel" named no artefact. The rendering is a pure function of two strings
/// rather than a read of `Bundle.main`, and that is what makes it assertable at all: a test
/// bundle's `Bundle.main` is the test runner's, so a function that read one directly could only
/// ever be held against whatever Xcode stamped on the runner.
///
/// What the *app's* bundle actually carries is the self-check's, which reads it in the shipping
/// process and pins the sentence the Settings pane drew against it.
@Suite("The version a person can quote")
struct AppVersionTests {
    @Test("the sentence is the marketing version with the build in brackets")
    func theShape() {
        #expect(AppVersion.rendered(short: "0.1.0", build: "1") == "0.1.0 (1)")
        #expect(AppVersion.rendered(short: "1.2.3", build: "4096") == "1.2.3 (4096)")
    }

    /// **A missing value is drawn, not omitted.**
    ///
    /// `0.1.0 ()` looks like a formatting bug; `0.1.0 (—)` says the build did not stamp itself,
    /// which is a true thing about the artefact and something somebody can act on. It is
    /// `NudgeSubject`'s doctrine — an empty string is worse than an identifier — from the other
    /// end, and it is why this does not answer `nil` and let a view decide.
    @Test("a value the bundle does not carry is drawn as an em dash")
    func absentValuesAreDrawn() {
        #expect(AppVersion.rendered(short: nil, build: "1") == "— (1)")
        #expect(AppVersion.rendered(short: "0.1.0", build: nil) == "0.1.0 (—)")
        #expect(AppVersion.rendered(short: nil, build: nil) == "— (—)")
        // An empty or whitespace value is a missing one: a plist key present and blank is the
        // same fact about the build as a key that is not there.
        #expect(AppVersion.rendered(short: "", build: "  ") == "— (—)")
    }

    /// Whitespace around a real value is stripped, because it is a build setting somebody typed.
    @Test("a value is trimmed but never otherwise rewritten")
    func valuesAreTrimmedOnly() {
        #expect(AppVersion.rendered(short: "  0.1.0 ", build: " 1 ") == "0.1.0 (1)")
        // Not parsed, not reformatted: whatever the project says is what a person is shown.
        #expect(AppVersion.rendered(short: "0.1.0-rc.2", build: "abc") == "0.1.0-rc.2 (abc)")
    }

    /// The bundle-reading overload is the same function, and a bundle carrying neither key is the
    /// case every test process is in — so this is the one arm a unit lane can drive honestly.
    @Test("a bundle carrying neither key renders as two em dashes")
    func aBundleWithNothingInIt() {
        #expect(AppVersion.rendered(bundle: Bundle(for: Marker.self)) == "\(AppVersion.absent) (\(AppVersion.absent))")
    }

    /// Something whose bundle is this test bundle, which has no `CFBundleShortVersionString`.
    private final class Marker {}
}
