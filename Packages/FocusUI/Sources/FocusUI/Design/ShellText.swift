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

    // The priority itself
    case priorityHeroEmpty = "priority.hero.empty"
    case priorityDoneWhenLabel = "priority.doneWhen.label"
    case priorityDoneWhenPrompt = "priority.doneWhen.prompt"
    case priorityActionComplete = "priority.action.complete"
    case priorityActionClear = "priority.action.clear"

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

/// How large the shell draws its text.
///
/// macOS has no injectable Dynamic Type — measured on this machine, an injected
/// `dynamicTypeSize` changes neither font size nor `@ScaledMetric` output — so the shell
/// carries its own scale. `standard` is the system's own typography, which already follows
/// the Mac's system-wide Text Size setting; the larger scale is what the snapshot and
/// pseudo-localisation lanes inject to prove the layout grows instead of truncating.
public enum ShellTextScale: String, Sendable, CaseIterable, Hashable {
    /// The system's typography, unmodified. What the app always runs at.
    case standard
    /// Roughly twice the system size — the largest accessibility text size, simulated.
    case accessibilityLarge

    public var multiplier: CGFloat {
        switch self {
        case .standard: 1
        case .accessibilityLarge: 2
        }
    }
}

extension EnvironmentValues {
    /// The text scale in force for this subtree. `standard` everywhere in the app.
    @Entry public var shellTextScale: ShellTextScale = .standard
}

extension View {
    /// Draw this subtree's text at a given scale. Used by the snapshot and
    /// pseudo-localisation lanes; the app never calls it.
    public func shellTextScale(_ scale: ShellTextScale) -> some View {
        environment(\.shellTextScale, scale)
    }
}

/// A piece of user-visible text.
///
/// Every string the shell draws goes through this view. It resolves the catalog entry, hands
/// it to whatever transform is in force, applies the shell's type role at the scale in
/// force, and draws the result — which is what makes the pseudo-localisation and
/// large-text passes properties of the real views rather than of a test-only copy of them.
public struct ShellText: View {
    private let resource: LocalizedStringResource
    private let role: DesignTokens.FontRole

    @Environment(\.shellStringTransform) private var transform
    @Environment(\.shellTextScale) private var scale

    /// A string from `FocusUI`'s own catalog.
    public init(_ key: ShellStringKey, role: DesignTokens.FontRole = .body) {
        self.resource = ShellStrings.resource(key)
        self.role = role
    }

    /// A string from some other package's catalog — the status labels, which `FocusCore`
    /// owns, are the e01 case.
    ///
    /// Labelled `resource:` deliberately. Xcode generates a typed
    /// `LocalizedStringResource` symbol for every catalog entry, so an unlabelled overload
    /// makes `ShellText(.settingsAppearanceLabel)` ambiguous between this initialiser and
    /// the key one — under `xcodebuild` only, where those symbols exist. The label is what
    /// keeps the two lanes compiling the same source.
    public init(resource: LocalizedStringResource, role: DesignTokens.FontRole = .body) {
        self.resource = resource
        self.role = role
    }

    public var body: some View {
        Text(verbatim: transform(String(localized: resource)))
            .font(DesignTokens.font(role, scale: scale))
    }
}
