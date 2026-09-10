import FocusCore
import Foundation

/// One case that did not do what it promised. Empty on a green run.
///
/// The first thing a reviewer reads on a red one: a metric that fails without naming the case
/// that failed it is a metric that costs an hour.
public struct EvaluationFailure: Sendable, Equatable {
    public let id: String
    public let expected: String
    public let actual: String
    public let note: String
}

/// The three rates R-67 defines, computed over a stated denominator.
public struct EvaluationRates: Sendable, Equatable {
    /// Cases producing `.mandated` whose expectation was **not** `.mandated`, over all cases
    /// whose expectation was not `.mandated`.
    public let falseNudgeRate: Double
    /// Cases **not** producing `.mandated` whose expectation was `.mandated`, over all cases
    /// whose expectation was `.mandated`.
    public let missRate: Double
    /// Cases whose verdict is `uncertain`, over the denominator this block names.
    public let uncertaintyRate: Double
    public let denominator: Int
}

public struct AdversarialSummary: Sendable, Equatable {
    public let caseCount: Int
    public let familyCount: Int
    /// Declared controls, counted separately so the rate the gate reads is computed over
    /// `caseCount − negativeControlCount` and a control cannot dilute it (R-68).
    public let negativeControlCount: Int
    public let uncertaintyRate: Double
    public let falseNudgeRate: Double
}

public struct SequenceSummary: Sendable, Equatable {
    public let count: Int
    public let mandateCount: Int
    /// FNV-1a over every fixture's transcript, concatenated in id order.
    ///
    /// This is the **cross-process** half of R-69's byte-identity assertion: the executable
    /// writes it, the test process recomputes it from the same fixtures, and the two must agree.
    /// A digest that used `Hasher` could not do that — P-118 measured it returning a different
    /// value in every process, which is why every digest in this epic is FNV-1a.
    public let transcriptDigest: UInt64
}

public struct LatencySummary: Sendable, Equatable {
    public let p50: Double
    public let p95: Double
    public let max: Double
    /// The very first classification a process ever performs, before anything is warmed.
    /// Reported but **not** gated: P-116 measured the embedding's cold load at 59.4 ms and the
    /// whole point of `warmUp()` is that a person never pays it inside a nudge decision.
    public let coldFirstCall: Double
    /// The worst classification in the cold pass. Also reported and not gated, and it is the
    /// figure to read when `coldFirstCall` looks fine and something still stutters: every
    /// remaining one-time framework load lands here rather than hiding inside a percentile.
    public let coldMax: Double
}

public struct CascadeSummary: Sendable, Equatable {
    /// Nine. Every rung the vocabulary knows, including the one e06 fills.
    public let declaredRungs: Int
    /// Eight. The rungs this build can actually consult.
    public let executableRungs: Int
    public let meanDepth: Double
    public let maxDepth: Int
}

/// **The `nudge` object of `evaluation.json`** (R-94, R-94a, Appendix A.3).
///
/// e04's `falseNudgeRate` stays a top-level key, so every committed digest and all five of R-75's
/// binding checks remain valid; this sits beside it and `accusationFalsePositiveRate` is asserted
/// **equal** to it, which is what makes the split explicit rather than a second opinion.
///
/// Read the names carefully, because the renaming is the point of finding 2. Three numbers bound
/// how often the app speaks — per judgement, per day, per priority — and **none of them is a
/// false-positive rate**. Two numbers are exact-zero gates on the query failures that are
/// unambiguously defects. One is a two-sided honesty band. The rest are reported and ungated,
/// because a number nobody gates is still a number somebody reads.
/// `Sendable` and deliberately **not** `Equatable`: the distributions are `[(String, Int)]`, in
/// the same key-ordered shape every other block in this report uses, and two reports are compared
/// through `EvaluationReport.==` — which compares the emitted JSON, because the artefact is the
/// thing two runs have to agree on.
public struct NudgeSummary: Sendable {
    // --- the exact zeroes ------------------------------------------------------------------
    /// An `InterventionMandate` on any corpus case not labelled `unrelated`. **== `falseNudgeRate`.**
    public let accusationFalsePositiveRate: Double
    /// A second question about the same `(priorityID, subjectKind, subject)`. U-1 calls
    /// repeat-asking a defect, and a defect's gate is zero.
    public let repeatQueryCount: Int
    /// A question about a subject the context pack, a decisive rule or a decisive seed had
    /// already answered — the app failing to read its own notes.
    public let queryOnDecidableCount: Int
    /// A question produced from an uncertainty R-77 marks unaskable — the guard on `noEvidence`
    /// above all, where a question would announce that we noticed a password manager.
    public let queryOnUnaskableCount: Int
    /// An accusation produced from an `uncertain` verdict. Structurally impossible; counted
    /// anyway, because an invariant nobody counts is an invariant nobody notices losing.
    public let accusationsFromQuery: Int
    /// A rung delivered above the ambient one whose predecessor was not a delivered rung one rank
    /// below. R-81, as arithmetic.
    public let escalationsFromDeferred: Int
    /// D-06's three, asserted as a number as well as a type.
    public let ladderRungsDeclared: Int

