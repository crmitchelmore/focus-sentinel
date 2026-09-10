import FocusCore
import Foundation
import NaturalLanguage

/// What the similarity signal is allowed to say.
///
/// **There is no case that could mean `unrelated`, at any distance.** That is not an omission
/// and it is not a default somebody can add a case beside: it is R-58, and it is forced by
/// measurement. P-113 found the two classes overlapping over sixteen pairs; P-124 quadrupled
/// the corpus and found **28 of 32** unrelated pairs sitting inside the related range, with 11
/// of 30 related pairs above the unrelated minimum. A rule of the form "further than X means
/// not your work" would accuse somebody on more than a third of their own evidence.
///
/// So the signal is **asymmetric**: it may corroborate `relevant` below a ceiling set strictly
/// below every measured unrelated distance, and it may never accuse. A test asserts no code
/// path in this package maps a distance to `.unrelated`; this type is what makes the test
/// about enforcement rather than about vigilance.
public enum SimilarityCorroboration: Sendable, Equatable, Hashable {
    /// The two sentences are close enough to support relevance, at the band R-56's table gives
    /// this route. Always `.low`, which is **below `interventionBandFloor`** — so similarity is
    /// structurally incapable of causing a nudge on its own.
    case supportsRelevance(band: EvidenceBand)
    /// No corroboration: too far, not English, no embedding, or nothing to compare.
    case none

    public var band: EvidenceBand? {
        switch self {
        case .supportsRelevance(let band): band
        case .none: nil
        }
    }

    public var corroborates: Bool { band != nil }
}

/// What the bounded LRU did, for `evaluation.json`'s `cache` block (R-74.4).
public struct SimilarityCacheStatistics: Sendable, Equatable, Hashable, Codable {
    public let capacity: Int
    public let entries: Int
    public let hits: Int
    public let misses: Int
    public let evictions: Int

    public var hitRate: Double {
        let total = hits + misses
        guard total > 0 else { return 0 }
        return Double(hits) / Double(total)
    }
}

/// The sentence-similarity signal: **English only, corroboration only, and bounded**.
///
/// Three rulings live in this one type, each forced by a measurement rather than chosen:
///
/// 1. **Sentence embeddings only.** `NLEmbedding.wordEmbedding` is banned from the shipping
///    graph by lint. P-112 measured its cross-domain separation at **0.017** on
///    `code~programming` versus `code~cooking`, and measured it *inverting* on
///    `proposal~invoice` (1.2665, both work) against `proposal~game` (1.2629, a distraction).
///    A signal that ranks a distraction closer than a colleague is not a signal.
///    `NLContextualEmbedding` is banned outright: its surface includes an asset *request*, and
///    a package whose whole guarantee is that it cannot reach the network may not name a type
///    that can ask for a download (SC-7).
/// 2. **English, at or above `languageConfidenceFloor`, on both sides.** P-111 measured
///    `NLEmbedding` returning `nil` for `fr`, `de`, `ja`, `zh-Hans` and `es` — word and
///    sentence, every one — so for anything else there is nothing to consult. Both routes end
///    at `uncertain`, which is the right answer to "I have no instrument for this".
/// 3. **Corroboration only.** See `SimilarityCorroboration`.
///
/// ## Cost, and where it is paid
///
/// P-116: a sentence vector is 1.75 ms, a sentence distance 3.48 ms, and the **cold load is
/// 59.4 ms**. So the priority side is computed once per priority revision (R-65); the evidence
/// side is memoised here in a bounded LRU of `RelevancePolicy.similarityCacheCapacity`
/// entries; the scorer runs only at the heuristic rung and only after overlap has declined, so
/// it costs nothing on a rule hit; and `warmUp()` pays the cold load at engine construction,
/// off the classification path, because a 59 ms stutter inside a nudge decision is a defect a
/// person can feel.
///
/// A `final class` with a lock rather than a value type, because an LRU is mutable state that
/// several classifications share. There is **no timer, no queue and no task** in it (R-70e):
/// the lock is held across a dictionary read and an embedding call and nothing else.
public final class SimilarityScorer: @unchecked Sendable {
    private let lock = NSLock()

    /// Loaded lazily and at most once. `nil` after loading means this OS has no English
    /// sentence embedding, which is a fact to fall through on rather than to retry.
    private var embedding: NLEmbedding?
    private var hasAttemptedLoad = false

    private var cache: [String: SentenceVector] = [:]
    /// Least-recently-used first. A plain array because the capacity is bounded at 256 and an
    /// intrusive list would be more machinery than the workload deserves.
    private var recency: [String] = []

    private var hits = 0
    private var misses = 0
    private var evictions = 0

    /// The dials the scorer reads (focus-exdi): the cache's capacity and the ceiling under
    /// which a distance may corroborate `relevant`. Guarded by the same lock as the cache.
    private var tunings: PolicyTunings

    public init(tunings: PolicyTunings = .shipped) {
        self.tunings = tunings
    }

    /// Take a person's dials. The cache is trimmed at once if the capacity fell.
    public func adopt(_ tunings: PolicyTunings) {
        lock.lock()
        defer { lock.unlock() }
        self.tunings = tunings
        evictIfNeededLocked()
    }

    // MARK: - Warm-up

