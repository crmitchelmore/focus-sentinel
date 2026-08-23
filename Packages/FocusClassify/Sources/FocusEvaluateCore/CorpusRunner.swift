import FocusClassify
import FocusCore
import FocusRules
import Foundation

/// What the engine actually did with one case, in the same vocabulary the expectation is
/// written in — so a failure prints two comparable lines rather than a stack trace.
public struct CorpusOutcome: Sendable, Equatable {
    public let verdict: Verdict
    public let source: VerdictSource
    public let stage: CascadeStage
    public let band: EvidenceBand?
    public let eligibility: CorpusEligibility
    public let clauses: Set<ExplanationClauseKind>
    public let uncertaintyReason: UncertaintyReason?
    public let skippedRuleCount: Int
    /// Executable rungs consulted before a decision, `1…8` (R-54).
    public let consultedDepth: Int
    public let drift: DriftState
    /// One sample per `judge` call, in call order. Fixture loading and snapshot construction
    /// are excluded: R-65 pays the priority-side sentence vector once per revision, not per
    /// activation, and charging it to a classification would measure the wrong thing.
    public let latencies: [Duration]

    public var isMandated: Bool { eligibility == .mandated }

    /// The expectation this run would satisfy, for a failure message that says what to write
    /// rather than only what was wrong.
    public var asExpectation: CorpusExpectation {
        CorpusExpectation(
            verdict: verdict,
            source: source,
            stage: stage,
            band: band,
            eligibility: eligibility,
            clauses: clauses,
            uncertaintyReason: uncertaintyReason
        )
    }
}

/// How one case differs from what it promised. Empty means it passed.
public struct CorpusMismatch: Sendable, Equatable {
    public let id: String
    public let file: String
    public let note: String
    public let differences: [String]

    public var description: String {
        "\(file)/\(id): \(differences.joined(separator: "; "))  — \(note)"
    }
}

/// Runs one committed case through the real engine.
///
/// ## The two-observation protocol, and why a single call would not do
///
/// A single-shot fixture carries a `dwellSeconds`, and dwell is the *only* thing that can turn
/// a verdict of `unrelated` into a mandate. But the drift machine is a reducer over an
/// activation stream: an activation says *"at time t, subject S is frontmost"*, and the interval
/// that just elapsed was spent under the **previous** observation's verdict. One call therefore
/// can never accumulate anything — it opens a grace period and stops — so a corpus run built on
/// a single call could not express `.mandated` at all, and `missRate` would have an empty
/// denominator.
///
/// So a case's claim is read as *"this subject has held for `dwellSeconds`, and still is"*, and
/// it is fed twice against the same evidence and the same dwell: once at `t = 0` and once at
/// `t = dwellSeconds`. The two readings then agree — the heuristic's own dwell gate and the
/// drift accumulator both see `dwellSeconds`, rather than the accumulator seeing an interval the
/// fixture never claimed. The **second** judgement is the one asserted; both are timed, because
/// both are real classifications.
///
/// The alternative — a first call at zero dwell — was tried and is wrong for a reason worth
/// recording: at zero dwell the heuristic answers `uncertain(.noEvidence)`, an `uncertain`
/// observation **freezes** the accumulator (R-60 ruling 3), and the interval would be credited
/// to nothing. A fixture claiming ninety-one seconds of drift would then report a grace period,
/// and every temporal boundary in the corpus would sit in the wrong place.
///
/// ## One scorer, many engines
///
/// The engine is fresh per case — a drift accumulator carried between fixtures would make every
/// case depend on the one before it, and the corpus would stop being a set of independent
/// claims. The **scorer** is shared, because it is long-lived in production too: its bounded LRU
/// is the thing R-74.4's benchmark measures, and giving each case its own would report a hit
/// rate of zero about a cache that does not exist.
public struct CorpusRunner: Sendable {
    public let normalizer: TokenNormalizer
    public let scorer: SimilarityScorer

    /// A fixed wall-clock origin, so rule ordering is deterministic across runs and processes.
    /// Rules are sorted by `(authority, subjectKind, createdAt, id)`, and a `Date()` here would
    /// make that sort — and therefore the snapshot's equality — depend on when the suite ran.
    public static let ruleEpoch = Date(
        timeIntervalSince1970: EvaluationPolicy.ruleEpochSecondsSince1970
    )

