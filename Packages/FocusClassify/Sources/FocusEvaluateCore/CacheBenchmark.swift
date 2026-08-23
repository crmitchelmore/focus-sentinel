import FocusClassify
import FocusCore
import Foundation

/// One capacity's result over the committed workload.
public struct CacheSweepPoint: Sendable, Equatable {
    public let capacity: Int
    public let hitRate: Double
    public let evictions: Int
    /// The 95th-percentile lookup cost in milliseconds, modelled from the **measured** cost of a
    /// real vector computation and a real cached read.
    public let p95: Double
}

/// R-74.4's answer for `similarityCacheCapacity`.
public struct CacheBenchmarkResult: Sendable, Equatable {
    public let capacity: Int
    public let hitRate: Double
    public let evictions: Int
    public let workloadSize: Int
    public let distinctKeys: Int
    public let sweep: [CacheSweepPoint]
    /// The smallest capacity whose p95 is within `cacheP95Tolerance` of the best measured — the
    /// derivation rule R-74.4 committed in advance.
    public let recommendedCapacity: Int
    /// Whether the workload can tell the four capacities apart at all.
    ///
    /// **The honest half of this benchmark, and the reason it is reported rather than left
    /// implicit.** Over this corpus no capacity evicts anything — the workload holds 47 distinct
    /// sentences and the smallest candidate is 64 — so all four points are identical. That is a
    /// real fact about this workload and it is published rather than smoothed over.
    ///
    /// It is **not** a reason to keep a larger number. R-74.4 committed the derivation rule
    /// before the sweep was run precisely so the answer would not be a judgement: the smallest
    /// capacity whose p95 is within ten per cent of the best. A flat sweep is evidence that 64
    /// suffices for this workload even though it is not evidence against 512, and the number the
    /// alternative preserves — 256 — is the un-evidenced value R-74.4 was written to replace,
    /// justified by a per-call latency figure that does not bear on capacity at all. So
    /// `EvaluationGate` requires `RelevancePolicy.similarityCacheCapacity` to equal
    /// `recommendedCapacity`, and this flag records what that recommendation rests on.
    ///
    /// The flag will flip: e07 turns window titles on, at which point the evidence-side sentence
    /// stream becomes the distinct titles of a working day, the sweep starts discriminating, the
    /// recommendation moves and the gate goes red until the constant is re-derived — which is
    /// R-74.4's own remedy, and the reason the assertion is worth having while it is quiet.
    public let isDiscriminating: Bool
}

/// Measures the bounded LRU against the corpus's **real** distribution of sentences.
///
/// P-116's 3.48 ms is a *per-call* figure and does not justify a capacity: capacity is about how
/// often a lookup is a hit, which is a property of the workload rather than of the call. So this
/// takes the exact key stream the scorer sees over a whole corpus run and answers, for each
/// candidate capacity, how many of those lookups would hit and how many entries would be
/// evicted.
///
/// Hit rate and eviction count are computed **exactly**, by simulating the same LRU the scorer
/// implements. The latency figure is the one part that must be measured rather than derived, and
/// it is: the cost of a real `vector(for:)` on an unseen key, and the cost of a cached read, both
/// timed on this machine, then applied to the exact hit/miss sequence. That is a real
/// measurement over a real workload — the two things a per-call figure was not.
public enum CacheBenchmark {
    /// The keys the scorer is asked for, in order, over a whole corpus run.
    ///
    /// Two sides feed it: the priority sentence of every snapshot (paid once per priority
    /// revision, R-65) and the evidence sentence of every classification that reaches the
    /// similarity stage. Both are lowercased and trimmed exactly as `SimilarityScorer.vector`
    /// keys them, so the simulation and the cache agree about what a key is.
    public static func workload(for corpus: GoldenCorpus) -> [String] {
        var keys: [String] = []
        for testCase in corpus.cases {
            if let priority = testCase.priority {
                keys.append(key(for: priority.prose))
            }
            if !testCase.evidence.titleTokens.isEmpty {
                keys.append(key(for: testCase.evidence.titleTokens.joined(separator: " ")))
            }
        }
        for sequence in corpus.sequences {
            if let priority = sequence.priority {
                keys.append(key(for: priority.prose))
            }
            for step in sequence.steps where !step.titleTokens.isEmpty {
                keys.append(key(for: step.titleTokens.joined(separator: " ")))
            }
        }
        return keys.filter { !$0.isEmpty }
    }

