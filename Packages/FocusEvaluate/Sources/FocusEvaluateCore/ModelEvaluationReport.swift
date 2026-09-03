import FocusClassify
import FocusCore
import Foundation

/// **The paired-bucket taxonomy** (R-111).
///
/// Aggregate rates side by side prove nothing — both lanes can move for unrelated reasons.
/// Every case is folded into **exactly one** bucket, and the buckets are asserted to sum to the
/// case count, so a bucket cannot be quietly dropped: a case that fell out of the fold is not a
/// case that passed.
public enum ModelBucket: String, Sendable, CaseIterable, Codable, Hashable {
    /// Identical verdict and stage. Reported.
    case unchanged
    /// Deterministic `uncertain` became model `relevant`, **and** the cell said `rescue`.
    case rescued
    /// The cell said `rescue` and the model declined. The complement of the recall floor, and a
    /// known-safe posture: the app asks the question it would have asked anyway.
    case missedRescue
    /// **The cell said `hold` and the model rescued it anyway. Budget zero.**
    ///
    /// This is world knowledge overriding the person's own evidence, and it is the only bucket
    /// with a hard ceiling. A seduction is a prompt defect and the remedy is the prompt, never
    /// the threshold.
    case seduced
    /// The cell said `hold` and the model declined. Reported — the tier working correctly.
    case declined
    /// **A mandating case changed at all, or a model answer reached `unrelated`. Budget zero.**
    ///
    /// `ModelAnswer` has no `unrelated` case, so the second half is unrepresentable rather than
    /// merely forbidden; the bucket exists so that the report says so in a number a reader can
    /// check, rather than only in a type a reader has to trust.
    case impossible
}

/// One case, as both lanes saw it.
public struct ModelPairedCase: Sendable, Equatable, Codable {
    public let id: String
    public let row: String
    public let column: String
    public let expectation: ModelExpectation
    public let deterministicStage: String
    public let deterministicVerdict: String
    public let modelStage: String
    public let modelVerdict: String
    public let bucket: ModelBucket
}

/// **Lane 2's own report type.**
///
/// Not a `status` field bolted onto `EvaluationReport`: adding one would change lane 1's JSON,
/// and lane 1 is the shipping gate. The adversarial review named this and it is the whole reason
/// the two lanes have two types.
public struct ModelEvaluationReport: Sendable, Equatable, Codable {
    /// `"ran"` or `"skipped"`. **A skipped lane is recorded as an outcome, never a silent pass.**
    public let status: String
    /// The availability case, verbatim, when the lane was skipped.
    public let reason: String?
    public let generatedAt: String
    public let runID: String
    public let stamp: String
    public let promptVersion: Int
    public let osVersion: String
    public let modelCorpusDigest: String
    public let cellCount: Int
    public let rescuableCells: Int

    public let buckets: [String: Int]
    public let bucketSum: Int
    public let rescueRecall: Double
    public let seduced: Int
    public let impossible: Int
    public let mandateParityMismatches: Int
    public let rescueSetNotDeterministicallyUncertain: Int
    public let gridCompleteness: Double
    public let axesWithoutBothExpectations: [String]

    public let modelConsultationCount: Int
    public let modelAnsweredOnFirstJudgement: Int
    public let executableRungs: Int
    public let repeatCount: Int
    public let bucketVectorDigests: [String]
    public let unstable: [String]

    public let cases: [ModelPairedCase]
    public let failures: [String]

    public static func skipped(
        reason: String, runID: String, generatedAt: String
    ) -> ModelEvaluationReport {
        ModelEvaluationReport(
            status: "skipped", reason: reason, generatedAt: generatedAt, runID: runID,
            stamp: EngineStamp.current.cacheKey, promptVersion: 0,
            osVersion: RuleCascade.osVersionKey,
            modelCorpusDigest: "", cellCount: 0, rescuableCells: 0,
            buckets: [:], bucketSum: 0, rescueRecall: 0, seduced: 0, impossible: 0,
            mandateParityMismatches: 0, rescueSetNotDeterministicallyUncertain: 0,
            gridCompleteness: 0, axesWithoutBothExpectations: [],
            modelConsultationCount: 0, modelAnsweredOnFirstJudgement: 0,
            executableRungs: CascadeLadder.deterministic.executableRungs.count,
            repeatCount: 0, bucketVectorDigests: [], unstable: [], cases: [], failures: []
        )
    }
}

/// The committed lane-2 thresholds, in one place, so the gate script restates no number.
public enum ModelEvaluationGate {
    public struct Check: Sendable, Equatable {
        public let metric: String
        public let requirement: String
        public let observed: String
        public let held: Bool
    }

