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

/// `evaluation.json`, as a value (Appendix A.4, extended by R-67 and R-75).
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
    public let failures: [EvaluationFailure]

    public static func == (lhs: EvaluationReport, rhs: EvaluationReport) -> Bool {
        lhs.json == rhs.json
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
