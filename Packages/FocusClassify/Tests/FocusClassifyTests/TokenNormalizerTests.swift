import FocusCore
import Foundation
import Testing

@testable import FocusClassify

/// What a token is, and what it is not (R-57, F-42).
///
/// Every expectation here is a **measurement**, not a preference: P-119 ran the same
/// identifiers and origins through `NLTokenizer` and through the hand-written decomposer and
/// recorded what came back, and these fixtures are that recording. A normaliser is the one
/// component whose output every other assertion in the epic is built on, so a fixture that
/// merely restated the implementation would make the whole corpus circular.
@Suite("Token normalisation")
struct TokenNormalizerTests {
    let normalizer = TokenNormalizer()

    // MARK: - (b) Identifiers — P-119's measured decompositions

    /// The decomposition `NLTokenizer` cannot do.
    ///
    /// P-119 measured the framework returning `["com", "apple", "ScreenContinuity"]` — it
    /// splits on `.` and `-` and leaves camelCase whole. Without the hand-written pass,
    /// F-171's seed-override guard would never fire, because the priority *"record the iPhone
    /// Mirroring demo"* would be compared against one opaque token.
    @Test(
        "P-119's identifier decompositions, exactly",
        arguments: [
            ("com.apple.ScreenContinuity", ["apple", "screen", "continuity"]),
            ("com.apple.dt.Xcode", ["apple", "xcode"]),
            ("com.mojang.minecraftpe", ["mojang", "minecraftpe"]),
            ("com.figma.Desktop", ["figma", "desktop"]),
            ("md.obsidian", ["obsidian"]),
            ("com.microsoft.Excel", ["microsoft", "excel"]),
            ("com.apple.iWork.Numbers", ["apple", "work", "numbers"]),
            ("com.apple.Preview", ["apple", "preview"]),
            ("com.omnigroup.OmniGraffle", ["omnigroup", "omni", "graffle"]),
            ("com.tinyspeck.slackmacgap", ["tinyspeck", "slackmacgap"])
        ]
    )
    func identifierDecomposition(identifier: String, expected: [String]) {
        let set = normalizer.tokens(fromIdentifier: identifier)
        #expect(set.tokens.map(\.value) == expected)
        #expect(set.subject == identifier)
    }

    /// The reverse-DNS heads are the registrar's words, not the application's. An overlap on
    /// `com` would match every application ever shipped.
    @Test("reverse-DNS heads never survive")
    func headsAreDropped() {
        for head in StopLists.reverseDNSHeadTokens {
            let set = normalizer.tokens(fromIdentifier: "\(head).example.Application")
            #expect(!set.values.contains(head), "\(head) survived as an identifier token")
        }
    }

    // MARK: - (c) Origins — P-119's measured decompositions

    @Test(
        "P-119's origin decompositions, exactly",
        arguments: [
            ("https://docs.google.com", ["docs", "google"]),
            ("https://www.youtube.com", ["youtube"]),
            ("https://proposal.acme.co.uk", ["proposal", "acme"]),
            ("https://developer.apple.com", ["developer", "apple"])
        ]
    )
    func originDecomposition(origin: String, expected: [String]) {
        #expect(normalizer.tokens(fromOrigin: origin).tokens.map(\.value) == expected)
    }

