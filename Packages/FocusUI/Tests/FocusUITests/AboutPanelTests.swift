import AppKit
import FocusCore
import Testing

@testable import FocusUI

/// **The About panel's content** (focus-odz.3).
///
/// SwiftUI's default app-menu item already opened `orderFrontStandardAboutPanel`, so the defect
/// was never that the item did nothing — it was that the panel it opened said nothing. For an app
/// whose whole product claim is what it does *not* look at, the one screen every Mac user knows
/// how to find carried an icon, a name and two numbers.
///
/// Presenting the panel needs a running application and would leave a window on the screen in the
/// middle of a test; the option dictionary is a value, so that is what is held here. Whether the
/// paragraph **resolves** — rather than answering its own key back — is the self-check's, because
/// under `swift test` SwiftPM copies String Catalogs instead of compiling them.
@Suite("The About panel")
struct AboutPanelTests {
    @Test("the panel is handed credits, under the key AppKit reads them from")
    func creditsAreSupplied() {
        let options = AboutPanel.options()
        let credits = options[.credits] as? NSAttributedString
        #expect(credits != nil, "the standard panel would draw nothing but the version")
        #expect(credits?.string == ShellStrings.string(.aboutCredits))
    }

    /// One key and no others: an option this app does not mean to override — `applicationName`,
    /// `version` — handed over by accident would replace what the bundle says with a literal.
    @Test("nothing but the credits is overridden")
    func onlyTheCreditsAreOverridden() {
        #expect(Array(AboutPanel.options().keys) == [.credits])
    }

    /// The paragraph is in the catalog, is drawn by nothing else, and says the thing the product
    /// is about. The wording is asserted in the shipping process by the self-check, where the
    /// catalog is compiled; this is the structural half — a key that exists and is reached.
    @Test("the credits key is the one the catalog declares")
    func theCreditsKeyIsDeclared() {
        #expect(ShellStringKey.aboutCredits.rawValue == "shell.about.credits")
        #expect(ShellStringKey.allCases.contains(.aboutCredits))
        #expect(ShellStringKey.allCases.contains(.commandAbout))
    }
}
