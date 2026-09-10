import Foundation

/// What a constant owes before it may be called committed (R-74).
///
/// R-59 makes every threshold named, digested and versioned. That is a mechanism against
/// *silent change* — it is **not** evidence that the value is right, and conflating the two is
/// how a number that arrived by narrative ends up looking audited. This class column is what
/// says which evidence each constant owes.
public enum PolicyConstantClass: String, Sendable, CaseIterable, Codable, Hashable {
    /// **Behavioural.** Changing it changes a verdict, an eligibility or a drift state. Owes a
    /// committed boundary triple (−1 / exact / +1) *and* a mutation witness naming the corpus
    /// case that fails at the nearest plausible alternative value. Narrative justification is
    /// not sufficient for a B constant and never was.
    case behavioural = "B"
    /// **Capacity.** It bounds cost, not judgement. Owes a committed workload benchmark with a
    /// stated eviction/hit profile — not a single-call latency figure, which measures the
    /// wrong thing.
    case capacity = "C"
    /// **Structural.** An ordinal or a set with no numeric neighbour to test. Owes an
    /// ordering-invariant test only.
    case structural = "S"
}

/// One constant's entry in the manifest: what it is, what class it is, what it encodes to for
/// the digest, what justifies it, and — for a B constant — which corpus case would notice it
/// moving and to what value.
///
/// The manifest is not documentation. `RelevancePolicyTests` asserts that every constant
/// declared here is digested, that every **B** constant names at least one witness and one
/// mutation value, and `MutationWitnessTests` (T104a) re-runs the corpus against a mutated
/// policy and asserts the named case actually flips. A B constant with no witness fails the
/// suite, which is what turns "corpus-tested constant" from an adjective into a gate.
public struct PolicyConstant: Sendable, Equatable, Hashable {
    /// The `static let`'s name, exactly.
    public let name: String
    public let kind: PolicyConstantClass
    /// The canonical encoding digested by `RelevancePolicy.digest`, in declaration order.
    public let encoded: String
    /// The probe or ruling that justifies the value — `P-114`, `R-56.1`, `D-05`.
    public let justification: String
    /// Corpus case ids that flip when this constant is mutated. **B constants only.**
    ///
    /// The ids are allocated here, before the corpus exists, because a witness chosen after
    /// the fact is a witness chosen to pass. Phase D creates cases with exactly these ids and
    /// exactly the shapes the comments below describe.
    public let witnesses: [String]
    /// The nearest plausible alternatives a maintainer would reach for. **B constants only.**
    public let mutations: [String]

    public init(
        name: String,
        kind: PolicyConstantClass,
        encoded: String,
        justification: String,
        witnesses: [String] = [],
        mutations: [String] = []
    ) {
        self.name = name
        self.kind = kind
        self.encoded = encoded
        self.justification = justification
        self.witnesses = witnesses
        self.mutations = mutations
    }
}

/// A threshold whose value is **derived from a committed measurement table**, not chosen.
///
/// P-113's sixteen similarity pairs and P-115's four language strings are too thin to fix a
/// float on: one additional unrelated pair below the drafted ceiling would have falsified its
/// whole justification. So R-74.2 defers both values to probe **P-124** (task T90a), which
/// scores ≥ 60 labelled pairs and ≥ 40 labelled strings, commits the raw tables as corpus
/// resources, and computes each constant by a rule this plan committed in advance.
///
/// Until that lands the value is **absent, not guessed**, and that is deliberate: a constant
/// measured after the code that reads it was written is a constant chosen to keep that code
/// green. `SimilarityScorer` cannot obtain a `Double` from `.pendingMeasurement`, so the
/// similarity signal simply does not run — which is the conservative direction, and the same
/// answer the English gate gives for a language this OS has no embedding for.
public enum DerivedThreshold: Sendable, Equatable, Hashable, Codable {
    /// P-124 has not been run yet. `RelevancePolicyTests` fails while any constant is in this
    /// state, by design (T83): the gate is what stops the value being written down early.
    case pendingMeasurement
    /// Derived from the committed table by the rule in the constant's doc comment, and
    /// re-derived by `SimilarityCorpusTests`, so a hand-edited constant against an unchanged
    /// table is a red gate.
    case measured(Double)

