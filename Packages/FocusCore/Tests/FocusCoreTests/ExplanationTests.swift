import Foundation
import Testing

@testable import FocusCore

/// The explanation is where raw captured content would reach a person if it could reach them
/// anywhere. These assertions are the check on the enforcement; the enforcement is the type
/// (R-57, R-62, F-52).
@Suite("Explanation vocabulary")
struct ExplanationTests {
    // MARK: - NormalisedToken

    @Test("a token bearing whitespace cannot be constructed by any route")
    func whitespaceIsRejected() throws {
        let hostile = [
            "Q3 proposal for Acme — Pages",          // a window title
            "two words",
            "tab\tseparated",
            "line\nbreak",
            " leading",
            "trailing ",
            "\u{00A0}nonbreaking",
            ""
        ]

        for candidate in hostile {
            #expect(NormalisedToken.normalised(candidate) == nil, "accepted \(candidate.debugDescription)")
            #expect(!NormalisedToken.isWellFormed(candidate))
        }
        #expect(NormalisedToken.normalised(hostile).isEmpty)
    }

    /// The four shapes of raw captured content the hostile corpus is made of. None of them is
    /// a token, and none of them can be turned into one.
    @Test("a URL, a path, a query string and a document name are all unrepresentable")
    func capturedContentIsUnrepresentable() {
        let captured = [
            "https://acme.example/deals/q3?token=secret&user=dana",
            "/Users/dana/Documents/Acme Proposal v4.pages",
            "acme.example/deals",
            "?token=secret",
            "user:password@host",
            "Proposal, final (2).docx"
        ]

        for candidate in captured {
            #expect(NormalisedToken.normalised(candidate) == nil, "accepted \(candidate.debugDescription)")
        }
    }

    @Test("a real normalised token is accepted, in any script")
    func tokensAreAccepted() throws {
        let good = ["proposal", "q3", "com.apple.safari", "docs", "screen-continuity",
                    "some_token", "提案", "rédiger", "ios"]

        for candidate in good {
            let token = try #require(NormalisedToken.normalised(candidate))
            #expect(token.value == candidate)
            #expect(token.description == candidate)
        }
        #expect(NormalisedToken.normalised(good).count == good.count)
    }

    @Test("tokens sort deterministically and compare by value")
    func tokensSortDeterministically() throws {
        let tokens = NormalisedToken.normalised(["proposal", "acme", "budget"])
        #expect(tokens.sorted().map(\.value) == ["acme", "budget", "proposal"])
        #expect(NormalisedToken.normalised("acme") == NormalisedToken.normalised("acme"))
    }

