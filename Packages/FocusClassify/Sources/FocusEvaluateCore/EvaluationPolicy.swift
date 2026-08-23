import Foundation

/// **Every number the evaluation lane commits to, in one file.**
///
/// `RelevancePolicy` is the engine's single numeric file and `check-forbidden.sh`'s R-70f lint
/// searches the whole of `Packages/FocusClassify/Sources` for literals outside it. R-75 then
/// puts the harness *into* that tree — `FocusEvaluateCore` exists precisely so that emission is
/// a product rather than a test side effect — and a percentile rank, a cache-sweep capacity and
/// a corpus floor are all numbers.
///
/// So this file is the harness tree's `RelevancePolicy`: the one place a number may be written
/// down, every one named, doc-commented and traceable to the ruling that fixed it, and the lint
/// excepts exactly this path. The property R-70f actually buys — *a threshold cannot be
/// introduced anywhere a reviewer would not think to look* — is preserved in both trees, and
/// the engine's own exception list is untouched.
///
/// Nothing here is a threshold *about a person*: these are the corpus's committed size, the
/// gate's committed metric thresholds and the benchmark's sweep. A number that changes a
/// verdict lives in `RelevancePolicy` and nowhere else.
public enum EvaluationPolicy {
    // MARK: - Determinism

    /// A fixed wall-clock origin for every fixture-built rule and context item: midnight UTC on
    /// 1 January 2026.
    ///
    /// Rules are sorted by `(authority.rank, subjectKind.rank, createdAt, id)`, which is a total
    /// order only if `createdAt` is one. A `Date()` here would make the sort — and therefore the
    /// snapshot's `Equatable` conformance, and therefore R-69's byte-identical transcript —
    /// depend on the second the suite happened to run in.
    public static let ruleEpochSecondsSince1970: Double = 1_767_225_600

    // MARK: - The corpus budget (R-74.3)

    /// An earlier draft promised "≥ 120 cases" without saying what they were, which is how a
    /// corpus arrives at 118 easy cases and a metric that means nothing. The budget is
    /// committed per file and **each floor is asserted separately**, so the corpus can be
    /// neither shrunk nor rebalanced towards its easy end: thirty extra baseline cases cannot
    /// stand in for the thirty-three adversarial ones.
    public struct CorpusBudget: Sendable, Equatable, Hashable {
        public let file: String
        public let floor: Int
        public let covers: String
    }

    /// F-03's zero-grant path: frontmost identifier plus dwell, with and without a priority,
    /// with and without a context pack, `bundleIdentifier == nil`, and the R-72.3 legacy-row
    /// skip.
    public static let baselineFloor = 20

    /// Every co-firing rung pair in both orders (R-54); the three authorities × three subject
    /// kinds; same-cell conflict; the specificity axis; the four F-130 dispositions.
    public static let rulesFloor = 30

    /// P-124's measured pairs as first-class cases, the overlap/similarity/dwell routes, the
    /// band table row by row, and the single-shot boundary triples of R-74.1.
    public static let heuristicFloor = 34

    /// Eleven families, per-family floors, family 11's required shape (R-68).
    public static let adversarialFloor = 33

    /// D-05's two, the drift transition table cell by cell, the temporal boundary triples,
    /// idle, phase exit, cooldown.
    public static let sequenceFloor = 15

    /// The total, committed at **132** rather than at 120 — a consequence of the per-file
    /// budget rather than a round number chosen first.
    public static let corpusFloor =
        baselineFloor + rulesFloor + heuristicFloor + adversarialFloor + sequenceFloor

    /// The four single-shot corpus files, in load order, each with the floor it owes.
    public static let budgets: [CorpusBudget] = [
        CorpusBudget(
            file: "baseline",
            floor: baselineFloor,
            covers: "F-03's app-only zero-grant path"
        ),
        CorpusBudget(
            file: "rules",
            floor: rulesFloor,
            covers: "precedence: both axes, every co-firing rung pair, conflict"
        ),
        CorpusBudget(
            file: "heuristic",
            floor: heuristicFloor,
            covers: "normalisation, overlap, similarity, dwell, the band table"
        ),
        CorpusBudget(
            file: "adversarial",
            floor: adversarialFloor,
            covers: "the eleven ambiguity families of F-153"
        )
    ]

    // MARK: - The adversarial families (R-68)

    /// Eleven, not ten. The registry and the roadmap name ten; family 11 is added because the
    /// ten shared a blind spot — every one of them puts a *plausible distraction* in front of
    /// the engine and asks it to decline, and none of them puts the person's actual work in
    /// front of it and asks the same. That is the asymmetry R-56.1 exists to close.
    public struct AdversarialFamily: Sendable, Equatable, Hashable {
        public let name: String
        public let floor: Int
        public let mechanism: String
    }

    /// The floor every family owes, so a family cannot be padded by another's cases.
    public static let familyFloor = 2

    /// Family 11's floor: three subjects × three dwell points at minimum.
    public static let productiveToolFamilyFloor = 9

    public static let productiveToolFamily = "productiveLexicallySilent"

