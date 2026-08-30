import AppKit
import Foundation

/// **What an application on this Mac is called** (P-67, focus-7gc).
///
/// Resolved through `NSWorkspace` with **no grant of any kind** (probe P-67): a bundle
/// identifier becomes a real name and a real icon, and an identifier that is not installed
/// resolves to `nil` — which is a first-class state the chip draws, not a blank space.
///
/// ## Why this is not `NSRunningApplication.localizedName`
///
/// Every surface that draws a stored subject draws one the person is **not** in right now: a
/// rule they wrote weeks ago, an application they excluded from presentation detection, the
/// anchor *"Back to …"* would launch. `NSRunningApplication` has nothing to say about any of
/// them, and the seam that asks it — `ReturnWorkspace.localizedNameOfRunningApplication(_:)` —
/// answers `nil` the moment the subject quits. LaunchServices answers from the disk either way.
///
/// ## Which of the three names a bundle has
///
/// A bundle can be asked its name three ways and they do not always agree. Measured on this Mac
/// over all 43 running bundles, against `NSRunningApplication.localizedName` — the name the
/// *running* branch of every one of these surfaces draws, and therefore the answer the not-
/// running branch has to match if the sentence is not to change when the subject quits:
///
/// | source | agrees |
/// |---|---|
/// | `CFBundleDisplayName`/`CFBundleName`, localised dictionary first | 40 / 43 |
/// | `FileManager.displayName(atPath:)` | 35 / 43 |
///
/// So the bundle's own declaration is asked first and the file name is the fallback. Every
/// disagreement measured was a background agent (`AccessibilityUIServer` → *"Accessibility"*,
/// `WiFiAgent` → *"Wi-Fi"*); every `.regular` application agreed under both. The three the
/// bundle read still misses are LaunchServices' own en-GB spellings — *"Control Centre"* for a
/// bundle whose `Info.plist` says *"Control Center"* — which no read of the disk reproduces.
///
/// The cost is a bundle the person renamed in the Finder: `displayName` follows the rename and
/// the `Info.plist` does not. That is the right trade here, because the name this has to agree
/// with is the running one, and the running one does not follow the rename either.
enum InstalledApplication {
    struct Info {
        let name: String
        let icon: NSImage?
    }

    static func info(bundleID: String) -> Info? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return Info(
            // The identifier is the last resort and never an empty chip, exactly as
            // `NudgeSubject` decides for the sentence.
            name: name(at: url) ?? bundleID,
            icon: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        )
    }

    /// What the application with this bundle identifier is called, or `nil` when nothing on this
    /// Mac answers to it — or when what answers has no name to give.
    ///
    /// The shape every caller wants: `nil` means *"there is nothing better than the key"*, which
    /// is what `NudgeSubject.named(_:runningName:)` takes.
    static func name(bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return name(at: url)
    }

    /// What the bundle **at this URL** is called, or `nil` when it has nothing to say.
    ///
    /// `ReturnToTask` reaches this one: it has already fetched the URL to decide the target is
    /// installed at all, and asking again by identifier would be a second lookup that could
    /// disagree with the first.
    ///
    /// Two answers it is not allowed to hand back, both measured on this Mac:
    ///
    ///  * **the extension.** `FileManager.displayName` honours *"Show all filename extensions"*,
    ///    so with that setting on the same bundle is *"Safari.app"* here and *"Safari"* through
    ///    `NSRunningApplication`. Measured with the setting off (this Mac's default): a
    ///    directory named `Foo.app` answers `"Foo"`. The suffix is dropped when it is still
    ///    there, so both Macs get the same sentence.
    ///  * **whitespace.** Measured: a bundle named `"Bar  .app"` answers `"Bar  "`, and one
    ///    named `"   .app"` answers `"   "`. A name made only of spaces is not a name — it is an
    ///    empty sentence with a bug in it — so it answers `nil` and the caller falls back to the
    ///    key.
    static func name(at url: URL) -> String? {
        let candidates = [declaredName(at: url), fileName(at: url)]
        for candidate in candidates {
            guard let candidate else { continue }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// The name the bundle declares for itself, localised where it has a localisation.
    ///
    /// `CFBundleDisplayName` before `CFBundleName` because that is the order the platform reads
    /// them in, and the localised dictionary before the raw one for the same reason: it is the
    /// person's language that decides what they call it.
    private static func declaredName(at url: URL) -> String? {
        guard let bundle = Bundle(url: url) else { return nil }
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let localised = bundle.localizedInfoDictionary?[key] as? String { return localised }
            if let declared = bundle.infoDictionary?[key] as? String { return declared }
        }
        return nil
    }

    /// The file name, with the bundle extension off it.
    private static func fileName(at url: URL) -> String? {
        let displayed = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
        let ext = url.pathExtension
        guard !ext.isEmpty, displayed.lowercased().hasSuffix(".\(ext.lowercased())") else {
            return displayed
        }
        return String(displayed.dropLast(ext.count + 1))
    }
}
