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
        // R-74.4: `similarityCacheCapacity` is class **C** and owes a workload benchmark, and
        // the derivation rule was committed *before* the sweep was run — the smallest capacity
        // whose p95 is within ten per cent of the best measured. A hit rate alone does not
        // enforce that: a capacity nobody derived would pass it every time, which is how 256
        // survived the ruling that was written to replace it. So the shipped constant is
        // compared to the recommendation the sweep produces on this run. When e07 turns window
        // titles on and the evidence-side stream grows past the smallest candidate, the sweep
        // starts discriminating, the recommendation moves, and this goes red until the constant
        // is re-derived — which is R-74.4's own remedy rather than a quiet raise.
        check(
            "cache.capacity",
            "== cache.recommendedCapacity (\(report.cache.recommendedCapacity))",
            "\(report.cache.capacity)",
            report.cache.capacity == report.cache.recommendedCapacity
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
        let dayCount = report.perFile
            .first { $0.0 == CorpusLoader.daysDirectoryName }?.1 ?? 0
        check(
            "perFile.days",
            ">= \(EvaluationPolicy.dayFloor)",
            "\(dayCount)",
            dayCount >= EvaluationPolicy.dayFloor
        )

        checks.append(contentsOf: nudgeChecks(for: report))

        return checks
    }

    /// **The split metric** (R-94, R-94a, §4.4): thirteen gated metrics carrying fourteen bounds.
    ///
    /// The thirteenth bound is `queryAnsweredRelevantShare`'s lower end. It is a **band**, not a
    /// ceiling, and the reason is recorded here because it is the one place somebody would think
    /// to "simplify" it: gating *relevant answers ÷ delivered queries* with a ceiling alone
    /// inverts U-1. A "yes" is the affordance working — one click, a durable rule, a subject the
    /// app never has to ask about again — and a one-sided ceiling on it creates a direct incentive
    /// to ask fewer of the questions U-1 exists to license. Both ends fail, and each end fails for
    /// its own reason.
    ///
    /// Two of the twelve are **fail-closed**: `queryGroundTruthCoverage` must be 1.0 and the day
    /// fixtures must be present, because a gate scoring a metric on absent data is a gate
    /// reporting a pass it did not measure.
    static func nudgeChecks(for report: EvaluationReport) -> [GateCheck] {
        var checks: [GateCheck] = []
        let nudge = report.nudge

        func check(_ name: String, _ requirement: String, _ measured: String, _ passed: Bool) {
            checks.append(
                GateCheck(
                    name: "nudge.\(name)",
                    requirement: requirement,
                    measured: measured,
                    passed: passed
                )
            )
        }
        func number(_ value: Double) -> String { EvaluationReport.number(value) }

        // --- the exact zeroes ---------------------------------------------------------------
        //
        // The split is asserted as an EQUALITY as well as a ceiling: e04's `falseNudgeRate` and
        // e05's `accusationFalsePositiveRate` are two names for one fact, and the day they
        // disagree one of them is lying.
        check(
            "accusationFalsePositiveRate",
            "== \(number(EvaluationPolicy.accusationFalsePositiveCeiling)) and == falseNudgeRate",
            number(nudge.accusationFalsePositiveRate),
            nudge.accusationFalsePositiveRate == EvaluationPolicy.accusationFalsePositiveCeiling
                && nudge.accusationFalsePositiveRate == report.overall.falseNudgeRate
        )
        check("repeatQueryCount", "== 0", "\(nudge.repeatQueryCount)", nudge.repeatQueryCount == 0)
        check(
            "queryOnDecidableCount", "== 0",
            "\(nudge.queryOnDecidableCount)", nudge.queryOnDecidableCount == 0
        )
        check(
            "queryOnUnaskableCount", "== 0",
            "\(nudge.queryOnUnaskableCount)", nudge.queryOnUnaskableCount == 0
        )
        check(
            "accusationsFromQuery", "== 0",
            "\(nudge.accusationsFromQuery)", nudge.accusationsFromQuery == 0
        )
        check(
            "escalationsFromDeferred", "== 0",
            "\(nudge.escalationsFromDeferred)", nudge.escalationsFromDeferred == 0
        )
        check(
            "ladderRungsDeclared", "== \(InterventionPolicy.ladderRungCount)",
            "\(nudge.ladderRungsDeclared)",
            nudge.ladderRungsDeclared == InterventionPolicy.ladderRungCount
        )

        // --- the floor on the app opening its mouth at all (focus-237) ------------------------
        //
        // Every check above this line is satisfied by an application that never accuses anybody.
        // This is the one that is not. It reads the panel rung's own count out of `byRung`, which
        // the report has always published and the gate has never named.
        let accusationsDelivered = nudge.byRung
            .first { $0.0 == LadderRung.Kind.panel.rawValue }?.1 ?? 0
        check(
            "byRung.panel",
            ">= \(EvaluationPolicy.accusationsDeliveredFloor) (a FLOOR — every other nudge metric passes for a silent app)",
            "\(accusationsDelivered)",
            accusationsDelivered >= EvaluationPolicy.accusationsDeliveredFloor
        )

        // --- the volume ceilings ------------------------------------------------------------
        check(
            "queryVolumeRate",
            "<= \(number(EvaluationPolicy.queryVolumeRateCeiling)) (VOLUME, not a false-positive rate)",
            number(nudge.queryVolumeRate),
            nudge.queryVolumeRate <= EvaluationPolicy.queryVolumeRateCeiling
        )
        check(
            "queriesPerFocusDay",
            "<= \(InterventionPolicy.dailyQueryCapAllPriorities) (max across day fixtures)",
            "\(nudge.queriesPerFocusDay)",
            nudge.queriesPerFocusDay <= InterventionPolicy.dailyQueryCapAllPriorities
        )
        check(
            "interruptionsPerFocusDayMax",
            "<= \(InterventionPolicy.dailyInterruptionCap)",
            "\(nudge.interruptionsPerFocusDayMax)",
            nudge.interruptionsPerFocusDayMax <= InterventionPolicy.dailyInterruptionCap
        )
        check(
            "queriesPerPriorityMax",
            "<= \(InterventionPolicy.dailyQueryCap)",
            "\(nudge.queriesPerPriorityMax)",
            nudge.queriesPerPriorityMax <= InterventionPolicy.dailyQueryCap
        )

        // --- the honesty band, and the data it needs ------------------------------------------
        check(
            "queryGroundTruthCoverage",
            ">= \(number(EvaluationPolicy.queryGroundTruthCoverageFloor)) (fails closed)",
            number(nudge.queryGroundTruthCoverage),
            nudge.queryGroundTruthCoverage >= EvaluationPolicy.queryGroundTruthCoverageFloor
        )
        check(
            "queryAnsweredRelevantShare",
            "in [\(number(EvaluationPolicy.queryAnsweredRelevantFloor)), "
                + "\(number(EvaluationPolicy.queryAnsweredRelevantCeiling))] — BOTH ends fail",
            number(nudge.queryAnsweredRelevantShare),
            nudge.queryAnsweredRelevantShare >= EvaluationPolicy.queryAnsweredRelevantFloor
                && nudge.queryAnsweredRelevantShare <= EvaluationPolicy.queryAnsweredRelevantCeiling
        )
        check(
            "unaskableUncertaintyShare",
            ">= \(number(EvaluationPolicy.unaskableUncertaintyFloor)) (a FLOOR)",
            number(nudge.unaskableUncertaintyShare),
            nudge.unaskableUncertaintyShare >= EvaluationPolicy.unaskableUncertaintyFloor
        )

        return checks
    }

    public static func passes(_ report: EvaluationReport) -> Bool {
        checks(for: report).allSatisfy(\.passed)
    }
}
