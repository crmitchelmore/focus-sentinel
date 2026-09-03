import FocusClassify
import FocusCore
import Foundation

/// What the harness needs of a model, so that lane 2 can be driven with the system model, with
/// a stub, or with the mutation witness's yes-to-everything model.
///
/// It is `FocusEvaluateCore`'s own protocol rather than `FocusModel`'s concrete type, so that
/// the fold, the buckets and every threshold in `ModelEvaluationGate` are testable in the unit
/// lane on a Mac with Apple Intelligence off — which is most Macs, and which is exactly the
/// condition under which a proof must still be able to fail.
public protocol ModelLaneJudge: Sendable {
    /// Ask, wait, and remember. Lane 2 pays the wait explicitly where production pays it in the
    /// forty-five seconds a question already waits out.
    func prime(_ request: ModelRequest) -> ModelAnswer
    /// The cache read the cascade performs. Must return what `prime` recorded, and `nil` before.
    func cachedAnswer(for request: ModelRequest) -> ModelAnswer?
    func reset()
    var promptVersion: Int { get }
    var generationCount: Int { get }
}

/// **Lane 2**: the same cells through both compositions, folded into the paired buckets.
public struct ModelEvaluationHarness: Sendable {
    private let corpus: ModelCorpus
    private let runner: ModelCorpusRunner
    private let judge: any ModelLaneJudge
    private let runID: String
    private let generatedAt: String
    private let repeats: Int

    public init(
        corpus: ModelCorpus,
        judge: any ModelLaneJudge,
        runID: String,
        generatedAt: String,
        repeats: Int = EvaluationPolicy.modelLaneRepeatCount,
        runner: ModelCorpusRunner = ModelCorpusRunner()
    ) {
        self.corpus = corpus
        self.judge = judge
        self.runID = runID
        self.generatedAt = generatedAt
        self.repeats = repeats
        self.runner = runner
    }

    public func run() -> ModelEvaluationReport {
        let stamp = EngineStamp.current

        // R-112. The whole corpus, `modelLaneRepeatCount` times, with the cache cleared between
        // runs so each one really re-asks. A language model is not a pure function and this does
        // not pretend it is: the bucket assignment of every cell must be identical across all
        // three, and anything that differs is `unstable` with a ceiling of zero.
        var passes: [[String: ModelBucket]] = []
        var lastCases: [ModelPairedCase] = []
        var consultations = 0
        var answeredOnFirstJudgement = 0

        for pass in 0..<max(repeats, 1) {
            judge.reset()
            var buckets: [String: ModelBucket] = [:]
            var cases: [ModelPairedCase] = []

            for cell in corpus.cells {
                let deterministic = runner.deterministic(cell)

                // **R-103, measured rather than asserted.** Before anything is primed, the
                // composed cascade is asked once. A model that answered here would be a model on
                // the classification path, and the count below is the gate on it being zero.
                let cold = runner.composed(cell, model: CacheOnly(judge: judge))
                if cold.stage == .onDeviceModel { answeredOnFirstJudgement += 1 }

                // Then the dwell: the ask the cascade enqueued is paid, and the next judgement
                // of the same subject reads the cache — which is what e03's activation stream
                // does inside the forty-five seconds before the app could speak.
                if let request = runner.request(cell, stamp: stamp) {
                    _ = judge.prime(request)
                    consultations += 1
                }
                let warm = runner.composed(cell, model: CacheOnly(judge: judge))

                let bucket = Self.bucket(
                    cell: cell, deterministic: deterministic, model: warm
                )
                buckets[cell.id] = bucket
                if pass == max(repeats, 1) - 1 {
                    cases.append(
                        ModelPairedCase(
                            id: cell.id, row: cell.row, column: cell.column,
                            expectation: cell.modelExpectation,
                            deterministicStage: deterministic.stage.rawValue,
                            deterministicVerdict: deterministic.verdict.rawValue,
                            modelStage: warm.stage.rawValue,
                            modelVerdict: warm.verdict.rawValue,
                            bucket: bucket
                        )
                    )
                }
            }
            passes.append(buckets)
            if !cases.isEmpty { lastCases = cases }
        }

        let final = passes.last ?? [:]
        let unstable = corpus.cells
            .map(\.id)
            .filter { id in Set(passes.map { $0[id] }).count > 1 }

        var counts: [String: Int] = [:]
        for kind in ModelBucket.allCases { counts[kind.rawValue] = 0 }
        for bucket in final.values { counts[bucket.rawValue, default: 0] += 1 }

        let rescued = counts[ModelBucket.rescued.rawValue] ?? 0
        let missed = counts[ModelBucket.missedRescue.rawValue] ?? 0
        let recall = rescued + missed == 0 ? 0 : Double(rescued) / Double(rescued + missed)

        // Every cell whose expectation is `rescue` must be `uncertain` in lane 1. A rescue set
        // containing a case the deterministic engine already solved would inflate the recall for
        // free, which is the corpus defect this counts rather than trusts.
        let notUncertain = lastCases.filter {
            $0.expectation == .rescue && $0.deterministicVerdict != Verdict.uncertain.rawValue
        }.count

        // §2.4's safety theorem, as a per-case equality rather than an argument. Nothing the
        // model says can mandate, because the model is consulted only where the deterministic
        // answer was already non-mandating.
        let parityMismatches = lastCases.filter {
            ($0.deterministicVerdict == Verdict.unrelated.rawValue)
                != ($0.modelVerdict == Verdict.unrelated.rawValue)
        }.count

        return ModelEvaluationReport(
            status: "ran",
            reason: nil,
            generatedAt: generatedAt,
            runID: runID,
            stamp: stamp.cacheKey,
            promptVersion: judge.promptVersion,
            osVersion: RuleCascade.osVersionKey,
            modelCorpusDigest: corpus.digestString,
            cellCount: corpus.cellCount,
            rescuableCells: corpus.rescueCount,
            buckets: counts,
            bucketSum: final.count,
            rescueRecall: recall,
            seduced: counts[ModelBucket.seduced.rawValue] ?? 0,
            impossible: counts[ModelBucket.impossible.rawValue] ?? 0,
            mandateParityMismatches: parityMismatches,
            rescueSetNotDeterministicallyUncertain: notUncertain,
            gridCompleteness: corpus.files.map(\.completeness).min() ?? 0,
            axesWithoutBothExpectations: corpus.files.flatMap(\.axesWithoutBothExpectations),
            modelConsultationCount: consultations,
            modelAnsweredOnFirstJudgement: answeredOnFirstJudgement,
            executableRungs: CascadeLadder(modelAvailable: true).executableRungs.count,
            repeatCount: max(repeats, 1),
            bucketVectorDigests: passes.map { Self.digest(of: $0, order: corpus.cells.map(\.id)) },
            unstable: unstable,
            cases: lastCases,
            // Filled by the caller after the checks run: a metric that fails without naming the
            // case that failed it is a metric that costs an hour.
            failures: []
        )
    }

