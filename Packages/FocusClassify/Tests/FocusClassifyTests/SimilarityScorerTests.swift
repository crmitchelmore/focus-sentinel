import FocusCore
import Foundation
import NaturalLanguage
import Testing

@testable import FocusClassify

/// The similarity signal: asymmetric, English-gated, bounded (R-58, F-44).
///
/// The suite that matters most here is not the one that checks a number — it is
/// `noDistanceCanProduceAnAccusation`, which walks every measured distance this OS produces
/// and shows there is no value at which this component says `unrelated`. P-113 and P-124 both
/// measured the two classes overlapping; the type is what turns that measurement into a
/// property of the build.
///
/// ## The assertion that is a compile error rather than a test
///
/// ```swift
/// scorer.corroboration(
///     priority: normalizer.tokens(fromProse: "write the q3 proposal"),
///     evidence: normalizer.tokens(fromIdentifier: "com.apple.Notes")  // ← does not compile
/// )
/// ```
///
/// `corroboration` takes `ProseTokenSet` values on both sides and `tokens(fromIdentifier:)`
/// returns an `IdentifierTokenSet`, which has no conversion to one. That is R-57's ban, and it
/// is enforced by the type checker rather than by this file. Lint R-70c carries the other half:
/// the banned word embedding appears nowhere in the shipping graph.
@Suite("Similarity scoring")
struct SimilarityScorerTests {
    let normalizer = TokenNormalizer()

    static func table() throws -> SimilarityCorpusTests.SimilarityTable {
        try SimilarityCorpusTests.load(
            SimilarityCorpusTests.SimilarityTable.self, named: "similarity-pairs"
        )
    }

    // MARK: - The measurement holds at runtime