    // --- the volume ceilings ---------------------------------------------------------------
    /// Delivered questions ÷ classifications. **A volume ceiling, not a false-positive rate.**
    public let queryVolumeRate: Double
    /// The **maximum** across the realistic-day fixtures, never the mean: a metric that averages
    /// a bad day away is a metric that ships a bad day.
    public let queriesPerFocusDay: Int
    public let interruptionsPerFocusDayMax: Int
    /// Reported, ungated — the middle of the distribution, so a reader can see whether the
    /// maximum is a spike or the shape.
    public let interruptionsPerFocusDayP50: Int
    public let queriesPerPriorityMax: Int

    // --- the honesty band ------------------------------------------------------------------
    /// The share of delivered questions whose committed `queryGroundTruth` is `relevant`, over
    /// the cases where the ground truth is not `eitherIsReasonable`. **Both ends fail.**
    public let queryAnsweredRelevantShare: Double
    /// Askable subject-bearing cases carrying a label ÷ askable subject-bearing cases. The gate
    /// fails below 1.0 rather than scoring the band on absent data.
    public let queryGroundTruthCoverage: Double
    /// Reported; excluded from the band's denominator, because for these cases no answer is wrong.
    public let queryEitherIsReasonableShare: Double
    /// A **floor**: the share of uncertain verdicts whose reason has no answerable question in it.
    public let unaskableUncertaintyShare: Double
    /// Reported, ungated. A rising number means the presentation gate is over-firing, which is a
    /// signal for e08 rather than a silent loss.
    public let deferredRungShare: Double

    // --- the distributions -----------------------------------------------------------------
    public let byKind: [(String, Int)]
    public let byRung: [(String, Int)]
    public let bySurface: [(String, Int)]
    public let byDisposition: [(String, Int)]
    public let byQueryReason: [(String, Int)]
    public let bySuppressionReason: [(String, Int)]
    public let byDeferralReason: [(String, Int)]
    /// e05's own manifest digest. **Not** `policyDigest`: two policies, two digests, so that
    /// tuning a cooldown never invalidates e06's verdict cache (R-95).
    public let interventionDigest: String

