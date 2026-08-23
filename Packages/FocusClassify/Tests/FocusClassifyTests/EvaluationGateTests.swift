import FocusCore
import FocusEvaluateCore
import Foundation
import Testing

@testable import FocusClassify

/// The metric gate (R-67, R-75, §4.4).
///
/// Stage 7d of the build gate runs the `FocusEvaluate` product and fails on a number. This suite
/// asserts the **same** thresholds through the same `EvaluationGate` list, so `swift test` alone
/// still catches a metric regression and the two readers cannot disagree about what the gate is.
///
/// Three properties matter here as much as the numbers themselves.
///
/// **It fails on a shrinking corpus.** The easiest way to make a false-nudge rate go to zero is
/// to delete the case that produced one. `caseCount ≥ corpusFloor` with a per-file breakdown
/// makes that red rather than green — and the per-file half is what stops a corpus being
/// rebalanced towards its easy end.
///
/// **It fails on stale evidence.** R-75's five binding checks exist because a shared staging
/// path plus no cleanup stage is a gate that can be satisfied by a file from a tree that no
/// longer exists.
///
/// **The report is archived, not just asserted.** Two runs of one tree produce two diffable
/// files, which is only true because the report is written by hand with fixed decimal places
/// rather than by an encoder that prints all seventeen digits of a `Double`.
@Suite("Evaluation gate")
struct EvaluationGateTests {
    /// The committed literals R-75.4's three legs all compare against. They live in exactly one
    /// place per lane: `RelevancePolicyTests` and `EngineStampTests` assert them of the test
    /// process, this suite asserts them of the report, and the two self-check stages assert them
    /// of the running application.
    static let committedPolicyDigest = "0xdfff9accb6fd410f"
    static let committedStampPrefix = "s1.p2.l1."

    /// The run, performed **once** for the whole suite. Sixteen assertions over one report is
    /// sixteen readings of one measurement; sixteen runs would be sixteen measurements, and the
    /// latency figures would then differ between the assertion that reads them and the one that
    /// checks they are stable.
    static let measured: Result<EvaluationReport, any Error> = Result {
        let corpus = try CorpusFixtures.loaded()
        return EvaluationHarness(
            corpus: corpus,
            runID: "unit-lane",
            generatedAt: EvaluationHarness.timestamp(Date(timeIntervalSince1970: 0))
        ).run()
    }

    static func report() throws -> EvaluationReport { try measured.get() }

    // MARK: - The corpus is complete before any metric is read

    @Test("the committed corpus is complete")
    func theCorpusIsComplete() throws {
        let corpus = try CorpusFixtures.loaded()
        #expect(throws: Never.self) { try corpus.validateComplete() }
        #expect(corpus.caseCount >= EvaluationPolicy.corpusFloor)
    }

    // MARK: - Every committed threshold

    /// All of them, by name, with the measured value in the failure message. A metric that fails
    /// without saying what it measured is a metric that costs an hour.
    @Test("every committed metric threshold holds")
    func everyThresholdHolds() throws {
        let report = try Self.report()
        let checks = EvaluationGate.checks(for: report)
        #expect(!checks.isEmpty)
        for check in checks {
            #expect(check.passed, "\(check.line)")
        }
        #expect(EvaluationGate.passes(report))
    }

    /// **Zero, not "small".** Called out on its own because it is the one threshold that is not
    /// a budget: every corpus case is one somebody wrote deliberately with an expectation, and a
    /// single false nudge on a case somebody thought about is a product defect.
    @Test("the false-nudge rate is exactly zero")
    func theFalseNudgeRateIsZero() throws {
        let report = try Self.report()
        #expect(report.overall.falseNudgeRate == 0)
        #expect(report.adversarial.falseNudgeRate == 0)
        #expect(report.failures.isEmpty, "\(report.failures.map(\.id))")
    }

    /// R-56.1's route must be **exercised**, not merely present. If this ever falls to zero,
    /// family 11 has stopped testing anything and the corpus no longer stands between the engine
    /// and its worst output.
    @Test("the negative-basis route is exercised")
    func theNegativeBasisRouteIsExercised() throws {
        let report = try Self.report()
        let count = report.byUncertaintyReason
            .first { $0.0 == UncertaintyReason.noNegativeBasis.rawValue }?.1 ?? 0
        #expect(count >= EvaluationPolicy.noNegativeBasisFloor, "noNegativeBasis fired \(count) times")
    }

    /// R-54's three lengths, kept distinguishable in the *evidence* rather than only in the
    /// code: nine declared, eight executable, and a model rung that no classification reaches.
    @Test("the three ladder lengths survive into the report")
    func theLadderLengthsAreReported() throws {
        let report = try Self.report()
        #expect(report.cascade.declaredRungs == EvaluationPolicy.declaredRungCount)
        #expect(report.cascade.executableRungs == EvaluationPolicy.executableRungCeiling)
        #expect(report.cascade.maxDepth <= EvaluationPolicy.executableRungCeiling)
        #expect(report.cascade.maxDepth >= 1)
        let model = report.byStage
            .first { $0.0 == CascadeStage.onDeviceModel.rawValue }?.1
        #expect(model == 0, "a classification reached e06's rung")
    }

