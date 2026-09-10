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

    // MARK: - The nudge lane's fixed surroundings (T143, R-96j's doctrine in the harness tree)

    /// The idle threshold every replayed lane uses — e03's own default, restated as a lane
    /// constant because the harness has no settings store to read one from.
    public static let nudgeIdleThresholdSeconds: Double = 120

    /// How idle a step that declares `isUserIdle` is. Far enough above the threshold that a
    /// reader is in no doubt the fixture meant it.
    public static let nudgeIdleSeconds: Double = 900

    /// A process identifier for the synthetic activation the lane hands `SensitivityGate`.
    ///
    /// It is never read by anything — the gate answers on the bundle identifier alone — but
    /// `FrontmostActivation` requires one, and R-70f is right that a bare number in the middle of
    /// an expression is a number nobody reviews.
    public static let nudgeLanePID: Int32 = 4_242

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
    /// band table row by row, and the single-shot boundary triples of R-74.1 — plus **one** e05
    /// case, `queryDwellThreshold`'s committed witness at forty-four seconds.
    ///
    /// One and not three, and the reason is a measurement rather than a preference. The
    /// *at* and *above* points of that boundary are walked a second at a time in a sequence
    /// fixture, exactly as `sustainedDriftThreshold`'s 89/90/91 are in seq-0003, because every
    /// single-shot case added here is an `uncertain` verdict in `unaskableUncertaintyShare`'s
    /// denominator: three askable cases move that share from 0.3472 to 0.3333 and take it below
    /// its committed floor of 0.34. Lowering the floor to fit the corpus would be precisely the
    /// move R-75 exists to catch, so the corpus was written to fit the floor instead.
    public static let heuristicFloor = 35

    /// Eleven families, per-family floors, family 11's required shape (R-68).
    public static let adversarialFloor = 33

    /// D-05's two, the drift transition table cell by cell, the temporal boundary triples,
    /// idle, phase exit, cooldown — **and e05's fourteen**: the tab-hop that witnesses
    /// `queryCooldown`, the nine-subject priority that witnesses `dailyQueryCap` across two days,
    /// the shared-budget contention, the deferred rung over a full-screen span, both backoffs,
    /// never-ask-twice across a relaunch, and the rule-deletion sequence finding 3 added.
    public static let sequenceFloor = 29

    /// **Three realistic days** (R-94a): one carrying three priorities, one a single long
    /// priority with many askable subjects, one a quiet day that must produce **zero**
    /// interruptions. `queriesPerFocusDay` and `interruptionsPerFocusDayMax` are measured on
    /// these, and the gate fails closed if they are absent rather than scoring a metric as
    /// passing on no data.
    public static let dayFloor = 3

    /// The total, committed as the sum of the per-file budget rather than as a round number
    /// chosen first.
    public static let corpusFloor =
        baselineFloor + rulesFloor + heuristicFloor + adversarialFloor + sequenceFloor + dayFloor

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

    // MARK: - Lane 2 · the model corpus and its budgets (e06)
    //
    // Every constant here sizes the *evidence*, not the judgement, which is why they live in
    // this file and not in `RelevancePolicy` — the same argument R-70f's second exception
    // already made for the rest of this type.

    /// R-113's grid: six priorities against six subjects, complete and fail-closed.
    public static let modelGridPriorities = 6
    public static let modelGridSubjects = 6
    /// The second competence: three non-English priorities against three subjects.
    public static let modelLanguageCount = 3
    public static let modelLanguageSubjects = 3

    /// **The sum of the two grids, not a round number chosen first** — the same discipline
    /// `corpusFloor` already uses. `GridCompletenessTests` asserts the arithmetic rather than
    /// the literal, so a grid that shrank could not be accommodated by editing this line.
    public static let modelCorpusFloor =
        modelGridPriorities * modelGridSubjects + modelLanguageCount * modelLanguageSubjects

    /// How many of those cells a human committed as `rescue`, counted from the files rather than
    /// chosen: 12 of the 36 in the 6×6 and 3 of the 9 multilingual cells.
    ///
    /// The remaining 30 are holds, and **the holds are the mutation witness**. A yes-to-everything
    /// model scores 100 % recall and fails on every one of them; `GridCompletenessTests` asserts
    /// the holds outnumber the rescues so that witness can never become a rump.
    public static let modelRescuableCells = 15

    /// **The recall floor, and the asymmetry that sets it** (R-111).
    ///
    /// A missed rescue costs a question the app would have asked anyway — today's behaviour, a
    /// known-safe posture — so the floor tolerates an imperfect model. A seduction costs the app
    /// going quiet about something it was told to hold, and its budget is zero with no floor to
    /// argue about. Set at three quarters: a tier that cannot rescue three cases in four is not
    /// worth the weight of a package.
    public static let modelRescueRecallFloor = 0.75

    /// Runs of the whole model lane, whose per-case bucket assignment must be identical across
    /// all of them (R-112). A language model is not a pure function and this does not pretend it
    /// is; `.greedy` sampling is the strongest reproducibility the tier offers and this is what
    /// checks the claim rather than assuming it.
    public static let modelLaneRepeatCount = 3

    /// Complete, and nothing less. A missing cell is not scored as passing; it fails.
    public static let modelGridCompleteness = 1.0

    /// The 8-4-4-4-12 hex grouping of a UUID string.
    ///
    /// It lives here rather than beside the code that uses it because R-70f permits a numeric
    /// literal in exactly one file per tree, and a canonical UUID layout is a number about a
    /// format rather than about a person — the same reason a percentile rank and a cache-sweep
    /// capacity are allowed to sit in this file. `ModelCorpusRunner` derives one stable priority
    /// identifier per cell from the cell's own id, so two runs of lane 2 key the same cache
    /// entries and R-112's repeat comparison compares like with like.
    public static let uuidGroupLengths = [8, 4, 4, 4, 12]

    /// R-56.1's route must be **exercised**, not merely present: if this ever falls to zero,
    /// family 11 has stopped testing anything.
    public static let noNegativeBasisFloor = 1

    /// The cache hit rate the committed workload achieves, rounded down with a margin. Measured
    /// at 0.8466 over 205 lookups of 47 distinct sentences; the floor is set below that so a
    /// re-ordered corpus does not redden the gate, and far enough above zero that a real
    /// regression — a corpus rewritten so every case carries a unique priority, or a scorer that
    /// stopped memoising — shows up here rather than being inferred.
    public static let cacheHitRateFloor = 0.70

    // MARK: - e05's split metric (R-94, R-94a, §4.4)

    /// **Zero, not "small", and unchanged from e04.** A wrong accusation is the failure the whole
    /// product boundary exists to prevent, and `nudge.accusationFalsePositiveRate` is asserted
    /// **equal** to `falseNudgeRate` so the split is explicit and the two halves cannot disagree.
    public static let accusationFalsePositiveCeiling: Double = 0

    /// **A floor on the app ACCUSING, because every other nudge metric is satisfied by silence**
    /// (focus-237).
    ///
    /// Measured on the shipping corpus at HEAD: all eleven gated nudge metrics are a ceiling, a
    /// zero-equality, or a floor a silent app meets — `accusationFalsePositiveRate == 0`,
    /// `accusationsFromQuery == 0`, `queryVolumeRate <= 0.17`, and so on down to
    /// `queryGroundTruthCoverage >= 1.0`, whose own comment says it "fails closed" and which for
    /// a silent app fails **open**, because `owedLabel == 0` returns the floor itself. So an app
    /// that had stopped accusing altogether passed the evaluation lane with eleven green metrics.
    ///
    /// One, not "several": this is the line between an app that accuses and an app that does not,
    /// and a bigger number would be this file choosing how loud the product is, which is
    /// `InterventionPolicy`'s job and the day fixtures' job. The days carry the shape — day-01
    /// commits one accusation, day-02 and day-03 commit none — and `measureNudge` now compares
    /// every replayed day against what its fixture claims, so a day that went silent is a named
    /// failure rather than a number that moved.
    public static let accusationsDeliveredFloor = 1

    /// **A volume ceiling, and it is named for what it measures** (R-94a, finding 2).
    ///
    /// Renamed from `queryRate` in adversarial review because the old name claimed a measurement
    /// this number does not make: P-140 enumerated every field of all 165 committed cases and
    /// found no field anywhere recording what a person would have answered, so `28/165` is an
    /// incidence of questions asked rather than a rate of questions that should not have been.
    ///
    /// **Derived, not chosen.** P-138 measured 28 distinct askable (subject, priority) pairs over
    /// 165 classifications = 0.1697; P-140's stricter keying, which drops the one pair with no
    /// bundle identifier, gives 0.1576. Seventeen hundredths bounds both. What it bounds is *how
    /// often the app opens its mouth per judgement*, which is a real and gateable failure mode.
    public static let queryVolumeRateCeiling = 0.17

    /// The floor P-138 measured at 25/72 = 0.3472, and a **floor** rather than a ceiling because
    /// the cheapest way to make the app look less chatty would be to quietly reclassify an
    /// unaskable reason as askable (R-94).
    public static let unaskableUncertaintyFloor = 0.34

    /// **A two-sided band, where both ends fail** (R-94a).
    ///
    /// The reviewer proposed gating *relevant answers ÷ delivered queries* with a ceiling. That
    /// definition inverts U-1: a "yes" is the affordance working — one click, a durable rule, a
    /// subject never asked about again — and a ceiling on it creates a direct incentive to ask
    /// fewer of the questions U-1 exists to license. Read as a band it keeps every diagnostic the
    /// reviewer wanted and removes the incentive to go quiet:
    ///
    /// * **above 0.75** the app is asking about work it should have recognised, U-1's bargain is
    ///   not being kept, and e06's model has a target;
    /// * **below 0.25** the app is using a polite question as a euphemism for an accusation it had
    ///   the evidence to make.
    public static let queryAnsweredRelevantFloor = 0.25
    public static let queryAnsweredRelevantCeiling = 0.75

    /// Coverage of the `queryGroundTruth` label over the cases that owe one. **The gate fails
    /// closed below 1.0** rather than scoring a band on absent data.
    public static let queryGroundTruthCoverageFloor = 1.0

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