    /// Public so a suite can build a **deliberately regressed** block and require the gate to go
    /// red by name. A gate nobody has watched fail is a gate nobody knows works, and the only way
    /// to watch this one fail is to hand it a report with one number moved.
    public init(
        accusationFalsePositiveRate: Double,
        repeatQueryCount: Int,
        queryOnDecidableCount: Int,
        queryOnUnaskableCount: Int,
        accusationsFromQuery: Int,
        escalationsFromDeferred: Int,
        ladderRungsDeclared: Int,
        queryVolumeRate: Double,
        queriesPerFocusDay: Int,
        interruptionsPerFocusDayMax: Int,
        interruptionsPerFocusDayP50: Int,
        queriesPerPriorityMax: Int,
        queryAnsweredRelevantShare: Double,
        queryGroundTruthCoverage: Double,
        queryEitherIsReasonableShare: Double,
        unaskableUncertaintyShare: Double,
        deferredRungShare: Double,
        byKind: [(String, Int)],
        byRung: [(String, Int)],
        bySurface: [(String, Int)],
        byDisposition: [(String, Int)],
        byQueryReason: [(String, Int)],
        bySuppressionReason: [(String, Int)],
        byDeferralReason: [(String, Int)],
        interventionDigest: String
    ) {
        self.accusationFalsePositiveRate = accusationFalsePositiveRate
        self.repeatQueryCount = repeatQueryCount
        self.queryOnDecidableCount = queryOnDecidableCount
        self.queryOnUnaskableCount = queryOnUnaskableCount
        self.accusationsFromQuery = accusationsFromQuery
        self.escalationsFromDeferred = escalationsFromDeferred
        self.ladderRungsDeclared = ladderRungsDeclared
        self.queryVolumeRate = queryVolumeRate
        self.queriesPerFocusDay = queriesPerFocusDay
        self.interruptionsPerFocusDayMax = interruptionsPerFocusDayMax
        self.interruptionsPerFocusDayP50 = interruptionsPerFocusDayP50
        self.queriesPerPriorityMax = queriesPerPriorityMax
        self.queryAnsweredRelevantShare = queryAnsweredRelevantShare
        self.queryGroundTruthCoverage = queryGroundTruthCoverage
        self.queryEitherIsReasonableShare = queryEitherIsReasonableShare
        self.unaskableUncertaintyShare = unaskableUncertaintyShare
        self.deferredRungShare = deferredRungShare
        self.byKind = byKind
        self.byRung = byRung
        self.bySurface = bySurface
        self.byDisposition = byDisposition
        self.byQueryReason = byQueryReason
        self.bySuppressionReason = bySuppressionReason
        self.byDeferralReason = byDeferralReason
        self.interventionDigest = interventionDigest
    }
}

/// `evaluation.json`, as a value (Appendix A.4, extended by R-67, R-75 and R-94).
///
/// Serialised **by hand** rather than through `JSONEncoder`, for one reason that matters: two
/// runs of one tree must produce two byte-identical files, and a `Double` encoded by
/// `JSONEncoder` prints all seventeen digits it happens to hold. Fixed decimal places and a
/// fixed key order make the report diffable, which is the whole reason it is an artefact rather
/// than an assertion.
public struct EvaluationReport: Sendable, Equatable {
    public let stamp: String
    public let policyDigest: String
    /// Single-shot cases **plus** sequence fixtures, compared against `corpusFloor`.
    public let caseCount: Int
    public let corpusFloor: Int
    /// How many classifications the run actually performed. `byStage`, `byBand`,
    /// `byUncertaintyReason`, `cascade` and `latencyMs` are all over this, and it is reported so
    /// their sums are checkable rather than assumed.
    public let classificationCount: Int
    public let generatedAt: String
    /// R-75.2's run token. Stage 7d fails unless it equals the current run's, which is the
    /// assertion that survives even if the pre-`unit` deletion silently no-ops.
    public let runID: String
    /// R-75.5. FNV-1a over the concatenated corpus bytes; the gate recomputes it from the
    /// working tree and refuses a report that describes a different corpus.
    public let corpusDigest: String
    public let perFile: [(String, Int)]
    public let overall: EvaluationRates
    public let adversarial: AdversarialSummary
    public let sequences: SequenceSummary
    public let cache: CacheBenchmarkResult
    public let latencyMs: LatencySummary
    public let cascade: CascadeSummary
    public let byStage: [(String, Int)]
    public let byUncertaintyReason: [(String, Int)]
    public let byBand: [(String, Int)]
    public let nudge: NudgeSummary
    public let failures: [EvaluationFailure]

    public static func == (lhs: EvaluationReport, rhs: EvaluationReport) -> Bool {
        lhs.json == rhs.json
    }

