import FocusCore
import Foundation
import NaturalLanguage

/// The only producer of `NormalisedToken` in the engine, and the only place raw text is ever
/// looked at.
///
/// Three entry points, three different rule sets, and **two different output types** (R-57):
///
/// | entry point | input | output |
/// |---|---|---|
/// | `tokens(fromProse:)` | a priority, a "done when", a keyword, a window title | `ProseTokenSet` |
/// | `tokens(fromIdentifier:)` | a bundle identifier | `IdentifierTokenSet` |
/// | `tokens(fromOrigin:)` | a normalised `scheme://host[:port]` | `IdentifierTokenSet` |
///
/// The type split is what makes "a bundle-identifier token reaches the similarity function" a
/// **compile error** rather than a review comment. `SimilarityScorer` takes `ProseTokenSet`
/// values; the identifier entry points cannot produce one; there is no conversion.
///
/// ## Determinism
///
/// Every stage is a pure function of its input on this OS revision, which is what lets a
/// golden corpus commit expectations at all. P-118 established the underlying fact the hard
/// way: an FNV-1a over 2 436 concatenated embedding components returned the identical value on
/// three separate process launches, and the identical value again from a zero-grant
/// ad-hoc-signed `.app` bundle. `TokenNormalizerTests` asserts the same property one level up,
/// with a committed digest over the whole corpus's normalised forms.
///
/// Note what is **not** used: Swift's `Hasher`. It is seeded per process, and an earlier run of
/// P-118 using it produced two different values for identical data. Every digest in this epic
/// is FNV-1a.
public struct TokenNormalizer: Sendable {
    public init() {}

    // MARK: - (a) Prose

    /// Tokens from prose a person wrote.
    ///
    /// 1. `NLLanguageRecognizer` for the dominant language and English's probability.
    /// 2. `NLTagger(tagSchemes: [.lexicalClass, .lemma])`, `unit: .word`, options
    ///    `[.omitWhitespace, .omitPunctuation]`.
    /// 3. Drop tokens whose lexical class is in `StopLists.droppedLexicalClasses`. **`Number`
    ///    is kept**: "chapter 3" and "Q3" are how people name work.
    /// 4. Take the lemma where the tagger gives one, else the surface form. P-114 measured
    ///    lemmatisation working: `writing→write`, `proposals→proposal`, `running→run`,
    ///    `invoices→invoice`.
    /// 5. Lowercase, then drop anything shorter than `RelevancePolicy.minimumTokenLength`.
    /// 6. Drop membership of `StopLists.genericStopTokens` — a date word matching a date word
    ///    is not evidence of relevance.
    public func tokens(fromProse prose: String) -> ProseTokenSet {
        let trimmed = prose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let sentence = trimmed.lowercased()
        let language = Self.languageReading(for: trimmed)

        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = trimmed
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]

        var accepted: [NormalisedToken] = []
        var seen: Set<String> = []

        tagger.enumerateTags(
            in: trimmed.startIndex..<trimmed.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: options
        ) { lexicalClass, range in
            if let lexicalClass,
               StopLists.droppedLexicalClasses.contains(lexicalClass.rawValue) {
                return true
            }

            let surface = String(trimmed[range])
            let lemma = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue
            let candidate = Self.preferredForm(lemma: lemma, surface: surface).lowercased()

            guard candidate.count >= RelevancePolicy.minimumTokenLength else { return true }
            guard !StopLists.genericStopTokens.contains(candidate) else { return true }
            guard let token = NormalisedToken.normalised(candidate) else { return true }
            if seen.insert(candidate).inserted { accepted.append(token) }
            return true
        }