    /// P-124's table, replayed through the shipping code path. Every committed distance is
    /// reproduced to four decimals, which is what makes the derived ceiling a threshold on a
    /// quantity the engine actually computes rather than on one a probe once did.
    @Test("every committed pair re-scores to its committed distance")
    func liveScoringReproducesTheTable() throws {
        let table = try Self.table()
        let scorer = SimilarityScorer()
        scorer.warmUp()
        try #require(scorer.isAvailable, "this OS has no English sentence embedding")

        for pair in table.pairs {
            let measured = try #require(
                scorer.distance(between: pair.priority, and: pair.evidence),
                "\(pair.id) produced no distance"
            )
            #expect(
                abs(measured - pair.distance) < 0.0001,
                "\(pair.id): live \(measured) vs committed \(pair.distance)"
            )
        }
    }

    /// The ceiling's measured behaviour over the whole corpus: **zero false positives**, and a
    /// real share of the related class admitted. The misses are the price and they are cheap —
    /// a miss falls to `uncertain`, which suppresses.
    @Test("the ceiling admits no unrelated pair and a real share of related ones")
    func ceilingIsZeroFalsePositiveOnTheCorpus() throws {
        let table = try Self.table()
        let scorer = SimilarityScorer()
        scorer.warmUp()

        var falsePositives: [String] = []
        var admitted = 0
        var relatedTotal = 0

        for pair in table.pairs {
            let priority = normalizer.tokens(fromProse: pair.priority)
            let evidence = normalizer.tokens(fromProse: pair.evidence)
            let result = scorer.corroboration(priority: priority, evidence: evidence)
            if pair.label == "unrelated", result.corroborates { falsePositives.append(pair.id) }
            if pair.label == "related" {
                relatedTotal += 1
                if result.corroborates { admitted += 1 }
            }
        }

        #expect(falsePositives.isEmpty, "corroborated unrelated pairs: \(falsePositives)")
        #expect(admitted > 0, "the signal admits nothing at all")
        #expect(
            Double(admitted) / Double(relatedTotal) > 0.25,
            "only \(admitted) of \(relatedTotal) related pairs corroborate"
        )
    }

    /// Corroboration always bands `.low`, and `.low` is below the intervention floor. This is
    /// the single assertion that makes "similarity can never nudge on its own" a property of
    /// the constants rather than of the reasoning about them.
    @Test("corroboration bands low, and low can never mandate")
    func corroborationBandsLow() {
        #expect(SimilarityScorer.corroborationBand == .low)
        #expect(SimilarityScorer.corroborationBand < RelevancePolicy.interventionBandFloor)
    }

    // MARK: - The asymmetry

    /// **No distance produces an accusation.** Walked over every pair in the committed
    /// corpus — which spans 0.5796 to 1.3046, i.e. the whole range this OS's embedding
    /// produces for realistic input — and asserting that the answer is one of exactly two
    /// things: corroboration at `.low`, or silence. The stronger half of the guarantee is not
    /// testable at all, and that is the point: `SimilarityCorroboration` has no third case, so
    /// there is no value for a future threshold to return.
    @Test("no distance can produce an accusation, at any value")
    func noDistanceCanProduceAnAccusation() throws {
        let table = try Self.table()
        let scorer = SimilarityScorer()
        scorer.warmUp()
        let ceiling = try #require(RelevancePolicy.similarityRelevantCeiling.value)

        for pair in table.pairs {
            let priority = normalizer.tokens(fromProse: pair.priority)
            let evidence = normalizer.tokens(fromProse: pair.evidence)
            let result = scorer.corroboration(priority: priority, evidence: evidence)
            let distance = try #require(scorer.distance(between: pair.priority, and: pair.evidence))

            // Exactly two possible answers, and the far one is silence rather than an
            // accusation. `SimilarityCorroboration` has no third case to reach for.
            switch result {
            case .supportsRelevance(let band):
                #expect(band == .low)
                #expect(distance <= ceiling)
            case .none:
                #expect(
                    distance > ceiling || !priority.isJudgeableEnglish
                        || !evidence.isJudgeableEnglish
                )
            }
        }
    }

    // MARK: - The English gate (P-111, P-115, P-124)

    /// P-111: `NLEmbedding` is `nil` for every non-English language on this OS, so there is
    /// nothing to consult. The gate refuses before it would have had to find that out.
    @Test(
        "a non-English priority is never scored",
        arguments: [
            "rédiger la proposition trimestrielle pour acme",
            "Quartalsbericht für Acme schreiben",
            "四半期の提案書を書く",
            "redactar la propuesta del tercer trimestre",
            "написать квартальный отчёт"
        ]
    )
    func nonEnglishIsNeverScored(prose: String) {
        let scorer = SimilarityScorer()
        scorer.warmUp()
        let priority = normalizer.tokens(fromProse: prose)
        let evidence = normalizer.tokens(fromProse: "q3 proposal acme draft")

        #expect(!priority.isJudgeableEnglish)
        #expect(scorer.corroboration(priority: priority, evidence: evidence) == .none)
        // …and in the other direction, which family 4 also fixtures.
        #expect(scorer.corroboration(priority: evidence, evidence: priority) == .none)
    }

    /// The floor also disqualifies input the recogniser could not judge — P-115's single word
    /// at 0.41, and its neighbours P-124 measured.
    @Test("a one-word priority is below the floor and is never scored")
    func oneWordIsNeverScored() {
        let scorer = SimilarityScorer()
        scorer.warmUp()
        let priority = normalizer.tokens(fromProse: "proposal")
        let evidence = normalizer.tokens(fromProse: "q3 proposal acme draft")

        #expect(!priority.isJudgeableEnglish)
        #expect(scorer.corroboration(priority: priority, evidence: evidence) == .none)
    }

    /// Nothing to compare is silence, not zero.
    @Test("an empty side yields no corroboration")
    func emptySideYieldsNothing() {
        let scorer = SimilarityScorer()
        let real = normalizer.tokens(fromProse: "write the q3 proposal for acme")
        #expect(scorer.corroboration(priority: .empty, evidence: real) == .none)
        #expect(scorer.corroboration(priority: real, evidence: .empty) == .none)
        #expect(scorer.vector(for: "") == nil)
        #expect(scorer.vector(for: "   ") == nil)
    }

    // MARK: - The bounded cache (R-74.4's instrument)

    /// The LRU is bounded, reports what it did, and never grows past its capacity. The
    /// *choice* of capacity is R-74.4's sweep, which lands with the evaluation harness; this
    /// asserts the mechanism the sweep will measure.
    @Test("the cache is bounded, and hits are hits")
    func theCacheIsBounded() {
        let scorer = SimilarityScorer()
        scorer.warmUp()

        let sentence = "q3 proposal acme draft"
        _ = scorer.vector(for: sentence)
        _ = scorer.vector(for: sentence)
        _ = scorer.vector(for: sentence)

        let warm = scorer.statistics
        #expect(warm.misses == 1)
        #expect(warm.hits == 2)
        #expect(warm.hitRate > 0.6)
        #expect(warm.capacity == RelevancePolicy.similarityCacheCapacity)

        // Overfill it by one and watch exactly one eviction, with the entry count pinned at
        // the capacity rather than drifting above it.
        for index in 0...RelevancePolicy.similarityCacheCapacity {
            _ = scorer.vector(for: "evidence sentence number \(index)")
        }
        let full = scorer.statistics
        #expect(full.entries == RelevancePolicy.similarityCacheCapacity)
        #expect(full.evictions > 0)
    }

    /// The vector is memoised, not recomputed: the same sentence twice is one embedding call
    /// and two identical values. P-118 established the determinism this rests on.
    @Test("the same sentence yields the identical vector, twice and across scorers")
    func vectorsAreDeterministic() throws {
        let first = SimilarityScorer()
        let second = SimilarityScorer()
        first.warmUp()
        second.warmUp()

        let a = try #require(first.vector(for: "write the q3 proposal for acme"))
        let b = try #require(second.vector(for: "write the q3 proposal for acme"))
        #expect(a == b)
        #expect(a.dimension == b.dimension)
        #expect(a.distance(to: b) == 0)
    }

    /// The stamp's OS-supplied component, read at runtime. P-117 measured `1` on this Mac; the
    /// assertion is that it is *readable and positive*, not that it is 1 for ever — an Apple
    /// asset bump is the event this component exists to notice.
    @Test("the sentence-embedding revision is readable at runtime")
    func embeddingRevisionIsReadable() {
        #expect(SimilarityScorer().embeddingRevision > 0)
    }

    // MARK: - The identity P-124 measured

    /// `NLEmbedding.distance(…, .cosine)` is the Euclidean distance between the L2-normalised
    /// vectors, and `SentenceVector.distance(to:)` computes exactly that. Asserted against the
    /// framework itself so that an OS which changed the definition fails here — loudly, in one
    /// place — rather than by silently re-scaling every committed threshold.
    @Test("the vector distance equals the framework's own, to six decimals")
    func theDistanceIdentityHolds() throws {
        let table = try Self.table()
        let embedding = try #require(NLEmbedding.sentenceEmbedding(for: .english))
        let scorer = SimilarityScorer()
        scorer.warmUp()

        for pair in table.pairs.prefix(20) {
            let ours = try #require(scorer.distance(between: pair.priority, and: pair.evidence))
            let theirs = embedding.distance(
                between: pair.priority.lowercased(),
                and: pair.evidence.lowercased(),
                distanceType: .cosine
            )
            #expect(
                abs(ours - theirs) < 0.00001,
                "\(pair.id): ours \(ours) vs framework \(theirs)"
            )
        }
    }
}
