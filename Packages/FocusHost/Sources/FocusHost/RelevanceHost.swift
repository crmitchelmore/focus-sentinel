import FocusClassify
import FocusCore
import FocusModel
import FocusRules
import Foundation
import Observation
import SwiftData
import os

/// One thing to judge, as much of it as the sensitivity gate allowed through.
///
/// Three answers, and the difference between the last two is the whole of adversarial family 6.
///
/// * **`bundleIdentifier != nil`** — an ordinary activation the gate cleared.
/// * **`bundleIdentifier == nil, isSuppressed == true`** — e03's `SensitivityGate` stood the app
///   down. The engine is handed *no subject*, so the strongest answer it can reach is
///   `uncertain`. **"We did not look" must never become "you are distracted"**, and the way to
///   guarantee that is to hand the engine nothing rather than to remember to ignore something.
/// * **`bundleIdentifier == nil, isSuppressed == false`** — a process with no bundle identifier
///   (six of ninety-two on this Mac, e03's P-83). There is nothing to write a rule *about* one,
///   so there is nothing to conclude either.
///
/// There is no fourth field. A window title, an origin and a document name are all absent by
/// construction: `ClassificationInput.origin` and `.titleTokens` are exercised by the golden
/// corpus and **empty in every shipping path in this epic** (F-03 is baseline-only, e07 turns
/// them on), and this type is where that promise is kept in the app.
struct JudgeableSubject: Sendable, Equatable {
    var bundleIdentifier: String?
    var isSuppressed: Bool

    /// Nothing has come forward yet.
    static let none = JudgeableSubject(bundleIdentifier: nil, isSuppressed: false)

    /// The key the dwell clock is filed under.
    ///
    /// Two *different* absences must not share a clock: a stand-down for a password manager and
    /// an unbundled helper are different observations, and letting one continue the other's
    /// dwell would be inventing continuity across a boundary the gate drew.
    var dwellKey: String {
        if let bundleIdentifier { return bundleIdentifier }
        return isSuppressed ? "\u{0000}suppressed" : "\u{0000}unbundled"
    }
}

/// The relevance runtime: the engine, its snapshot, and the verdict the cockpit draws.
///
/// ## What it publishes, and who reads it
///
/// **One eligibility, two readers** (focus-lmy). `assign(_:)` below stores the verdict for the
/// Privacy pane's inspector (R-71) *and* fires `onJudgement`, which `NudgeHost` folds into the
/// ladder. The pane and the nudge are therefore two views of the same decision rather than two
/// decisions, and a sentence drawn in one that denies the other is a defect in the sentence —
/// which is exactly how `settings.verdict.mandated` shipped saying nothing could nudge.
///
/// ## Why the store is read here and never during a classification (R-65)
///
/// `RuleStore` is `async throws` and `SwiftDataRuleStore` is `@MainActor` — its own doc comment
/// worries that *"rule reads happen on the main actor path during classification and must not
/// block it"*. e04 resolves that by never reading the store during a classification at all. The
/// snapshot is rebuilt when — and only when — one of **four** things happens, each of which is
/// a thing a person did:
///
/// 1. the active priority changes,
/// 2. its `revision` changes (they edited the sentence),
/// 3. a rule is written, changed or removed,
/// 4. a context item is added or removed.
///
/// All four already emit through `PriorityActing`, so the composition root has exactly one hook
/// to place. The rebuild is asynchronous because the shipped store API is, and that costs
/// nothing: an activation arriving mid-rebuild is judged against the previous snapshot, and if
/// that snapshot describes a different priority revision the engine **refuses it and answers
/// `uncertain`**, which suppresses. The conservative answer is the one the race produces.
///
/// ## Time
///
/// There is no timer here. `now` is a reading of the injected `MonotonicClock` taken at the
/// moment somebody asked, and dwell is `now` minus the reading at which the current subject
/// became current. The observation stream is driven by the two things that already happen —
/// every accepted activation, and e03's five-second corroboration tick — so the drift clock
/// advances without this host owning a repeating anything.
@MainActor
@Observable
final class RelevanceHost {
    /// The engine, exposed because it *is* the app's `RelevanceClassifier`: the composition root
    /// hands this same object across the seam rather than building a second one, so the verdict
    /// the inspector draws and the answer the seam gives can never be two different opinions.
    let engine: DeterministicRelevanceEngine