    public var value: Double? {
        switch self {
        case .pendingMeasurement: nil
        case .measured(let value): value
        }
    }

    public var isMeasured: Bool { value != nil }

    /// The canonical encoding for the digest. Two decimals, because both derivation rules
    /// round to two.
    public var encoded: String {
        switch self {
        case .pendingMeasurement: "pending"
        case .measured(let value): String(format: "%.2f", value)
        }
    }
}

/// FNV-1a over UTF-8 bytes, 64-bit.
///
/// **Never `Hasher`.** Probe P-118 established the reason the hard way: Swift's `Hasher` is
/// seeded per process, and an earlier run of that probe produced two different values for
/// identical data. Every digest in this epic — the policy digest, the corpus digest, the
/// normalisation digest, the transcript digest — is FNV-1a, so that two runs and two processes
/// agree and a committed literal means something.
public enum FNV1a {
    public static func hash(_ string: String) -> UInt64 {
        hash(Array(string.utf8))
    }

    public static func hash(_ bytes: some Sequence<UInt8>) -> UInt64 {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            value ^= UInt64(byte)
            value = value &* 0x0000_0100_0000_01b3
        }
        return value
    }

    /// `0x…`, sixteen lowercase hex digits. The form every committed digest literal takes.
    public static func hex(_ value: UInt64) -> String {
        "0x" + String(format: "%016lx", value)
    }
}

/// **Every threshold in the relevance engine, in one file.**
///
/// This is the only file in `FocusCore/Relevance/` and `FocusClassify/Sources/` in which a
/// numeric literal may appear, and `check-forbidden.sh`'s R-70f lint enforces it. That is what
/// makes "no magic numbers" mechanical instead of a habit: a threshold cannot be introduced
/// somewhere else, and a threshold introduced here cannot move without changing
/// `RelevancePolicy.digest`, which fails `RelevancePolicyTests` until `EngineStamp.policyVersion`
/// is bumped and the digest re-recorded.
///
/// Each constant's doc comment names the probe or ruling that justifies it **and its class**
/// (R-74). The manifest at the foot of this file is the machine-readable form of the same
/// thing, and it is what the digest and the witness assertions read.
public enum RelevancePolicy {
    // MARK: - Normalisation (R-57)

    /// **B.** P-119: a length-4 filter loses `bug`, `fix`, `app` and `iOS` from real
    /// priorities. Genericity is handled by the stop list, not by length — a short word that
    /// matches everything is a stop word, not a short word.
    public static let minimumTokenLength = 3

    /// **B.** P-114: every true overlap token in the measured corpus — `proposal`, `budget`,
    /// `sprint`, `ticket`, `board` — is five characters or more. An overlap on a token of at
    /// least this length bands `.medium`; anything shorter bands `.low`, which cannot mandate.
    public static let minimumStrongTokenLength = 4

    /// **B.** P-114: unrelated Jaccard was **0.000 on all eight** measured pairs. One strong
    /// overlap is already a zero-false-positive signal; requiring two would only add misses,
    /// and a miss falls to `uncertain`, which suppresses.
    public static let minimumOverlapTokens = 1

    /// **B.** Condition 1 of the negative basis (R-56.1): the floor below which a priority is
    /// not judgeable at all. *"stuff"*, *"work"* and *"catch up"* sit below it, and P-115
    /// corroborates from the other side — a one-word English string scores only 0.41 on
    /// language confidence.
    public static let minimumPriorityContentTokens = 2

    // MARK: - The negative basis (R-56.1)

