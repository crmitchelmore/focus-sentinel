import FocusCore
import Foundation

/// One threshold, and whether the run met it.
public struct GateCheck: Sendable, Equatable {
    public let name: String
    public let requirement: String
    public let measured: String
    public let passed: Bool

    public var line: String {
        "\(passed ? "ok  " : "FAIL") \(name): \(measured) (requires \(requirement))"
    }
}

/// **The committed metric thresholds of §4.4, in one place.**
///
/// One place, deliberately: the `FocusEvaluate` product decides its exit status from these and
/// `EvaluationGateTests` asserts the same list, so `swift test` alone still catches a metric
/// regression and the two can never disagree about what the gate is. R-75 keeps *emission* in
/// the product and *assertion* in the suite; this is the shared statement of what is being
/// asserted, which is a third thing and belongs to neither.
///
/// R-75's five binding checks are **not** here. They are about the report's provenance — the run
/// token, the mtime, the stamp, the corpus digest and which copy of the file was parsed — and
/// three of the five can only be answered by whoever holds the file. Stage 7d owns them, and it
/// evaluates them *first*: a stale or foreign report is not a failing number, it is no evidence
/// at all, and reporting it as a metric failure would send a reader looking in the wrong place.
public enum EvaluationGate {
    public static func checks(for report: EvaluationReport) -> [GateCheck] {
        var checks: [GateCheck] = []

        func check(_ name: String, _ requirement: String, _ measured: String, _ passed: Bool) {
            checks.append(
                GateCheck(name: name, requirement: requirement, measured: measured, passed: passed)
            )
        }

        func number(_ value: Double) -> String { EvaluationReport.number(value) }

        check(
            "overall.falseNudgeRate",
            "== \(number(EvaluationPolicy.falseNudgeRateCeiling))",
            number(report.overall.falseNudgeRate),
            report.overall.falseNudgeRate == EvaluationPolicy.falseNudgeRateCeiling
        )
        check(
            "overall.missRate",
            "<= \(number(EvaluationPolicy.missRateCeiling))",
            number(report.overall.missRate),
            report.overall.missRate <= EvaluationPolicy.missRateCeiling
        )
        check(
            "overall.uncertaintyRate",
            "<= \(number(EvaluationPolicy.uncertaintyRateCeiling))",
            number(report.overall.uncertaintyRate),
            report.overall.uncertaintyRate <= EvaluationPolicy.uncertaintyRateCeiling
        )
        check(
            "adversarial.uncertaintyRate",
            ">= \(number(EvaluationPolicy.adversarialUncertaintyFloor))",
            number(report.adversarial.uncertaintyRate),
            report.adversarial.uncertaintyRate >= EvaluationPolicy.adversarialUncertaintyFloor
        )
        check(
            "adversarial.familyCount",
            "== \(EvaluationPolicy.declaredFamilyCount)",
            "\(report.adversarial.familyCount)",
            report.adversarial.familyCount == EvaluationPolicy.declaredFamilyCount
        )
        check(
            "latencyMs.p95",
            "<= \(number(EvaluationPolicy.latencyP95CeilingMilliseconds))",
            number(report.latencyMs.p95),
            report.latencyMs.p95 <= EvaluationPolicy.latencyP95CeilingMilliseconds
        )
        check(
            "latencyMs.max",
            "<= \(number(EvaluationPolicy.latencyMaxCeilingMilliseconds))",
            number(report.latencyMs.max),
            report.latencyMs.max <= EvaluationPolicy.latencyMaxCeilingMilliseconds
        )
        check(
            "cascade.maxDepth",
            "<= \(EvaluationPolicy.executableRungCeiling)",
            "\(report.cascade.maxDepth)",
            report.cascade.maxDepth <= EvaluationPolicy.executableRungCeiling
        )
        check(
            "cascade.declaredRungs",
            "== \(EvaluationPolicy.declaredRungCount)",
            "\(report.cascade.declaredRungs)",
            report.cascade.declaredRungs == EvaluationPolicy.declaredRungCount
        )
        check(
            "cascade.executableRungs",
            "== \(EvaluationPolicy.executableRungCeiling)",
            "\(report.cascade.executableRungs)",
            report.cascade.executableRungs == EvaluationPolicy.executableRungCeiling
        )

        let modelRung = report.byStage
            .first { $0.0 == CascadeStage.onDeviceModel.rawValue }?.1 ?? -1
        check(
            "byStage.onDeviceModel",
            "== 0",
            "\(modelRung)",
            modelRung == 0
        )
        check(
            "caseCount",
            ">= \(report.corpusFloor)",
            "\(report.caseCount)",
            report.caseCount >= report.corpusFloor
        )

        let noNegativeBasis = report.byUncertaintyReason
            .first { $0.0 == UncertaintyReason.noNegativeBasis.rawValue }?.1 ?? 0
        check(
            "byUncertaintyReason.noNegativeBasis",
            ">= \(EvaluationPolicy.noNegativeBasisFloor)",
            "\(noNegativeBasis)",
            noNegativeBasis >= EvaluationPolicy.noNegativeBasisFloor
        )
        check(
            "cache.hitRate",
            ">= \(number(EvaluationPolicy.cacheHitRateFloor))",
            number(report.cache.hitRate),
            report.cache.hitRate >= EvaluationPolicy.cacheHitRateFloor
        )
        check(
            "failures",
            "empty",
            "\(report.failures.count)",
            report.failures.isEmpty
        )

        for budget in EvaluationPolicy.budgets {
            let count = report.perFile.first { $0.0 == budget.file }?.1 ?? 0
            check(
                "perFile.\(budget.file)",
                ">= \(budget.floor)",
                "\(count)",
                count >= budget.floor
            )
        }
        let sequenceCount = report.perFile
            .first { $0.0 == CorpusLoader.sequencesDirectoryName }?.1 ?? 0
        check(
            "perFile.sequences",
            ">= \(EvaluationPolicy.sequenceFloor)",
            "\(sequenceCount)",
            sequenceCount >= EvaluationPolicy.sequenceFloor
        )

        return checks
    }

    public static func passes(_ report: EvaluationReport) -> Bool {
        checks(for: report).allSatisfy(\.passed)
    }
}