    public init(normalizer: TokenNormalizer = TokenNormalizer(), scorer: SimilarityScorer) {
        self.normalizer = normalizer
        self.scorer = scorer
    }

    // MARK: - Building the snapshot

    /// A stable identity derived from a string.
    ///
    /// Derived rather than allocated, because a `UUID()` would make the snapshot differ between
    /// runs and R-69's byte-identical-transcript assertion is the whole reason the corpus is
    /// worth committing at all. Two FNV-1a digests over two salted forms of the name fill the
    /// sixteen bytes — FNV-1a and never `Hasher`, which P-118 measured returning a different
    /// value in every process.
    public static func stableID(for name: String) -> UUID {
        var bytes: [UInt8] = []
        for digest in [FNV1a.hash("\(name)|high"), FNV1a.hash("\(name)|low")] {
            var remaining = digest
            for _ in 0..<MemoryLayout<UInt64>.size {
                bytes.append(UInt8(truncatingIfNeeded: remaining))
                remaining >>= UInt64(UInt8.bitWidth)
            }
        }
        return bytes.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
    }

    public func snapshot(for testCase: CorpusCase) -> RuleSnapshot {
        let priority = testCase.priority.map {
            PriorityInput(
                id: Self.stableID(for: testCase.id),
                revision: $0.revision,
                intent: $0.intent,
                doneWhen: $0.doneWhen
            )
        }

        var sessionRules: [ScopedRuleValue] = []
        var storedRules: [StoredRuleRow] = []

        for (index, rule) in testCase.rules.enumerated() {
            let createdAt = Self.ruleEpoch.addingTimeInterval(Double(index))
            let id = Self.stableID(for: "\(testCase.id)|rule|\(index)")
            switch rule.authority {
            case .session:
                sessionRules.append(
                    ScopedRuleValue(
                        id: id,
                        authority: .session,
                        subjectKind: rule.subjectKind,
                        subject: rule.subject,
                        verdict: rule.verdict,
                        createdAt: createdAt
                    )
                )
            case .task, .global:
                storedRules.append(
                    StoredRuleRow(
                        rule: RelevanceRuleValue(
                            id: id,
                            scope: Self.scope(for: rule.subjectKind),
                            subject: rule.subject,
                            verdict: Self.storedVerdict(for: rule.verdict),
                            createdAt: createdAt
                        ),
                        isTaskScoped: rule.authority == .task
                    )
                )
            }
        }

        // The legacy shape, planted deliberately (R-72.3). A fixture that constructs the
        // ambiguous row in order to prove it reaches no rung is the opposite of a violation —
        // the same reason `Packages/FocusRules/Tests` and `Packages/FocusClassify/Tests` are on
        // lint R-70n's allow-list, applied to the test-lane library that both of them and the
        // `FocusEvaluate` product now share.
        for (index, row) in testCase.legacySessionScopedRows.enumerated() {
            storedRules.append(
                StoredRuleRow(
                    rule: RelevanceRuleValue(
                        id: Self.stableID(for: "\(testCase.id)|legacy|\(index)"),
                        scope: RuleScope.session,
                        subject: row.subject,
                        verdict: Self.storedVerdict(for: row.verdict),
                        createdAt: Self.ruleEpoch.addingTimeInterval(Double(index))
                    ),
                    isTaskScoped: false
                )
            )
        }

        let contextPack = testCase.contextPack.enumerated().map { index, item in
            ContextItemValue(
                id: Self.stableID(for: "\(testCase.id)|context|\(index)"),
                kind: item.kind,
                value: item.value,
                displayName: item.value,
                addedAt: Self.ruleEpoch.addingTimeInterval(Double(index))
            )
        }

        return RuleSnapshotBuilder(normalizer: normalizer, scorer: scorer).build(
            priority: priority,
            storedRules: storedRules,
            sessionRules: sessionRules,
            contextPack: contextPack
        )
    }

    static func scope(for kind: RuleSubjectKind) -> RuleScope {
        switch kind {
        case .app: .app
        case .domain: .domain
        case .titleToken: .titleToken
        }
    }