    /// **B.** Condition 2 of the negative basis, and the most consequential constant in the
    /// epic. The number of `app`/`domain` context identities a priority must carry before an
    /// *absence* of overlap is informative about anything.
    ///
    /// At `0` the engine reaches absence-plus-dwell for a productive application whose
    /// reverse-DNS name says nothing about the work — Excel against *"Write the Q3 proposal
    /// for Acme"* — and accuses somebody of slacking off for doing their job. That is why `0`
    /// is the committed mutation value: the corpus must demonstrably reintroduce the false
    /// accusation when the guard is removed.
    public static let minimumNegativeBasisItems = 1

    /// **S.** R-56.1: only an *identity* can be absent in a way that means something. A
    /// `keyword` can only ever match positively, so its absence is the same absence the
    /// overlap stage already declined to conclude from; a `file` cannot be observed at zero
    /// grants at all, so it can neither match nor fail to match.
    public static let negativeBasisKinds: [ContextItemKind] = [.app, .domain]

    // MARK: - Explanation (R-62)

    /// **B.** An explanation is evidence, not a transcript: three words a person can check at
    /// a glance beat twelve they will not read. Enforced at construction by
    /// `Explanation.make(…)`, not by convention.
    public static let maximumExplanationTokens = 3

    // MARK: - Similarity and language (R-58, R-74.2)

    /// **B, derived.** The distance at or below which the sentence-similarity signal may
    /// *corroborate* `relevant`. It may **never** produce `unrelated`, at any distance, because
    /// P-113 measured the two classes overlapping — the unrelated maximum sits *inside* the
    /// related range, so there is no upper region the unrelated class occupies alone.
    ///
    /// **Derivation rule (committed in advance, R-58):** the measured unrelated **minimum**,
    /// minus one measured standard deviation of the unrelated class, rounded **down** to two
    /// decimals. Rounding down costs misses rather than false positives, which is the
    /// direction this whole engine leans. Supplied by P-124 at T90a and asserted by
    /// recomputation from the committed table.
    ///
    /// **Measured (P-124, 62 labelled pairs, 30 related and 32 unrelated):** related
    /// `min 0.5796 · mean 0.9863 · max 1.2664`; unrelated
    /// `min 1.0437 · mean 1.1623 · max 1.3046`, population σ `0.0733`. The rule gives
    /// `1.0437 − 0.0733 = 0.9705`, rounded down to **`0.97`** — at which the corpus shows
    /// **0 false positives**, 14 true positives and 16 misses, and every miss falls to
    /// `uncertain`, which suppresses.
    ///
    /// The classes still overlap heavily, exactly as P-113 found at sixteen pairs: **28 of the
    /// 32 unrelated pairs sit inside the related range**, and 11 of the 30 related pairs sit
    /// above the unrelated minimum. Four unrelated pairs do sit above the related *sample*
    /// maximum — and that region is not a licence to accuse, because one new related pair above
    /// 1.2664 erases it, which is R-74.2's own argument pointed at the outcome that would cost
    /// a false accusation rather than a miss. So **similarity may never produce `unrelated` at
    /// any distance** (R-58): a ruling about the shape of the evidence rather than about this
    /// number, and one that stands whatever the number turns out to be.
    public static let similarityRelevantCeiling: DerivedThreshold = .measured(0.97)

