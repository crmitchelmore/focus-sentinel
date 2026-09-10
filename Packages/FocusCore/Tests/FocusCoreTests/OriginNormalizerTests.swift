import Foundation
import Testing

@testable import FocusCore

/// A tiny reproducible generator.
///
/// The property test below has to be able to fail the same way twice: a random seed that
/// changes every run turns a real defect into "it went red once on someone's laptop". This is
/// a linear congruential generator with a fixed seed, so the corpus is the same corpus on
/// every machine and every day.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

/// Standing condition 3, made checkable: only normalised origins, never full URLs.
@Suite("Origin normalisation")
struct OriginNormalizerTests {
    /// The three cases probe P-68 measured, verbatim.
    @Test(
        "the measured cases",
        arguments: [
            ("https://Docs.Google.com/document/d/abc?x=1#y", "https://docs.google.com"),
            ("http://localhost:3000/a/b", "http://localhost:3000"),
            ("https://user:pw@example.co.uk:8443/p", "https://example.co.uk:8443")
        ]
    )
    func measuredCases(_ input: String, _ expected: String) throws {
        let url = try #require(URL(string: input))
        #expect(OriginNormalizer.normalize(url) == expected)
        #expect(OriginNormalizer.normalize(input) == expected)
    }

    @Test(
        "anything without a host has no origin, and is not guessed at",
        arguments: [
            "file:///Users/someone/notes.md",
            "mailto:someone@example.com",
            "/just/a/path",
            "notes.md",
            "",
            "   ",
            "https://",
            "tel:+15551234"
        ]
    )
    func thingsWithoutAnOrigin(_ input: String) {
        #expect(
            OriginNormalizer.normalize(input) == nil,
            "‘\(input)’ produced an origin it does not have"
        )
    }

    @Test("normalising an origin returns that same origin")
    func idempotent() {
        for origin in [
            "https://example.com",
            "http://localhost:3000",
            "https://example.co.uk:8443",
            "https://sub.domain.example.org"
        ] {
            #expect(OriginNormalizer.normalize(origin) == origin)
            #expect(OriginNormalizer.isNormalized(origin))
        }
    }

    /// The property, over a generated corpus: **none of the five forbidden components
    /// survives**, the host is lowercase, and normalising the result changes nothing.
    @Test("no path, query, fragment, user or password ever survives")
    func propertyOverGeneratedURLs() throws {
        var generator = SeededGenerator(seed: 0x0E02_5C3F_1234_5678)

        let schemes = ["http", "https", "HTTPS", "Http"]
        let hosts = [
            "example.com", "Docs.Google.COM", "localhost", "sub.domain.example.org",
            "EXAMPLE.CO.UK", "news.example", "a-b-c.example.io"
        ]
        let ports: [Int?] = [nil, 80, 443, 3000, 8443]
        let paths = ["", "/", "/a", "/a/b/c", "/document/d/SECRETDOCID", "/~user/notes.md"]
        let queries: [String?] = [nil, "x=1", "q=SECRETQUERY&page=2", "token=SECRETTOKEN"]
        let fragments: [String?] = [nil, "top", "SECRETFRAGMENT"]
        let users: [String?] = [nil, "SECRETUSER"]
        let passwords: [String?] = [nil, "SECRETPASSWORD"]

        var checked = 0
        for _ in 0..<400 {
            var components = URLComponents()
            components.scheme = schemes.randomElement(using: &generator)
            components.host = hosts.randomElement(using: &generator)
            components.port = ports.randomElement(using: &generator)!
            components.path = paths.randomElement(using: &generator)!
            components.query = queries.randomElement(using: &generator)!
            components.fragment = fragments.randomElement(using: &generator)!
            components.user = users.randomElement(using: &generator)!
            if components.user != nil {
                components.password = passwords.randomElement(using: &generator)!
            }

            guard let url = components.url else { continue }
            checked += 1

            let origin = try #require(
                OriginNormalizer.normalize(url),
                "a URL with a scheme and a host must have an origin: \(url.absoluteString)"
            )

            // Nothing secret survives. The markers are deliberately unmistakable so that a
            // failure names which component leaked.
            for secret in [
                "SECRETDOCID", "SECRETQUERY", "SECRETTOKEN", "SECRETFRAGMENT", "SECRETUSER",
                "SECRETPASSWORD", "notes.md", "page=2"
            ] {
                #expect(
                    !origin.contains(secret),
                    "‘\(secret)’ survived normalisation of \(url.absoluteString) → \(origin)"
                )
            }

            // Structurally: exactly one "://", and nothing after the authority.
            let authority = origin.replacingOccurrences(of: "://", with: "|")
            #expect(authority.filter { $0 == "|" }.count == 1, "malformed origin \(origin)")
            #expect(!authority.contains("/"), "a path survived in \(origin)")
            #expect(!origin.contains("?"), "a query survived in \(origin)")
            #expect(!origin.contains("#"), "a fragment survived in \(origin)")
            #expect(!origin.contains("@"), "user info survived in \(origin)")

            // Lowercase host, and a port only when the URL carried one.
            let expectedHost = try #require(components.host).lowercased()
            let expectedScheme = try #require(components.scheme).lowercased()
            let expectedPort = components.port.map { ":\($0)" } ?? ""
            #expect(origin == "\(expectedScheme)://\(expectedHost)\(expectedPort)")

            // And normalising it again is a no-op.
            #expect(OriginNormalizer.normalize(origin) == origin, "not idempotent: \(origin)")
        }

        #expect(checked >= 300, "the generated corpus was too small to mean anything")
    }

    @Test("a domain context item can only ever be built from an origin")
    func domainChipsCarryOnlyOrigins() throws {
        let now = FixedDateProvider.reference.now
        let url = try #require(URL(string: "https://Docs.Google.com/document/d/abc?x=1#y"))

        let item = try #require(ContextItemValue.domain(from: url, addedAt: now))
        #expect(item.kind == .domain)
        #expect(item.value == "https://docs.google.com")
        #expect(item.displayName == "docs.google.com")

        // A URL with no origin makes no chip at all, rather than a chip holding a path.
        #expect(ContextItemValue.domain(from: URL(fileURLWithPath: "/tmp/x"), addedAt: now) == nil)
        #expect(ContextItemValue.domain(origin: "/tmp/x", addedAt: now) == nil)
    }
}
