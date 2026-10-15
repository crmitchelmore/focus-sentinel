import Foundation
import Testing

@testable import FocusCore

/// What a drop, a paste or the file picker becomes (focus-6ji4).
///
/// Three gaps the claims audit found (`marketing/claims-audit.md` W8, W10, W11): a dropped
/// application was stored as a file item the engine never matches; pasted text with a scheme
/// but no origin, or a scheme-less link with a path, was stored verbatim as a keyword — a file
/// path in the store by the back door; and a site chip was offered that nothing in the shipping
/// app can match.
@Suite("Context drafts from drops, pastes and the file picker")
struct ContextItemDraftDecodeTests {
    // MARK: - Applications

    @Test("an application bundle becomes an app item keyed by its bundle identifier")
    func applicationBecomesAnAppItem() throws {
        let url = URL(filePath: "/System/Applications/Calculator.app", directoryHint: .isDirectory)
        try #require(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))

        let draft = ContextItemDraft.attachment(url: url)
        #expect(draft.kind == .app)
        #expect(draft.value == "com.apple.calculator")
        #expect(!draft.displayName.isEmpty)
        #expect(!draft.displayName.hasSuffix(".app"))
        // An app item is keyed by identity, not location: no path and no bookmark is kept.
        #expect(!draft.value.contains("/"))
        #expect(draft.bookmark == nil)
    }

    @Test("a bundle the person built themselves is read from its own Info.plist")
    func handMadeBundleIsReadFromItsInfoPlist() throws {
        let bundle = try Self.makeBundle(
            named: "Drafting Table",
            info: ["CFBundleIdentifier": "com.example.drafting-table", "CFBundleName": "Drafting Table"]
        )
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }

