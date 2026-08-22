import Foundation
import SwiftUI

/// Where every user-visible string in the shell comes from.
///
/// `FocusUI` owns a String Catalog of its own (`Sources/FocusUI/Resources/Localizable.xcstrings`)
/// and every key in it is resolved through here, against this package's bundle rather than
/// the app's. That matters twice over: the views work identically whether they are hosted by
/// the app or by a test process, and the snapshot lane can render them without an app bundle
/// existing at all.
public enum ShellStrings {
    /// This package's resource bundle — where the compiled catalog lives.
    ///
    /// Exposed because the localisation tests need to ask the *package* what a key resolves
    /// to, and `Bundle.module` inside a test target means the test bundle, not this one.
    public static var bundle: Bundle { .module }

    /// A catalog entry, as a resource the UI can draw.
    public static func resource(_ key: ShellStringKey) -> LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(key.rawValue),
            bundle: .atURL(bundle.bundleURL)
        )
    }

    /// A catalog entry, resolved to a plain `String`.
    ///
    /// Under `swift test` this returns the key itself, because SwiftPM copies String
    /// Catalogs instead of compiling them. That is exactly the trap `LocalizationLane`
    /// exists to gate assertions on — see `FocusCore.LocalizationLane`.
    public static func string(_ key: ShellStringKey) -> String {
        String(localized: resource(key))
    }
}

/// Every user-visible string `FocusUI` owns, as a typed key.
///
/// One enum rather than literals scattered through the views, for three reasons: the string
/// lint can find every key by reading this file, the catalog-completeness test can iterate
/// `allCases` instead of hardcoding a list, and a key can never be misspelled at a call site
/// without the compiler saying so.
public enum ShellStringKey: String, Sendable, CaseIterable, Hashable {
    // Window titles
    case cockpitWindowTitle = "shell.window.cockpit.title"
    case helpWindowTitle = "shell.window.help.title"

    // Menu commands
    case commandCloseWindow = "shell.command.closeWindow"
    case commandHelp = "shell.command.help"

    // Cockpit
    case cockpitHeading = "shell.cockpit.heading"
    case cockpitStoreReady = "shell.cockpit.store.ready"
    case cockpitStoreUnavailable = "shell.cockpit.store.unavailable"
    case cockpitSensingUnavailable = "shell.cockpit.sensing.unavailable"
    case cockpitOpenSettings = "shell.cockpit.openSettings"

    // Keyboard shortcuts reference
    case helpHeading = "shell.help.heading"
    case helpIntroduction = "shell.help.introduction"
    case helpColumnAction = "shell.help.column.action"
    case helpColumnShortcut = "shell.help.column.shortcut"
    case helpGroupFile = "shell.help.group.file"
    case helpGroupHelp = "shell.help.group.help"

    // Settings
    case settingsGeneralTitle = "settings.general.title"
    case settingsPrivacyTitle = "settings.privacy.title"
    case settingsAppearanceLabel = "settings.appearance.label"
    case settingsAppearanceMatchSystem = "settings.appearance.matchSystem"
    case settingsAppearanceLight = "settings.appearance.light"
    case settingsAppearanceDark = "settings.appearance.dark"
    case settingsAppearanceNote = "settings.appearance.note"
    case settingsPrivacyStatement = "settings.privacy.statement"
    case settingsPrivacyStoreLabel = "settings.privacy.storeLabel"
    case settingsPrivacyReveal = "settings.privacy.reveal"
}

/// A transform applied to a resolved string immediately before it is drawn.
///
/// The shell ships exactly one implementation — `identity` — and that is not a hedge. The
/// seam exists so the pseudo-localisation lane can push ~2× expanded strings through the
/// *same* accessor the real views use, instead of rendering a parallel set of views that
/// prove nothing about the shipping ones. Translation itself is parked (no translator in the
/// loop); pseudo-localisation is the sanctioned substitute, and it needs this hook.
public struct ShellStringTransform: Sendable {
    /// Named so a snapshot filename and a test failure can both say which transform ran.
    public let name: String
    private let body: @Sendable (String) -> String

    public init(name: String, body: @escaping @Sendable (String) -> String) {
        self.name = name
        self.body = body
    }

    public func callAsFunction(_ string: String) -> String { body(string) }

    /// The shipping transform: the catalog's own text, untouched.
    public static let identity = ShellStringTransform(name: "identity") { $0 }
}

extension EnvironmentValues {
    /// The string transform in force for this subtree. `identity` everywhere in the app.
    @Entry public var shellStringTransform: ShellStringTransform = .identity
}

extension View {
    /// Render this subtree's strings through `transform`. Used only by the
    /// pseudo-localisation lane; the app never calls it.
    public func shellStringTransform(_ transform: ShellStringTransform) -> some View {
        environment(\.shellStringTransform, transform)
    }
}

/// A piece of user-visible text.
///
/// Every string the shell draws goes through this view. It resolves the catalog entry, hands
/// it to whatever transform is in force, and draws the result — which is what makes the
/// pseudo-localisation pass a property of the real views rather than of a test-only copy of
/// them.
public struct ShellText: View {
    private let resource: LocalizedStringResource

    @Environment(\.shellStringTransform) private var transform

    /// A string from `FocusUI`'s own catalog.
    public init(_ key: ShellStringKey) {
        self.resource = ShellStrings.resource(key)
    }

    /// A string from some other package's catalog — the status labels, which `FocusCore`
    /// owns, are the e01 case.
    public init(_ resource: LocalizedStringResource) {
        self.resource = resource
    }

    public var body: some View {
        Text(verbatim: transform(String(localized: resource)))
    }
}
