import AppKit

/// **The About panel, with something in it worth reading** (focus-odz.3).
///
/// SwiftUI's default `.appInfo` group already puts *About Focus Sentinel* in the app menu and
/// already opens `orderFrontStandardAboutPanel`. What it opens is a panel with an icon, a name and
/// two numbers — and for an app whose entire product claim is what it does **not** look at, the
/// one screen every Mac user knows how to find said nothing about it.
///
/// So the item is replaced rather than added: the same standard panel, with a credits paragraph
/// from the catalog, and a title that is a catalog key like every other menu item's.
///
/// ## Why the panel is AppKit's rather than a window of our own
///
/// Because it is the one every Mac app has. A bespoke About window would be a second surface to
/// theme, to size, to make keyboard-reachable and to snapshot, in exchange for nothing a person
/// asked for. `orderFrontStandardAboutPanel(options:)` takes the credits as an
/// `NSAttributedString` and draws it under the version, which is exactly the shape wanted.
///
/// ## Why the options are a value
///
/// So the unit lane can assert what is in them. Presenting the panel needs a running application
/// and would leave a window on the screen in the middle of a test; the *content* is a dictionary,
/// and a dictionary is something a test can read. `AboutPanelTests` holds the credits key against
/// the catalog, which is what stops the paragraph being dropped from the call and nobody noticing.
public enum AboutPanel {
    /// What the standard panel is handed.
    ///
    /// `nonisolated` and pure: it reads the catalog and builds a dictionary, touching no window.
    nonisolated public static func options() -> [NSApplication.AboutPanelOptionKey: Any] {
        [.credits: NSAttributedString(string: ShellStrings.string(.aboutCredits))]
    }

    /// Show it.
    @MainActor
    public static func present() {
        NSApplication.shared.orderFrontStandardAboutPanel(options: options())
    }
}