    /// The `co.uk` rule, stated as a property rather than as a single fixture: a two-letter
    /// final label takes the label before it with it, and a longer one does not.
    @Test("a two-letter country code takes the public suffix before it")
    func countryCodeRule() {
        #expect(normalizer.tokens(fromOrigin: "https://acme.co.uk").values == ["acme"])
        #expect(normalizer.tokens(fromOrigin: "https://acme.com").values == ["acme"])
        #expect(normalizer.tokens(fromOrigin: "https://reports.acme.co.uk").values
                    == ["reports", "acme"])
    }

    /// Standing condition 3 from the other end: the origin normaliser removed the path and the
    /// query before this value existed, and there is nothing here that could keep one anyway.
    @Test("no origin token carries a scheme, a port or a path separator")
    func originsCarryNoStructure() {
        let set = normalizer.tokens(fromOrigin: "https://docs.google.com:8443")
        #expect(set.values == ["docs", "google"])
        for token in set.tokens {
            #expect(!token.value.contains(":"))
            #expect(!token.value.contains("/"))
        }
    }

    // MARK: - (a) Prose

    /// The lexical-class drop set and the lemma preference, measured at P-114.
    @Test(
        "prose keeps content words, lemmatised and lowercased",
        arguments: [
            ("Write the Q3 proposal for Acme", ["write", "proposal", "acme"]),
            ("fix the login bug in the ios app", ["fix", "login", "bug", "ios", "app"]),
            ("writing proposals and running invoices",
             ["write", "proposal", "run", "invoice"]),
            ("prepare the sprint board tickets",
             ["prepare", "sprint", "board", "ticket"]),
            ("close the Bergman audit", ["close", "bergman", "audit"])
        ]
    )
    func proseKeepsContentWords(prose: String, expected: [String]) {
        #expect(normalizer.tokens(fromProse: prose).tokens.map(\.value) == expected)
    }

    /// `Number` is deliberately **absent** from the drop set — "chapter 3" is how people name
    /// work — but a two-character token still falls to the length filter. Both halves matter,
    /// and asserting them together is what stops somebody "fixing" one by deleting the other.
    @Test("numbers survive their lexical class and then meet the length filter")
    func numbersSurviveTheClassFilterAndMeetTheLengthFilter() {
        #expect(!StopLists.droppedLexicalClasses.contains("Number"))
        #expect(normalizer.tokens(fromProse: "finish chapter 3").values == ["chapter"])
        #expect(normalizer.tokens(fromProse: "finish chapter 314").values.contains("314"))
    }

    /// A date word matching a date word is not evidence of relevance — the single easiest way
    /// for the overlap stage to produce a false `relevant` (P-119).
    @Test("generic words are dropped from prose and kept in identifiers")
    func genericStopTokens() {
        let prose = normalizer.tokens(
            fromProse: "reconcile the invoices before Friday last month"
        )
        #expect(prose.values == ["reconcile", "invoice"])
        // The same list is NOT applied to identifiers: com.apple.Notes losing `notes` would
        // leave the misleading-name family with nothing to be misleading about.
        #expect(normalizer.tokens(fromIdentifier: "com.apple.Notes").values.contains("notes"))
    }

    /// The other side of family 8: a vague priority produces too few content tokens to be
    /// judged at all, which is R-56.1's first condition failing.
    @Test(
        "a vague priority yields fewer content tokens than the negative basis needs",
        arguments: ["stuff", "work", "catch up", ""]
    )
    func vaguePrioritiesAreBelowTheContentFloor(prose: String) {
        let set = normalizer.tokens(fromProse: prose)
        #expect(set.tokens.count < RelevancePolicy.minimumPriorityContentTokens)
    }

    // MARK: - Language

    /// P-115's measurement, re-run: a real English priority is recognised with near-certainty,
    /// a non-English one scores **zero** for English, and a single word scores far below both.
    @Test("English confidence is read for English specifically, not for the winner")
    func englishConfidenceIsReadForEnglish() throws {
        let english = try #require(
            normalizer.tokens(fromProse: "Write the Q3 proposal for Acme").language
        )
        #expect(english.tag == "en")
        #expect(english.englishConfidence > 0.9)

        for (prose, tag) in [
            ("rédiger la proposition trimestrielle", "fr"),
            ("Quartalsbericht schreiben", "de"),
            ("四半期の提案書を書く", "ja")
        ] {
            let reading = try #require(normalizer.tokens(fromProse: prose).language)
            #expect(reading.tag == tag)
            #expect(
                reading.englishConfidence < english.englishConfidence,
                "\(tag) scored English at \(reading.englishConfidence)"
            )
        }
    }

    /// P-115's single-word case, which is the second, independent route by which a vague
    /// priority reaches `uncertain`.
    @Test("a one-word priority scores far below a sentence")
    func oneWordScoresLow() throws {
        let word = try #require(normalizer.tokens(fromProse: "proposal").language)
        let sentence = try #require(
            normalizer.tokens(fromProse: "write the quarterly proposal").language
        )
        #expect(word.englishConfidence < sentence.englishConfidence)
        #expect(word.englishConfidence < 0.6)
    }

    // MARK: - The type split (R-57, P-112)

    /// **The assertion that cannot be written as an expectation.**
    ///
    /// `SimilarityScorer.corroboration(priority:evidence:)` takes `ProseTokenSet` values.
    /// `tokens(fromIdentifier:)` returns an `IdentifierTokenSet`, which is a different type
    /// with no conversion to the other — so
    ///
    /// ```swift
    /// scorer.corroboration(
    ///     priority: prose,
    ///     evidence: normalizer.tokens(fromIdentifier: "com.apple.Notes")  // ← does not compile
    /// )
    /// ```
    ///
    /// is a **compile error**, not a test failure. What can be asserted at runtime is the
    /// property that makes the split necessary: the two entry points return different types,
    /// and neither exposes a bridge. The lint (R-70c) and `SimilarityScorerTests` carry the
    /// rest.
    @Test("identifier tokens and prose tokens are different types with no bridge")
    func theTypeSplitIsReal() {
        let prose: ProseTokenSet = normalizer.tokens(fromProse: "review the Notion proposal")
        let identifier: IdentifierTokenSet = normalizer.tokens(fromIdentifier: "com.apple.Notes")

        #expect(prose.values.contains("notion"))
        #expect(identifier.values.contains("notes"))
        // They share no token, which is exactly why the misleading-name family resolves to
        // `uncertain`: `notes` never matches `notion` by equality, and it can never be
        // compared to it semantically because it cannot reach the embedding at all.
        #expect(prose.values.intersection(identifier.values).isEmpty)
    }

    // MARK: - Determinism (P-118)

    /// A golden corpus is only worth committing if normalisation is a pure function of its
    /// input on this OS revision. The digest is FNV-1a and never `Hasher`: P-118 found the
    /// hard way that `Hasher` is seeded per process and produced two different values for
    /// identical data.
    @Test("the same inputs produce the same tokens, digested")
    func determinismDigest() {
        #expect(normalizer.digest(overProse: Self.proseCorpus) == Self.committedProseDigest)
        #expect(
            normalizer.digest(overIdentifiers: Self.identifierCorpus)
                == Self.committedIdentifierDigest
        )

        // Twice in one process, and through a second normaliser, so the assertion is about
        // the function rather than about a memoised first answer.
        let second = TokenNormalizer()
        #expect(
            second.digest(overProse: Self.proseCorpus)
                == normalizer.digest(overProse: Self.proseCorpus)
        )
    }

    /// No token, from any entry point, over any input in the corpus, contains whitespace.
    ///
    /// `NormalisedToken` already rejects it at construction — this is the check on the
    /// enforcement, and it is run over the hostile shapes as well as the ordinary ones.
    @Test("no token carries whitespace, a path separator or a query character")
    func noTokenCarriesStructure() {
        let hostile = [
            "Q3 Proposal — Acme Corp.docx",
            "https://mail.example.com/u/0/#inbox?compose=new&to=dana",
            "/Users/someone/Documents/Bergman audit/2026 Q3.numbers",
            "Rapport trimestriel — Acme S.A.",
            "四半期の提案書 — 株式会社"
        ]
        for input in hostile + Self.proseCorpus {
            for token in normalizer.tokens(fromProse: input).tokens {
                #expect(!token.value.contains { $0.isWhitespace })
                #expect(!token.value.contains("/"))
                #expect(!token.value.contains("?"))
                #expect(!token.value.contains("&"))
                #expect(!token.value.contains("#"))
            }
        }
    }

    // MARK: - The corpora the digests are taken over

    /// Realistic priorities and evidence phrases, deliberately not chosen to illustrate a
    /// point — the failure mode being guarded against is a corpus assembled to confirm a
    /// behaviour already believed in.
    static let proseCorpus = [
        "Write the Q3 proposal for Acme",
        "fix the login bug in the ios app",
        "close the Bergman audit",
        "ship the release notes",
        "review the Notion proposal",
        "record the iPhone Mirroring demo",
        "reconcile the invoices before Friday last month",
        "draft the Q3 review",
        "prepare the sprint board tickets",
        "writing proposals and running invoices",
        "stuff",
        "proposal",
        "rédiger la proposition trimestrielle",
        "Quartalsbericht schreiben",
        "四半期の提案書を書く"
    ]

    static let identifierCorpus = [
        "com.apple.ScreenContinuity",
        "com.apple.dt.Xcode",
        "com.microsoft.Excel",
        "com.apple.iWork.Numbers",
        "com.apple.iWork.Pages",
        "com.apple.iWork.Keynote",
        "com.apple.Preview",
        "com.apple.Terminal",
        "com.figma.Desktop",
        "com.omnigroup.OmniGraffle",
        "com.apple.Safari",
        "com.apple.Notes",
        "com.apple.Chess",
        "com.tinyspeck.slackmacgap",
        "md.obsidian"
    ]

    /// Re-record these **only** together with a bump to `EngineStamp.lexiconVersion`: the stop
    /// lists and the decomposer are what they digest, and a lexicon that changed without a
    /// version bump would serve e06's cache stale verdicts.
    static let committedProseDigest: UInt64 = 0x7e05_bb73_c8a2_259e
    static let committedIdentifierDigest: UInt64 = 0x98d9_157c_144a_a54a
}