    static func storedVerdict(for verdict: PriorityRuleVerdict) -> RuleVerdict {
        switch verdict {
        case .relevant: .relevant
        case .unrelated: .unrelated
        case .uncertain: .uncertain
        }
    }

    // MARK: - Running

    public func run(_ testCase: CorpusCase) -> CorpusOutcome {
        let snapshot = snapshot(for: testCase)
        let engine = DeterministicRelevanceEngine(normalizer: normalizer, scorer: scorer)
        let input = ClassificationInput(
            priorityIntent: testCase.priority?.intent ?? "",
            priorityDoneWhen: testCase.priority?.doneWhen,
            bundleIdentifier: testCase.evidence.bundleIdentifier,
            origin: testCase.evidence.origin,
            titleTokens: testCase.evidence.titleTokens
        )

        var latencies: [Duration] = []
        let clock = ContinuousClock()

        func judge(now: Duration, dwell: Duration) -> Judgement {
            let started = clock.now
            let judgement = engine.judge(
                input: input,
                snapshot: snapshot,
                evidenceRevision: testCase.evidenceRevision,
                now: now,
                dwell: dwell,
                phase: testCase.sessionPhase,
                status: testCase.focusStatus,
                isUserIdle: testCase.isUserIdle
            )
            latencies.append(clock.now - started)
            return judgement
        }

        let dwell = Duration.seconds(testCase.dwellSeconds)
        _ = judge(now: .zero, dwell: dwell)
        let judgement = judge(now: dwell, dwell: dwell)

        return CorpusOutcome(
            verdict: judgement.verdict,
            source: judgement.outcome.source,
            stage: judgement.stage,
            band: judgement.verdict == .uncertain ? nil : judgement.outcome.band,
            eligibility: judgement.eligibility.isMandated
                ? .mandated
                : .suppressed(judgement.eligibility.suppressionReason ?? .verdictUncertain),
            clauses: Set(judgement.explanation.clauseKinds),
            uncertaintyReason: judgement.uncertaintyReason,
            skippedRuleCount: snapshot.skippedRuleCount,
            consultedDepth: judgement.consultedDepth,
            drift: judgement.drift,
            latencies: latencies
        )
    }

    // MARK: - Comparing

    /// Every way the run differed from the promise, named one by one.
    public func compare(_ testCase: CorpusCase, to outcome: CorpusOutcome) -> CorpusMismatch? {
        var differences: [String] = []
        let expect = testCase.expect

        if outcome.verdict != expect.verdict {
            differences.append("verdict \(outcome.verdict.rawValue) ≠ \(expect.verdict.rawValue)")
        }
        if outcome.source != expect.source {
            differences.append("source \(outcome.source.rawValue) ≠ \(expect.source.rawValue)")
        }
        if outcome.stage != expect.stage {
            differences.append("stage \(outcome.stage.rawValue) ≠ \(expect.stage.rawValue)")
        }
        if outcome.band != expect.band {
            differences.append(
                "band \(outcome.band?.rawValue ?? "null") ≠ \(expect.band?.rawValue ?? "null")"
            )
        }
        if outcome.eligibility != expect.eligibility {
            differences.append(
                "eligibility \(outcome.eligibility.encoded) ≠ \(expect.eligibility.encoded)"
            )
        }
        if outcome.clauses != expect.clauses {
            differences.append(
                "clauses [\(outcome.clauses.map(\.rawValue).sorted().joined(separator: " "))]"
                    + " ≠ [\(expect.clauses.map(\.rawValue).sorted().joined(separator: " "))]"
            )
        }
        if outcome.uncertaintyReason != expect.uncertaintyReason {
            differences.append(
                "uncertaintyReason \(outcome.uncertaintyReason?.rawValue ?? "null")"
                    + " ≠ \(expect.uncertaintyReason?.rawValue ?? "null")"
            )
        }
        if outcome.skippedRuleCount != testCase.expectSkippedRuleCount {
            differences.append(
                "skippedRuleCount \(outcome.skippedRuleCount) ≠ \(testCase.expectSkippedRuleCount)"
            )
        }

        guard !differences.isEmpty else { return nil }
        return CorpusMismatch(
            id: testCase.id,
            file: testCase.file,
            note: testCase.note,
            differences: differences
        )
    }
}
