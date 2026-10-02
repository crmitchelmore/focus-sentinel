import FocusCore
import Foundation
import Testing

@testable import FocusUI

/// The decode path for F-96 and F-21: what a dropped or pasted thing becomes.
///
/// The real cross-app gesture — a drag out of Finder, a ⌘C in Safari — is TCC-gated evidence
/// and is read from frames (measured: driving Finder's own copy through `osascript` blocks on
/// Automation consent, P-65). What *is* gateable, and is the part that could be wrong in a way
/// a user would care about, is the decode itself: it is a pure function, and this is its table.
///
/// The standing-condition-3 case is the one that matters most. A dropped link must reach the
/// store as an **origin** — no path, no query, no fragment, no credentials — and there is no
/// initialiser anywhere that takes a full URL and keeps it. While the shipping app reads no
/// site (focus-6ji4, `ShippingObservation`), a dropped link reaches the store as nothing at all.
@Suite("Context drop decoding")
struct ContextDropTests {
    @Test("a dropped file becomes a file item, bookmarked at the moment it arrived")
    func fileURLBecomesAFileItem() throws {
        let url = URL(filePath: NSTemporaryDirectory())
            .appending(path: "focus-drop-\(UUID().uuidString).txt")
        try "context".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let draft = try #require(ContextDecoder.decode(.url(url)))
        #expect(draft.kind == .file)
        #expect(draft.value == url.path(percentEncoded: false))
        #expect(draft.displayName == url.lastPathComponent)
        // A path is not a file. The bookmark is the durable handle, and it is made at the one
        // moment the app is certain it can reach the file.
        #expect(draft.bookmark != nil)
    }

    @Test("a dropped application becomes an app item keyed by its bundle identifier")
    func applicationBecomesAnAppItem() throws {
        let url = URL(filePath: "/System/Applications/Calculator.app", directoryHint: .isDirectory)
        try #require(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))

        let draft = try #require(ContextDecoder.decode(.url(url)))
        #expect(draft.kind == .app)
        #expect(draft.value == "com.apple.calculator")
    }

    @Test("a dropped link is a site — nothing while sites are not read, and only ever an origin")
    func webURLIsASiteOrNothing() throws {
        let url = try #require(URL(string: "https://User:pw@Docs.Google.com:8443/document/d/abc?x=1#y"))
        let draft = ContextDecoder.decode(.url(url))
        #expect(draft == ContextItemDraft.site(from: url))
        if !ShippingObservation.readsBrowserSite {
            #expect(draft == nil)
        }
        for forbidden in ["User", "pw", "document", "abc", "x=1", "#y", "?"] {
            #expect(draft?.value.contains(forbidden) != true, "\(forbidden) survived into the stored value")
        }
    }

    @Test("pasted text that is a link takes the same path as a dropped link")
    func textThatIsALinkTakesTheLinkPath() throws {
        let url = try #require(URL(string: "https://example.co.uk/a/b?c=d"))
        #expect(ContextDecoder.decode(.text("  https://example.co.uk/a/b?c=d  ")) == ContextDecoder.decode(.url(url)))
        #expect(ContextDecoder.decode(.text("example.co.uk/a/b?c=d")) == ContextDecoder.decode(.url(url)))
    }

    @Test("pasted text shaped like a file path is never stored as a keyword")
    func pathShapedTextIsNeverAKeyword() {
        for text in [
            "file:///Users/x/secret.pdf",
            "/Users/x/secret.pdf",
            "~/Documents/secret.pdf",
            "mailto:someone@example.com",
            "docs.example.com/document/d/abc"
        ] {
            #expect(ContextDecoder.decode(.text(text))?.kind != .keyword, "\(text) was stored as a keyword")
        }
        // Prose with a colon in it is still prose.
        #expect(ContextDecoder.decode(.text("note: draft"))?.kind == .keyword)
    }

    @Test("pasted prose becomes a keyword, trimmed and lowercased")
    func textBecomesAKeyword() throws {
        let draft = try #require(ContextDecoder.decode(.text("  Q3 Proposal  ")))
        #expect(draft.kind == .keyword)
        #expect(draft.value == "q3 proposal")
        #expect(draft.displayName == "q3 proposal")
    }

    @Test("nothing decodable yields nothing — never an empty chip")
    func undecodableInputYieldsNil() throws {
        #expect(ContextDecoder.decode(.text("")) == nil)
        #expect(ContextDecoder.decode(.text("   \n ")) == nil)
        // A scheme with no host has no origin to normalise, and "mailto" is not a keyword the
        // user typed either.
        let hostless = try #require(URL(string: "mailto:someone@example.com"))
        #expect(ContextDecoder.decode(.url(hostless)) == nil)
        // The same shapes as text are refused the same way, rather than kept as a keyword.
        #expect(ContextDecoder.decode(.text("mailto:someone@example.com")) == nil)
        #expect(ContextDecoder.decode(.text("file:///Users/x/secret.pdf")) == nil)
    }

    @Test("a mixed drop adds what it understood and silently drops what it did not")
    func mixedDropDecodesWhatItCan() throws {
        let app = URL(filePath: "/System/Applications/Calculator.app", directoryHint: .isDirectory)
        let drafts = ContextDecoder.decode([
            .url(app),
            .text(""),
            .text("/Users/x/secret.pdf"),
            .text("focus")
        ])

        #expect(drafts.count == 2)
        #expect(drafts.map(\.kind) == [.app, .keyword])
        #expect(drafts[0].value == "com.apple.calculator")
        #expect(drafts[1].value == "focus")
    }
}