    /// **B, derived.** The `NLLanguageRecognizer` confidence both sides must reach, in English,
    /// before similarity is consulted at all. P-111 measured `NLEmbedding` returning `nil` for
    /// `fr`, `de`, `ja`, `zh-Hans` and `es`, so for anything else there is nothing to consult;
    /// P-115 measured a single-word English string at **0.41**, so the floor also disqualifies
    /// input too short to be judged. Both routes end at `uncertain`, which is the correct
    /// answer to "I have no instrument for this".
    ///
    /// **Derivation rule (committed in advance, R-58):** the midpoint between the lowest
    /// scoring judgeable English string and the highest scoring non-judgeable one, rounded
    /// **up** to two decimals. Supplied by P-124 at T90a.
    ///
    /// **Measured (P-124, 42 labelled strings):** judgeable English `min 0.7618`, and the
    /// highest non-judgeable is the two-word fragment *"catch up"* at `0.9090`. The rule gives
    /// `(0.7618 + 0.9090) / 2 = 0.8354`, rounded up to **`0.84`**.
    ///
    /// **The measurement returned a negative result and it is recorded rather than smoothed.**
    /// The two classes *overlap*: three English fragments — `work` (0.8832), `the thing`
    /// (0.8435) and `catch up` (0.9090) — score above the lowest real English sentence
    /// (`bergman audit findings spreadsheet`, 0.7618). So P-115's suggestion that this signal
    /// also separates short input from long does **not** generalise from its single measured
    /// point, and this constant is an English gate rather than a vagueness gate. The
    /// vagueness gate is `minimumPriorityContentTokens`, and all three of those fragments
    /// carry fewer content tokens than it requires — the two guards are complementary, which
    /// is why the overlap costs nothing.
    ///
    /// What the floor *does* separate cleanly is the thing P-111 forces it to: all fourteen
    /// non-English strings score English at or below `0.0001`, so a non-English priority
    /// reaches the similarity signal at no confidence at all.
    public static let languageConfidenceFloor: DerivedThreshold = .measured(0.84)

    /// **C.** The bounded LRU of evidence-side sentence vectors. P-116's 3.48 ms is a
    /// *per-call* figure and does not justify a capacity, so R-74.4 requires a committed
    /// 64/128/256/512 sweep over the corpus's real evidence-sentence distribution, reporting
    /// hit rate, evictions and p95; **the committed value is the smallest capacity whose p95 is
    /// within 10% of the best measured.** That rule was committed before the sweep was run,
    /// precisely so this number would be derived rather than chosen.
    ///
    /// **Measured (T103's sweep, 205 lookups over 47 distinct sentences):** every capacity in
    /// the sweep returns p95 `1.7447 ms` and **zero** evictions, because the workload holds
    /// fewer distinct sentences than the smallest candidate. The rule's answer is therefore
    /// **64**, and `evaluation.json` carries the whole sweep plus an `isDiscriminating` flag
    /// saying, honestly, that this workload cannot tell the four candidates apart.
    ///
    /// The flag is reported; it is not a licence to keep a larger number. A capacity the
    /// benchmark cannot justify is exactly the un-evidenced 256 that R-74.4 exists to replace,
    /// and a sweep that says *"64 is enough"* is evidence for 64 even when it is not evidence
    /// against 512. `EvaluationGate` fails the run unless this constant equals the sweep's
    /// recommendation, so when e07 turns window titles on and the evidence-side stream becomes
    /// the distinct titles of a working day, the benchmark starts discriminating, the
    /// recommendation moves, and the gate goes red until the constant is re-derived — rather
    /// than the number being quietly left where somebody once put it.
    public static let similarityCacheCapacity = 64

    // MARK: - The intervention floor (R-56)

    /// **S.** A `.low` band can never mandate. This single constant is what makes the
    /// similarity signal structurally incapable of causing a nudge on its own, which is the
    /// design conclusion P-113 forces.
    public static let interventionBandFloor: EvidenceBand = .medium

    // MARK: - Time (R-60, R-61)

    /// **B.** D-05's own figure — *"left IDE <90s ago for docs" ≠ drift* — and 4 000× the
    /// 22 ms activation-storm window e03 measured at P-82, so debounce noise cannot traverse
    /// it. Boundary triple at 89 / 90 / 91 seconds; the mandate is issued at the first
    /// observation **after** the threshold, so 90 exactly does not mandate.
    public static let sustainedDriftThreshold: Duration = .seconds(90)

