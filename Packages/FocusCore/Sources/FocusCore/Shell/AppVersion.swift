import Foundation

/// **Which build of this app a person is looking at** (focus-odz.3).
///
/// Nothing in the programme read `CFBundleShortVersionString` before this: there was no About
/// panel, no version line in Settings, and no way for somebody reporting a defect to say which
/// build they saw it in. A bug report against "Focus Sentinel" names no artefact.
///
/// ## What is in the string, and what is not
///
/// `0.1.0 (1)` — the marketing version, then the build number in brackets, which is the form
/// every Mac app's About panel uses and the form a person can read back over the phone. Both come
/// from the project file, which is this repository's single home for scalar Info.plist keys:
/// `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
///
/// **The git short hash is deliberately absent, and that is a finding rather than an omission.**
/// Baking it needs one of two project changes, and both cost more than they buy here:
///
/// * a run-script phase writing a generated Swift constant into `$DERIVED_FILE_DIR` needs that
///   file to be a compile input, and `App/` is a `PBXFileSystemSynchronizedRootGroup` — file
///   membership is directory-implicit, so there is no file reference to hang a derived source on
///   without hand-authoring one for a file that does not exist when the project is parsed;
/// * a phase rewriting the built product's `Info.plist` runs inside the window between the plist
///   being generated and the product being signed, and this repository asserts the shipped
///   plist's contents (gate stage 6a) and the product's entitlements on both configurations. A
///   build phase that edits the artefact those stages read is a change whose failure modes are
///   in the signing lane.
///
/// So this ships the two numbers that are already build settings, `README.md`'s "The project
/// file" section stays true, and `verify-project.sh` needs nothing. The hash is a later slice of
/// e10's release work, where the packaging change belongs.
public enum AppVersion {
    /// The key the marketing version is stored under.
    public static let shortVersionKey = "CFBundleShortVersionString"
    /// The key the build number is stored under.
    public static let buildKey = "CFBundleVersion"

    /// What a person is shown, given the two stored values.
    ///
    /// Taking the two strings rather than a `Bundle` is what makes this testable at all: a test
    /// bundle's `Bundle.main` is the test runner's, so a function that read one directly could
    /// only ever be asserted against whatever Xcode happened to stamp on the runner.
    ///
    /// **A missing value is drawn as `—`, never as an empty string or a silent omission.** A
    /// version line reading `0.1.0 ()` looks like a formatting bug; one reading `— (—)` says the
    /// build did not stamp itself, which is a true thing about the artefact and something
    /// somebody can act on. `NudgeSubject`'s doctrine — an empty string is worse than an
    /// identifier — is the same rule seen from the other end.
    public static func rendered(short: String?, build: String?) -> String {
        "\(present(short)) (\(present(build)))"
    }

    /// The same, read from a bundle. `Bundle.main` in the application; the caller chooses.
    public static func rendered(bundle: Bundle) -> String {
        rendered(
            short: bundle.object(forInfoDictionaryKey: shortVersionKey) as? String,
            build: bundle.object(forInfoDictionaryKey: buildKey) as? String
        )
    }

    /// What is drawn where a bundle carries nothing under the key. An em dash, which is what the
    /// Keyboard Shortcuts window already draws for an action with no key equivalent.
    public static let absent = "—"

    private static func present(_ value: String?) -> String {
        guard let value else { return absent }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? absent : trimmed
    }
}
