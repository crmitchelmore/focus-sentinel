import FocusCore
import FocusRules
import Foundation

/// Turns what the store holds into what a judgement needs — once per invalidation, never per
/// activation (R-65).
///
/// ## The two precedence axes, derived rather than invented (R-72)
///
/// | authority | derived from |
/// |---|---|
/// | `.global` | a stored row with `scopeRaw ∈ {app, domain}` and `task == nil` |
/// | `.task` | the same row with `task != nil` |
/// | `.session` | `SessionRuleBox`, in memory, never persisted |
///
/// **No schema change.** `FocusSchemaV3` is untouched: no `FocusSchemaV4`, no migration stage,
/// no fixture regeneration. The authority axis is *derived* from facts already stored, plus one
/// in-memory owner for the lifetime that was never persistable — a session rule that survived a
/// relaunch would be a session rule that outlived its session, and the cheapest way to
/// guarantee it cannot is to give it no persistence to reach.
///
/// ## Legacy `.session` rows are skipped and counted, never guessed at (R-72.3)
///
/// The shipped `RuleScope` makes `.session` mutually exclusive with `app`/`domain`/`titleToken`,
/// so a row carrying it has **no subject kind at all**: nothing in the row says whether its
/// subject is a bundle identifier, an origin or a title token, and the shipped
/// `SwiftDataRuleStoreTests` plants one of each in the same suite. Inferring "this looks like a
/// bundle identifier" from the shape of a string is exactly the magic this epic's third binding
/// condition forbids. So the builder drops such rows into `skippedRuleCount` and the count is
/// surfaced rather than swallowed.
///
/// ## Stored `.titleToken` rows are skipped and counted too, since e07a
///
/// The cascade's title-token arm is real and the golden corpus exercises it through its own
/// producer; the **store** never had a producer — the one shipping path passes application
/// identity only, and under PD-1 the AX-title depth dial is parked with a named blocker. A stored
/// title-token row was therefore a rule the engine read and could never match, and the pane drew
/// it as live. `PriorityRuleScope.isRetired` names the scope; this builder honours it the way it
/// honours a legacy `.session` row, so "no longer read" on the pane is a fact about the engine.
///
/// **Except where the road not taken is being measured.** PD-1 parks the AX-title dial rather
/// than deleting it and promises the measured cost of that road (e07 §S0); the golden corpus is
/// that measurement, and eleven of its cases are title-token rules. The evaluation lane builds
/// its snapshots with `readsRetiredScopes: true` so those cells keep computing through the
/// shipping cascade; the shipping `RelevanceHost` takes the default and skips them.
public struct RuleSnapshotBuilder: Sendable {
    public let normalizer: TokenNormalizer
    /// Optional so that a corpus case, a unit test or a build with no embedding can construct
    /// a snapshot without one — in which case `prioritySentence` is `nil`, the similarity
    /// signal never runs, and every route it could have taken ends at `uncertain`.
    private let scorer: SimilarityScorer?
    /// Whether a stored row of a retired scope is promoted to a rung (e07a). `false` for the
    /// shipping engine; `true` only for the evaluation lane, which measures the road not taken.
    public let readsRetiredScopes: Bool

    public init(
        normalizer: TokenNormalizer = TokenNormalizer(),
        scorer: SimilarityScorer? = nil,
        readsRetiredScopes: Bool = false
    ) {
        self.normalizer = normalizer
        self.scorer = scorer
        self.readsRetiredScopes = readsRetiredScopes
    }