    /// What this Mac said about the on-device model at launch, in `FocusCore`'s vocabulary.
    ///
    /// Published so the capability matrix, the Privacy pane and the self-check read **one**
    /// answer rather than each taking their own — and so that `.notRequested` stops being a lie
    /// about a build that asks. Nothing is ever asked of the person about it: a Mac with Apple
    /// Intelligence on gets a better app, and a Mac without it is never told it is missing out
    /// (R-108).
    let modelAvailability: ModelTierAvailability

    /// Whether the rung is actually in this composition's ladder.
    ///
    /// A different question from `modelAvailability`, and keeping them apart is the point: the
    /// first is a fact about the Mac, the second is a fact about the run. A reading that
    /// conflated them would say "available" and leave a reader to guess whether anything was
    /// composed.
    var modelRungIsComposed: Bool { engine.ladder.canExecute(.onDeviceModel) }

    private var builder: RuleSnapshotBuilder
    private let scorer: SimilarityScorer
    private let priorities: PriorityStore
    private let ruleStore: any RuleStore
    private let monotonicClock: any MonotonicClock
    private let logger = Logger(
        subsystem: FocusStore.bundleIdentifier,
        category: "RelevanceHost"
    )

    /// **The verdict stream e05's nudge host consumes.**
    ///
    /// Observation only: it fires *after* the judgement has been made and published, carries a
    /// value, and no classification anywhere in this file reads it or depends on whether
    /// anybody is listening. e04's own promise — "this host publishes; nothing acts" — is
    /// therefore intact in the direction that matters: e05 acts, and the acting cannot reach
    /// back into the judging.
    ///
    /// `NudgeJudgement` rather than `VerdictSnapshot` because a question needs three things the
    /// inspector had no use for: the `ClassificationOutcome` itself, the named route to
    /// `uncertain`, and the subject the classification was actually **about**.
    var onJudgement: ((NudgeJudgement) -> Void)?

    /// Where the session authority comes from (R-72.2).
    ///
    /// A closure rather than a reference to `SessionHost`, because this host must not be able to
    /// reach anything else on it: the only fact it needs is *which session rules apply to this
    /// priority right now*, and `SessionRuleBox` is the only owner of that answer. Wired by the
    /// composition root; `nil` means there is no session lane, which yields no session rules —
    /// the honest answer rather than an empty guess.
    var sessionRules: (@MainActor (UUID?) -> [ScopedRuleValue])?

    /// **Which commitment to build the snapshot for** (focus-zrs).
    ///
    /// A closure for the reason `sessionRules` is one, and wired to `PriorityHost.activeCommitment`
    /// — the app's single statement of the active priority. This host used to answer the question
    /// itself, with a `PriorityStore.activeTask()` of its own: a **fourth** independent read of the
    /// one fact gate 1 is decided by, the nudge loop keys its receipts to, and the lifecycle watch
    /// edges on. Nothing compared them, so the engine could be reasoning about one commitment
    /// while the loop wrote about another.
    ///
    /// The identity is handed in; the *row* is still fetched, because the snapshot needs a
    /// revision, a definition of done and a context pack — but it is fetched **by that identifier**
    /// rather than by asking the store which task is active, which is the same shape
    /// `NudgeHost.answer(_:)` uses for exactly the same reason.
    ///
    /// `nil` means no wire, which yields no priority — the honest answer rather than a guess.
    var activeCommitment: (@MainActor () -> ActiveCommitment?)?

    /// Everything a judgement needs, pre-fetched. Rebuilt on the four invalidations above.
    private(set) var snapshot: RuleSnapshot

    /// What the engine last concluded, or `nil` when it has concluded nothing.
    ///
    /// `nil` is the honest default and the inspector draws it as *nothing judged yet*, never as
    /// a verdict. An app that drew `relevant` before it had looked at anything would be
    /// inventing a judgement.
    private(set) var verdict: VerdictSnapshot?

