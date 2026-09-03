import FocusClassify
import FocusCore
import Foundation

/// Runs one model-corpus cell through a composition, deterministic or composed.
///
/// It exists separately from `CorpusRunner` because the two answer different questions and
/// share nothing but a snapshot builder: `CorpusRunner` asserts a committed expectation about a
/// case, while this one **pairs** two compositions over the same input and hands the pair to the
/// bucket fold. Folding lane 2 into `CorpusRunner` would have meant adding a `status` to the
/// shared report, which is exactly the shape the adversarial review told us not to take.
public struct ModelCorpusRunner: Sendable {
    private let normalizer: TokenNormalizer
    private let scorer: SimilarityScorer
    private let builder: RuleSnapshotBuilder

    public init(
        normalizer: TokenNormalizer = TokenNormalizer(),
        scorer: SimilarityScorer = SimilarityScorer()
    ) {
        self.normalizer = normalizer
        self.scorer = scorer
        self.builder = RuleSnapshotBuilder(normalizer: normalizer, scorer: scorer)
    }

    public func snapshot(_ cell: ModelCorpusCell) -> RuleSnapshot {
        builder.build(
            priority: PriorityInput(
                id: Self.priorityID(for: cell),
                revision: cell.priority.revision,
                intent: cell.priority.intent
            ),
            // **Identity-free, always.** `noNegativeBasis` is a property of the priority, not of
            // the subject: it fires when the pack holds fewer than `minimumNegativeBasisItems`
            // app or domain identities. An empty pack is what makes every cell reach the one
            // route the grid probes.
            contextPack: []
        )
    }

    public func evidence(_ cell: ModelCorpusCell) -> ClassificationEvidence {
        ClassificationEvidence.make(
            input: ClassificationInput(
                bundleIdentifier: cell.evidence.bundleIdentifier,
                origin: cell.evidence.origin,
                titleTokens: cell.evidence.titleTokens
            ),
            dwell: cell.dwell,
            normalizer: normalizer
        )
    }

    /// The cell under the shipping composition: no port, `.deterministic` ladder.
    public func deterministic(_ cell: ModelCorpusCell) -> CascadeResolution {
        RuleCascade(heuristic: HeuristicClassifier(scorer: scorer), normalizer: normalizer)
            .evaluate(evidence: evidence(cell), snapshot: snapshot(cell))
    }

    /// The cell under a composition that has the model in its ladder.
    public func composed(_ cell: ModelCorpusCell, model: any ModelRung) -> CascadeResolution {
        RuleCascade(
            heuristic: HeuristicClassifier(scorer: scorer),
            model: model,
            ladder: CascadeLadder(modelAvailable: true),
            normalizer: normalizer
        ).evaluate(evidence: evidence(cell), snapshot: snapshot(cell))
    }

    /// What the heuristic said about reviewability for this cell — the property §2.3 turns on.
    public func finality(_ cell: ModelCorpusCell) -> RungFinality {
        HeuristicClassifier(scorer: scorer)
            .judge(evidence: evidence(cell), snapshot: snapshot(cell))?.finality ?? .decided
    }

    /// The request the cascade would build for this cell, so the harness can prime the cache the
    /// way the forty-five-second dwell does in production.
    public func request(_ cell: ModelCorpusCell, stamp: EngineStamp) -> ModelRequest? {
        let evidence = evidence(cell)
        guard let subject = evidence.subject,
              let token = NormalisedToken.normalised(subject.lowercased())
        else { return nil }
        return ModelRequest(
            cacheKey: stamp.verdictCacheKey(
                priorityID: Self.priorityID(for: cell),
                priorityRevision: cell.priority.revision,
                evidenceKey: "\(RuleCascade.osVersionKey)|\(subject)"
            ),
            priorityTokens: snapshot(cell).priorityTokens.tokens,
            subject: token,
            priorityRevision: cell.priority.revision
        )
    }

    /// A stable identifier per cell, derived from its id rather than minted, so two runs of the
    /// lane key the same cache entries and R-112's repeat comparison is comparing like with like.
    static func priorityID(for cell: ModelCorpusCell) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, byte) in Array(cell.id.utf8).enumerated() {
            bytes[index % 16] ^= byte &+ UInt8(index & 0x7F)
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
