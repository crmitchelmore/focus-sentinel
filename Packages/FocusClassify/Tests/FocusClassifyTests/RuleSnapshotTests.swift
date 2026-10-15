import FocusCore
import FocusRules
import Foundation
import Testing

@testable import FocusClassify

/// The snapshot, and the two precedence axes derived from what the schema already stores
/// (R-65, R-72).
///
/// The assertion that matters most is `aLegacySessionRowReachesNoRung`. The shipped `RuleScope`
/// makes `.session` mutually exclusive with `app`/`domain`/`titleToken`, so a row carrying it
/// says nothing about whether its subject is a bundle identifier, an origin or a title token —
/// and `SwiftDataRuleStoreTests` plants one of each in the same suite, so the ambiguity is
/// already live in the shipped tree. This suite proves the builder declines to guess.
@Suite("Rule snapshot")
struct RuleSnapshotTests {
    static let reference = Date(timeIntervalSince1970: 1_767_225_600)

    static func priority(
        _ intent: String = "write the q3 proposal for acme",
        doneWhen: String? = nil,
        revision: Int = 1
    ) -> PriorityInput {
        PriorityInput(
            id: UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!,
            revision: revision,
            intent: intent,
            doneWhen: doneWhen
        )
    }

    static func stored(
        _ scope: RuleScope,
        _ subject: String,
        _ verdict: RuleVerdict,
        task: Bool = false,
        id: UUID = UUID(),
        age: Double = 0
    ) -> StoredRuleRow {
        StoredRuleRow(
            rule: RelevanceRuleValue(
                id: id,
                scope: scope,
                subject: subject,
                verdict: verdict,
                createdAt: reference.addingTimeInterval(age)
            ),
            isTaskScoped: task
        )
    }

    // MARK: - The authority derivation (R-72.2)

    /// Two authorities from one optional, which is all `task: PriorityTask?` can express — the
    /// sentence an earlier draft of R-72 got wrong and withdrew in its own text.
    @Test("a task-scoped row becomes .task and a global one becomes .global")
    func authorityComesFromTheTaskAssociation() {
        let snapshot = RuleSnapshotBuilder().build(
            priority: Self.priority(),
            storedRules: [
                Self.stored(.app, "com.apple.Safari", .relevant, task: true),
                Self.stored(.app, "com.apple.Notes", .unrelated, task: false)
            ]
        )

        #expect(snapshot.rules(at: .task).map(\.subject) == ["com.apple.Safari"])
        #expect(snapshot.rules(at: .global).map(\.subject) == ["com.apple.Notes"])
        #expect(snapshot.rules(at: .session).isEmpty)
        #expect(snapshot.skippedRuleCount == 0)
    }

    /// The third authority has no persisted home and is never given one: it arrives from the
    /// in-memory box, which is what makes "a session rule cannot outlive its session" a fact
    /// about reachability rather than a promise about cleanup.
    @Test("the session authority arrives only from the in-memory box")
    func sessionAuthorityArrivesFromTheBox() {
        let sessionRule = ScopedRuleValue(
            authority: .session,
            subjectKind: .app,
            subject: "com.apple.Music",
            verdict: .uncertain,
            createdAt: Self.reference
        )
        let snapshot = RuleSnapshotBuilder().build(
            priority: Self.priority(),
            storedRules: [Self.stored(.app, "com.apple.Notes", .unrelated)],
            sessionRules: [sessionRule]
        )

        #expect(snapshot.rules(at: .session).map(\.subject) == ["com.apple.Music"])
        #expect(snapshot.rules.first?.authority == .session, "session must sort first")
    }

    /// A rule handed to the session slot at the wrong authority is dropped **and counted**,
    /// never quietly re-labelled.
    @Test("a rule at the wrong authority is dropped and counted, not re-labelled")
    func misfiledSessionRulesAreCounted() {
        let snapshot = RuleSnapshotBuilder().build(
            priority: Self.priority(),
            sessionRules: [
                ScopedRuleValue(
                    authority: .global, subjectKind: .app, subject: "com.apple.Music",
                    verdict: .uncertain, createdAt: Self.reference
                )
            ]
        )
        #expect(snapshot.rules.isEmpty)
        #expect(snapshot.skippedRuleCount == 1)
    }

    // MARK: - R-72.3: the legacy row is skipped, counted, never guessed at

