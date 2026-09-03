import Foundation

/// The kind of an explanation clause, as a plain string.
///
/// Carried separately from the clause itself so that a corpus case can assert the *set of
/// clause kinds* an answer produced without restating every payload — which is what makes a
/// fixture readable and its expectation order-independent (Appendix A.5).
///
/// Every kind has one String Catalog key, and `check-strings.sh` asserts the bijection between
/// these cases and the `explanation.clause.*` keys in both directions (R-70l).
public enum ExplanationClauseKind: String, Sendable, CaseIterable, Codable, Hashable {
    case userRule
    case contextItem
    case seedDefault
    case tokenOverlap
    case similarityCorroborated
    case sustainedDwell
    case returnedToAnchor
    case mixedSubjects
    case conflictingRules
    case insufficientEvidence
    case languageNotSupported
    case seedFallbackMixedUse
    case noNegativeBasis
    case modelDirect
    case modelSupporting

    /// The String Catalog key the UI renders this clause from.
    public var copyKey: String {
        switch self {
        case .userRule: "explanation.clause.userRule"
        case .contextItem: "explanation.clause.contextItem"
        case .seedDefault: "explanation.clause.seedDefault"
        case .tokenOverlap: "explanation.clause.tokenOverlap"
        case .similarityCorroborated: "explanation.clause.similarityCorroborated"
        case .sustainedDwell: "explanation.clause.sustainedDwell"
        case .returnedToAnchor: "explanation.clause.returnedToAnchor"
        case .mixedSubjects: "explanation.clause.mixedSubjects"
        case .conflictingRules: "explanation.clause.conflictingRules"
        case .insufficientEvidence: "explanation.clause.insufficientEvidence"
        case .languageNotSupported: "explanation.clause.languageNotSupported"
        case .seedFallbackMixedUse: "explanation.clause.seedFallbackMixedUse"
        case .noNegativeBasis: "explanation.clause.noNegativeBasis"
        case .modelDirect: "explanation.clause.modelDirect"
        case .modelSupporting: "explanation.clause.modelSupporting"
        }
    }

    public var copyResource: LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(copyKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }
}

/// One reason, typed.
///
/// **No clause takes a `String`.** Every textual payload is a `NormalisedToken`, which has no
/// public initialiser and rejects anything that is not a single token (R-57). So a window
/// title, a full URL, a document name or a file path cannot appear in an explanation by any
/// route — it is not forbidden, it is unrepresentable (R-62).
///
/// And no clause carries a *number the user reads*. `similarityCorroborated` has no distance:
/// showing somebody "cosine 1.03" is showing them an implementation detail dressed as a
/// reason, and probe P-113 proves the number would not even mean what they would take it to
/// mean. The two integers that do appear — a dwell in seconds and a count of subjects — are
/// facts about their own day, not scores about them.
public enum ExplanationClause: Sendable, Equatable, Hashable, Codable {
    /// A rule the user wrote, at the authority and narrowness they wrote it at.
    case userRule(authority: RuleAuthority, kind: RuleSubjectKind, subject: NormalisedToken)
    /// Something they attached to this priority.
    case contextItem(kind: ContextItemKind, subject: NormalisedToken)
    /// A default this app ships — the one opinion it has, or an `ask each time`.
    case seedDefault(disposition: AppRuleDisposition, subject: NormalisedToken)
    /// Words this shares with the priority. At most `RelevancePolicy.maximumExplanationTokens`.
    case tokenOverlap(tokens: [NormalisedToken])
    /// The sentence-similarity signal agreed. **Corroboration only, and never a number.**
    case similarityCorroborated
    /// How long the drift has been sustained.
    case sustainedDwell(seconds: Int)
    /// The person went back to where they were working.
    case returnedToAnchor(subject: NormalisedToken)
    /// Drift accumulated across several subjects, so nothing is misnamed.
    case mixedSubjects(count: Int)
    /// Two rules at the same authority and narrowness disagree. Both are named; neither wins.
    case conflictingRules(subjects: [NormalisedToken])
    /// The engine declined, and this is which of the named routes it took.
    case insufficientEvidence(reason: UncertaintyReason)
    /// Neither side was English at or above the confidence floor, and this OS has no embedding
    /// for anything else (P-111). The tag is carried when there was one to carry.
    case languageNotSupported(BCP47: NormalisedToken?)
    /// A bundled `ask each time` default: a browser, a chat client, a media player.
    case seedFallbackMixedUse(subject: NormalisedToken)
    /// **R-56.1.** The only clause in this epic whose copy carries an *ask*: name one
    /// application or site you expect to be looking at, and the engine gains something an
    /// absence can be an absence *of*. Until then it declines, however long the dwell.
    case noNegativeBasis
    /// **e06, R-109.** The on-device model read the priority and the subject and said the
    /// subject is the work. Band `.low` at the rung, because it is a guess and the inspector
    /// must not draw `.high` for one.
    case modelDirect(subject: NormalisedToken)
    /// The model said the subject is *in service of* the work. F-50's entire user-visible
    /// payoff and worth a second case: *"reading documentation — supporting your task"* is a
    /// different and more trustworthy sentence than *"this is your task"*, and a person who
    /// disagrees with it knows exactly which claim to correct.
    ///
    /// **No free text from the model ever reaches a surface.** Both clauses carry a
    /// `NormalisedToken` and are drawn from the catalog like every other clause; the schema's
    /// answer is a label, not prose, and there is no rationale field to render.
    case modelSupporting(subject: NormalisedToken)

