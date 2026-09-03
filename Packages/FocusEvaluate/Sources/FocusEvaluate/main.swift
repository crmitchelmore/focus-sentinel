import FocusCore
import FocusEvaluateCore
import Foundation

// `FocusEvaluate` — the evaluation report as a **product**, not a test side effect (R-75).
//
// A report emitted as a side effect of a test run is a report whose existence depends on a test
// having been scheduled, and whose destination depends on an environment value `xcodebuild`
// does not carry into a SwiftPM test target's process — measured twice on this machine, and
// already documented in `build-gate.sh` for the snapshot lane. A plain process **does** carry
// its environment, which is the whole reason this target exists.
//
// It is a test-lane product and is deliberately not in the shipping graph: no application
// target links it, `check-boundaries.sh` asserts that rather than assuming it, and the product
// list `FocusSentinel.app` builds is unchanged.
//
//   FOCUS_EVAL_OUT      where evaluation.json is written. Default $TMPDIR/focus-eval
//   FOCUS_GATE_RUN_ID   the gate's per-run token, stamped into the report (R-75.2)
//   FOCUS_CORPUS_DIR    the golden corpus directory. Defaults to this source file's own tree
//
// Exit status: 0 when the report was written and every committed threshold held; 1 otherwise.
// The report is written **before** the thresholds are judged, so a red run still leaves the
// artefact the gate archives and a reviewer reads.

let environment = ProcessInfo.processInfo.environment

/// The corpus, found the same way in both processes.
///
/// The gate recomputes the corpus digest from the working tree and refuses a report that does
/// not match (R-75.5), so this executable has to read the *tree* rather than a bundled copy —
/// otherwise the two could diverge and the check would be comparing a copy against itself.
/// `#filePath` resolves to this file inside `Packages/FocusEvaluate/Sources/FocusEvaluate/`, so
/// three steps up is the package root and the corpus sits under its test target's resources.
func defaultCorpusDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()      // FocusEvaluate/
        .deletingLastPathComponent()      // Sources/
        .deletingLastPathComponent()      // Packages/FocusEvaluate/
        .appendingPathComponent("Tests")
        .appendingPathComponent("FocusEvaluateTests")
        .appendingPathComponent("Resources")
        .appendingPathComponent(CorpusLoader.goldenCorpusDirectoryName)
}

let corpusDirectory = environment["FOCUS_CORPUS_DIR"].map(URL.init(fileURLWithPath:))
    ?? defaultCorpusDirectory()

let temporaryRoot = environment["TMPDIR"] ?? NSTemporaryDirectory()
let outputDirectory = URL(
    fileURLWithPath: environment["FOCUS_EVAL_OUT"]
        ?? URL(fileURLWithPath: temporaryRoot).appendingPathComponent("focus-eval").path
)

// A run with no token is a local run, and it says so rather than borrowing a plausible-looking
// one. Stage 7d fails unless the token in the report is the gate's own, so a report written
// without one can never be mistaken for gate evidence.
let runID = environment["FOCUS_GATE_RUN_ID"] ?? "local-\(ProcessInfo.processInfo.processIdentifier)"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FocusEvaluate: \(message)\n".utf8))
    exit(1)
}

// **Lane 2 is a different entry point in the same executable, and it returns.**
//
// `--model` writes `evaluation-model.json` and never touches `evaluation.json`. Lane 1 below is
// the shipping gate and stays deterministic; lane 2 is evidence, availability-gated, and exits 0
// on a skip so it can never redden the gate on a Mac with Apple Intelligence off.
if CommandLine.arguments.contains("--model") {
    ModelLane.run(
        corpusDirectory: corpusDirectory, outputDirectory: outputDirectory, runID: runID
    )
}

let corpus: GoldenCorpus
do {
    corpus = try CorpusLoader.load(directory: corpusDirectory)
    try corpus.validateComplete()
} catch {
    fail("the corpus at \(corpusDirectory.path) did not load: \(error)")
}

let harness = EvaluationHarness(
    corpus: corpus,
    runID: runID,
    // R-26's injected wall clock rather than a bare `Date()`: the report's `generatedAt` is a
    // timestamp a person reads, and every timestamp in this programme comes from a DateProvider.
    generatedAt: EvaluationHarness.timestamp(SystemDateProvider().now)
)
let report = harness.run()

do {
    try FileManager.default.createDirectory(
        at: outputDirectory, withIntermediateDirectories: true
    )
    try report.data.write(to: outputDirectory.appendingPathComponent("evaluation.json"))
} catch {
    fail("could not write the report into \(outputDirectory.path): \(error)")
}

print("FocusEvaluate")
print("corpus:   \(corpusDirectory.path)")
print("report:   \(outputDirectory.appendingPathComponent("evaluation.json").path)")
print("runID:    \(report.runID)")
print("stamp:    \(report.stamp)  policyDigest: \(report.policyDigest)")
print("corpus digest: \(report.corpusDigest)")
print("")

let checks = EvaluationGate.checks(for: report)
for check in checks { print(check.line) }
print("")

for failure in report.failures {
    print("FAILURE \(failure.id): expected \(failure.expected)")
    print("        actual   \(failure.actual)")
    print("        \(failure.note)")
}

if checks.allSatisfy(\.passed) {
    print("EVALUATION RESULT: PASS")
    exit(0)
} else {
    print("EVALUATION RESULT: FAIL")
    exit(1)
}