    /// **The load-bearing one.** A persisted `scopeRaw == "session"` row has no subject kind,
    /// and the engine will not infer one from the shape of its subject — which is exactly what
    /// the shipped store's own tests demonstrate is impossible to do safely, by planting a
    /// bundle identifier and a host under the same scope.
    @Test("a legacy session-scoped row reaches no rung and increments the count by exactly one")
    func aLegacySessionRowReachesNoRung() {
        let snapshot = RuleSnapshotBuilder().build(
            priority: Self.priority(),
            storedRules: [
                Self.stored(.session, "com.apple.Safari", .unrelated),
                Self.stored(.app, "com.apple.Notes", .relevant)
            ]
        )

        #expect(snapshot.skippedRuleCount == 1)
        #expect(snapshot.rules.count == 1)
        #expect(snapshot.rules.first?.subject == "com.apple.Notes")
        // And no rule anywhere in the snapshot claims a subject kind it was never given.
        #expect(!snapshot.rules.contains { $0.subject == "com.apple.Safari" })
    }

    /// Both of the shipped store's ambiguous plantings, in one snapshot: a bundle identifier
    /// and a host, under the same scope, neither one guessed at.
    @Test("both shapes of legacy row are skipped, and the count is not zero-suppressed")
    func bothAmbiguousLegacyShapesAreSkipped() {
        let snapshot = RuleSnapshotBuilder().build(
            priority: Self.priority(),
            storedRules: [
                Self.stored(.session, "com.apple.Safari", .unrelated),
                Self.stored(.session, "news.example", .unrelated)
            ]
        )
        #expect(snapshot.rules.isEmpty)
        #expect(snapshot.skippedRuleCount == 2)
    }

    /// The mapping is total over `RuleScope.allCases`, so a fifth scope cannot become a rung by
    /// accident — it fails here first.
    @Test("the subject-kind mapping is total over RuleScope and excludes exactly .session and the retired .titleToken")
    func subjectKindMappingIsTotal() {
        var mapped: [RuleSubjectKind] = []
        var unmapped: [RuleScope] = []
        for scope in RuleScope.allCases {
            if let kind = RuleSnapshotBuilder.subjectKind(for: scope) {
                mapped.append(kind)
            } else {
                unmapped.append(scope)
            }
        }
        // Every subject kind a stored row can still reach, and exactly the two scopes a stored
        // row is not promoted from: the lifetime one, and the retired one (e07a).
        #expect(Set(mapped) == Set(RuleSubjectKind.allCases).subtracting([.titleToken]))
        #expect(Set(unmapped) == [.session, .titleToken])
        #expect(mapped.count + unmapped.count == RuleScope.allCases.count)
        // Reading retired scopes on purpose restores the whole codomain and still never promotes
        // a lifetime row.
        let measured = RuleScope.allCases.compactMap {
            RuleSnapshotBuilder.subjectKind(for: $0, readingRetired: true)
        }
        #expect(Set(measured) == Set(RuleSubjectKind.allCases))
        #expect(RuleSnapshotBuilder.subjectKind(for: .session, readingRetired: true) == nil)
    }

    @Test("the verdict mapping is total over RuleVerdict and preserves the raw value")
    func verdictMappingIsTotal() {
        for verdict in RuleVerdict.allCases {
            #expect(RuleSnapshotBuilder.priorityVerdict(for: verdict).rawValue == verdict.rawValue)
        }
    }

    // MARK: - The total order (what replay needs)

