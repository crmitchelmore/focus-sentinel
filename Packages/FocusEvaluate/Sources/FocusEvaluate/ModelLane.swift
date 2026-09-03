import FocusClassify
import FocusCore
import FocusEvaluateCore
import FocusModel
import Foundation

/// **Lane 2, as a separate entry point in the same executable.**
///
/// `FocusEvaluate --model` writes `evaluation-model.json` and never touches
/// `evaluation.json`. The two lanes share a process and share nothing else: lane 1 is the
/// shipping gate and stays deterministic, lane 2 is evidence and is availability-gated.
///
/// **A skipped lane is recorded as an outcome, never a silent pass.** When
/// `SystemLanguageModel.default.availability` is anything but `.available` the report says
/// `"status": "skipped"` with the availability case as its reason, the gate stage prints
/// `evaluation-model  SKIP  <reason>` and exits 0 — so gate-green can never depend on a model
/// being present, and a reader can always tell "it ran and passed" from "it did not run".
enum ModelLane {
    /// The bridge from `FocusModel`'s rung to the harness's protocol.
    ///
    /// It lives here, in the executable, rather than in `FocusEvaluateCore`, because the core is
    /// where the fold and the thresholds live and those must be testable in the unit lane on a
    /// Mac with Apple Intelligence off. Nothing in `FocusEvaluateCore` names `FocusModel`.
    struct SystemJudge: ModelLaneJudge {
        let rung: FocusModelRung
        func prime(_ request: ModelRequest) -> ModelAnswer { rung.primeSynchronously(request) }
        func cachedAnswer(for request: ModelRequest) -> ModelAnswer? {
            rung.cachedAnswer(for: request)
        }
        func reset() { rung.reset() }
        var promptVersion: Int { rung.promptVersion }
        var generationCount: Int { rung.generationCount }
    }

    static func run(corpusDirectory: URL, outputDirectory: URL, runID: String) -> Never {
        let generatedAt = EvaluationHarness.timestamp(SystemDateProvider().now)
        let destination = outputDirectory.appendingPathComponent("evaluation-model.json")

        func emit(_ report: ModelEvaluationReport) {
            do {
                try FileManager.default.createDirectory(
                    at: outputDirectory, withIntermediateDirectories: true
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(report).write(to: destination)
            } catch {
                FileHandle.standardError.write(
                    Data("FocusEvaluate --model: could not write \(destination.path)\n".utf8)
                )
            }
        }

        let rung = FocusModelRung()
        let availability = rung.availability
        guard availability.isExecutable else {
            emit(
                .skipped(
                    reason: availability.rawValue, runID: runID, generatedAt: generatedAt
                )
            )
            print("FocusEvaluate --model")
            print("report:   \(destination.path)")
            print("MODEL LANE: SKIPPED — \(availability.rawValue)")
            print("A skipped lane is not evidence. Gate-green never depends on it; epic-close does.")
            exit(0)
        }

        let corpus: ModelCorpus
        do {
            corpus = try ModelCorpusLoader.load(goldenCorpusDirectory: corpusDirectory)
        } catch {
            FileHandle.standardError.write(
                Data("FocusEvaluate --model: the model corpus did not load: \(error)\n".utf8)
            )
            exit(1)
        }

        let report = ModelEvaluationHarness(
            corpus: corpus,
            judge: SystemJudge(rung: rung),
            runID: runID,
            generatedAt: generatedAt
        ).run()
        emit(report)

        print("FocusEvaluate --model")
        print("corpus:   \(corpusDirectory.path)/\(ModelCorpusLoader.directoryName)")
        print("report:   \(destination.path)")
        print("runID:    \(report.runID)")
        print("stamp:    \(report.stamp)  promptVersion: \(report.promptVersion)")
        print("os:       \(report.osVersion)")
        print("model corpus digest: \(report.modelCorpusDigest)")
        print("")
        for kind in ModelBucket.allCases {
            print(String(format: "  %-14s %d", (kind.rawValue as NSString).utf8String!,
                         report.buckets[kind.rawValue] ?? 0))
        }
        print("")

        // **F-162's Court split, and the reason this stage cannot redden the gate on a number
        // about a language model.** The contract half is T1: a corpus that does not sum, a grid
        // with a missing cell, a model answer that reached `unrelated`, a mandate that moved, an
        // answer on the classification path. Those are defects in what was built and the stage
        // exits on them. The quality half is evidence: it decides whether the tier is composed
        // into the shipping ladder, it is archived every run, and it never gates the build —
        // because gate-green must never depend on a model being present (R-110).
        print("== contract (T1 — this stage exits on these)")
        let contract = ModelEvaluationGate.contractChecks(for: report)
        for check in contract {
            print("\(check.held ? "ok  " : "FAIL") \(check.metric): \(check.observed) "
                + "(requires \(check.requirement))")
        }
        print("")
        print("== quality (evidence — reported, never a gate)")
        for check in ModelEvaluationGate.qualityChecks(for: report) {
            print("\(check.held ? "ok  " : "MISS") \(check.metric): \(check.observed) "
                + "(requires \(check.requirement))")
        }
        print("")
        for paired in report.cases where paired.bucket == .seduced || paired.bucket == .impossible {
            print("BUDGET-ZERO \(paired.id) [\(paired.row)/\(paired.column)] "
                + "expected \(paired.expectation.rawValue), model said \(paired.modelVerdict) "
                + "at \(paired.modelStage)")
        }
        for paired in report.cases where paired.bucket == .missedRescue {
            print("missed rescue \(paired.id) [\(paired.row)/\(paired.column)]")
        }

        print("")
        print("MODEL LANE QUALITY: \(ModelEvaluationGate.qualityHolds(report) ? "EARNED" : "NOT EARNED")")
        print("the ladder this build composes: "
            + "\(FocusModelRung.self) is \(ModelTierRelease.composesTheRung ? "" : "NOT ")in it "
            + "— \(ModelTierRelease.reason)")
        if contract.allSatisfy(\.held) {
            print("MODEL LANE CONTRACT: PASS")
            exit(0)
        }
        print("MODEL LANE CONTRACT: FAIL")
        exit(1)
    }
}
