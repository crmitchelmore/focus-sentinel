import FocusCore
import Foundation

/// One classification, whole: what the engine concluded, why, whether it may say anything, and
/// where the drift clock stands.
///
/// Everything a surface needs and nothing it does not. The mandate this value carries is what
/// e05's ladder climbs, and the same value is what the Privacy pane's verdict inspector draws:
/// one judgement, read by the surface that acts on it and by the surface that explains it.
public struct Judgement: Sendable, Equatable {
    public let outcome: ClassificationOutcome
    public let explanation: Explanation
    public let eligibility: InterventionEligibility
    /// The drift state the eligibility was decided from — **before** a mandate moved the
    /// machine into cooldown, so a surface draws the reading the decision was made on rather
    /// than its consequence.
    public let drift: DriftState
    public let stage: CascadeStage
    /// Executable rungs consulted, `1…8`.
    public let consultedDepth: Int
    public let uncertaintyReason: UncertaintyReason?
    public let status: FocusStatus

    public var verdict: Verdict { outcome.verdict }

    /// The value the verdict inspector draws (R-71).
    ///
    /// The band is `nil` when the verdict is `uncertain`: declining to decide has no evidence
    /// to band, and drawing `.low` there would imply a weak *decision* rather than the absence
    /// of one.
    public func verdictSnapshot(stampKey: String) -> VerdictSnapshot {
        VerdictSnapshot(
            status: status,
            stage: stage,
            band: outcome.verdict == .uncertain ? nil : outcome.band,
            drift: drift,
            eligibility: eligibility,
            explanation: explanation,
            stampKey: stampKey
        )
    }
}

/// **The engine.** Rule-first, deterministic, and complete before any model exists.
///
/// It composes the six pieces this phase built — the normaliser, the similarity scorer, the
/// cascade, the heuristic rung, the drift machine and the transition window — and satisfies the
/// `RelevanceClassifier` seam e01 shipped. That ordering is the point: the heuristic layer is
/// the *whole* engine here, which is what makes the charter's *"fallback ALWAYS present and
/// independently tested"* clause temporally true rather than a promise made about a later epic.
///
/// ## What it refuses
///
/// Two refusals, both before any rung is consulted, and both answering `uncertain` rather than
/// guessing:
///
/// * **A snapshot built under a different policy.** The thresholds that produced its priority
///   tokens are not the ones about to be applied to them.
/// * **A snapshot describing a different priority revision.** An edited priority is a different
///   priority, and every judgement about the old wording is stale — the corpus half of F-53's
///   cache-key contract.
///
/// ## Warm-up is not on this path
///
/// P-116 measured the sentence embedding's cold load at **59.4 ms**. `warmUp()` pays it at
/// construction, called by the composition root, because a stutter that long inside a nudge
/// decision is a defect a person can feel. Nothing here loads it lazily on the classification
/// path.
///
/// A `final class` rather than a value type because the drift machine and the transition window
/// are state that successive classifications share. There is **no timer, no queue and no task**
/// in it (R-70e): the lock is held across a reduce and a record and nothing else.
public final class DeterministicRelevanceEngine: RelevanceClassifier, @unchecked Sendable {
    private let normalizer: TokenNormalizer
    private let scorer: SimilarityScorer
    private let cascade: RuleCascade
    private let explanations = ExplanationBuilder()

    private let lock = NSLock()
    private var drift = DriftMachine()
    private var window: TransitionWindow

    /// How many observations the look-back keeps.
    ///
    /// `RelevancePolicy.maximumLookBackEvents` in every shipping path, and the only reason it is
    /// a parameter at all is R-74.4: `maximumLookBackEvents` is class **C** and owes evidence
    /// that the bound is *sufficient* rather than merely present, which means replaying the
    /// committed sequences against an engine that keeps everything and showing the transcript
    /// does not move.
    private let lookBackCapacity: Int

    /// e06's port, or `nil`. Held so that `reset()` can clear what the model knows: a session
    /// ending, or a priority changing, makes every earlier model answer evidence about a
    /// different question (R-105).
    private let model: (any ModelRung)?