    /// Sorted by `(authority, subjectKind, createdAt, id)`. Total, so two builds of the same
    /// inputs are `==` and a sequence fixture can assert a byte-identical transcript.
    @Test("the sort is total, so two builds of the same inputs are equal")
    func theSortIsTotal() {
        let identifiers = (0..<4).map { _ in UUID() }
        // No stored `.titleToken` row here since e07a: the builder skips one (see the retirement
        // test below), so a sort that included it would be sorting three rows and claiming four.
        let rows = [
            Self.stored(.domain, "https://mail.google.com", .unrelated, task: true, id: identifiers[0]),
            Self.stored(.app, "com.apple.Safari", .relevant, task: true, id: identifiers[1]),
            Self.stored(.domain, "https://docs.google.com", .relevant, id: identifiers[2]),
            Self.stored(.app, "com.apple.Notes", .unrelated, id: identifiers[3])
        ]

        let first = RuleSnapshotBuilder().build(priority: Self.priority(), storedRules: rows)
        let second = RuleSnapshotBuilder().build(
            priority: Self.priority(), storedRules: rows.reversed()
        )

        #expect(first == second, "the sort is not total — replay would not be exact")
        #expect(
            first.rules.map { "\($0.authority.rawValue)/\($0.subjectKind.rawValue)" }
                == ["task/domain", "task/app", "global/domain", "global/app"]
        )
    }

    // MARK: - e07a: a stored title-token row is retired — skipped and counted, never a rung

    /// **The engine half of "no longer read"** (e07a, PD-1). Nothing in the shipping app produces
    /// a title token — the one shipping producer passes application identity only, and the
    /// AX-title depth dial is parked — so a stored `.titleToken` row was a rule the engine read and
    /// could never match, drawn on the pane as live. Red before this round: the builder promoted
    /// the row to a `task/titleToken` rung with `skippedRuleCount == 0`.
    ///
    /// The cascade's title-token **arm** is deliberately untouched — the golden corpus builds its
    /// rules through its own producer and measures what the road not taken would cost — so this
    /// is a fact about stored rows, held beside the legacy-session rule it mirrors.
    @Test("a stored title-token row reaches no rung and is counted, like a legacy session row")
    func aStoredTitleTokenRowIsRetired() {
        let snapshot = RuleSnapshotBuilder().build(
            priority: Self.priority(),
            storedRules: [
                Self.stored(.titleToken, "proposal", .relevant, task: true),
                Self.stored(.app, "com.apple.Notes", .relevant)
            ]
        )
        #expect(snapshot.skippedRuleCount == 1)
        #expect(snapshot.rules.count == 1)
        #expect(snapshot.rules.first?.subject == "com.apple.Notes")
        #expect(!snapshot.rules.contains { $0.subjectKind == .titleToken })
        // …while the evaluation lane, which measures the road not taken (PD-1, e07 S0), can still
        // ask for the row on purpose — and only on purpose.
        let measured = RuleSnapshotBuilder(readsRetiredScopes: true).build(
            priority: Self.priority(),
            storedRules: [Self.stored(.titleToken, "proposal", .relevant, task: true)]
        )
        #expect(measured.skippedRuleCount == 0)
        #expect(measured.rules.map(\.subjectKind) == [.titleToken])
    }

    /// **An item rule is live, a word rule is not** (issue #24). Both are stored `.titleToken`;
    /// only the shape the Accessibility reader writes — `<bundle>::<label>` — becomes a rung.
    @Test("a stored item rule becomes a rung, while a legacy word rule stays retired")
    func aStoredItemRuleIsLive() {
        let item = SelectedItem(bundleIdentifier: "com.github.githubapp", label: "Plan the holiday")!
        let snapshot = RuleSnapshotBuilder().build(
            priority: Self.priority(),
            storedRules: [
                Self.stored(.titleToken, item.subject, .unrelated, task: true),
                Self.stored(.titleToken, "proposal", .relevant, task: true),
                Self.stored(.titleToken, "com.github.githubapp::Not: normalised", .relevant),
            ]
        )
        #expect(snapshot.skippedRuleCount == 2)
        #expect(snapshot.rules.map(\.subject) == [item.subject])
        #expect(snapshot.rules.map(\.subjectKind) == [.titleToken])
        #expect(snapshot.rules.map(\.authority) == [.task])
    }

    /// Ties on authority and narrowness are broken by age and then by identity, so a snapshot
    /// never depends on the order the store happened to return rows in.
    @Test("ties break by age and then by identity")
    func tiesBreakDeterministically() {
        let older = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let newer = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let snapshot = RuleSnapshotBuilder().build(
            priority: Self.priority(),
            storedRules: [
                Self.stored(.app, "b", .relevant, id: newer, age: 60),
                Self.stored(.app, "a", .relevant, id: older, age: 0)
            ]
        )
        #expect(snapshot.rules.map(\.subject) == ["a", "b"])
    }

    // MARK: - The priority side, computed once (R-65)

    /// P-116 measured the sentence vector at 1.75 ms. It is paid once per priority revision,
    /// which is the whole reason the snapshot exists.
    @Test("the priority vector is computed once and reused")
    func priorityVectorIsComputedOnce() {
        let scorer = SimilarityScorer()
        scorer.warmUp()
        let builder = RuleSnapshotBuilder(scorer: scorer)

        let first = builder.build(priority: Self.priority())
        #expect(first.prioritySentence != nil)
        #expect(scorer.statistics.misses == 1, "the priority vector was not the only embedding call")

        // Re-building the same priority reads the memo rather than the embedding.
        let second = builder.build(priority: Self.priority())
        #expect(second.prioritySentence == first.prioritySentence)
        #expect(scorer.statistics.misses == 1)
        #expect(scorer.statistics.hits == 1)
    }

    /// A priority the similarity signal may never consult costs no vector at all — the English
    /// gate applied at the point the cost is incurred rather than at the point it is read.
    @Test("a non-English priority is not vectorised")
    func nonEnglishPriorityIsNotVectorised() {
        let scorer = SimilarityScorer()
        scorer.warmUp()
        let snapshot = RuleSnapshotBuilder(scorer: scorer).build(
            priority: Self.priority("rédiger la proposition trimestrielle pour acme")
        )
        #expect(snapshot.prioritySentence == nil)
        #expect(snapshot.priorityLanguage?.tag == "fr")
        #expect(scorer.statistics.misses == 0)
    }

    /// A build with no scorer produces no vector, and every route the similarity signal could
    /// have taken ends at `uncertain` — the conservative direction, by construction.
    @Test("a snapshot built with no scorer carries no vector")
    func noScorerMeansNoVector() {
        let snapshot = RuleSnapshotBuilder().build(priority: Self.priority())
        #expect(snapshot.prioritySentence == nil)
        #expect(!snapshot.priorityTokens.tokens.isEmpty)
    }

    /// The "done when" is part of the work's description, so it is tokenised with the intent.
    @Test("the done-when phrasing is tokenised with the intent")
    func doneWhenIsTokenised() {
        let snapshot = RuleSnapshotBuilder().build(
            priority: Self.priority("write the q3 proposal", doneWhen: "sent to Dana")
        )
        #expect(snapshot.priorityTokens.values.contains("proposal"))
        #expect(snapshot.priorityTokens.values.contains("dana"))
    }

    // MARK: - The two refusals

    /// A snapshot built by one policy version may not be evaluated by another: the thresholds
    /// that produced its tokens are not the ones about to be applied to them.
    @Test("a policy-digest mismatch is refused rather than tolerated")
    func policyDigestMismatchIsRefused() {
        let good = RuleSnapshotBuilder().build(priority: Self.priority())
        #expect(good.matchesRunningPolicy)
        #expect(good.policyDigest == RelevancePolicy.digest)

        let stale = RuleSnapshot(
            priorityID: good.priorityID,
            priorityRevision: good.priorityRevision,
            priorityTokens: good.priorityTokens,
            prioritySentence: nil,
            priorityLanguage: good.priorityLanguage,
            rules: [],
            skippedRuleCount: 0,
            contextPack: [],
            policyDigest: good.policyDigest &+ 1,
            stamp: .current
        )
        #expect(!stale.matchesRunningPolicy)
    }

    /// An edited priority is a different priority: every judgement about the old wording is
    /// stale, which is the corpus half of F-53's cache-key contract.
    @Test("a revision mismatch is visible on the snapshot")
    func revisionMismatchIsVisible() {
        let snapshot = RuleSnapshotBuilder().build(priority: Self.priority(revision: 3))
        #expect(snapshot.describes(revision: 3))
        #expect(!snapshot.describes(revision: 4))
    }

    // MARK: - The negative basis (R-56.1)

    /// Only an *identity* can be absent in a way that means something. A `keyword` can only
    /// ever match positively; a `file` cannot be observed at zero grants at all.
    @Test("only app and domain items constitute a negative basis")
    func onlyIdentitiesAreANegativeBasis() {
        let keywordOnly = RuleSnapshotBuilder().build(
            priority: Self.priority(),
            contextPack: [
                ContextItemValue.keyword("proposal", addedAt: Self.reference)!,
                ContextItemValue.keyword("acme", addedAt: Self.reference)!
            ]
        )
        #expect(keywordOnly.negativeBasisItems.isEmpty)
        #expect(!keywordOnly.hasNegativeBasis)

        let fileOnly = RuleSnapshotBuilder().build(
            priority: Self.priority(),
            contextPack: [
                ContextItemValue.file(
                    url: URL(fileURLWithPath: "/Users/someone/Q3.numbers"),
                    bookmark: nil,
                    addedAt: Self.reference
                )
            ]
        )
        #expect(!fileOnly.hasNegativeBasis)

        let appIdentity = RuleSnapshotBuilder().build(
            priority: Self.priority(),
            contextPack: [
                ContextItemValue.app(
                    bundleID: "com.apple.Pages", displayName: "Pages", addedAt: Self.reference
                )
            ]
        )
        #expect(appIdentity.hasNegativeBasis)

        let domainIdentity = RuleSnapshotBuilder().build(
            priority: Self.priority(),
            contextPack: [
                ContextItemValue.domain(origin: "https://docs.google.com", addedAt: Self.reference)!
            ]
        )
        #expect(domainIdentity.hasNegativeBasis)
    }

    /// R-56.1's first condition, on the snapshot: a priority nobody could judge.
    @Test("a vague priority is not judgeable and an absent one has no active priority")
    func judgeabilityIsVisibleOnTheSnapshot() {
        #expect(!RuleSnapshotBuilder().build(priority: Self.priority("stuff")).hasJudgeablePriority)
        #expect(RuleSnapshotBuilder().build(priority: Self.priority()).hasJudgeablePriority)

        let none = RuleSnapshot.empty()
        #expect(!none.hasActivePriority)
        #expect(!none.hasJudgeablePriority)
        #expect(none.matchesRunningPolicy)
        #expect(none.skippedRuleCount == 0)
    }
}
