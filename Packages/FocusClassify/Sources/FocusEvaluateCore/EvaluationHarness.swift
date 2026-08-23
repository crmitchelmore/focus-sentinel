import FocusClassify
import FocusCore
import Foundation

/// Runs the whole committed corpus and turns it into evidence (R-67, F-152).
///
/// ## The instrument, and why it is not `XCTClockMetric`
///
/// P-121 measured the repository: `import Testing` in every one of the five packages' test
/// targets, and `import XCTest` in **zero** files. `XCTClockMetric` requires an `XCTestCase` and
/// is therefore unavailable, and adding XCTest would fork the test lane in two. So latency is
/// measured with `ContinuousClock` and the harness emits its own JSON — which is strictly better
/// evidence anyway: an `.xcresult` metric needs `xcresulttool` to read and cannot be diffed
/// between runs, and a JSON file can be, and is archived.
///
/// ## What is measured, and over what
///
/// * The **rates** are over the single-shot cases, which are the ones carrying a full committed
///   expectation. A sequence's claim is its transcript and its mandate count, and those live in
///   their own block.
/// * The **distributions** — `byStage`, `byBand`, `byUncertaintyReason`, the cascade depth and
///   the latency percentiles — are over *every classification the run performed*, single-shot
///   and sequence step alike, because that is the real distribution of what the engine did.
///   `classificationCount` is reported so those sums are checkable rather than assumed.
/// * `caseCount` is single-shot cases **plus** sequence fixtures, which is what `corpusFloor`
///   is a floor on. A corpus that met its total by dropping every sequence could not express
///   time at all.
///
/// ## The cold call, and what `latencyMs.max` is actually made of
///
/// `coldFirstCall` is measured once, on a scorer that has never been warmed, and is reported but
/// not gated. P-116 measured the embedding's cold load at 59.4 ms; `warmUp()` pays it at
/// construction, off the classification path, because a stutter that long inside a nudge
/// decision is a defect a person can feel. Reporting it is how a regression in *that* becomes
/// visible.
///
/// `latencyMs.max` is what found the defect this warm-up now closes, and the sequence is worth
/// recording because it is what a metric gate is *for*. Measured against an engine with only
/// the embedding warmed, the maximum over a whole corpus run was 57–61 ms — against a p95 of
/// 0.86 ms and a median of 0.014 ms — and a second pass over the identical corpus in the same
/// process gave a maximum of 1 ms. Every spike was `NaturalLanguage` initialising a tagger model
/// on its first real use: one-time, process-wide, and squarely on the classification path. It
/// took this metric over its committed ceiling on one run in three.
///
/// The ceiling was doing exactly what P-116 put it there to do — *"`warmUp()` moves it off this
/// path, and 60 ms is the ceiling that proves it did"* — and it was telling the truth: the
/// warm-up moved the embedding's load off the path and left the normaliser's on it. So
/// `TokenNormalizer.warmUp()` was added and `DeterministicRelevanceEngine.warmUp()` now calls
/// both. The corpus maximum is 3.1 ms, and a person's first activation no longer stutters.
public struct EvaluationHarness: Sendable {
    public let corpus: GoldenCorpus
    public let runID: String
    public let generatedAt: String

    public init(corpus: GoldenCorpus, runID: String, generatedAt: String) {
        self.corpus = corpus
        self.runID = runID
        self.generatedAt = generatedAt
    }