    /// **B.** The shortest return that counts as a return. Without it, alt-tabbing back to the
    /// IDE for one second every minute makes the app permanently mute — the single most
    /// obvious way to defeat a drift detector, and the one a naïve implementation always has.
    /// Twenty seconds cannot be produced by an activation storm (P-82) or a window flurry.
    public static let driftResetGrace: Duration = .seconds(20)

    /// **B.** Past five minutes a person is not glancing, and the band rises `.medium` →
    /// `.high`. Boundary triple at 299 / 300 / 301 seconds, with mutation witnesses at 240 and
    /// 360 — the two values a maintainer would reach for first.
    public static let escalationDwell: Duration = .seconds(300)

    /// **B.** One mandate per subject per ten minutes, **from the engine**. e05's ladder has
    /// its own proportionality on top of this; an engine that could issue two mandates a
    /// minute would make that ladder's job impossible.
    public static let mandateCooldown: Duration = .seconds(600)

    /// **B.** Twice `sustainedDriftThreshold`: long enough to contain a whole detour and its
    /// anchor, short enough that yesterday is not evidence. Tested as a **relation** rather
    /// than as a number — `lookBackSpan == sustainedDriftThreshold * 2` is asserted — so the
    /// two cannot drift apart independently.
    public static let lookBackSpan: Duration = .seconds(180)

    /// **C.** The look-back must be O(1) and replayable. R-74.4 requires a benchmark showing
    /// that truncating the window to this many events produces a transcript byte-identical to
    /// an untruncated replay over every sequence fixture — which is what makes 32 *sufficient*
    /// rather than merely bounded. If a fixture ever needs more, that assertion fails and the
    /// constant is re-derived rather than quietly raised.
    public static let maximumLookBackEvents = 32

    /// **B.** How long a relevant subject must have held to count as somewhere you *were*, and
    /// therefore as somewhere you can be detouring *from* (R-61).
    public static let returnAnchorDwell: Duration = .seconds(30)

    /// **B.** An anchored detour gets a second grace period — which is exactly D-05's
    /// `IDE → docs → IDE`, at an effective threshold of 180 seconds. The window may **only**
    /// extend the threshold: a look-back that could make the app *more* likely to nudge is one
    /// that has to be right, and one that can only make it less likely can only be
    /// conservative.
    public static let detourExtension: Duration = .seconds(90)

    /// **S.** e03 already owns the two idle sources and their 180-second threshold. A person
    /// who walked away is not drifting, so an idle observation freezes the accumulator rather
    /// than advancing or resetting it.
    public static let idleSuspendsAccumulation = true

    // MARK: - The manifest, the digest and the version