    /// How many judgements this process has made, and how many snapshots it has built.
    /// Recorded so the zero-grant self-check can report that the engine really ran rather than
    /// that it was merely constructed.
    private(set) var judgementCount = 0
    private(set) var snapshotBuildCount = 0

    /// The subject the dwell clock is currently running for, and when it started.
    private var subjectKey: String?
    private var subjectSince: Duration

    /// Snapshot rebuilds are coalesced: a burst of four invalidations from one mutation is one
    /// rebuild, and a rebuild that arrives while one is in flight schedules exactly one more.
    private var rebuildInFlight = false
    private var rebuildRequested = false

    /// The normaliser and the scorer are built here and handed to **both** the engine and the
    /// snapshot builder, rather than defaulted separately in each.
    ///
    /// That is not tidiness. The scorer is a reference type holding the bounded LRU of P-116's
    /// 3.48 ms sentence distances and the loaded embedding; two of them would be two caches, two
    /// cold loads, and a `warmUp()` that warmed only one of them. The priority-side vector the
    /// snapshot computes once per revision has to come out of the same instance the heuristic
    /// rung later measures against, or the identity the whole signal rests on is being computed
    /// by two different objects.
    ///
    /// ## The model tier is composed here or nowhere (e06, R-100/R-101)
    ///
    /// `FocusClassify` declares the port and imports no implementation of it, so the one module
    /// permitted every sibling is the one that plugs the two together. The rung is built, asked
    /// what this Mac can do, and **only then** composed: on any answer but `.available` the
    /// ladder is `.deterministic` and the app is, by construction, the app e05 shipped — the
    /// same code path the shipping gate already proves, which is why suppression needs no
    /// separate safety argument.
    ///
    /// The availability is read **once, here**, rather than watched. R-117e forbids this tier a
    /// timer, and a tier that could appear mid-session would mean a person watching the app
    /// change its mind about what their work is. A Mac that gains Apple Intelligence gains the
    /// rung at the next launch.
    init(
        context: ModelContext,
        ruleStore: any RuleStore,
        monotonicClock: any MonotonicClock,
        normalizer: TokenNormalizer = TokenNormalizer(),
        scorer: SimilarityScorer = SimilarityScorer(),
        modelRung: FocusModelRung? = FocusModelRung(),
        tunings: PolicyTunings = .shipped
    ) {
        var normalizer = normalizer
        normalizer.tunings = tunings
        scorer.adopt(tunings)
        let availability = modelRung?.availability ?? .unknown
        // **Two gates, and the second is a measurement.** Availability is what this Mac can do;
        // `ModelTierRelease.composesTheRung` is whether the tier has earned a place in the
        // ladder, and it is `false` — the on-device model went quiet about fifteen of the thirty
        // cells the grid committed as holds, three prompt forms running, and a seduction is the
        // app going silent about something the person's own evidence said to hold. See
        // `ModelTierRelease` for the table and for what would flip it.
        let composed = availability.isExecutable && ModelTierRelease.composesTheRung
            ? modelRung : nil
        self.modelAvailability = availability
        let engine = DeterministicRelevanceEngine(
            normalizer: normalizer,
            scorer: scorer,
            model: composed,
            ladder: CascadeLadder(modelAvailable: composed != nil),
            tunings: tunings
        )
        self.engine = engine
        self.ruleStore = ruleStore
        self.monotonicClock = monotonicClock
        self.priorities = PriorityStore(context: context)
        self.builder = RuleSnapshotBuilder(normalizer: normalizer, scorer: scorer)
        self.scorer = scorer
        self.subjectSince = monotonicClock.elapsed
        self.snapshot = RuleSnapshot.empty(stamp: engine.stamp)

        // P-116 measured the sentence embedding's cold load at 59.4 ms and `NaturalLanguage`'s
        // first tagger initialisation at a further 57 ms. Both are paid **here**, at
        // construction, off the classification path — because a stutter that long inside a
        // judgement is a defect a person can feel, and the golden corpus's maximum
        // classification latency falls from 61 ms to 3.1 ms when they are paid up front.
        engine.warmUp()
    }

    // MARK: - What the self-check and the surfaces read

