import FocusCore
import Foundation

/// What `NLLanguageRecognizer` made of a string.
///
/// Two facts travel together and only one of them is a gate. `tag` is the *dominant*
/// language, carried so that an explanation can say which language it was
/// (`ExplanationClause.languageNotSupported(BCP47:)`); `englishConfidence` is the recogniser's
/// probability for **English specifically**, which is the only number the similarity gate
/// reads.
///
/// The distinction is load-bearing. P-111 measured `NLEmbedding` returning `nil` for `fr`,
/// `de`, `ja`, `zh-Hans` and `es` — word and sentence, every one — so a non-English string has
/// no similarity signal to consult at all. And P-115 measured a single English word scoring
/// only `0.41`, so the same floor also disqualifies input too short to be judged. Both routes
/// end at `uncertain`, which is the correct answer to "I have no instrument for this".
public struct LanguageReading: Sendable, Equatable, Hashable, Codable {
    /// The dominant language's BCP-47 tag, e.g. `en`, `fr`, `zh-Hans`.
    public let tag: String
    /// The recogniser's probability for English, whatever the dominant language turned out
    /// to be. `0` when English is not among the reported hypotheses.
    public let englishConfidence: Double

    public init(tag: String, englishConfidence: Double) {
        self.tag = tag
        self.englishConfidence = englishConfidence
    }

    /// Whether this string may be compared by the similarity signal at all.
    ///
    /// **`false` while `languageConfidenceFloor` is unmeasured**, which is the conservative
    /// direction and the same answer the gate gives for a language this OS has no embedding
    /// for: an engine with no calibrated floor has no business consulting a distance.
    public var isJudgeableEnglish: Bool { isJudgeableEnglish(tunings: .shipped) }

    /// The same reading under a person's dials (focus-exdi). The shipped floor may be
    /// unmeasured, in which case the answer is `false` whatever the dial says.
    public func isJudgeableEnglish(tunings: PolicyTunings) -> Bool {
        guard RelevancePolicy.languageConfidenceFloor.value != nil else { return false }
        return englishConfidence >= tunings.value(.languageConfidenceFloor)
    }
}

/// Tokens drawn from **prose** — a priority, a "done when", a keyword, a window title.
///
/// This is the type `SimilarityScorer` accepts, and the only one. That is not a convention: it
/// is the whole of R-57's ban expressed as a type. `TokenNormalizer.tokens(fromIdentifier:)`
/// returns an `IdentifierTokenSet`, which is a *different type*, so handing a bundle
/// identifier to the similarity function does not compile — there is no cast, no bridging
/// initialiser and no protocol both conform to that the scorer accepts.
///
/// The reason is measured rather than felt. P-112 found nine of sixteen common application
/// names outside the embedding's vocabulary altogether (`figma`, `xcode`, `spotify`,
/// `youtube`, `github`, `jira`, `reddit`, `tiktok`, `instagram`), and of the seven inside,
/// `notion`, `slack`, `terminal`, `mail`, `safari`, `discord` and `chrome` all carry their
/// **English** meanings rather than the application's. "Review the Notion doc" would match a
/// notebook application because `notion` means *an idea*, which is a right answer reached for
/// a reason that has nothing to do with the software.
public struct ProseTokenSet: Sendable, Equatable, Hashable, Codable {
    /// The surviving content tokens, in the order they appeared, deduplicated.
    public let tokens: [NormalisedToken]
    /// The trimmed, lowercased sentence the tokens came from.
    ///
    /// Carried because the sentence — not the token list — is what the sentence embedding
    /// consumes, and because it is the LRU's cache key. It never reaches an explanation: no
    /// `ExplanationClause` has a `String` payload (R-62), so there is no route from here to a
    /// surface.
    public let sentence: String
    /// What the recogniser made of it, or `nil` when there was nothing to recognise.
    public let language: LanguageReading?

    public init(tokens: [NormalisedToken], sentence: String, language: LanguageReading?) {
        self.tokens = tokens
        self.sentence = sentence
        self.language = language
    }

    /// The empty set — no tokens, no sentence, no language. What an absent priority or an
    /// evidence-free activation produces.
    public static let empty = ProseTokenSet(tokens: [], sentence: "", language: nil)

    public var isEmpty: Bool { tokens.isEmpty && sentence.isEmpty }

    /// Whether the similarity signal may look at this side at all.
    public var isJudgeableEnglish: Bool { isJudgeableEnglish(tunings: .shipped) }

    public func isJudgeableEnglish(tunings: PolicyTunings) -> Bool {
        language?.isJudgeableEnglish(tunings: tunings) ?? false
    }

    /// The token values, for set arithmetic against the other kind of token set.
    public var values: Set<String> { Set(tokens.map(\.value)) }
}

/// Tokens decomposed from an **identifier** — a bundle identifier or a normalised origin.
///
/// A deliberately different type from `ProseTokenSet`, with no conversion between them. These
/// tokens may be compared for equality against rules, context-pack items and priority tokens,
/// and may **never** be passed to any similarity function (R-57, P-112). The type split is the
/// enforcement; the lint and the test are the audit trail.
public struct IdentifierTokenSet: Sendable, Equatable, Hashable, Codable {
    /// The identifier or origin these were decomposed from, verbatim.
    public let subject: String
    /// The surviving tokens, in order, deduplicated.
    public let tokens: [NormalisedToken]

    public init(subject: String, tokens: [NormalisedToken]) {
        self.subject = subject
        self.tokens = tokens
    }

    public static let empty = IdentifierTokenSet(subject: "", tokens: [])

    public var isEmpty: Bool { tokens.isEmpty }

    public var values: Set<String> { Set(tokens.map(\.value)) }
}

/// The overlap stage's arithmetic, in one place.
///
/// Exact-token intersection, and nothing cleverer. P-114 measured it producing **zero** false
/// positives over the sixteen-pair corpus — unrelated Jaccard was `0.000` on all eight
/// unrelated pairs, without exception — against roughly half misses. That asymmetry is the
/// engine's whole shape: overlap is the *precision* instrument and decides `relevant`;
/// similarity is the *recall* instrument and may only corroborate; and neither of them may
/// decide `unrelated` (R-57, R-58).
public enum TokenOverlap {
    /// The tokens both sides share, sorted, so that two runs over the same evidence produce
    /// the same explanation.
    public static func shared(
        _ priority: [NormalisedToken],
        _ evidence: [NormalisedToken]
    ) -> [NormalisedToken] {
        let candidates = Set(evidence.map(\.value))
        return priority.filter { candidates.contains($0.value) }.sorted()
    }

    /// Whether any shared token is long enough to band `.medium`.
    ///
    /// P-114: every true overlap token in the measured corpus — `proposal`, `budget`,
    /// `sprint`, `ticket`, `board` — is five characters or more. A shorter overlap is real
    /// signal and bands `.low`, which is below `interventionBandFloor` and therefore cannot
    /// mandate anything on its own.
    public static func isStrong(
        _ shared: [NormalisedToken],
        tunings: PolicyTunings = .shipped
    ) -> Bool {
        shared.contains { $0.value.count >= tunings.count(.minimumStrongTokenLength) }
    }

    /// The band a given overlap earns, or `nil` when there is not enough of one to decide.
    public static func band(
        for shared: [NormalisedToken],
        tunings: PolicyTunings = .shipped
    ) -> EvidenceBand? {
        guard shared.count >= tunings.count(.minimumOverlapTokens) else { return nil }
        return isStrong(shared, tunings: tunings) ? .medium : .low
    }
}