    /// Load the embedding now, off the classification path.
    ///
    /// Called once by the composition root. Idempotent, and safe to call when there is no
    /// embedding to load: the failure is remembered so the 59 ms is never paid twice.
    public func warmUp() {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()
    }

    /// Whether an English sentence embedding is available at all. Read by the engine when it
    /// stamps itself, and by the tests that assert the fall-through.
    public var isAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()
        return embedding != nil
    }

    /// `NLEmbedding.currentSentenceEmbeddingRevision(for: .english)` — the one component of
    /// `EngineStamp` that no amount of discipline could supply, because it changes when Apple
    /// ships an asset and every distance the engine computes changes with it (P-117, R-63).
    public var embeddingRevision: Int {
        NLEmbedding.currentSentenceEmbeddingRevision(for: .english)
    }

    private func loadIfNeededLocked() {
        guard !hasAttemptedLoad else { return }
        hasAttemptedLoad = true
        embedding = NLEmbedding.sentenceEmbedding(for: .english)
    }

    // MARK: - Vectors

    /// The vector for a sentence, memoised.
    ///
    /// The key is the sentence exactly as `ProseTokenSet.sentence` normalised it — trimmed and
    /// lowercased — so two activations that produced the same evidence share one 1.75 ms call.
    public func vector(for sentence: String) -> SentenceVector? {
        let key = sentence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }

        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[key] {
            hits += 1
            touchLocked(key)
            return cached
        }
        misses += 1

        loadIfNeededLocked()
        guard let embedding, let components = embedding.vector(for: key),
              let vector = SentenceVector(components)
        else { return nil }

        cache[key] = vector
        touchLocked(key)
        evictIfNeededLocked()
        return vector
    }

    private func touchLocked(_ key: String) {
        if let index = recency.firstIndex(of: key) { recency.remove(at: index) }
        recency.append(key)
    }

    private func evictIfNeededLocked() {
        while recency.count > tunings.count(.similarityCacheCapacity) {
            let oldest = recency.removeFirst()
            cache.removeValue(forKey: oldest)
            evictions += 1
        }
    }

    /// The distance between two sentences, on the scale P-113 and P-124 measured.
    ///
    /// Exposed so a test can compare a live scoring against the committed table row by row;
    /// the engine never reads a distance, only a `SimilarityCorroboration`.
    public func distance(between first: String, and second: String) -> Double? {
        guard let left = vector(for: first), let right = vector(for: second) else { return nil }
        return left.distance(to: right)
    }

    public var statistics: SimilarityCacheStatistics {
        lock.lock()
        defer { lock.unlock() }
        return SimilarityCacheStatistics(
            capacity: tunings.count(.similarityCacheCapacity),
            entries: cache.count,
            hits: hits,
            misses: misses,
            evictions: evictions
        )
    }

    /// Forget every memoised vector, keeping the counters. Used by the capacity sweep, which
    /// has to measure a cold workload at each capacity.
    public func resetCache() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
        recency.removeAll()
    }

    // MARK: - Corroboration

    /// The engine's entry point: the priority side arrives already vectorised by the snapshot
    /// (R-65), and only the evidence side is scored here.
    ///
    /// **The parameter types are the ban.** Both sides are prose. `IdentifierTokenSet` — what
    /// `TokenNormalizer.tokens(fromIdentifier:)` returns — cannot be passed to anything on this
    /// type, so a bundle-identifier token reaching the embedding is a compile error rather than
    /// a review comment (R-57, P-112).
    public func corroboration(
        priorityVector: SentenceVector?,
        priorityLanguage: LanguageReading?,
        evidence: ProseTokenSet
    ) -> SimilarityCorroboration {
        // The gate, in the order that makes each refusal cheapest.
        guard RelevancePolicy.similarityRelevantCeiling.value != nil else { return .none }
        lock.lock()
        let tunings = self.tunings
        lock.unlock()
        let ceiling = tunings.value(.similarityRelevantCeiling)
        guard let priorityVector else { return .none }
        guard priorityLanguage?.isJudgeableEnglish(tunings: tunings) == true else { return .none }
        guard evidence.isJudgeableEnglish(tunings: tunings) else { return .none }
        guard let evidenceVector = vector(for: evidence.sentence) else { return .none }
        guard let distance = priorityVector.distance(to: evidenceVector) else { return .none }

        // The one comparison, and the only direction it can conclude in.
        guard distance <= ceiling else { return .none }
        return .supportsRelevance(band: Self.corroborationBand)
    }

    /// The convenience both sides of a test and the snapshot builder use: score prose against
    /// prose, vectorising the priority side here.
    public func corroboration(
        priority: ProseTokenSet,
        evidence: ProseTokenSet
    ) -> SimilarityCorroboration {
        corroboration(
            priorityVector: vector(for: priority.sentence),
            priorityLanguage: priority.language,
            evidence: evidence
        )
    }

    /// R-56's band table, this row: *"similarity below the ceiling, no overlap → `.low`"*.
    ///
    /// `.low` is below `RelevancePolicy.interventionBandFloor`, which is what makes the
    /// similarity signal structurally incapable of causing a nudge on its own — the design
    /// conclusion P-113 forces, expressed as a constant rather than as care.
    public static let corroborationBand: EvidenceBand = .low
}
