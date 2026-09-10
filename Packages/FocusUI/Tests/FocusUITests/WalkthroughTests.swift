import FocusCore
import Testing

@testable import FocusUI

/// **The walkthrough's pages are a closed vocabulary, and this holds it closed** (focus-u6de).
///
/// What a unit process can prove about a sheet is what it is built from: the page order, the
/// keys each page draws, and that the catalog and the pages agree in both directions. What it
/// cannot prove is the picture, which is the snapshot lane's, and the presentation over the
/// cockpit, which `FirstRunExplanationTests` holds through the composition root.
@Suite("The walkthrough")
struct WalkthroughTests {
    /// **The first page is the privacy statement, unchanged.** focus-odz.7 shipped one screen
    /// that says what the app looks at; every claim the product rests on is on it, and a
    /// walkthrough that opened on anything else would be putting the features before the
    /// posture.
    @Test("the first page is the first-run explanation, with its store path")
    func theFirstPageIsThePrivacyStatement() {
        let first = WalkthroughPage.first
        #expect(first == .watches)
        #expect(first.titleKey == .firstRunTitle)
        #expect(first.paragraphs.map(\.key) == [.firstRunObserves, .firstRunNever, .firstRunPermissions])
        #expect(first.showsStoreLocation)
        for page in WalkthroughPage.allCases where page != first {
            #expect(!page.showsStoreLocation, "\(page.rawValue) draws the store path")
        }
    }

    @Test("the pages read in the order a person meets the app")
    func thePagesAreInOrder() {
        #expect(WalkthroughPage.allCases == [
            .watches, .priority, .time, .desk, .nudges, .menuBar, .settings
        ])
        #expect(WalkthroughPage.last == .settings)
    }

    /// Every page has a heading and something under it. A page with no paragraphs would be a
    /// title and two buttons.
    @Test("every page has a title and at least one paragraph, each with a symbol")
    func everyPageHasContent() {
        for page in WalkthroughPage.allCases {
            #expect(!page.paragraphs.isEmpty, "\(page.rawValue) is empty")
            for paragraph in page.paragraphs {
                #expect(!paragraph.symbol.isEmpty, "\(paragraph.key.rawValue) has no symbol")
            }
        }
    }

    /// One sentence, one page. A paragraph drawn on two pages is a paragraph somebody will read
    /// twice and wonder whether the second is different.
    @Test("no key is drawn on two pages")
    func keysAreUnique() {
        let keys = WalkthroughPage.allCases.flatMap { page in
            [page.titleKey] + page.paragraphs.map(\.key)
        }
        #expect(Set(keys).count == keys.count)
    }

    /// **The bijection over the catalog prefix.** Every `shell.walkthrough.` key that is not
    /// chrome is drawn by exactly one page, and every page key is in the catalog's namespace or is
    /// one of the four first-run keys the first page reuses. A key added to the catalog without a
    /// page fails here; a page naming a key outside the namespace fails here.
    @Test("every walkthrough key in the catalog belongs to exactly one page, or is chrome")
    func catalogAndPagesAgree() {
        let chrome: Set<ShellStringKey> = [
            .walkthroughBack, .walkthroughNext, .walkthroughDone, .walkthroughPosition
        ]
        let carriedOver: Set<ShellStringKey> = [
            .firstRunTitle, .firstRunObserves, .firstRunNever, .firstRunPermissions
        ]
        let inNamespace = Set(
            ShellStringKey.allCases.filter { $0.rawValue.hasPrefix("shell.walkthrough.") }
        )
        let drawn = Set(
            WalkthroughPage.allCases.flatMap { [$0.titleKey] + $0.paragraphs.map(\.key) }
        )

        #expect(chrome.isSubset(of: inNamespace))
        #expect(drawn.isDisjoint(with: chrome))
        #expect(drawn.subtracting(carriedOver) == inNamespace.subtracting(chrome))
    }

    @Test("next and previous walk the whole list and stop at both ends")
    func navigationWalksTheList() {
        var walked: [WalkthroughPage] = [.first]
        while let next = walked[walked.count - 1].next { walked.append(next) }
        #expect(walked == WalkthroughPage.allCases)

        var back: [WalkthroughPage] = [.last]
        while let previous = back[back.count - 1].previous { back.append(previous) }
        #expect(back == WalkthroughPage.allCases.reversed())

        #expect(WalkthroughPage.first.previous == nil)
        #expect(WalkthroughPage.last.next == nil)
        #expect(WalkthroughPage.allCases.map(\.ordinal) == Array(1...WalkthroughPage.allCases.count))
    }

    /// The snapshot lane photographs every page, and this is the half that says it does: a page
    /// added here without a component is a page nobody has seen at the largest text size.
    @Test("every page has a snapshot component")
    func everyPageIsPhotographed() {
        let photographed = SnapshotComponent.allCases
            .filter { $0.rawValue.hasPrefix("walkthrough") }
            .map(\.walkthroughPage)
        #expect(photographed == WalkthroughPage.allCases)
    }

    @Test(
        "every string the walkthrough draws resolves to real text",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func stringsResolve() {
        let keys = WalkthroughPage.allCases.flatMap { [$0.titleKey] + $0.paragraphs.map(\.key) }
            + [.walkthroughBack, .walkthroughNext, .walkthroughDone, .walkthroughPosition,
               .commandShowWalkthrough, .settingsShowWalkthroughNote]
        for key in keys {
            let resolved = ShellStrings.string(key)
            #expect(!resolved.isEmpty)
            #expect(resolved != key.rawValue, "\(key.rawValue) echoes its key")
        }
        #expect(ShellStrings.string(.commandShowWalkthrough) == "Show walkthrough")
        #expect(String(format: ShellStrings.string(.walkthroughPosition), arguments: ["2", "7"]) == "2 of 7")
    }
}