    /// **The composition seam e06 needed and e04 did not leave.**
    ///
    /// This initialiser used to build its `RuleCascade` internally, which meant there was no
    /// way to hand the engine a ladder or a port — the adversarial review found it, and
    /// T-e06-11 depends on it. The default arguments are exactly what e05 shipped: no model, the
    /// deterministic ladder, and a cascade built the same way it always was. A caller who passes
    /// nothing gets the engine that has been measured over 202 corpus cases.
    public init(
        normalizer: TokenNormalizer = TokenNormalizer(),
        scorer: SimilarityScorer = SimilarityScorer(),
        lookBackCapacity: Int = RelevancePolicy.maximumLookBackEvents,
        model: (any ModelRung)? = nil,
        ladder: CascadeLadder = .deterministic
    ) {
        self.normalizer = normalizer
        self.scorer = scorer
        self.lookBackCapacity = lookBackCapacity
        self.model = model
        self.window = TransitionWindow(capacity: lookBackCapacity)
        self.cascade = RuleCascade(
            heuristic: HeuristicClassifier(scorer: scorer),
            model: model,
            ladder: ladder,
            normalizer: normalizer
        )
    }

    /// The ladder this engine composed, for the report and the self-check to read rather than
    /// infer. Eight rungs with no port, nine with one.
    public var ladder: CascadeLadder { cascade.composedLadder }

    /// Pay every cold cost at construction, off the classification path. Idempotent.
    ///
    /// Two of them, and the second was found by measurement rather than reasoning. The
    /// embedding's load is P-116's 59.4 ms and was always the point of this method. The
    /// normaliser's is `NaturalLanguage` initialising its tagger models the first time it is
    /// asked to work — one-time, process-wide, and worth 57 ms on a classification that happens
    /// to be the first of its kind. The golden corpus's maximum classification latency falls
    /// from 61 ms to 3.1 ms when both are warmed here instead of one, which is the difference
    /// between a stutter a person feels on their first activation and one that never happens.
    public func warmUp() {
        normalizer.warmUp()
        scorer.warmUp()
    }

    /// This build's stamp, with the OS-supplied sentence-embedding revision filled in.
    ///
    /// `embeddingRevision` is the one component no amount of discipline could supply: if Apple
    /// ships a new asset in a point release every distance the engine computes changes, and a
    /// cache keyed only on our own edits would serve stale verdicts for ever (P-117, R-63).
    public var stamp: EngineStamp {
        EngineStamp.current.withEmbeddingRevision(
            scorer.isAvailable ? scorer.embeddingRevision : 0
        )
    }

    /// What the LRU did, for `evaluation.json`'s `cache` block.
    public var cacheStatistics: SimilarityCacheStatistics { scorer.statistics }

    /// The drift state, for a surface that wants to draw the clock between activations.
    public var driftState: DriftState {
        lock.lock()
        defer { lock.unlock() }
        return drift.state
    }

    /// Forget the clock. Called when the session ends or the priority changes, both of which
    /// make every earlier observation evidence about a different question.
    public func reset() {
        lock.lock()
        drift = DriftMachine()
        window.reset()
        lock.unlock()
        // R-105's second invalidation, outside this engine's lock because the rung holds its
        // own. Model silence is not consent to anything and must not outlive the session that
        // produced it.
        model?.reset()
    }

    /// R-105's third invalidation: a rule the person wrote about a subject.
    ///
    /// That rule outranks rank 6 anyway — rungs 0–2 answer before the heuristic is reached — so
    /// dropping the entry changes no verdict. What it changes is the inspector: without this it
    /// could show a stale model rationale beside a rule that already decided the question.
    public func forgetModelAnswers(about subject: String) {
        model?.invalidate(subject: subject)
    }

    // MARK: - The seam e01 shipped

    /// The degraded answer.
    ///
    /// A `ClassificationInput` carries no priority revision, no rules and no context pack, so
    /// there is nothing to judge it against: this returns `.undecided`, which suppresses. The
    /// engine's real entry point is `judge(…)`, which takes a snapshot — and the reason the
    /// protocol keeps this shape is that e01's call sites and tests were written against it and
    /// e06's model will answer through the same seam.
    public func classify(_ input: ClassificationInput) -> ClassificationOutcome {
        _ = input
        return .undecided
    }

    // MARK: - The real entry point

