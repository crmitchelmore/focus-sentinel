import Foundation

/// How a person may pause, as a closed set of presets.
///
/// F-64's own three, declared here because they *are* a policy constant — `pauseDurations` is
/// the list, and a fourth preset is an edit to the manifest and therefore to the digest. The
/// request type that carries a chosen preset onto e03's `SessionMachine` is `PauseRequest`;
/// this is the vocabulary it chooses from, so there is no second pause concept.
public enum PausePreset: Sendable, Equatable, Hashable, Codable {
    /// A fixed span from now.
    case fixed(Duration)
    /// Until a wall-clock time the person picks.
    case untilTime
    /// The rest of the local day.
    case restOfDay

    /// The canonical encoding this preset contributes to the digest.
    public var encoded: String {
        switch self {
        case .fixed(let span): "\(span.components.seconds)"
        case .untilTime: "untilTime"
        case .restOfDay: "restOfDay"
        }
    }
}

/// A local-time window, as a pair of minute-of-day offsets.
///
/// The *value* lives here because `quietHoursDefault` is a policy constant and a constant's
/// type belongs beside it; the *evaluation* — wrapping midnight, an injected `Calendar` and
/// `Locale`, DST — is `QuietHours`, which consumes this. R-85's ruling is that the shipped
/// default is **no window at all**, so this type is declared and the constant is `nil`.
public struct QuietHoursWindow: Sendable, Equatable, Hashable, Codable {
    /// Minutes since local midnight, inclusive.
    public let startMinuteOfDay: Int
    /// Minutes since local midnight, exclusive. May be *less* than `startMinuteOfDay`, which
    /// is a window that wraps midnight and is the common case for a quiet-hours setting.
    public let endMinuteOfDay: Int

    public init(startMinuteOfDay: Int, endMinuteOfDay: Int) {
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
    }

    public var encoded: String { "\(startMinuteOfDay)-\(endMinuteOfDay)" }
}

/// How long a ledger keeps its rows.
///
/// A **C** constant with no number in it, deliberately: the query ledger's rows die with their
/// priority (F-115/F-116) and with nothing else, so what it owes is a purge-completeness test
/// rather than a latency figure.
public enum NudgeRetentionRule: String, Sendable, CaseIterable, Codable, Hashable {
    /// Rows die with the priority they were written under, and with nothing else.
    case withPriority
    /// Rows ride the activity log's user-chosen retention span.
    case activityRetentionPicker
}

/// **Every threshold in the nudge loop, in one file — and deliberately not in
/// `RelevancePolicy`.**
///
/// The reason is concrete rather than tidy. `RelevancePolicy.digest` feeds
/// `EngineStamp.cacheKey`, which e06's verdict cache keys on. Putting a snooze duration in that
/// manifest would mean **changing a cooldown invalidates every cached verdict** — a cache
/// stampede caused by a copy-adjacent tuning change. Two policies, two digests, one
/// `EngineStamp` carrying both, and `cacheKey` untouched (R-95).
///
/// This is the **second and last** file in the nudge graph in which a numeric literal may
/// appear, and `check-forbidden.sh`'s R-96j lint enforces it — the same instrument R-70f
/// aims at `RelevancePolicy`. Each constant's doc comment names the probe, ruling or relation
/// that justifies it **and its class** (R-74); the manifest at the foot of the file is the
/// machine-readable form of the same thing, and it is what the digest and the witness
/// assertions read.
public enum InterventionPolicy {
    // MARK: - Cooldowns and the dwell a question needs (R-83, R-95)

    /// **B.** How long a person must have been with a subject before a *question* is
    /// warranted. Boundary triple 44 / 45 / 46.
    ///
    /// Asserted as the **relation** `× 2 == RelevancePolicy.sustainedDriftThreshold`: a
    /// question may come at half the dwell an accusation needs, because it is cheaper — one
    /// click, a durable rule, and the app never has to ask again — but never instantly. A
    /// question the moment somebody opens an application is a question about a keystroke, not
    /// about their work.
    public static let queryDwellThreshold: Duration = .seconds(45)