    /// `EngineStamp.cacheKey`, with the OS-supplied sentence-embedding revision filled in.
    ///
    /// Read from the live engine rather than from `EngineStamp.current`, so what the running
    /// application reports is what the running application would actually key a cache on
    /// (P-117, R-63).
    var stampKey: String { engine.stamp.cacheKey }

    /// `RelevancePolicy.digest`, hex. The same literal the unit lane asserts of the test
    /// process and stage 7d asserts of the evaluation report — three legs, one set of committed
    /// literals (R-75.4).
    var policyDigest: String { RelevancePolicy.digestHex }

    /// The dials the engine runs on (focus-exdi).
    var tunings: PolicyTunings { engine.tunings }

    /// Take a person's dials: the engine everywhere it reads one, and the snapshot builder,
    /// whose normaliser holds the shortest-word dial by value.
    func adopt(_ tunings: PolicyTunings) {
        engine.adopt(tunings)
        builder = RuleSnapshotBuilder(normalizer: TokenNormalizer(tunings: tunings), scorer: scorer)
    }

    /// Stored rows this build declined to promote to a rung — legacy `scopeRaw == "session"`
    /// rows, which have no subject kind at all, and retired `scopeRaw == "titleToken"` rows, which
    /// nothing in the shipping app could ever match (e07a) — **skipped and counted, never guessed
    /// at** (R-72.3). Surfaced rather than swallowed.
    var skippedRuleCount: Int { snapshot.skippedRuleCount }

    // MARK: - The snapshot

    private var storeWasDeleted = false

    /// A queued rebuild must not read the old context while the app awaits relaunch.
    func stopForStoreDeletion() {
        storeWasDeleted = true
        rebuildRequested = false
        onJudgement = nil
    }

    /// One of the four invalidations happened. Rebuild, once, soon.
    ///
    /// Synchronous and cheap on purpose: it is called from `refreshCockpit`, which runs on every
    /// mutation and every corroboration tick, and a rebuild per tick would be a store read per
    /// tick — exactly what R-65 exists to prevent.
    func invalidateSnapshot() {
        guard !storeWasDeleted else { return }
        guard !rebuildInFlight else {
            rebuildRequested = true
            return
        }
        rebuildInFlight = true
        Task { @MainActor [weak self] in
            await self?.drainRebuilds()
        }
    }

    private func drainRebuilds() async {
        defer { rebuildInFlight = false }
        repeat {
            rebuildRequested = false
            await rebuildSnapshot()
        } while rebuildRequested
    }

    /// Read the store once and build the immutable value every later judgement reasons from.
    ///
    /// Exposed rather than private so the zero-grant self-check can build a snapshot and read
    /// the result in-process, which is the only way to prove the four-invalidation contract
    /// without an `osascript` grant.
    func rebuildSnapshot() async {
        guard !storeWasDeleted else { return }
        let task = activeTask()
        let priority = task.map {
            PriorityInput(
                id: $0.id,
                revision: $0.revision,
                intent: $0.intent,
                doneWhen: $0.doneWhen
            )
        }

        var rows: [StoredRuleRow] = []
        do {
            rows = try await storedRuleRows(priorityID: priority?.id)
        } catch {
            // A store that will not answer is a fact to report, never a reason to invent rules:
            // an empty rule set falls through to the heuristic, which is the conservative rung.
            logger.error(
                "the rule store refused a read: \(error.localizedDescription, privacy: .public)"
            )
        }

        guard !storeWasDeleted else { return }

        // A different priority makes every earlier observation evidence about a different
        // question, so the drift accumulator and the last verdict go with it. Detected here
        // rather than wired from the composition root, because the snapshot is the only place
        // that knows which priority the engine has been reasoning about.
        let changedPriority = priority?.id != snapshot.priorityID

        snapshot = builder.build(
            priority: priority,
            storedRules: rows,
            sessionRules: sessionRules?(priority?.id) ?? [],
            contextPack: task.map(Self.contextValues(of:)) ?? [],
            stamp: engine.stamp
        )
        snapshotBuildCount += 1
        if changedPriority { reset() }
    }