        return ProseTokenSet(tokens: accepted, sentence: sentence, language: language)
    }

    /// The lemma when the tagger produced a usable one, else the surface form.
    ///
    /// A lemma is preferred because it is what makes `proposals` in a priority match
    /// `proposal` in a title; the surface form is the fallback because the tagger returns no
    /// lemma at all for a proper noun, a product name or a token like `q3`, and those are
    /// exactly the words that identify somebody's work.
    static func preferredForm(lemma: String?, surface: String) -> String {
        guard let lemma, !lemma.isEmpty else { return surface }
        return lemma
    }

    /// What the recogniser makes of a string, with **English's** probability read out
    /// specifically.
    ///
    /// The recogniser is asked for as many hypotheses as there are languages P-111 measured,
    /// so that English is reported even when it is not the dominant language. Reading only the
    /// winner would score every French priority's English confidence at zero for a reason that
    /// is about truncation rather than about language, and the derivation of
    /// `languageConfidenceFloor` would be measuring the wrong thing.
    static func languageReading(for text: String) -> LanguageReading? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return nil }
        let hypotheses = recognizer.languageHypotheses(
            withMaximum: StopLists.measuredLanguages.count
        )
        return LanguageReading(
            tag: dominant.rawValue,
            englishConfidence: hypotheses[.english] ?? 0
        )
    }

    // MARK: - (b) Bundle identifiers

    /// Tokens from a reverse-DNS bundle identifier.
    ///
    /// `NLTokenizer` is **not** sufficient and P-119 is why: it splits on `.` and `-` but
    /// leaves camelCase whole, so `com.apple.ScreenContinuity` came back as
    /// `["com", "apple", "ScreenContinuity"]`. F-171's seed-override guard needs to see
    /// `screen` and `continuity` separately, or a priority naming *"the iPhone Mirroring
    /// demo"* would be nudged about by the app's own bundled default. Hence a hand-written
    /// decomposer: split on `.`/`-`/`_`, then on camelCase boundaries, lowercase, drop the
    /// reverse-DNS heads, drop anything shorter than `minimumTokenLength`.
    ///
    /// Measured decompositions, committed as fixtures in `TokenNormalizerTests`:
    /// `com.apple.ScreenContinuity` → `["apple", "screen", "continuity"]`;
    /// `com.apple.dt.Xcode` → `["apple", "xcode"]`;
    /// `com.mojang.minecraftpe` → `["mojang", "minecraftpe"]`;
    /// `com.figma.Desktop` → `["figma", "desktop"]`;
    /// `md.obsidian` → `["obsidian"]`.
    public func tokens(fromIdentifier identifier: String) -> IdentifierTokenSet {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let segments = trimmed.split(whereSeparator: StopLists.identifierSeparators.contains)
        var accepted: [NormalisedToken] = []
        var seen: Set<String> = []

        for segment in segments {
            for piece in Self.splitCamelCase(String(segment)) {
                let lowered = piece.lowercased()
                guard lowered.count >= RelevancePolicy.minimumTokenLength else { continue }
                guard !StopLists.reverseDNSHeadTokens.contains(lowered) else { continue }
                guard let token = NormalisedToken.normalised(lowered) else { continue }
                if seen.insert(lowered).inserted { accepted.append(token) }
            }
        }

        return IdentifierTokenSet(subject: trimmed, tokens: accepted)
    }

    /// Split one identifier segment on camelCase boundaries.
    ///
    /// A boundary is an uppercase character that either follows a lowercase or a digit
    /// (`ScreenContinuity` → `Screen`, `Continuity`) or begins a new word inside a run of
    /// capitals (`HTMLParser` → `HTML`, `Parser`). Written out rather than reached for through
    /// a regular expression because a fixture asserts the exact output of five real bundle
    /// identifiers, and a decomposer whose behaviour a reader cannot predict is one nobody
    /// will be able to extend.
    static func splitCamelCase(_ text: String) -> [String] {
        let characters = Array(text)
        var pieces: [String] = []
        var current = ""

        for (index, character) in characters.enumerated() {
            if character.isUppercase, !current.isEmpty {
                let previous = characters[index - 1]
                let following: Character? =
                    index + 1 < characters.count ? characters[index + 1] : nil
                let startsWord = !previous.isUppercase || (following?.isLowercase ?? false)
                if startsWord {
                    pieces.append(current)
                    current = ""
                }
            }
            current.append(character)
        }

        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    // MARK: - (c) Origins

    /// Tokens from a normalised origin.
    ///
    /// The host only — never the scheme, never a port, and there is no path or query to take
    /// because `OriginNormalizer` removed them before this value existed (standing condition
    /// 3). Then: split on `.`, drop `www`, drop the final label, drop the second-to-last as
    /// well when the final one was a two-letter country code, lowercase, length filter.
    ///
    /// Measured (P-119): `https://docs.google.com` → `["docs", "google"]`;
    /// `https://www.youtube.com` → `["youtube"]`; `https://proposal.acme.co.uk` →
    /// `["proposal", "acme"]`.
    public func tokens(fromOrigin origin: String) -> IdentifierTokenSet {
        let trimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let host = Self.host(of: trimmed).lowercased()
        var labels = host.split(separator: ".").map(String.init)
        labels.removeAll { $0 == StopLists.wwwLabel }

        if let last = labels.last {
            labels.removeLast()
            if last.count == StopLists.countryCodeTLDLength, !labels.isEmpty {
                labels.removeLast()
            }
        }

        var accepted: [NormalisedToken] = []
        var seen: Set<String> = []
        for label in labels {
            guard label.count >= RelevancePolicy.minimumTokenLength else { continue }
            guard let token = NormalisedToken.normalised(label) else { continue }
            if seen.insert(label).inserted { accepted.append(token) }
        }

        return IdentifierTokenSet(subject: trimmed, tokens: accepted)
    }

    /// The host of a `scheme://host[:port]` origin, or the string itself when it is already a
    /// bare host. Never a path and never a query: there is nothing here that could keep one.
    static func host(of origin: String) -> String {
        if let components = URLComponents(string: origin), let host = components.host {
            return host
        }
        return origin
    }

    // MARK: - Determinism

    /// FNV-1a over the normalised forms of a list of inputs, in order.
    ///
    /// The instrument `TokenNormalizerTests` uses to assert that the same input produces
    /// byte-identical tokens across processes. FNV-1a and never `Hasher`, for the reason P-118
    /// found: `Hasher` is seeded per process and produced two different values for identical
    /// data.
    public func digest(overProse inputs: [String]) -> UInt64 {
        let encoded = inputs
            .map { tokens(fromProse: $0).tokens.map(\.value).joined(separator: ",") }
            .joined(separator: ";")
        return FNV1a.hash(encoded)
    }

    /// The same, over identifiers.
    public func digest(overIdentifiers inputs: [String]) -> UInt64 {
        let encoded = inputs
            .map { tokens(fromIdentifier: $0).tokens.map(\.value).joined(separator: ",") }
            .joined(separator: ";")
        return FNV1a.hash(encoded)
    }
}