    /// **B.** The minimum gap between two questions. Boundary triple 179 / 180 / 181.
    ///
    /// Asserted as the **relation** `== RelevancePolicy.lookBackSpan`, so a question and a
    /// look-back agree on what "just now" means. It is 8 000× e03's measured 22 ms activation
    /// storm (P-82), so tab-hopping through four applications in a minute produces **one**
    /// question rather than four.
    public static let queryCooldown: Duration = .seconds(180)

    /// **B.** Two consecutive questions declined or dismissed without an answer suspend
    /// questions altogether. Boundary triple 1 / 2 / 3.
    ///
    /// Two unanswered questions is the point at which the app is talking to itself.
    public static let ignoredQueryBackoff = 2

    /// **B.** Two delivered accusation rungs with no correction, snooze, pause or return
    /// drop the ladder back to `.ambient` for `backoffSpan`. Boundary triple
    /// 1 / 2 / 3. F-63's "back off when ignored", with the ambient rung retained because going
    /// fully silent would lose the one channel the person has not objected to.
    ///
    /// **The hold it arms is time-bounded, and was not** (focus-845). This constant's own value
    /// is unchanged; what changed is the consequence of it firing. See `backoffSpan` below.
    ///
    /// **It moved with the rung count** (U-2), and the reason it was given at the time was wrong
    /// in a way worth writing down (focus-yxb).
    ///
    /// The stated argument was: `candidate(…)` answers `nil` at the top rung, so with the ladder
    /// cut to two rungs a third delivery can never happen, so a backoff of 3 could never trip.
    /// **That argument is about the ladder, and this constant has two consumers with differently
    /// scoped counters.** Measured, driving the loop's own sequence — drift, glyph, panel,
    /// dismiss — over four different subjects:
    ///
    ///     round 1  ladder.consecutiveIgnored=1  engaged  | fatigue.count=1  held=false
    ///     round 2  ladder.consecutiveIgnored=1  engaged  | fatigue.count=0  held=TRUE
    ///     round 3  ladder.consecutiveIgnored=1  engaged  | fatigue.count=1  held=true
    ///
    /// * **`FatigueController`'s run is session-wide.** Nothing but an answered accusation resets
    ///   it, so a subject change carries it forward and the second dismissal of the session trips
    ///   the hold — whatever it was about. This constant fires, and `NudgeReachabilityTests`
    ///   drives the sequence that fires it. A backoff of 3 would have tripped too, on the third
    ///   subject; the old rationale was false, not merely unlucky.
    /// * **`LadderMachine`'s run is per subject.** `arrive(_:)` resets to `.idle` for a different
    ///   drift, and `candidate(…)` answers `nil` for the same one once it has been ignored, so
    ///   the ladder's own count cannot pass 1 — measured above, in every round. From
    ///   `NudgeHost`'s events, `LadderState.heldAtAmbient` is therefore unreachable and the
    ///   ladder is quiet for a subject by arithmetic rather than by decision. The replay model
    ///   is not so limited: `seq-0023` scripts an ignored **ambient** rung, which the host offers
    ///   no way to produce, and reaches the ladder's own hold in two. That divergence is pinned
    ///   by `NudgeReachabilityTests` and belongs to the round that owns the corpus.
    ///
    /// So the number stands, on the consumer that can reach it: two ignored accusations in a
    /// session is the point at which the app is talking to itself. Boundary triple 1 / 2 / 3.
    public static let ignoredAccusationBackoff = 2

    /// **B.** How long a tripped backoff lasts — **either** of them. Boundary triple
    /// 3599 / 3600 / 3601 — one hour, which is long enough to be a real rest and short enough
    /// that a person who changes what they are doing is not ignored for the afternoon.
    ///
    /// **It was `queryBackoffSpan`, and the accusation hold had no span at all** (focus-845).
    /// `ignoredQueryBackoff` and `ignoredAccusationBackoff` are the same instrument aimed at the
    /// two kinds — both are 2, both mean *"the app is talking to itself"* — but only the question
    /// side was time-bounded. The accusation side set a `Bool` that nothing but `sessionEnded`
    /// could clear, so two dismissals silenced the only rung that carries a sentence for the rest
    /// of the session. Since U-2 cut the ladder to two rungs that is the whole speaking product,
    /// muted by an afternoon's two clicks and never given back.
    ///
    /// One constant rather than two asserted equal, because a threshold with two homes is a
    /// threshold that can be moved in one of them. The consequence is the policy stated plainly:
    /// **a backoff this app imposes lasts an hour, whichever kind of interruption tripped it.**
    public static let backoffSpan: Duration = .seconds(3600)