        let draft = ContextItemDraft.attachment(url: bundle)
        #expect(draft.kind == .app)
        #expect(draft.value == "com.example.drafting-table")
        #expect(draft.displayName == "Drafting Table")
    }

    @Test("a bundle that names no identifier stays a file, which still opens with the session")
    func bundleWithoutAnIdentifierStaysAFile() throws {
        let bundle = try Self.makeBundle(named: "Nameless", info: ["CFBundleName": "Nameless"])
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }

        let draft = ContextItemDraft.attachment(url: bundle)
        #expect(draft.kind == .file)
        #expect(ContextItemDraft.application(at: bundle) == nil)
    }

    @Test("an ordinary file is still a file")
    func ordinaryFileIsAFile() throws {
        let url = URL(filePath: NSTemporaryDirectory())
            .appending(path: "focus-draft-\(UUID().uuidString).txt")
        try "context".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let draft = ContextItemDraft.attachment(url: url)
        #expect(draft.kind == .file)
        #expect(draft.value == url.path(percentEncoded: false))
        #expect(ContextItemDraft.application(at: url) == nil)
    }

    @Test("a web URL is not an application")
    func webURLIsNotAnApplication() throws {
        let url = try #require(URL(string: "https://example.com/Calculator.app"))
        #expect(ContextItemDraft.application(at: url) == nil)
    }

    // MARK: - Pasted text

    /// Ordinary prose, including prose with a colon or a slash in it, is still a keyword.
    @Test(
        "prose is a keyword, colons and slashes included",
        arguments: [
            ("  Q3 Proposal  ", "q3 proposal"),
            ("note: draft", "note: draft"),
            ("note:draft", "note:draft"),
            ("re:invent", "re:invent"),
            ("a/b testing", "a/b testing"),
            ("and/or", "and/or"),
            ("data: the March numbers", "data: the march numbers"),
            ("example.com", "example.com"),
            ("v1.2/notes", "v1.2/notes"),
            ("Ratio 3:2", "ratio 3:2")
        ]
    )
    func proseIsAKeyword(text: String, expected: String) throws {
        let draft = try #require(ContextItemDraft.pasted(text))
        #expect(draft.kind == .keyword)
        #expect(draft.value == expected)
    }

    /// Text shaped like a location is never stored as a keyword, whatever else happens to it.
    @Test(
        "a path, a file URL, an address URL or a link is never a keyword",
        arguments: [
            "file:///Users/x/secret.pdf",
            "FILE:///Users/x/secret.pdf",
            "file:/Users/x/secret.pdf",
            "/Users/x/secret.pdf",
            "/Users/x/My Documents/secret.pdf",
            "~/Documents/secret.pdf",
            "~",
            "see file:///Users/x/secret.pdf for the draft",
            "mailto:someone@example.com",
            "MAILTO:someone@example.com",
            "tel:+441234567890",
            "sms:+441234567890",
            "data:text/plain;base64,c2VjcmV0",
            "docs.example.com/document/d/abc",
            "example.co.uk/a?b=c",
            "www.example.com#section",
            "localhost:3000/admin",
            "https://example.com/a/b?c=d",
            "x-devonthink-item://4F1D-22"
        ]
    )
    func locationIsNeverAKeyword(text: String) {
        let draft = ContextItemDraft.pasted(text)
        #expect(draft?.kind != .keyword, "\(text) was stored as a keyword")
        // Whatever does come through is an origin and nothing more (SC-3).
        if let draft {
            #expect(draft.kind == .domain)
            #expect(OriginNormalizer.isNormalized(draft.value))
        }
    }

    @Test("a pasted link with no origin yields nothing, sites or no sites")
    func locationWithoutAnOriginYieldsNil() {
        for text in ["file:///Users/x/secret.pdf", "/Users/x/a.pdf", "~/a.pdf", "mailto:a@example.com"] {
            #expect(ContextItemDraft.pasted(text) == nil, "\(text)")
        }
    }

    @Test("a pasted link takes the site path, scheme or no scheme")
    func linkTakesTheSitePath() throws {
        let withScheme = try #require(URL(string: "https://docs.example.com/document/d/abc"))
        let site = ContextItemDraft.site(from: withScheme)
        #expect(ContextItemDraft.pasted("https://docs.example.com/document/d/abc") == site)
        #expect(ContextItemDraft.pasted("docs.example.com/document/d/abc") == site)
    }

    @Test("empty text yields nothing")
    func emptyTextYieldsNil() {
        #expect(ContextItemDraft.pasted("") == nil)
        #expect(ContextItemDraft.pasted("  \n\t ") == nil)
    }

    // MARK: - Sites

    @Test("a site is offered exactly when the shipping app reads one")
    func siteFollowsShippingObservation() throws {
        let url = try #require(URL(string: "https://User:pw@Docs.Google.com:8443/document/d/abc?x=1#y"))
        let site = ContextItemDraft.site(from: url)
        if ShippingObservation.readsBrowserSite {
            #expect(site?.value == "https://docs.google.com:8443")
        } else {
            #expect(site == nil)
        }
        // The normaliser itself is unchanged: the day sites return, they return as origins.
        #expect(ContextItemDraft.domain(from: url)?.value == "https://docs.google.com:8443")
    }

    @Test("the vocabulary's observed flags agree with the one shipping fact")
    func observedFlagsAgree() {
        #expect(PriorityRuleScope.domain.isObserved == ShippingObservation.readsBrowserSite)
        #expect(ContextItemKind.domain.isObserved == ShippingObservation.readsBrowserSite)
        #expect(PriorityRuleScope.app.isObserved)
        #expect(!PriorityRuleScope.titleToken.isObserved)
        #expect(ContextItemKind.app.isObserved)
        #expect(ContextItemKind.keyword.isObserved)
        #expect(ContextItemKind.file.isObserved)
        #expect(!ContextItemKind.unknown("person").isObserved)
    }

    // MARK: - Fixtures

    private static func makeBundle(named name: String, info: [String: String]) throws -> URL {
        let root = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            .appending(path: "focus-draft-\(UUID().uuidString)", directoryHint: .isDirectory)
        let bundle = root.appending(path: "\(name).app", directoryHint: .isDirectory)
        let contents = bundle.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist: [String: String] = ["CFBundlePackageType": "APPL"]
        plist.merge(info) { _, new in new }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))
        return bundle
    }
}