    /// Every constant above, in **declaration order**, with its class and its evidence.
    ///
    /// Declaration order is load-bearing: the digest is computed over this sequence, so
    /// re-ordering the manifest changes the digest and fails the suite — which is correct,
    /// because the manifest is what a reviewer reads to check that the file and the evidence
    /// agree.
    public static let manifest: [PolicyConstant] = [
        PolicyConstant(
            name: "minimumTokenLength",
            kind: .behavioural,
            encoded: "\(minimumTokenLength)",
            justification: "P-119",
            // A priority naming a three-character content token (`bug`, `fix`, `iOS`) that
            // overlaps the evidence. At 4 the token is filtered out and the case declines.
            witnesses: ["gc-0201"],
            mutations: ["4"]
        ),
        PolicyConstant(
            name: "minimumStrongTokenLength",
            kind: .behavioural,
            encoded: "\(minimumStrongTokenLength)",
            justification: "P-114",
            // An overlap on a four-character token, banded `.medium`. At 5 it bands `.low`,
            // which is below the intervention floor, so the eligibility flips to suppressed.
            witnesses: ["gc-0202"],
            mutations: ["3", "5"]
        ),
        PolicyConstant(
            name: "minimumOverlapTokens",
            kind: .behavioural,
            encoded: "\(minimumOverlapTokens)",
            justification: "P-114",
            // Exactly one strong overlap token. At 2 the case falls through to `uncertain`.
            witnesses: ["gc-0203"],
            mutations: ["2"]
        ),
        PolicyConstant(
            name: "minimumPriorityContentTokens",
            kind: .behavioural,
            encoded: "\(minimumPriorityContentTokens)",
            justification: "R-56.1",
            // A two-content-token priority that is judgeable at 2 and becomes
            // `uncertain(.insufficientPriorityEvidence)` at 3.
            witnesses: ["gc-0204"],
            mutations: ["1", "3"]
        ),
        PolicyConstant(
            name: "minimumNegativeBasisItems",
            kind: .behavioural,
            encoded: "\(minimumNegativeBasisItems)",
            justification: "R-56.1",
            // **The strongest witness in the epic.** Family 11's productive-tool case:
            // a well-specified priority, no `app`/`domain` context identity, a lexically
            // silent productive application, dwelt past the threshold. At 0 it becomes
            // `unrelated` at band `.medium` and MANDATES — the false accusation R-56.1 exists
            // to prevent — so the corpus demonstrably reintroduces the defect when the guard
            // is removed.
            witnesses: ["gc-0301"],
            mutations: ["0"]
        ),
        PolicyConstant(
            name: "negativeBasisKinds",
            kind: .structural,
            encoded: negativeBasisKinds.map(\.rawValue).joined(separator: ","),
            justification: "R-56.1"
        ),
        PolicyConstant(
            name: "maximumExplanationTokens",
            kind: .behavioural,
            encoded: "\(maximumExplanationTokens)",
            justification: "R-62",
            // An overlap of four tokens, of which exactly three reach the explanation.
            witnesses: ["gc-0205"],
            mutations: ["2", "4"]
        ),
        PolicyConstant(
            name: "similarityRelevantCeiling",
            kind: .behavioural,
            encoded: similarityRelevantCeiling.encoded,
            justification: "P-124",
            // A measured pair whose distance sits just inside the derived ceiling and
            // corroborates, and its neighbour just outside, which does not.
            witnesses: ["gc-0206"],
            mutations: ["0.96", "0.98"]
        ),
        PolicyConstant(
            name: "languageConfidenceFloor",
            kind: .behavioural,
            encoded: languageConfidenceFloor.encoded,
            justification: "P-124",
            // A priority scoring 0.8678 on English, just above the floor, whose sentence vector
            // is therefore taken and whose similarity corroborates. Its sibling at 0.7618 —
            // identical evidence, a distance well inside the ceiling — does not.
            //
            // **The mutation values are ±0.06 rather than ±0.01, and that is a measurement
            // rather than a preference.** P-124 found nothing at all between 0.7618 and 0.9090:
            // the derivation rule placed this floor at the midpoint of an empty interval, so
            // every string in the corpus is more than a hundredth away from it and a ±0.01
            // mutation cannot flip a single fixture. A mutation value no witness responds to is
            // not evidence that the constant is tested — it is the appearance of evidence,
            // which is the thing R-74 exists to remove. So the committed alternatives are the
            // two a maintainer would actually reach for: P-115's original `0.60`, which admits
            // the sibling, and a round `0.90`, which excludes the witness.
            witnesses: ["gc-0207"],
            mutations: ["0.60", "0.90"]
        ),
        PolicyConstant(
            name: "similarityCacheCapacity",
            kind: .capacity,
            encoded: "\(similarityCacheCapacity)",
            justification: "R-74.4"
        ),
        PolicyConstant(
            name: "interventionBandFloor",
            kind: .structural,
            encoded: interventionBandFloor.rawValue,
            justification: "R-56"
        ),
        PolicyConstant(
            name: "sustainedDriftThreshold",
            kind: .behavioural,
            encoded: Self.encode(sustainedDriftThreshold),
            justification: "D-05",
            // The temporal boundary triple: 89 s (no mandate), 90 s (no mandate — the
            // threshold is crossed at the first observation AFTER it), 91 s (one mandate).
            witnesses: ["seq-0003"],
            mutations: ["60s", "120s"]
        ),
        PolicyConstant(
            name: "driftResetGrace",
            kind: .behavioural,
            encoded: Self.encode(driftResetGrace),
            justification: "R-60",
            // A 19-second return that does not reset the accumulator and a 21-second one that
            // does — the anti-defeat property, as a fixture.
            witnesses: ["seq-0005"],
            mutations: ["5s", "30s"]
        ),
        PolicyConstant(
            name: "escalationDwell",
            kind: .behavioural,
            encoded: Self.encode(escalationDwell),
            justification: "R-56",
            // Dwell at 299 s bands `.medium`; at 301 s it bands `.high`.
            witnesses: ["seq-0006"],
            mutations: ["240s", "360s"]
        ),
        PolicyConstant(
            name: "mandateCooldown",
            kind: .behavioural,
            encoded: Self.encode(mandateCooldown),
            justification: "R-60",
            // Two sustained stretches 599 s apart produce one mandate; 601 s apart, two.
            witnesses: ["seq-0007"],
            mutations: ["300s", "900s"]
        ),
        PolicyConstant(
            name: "lookBackSpan",
            kind: .behavioural,
            encoded: Self.encode(lookBackSpan),
            justification: "R-61",
            // An anchor 179 s back is still in the window; one 181 s back is not.
            witnesses: ["seq-0008"],
            mutations: ["90s", "360s"]
        ),
        PolicyConstant(
            name: "maximumLookBackEvents",
            kind: .capacity,
            encoded: "\(maximumLookBackEvents)",
            justification: "R-74.4"
        ),
        PolicyConstant(
            name: "returnAnchorDwell",
            kind: .behavioural,
            encoded: Self.encode(returnAnchorDwell),
            justification: "R-61",
            // A 29-second anchor does not extend the threshold; a 31-second one does.
            witnesses: ["seq-0009"],
            mutations: ["15s", "60s"]
        ),
        PolicyConstant(
            name: "detourExtension",
            kind: .behavioural,
            encoded: Self.encode(detourExtension),
            justification: "D-05",
            // D-05's own example: IDE → docs (100 s) → IDE, which mandates at 90 s without the
            // extension and does not mandate at all with it.
            witnesses: ["seq-0010"],
            mutations: ["45s", "180s"]
        ),
        PolicyConstant(
            name: "idleSuspendsAccumulation",
            kind: .structural,
            encoded: "\(idleSuspendsAccumulation)",
            justification: "R-60"
        )
    ]

    /// The canonical encoding the digest is taken over: `name=value`, in declaration order,
    /// separated by `;`. Deterministic, printable, and diffable in a failure message.
    public static var canonicalEncoding: String {
        manifest.map { "\($0.name)=\($0.encoded)" }.joined(separator: ";")
    }

    /// FNV-1a over `canonicalEncoding`. Asserted against a committed literal.
    ///
    /// Changing any threshold changes this and fails `RelevancePolicyTests` until
    /// `EngineStamp.policyVersion` is bumped and the digest re-recorded — which is the
    /// mechanism that makes "every threshold is a committed constant" a property of the build
    /// rather than a habit.
    public static var digest: UInt64 { FNV1a.hash(canonicalEncoding) }

    /// `0x…`, the form the committed literal and `evaluation.json`'s `policyDigest` take.
    public static var digestHex: String { FNV1a.hex(digest) }

    /// Seconds, as an integer with an `s` suffix. A `Duration`'s description is not a stable
    /// serialisation and a `Double` of seconds would round differently on two machines.
    static func encode(_ duration: Duration) -> String {
        "\(duration.components.seconds)s"
    }
}