    /// **The fold**, and it is total over the case space by construction.
    static func bucket(
        cell: ModelCorpusCell,
        deterministic: CascadeResolution,
        model: CascadeResolution
    ) -> ModelBucket {
        // A model answer that reached `unrelated` is unrepresentable — `ModelAnswer` has no such
        // case — but the report says so in a number rather than only in a type.
        if model.verdict == .unrelated && deterministic.verdict != .unrelated { return .impossible }
        if deterministic.verdict == .unrelated && model.verdict != .unrelated { return .impossible }

        let rescuedByModel = model.stage == .onDeviceModel && model.verdict == .relevant
        switch (cell.modelExpectation, rescuedByModel) {
        case (.rescue, true): return .rescued
        case (.rescue, false): return .missedRescue
        case (.hold, true): return .seduced
        case (.hold, false):
            return deterministic.stage == model.stage ? .declined : .unchanged
        }
    }

    static func digest(of buckets: [String: ModelBucket], order: [String]) -> String {
        var accumulated = Data()
        for id in order {
            accumulated.append(contentsOf: Array(id.utf8))
            accumulated.append(contentsOf: Array((buckets[id]?.rawValue ?? "-").utf8))
        }
        return String(format: "0x%016lx", FNV1a.hash(accumulated))
    }
}

/// A `ModelRung` that only ever reads. It is what the cascade is handed in both halves of the
/// pairing, so the cascade cannot pay for a generation on the classification path even in the
/// harness — which is the property `modelAnsweredOnFirstJudgement == 0` measures.
struct CacheOnly: ModelRung {
    let judge: any ModelLaneJudge
    var promptVersion: Int { judge.promptVersion }
    func cachedAnswer(for request: ModelRequest) -> ModelAnswer? { judge.cachedAnswer(for: request) }
    func request(_ request: ModelRequest) {}
    func invalidate(subject: String) {}
    func reset() {}
}