    public static let families: [AdversarialFamily] = [
        AdversarialFamily(
            name: "mixedUse",
            floor: familyFloor,
            mechanism: "seedFallback (R-64): nothing about 'a browser' is evidence about this priority"
        ),
        AdversarialFamily(
            name: "misleadingNames",
            floor: familyFloor,
            mechanism: "identifier tokens never reach the similarity function (R-57), so notes never matches notion"
        ),
        AdversarialFamily(
            name: "gamesUsedForWork",
            floor: familyFloor,
            mechanism: "the seed-override guard (R-64): the person's own words outrank a bundled default"
        ),
        AdversarialFamily(
            name: "multilingual",
            floor: familyFloor,
            mechanism: "P-111: NLEmbedding is nil for every non-English language, so there is nothing to consult"
        ),
        AdversarialFamily(
            name: "privateBrowsing",
            floor: familyFloor,
            mechanism: "absence of evidence is uncertain(.noEvidence); R-70i proves no other route was tried"
        ),
        AdversarialFamily(
            name: "sensitiveApplications",
            floor: familyFloor,
            mechanism: "'we did not look' must never become 'you are distracted'"
        ),
        AdversarialFamily(
            name: "unbundledProcesses",
            floor: familyFloor,
            mechanism: "uncertain(.noIdentifiableSubject): there is nothing to write a rule about"
        ),
        AdversarialFamily(
            name: "vaguePriorities",
            floor: familyFloor,
            mechanism: "uncertain(.insufficientPriorityEvidence): R-56.1's first condition fails"
        ),
        AdversarialFamily(
            name: "contradictoryRules",
            floor: familyFloor,
            mechanism: "R-54: same-cell conflict declines to decide, never resolves by recency"
        ),
        AdversarialFamily(
            name: "staleRevisions",
            floor: familyFloor,
            mechanism: "an edited priority invalidates every judgement about the old wording"
        ),
        AdversarialFamily(
            name: productiveToolFamily,
            floor: productiveToolFamilyFloor,
            mechanism: "R-56.1: absence of lexical evidence may never alone produce unrelated"
        )
    ]

    /// R-68's own count, asserted rather than derived from the array's length, so a family
    /// deleted from the array fails rather than quietly lowering the requirement.
    public static let declaredFamilyCount = 11

    // MARK: - The committed metric thresholds (R-67, §4.4)

    /// **Zero, not "small".** Every corpus case is one a person wrote deliberately with an
    /// expectation; a single false nudge on a case somebody thought about is a product defect,
    /// and a non-zero budget is how a defect becomes a habit.
    public static let falseNudgeRateCeiling: Double = 0

    /// Misses are cheap: a miss falls to `uncertain`, which suppresses. P-124 predicts roughly
    /// half of similarity-reachable relevance is missed by design, and that is the side of the
    /// trade this engine deliberately takes.
    public static let missRateCeiling = 0.25

    /// An engine that says "I don't know" to everything is safe and useless. This is the
    /// ceiling that keeps it honest.
    public static let uncertaintyRateCeiling = 0.45

    /// The adversarial suite exists to be declined. Computed over
    /// `caseCount − negativeControlCount`, so a declared control cannot dilute it.
    public static let adversarialUncertaintyFloor = 0.90

    /// P-116: the worst realistic warm path is about ten milliseconds — two language detections,
    /// one evidence vector, one distance and normalisation. Two and a half times that.
    public static let latencyP95CeilingMilliseconds = 25.0

    /// P-116 measured a 59.4 ms cold embedding load; `warmUp()` moves it off the classification
    /// path, and sixty milliseconds is the ceiling that proves it did.
    public static let latencyMaxCeilingMilliseconds = 60.0

    /// The **executable** ladder length (R-54). The declared ladder is nine; `onDeviceModel` is
    /// not in the sequence `RuleCascade` walks, so no classification in this build can consult
    /// it, and `byStage.onDeviceModel` must be zero.
    public static let executableRungCeiling = 8

    /// The declared ladder length, including the rung e06 fills.
    public static let declaredRungCount = 9

    /// R-56.1's route must be **exercised**, not merely present: if this ever falls to zero,
    /// family 11 has stopped testing anything.
    public static let noNegativeBasisFloor = 1

    /// The cache hit rate the committed workload achieves, rounded down with a margin. Measured
    /// at 0.8466 over 205 lookups of 47 distinct sentences; the floor is set below that so a
    /// re-ordered corpus does not redden the gate, and far enough above zero that a real
    /// regression — a corpus rewritten so every case carries a unique priority, or a scorer that
    /// stopped memoising — shows up here rather than being inferred.
    public static let cacheHitRateFloor = 0.70

    // MARK: - How the report is measured and written

    /// The two percentiles §4.4 gates on. Nearest-rank, which is the definition that does not
    /// interpolate between two measurements that were never taken.
    public static let latencyMedianRank = 0.50
    public static let latencyUpperRank = 0.95

    /// R-74.4's sweep. A capacity constant owes a workload benchmark rather than a per-call
    /// figure, and these are the four points the ruling names.
    public static let cacheSweepCapacities = [64, 128, 256, 512]

    /// The committed derivation rule for `similarityCacheCapacity`: the smallest capacity whose
    /// p95 is within ten per cent of the best measured.
    public static let cacheP95Tolerance = 0.10

    /// How many real vector computations the benchmark times before modelling the sweep. Enough
    /// that one scheduling hiccup does not become the reported cost.
    public static let cacheCostSampleCount = 8

    /// Fixed decimal places in the emitted report, so two runs of one tree produce two diffable
    /// files rather than two files that differ in the seventeenth digit of a Double.
    public static let reportDecimalPlaces = 4

    /// Unit conversions, here rather than inline, because R-70f is right that a bare number in
    /// the middle of an expression is a number nobody reviews.
    public static let millisecondsPerSecond = 1_000.0
    public static let attosecondsPerMillisecond = 1_000_000_000_000_000.0
}