    /// The same report with a different `nudge` block.
    ///
    /// The report's own initialiser stays internal — it is the harness's to build, and a report
    /// somebody assembled by hand is not a measurement. This one seam is public because the gate
    /// has to be watched failing: `EvaluationGateTests` moves one nudge number across its bound
    /// and requires the check of that name to go red.
    public func replacingNudge(_ nudge: NudgeSummary) -> EvaluationReport {
        EvaluationReport(
            stamp: stamp,
            policyDigest: policyDigest,
            caseCount: caseCount,
            corpusFloor: corpusFloor,
            classificationCount: classificationCount,
            generatedAt: generatedAt,
            runID: runID,
            corpusDigest: corpusDigest,
            perFile: perFile,
            overall: overall,
            adversarial: adversarial,
            sequences: sequences,
            cache: cache,
            latencyMs: latencyMs,
            cascade: cascade,
            byStage: byStage,
            byUncertaintyReason: byUncertaintyReason,
            byBand: byBand,
            nudge: nudge,
            failures: failures
        )
    }

    // MARK: - Serialisation

    static func number(_ value: Double) -> String {
        String(format: "%.\(EvaluationPolicy.reportDecimalPlaces)f", value)
    }

    static func quoted(_ value: String) -> String {
        // The report carries no free text a person typed: every string in it is an enumeration
        // raw value, a hex digest, an ISO-8601 instant or a corpus id. Escaping the two
        // characters JSON forbids is therefore total rather than optimistic.
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func object(_ entries: [(String, Int)]) -> String {
        entries.map { "\(quoted($0.0)): \($0.1)" }.joined(separator: ", ")
    }

    /// The whole report, deterministic and diffable.
    public var json: String {
        var lines: [String] = []
        lines.append("{")
        lines.append("  \"stamp\": \(Self.quoted(stamp)),")
        lines.append("  \"policyDigest\": \(Self.quoted(policyDigest)),")
        lines.append("  \"runID\": \(Self.quoted(runID)),")
        lines.append("  \"corpusDigest\": \(Self.quoted(corpusDigest)),")
        lines.append("  \"generatedAt\": \(Self.quoted(generatedAt)),")
        lines.append("  \"caseCount\": \(caseCount),")
        lines.append("  \"corpusFloor\": \(corpusFloor),")
        lines.append("  \"classificationCount\": \(classificationCount),")
        lines.append("  \"perFile\": { \(Self.object(perFile)) },")
        lines.append(
            "  \"overall\": { \"falseNudgeRate\": \(Self.number(overall.falseNudgeRate)), "
                + "\"missRate\": \(Self.number(overall.missRate)), "
                + "\"uncertaintyRate\": \(Self.number(overall.uncertaintyRate)), "
                + "\"denominator\": \(overall.denominator) },"
        )
        lines.append(
            "  \"adversarial\": { \"caseCount\": \(adversarial.caseCount), "
                + "\"familyCount\": \(adversarial.familyCount), "
                + "\"negativeControlCount\": \(adversarial.negativeControlCount), "
                + "\"uncertaintyRate\": \(Self.number(adversarial.uncertaintyRate)), "
                + "\"falseNudgeRate\": \(Self.number(adversarial.falseNudgeRate)) },"
        )
        lines.append(
            "  \"sequences\": { \"count\": \(sequences.count), "
                + "\"mandateCount\": \(sequences.mandateCount), "
                + "\"transcriptDigest\": \(Self.quoted(FNV1a.hex(sequences.transcriptDigest))) },"
        )
        lines.append(
            "  \"cache\": { \"capacity\": \(cache.capacity), "
                + "\"hitRate\": \(Self.number(cache.hitRate)), "
                + "\"evictions\": \(cache.evictions), "
                + "\"workloadSize\": \(cache.workloadSize), "
                + "\"distinctKeys\": \(cache.distinctKeys), "
                + "\"recommendedCapacity\": \(cache.recommendedCapacity), "
                + "\"isDiscriminating\": \(cache.isDiscriminating), "
                + "\"sweep\": [ "
                + cache.sweep.map {
                    "{ \"capacity\": \($0.capacity), \"hitRate\": \(Self.number($0.hitRate)), "
                        + "\"evictions\": \($0.evictions), \"p95\": \(Self.number($0.p95)) }"
                }.joined(separator: ", ")
                + " ] },"
        )
        lines.append(
            "  \"latencyMs\": { \"p50\": \(Self.number(latencyMs.p50)), "
                + "\"p95\": \(Self.number(latencyMs.p95)), "
                + "\"max\": \(Self.number(latencyMs.max)), "
                + "\"coldFirstCall\": \(Self.number(latencyMs.coldFirstCall)), "
                + "\"coldMax\": \(Self.number(latencyMs.coldMax)) },"
        )
        lines.append(
            "  \"cascade\": { \"declaredRungs\": \(cascade.declaredRungs), "
                + "\"executableRungs\": \(cascade.executableRungs), "
                + "\"meanDepth\": \(Self.number(cascade.meanDepth)), "
                + "\"maxDepth\": \(cascade.maxDepth) },"
        )
        lines.append("  \"byStage\": { \(Self.object(byStage)) },")
        lines.append("  \"byUncertaintyReason\": { \(Self.object(byUncertaintyReason)) },")
        lines.append("  \"byBand\": { \(Self.object(byBand)) },")
        lines.append("  \"nudge\": {")
        lines.append(
            "    \"accusationFalsePositiveRate\": \(Self.number(nudge.accusationFalsePositiveRate)), "
                + "\"repeatQueryCount\": \(nudge.repeatQueryCount), "
                + "\"queryOnDecidableCount\": \(nudge.queryOnDecidableCount), "
                + "\"queryOnUnaskableCount\": \(nudge.queryOnUnaskableCount),"
        )
        lines.append(
            "    \"queryVolumeRate\": \(Self.number(nudge.queryVolumeRate)), "
                + "\"queriesPerFocusDay\": \(nudge.queriesPerFocusDay), "
                + "\"interruptionsPerFocusDayMax\": \(nudge.interruptionsPerFocusDayMax), "
                + "\"interruptionsPerFocusDayP50\": \(nudge.interruptionsPerFocusDayP50), "
                + "\"queriesPerPriorityMax\": \(nudge.queriesPerPriorityMax),"
        )
        lines.append(
            "    \"queryAnsweredRelevantShare\": \(Self.number(nudge.queryAnsweredRelevantShare)), "
                + "\"queryGroundTruthCoverage\": \(Self.number(nudge.queryGroundTruthCoverage)), "
                + "\"queryEitherIsReasonableShare\": "
                + "\(Self.number(nudge.queryEitherIsReasonableShare)), "
                + "\"unaskableUncertaintyShare\": \(Self.number(nudge.unaskableUncertaintyShare)),"
        )
        lines.append(
            "    \"ladderRungsDeclared\": \(nudge.ladderRungsDeclared), "
                + "\"escalationsFromDeferred\": \(nudge.escalationsFromDeferred), "
                + "\"accusationsFromQuery\": \(nudge.accusationsFromQuery), "
                + "\"deferredRungShare\": \(Self.number(nudge.deferredRungShare)),"
        )
        lines.append("    \"byKind\": { \(Self.object(nudge.byKind)) },")
        lines.append("    \"byRung\": { \(Self.object(nudge.byRung)) },")
        lines.append("    \"bySurface\": { \(Self.object(nudge.bySurface)) },")
        lines.append("    \"byDisposition\": { \(Self.object(nudge.byDisposition)) },")
        lines.append("    \"byQueryReason\": { \(Self.object(nudge.byQueryReason)) },")
        lines.append("    \"bySuppressionReason\": { \(Self.object(nudge.bySuppressionReason)) },")
        lines.append("    \"byDeferralReason\": { \(Self.object(nudge.byDeferralReason)) },")
        lines.append("    \"interventionDigest\": \(Self.quoted(nudge.interventionDigest))")
        lines.append("  },")
        lines.append("  \"failures\": [")
        lines.append(
            failures.map {
                "    { \"id\": \(Self.quoted($0.id)), \"expected\": \(Self.quoted($0.expected)), "
                    + "\"actual\": \(Self.quoted($0.actual)), \"note\": \(Self.quoted($0.note)) }"
            }.joined(separator: ",\n")
        )
        lines.append("  ]")
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    public var data: Data { Data(json.utf8) }
}