    /// Every stage and every reason appears, including the zeroes. A key that vanished when its
    /// count did would turn `byStage.onDeviceModel == 0` from a red gate into a missing one.
    @Test("the distributions are total over their vocabularies")
    func theDistributionsAreTotal() throws {
        let report = try Self.report()
        #expect(report.byStage.map(\.0) == CascadeStage.allCases.map(\.rawValue))
        #expect(
            report.byUncertaintyReason.map(\.0)
                == UncertaintyReason.allCases.map(\.rawValue)
        )
        #expect(report.byBand.map(\.0) == EvidenceBand.allCases.map(\.rawValue))
        #expect(
            report.byStage.reduce(0) { $0 + $1.1 } == report.classificationCount,
            "the per-rung counts do not add up to the classifications performed"
        )
    }

    // MARK: - The per-file budget (R-74.3)

    @Test("every per-file floor is met, separately")
    func everyFileFloorIsMet() throws {
        let report = try Self.report()
        for budget in EvaluationPolicy.budgets {
            let count = report.perFile.first { $0.0 == budget.file }?.1 ?? 0
            #expect(count >= budget.floor, "\(budget.file): \(count) < \(budget.floor)")
        }
        let sequences = report.perFile
            .first { $0.0 == CorpusLoader.sequencesDirectoryName }?.1 ?? 0
        #expect(sequences >= EvaluationPolicy.sequenceFloor)
    }

    // MARK: - R-75's five binding checks

    /// The rule itself, exercised on a report that satisfies it and on four that do not. Stage
    /// 7d applies the same rule to the file it holds; this is what stops the two descriptions of
    /// it drifting apart.
    @Test("a bound report passes all five checks")
    func aBoundReportPasses() throws {
        let evidence = try Self.binding(for: Self.report())
        for result in ReportBinding.evaluate(evidence) {
            #expect(result.passed, "\(result.check): \(result.detail)")
        }
    }

    @Test("a report from another run is refused")
    func aForeignRunIsRefused() throws {
        var evidence = try Self.binding(for: Self.report())
        evidence = Self.replacing(evidence, expectedRunID: "a-different-run")
        let failed = ReportBinding.evaluate(evidence).filter { !$0.passed }.map(\.check)
        #expect(failed == [ReportBinding.Check.runID.rawValue])
    }

    @Test("a report older than the run's marker is refused")
    func aStaleReportIsRefused() throws {
        let evidence = try Self.binding(for: Self.report(), modifiedAt: Date(timeIntervalSince1970: 0))
        let failed = ReportBinding.evaluate(evidence).filter { !$0.passed }.map(\.check)
        #expect(failed == [ReportBinding.Check.freshness.rawValue])
    }

    /// A check that could not be performed has **not** been performed. The absence of a marker
    /// must read as a failure rather than as a pass, because an unperformed check that reads
    /// green is exactly the shape of the hazard R-75 exists to close.
    @Test("a missing marker is a failure, not a pass")
    func aMissingMarkerIsAFailure() throws {
        let evidence = try Self.binding(for: Self.report(), markerAt: nil)
        let failed = ReportBinding.evaluate(evidence).filter { !$0.passed }.map(\.check)
        #expect(failed == [ReportBinding.Check.freshness.rawValue])
    }

    @Test("a report generated against another policy is refused")
    func aForeignEngineIsRefused() throws {
        var evidence = try Self.binding(for: Self.report())
        evidence = Self.replacing(evidence, expectedPolicyDigest: "0x0000000000000000")
        let failed = ReportBinding.evaluate(evidence).filter { !$0.passed }.map(\.check)
        #expect(failed == [ReportBinding.Check.engine.rawValue])
    }

    @Test("a report describing another corpus is refused")
    func aForeignCorpusIsRefused() throws {
        var evidence = try Self.binding(for: Self.report())
        evidence = Self.replacing(evidence, expectedCorpusDigest: "0x0000000000000000")
        let failed = ReportBinding.evaluate(evidence).filter { !$0.passed }.map(\.check)
        #expect(failed == [ReportBinding.Check.corpus.rawValue])
    }

    /// B5. Parsing the shared staging file rather than the run's own copy is refused even when
    /// every other check passes, because what the gate asserts on and what it archives have to
    /// be the same bytes.
    @Test("parsing the shared staging file rather than the run's copy is refused")
    func parsingStagingIsRefused() throws {
        var evidence = try Self.binding(for: Self.report())
        evidence = Self.replacing(evidence, parsedPath: evidence.stagingPath)
        let failed = ReportBinding.evaluate(evidence).filter { !$0.passed }.map(\.check)
        #expect(failed == [ReportBinding.Check.provenance.rawValue])
    }

    // MARK: - R-75.4's third leg, from the report's side

    @Test("the report carries this build's stamp and policy digest")
    func theReportCarriesThisEngine() throws {
        let report = try Self.report()
        #expect(report.policyDigest == Self.committedPolicyDigest)
        #expect(
            report.stamp.hasPrefix(Self.committedStampPrefix),
            "the report's stamp is \(report.stamp)"
        )
        #expect(report.policyDigest == RelevancePolicy.digestHex)
    }

    /// R-75.5, from the test process's side: the digest in the report and the digest recomputed
    /// from the corpus directory must agree. The gate does the same thing against the working
    /// tree, and a `.copy` resource is a byte-for-byte copy of it.
    @Test("the corpus digest recomputes")
    func theCorpusDigestRecomputes() throws {
        let report = try Self.report()
        let recomputed = try CorpusLoader.digest(directory: CorpusFixtures.directory)
        #expect(report.corpusDigest == FNV1a.hex(recomputed))
    }

    // MARK: - Determinism

    /// Two runs of one tree produce the same report, everything that is not a clock reading. The
    /// varying parts are named rather than excluded silently: `generatedAt` is a wall clock,
    /// `latencyMs` and the cache's live figures are measurements of this machine at this moment,
    /// and `runID` is the token the run was given.
    @Test("two runs agree on everything that is not a measurement of the moment")
    func theReportIsDeterministic() throws {
        let corpus = try CorpusFixtures.loaded()
        func run() -> EvaluationReport {
            EvaluationHarness(
                corpus: corpus,
                runID: "unit-lane",
                generatedAt: EvaluationHarness.timestamp(Date(timeIntervalSince1970: 0))
            ).run()
        }
        let first = run()
        let second = run()

        #expect(first.stamp == second.stamp)
        #expect(first.policyDigest == second.policyDigest)
        #expect(first.corpusDigest == second.corpusDigest)
        #expect(first.caseCount == second.caseCount)
        #expect(first.classificationCount == second.classificationCount)
        #expect(first.overall == second.overall)
        #expect(first.adversarial == second.adversarial)
        #expect(first.sequences == second.sequences)
        #expect(first.cascade == second.cascade)
        #expect(first.byStage.map(\.1) == second.byStage.map(\.1))
        #expect(first.byUncertaintyReason.map(\.1) == second.byUncertaintyReason.map(\.1))
        #expect(first.byBand.map(\.1) == second.byBand.map(\.1))
        #expect(first.perFile.map(\.1) == second.perFile.map(\.1))
    }

    /// The report is written by hand for exactly this reason: fixed decimal places and a fixed
    /// key order, so two runs of one tree produce two files a person can diff.
    @Test("the report serialises to fixed decimal places")
    func theReportIsDiffable() throws {
        let report = try Self.report()
        let json = report.json
        #expect(json.hasPrefix("{\n"))
        #expect(json.hasSuffix("}\n"))
        #expect(json.contains("\"falseNudgeRate\": 0.0000"))
        #expect(json.contains("\"policyDigest\": \"\(Self.committedPolicyDigest)\""))
        #expect(json.contains("\"runID\": \"unit-lane\""))
    }

    // MARK: - Helpers

    static func binding(
        for report: EvaluationReport,
        modifiedAt: Date? = Date(timeIntervalSince1970: 2),
        markerAt: Date? = Date(timeIntervalSince1970: 1)
    ) throws -> ReportBinding.Evidence {
        let corpusDigest = FNV1a.hex(try CorpusLoader.digest(directory: CorpusFixtures.directory))
        return ReportBinding.Evidence(
            runID: report.runID,
            expectedRunID: report.runID,
            modifiedAt: modifiedAt,
            markerAt: markerAt,
            stamp: report.stamp,
            expectedStamp: report.stamp,
            policyDigest: report.policyDigest,
            expectedPolicyDigest: Self.committedPolicyDigest,
            corpusDigest: report.corpusDigest,
            expectedCorpusDigest: corpusDigest,
            parsedPath: "/run/evaluation.json",
            stagingPath: "/staging/evaluation.json"
        )
    }

    static func replacing(
        _ evidence: ReportBinding.Evidence,
        expectedRunID: String? = nil,
        expectedPolicyDigest: String? = nil,
        expectedCorpusDigest: String? = nil,
        parsedPath: String? = nil
    ) -> ReportBinding.Evidence {
        ReportBinding.Evidence(
            runID: evidence.runID,
            expectedRunID: expectedRunID ?? evidence.expectedRunID,
            modifiedAt: evidence.modifiedAt,
            markerAt: evidence.markerAt,
            stamp: evidence.stamp,
            expectedStamp: evidence.expectedStamp,
            policyDigest: evidence.policyDigest,
            expectedPolicyDigest: expectedPolicyDigest ?? evidence.expectedPolicyDigest,
            corpusDigest: evidence.corpusDigest,
            expectedCorpusDigest: expectedCorpusDigest ?? evidence.expectedCorpusDigest,
            parsedPath: parsedPath ?? evidence.parsedPath,
            stagingPath: evidence.stagingPath
        )
    }
}