    /// **The contract half — T1, and it reddens the gate.**
    ///
    /// F-162's Court split, applied literally: these are claims about the *mechanism*, and every
    /// one of them is a promise this epic made about safety or about the shape of the evidence.
    /// A corpus that does not sum, a grid with a missing cell, a model answer that reached
    /// `unrelated`, a mandate that moved, or an answer on the classification path is a defect in
    /// what was built — not a fact about how good a language model is — and the gate fails on it.
    public static func contractChecks(for report: ModelEvaluationReport) -> [Check] {
        guard report.status == "ran" else { return [] }
        return [
            Check(
                metric: "bucketSum",
                requirement: "== cellCount (\(report.cellCount))",
                observed: "\(report.bucketSum)",
                held: report.bucketSum == report.cellCount
            ),
            Check(
                metric: "cellCount",
                requirement: ">= \(EvaluationPolicy.modelCorpusFloor)",
                observed: "\(report.cellCount)",
                held: report.cellCount >= EvaluationPolicy.modelCorpusFloor
            ),
            Check(
                metric: "gridCompleteness",
                requirement: "== \(EvaluationPolicy.modelGridCompleteness) (fails closed)",
                observed: String(format: "%.4f", report.gridCompleteness),
                held: report.gridCompleteness == EvaluationPolicy.modelGridCompleteness
            ),
            Check(
                metric: "axesWithoutBothExpectations",
                requirement: "empty — both axes must move",
                observed: report.axesWithoutBothExpectations.joined(separator: ", "),
                held: report.axesWithoutBothExpectations.isEmpty
            ),
            Check(
                metric: "impossible",
                requirement: "== 0",
                observed: "\(report.impossible)",
                held: report.impossible == 0
            ),
            Check(
                metric: "mandateParityMismatches",
                requirement: "== 0 (§2.4, measured rather than argued)",
                observed: "\(report.mandateParityMismatches)",
                held: report.mandateParityMismatches == 0
            ),
            Check(
                metric: "rescueSetNotDeterministicallyUncertain",
                requirement: "== 0 (a rescue the engine already solved is a corpus defect)",
                observed: "\(report.rescueSetNotDeterministicallyUncertain)",
                held: report.rescueSetNotDeterministicallyUncertain == 0
            ),
            Check(
                metric: "modelAnsweredOnFirstJudgement",
                requirement: "== 0 (R-103: never on the classification path)",
                observed: "\(report.modelAnsweredOnFirstJudgement)",
                held: report.modelAnsweredOnFirstJudgement == 0
            ),
            Check(
                metric: "modelConsultationCount",
                requirement: ">= cellCount (\(report.cellCount))",
                observed: "\(report.modelConsultationCount)",
                held: report.modelConsultationCount >= report.cellCount
            ),
            Check(
                metric: "cascade.executableRungs",
                requirement: "== \(EvaluationPolicy.declaredRungCount)",
                observed: "\(report.executableRungs)",
                held: report.executableRungs == EvaluationPolicy.declaredRungCount
            )
        ]
    }

    /// **The quality half — reported, and it does NOT redden the gate.**
    ///
    /// These are facts about how good the on-device model is at a question nobody has promised
    /// it can answer. They decide whether the tier is composed into the shipping ladder — see
    /// `ModelTierRelease` — and they are archived every run so the decision is made from an
    /// artefact rather than from an assertion about one. A quality half that could redden the
    /// gate would make gate-green depend on a model being present, which R-110 forbids outright.
    public static func qualityChecks(for report: ModelEvaluationReport) -> [Check] {
        guard report.status == "ran" else { return [] }
        let bucket = { (kind: ModelBucket) in report.buckets[kind.rawValue] ?? 0 }
        return [
            Check(
                metric: "seduced",
                requirement: "== 0 (a prompt defect, never a threshold)",
                observed: "\(report.seduced)",
                held: report.seduced == 0
            ),
            Check(
                metric: "rescueRecall",
                requirement: ">= \(EvaluationPolicy.modelRescueRecallFloor)",
                observed: String(format: "%.4f", report.rescueRecall),
                held: report.rescueRecall >= EvaluationPolicy.modelRescueRecallFloor
            ),
            Check(
                metric: "unstable",
                requirement: "empty across \(report.repeatCount) run(s)",
                observed: report.unstable.joined(separator: ", "),
                held: report.unstable.isEmpty
            ),
            Check(
                metric: "byStage.onDeviceModel (rescued + seduced)",
                requirement: "> 0 — the rung actually fired",
                observed: "\(bucket(.rescued) + bucket(.seduced))",
                held: bucket(.rescued) + bucket(.seduced) > 0
            )
        ]
    }

    /// Both halves, for a reader who wants the whole table.
    public static func checks(for report: ModelEvaluationReport) -> [Check] {
        contractChecks(for: report) + qualityChecks(for: report)
    }

    /// Whether the tier answered well enough to be composed into a shipping ladder.
    public static func qualityHolds(_ report: ModelEvaluationReport) -> Bool {
        report.status == "ran" && qualityChecks(for: report).allSatisfy(\.held)
    }

    /// What the gate stage exits on: the contract half alone.
    public static func passes(_ report: ModelEvaluationReport) -> Bool {
        contractChecks(for: report).allSatisfy(\.held)
    }
}