    /// An ISO-8601 instant from an injected wall clock, so a caller that wants a deterministic
    /// report can supply one.
    public static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    public func run() -> EvaluationReport {
        // Pass one, cold: reported, never gated. See `measureColdPass` for what it is for.
        let cold = measureColdPass()

        // Both halves of the warm-up, exactly as the composition root performs it: the
        // embedding's load and the normaliser's tagger models. Measuring a corpus against a
        // half-warmed engine would report `NaturalLanguage`'s one-time initialisation as this
        // engine's per-classification cost, which is a true number about the wrong thing.
        let normalizer = TokenNormalizer()
        normalizer.warmUp()
        let scorer = SimilarityScorer()
        scorer.warmUp()
        let runner = CorpusRunner(normalizer: normalizer, scorer: scorer)
        let replay = SequenceReplayHarness(runner: runner)

        var latencies: [Duration] = []
        var byStage: [CascadeStage: Int] = [:]
        var byBand: [EvidenceBand: Int] = [:]
        var byReason: [UncertaintyReason: Int] = [:]
        var depths: [Int] = []
        var failures: [EvaluationFailure] = []

        var falseNudges = 0
        var notMandatedExpected = 0
        var misses = 0
        var mandatedExpected = 0
        var uncertain = 0

        var adversarialTotal = 0
        var adversarialControls = 0
        var adversarialUncertain = 0
        var adversarialFalseNudges = 0
        var adversarialNotMandatedExpected = 0

        for testCase in corpus.cases {
            let outcome = runner.run(testCase)
            latencies.append(contentsOf: outcome.latencies)
            byStage[outcome.stage, default: 0] += 1
            if let band = outcome.band { byBand[band, default: 0] += 1 }
            if let reason = outcome.uncertaintyReason { byReason[reason, default: 0] += 1 }
            depths.append(outcome.consultedDepth)

            if let mismatch = runner.compare(testCase, to: outcome) {
                failures.append(
                    EvaluationFailure(
                        id: testCase.id,
                        expected: describe(testCase.expect),
                        actual: describe(outcome.asExpectation),
                        note: mismatch.differences.joined(separator: "; ")
                    )
                )
            }

            let expectedMandate = testCase.expect.eligibility == .mandated
            if expectedMandate {
                mandatedExpected += 1
                if !outcome.isMandated { misses += 1 }
            } else {
                notMandatedExpected += 1
                if outcome.isMandated { falseNudges += 1 }
            }
            if outcome.verdict == .uncertain { uncertain += 1 }

            guard !testCase.families.isEmpty else { continue }
            adversarialTotal += 1
            if testCase.isNegativeControl {
                adversarialControls += 1
            } else if outcome.verdict == .uncertain {
                adversarialUncertain += 1
            }
            if !expectedMandate {
                adversarialNotMandatedExpected += 1
                if outcome.isMandated { adversarialFalseNudges += 1 }
            }
        }

        var sequenceMandates = 0
        var transcript = ""
        for fixture in corpus.sequences.sorted(by: { $0.id < $1.id }) {
            let replayed = replay.replay(fixture)
            sequenceMandates += replayed.mandateCount
            transcript += "\(fixture.id)\n\(replayed.text)\n"
            for record in replayed.records {
                byStage[record.stage, default: 0] += 1
                if let band = record.band { byBand[band, default: 0] += 1 }
            }
            if let mismatch = replay.compare(fixture, to: replayed) {
                failures.append(
                    EvaluationFailure(
                        id: fixture.id,
                        expected: "\(fixture.expectMandates) mandate(s)",
                        actual: "\(replayed.mandateCount) mandate(s)",
                        note: mismatch.differences.joined(separator: "; ")
                    )
                )
            }
        }

        let cache = CacheBenchmark.run(corpus: corpus, scorer: scorer)

        let samples = latencies.map(CacheBenchmark.milliseconds)
        let classificationCount = byStage.values.reduce(0, +)

        return EvaluationReport(
            stamp: EngineStamp.current
                .withEmbeddingRevision(scorer.isAvailable ? scorer.embeddingRevision : 0)
                .cacheKey,
            policyDigest: RelevancePolicy.digestHex,
            caseCount: corpus.caseCount,
            corpusFloor: EvaluationPolicy.corpusFloor,
            classificationCount: classificationCount,
            generatedAt: generatedAt,
            runID: runID,
            corpusDigest: FNV1a.hex(corpus.digest),
            perFile: corpus.files
                .map { ($0.name, $0.cases.count) }
                .sorted { $0.0 < $1.0 }
                + [(CorpusLoader.sequencesDirectoryName, corpus.sequences.count)],
            overall: EvaluationRates(
                falseNudgeRate: rate(falseNudges, over: notMandatedExpected),
                missRate: rate(misses, over: mandatedExpected),
                uncertaintyRate: rate(uncertain, over: corpus.cases.count),
                denominator: corpus.cases.count
            ),
            adversarial: AdversarialSummary(
                caseCount: adversarialTotal,
                familyCount: Set(corpus.adversarial.flatMap(\.families)).count,
                negativeControlCount: adversarialControls,
                uncertaintyRate: rate(
                    adversarialUncertain, over: adversarialTotal - adversarialControls
                ),
                falseNudgeRate: rate(adversarialFalseNudges, over: adversarialNotMandatedExpected)
            ),
            sequences: SequenceSummary(
                count: corpus.sequences.count,
                mandateCount: sequenceMandates,
                transcriptDigest: FNV1a.hash(transcript)
            ),
            cache: cache,
            latencyMs: LatencySummary(
                p50: CacheBenchmark.percentile(samples, rank: EvaluationPolicy.latencyMedianRank),
                p95: CacheBenchmark.percentile(samples, rank: EvaluationPolicy.latencyUpperRank),
                max: samples.max() ?? 0,
                coldFirstCall: cold.firstCall,
                coldMax: cold.max
            ),
            cascade: CascadeSummary(
                declaredRungs: CascadeStage.allCases.count,
                executableRungs: CascadePrecedence.executableRungs.count,
                meanDepth: depths.isEmpty
                    ? 0
                    : Double(depths.reduce(0, +)) / Double(depths.count),
                maxDepth: depths.max() ?? 0
            ),
            // Every stage and every reason, including the zeroes: `byStage.onDeviceModel == 0`
            // is an assertion the gate makes, and a key that vanished when its count did would
            // turn a red gate into a missing one.
            byStage: CascadeStage.allCases.map { ($0.rawValue, byStage[$0] ?? 0) },
            byUncertaintyReason: UncertaintyReason.allCases.map {
                ($0.rawValue, byReason[$0] ?? 0)
            },
            byBand: EvidenceBand.allCases.map { ($0.rawValue, byBand[$0] ?? 0) },
            failures: failures
        )
    }