    /// The stored rules, with the one fact `RelevanceRuleValue` cannot carry.
    ///
    /// `RelevanceRuleValue` has **no `task` field** — the association lives only on the persisted
    /// `FocusSchemaV3.RelevanceRule.task` (R-72's withdrawal, checked against the tree at
    /// `73c1a1f`) — so the two authorities are derived from *which query returned the row*
    /// rather than from anything on the value.
    ///
    /// A store that cannot answer the scoped question has only global rows to give, and that is
    /// the honest reading rather than a shortfall: `InMemoryRuleStore` records no task
    /// association at all, so inferring one from the shape of a subject string would be exactly
    /// the guess R-72.3 forbids.
    private func storedRuleRows(priorityID: UUID?) async throws -> [StoredRuleRow] {
        guard !storeWasDeleted else { return [] }
        guard let scoped = ruleStore as? SwiftDataRuleStore else {
            return try await ruleStore.allRules()
                .map { StoredRuleRow(rule: $0, isTaskScoped: false) }
        }
        var rows = try await scoped.globalRules()
            .map { StoredRuleRow(rule: $0, isTaskScoped: false) }
        guard !storeWasDeleted else { return [] }
        if let priorityID {
            rows += try await scoped.rules(forTask: priorityID)
                .map { StoredRuleRow(rule: $0, isTaskScoped: true) }
        }
        return rows
    }

    private func activeTask() -> FocusSchemaV3.PriorityTask? {
        // The commitment's identifier from the one place that states it, and the row by that
        // identifier (focus-zrs). Never `activeTask()`, which would be this host deciding for
        // itself which commitment the app is working under.
        guard let id = activeCommitment?()?.id else { return nil }
        do {
            return try priorities.task(id: id)
        } catch {
            logger.error(
                "the priority store refused a read: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// The context pack, in chip order.
    ///
    /// Availability is deliberately not resolved here. A `file` item's bookmark says nothing the
    /// engine may use — R-56.1 excludes `file` from the negative basis precisely because at zero
    /// grants the engine cannot see which file is open — so touching the disk to build a
    /// judgement's input would be a file-system operation with no consequence.
    private static func contextValues(of task: FocusSchemaV3.PriorityTask) -> [ContextItemValue] {
        task.contextItems
            .sorted { $0.addedAt < $1.addedAt }
            .map { ContextItemValue($0) }
    }

    // MARK: - Judging

    /// Fold one observation in and publish what came back.
    ///
    /// Called on every accepted activation **and** on e03's corroboration tick, which is what
    /// makes the drift clock advance between activations without a timer of this host's own. An
    /// observation at a `now` the machine has already seen changes nothing: the drift reducer
    /// guards on a positive interval, so a burst of refreshes costs a judgement and moves no
    /// clock.
    func observe(
        _ subject: JudgeableSubject,
        phase: SessionPhase,
        isUserIdle: Bool
    ) {
        let now = monotonicClock.elapsed
        let key = subject.dwellKey
        if key != subjectKey {
            subjectKey = key
            subjectSince = now
        }

        let dwell = now - subjectSince
        let judgement = engine.judge(
            input: ClassificationInput(bundleIdentifier: subject.bundleIdentifier),
            snapshot: snapshot,
            now: now,
            dwell: dwell,
            phase: phase,
            isUserIdle: isUserIdle
        )
        judgementCount += 1
        let published = judgement.verdictSnapshot(stampKey: stampKey)
        verdict = published

        // Published last, and consumed by at most one listener. Everything above has already
        // happened; a nudge host that threw would not change a verdict, and a nudge host that
        // is absent changes nothing at all — which is exactly what e04 shipped.
        onJudgement?(
            NudgeJudgement(
                outcome: judgement.outcome,
                uncertainty: judgement.uncertaintyReason,
                subject: subject.bundleIdentifier,
                dwelled: dwell,
                snapshot: published,
                stamp: engine.stamp
            )
        )
    }

    /// Forget the clock and the last verdict.
    ///
    /// Called when the priority changes or the session ends, both of which make every earlier
    /// observation evidence about a different question. Keeping the accumulator across a new
    /// priority would be attributing the last one's detour to this one.
    func reset() {
        engine.reset()
        subjectKey = nil
        subjectSince = monotonicClock.elapsed
        verdict = nil
    }
}