    public var kind: ExplanationClauseKind {
        switch self {
        case .userRule: .userRule
        case .contextItem: .contextItem
        case .seedDefault: .seedDefault
        case .tokenOverlap: .tokenOverlap
        case .similarityCorroborated: .similarityCorroborated
        case .sustainedDwell: .sustainedDwell
        case .returnedToAnchor: .returnedToAnchor
        case .mixedSubjects: .mixedSubjects
        case .conflictingRules: .conflictingRules
        case .insufficientEvidence: .insufficientEvidence
        case .languageNotSupported: .languageNotSupported
        case .seedFallbackMixedUse: .seedFallbackMixedUse
        case .noNegativeBasis: .noNegativeBasis
        case .modelDirect: .modelDirect
        case .modelSupporting: .modelSupporting
        }
    }

    /// Every token this clause carries, in payload order. Used by the cap in
    /// `Explanation.make(…)` and by the hostile-corpus assertion, which needs to look at every
    /// string an explanation can reach a surface with.
    public var tokens: [NormalisedToken] {
        switch self {
        case .userRule(_, _, let subject): [subject]
        case .contextItem(_, let subject): [subject]
        case .seedDefault(_, let subject): [subject]
        case .tokenOverlap(let tokens): tokens
        case .returnedToAnchor(let subject): [subject]
        case .conflictingRules(let subjects): subjects
        case .languageNotSupported(let tag): tag.map { [$0] } ?? []
        case .seedFallbackMixedUse(let subject): [subject]
        case .modelDirect(let subject): [subject]
        case .modelSupporting(let subject): [subject]
        case .similarityCorroborated, .sustainedDwell, .mixedSubjects,
             .insufficientEvidence, .noNegativeBasis: []
        }
    }

    /// The clause with its token list truncated to `limit`, sorted first so that two runs over
    /// the same evidence produce the same clause. Clauses carrying at most one token are
    /// returned unchanged — a subject the user themselves authored is the *point* of the
    /// clause, not a transcript of what was on screen.
    func capped(to limit: Int) -> ExplanationClause {
        switch self {
        case .tokenOverlap(let tokens):
            .tokenOverlap(tokens: Array(tokens.sorted().prefix(limit)))
        case .conflictingRules(let subjects):
            .conflictingRules(subjects: Array(subjects.sorted().prefix(limit)))
        default:
            self
        }
    }
}

/// `ContextItemKind` gains `Codable` here, beside the clause that needs it.
///
/// It is not a string-raw enum — `unknown(String)` carries a value written by a build that
/// knew a kind this one does not — so the conformance is written out and round-trips through
/// the same `rawValue`/`init(rawValue:)` pair the store already uses. Declared in this file
/// rather than in `ContextItemKind.swift` so that e02's context vocabulary is not edited by an
/// epic that only reads it.
extension ContextItemKind: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Why the app concluded what it concluded — a list of typed clauses, never a string.
///
/// There is no `Explanation("…")` and no concatenation anywhere in the programme. `FocusUI`
/// maps each clause to a String Catalog key and substitutes typed values, so **there is no
/// runtime model-authored prose** — there is no model in this build at all — and D-11 /
/// standing condition 4 is structurally satisfied rather than observed.
public struct Explanation: Sendable, Equatable, Hashable, Codable {
    /// The rung that decided.
    public let stage: CascadeStage
    /// How much it had to go on.
    public let band: EvidenceBand
    /// The reasons, in the order the engine found them.
    public let clauses: [ExplanationClause]
    /// Which engine said so — schema, policy, lexicon, embedding revision and prompt version.
    public let stamp: EngineStamp

    /// **Private on purpose**, and the reason lint R-70g asserts `Explanation(` appears only in
    /// this file: every explanation in the programme is built by the factory below, which is
    /// where the token cap is applied. A second construction site would be a second cap, or
    /// none.
    private init(
        stage: CascadeStage,
        band: EvidenceBand,
        clauses: [ExplanationClause],
        stamp: EngineStamp
    ) {
        self.stage = stage
        self.band = band
        self.clauses = clauses
        self.stamp = stamp
    }

    /// The one route to an explanation.
    ///
    /// Every token-list payload is truncated to `RelevancePolicy.maximumExplanationTokens`,
    /// because an explanation is evidence and not a transcript: three words a person can check
    /// at a glance beat twelve they will not read.
    public static func make(
        stage: CascadeStage,
        band: EvidenceBand,
        clauses: [ExplanationClause],
        stamp: EngineStamp
    ) -> Explanation {
        Explanation(
            stage: stage,
            band: band,
            clauses: clauses.map { $0.capped(to: RelevancePolicy.maximumExplanationTokens) },
            stamp: stamp
        )
    }

    /// The set of clause kinds, in order. What a corpus expectation compares against.
    public var clauseKinds: [ExplanationClauseKind] { clauses.map(\.kind) }

    /// Every token in the whole explanation. What the hostile-corpus assertion reads.
    public var tokens: [NormalisedToken] { clauses.flatMap(\.tokens) }

    public var isEmpty: Bool { clauses.isEmpty }
}