    /// Decoding is the third construction route and it validates too, so a corpus fixture
    /// carrying a sentence fails the load rather than smuggling one past the factories.
    @Test("decoding a token validates, and a sentence fails the decode")
    func decodingValidates() throws {
        let encoded = try JSONEncoder().encode(try #require(NormalisedToken.normalised("proposal")))
        let decoded = try JSONDecoder().decode(NormalisedToken.self, from: encoded)
        #expect(decoded.value == "proposal")
        #expect(String(data: encoded, encoding: .utf8) == "\"proposal\"")

        let sentence = Data("\"two words\"".utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(NormalisedToken.self, from: sentence)
        }
    }

    // MARK: - ExplanationClause

    /// The structural assertion this suite exists for: **no clause takes a bare `String`.**
    /// Reflection over one value of every case, because a payload that is a `String` is how
    /// free text would get in, and a lint over the source can be defeated by a typealias.
    @Test("no explanation clause carries a bare String")
    func noClauseCarriesFreeText() throws {
        for clause in Self.oneOfEveryClause() {
            let mirror = Mirror(reflecting: clause)
            for child in mirror.children {
                assertCarriesNoBareString(child.value, in: clause)
            }
        }
    }

    private func assertCarriesNoBareString(_ value: Any, in clause: ExplanationClause) {
        if value is String {
            Issue.record("\(clause.kind.rawValue) carries a bare String")
            return
        }
        let mirror = Mirror(reflecting: value)
        // A tuple of associated values, an optional or an array: look inside it too.
        for child in mirror.children where !(value is NormalisedToken) {
            assertCarriesNoBareString(child.value, in: clause)
        }
    }

    @Test("every clause kind is represented, distinct, and has its own copy key")
    func everyClauseKindHasCopy() {
        let clauses = Self.oneOfEveryClause()
        #expect(Set(clauses.map(\.kind)) == Set(ExplanationClauseKind.allCases))
        #expect(clauses.count == ExplanationClauseKind.allCases.count)

        let keys = ExplanationClauseKind.allCases.map(\.copyKey)
        #expect(Set(keys).count == keys.count)
        for kind in ExplanationClauseKind.allCases {
            #expect(kind.copyKey == "explanation.clause.\(kind.rawValue)")
        }
    }

    @Test("every clause round-trips through Codable")
    func clausesRoundTrip() throws {
        for clause in Self.oneOfEveryClause() {
            let decoded = try JSONDecoder().decode(
                ExplanationClause.self, from: JSONEncoder().encode(clause)
            )
            #expect(decoded == clause, "\(clause.kind.rawValue) did not round-trip")
        }
    }

    // MARK: - Explanation

    @Test("the token cap is enforced at construction, not by convention")
    func tokenCapIsEnforcedAtConstruction() throws {
        let many = NormalisedToken.normalised(
            ["proposal", "acme", "budget", "sprint", "ticket", "board"]
        )
        #expect(many.count > RelevancePolicy.maximumExplanationTokens)

        let explanation = Explanation.make(
            stage: .heuristic,
            band: .medium,
            clauses: [.tokenOverlap(tokens: many), .conflictingRules(subjects: many)],
            stamp: .current
        )

        for clause in explanation.clauses {
            #expect(clause.tokens.count <= RelevancePolicy.maximumExplanationTokens)
        }
        // Sorted before truncation, so two runs over the same evidence agree.
        #expect(
            explanation.clauses.first?.tokens.map(\.value) == ["acme", "board", "budget"]
        )
    }

    @Test("an explanation reports its clause kinds and its tokens")
    func explanationProjectsItsContents() throws {
        let subject = try #require(NormalisedToken.normalised("com.apple.safari"))
        let explanation = Explanation.make(
            stage: .globalRule,
            band: .high,
            clauses: [
                .userRule(authority: .global, kind: .app, subject: subject),
                .similarityCorroborated
            ],
            stamp: .current
        )

        #expect(explanation.clauseKinds == [.userRule, .similarityCorroborated])
        #expect(explanation.tokens == [subject])
        #expect(explanation.stage == .globalRule)
        #expect(explanation.band == .high)
        #expect(!explanation.isEmpty)
    }

    @Test("an explanation round-trips through Codable with every clause intact")
    func explanationRoundTrips() throws {
        let explanation = Explanation.make(
            stage: .seedFallback,
            band: .low,
            clauses: Self.oneOfEveryClause(),
            stamp: .current
        )
        let decoded = try JSONDecoder().decode(
            Explanation.self, from: JSONEncoder().encode(explanation)
        )
        #expect(decoded == explanation)
    }

    /// One value of every clause, so a case added without a fixture fails
    /// `everyClauseKindHasCopy` rather than silently going untested.
    private static func oneOfEveryClause() -> [ExplanationClause] {
        let subject = NormalisedToken.normalised("com.apple.safari")!
        let other = NormalisedToken.normalised("docs")!
        return [
            .userRule(authority: .task, kind: .app, subject: subject),
            .contextItem(kind: .domain, subject: other),
            .seedDefault(disposition: .askEachTime, subject: subject),
            .tokenOverlap(tokens: [other, subject]),
            .similarityCorroborated,
            .sustainedDwell(seconds: 120),
            .returnedToAnchor(subject: subject),
            .mixedSubjects(count: 3),
            .conflictingRules(subjects: [subject, other]),
            .insufficientEvidence(reason: .noNegativeBasis),
            .languageNotSupported(BCP47: NormalisedToken.normalised("fr")),
            .seedFallbackMixedUse(subject: subject),
            .noNegativeBasis,
            .modelDirect(subject: subject),
            .modelSupporting(subject: subject)
        ]
    }
}