    /// **Pass one: the whole corpus on an engine that has been warmed by nothing.**
    ///
    /// Two figures come out of it and neither is gated. `firstCall` is the very first
    /// classification a process ever performs — P-116's 59.4 ms embedding load lives here, and
    /// reporting it is how a regression in `warmUp()` becomes visible. `max` is the worst
    /// classification in the pass, which is where every remaining one-time framework cost shows
    /// up.
    ///
    /// It runs before the measured pass, which is what makes the measured pass *steady state* —
    /// and steady state is what the gated figures have to be if they are to mean anything. A
    /// maximum that swings between 3 ms and 61 ms depending on which fixture happened to be
    /// first is not a number two runs can be diffed on, and R-67's whole argument for a JSON
    /// report over an `.xcresult` metric is that it can be.
    ///
    /// **What the cold pass is measuring, recorded because it will matter to e07.**
    /// `NLTagger` loads a model the first time it meets a string it detects as a new language,
    /// and a two-word window title is detected as almost anything — `"budget lisbon"` reads as
    /// Indonesian, `"invoice"` as Romanian, `"sprint snooker"` as Dutch. Each first sighting
    /// costs 30–60 ms, once, process-wide. `TokenNormalizer.warmUp()` pays that up front for the
    /// six languages P-111 measured, which covers every prose string e04's SHIPPING path
    /// tokenises — the priority and the seed subject names — because F-03 is baseline-only and
    /// no title reaches the engine in this build. e07 turns titles on for real, and no bounded
    /// warm-up list can cover the languages a title might be mistaken for; the answer there is
    /// likely to be that a title need not be lemmatised in a language the engine cannot reason
    /// in at all. This pass is what will keep that visible until somebody does it.
    func measureColdPass() -> (firstCall: Double, max: Double) {
        let runner = CorpusRunner(normalizer: TokenNormalizer(), scorer: SimilarityScorer())
        let clock = ContinuousClock()
        var firstCall: Double = 0
        var worst: Double = 0

        for (index, testCase) in corpus.cases.enumerated() {
            let started = clock.now
            let outcome = runner.run(testCase)
            let elapsed = CacheBenchmark.milliseconds(clock.now - started)
            if index == 0 { firstCall = elapsed }
            worst = Swift.max(worst, outcome.latencies.map(CacheBenchmark.milliseconds).max() ?? 0)
        }
        return (firstCall, worst)
    }

    func rate(_ numerator: Int, over denominator: Int) -> Double {
        denominator == 0 ? 0 : Double(numerator) / Double(denominator)
    }

    func describe(_ expectation: CorpusExpectation) -> String {
        [
            expectation.verdict.rawValue,
            expectation.source.rawValue,
            expectation.stage.rawValue,
            expectation.band?.rawValue ?? "-",
            expectation.eligibility.encoded,
            expectation.clauses.map(\.rawValue).sorted().joined(separator: ",")
        ].joined(separator: "|")
    }
}