    static func key(for sentence: String) -> String {
        sentence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Run the sweep.
    public static func run(corpus: GoldenCorpus, scorer: SimilarityScorer) -> CacheBenchmarkResult {
        let keys = workload(for: corpus)
        let distinct = Set(keys).count

        // The live figures are taken **before** the cost probes below, which reset the cache and
        // then perform sixteen lookups of their own. Reading them afterwards would report the
        // benchmark's own traffic as the corpus run's, which is the sort of contamination that
        // makes a hit rate look better than the workload earned.
        let live = scorer.statistics

        let (missCost, hitCost) = measureCosts(scorer: scorer, keys: keys)

        var sweep: [CacheSweepPoint] = []
        for capacity in EvaluationPolicy.cacheSweepCapacities {
            let simulated = simulate(keys: keys, capacity: capacity)
            var samples: [Double] = []
            for wasHit in simulated.outcomes {
                samples.append(wasHit ? hitCost : missCost)
            }
            sweep.append(
                CacheSweepPoint(
                    capacity: capacity,
                    hitRate: simulated.hitRate,
                    evictions: simulated.evictions,
                    p95: percentile(samples, rank: EvaluationPolicy.latencyUpperRank)
                )
            )
        }

        let best = sweep.map(\.p95).min() ?? 0
        let tolerated = best * (1 + EvaluationPolicy.cacheP95Tolerance)
        let recommended = sweep.first { $0.p95 <= tolerated }?.capacity
            ?? RelevancePolicy.similarityCacheCapacity

        return CacheBenchmarkResult(
            capacity: live.capacity,
            hitRate: live.hitRate,
            evictions: live.evictions,
            workloadSize: keys.count,
            distinctKeys: distinct,
            sweep: sweep,
            recommendedCapacity: recommended,
            // The sweep can only discriminate once some capacity in it actually evicts.
            isDiscriminating: sweep.contains { $0.evictions > 0 }
        )
    }

    /// The exact LRU the scorer implements: most-recently-used at the back, evict from the
    /// front once the capacity is exceeded.
    static func simulate(
        keys: [String],
        capacity: Int
    ) -> (hitRate: Double, evictions: Int, outcomes: [Bool]) {
        var cache: Set<String> = []
        var recency: [String] = []
        var hits = 0
        var evictions = 0
        var outcomes: [Bool] = []

        for key in keys {
            let hit = cache.contains(key)
            outcomes.append(hit)
            if hit {
                hits += 1
            } else {
                cache.insert(key)
            }
            if let index = recency.firstIndex(of: key) { recency.remove(at: index) }
            recency.append(key)
            while recency.count > capacity {
                let oldest = recency.removeFirst()
                cache.remove(oldest)
                evictions += 1
            }
        }

        let rate = keys.isEmpty ? 0 : Double(hits) / Double(keys.count)
        return (rate, evictions, outcomes)
    }

    /// The two costs, measured on this machine rather than assumed.
    static func measureCosts(
        scorer: SimilarityScorer,
        keys: [String]
    ) -> (miss: Double, hit: Double) {
        let clock = ContinuousClock()
        let sample = Array(Set(keys)).sorted().prefix(EvaluationPolicy.cacheCostSampleCount)
        guard !sample.isEmpty else { return (0, 0) }

        // A miss: the scorer's cache is cleared first so every one of these is a real
        // computation rather than a read of something an earlier stage warmed.
        scorer.resetCache()
        var missTotal = Duration.zero
        for key in sample {
            let started = clock.now
            _ = scorer.vector(for: key)
            missTotal += clock.now - started
        }

        // A hit: the same keys, now in the cache.
        var hitTotal = Duration.zero
        for key in sample {
            let started = clock.now
            _ = scorer.vector(for: key)
            hitTotal += clock.now - started
        }

        return (
            milliseconds(missTotal) / Double(sample.count),
            milliseconds(hitTotal) / Double(sample.count)
        )
    }

    /// Nearest-rank, which does not interpolate between two measurements that were never taken.
    public static func percentile(_ samples: [Double], rank: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let position = Int((rank * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(max(position, 0), sorted.count - 1)]
    }

    public static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * EvaluationPolicy.millisecondsPerSecond
            + Double(components.attoseconds) / EvaluationPolicy.attosecondsPerMillisecond
    }
}