    public func judge(
        input: ClassificationInput,
        snapshot: RuleSnapshot,
        evidenceRevision: Int? = nil,
        now: Duration,
        dwell: Duration,
        phase: SessionPhase = .focus,
        status: FocusStatus? = nil,
        isUserIdle: Bool = false
    ) -> Judgement {
        let stamp = self.stamp

        // The two refusals. Both answer `uncertain`, which suppresses, and both name their own
        // route so the metric can tell them apart from an ordinary decline.
        if !snapshot.matchesRunningPolicy
            || !snapshot.describes(revision: evidenceRevision ?? snapshot.priorityRevision) {
            return stale(snapshot: snapshot, phase: phase, status: status, stamp: stamp)
        }

        let evidence = ClassificationEvidence.make(
            input: input, dwell: dwell, normalizer: normalizer
        )
        let resolution = cascade.evaluate(evidence: evidence, snapshot: snapshot)

        lock.lock()
        // The threshold is read **before** this observation is recorded, so an activation can
        // never be its own return anchor (R-61).
        let observation = DriftObservation(
            now: now,
            verdict: resolution.verdict,
            subject: evidence.subject,
            isUserIdle: isUserIdle,
            phase: phase,
            effectiveThreshold: window.effectiveThreshold(at: now)
        )
        let anchorToken = window.anchorToken(at: now)
        let mixedSubjects = window.distinctUnrelatedSubjects
        let driftState = drift.reduce(observation)
        window.record(observation)
        lock.unlock()

        let explanation = explanations.build(
            resolution: resolution,
            drift: driftState,
            anchor: anchorToken,
            mixedSubjectCount: mixedSubjects,
            stamp: stamp
        )

        let resolvedStatus = status ?? Self.status(for: resolution.verdict, phase: phase)
        let eligibility = InterventionEligibility.decide(
            outcome: resolution.outcome,
            drift: driftState,
            phase: phase,
            status: resolvedStatus,
            isUserIdle: isUserIdle,
            hasActivePriority: snapshot.hasActivePriority,
            explanation: explanation,
            stamp: stamp
        )

        // One mandate per subject per `mandateCooldown`, from the engine. e05's ladder has its
        // own proportionality on top of this.
        if eligibility.isMandated {
            lock.lock()
            drift.recordMandate(at: now)
            lock.unlock()
        }

        return Judgement(
            outcome: resolution.outcome,
            explanation: explanation,
            eligibility: eligibility,
            drift: driftState,
            stage: resolution.stage,
            consultedDepth: resolution.consultedDepth,
            uncertaintyReason: resolution.uncertaintyReason,
            status: resolvedStatus
        )
    }

    /// The refusal, as a whole judgement.
    ///
    /// It does not touch the drift machine at all: a stale snapshot is not an observation about
    /// the person, and folding one in would let a cache miss move a clock that is about their
    /// afternoon.
    func stale(
        snapshot: RuleSnapshot,
        phase: SessionPhase,
        status: FocusStatus?,
        stamp: EngineStamp
    ) -> Judgement {
        let resolution = CascadeResolution(
            stage: .unresolved,
            verdict: .uncertain,
            source: .undecided,
            band: .low,
            clauses: [.insufficientEvidence(reason: .staleSnapshot)],
            uncertaintyReason: .staleSnapshot,
            consultedDepth: CascadePrecedence.executableRungs.count
        )
        let explanation = explanations.build(
            resolution: resolution, drift: driftState, stamp: stamp
        )
        let resolvedStatus = status ?? Self.status(for: .uncertain, phase: phase)

        return Judgement(
            outcome: resolution.outcome,
            explanation: explanation,
            eligibility: InterventionEligibility.decide(
                outcome: resolution.outcome,
                drift: driftState,
                phase: phase,
                status: resolvedStatus,
                isUserIdle: false,
                hasActivePriority: snapshot.hasActivePriority,
                explanation: explanation,
                stamp: stamp
            ),
            drift: driftState,
            stage: resolution.stage,
            consultedDepth: resolution.consultedDepth,
            uncertaintyReason: .staleSnapshot,
            status: resolvedStatus
        )
    }

    /// The five-case surface vocabulary, from the three-case verdict and the session's phase.
    ///
    /// `FocusStatus` is a superset of `Verdict` by exactly the two states a verdict cannot
    /// describe — paused and on a break — and those come from the session rather than from
    /// anything on screen. A caller that knows better may pass its own; the corpus does, so a
    /// fixture can hold the status still while it varies everything else.
    static func status(for verdict: Verdict, phase: SessionPhase) -> FocusStatus {
        switch phase {
        case .paused, .interrupted, .complete: return .paused
        case .onBreak: return .onBreak
        case .focus, .intentionalDetour: break
        }
        switch verdict {
        case .relevant: return .relevant
        case .unrelated: return .unrelated
        case .uncertain: return .uncertain
        }
    }
}
