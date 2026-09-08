import FocusClassify
import FocusCore
import Foundation

/// The seam between the rung and the framework, so that every behaviour of the rung can be
/// driven without a model on the machine.
///
/// `ResourceSuppressionTests` injects each of R-107's three conditions through this rather than
/// through `ProcessInfo` directly, and `FocusModelRungTests` drives a rung that answers `yes`,
/// one that answers `unrelated` and one that refuses — none of which needs Apple Intelligence
/// to be on. A repair whose failing state cannot be produced is not a repair.
public protocol ModelJudging: Sendable {
    func availability() -> ModelTierAvailability
    func judge(_ request: ModelRequest) async -> ModelAnswer
}

/// The shipping judge: the system model, read through the one file that names it.
public struct SystemModelJudge: ModelJudging {
    public init() {}

    public func availability() -> ModelTierAvailability { SystemModelPort.availability() }

    public func judge(_ request: ModelRequest) async -> ModelAnswer {
        await SystemModelPort.judge(request)
    }
}

/// **The model rung.** One public type, and the only implementation of `ModelRung`.
///
/// ## The cache is the rate limiter, so there is no rate constant to get wrong
///
/// The model is asked **at most once per `(priorityRevision, subject)` per session**, because
/// declines are cached too — a model that keeps declining is asked once, not for ever. In-flight
/// requests are tracked so that the dwell ticks re-judging a frontmost subject cannot fan out
/// into a queue of identical asks.
///
/// ## In-memory, session-scoped, never persisted (R-105)
///
/// Persisting it means the OS updating its model, or a prompt bump, leaves a store full of
/// verdicts nobody can safely serve — a staleness class needing a purge job, a migration and a
/// test. And a model answer is **not a user answer**: U-1's never-ask-twice guarantee is about
/// questions a person answered, and those are durable rules and receipts. Model silence is not
/// consent to anything and must not outlive the session that produced it. The cost is that a
/// relaunch re-asks; the model is off the critical path, so the cost is invisible.
///
/// Three invalidations, all synchronous, all already-existing events: a priority edit (the
/// revision moves, so the key moves), a session end (`reset()`), and a user rule written about
/// a subject (`invalidate(subject:)` — that rule outranks rank 6 anyway, but the entry is
/// dropped so the verdict inspector cannot show a stale model rationale beside a rule).
///
/// A `final class` behind an `NSLock` rather than an actor, because `cachedAnswer(for:)` is on
/// the classification path and the classification path is not `async`: an actor would make the
/// read `await`, which is the one thing R-103 forbids.
public final class FocusModelRung: ModelRung, @unchecked Sendable {
    private let judge: any ModelJudging
    private let lock = NSLock()
    private var answers: [String: ModelAnswer] = [:]
    private var keysBySubject: [String: Set<String>] = [:]
    private var inFlight: Set<String> = []
    private var asked = 0

    public init(judge: any ModelJudging = SystemModelJudge()) {
        self.judge = judge
    }

    /// R-104. The prompt revision list's length; the model's own identity rides in the request's
    /// cache key, which folds in the OS version string because no model revision is published on
    /// any public surface (P-152 looked; the version strings exist only in `modelmanagerd`'s
    /// logs). Coarser in the safe direction than a revision we cannot read.
    public var promptVersion: Int { Prompt.version }

    /// Whether the rung may be composed into the ladder right now.
    ///
    /// All three of R-107's conditions, read on demand rather than polled: availability, a
    /// thermal state below `.serious`, and Low Power Mode off. Suppression **stops new
    /// requests; it does not revoke cached answers** — a person whose fan spins up must not
    /// watch the app change its mind about what their work is. Existing knowledge is free;
    /// computing more is what costs.
    public var availability: ModelTierAvailability {
        let reported = judge.availability()
        guard reported == .available else { return reported }
        let process = ProcessInfo.processInfo
        if process.isLowPowerModeEnabled { return .suppressedByResources }
        switch process.thermalState {
        case .serious, .critical: return .suppressedByResources
        default: return .available
        }
    }

    // MARK: - The port

    public func cachedAnswer(for request: ModelRequest) -> ModelAnswer? {
        lock.lock()
        defer { lock.unlock() }
        return answers[request.cacheKey]
    }

    public func request(_ request: ModelRequest) {
        guard availability.isExecutable else { return }

        lock.lock()
        let alreadyKnown = answers[request.cacheKey] != nil || inFlight.contains(request.cacheKey)
        if !alreadyKnown { inFlight.insert(request.cacheKey) }
        lock.unlock()
        guard !alreadyKnown else { return }

        Task { [judge] in
            let answer = await judge.judge(request)
            self.record(answer, for: request)
        }
    }

    public func invalidate(subject: String) {
        lock.lock()
        defer { lock.unlock() }
        for key in keysBySubject.removeValue(forKey: subject) ?? [] {
            answers.removeValue(forKey: key)
        }
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        answers.removeAll()
        keysBySubject.removeAll()
        inFlight.removeAll()
    }

    // MARK: - Evaluation and test priming

    /// Ask and cache without blocking a cooperative executor worker. Async test callers must
    /// use this path: waiting on a semaphore can exhaust the pool needed to finish the request.
    @discardableResult
    public func prime(_ request: ModelRequest) async -> ModelAnswer {
        if let known = cachedAnswer(for: request) { return known }
        guard availability.isExecutable else { return .decline(.notAvailable) }
        let answer = await judge.judge(request)
        record(answer, for: request)
        return answer
    }

    /// Ask, wait, and write the cache — **for the evaluation lane and for nothing else.**
    ///
    /// Lane 2 runs a corpus, not a session: there is no forty-five-second dwell for an answer to
    /// arrive inside, so the harness pays the wait explicitly where production pays it in
    /// elapsed time. It is deliberately not on `ModelRung`, so no shipping caller can reach it:
    /// the port a cascade holds has exactly one synchronous member and it is a dictionary read.
    /// Call only from the standalone evaluation entry point, outside Swift's task executor.
    @available(*, noasync, message: "Use await prime(_:) from an async context")
    @discardableResult
    public func primeSynchronously(_ request: ModelRequest) -> ModelAnswer {
        let box = AnswerBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            box.value = await self.prime(request)
            semaphore.signal()
        }
        semaphore.wait()
        return box.value ?? .decline(.refused)
    }

    /// How many generations this rung has actually paid for. Counted separately from how often
    /// it answered, so a rung that is reached and always declines is distinguishable from one
    /// that is never reached at all.
    public var generationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return asked
    }

    private func record(_ answer: ModelAnswer, for request: ModelRequest) {
        lock.lock()
        defer { lock.unlock() }
        answers[request.cacheKey] = answer
        keysBySubject[request.subject.value, default: []].insert(request.cacheKey)
        inFlight.remove(request.cacheKey)
        asked += 1
    }
}

/// A one-slot mailbox for the synchronous door above. `final class` with a lock rather than a
/// `var` captured across an `await`, which Swift 6 will not let a `Sendable` closure do.
private final class AnswerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ModelAnswer?

    var value: ModelAnswer? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}