    // MARK: - The caps, and the budget they share (R-83)

    /// **B.** Questions per priority per local day. Boundary triple 3 / 4 / 5.
    ///
    /// P-138: four covers **16 of the 17** corpus priorities' askable subjects in full. The one
    /// it does not — nine askable subjects — is deliberately spread across days, and its
    /// unasked subjects stay silent-uncertain, which is the pre-U-1 behaviour. So the cap can
    /// never make the app *worse* than the shipped baseline.
    public static let dailyQueryCap = 4

    /// **B.** Questions per local day across **every** priority. Boundary triple 4 / 5 / 6.
    ///
    /// Added in adversarial review, and the defect it closes is real: a cap that is *per
    /// priority* is not a cap on a person's day. Three priorities in one day would have
    /// licensed twelve questions under `dailyQueryCap` alone, held down only by the shared
    /// budget's seven. The number a person feels is questions-per-day, so that is the number
    /// with a constant, a fixture and a gated metric (`nudge.queriesPerFocusDay ≤ 5`). Five is
    /// chosen so a mid-day priority change still buys the new commitment a question or two.
    public static let dailyQueryCapAllPriorities = 5

    /// **B.** Accusations per local day. Boundary triple 5 / 6 / 7. Six accusations at
    /// `RelevancePolicy.mandateCooldown` (600 s) is one per hour across a six-hour focus day.
    public static let dailyAccusationCap = 6

    /// **B.** The **shared** interruption budget: questions and accusations together, per
    /// local day. Boundary triple 7 / 8 / 9.
    ///
    /// Deliberately **less than** `dailyQueryCap + dailyAccusationCap`. The two budgets must
    /// genuinely compete, or "shared" is a word with no consequence — and a person asked ten
    /// questions has been interrupted ten times, whatever the app calls them.
    public static let dailyInterruptionCap = 8

    /// **S.** Units of the shared budget a question may never spend.
    ///
    /// **A query never spends the last unit.** Running out of budget on questions and therefore
    /// being unable to say "you are off task" is the failure that defeats the product. An
    /// ordering invariant rather than a boundary triple: with one unit left and both offered,
    /// the accusation takes it.
    public static let reservedAccusationUnits = 1

    // MARK: - Structural sets (R-87, F-61, F-64, D-06, R-85)

    /// **S.** F-61's own three snooze spans, shortest first. A snooze is subject-scoped, in
    /// memory, and shows a countdown in the menu bar; it is never a global mute.
    public static let snoozeDurations: [Duration] = [.seconds(300), .seconds(600), .seconds(900)]

    /// **S.** F-64's own three pause presets, in the order a surface offers them.
    public static let pauseDurations: [PausePreset] = [
        .fixed(.seconds(900)), .untilTime, .restOfDay
    ]

    /// **S.** The ladder is two rungs, no more and no fewer — D-06 as amended by U-2.
    ///
    /// D-06 ruled three stages and e05 shipped three. The user amended it: the ambient glyph and a
    /// single panel nudge ship; the third rung, explicit recommitment, is deferred to focus-5ab to
    /// be designed cleanly rather than repaired. The number is **amended rather than evaded** —
    /// this is still a lint, `LadderVocabularyTests` still asserts it equals
    /// `LadderRung.Kind.allCases.count`, and `nudge.ladderRungsDeclared == 2` still asserts the
    /// same fact as a number in the evaluation report. Adding or losing a rung by accident is a
    /// red run exactly as it was before; what changed is which number is right.
    public static let ladderRungCount = 2

    /// **S.** R-85: the shipped default is **off**, with no bundled window.
    ///
    /// A default of "22:00–08:00" would be the app making a claim about a person's life it has
    /// no evidence for, and the product boundary is that the priority outranks the app's
    /// opinions. Quiet hours are also **not** the system Focus: P-137 measured that
    /// `~/Library/DoNotDisturb/DB/Assertions.json` does not exist on this machine and
    /// `ModeConfigurations.json` is unreadable, and standing condition 8 forbids the private
    /// route — so the app makes no claim to read it.
    public static let quietHoursDefault: QuietHoursWindow? = nil

