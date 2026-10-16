import FocusCore
import Foundation

/// What the model is asked about — **one priority, one subject, and nothing else.**
///
/// No window title, no full URL, no file path, no document name: there are none at zero grants,
/// and when e07 supplies them, sending captured prose to a model is a new data flow that needs
/// its own ruling. The type is what makes that a boundary rather than a promise — every field
/// here is either a normalised identity the person can see in their own context pack, or prose
/// they themselves typed into the priority.
///
/// `cacheKey` is `EngineStamp.verdictCacheKey(priorityID:priorityRevision:evidenceKey:)` folded
/// together with the OS version string, which is R-104's fallback for a model identity the
/// system does not publish. Coarse in the safe direction: a point release that ships a new
/// asset invalidates every entry, and one that does not costs a session's worth of re-asking.
///
/// **Neither textual field is a `String`.** `RuleSnapshot` does not carry the priority's raw
/// prose — only its normalised tokens — and `NormalisedToken` has no public initialiser and
/// rejects anything that is not a single token (R-57). So a window title, a full URL, a
/// document name or a file path cannot reach a prompt by any route: it is not forbidden, it is
/// unrepresentable, which is the same technique `ExplanationClause` uses at the other end of
/// the pipeline. R-116 asks for exactly this — *"the prompt builder is typed so that it cannot
/// accept a bare `String` from outside `ClassificationEvidence`"*.
public struct ModelRequest: Sendable, Equatable, Hashable {
    /// The whole cache key, computed by the caller so this type carries no policy.
    public let cacheKey: String
    /// The priority's own words, normalised — the same tokens every other rung compares.
    public let priorityTokens: [NormalisedToken]
    /// The bundle identifier or normalised origin in front of them.
    public let subject: NormalisedToken
    /// `FocusSchemaV3.PriorityTask.revision`. An edited priority is a different question.
    public let priorityRevision: Int

    public init(
        cacheKey: String,
        priorityTokens: [NormalisedToken],
        subject: NormalisedToken,
        priorityRevision: Int
    ) {
        self.cacheKey = cacheKey
        self.priorityTokens = priorityTokens
        self.subject = subject
        self.priorityRevision = priorityRevision
    }
}

/// How the model says the subject relates to the work.
///
/// Two cases rather than one because F-50's entire user-visible payoff is the difference:
/// *"reading documentation — supporting your task"* is a more trustworthy sentence than *"this
/// is your task"*, and a person who disagrees with it knows exactly which claim to correct.
public enum ModelRelevance: String, Sendable, CaseIterable, Codable, Hashable {
    /// The subject **is** the work.
    case direct
    /// The subject is in service of the work — documentation, a reference, a tool.
    case supporting
}

/// Why the model did not rescue this case. Every one of these is silence, never an accusation.
public enum ModelDeclineReason: String, Sendable, CaseIterable, Codable, Hashable {
    /// The model's own `unrelated` label. **It maps here and only here**, and what it produces
    /// is a decline: the deterministic `uncertain` stands, the app asks its question, and the
    /// person answers it. R-117c lints that `Verdict.unrelated` is not constructible in
    /// `FocusModel` at all.
    case modelSaidUnrelated
    /// The model's own `unsure` label.
    case modelSaidUncertain
    /// The tier is not composed, the resource gate closed, or the judge could not be reached
    /// (a remote judge offline, timed out or rate-limited). **Never cached**: it says nothing
    /// about the window, so `FocusModelRung` asks again at the next judgement.
    case notAvailable
    /// The session refused, threw, or produced something the schema could not hold.
    ///
    /// **A timeout is one of these and does not have a case of its own.** A deadline needs a
    /// clock, and R-117e forbids `FocusModel` a `Timer`, a `DispatchSourceTimer`, a
    /// `Task.sleep` poll or a `.timer` publisher — F-54 being event-driven is what makes the
    /// zero-poll claim structural rather than a habit. There is nothing to race against, and
    /// nothing needs to be: a late answer lands in a cache keyed on the priority revision, and
    /// a key nobody asks for again is never read.
    case refused
}

/// **What the model is allowed to say.**
///
/// There is no `unrelated` case and there is no way to add one without editing this enum, which
/// is U-1's *"an uncertain verdict can never be widened into an unrelated one"* held at the type
/// level rather than by a test. `ModelAnswerTests` folds over every case of the `@Generable`
/// schema and asserts the mapping is total and that the `unrelated` label lands in
/// `.decline(.modelSaidUnrelated)`; the fold is a check on the mapping, not the guarantee.
///
/// The guarantee is the shape: the model can turn a question into silence, and there is
/// nothing it can say that turns a question into an accusation.
public enum ModelAnswer: Sendable, Equatable, Hashable {
    case relevant(ModelRelevance)
    case decline(ModelDeclineReason)

    public var isRelevant: Bool {
        switch self {
        case .relevant: true
        case .decline: false
        }
    }
}

/// **The model rung, as a port.**
///
/// Declared here beside `HeuristicRung` — in the shape that file already anticipated, *"so that
/// e06's model rung, when it arrives, plugs into a shape that already exists rather than into
/// one invented for it"* — and implemented in `Packages/FocusModel`, which is the only package
/// in this repository permitted to name `FoundationModels`. `FocusClassify` does not import it,
/// and its framework row (`Foundation NaturalLanguage os`) does not move.
///
/// ## `cachedAnswer` is synchronous because the classification path is
///
/// `judge(…)` is not `async` and never awaits (R-117f lints both). `InterventionPolicy`'s query
/// dwell is forty-five seconds: a question is not warranted until a person has been with a
/// subject for three quarters of a minute. The deterministic engine answers in under a
/// millisecond. So there is a forty-five-second budget between the first judgement of a subject
/// and the first moment the app could speak about it, and an on-device generation costs some
/// hundreds of milliseconds — measured 205–236 ms warm on this rig, 0.6–2.7 s cold. The model
/// fits inside a window that already exists, with three orders of magnitude to spare, *if it is
/// never awaited*.
///
/// So the contribution to a classification is a dictionary read behind a lock. A miss leaves
/// the deterministic answer standing — exactly today's behaviour — and enqueues the ask; the
/// next judgement of that subject reads the cache. The app's first reaction to a new subject is
/// always the deterministic one, which the model lane gates as
/// `modelAnsweredOnFirstJudgement == 0`.
public protocol ModelRung: Sendable {
    /// The synchronous read. Cache only — this is on the classification path.
    func cachedAnswer(for request: ModelRequest) -> ModelAnswer?
    /// The asynchronous ask. Returns immediately; never awaited by a classification.
    func request(_ request: ModelRequest)
    /// Drop what is known about one subject.
    ///
    /// R-105's third invalidation: a user rule written about a subject outranks rank 6 anyway,
    /// but the entry is dropped so the verdict inspector cannot show a stale model rationale
    /// beside a rule. Without this on the protocol the ruling is unimplementable, which is what
    /// the adversarial review found.
    func invalidate(subject: String)
    /// Forget everything. A session ending, or a priority changing, makes every earlier answer
    /// evidence about a different question.
    func reset()
    /// Non-zero, and the model's identity is folded into it (R-104).
    var promptVersion: Int { get }
}
