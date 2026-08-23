import Foundation

/// Which engine produced a judgement.
///
/// The Court cut the multi-release registry and the management UI and kept *"one embedded
/// prompt/schema version stamp baked into F-45's cache keys, plus bundled versioned
/// fixtures"*, at T1, on the grounds that the verdict cache's correctness hard-depends on it.
/// This is that stamp (F-53, R-63).
///
/// Four of the five components count our own edits. The fifth does not, and it is the
/// load-bearing one: `embeddingRevision` is **read from the OS at runtime**. P-117 measured
/// `NLEmbedding.currentSentenceEmbeddingRevision(for: .english) == 1` on this Mac. If Apple
/// ships a new asset in a point release, every distance the engine computes changes — and a
/// cache keyed only on our own edits would serve stale verdicts for ever. That is the one
/// component no amount of discipline could supply.
public struct EngineStamp: Sendable, Equatable, Hashable, Codable {
    /// The shape of `ClassificationInput` / `ClassificationOutcome` / `Explanation`.
    public let schemaVersion: Int
    /// The `RelevancePolicy` constant set. Bumped whenever `RelevancePolicy.digest` changes.
    public let policyVersion: Int
    /// The stop list, the reverse-DNS head list and the seed table.
    public let lexiconVersion: Int
    /// `NLEmbedding.currentSentenceEmbeddingRevision(for: .english)`, read at **runtime**.
    ///
    /// `FocusCore` may not import `NaturalLanguage` (the R-14 matrix), so this package cannot
    /// read it and does not pretend to: `current` carries `0`, meaning *no embedding revision
    /// has been read*, and `FocusClassify` — which may import it — supplies the real value
    /// through `withEmbeddingRevision(_:)` when the engine is built.
    public let embeddingRevision: Int
    /// The model prompt/schema version. **`0` in this build — there is no model.** e06 sets it.
    public let promptVersion: Int

    public init(
        schemaVersion: Int,
        policyVersion: Int,
        lexiconVersion: Int,
        embeddingRevision: Int,
        promptVersion: Int
    ) {
        self.schemaVersion = schemaVersion
        self.policyVersion = policyVersion
        self.lexiconVersion = lexiconVersion
        self.embeddingRevision = embeddingRevision
        self.promptVersion = promptVersion
    }

    /// This build's stamp, before any embedding revision has been read.
    ///
    /// `policyVersion` moves with `RelevancePolicy.digest`: re-recording that digest without
    /// bumping this is the change `RelevancePolicyTests` and `EngineStampTests` exist to
    /// refuse.
    public static let current = EngineStamp(
        schemaVersion: 1,
        policyVersion: 1,
        lexiconVersion: 1,
        embeddingRevision: 0,
        promptVersion: 0
    )

    /// The same stamp with the OS-supplied sentence-embedding revision filled in.
    ///
    /// Called once, in `FocusClassify`, when the engine is constructed. A value of `0` means
    /// the embedding was never loaded — which is a different fact from revision 1 and keys
    /// differently, deliberately: a judgement made with no similarity signal must not be
    /// served from a cache filled by one that had it.
    public func withEmbeddingRevision(_ revision: Int) -> EngineStamp {
        EngineStamp(
            schemaVersion: schemaVersion,
            policyVersion: policyVersion,
            lexiconVersion: lexiconVersion,
            embeddingRevision: revision,
            promptVersion: promptVersion
        )
    }

    /// `"s1.p1.l1.e1.m0"` — short, sortable, and safe in a file name and a SwiftData column.
    public var cacheKey: String {
        "s\(schemaVersion).p\(policyVersion).l\(lexiconVersion).e\(embeddingRevision).m\(promptVersion)"
    }

    /// The full verdict-cache key e06 will use.
    ///
    /// `priorityRevision` is `FocusSchemaV3.PriorityTask.revision` — already shipped, and
    /// already documented in the schema as existing *"because the verdict cache e04 adds keys
    /// on it"*. e04 declares the format and proves an edited priority produces a different
    /// key; e06 adds the cache behind it.
    public func verdictCacheKey(
        priorityID: UUID,
        priorityRevision: Int,
        evidenceKey: String
    ) -> String {
        "\(cacheKey)|\(priorityID.uuidString)|\(priorityRevision)|\(evidenceKey)"
    }
}