    /// **C.** The query ledger's rows die with their priority (F-115/F-116) and with nothing
    /// else, so what this constant owes is a purge-completeness test rather than a latency
    /// figure.
    public static let queryLedgerRetention: NudgeRetentionRule = .withPriority

    // MARK: - The manifest, the digest and the version

    /// Every constant above, in **declaration order**, with its class and its evidence.
    ///
    /// Declaration order is load-bearing: the digest is computed over this sequence, so
    /// re-ordering the manifest changes the digest and fails the suite — which is correct,
    /// because the manifest is what a reviewer reads to check that the file and the evidence
    /// agree.
    ///
    /// The witness ids are allocated **here, before the fixtures exist**, because a witness
    /// chosen after the fact is a witness chosen to pass. T143 creates cases and sequences with
    /// exactly these ids and exactly the shapes the comments below describe.
    public static let manifest: [PolicyConstant] = [
        PolicyConstant(
            name: "queryDwellThreshold",
            kind: .behavioural,
            encoded: encoded(queryDwellThreshold),
            justification: "R-95, relation: × 2 == RelevancePolicy.sustainedDriftThreshold",
            // A case dwelling 44 s on an askable uncertain subject, which must NOT ask. At 44
            // it asks a person about an application they have had open for less than a minute.
            witnesses: ["gc-0501"],
            mutations: ["44", "46"]
        ),
        PolicyConstant(
            name: "queryCooldown",
            kind: .behavioural,
            encoded: encoded(queryCooldown),
            justification: "R-95, relation: == RelevancePolicy.lookBackSpan; P-82",
            // The four-application tab-hop: one question at 180, four at 0.
            witnesses: ["seq-0019"],
            mutations: ["179", "181"]
        ),
        PolicyConstant(
            name: "ignoredQueryBackoff",
            kind: .behavioural,
            encoded: "\(ignoredQueryBackoff)",
            justification: "R-83",
            // Two questions declined in a row, then silence for backoffSpan.
            witnesses: ["seq-0022"],
            mutations: ["1", "3"]
        ),
        PolicyConstant(
            name: "ignoredAccusationBackoff",
            kind: .behavioural,
            encoded: "\(ignoredAccusationBackoff)",
            justification: "R-83, F-63",
            // Two delivered rungs ignored, then the ladder holds at `.ambient`. It said three
            // against a constant of 2; the note at the declaration above is explicit that
            // seq-0023 "reaches the ladder's own hold in two".
            witnesses: ["seq-0023"],
            mutations: ["2", "4"]
        ),
        PolicyConstant(
            name: "backoffSpan",
            kind: .behavioural,
            encoded: encoded(backoffSpan),
            justification: "R-83",
            // seq-0022 asks two questions, is declined twice, is refused while the hour runs and
            // asks again exactly an hour later. The accusation hold's half is driven in
            // `FatigueControllerTests.theAccusationHoldExpires`, which folds the reducer's own
            // events across the boundary.
            witnesses: ["seq-0022"],
            mutations: ["3599", "3601"]
        ),
        PolicyConstant(
            name: "dailyQueryCap",
            kind: .behavioural,
            encoded: "\(dailyQueryCap)",
            justification: "P-138",
            // The nine-askable-subject priority: four questions on day one, four on day two.
            witnesses: ["seq-0020"],
            mutations: ["3", "5"]
        ),
        PolicyConstant(
            name: "dailyQueryCapAllPriorities",
            kind: .behavioural,
            encoded: "\(dailyQueryCapAllPriorities)",
            justification: "R-83, adversarial review finding 2",
            // The three-priority working day. Without this cap the same day licenses twelve
            // questions, bounded only by the shared budget at seven.
            witnesses: ["day-01"],
            mutations: ["4", "6"]
        ),
        PolicyConstant(
            name: "dailyAccusationCap",
            kind: .behavioural,
            encoded: "\(dailyAccusationCap)",
            justification: "R-83",
            witnesses: ["seq-0021"],
            mutations: ["5", "7"]
        ),
        PolicyConstant(
            name: "dailyInterruptionCap",
            kind: .behavioural,
            encoded: "\(dailyInterruptionCap)",
            justification: "R-83",
            // Four questions and six accusations offered in one day; eight delivered.
            witnesses: ["seq-0021"],
            mutations: ["7", "9"]
        ),
        PolicyConstant(
            name: "reservedAccusationUnits",
            kind: .structural,
            encoded: "\(reservedAccusationUnits)",
            justification: "R-83"
        ),
        PolicyConstant(
            name: "snoozeDurations",
            kind: .structural,
            encoded: snoozeDurations.map(encoded).joined(separator: ","),
            justification: "F-61"
        ),
        PolicyConstant(
            name: "pauseDurations",
            kind: .structural,
            encoded: pauseDurations.map(\.encoded).joined(separator: ","),
            justification: "F-64"
        ),
        PolicyConstant(
            name: "ladderRungCount",
            kind: .structural,
            encoded: "\(ladderRungCount)",
            justification: "D-06 as amended by U-2"
        ),
        PolicyConstant(
            name: "quietHoursDefault",
            kind: .structural,
            encoded: quietHoursDefault?.encoded ?? "none",
            justification: "R-85, P-137"
        ),
        PolicyConstant(
            name: "queryLedgerRetention",
            kind: .capacity,
            encoded: queryLedgerRetention.rawValue,
            justification: "F-115, F-116"
        )
    ]

