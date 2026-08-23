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
/// `latencyMs.max` needs reading with the same care, because it is **not** a steady-state
/// figure. Measured on this machine, the maximum over a whole corpus run is ~56 ms while p95 is
/// under 1 ms and p50 is 0.014 ms — and replaying the identical corpus a second time in the same
/// process gives a maximum of ~1 ms. Every one of those spikes is `NLTagger` loading a language
/// model the first time it meets a string it detects as a new language: `"budget lisbon"`,
/// `"invoice"`, `"iPhone Mirroring"`. They are one-time, process-wide and unrepeatable, which is
/// why the second pass is flat.
///
/// Two consequences worth committing rather than rediscovering. First, the ceiling of 60 ms is
/// met with about six per cent to spare, so a slower machine could redden this gate on a cost
/// that has nothing to do with the engine's logic. Second, all but one of those spikes are
/// provoked by `titleTokens`, which the **corpus** supplies and which no shipping path in e04
/// produces — F-03 is baseline-only. The exception is the seed-override guard tokenising
/// `"iPhone Mirroring"`, which a real session does reach; a warm-up over `SeedSubjectNames`
/// would move it off the classification path in the same way the embedding's load already is.
/// e07 turns titles on for real, and that is the epic in which this stops being a footnote.
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
        // The cold first call, before anything is warmed. A separate scorer, because the
        // measurement is meaningless on one that has already loaded the embedding.
        let coldFirstCall = measureColdFirstCall()

        let scorer = SimilarityScorer()
        scorer.warmUp()
        let runner = CorpusRunner(scorer: scorer)
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
                coldFirstCall: coldFirstCall
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

    /// P-116's cold load, on the classification path it is kept off.
    func measureColdFirstCall() -> Double {
        let cold = SimilarityScorer()
        let runner = CorpusRunner(scorer: cold)
        guard let first = corpus.cases.first else { return 0 }
        let clock = ContinuousClock()
        let started = clock.now
        _ = runner.run(first)
        return CacheBenchmark.milliseconds(clock.now - started)
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