    public func build(
        priority: PriorityInput?,
        storedRules: [StoredRuleRow] = [],
        sessionRules: [ScopedRuleValue] = [],
        contextPack: [ContextItemValue] = [],
        stamp: EngineStamp = .current
    ) -> RuleSnapshot {
        let tokens = priority.map { normalizer.tokens(fromProse: $0.prose) } ?? .empty

        // P-116: 1.75 ms, paid once per priority revision rather than once per activation. The
        // vector is only worth taking when the similarity signal could ever consult it, so the
        // English gate is applied here as well as in the scorer — a French priority costs
        // nothing at all rather than costing a vector nobody may read.
        let sentence: SentenceVector? = {
            guard let scorer, tokens.isJudgeableEnglish(tunings: normalizer.tunings) else { return nil }
            return scorer.vector(for: tokens.sentence)
        }()

        // A rule handed to the session slot that is not at session authority is a
        // programming error rather than a stored ambiguity — dropped and counted like any
        // other row this build declines to promote, because a silent drop is the thing R-72.3
        // exists to prevent.
        let sessionScoped = sessionRules.filter { $0.authority == .session }
        var scoped = sessionScoped
        var skipped = sessionRules.count - sessionScoped.count

        for row in storedRules {
            guard let subjectKind = Self.subjectKind(
                for: row.rule.scope,
                subject: row.rule.subject,
                readingRetired: readsRetiredScopes
            ) else {
                // A legacy `.session` row, or a retired word-shaped `.titleToken` one (e07a).
                // It reaches no rung, is counted, and is never assigned an inferred subject
                // kind (R-72.3).
                skipped += 1
                continue
            }
            scoped.append(
                ScopedRuleValue(
                    id: row.rule.id,
                    authority: row.isTaskScoped ? .task : .global,
                    subjectKind: subjectKind,
                    subject: row.rule.subject,
                    verdict: Self.priorityVerdict(for: row.rule.verdict),
                    createdAt: row.rule.createdAt
                )
            )
        }

        return RuleSnapshot(
            priorityID: priority?.id,
            priorityRevision: priority?.revision ?? 0,
            priorityTokens: tokens,
            prioritySentence: sentence,
            priorityLanguage: tokens.language,
            rules: scoped.sorted(by: ScopedRuleValue.precedes),
            skippedRuleCount: skipped,
            contextPack: contextPack,
            policyDigest: RelevancePolicy.digest,
            stamp: stamp
        )
    }

    /// `RuleScope` minus `.session` and minus the retired `.titleToken`, written out rather than
    /// reached for through `init(rawValue:)`, for the same reason `SessionPhase.decode` is
    /// (R-45's doctrine): the totality is held by a test over `allCases`, and a fifth scope added
    /// without touching this function fails that test rather than silently becoming a rung.
    ///
    /// `.titleToken` answers `nil` unless the caller is reading retired scopes on purpose:
    /// `RuleSubjectKind.titleToken` and the cascade arm that matches it stay, because the corpus
    /// measures what the road not taken would have cost (PD-1, e07 S0) and does so through this
    /// very function with `readingRetired: true`.
    ///
    /// **Except an item rule** (issue #24). A `.titleToken` row whose subject parses as a
    /// `SelectedItem` is the live shape the Accessibility reader produces, and it is promoted
    /// whatever `readingRetired` says. Only the word-shaped legacy row stays retired.
    static func subjectKind(
        for scope: RuleScope,
        subject: String? = nil,
        readingRetired: Bool = false
    ) -> RuleSubjectKind? {
        switch scope {
        case .app: .app
        case .domain: .domain
        case .titleToken:
            readingRetired || subject.map(SelectedItem.isItemSubject) == true ? .titleToken : nil
        case .session: nil
        }
    }

    /// `FocusRules.RuleVerdict` → `FocusCore.PriorityRuleVerdict`.
    ///
    /// Two vocabularies rather than one because `FocusCore` may import no sibling package (the
    /// R-14 matrix), and `FocusRulesTests` already asserts they are the same set of strings.
    /// An exhaustive switch rather than a raw-value bridge, so that a fourth verdict is a
    /// compile error here rather than a `nil` somewhere at runtime.
    static func priorityVerdict(for verdict: RuleVerdict) -> PriorityRuleVerdict {
        switch verdict {
        case .relevant: .relevant
        case .unrelated: .unrelated
        case .uncertain: .uncertain
        }
    }
}