    /// Seconds, as the digest sees a `Duration`. Sub-second components are never used by any
    /// constant in this file and would be a threshold nobody could feel.
    static func encoded(_ span: Duration) -> String {
        "\(span.components.seconds)"
    }

    /// The canonical encoding the digest is taken over: `name=value`, in declaration order,
    /// joined with `;` — byte-identical to `RelevancePolicy`'s, so one reader understands both.
    public static var canonicalEncoding: String {
        manifest.map { "\($0.name)=\($0.encoded)" }.joined(separator: ";")
    }

    /// FNV-1a over `canonicalEncoding`, never `Hasher` (P-118: `Hasher` is seeded per process
    /// and produced two different values for identical data). Asserted against a committed
    /// literal in `InterventionPolicyTests`.
    public static var digest: UInt64 { FNV1a.hash(canonicalEncoding) }

    /// `0x…`, sixteen lowercase hex digits — the form every committed digest literal takes.
    public static var digestHex: String { FNV1a.hex(digest) }

    /// Every revision of this constant set, oldest first. **The list is the version.**
    ///
    /// Adding a row is the deliberate act that re-records `InterventionPolicyTests`'
    /// committed digest alongside it, and the row says what moved — which is what a reader of
    /// an intervention digest six months from now actually needs.
    public static let revisions: [String] = [
        "T113 — the fifteen constants of R-95's table, digested and classed B/C/S, in the "
            + "nudge's own manifest so that a cooldown cannot invalidate a verdict cache",
        "U-2 — ladderRungCount 3 -> 2 and ignoredAccusationBackoff 3 -> 2. D-06's third rung, "
            + "explicit recommitment, is deferred to epic focus-5ab and removed from the shipping "
            + "product; the ladder is the ambient glyph and a single panel nudge. The backoff "
            + "moved with it. NOTE (focus-yxb): the reason recorded here for the backoff was "
            + "false — 'candidate(...) answers nil at the top rung so a backoff of 3 could never "
            + "trip' is true of LadderMachine, whose run resets with the drift subject, and false "
            + "of FatigueController, whose run is session-wide and would have reached 3 on a "
            + "third subject. Measured: the hold trips on the second dismissal of a session. The "
            + "value is unchanged and the digest with it; only the claim about it is corrected",
        "focus-845 — queryBackoffSpan renamed backoffSpan, and the accusation hold now uses it. "
            + "The value is unchanged at 3600 s; what changed is that a second consumer reads it. "
            + "ignoredAccusationBackoff tripped a Bool that only sessionEnded could clear, so two "
            + "dismissals held the ladder at the ambient rung for the rest of the session — and "
            + "since U-2 the panel is the only rung that says anything, so that muted the product "
            + "with no expiry, asymmetrically with its own twin ignoredQueryBackoff, which trips "
            + "at the same count of 2 and is bounded to an hour. One span, two backoffs: a "
            + "backoff this app imposes lasts an hour, whichever kind tripped it"
    ]

    /// `EngineStamp.interventionVersion`'s value: the count of `revisions`, so a version that
    /// changed without a reason is unrepresentable.
    public static var version: Int { revisions.count }
}
