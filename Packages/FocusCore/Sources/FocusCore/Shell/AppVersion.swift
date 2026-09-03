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
/// **And the commit it was built from** — `0.1.0 (1) · a1b2c3d` (e10a). Two numbers that are the
/// same for every build of every tree tell a bug report nothing; the hash is what turns "Focus
/// Sentinel 0.1.0" into an artefact somebody can check out.
///
/// It arrives by **build-setting substitution**, which is the one route that costs nothing here.
/// `FOCUS_GIT_HASH` is a build setting with an empty default, `Config/FocusSentinel-Info.plist`
/// carries `$(FOCUS_GIT_HASH)`, and Xcode expands build settings in an `INFOPLIST_FILE` at the
/// process-plist step — which runs BEFORE signing. The two routes that were considered and
/// rejected are worth keeping written down, because both look obvious:
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
/// **An absent hash renders no suffix at all**, rather than `0.1.0 (1) · —`. It is absent for one
/// reason — the build was made without `FOCUS_GIT_HASH`, which is what a plain Xcode.app build
/// is — and that is a true and unalarming thing about a development build, unlike a missing
/// version number. The gate's `packaging` stage requires it to be present and to equal
/// `git rev-parse --short HEAD` in both configurations, so the artefact this programme ships
/// cannot lose it quietly.
public enum AppVersion {
    /// The key the marketing version is stored under.
    public static let shortVersionKey = "CFBundleShortVersionString"
    /// The key the build number is stored under.
    public static let buildKey = "CFBundleVersion"
    /// The key the commit the build came from is stored under. Not an Apple key: it is written by
    /// `Config/FocusSentinel-Info.plist` from the `FOCUS_GIT_HASH` build setting.
    public static let hashKey = "FocusGitHash"
    /// What separates the version from the commit. A middle dot with spaces, which is the
    /// separator the rest of this app's compound sentences use.
    public static let hashSeparator = " · "

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
        rendered(short: short, build: build, hash: nil)
    }

    /// The same, with the commit the build came from.
    ///
    /// An absent or blank hash renders **no suffix**, never `· —`: unlike a missing version
    /// number, a build with no hash is an ordinary Xcode.app build and saying so with a dash
    /// would read as damage.
    public static func rendered(short: String?, build: String?, hash: String?) -> String {
        let version = "\(present(short)) (\(present(build)))"
        guard let trimmed = trimmedOrNil(hash) else { return version }
        return version + hashSeparator + trimmed
    }

    /// The same, read from a bundle. `Bundle.main` in the application; the caller chooses.
    public static func rendered(bundle: Bundle) -> String {
        rendered(
            short: bundle.object(forInfoDictionaryKey: shortVersionKey) as? String,
            build: bundle.object(forInfoDictionaryKey: buildKey) as? String,
            hash: hash(bundle: bundle)
        )
    }

    /// The commit a bundle says it was built from, or `nil` where it says nothing.
    public static func hash(bundle: Bundle) -> String? {
        trimmedOrNil(bundle.object(forInfoDictionaryKey: hashKey) as? String)
    }

    /// What is drawn where a bundle carries nothing under the key. An em dash, which is what the
    /// Keyboard Shortcuts window already draws for an action with no key equivalent.
    public static let absent = "—"

    private static func trimmedOrNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func present(_ value: String?) -> String {
        guard let value else { return absent }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? absent : trimmed
    }
}
