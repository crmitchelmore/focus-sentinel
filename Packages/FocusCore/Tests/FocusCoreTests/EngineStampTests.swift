import Foundation
import Testing

@testable import FocusCore

/// The stamp, and the cache key e06 will live or die by (R-63, F-53).
@Suite("Engine stamp")
struct EngineStampTests {
    /// The committed literal. Re-record it **only** together with the version component that
    /// moved — and, for `policyVersion`, together with `RelevancePolicyTests.committedDigest`.
    static let committedCacheKey = "s1.p2.l1.e0.m0"

    /// What the running engine stamps once `FocusClassify` has read
    /// `NLEmbedding.currentSentenceEmbeddingRevision(for: .english)`, measured `1` on this Mac
    /// (P-117). This is the value `evaluation.json` and both self-check JSONs carry.
    static let committedRuntimeCacheKey = "s1.p2.l1.e1.m0"

    @Test("the stamp's cache key equals its committed literal")
    func cacheKeyIsCommitted() {
        #expect(EngineStamp.current.cacheKey == Self.committedCacheKey)
        #expect(
            EngineStamp.current.withEmbeddingRevision(1).cacheKey == Self.committedRuntimeCacheKey
        )
    }

    @Test("there is no model in this build, and the stamp says so")
    func promptVersionIsZero() {
        #expect(EngineStamp.current.promptVersion == 0)
        #expect(EngineStamp.current.cacheKey.hasSuffix(".m0"))
    }

    /// `FocusCore` cannot read the embedding revision — it may not import `NaturalLanguage` —
    /// so `current` says *unread* rather than guessing `1`. A judgement made with no
    /// similarity signal keys differently from one made with it, which is the honest answer.
    @Test("the unread embedding revision is zero and keys differently from revision one")
    func unreadEmbeddingRevisionKeysDifferently() {
        #expect(EngineStamp.current.embeddingRevision == 0)
        #expect(
            EngineStamp.current.cacheKey != EngineStamp.current.withEmbeddingRevision(1).cacheKey
        )
    }

    /// The component that no amount of our own discipline could supply: an Apple asset bump
    /// changes every distance the engine computes, so it must change the key too.
    @Test("an OS embedding-asset bump changes the cache key by itself")
    func embeddingRevisionInvalidatesTheCache() {
        let keys = Set((0...3).map { EngineStamp.current.withEmbeddingRevision($0).cacheKey })
        #expect(keys.count == 4)
    }

    @Test("every component appears in the key, and moving any one of them moves the key")
    func everyComponentIsInTheKey() {
        let base = EngineStamp.current
        let variants = [
            EngineStamp(schemaVersion: 2, policyVersion: 1, lexiconVersion: 1, embeddingRevision: 0, promptVersion: 0),
            EngineStamp(schemaVersion: 1, policyVersion: 3, lexiconVersion: 1, embeddingRevision: 0, promptVersion: 0),
            EngineStamp(schemaVersion: 1, policyVersion: 1, lexiconVersion: 2, embeddingRevision: 0, promptVersion: 0),
            EngineStamp(schemaVersion: 1, policyVersion: 1, lexiconVersion: 1, embeddingRevision: 2, promptVersion: 0),
            EngineStamp(schemaVersion: 1, policyVersion: 1, lexiconVersion: 1, embeddingRevision: 0, promptVersion: 2)
        ]
        for variant in variants {
            #expect(variant.cacheKey != base.cacheKey)
        }
        #expect(Set(variants.map(\.cacheKey)).count == variants.count)
    }

    /// The corpus half of F-53's contract: **an edited priority invalidates every judgement
    /// about the old wording.** e06 adds the cache; e04 proves the key already changes.
    @Test("an edited priority revision produces a different verdict-cache key")
    func editedPriorityChangesTheKey() {
        let priority = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!
        let stamp = EngineStamp.current.withEmbeddingRevision(1)

        let third = stamp.verdictCacheKey(
            priorityID: priority, priorityRevision: 3, evidenceKey: "com.apple.Safari"
        )
        let fourth = stamp.verdictCacheKey(
            priorityID: priority, priorityRevision: 4, evidenceKey: "com.apple.Safari"
        )

        #expect(third != fourth)
        #expect(third == "s1.p2.l1.e1.m0|3F2504E0-4F89-11D3-9A0C-0305E82C3301|3|com.apple.Safari")

        // And so do a different priority and a different piece of evidence.
        #expect(
            stamp.verdictCacheKey(priorityID: UUID(), priorityRevision: 3, evidenceKey: "com.apple.Safari")
                != third
        )
        #expect(
            stamp.verdictCacheKey(priorityID: priority, priorityRevision: 3, evidenceKey: "com.apple.Notes")
                != third
        )
    }

    @Test("the stamp round-trips through Codable")
    func stampRoundTrips() throws {
        let stamp = EngineStamp.current.withEmbeddingRevision(1)
        let decoded = try JSONDecoder().decode(EngineStamp.self, from: JSONEncoder().encode(stamp))
        #expect(decoded == stamp)
        #expect(decoded.cacheKey == stamp.cacheKey)
    }

    /// The policy digest and the policy version move together or not at all. Stated here as
    /// well as in `RelevancePolicyTests` because the two literals are the pair a careless
    /// re-record breaks: changing the digest alone would leave e06's cache keyed on a version
    /// that no longer describes the constants.
    @Test("the policy version and the policy digest are re-recorded together")
    func policyVersionTracksTheDigest() {
        #expect(EngineStamp.current.policyVersion == 2)
        #expect(EngineStamp.current.policyVersion == EngineStamp.policyRevisions.count)
        for revision in EngineStamp.policyRevisions {
            #expect(!revision.isEmpty, "a policy revision with no reason is a version churning")
        }
        #expect(RelevancePolicy.digest == RelevancePolicyTests.committedDigest)
    }
}
