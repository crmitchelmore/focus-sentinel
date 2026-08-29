import AppKit
import FocusClassify
import FocusCore
import FocusRules
import FocusUI
import Foundation
import Observation
import SwiftData
import os

/// **The nudge loop, running** (R-84a, R-93, F-04).
///
/// ## What it is, and what it deliberately is not
///
/// It is the **only** thing in the application that turns a judgement into behaviour, and it
/// makes **no decision of its own**. Every "should the app speak?" question is
/// `NudgeDecider.decide(…)`'s, every "which surface?" question is `SurfaceRouter`'s, every
/// "may it?" question is `SuppressionStack`'s and `FatigueController`'s, and every "which rung?"
/// question is `LadderMachine`'s. This object subscribes, calls, presents, records, and clears —
/// and `NudgeHostContractTests` asserts that by reading this file rather than by trusting it.
///
/// That division is the whole reason the decider is a pure function over values: the corpus, the
/// sequence fixtures and the realistic-day fixtures drive **the shipping decision** with no
/// store, no clock and no window, because the part that needs those lives here and decides
/// nothing.
///
/// ## The three lifetimes it holds
///
/// * **The day's spend** is not held at all — it is read from `InterventionLog` on every
///   judgement, so the caps survive a relaunch and cannot be cleared by quitting (R-83).
/// * **The session's state** — the ladder, the fatigue runs, the snooze book, the corrected
///   subjects, the interruption slot — is held in memory and dies with the session, because a
///   backoff or a snooze that survived a relaunch would have outlived the situation it was for.
/// * **The receipts** are the ledger's, and are immutable. Nothing here can edit one.
///
/// ## Nothing is ever recorded that nobody could see
///
/// Only a `.accuse`, a `.ask` and a `.deferred` reach `InterventionLog`. A silence is not an
/// event — the app says nothing thousands of times a day — and writing one per corroboration
/// tick would make the largest table in the store a log of the app not speaking. The
/// suppression-reason breakdown `evaluation.json` reports is computed by the harness from the
/// decider's own answers, which is where a *reason* belongs (R-93).
@MainActor
@Observable
final class NudgeHost {
    // MARK: - Collaborators

    private let ledger: QueryLedger
    private let log: InterventionLog
    private let priorities: PriorityStore
    private let sessionRules: SessionRuleBox
    private let panel: NudgePanelController
    private let menuBar: MenuBarController
    private let notifications: NotificationDelivery
    private let workspace: any ReturnWorkspace
    private let monotonicClock: any MonotonicClock
    private let dateProvider: any DateProvider
    private let logger = Logger(
        subsystem: FocusStore.bundleIdentifier,
        category: "NudgeHost"
    )

    // MARK: - What the composition root wires in

    /// Everything the world is doing, gathered by the root from e03's sensing types.
    ///
    /// A closure rather than a reference to `SensingHost`, for the reason `RelevanceHost`'s
    /// session-rule closure is one: the only facts this host needs are the ones
    /// `NudgeSurroundings` names, and a reference to the whole host would be a licence to reach
    /// for the rest of it.
    var surroundings: (@MainActor () -> NudgeSurroundings)?

    /// **What the person chose, and what the notification boundary currently believes**
    /// (focus-zrs).
    ///
    /// The authorisation used to be a **copy**: `AppComposition` read it from
    /// `NotificationDelivery` at launch and again after the settings pane's one sanctioned
    /// request, and wrote it in here. But `NotificationDelivery.deliver(…)` sets its own to
    /// `.denied` the moment a delivery actually fails — the route change R-82.4 requires — and
    /// nothing told the copy. So `SurfaceRouter` went on being handed `.authorised` and went on
    /// sending the next recommitment rung to a channel the boundary already knew was shut, failing
    /// and demoting each time, while the Settings pane (which reads the boundary directly) drew
    /// `.denied`. One question, two answers, in two windows and a router.
    ///
    /// Derived now. The two halves a **person** sets are stored; the authorisation is read from
    /// the object that owns it, every time this value is built.
    var preferences: NudgePreferences {
        NudgePreferences(
            voice: chosenVoice,
            reducedInterruption: chosenReducedInterruption,
            authorisation: notifications.authorisation
        )
    }

    private var chosenVoice: NudgeVoice = .standard
    private var chosenReducedInterruption = false

    /// The two things the Intervention pane can set.
    ///
    /// Named verbs rather than a settable `preferences`, so there is no way to hand this object an
    /// authorisation — a value it does not own and must not be able to hold a stale copy of.
    func choose(voice: NudgeVoice) { chosenVoice = voice }
    func choose(reducedInterruption: Bool) { chosenReducedInterruption = reducedInterruption }

    /// A correction that has to be performed somewhere else — a persisted rule (which goes
    /// through `PriorityHost`, so it lands in the Rules pane with an undo registered), a pause
    /// (which goes through e03's own session machine), or e02's confirm surface.
    ///
    /// The host never writes a rule itself. `CorrectionAction.outcome(scope:at:)` decides
    /// **what** one click writes and this closure performs it, so there is still exactly one
    /// place a click becomes a write (R-86).
    ///
    /// **It carries the commitment the nudge was raised under** (focus-lmo, U-1). The receipt
    /// half of that ruling was fixed by keying the open question to its ask-time priority; the
    /// *rule* half travelled on and was not. `AppComposition.perform(_:)` scoped the row it
    /// wrote to `priorityHost.state.priority?.id` — the priority as it stands when the person
    /// *clicks* — and both nudge surfaces are deliberately sticky (`hidesOnDeactivate` is
    /// `false`, R-89), so a person can commit to something new and then answer a panel that was
    /// raised about the old commitment. What they taught the app about one thing landed on
    /// another: a `RuleAuthority.task` rule under a task the judgement never concerned, and
    /// nothing at all under the task it did. The identifier is captured when the nudge goes up
    /// and travels with the outcome.
    var onCorrection: (@MainActor (CorrectionOutcome, UUID?) -> Void)?

    /// The session a session-lived rule belongs to. `nil` when there is no open session, in
    /// which case "Not this time" has no session to die with and is not offered.
    var currentSessionID: (@MainActor () -> UUID?)?

    // MARK: - Session state

    private(set) var ladder = LadderMachine()
    private(set) var fatigue = FatigueController()
    private(set) var snoozes = SnoozeBook.none
    /// Subjects a "this is relevant" correction has taken out of the accusable set this session.
    /// The **rule** is the mechanism; this is the backstop for the moment between the click and
    /// the next classification (R-83).
    private(set) var correctedSubjects: Set<String> = []
    /// The last subject the engine judged `relevant`: what "Back to …" returns to (R-88).
    /// `nil` until the engine has seen one, in which case the action is not offered at all.
    private(set) var returnAnchor: String?

    /// What the decider last said. Read by the self-check, so "the loop ran" is a value rather
    /// than a claim.
    private(set) var lastDecision: NudgeDecision?
    private(set) var decisionCount = 0

    /// **Attempts this process made, not the day's spend** (focus-zrs).
    ///
    /// Written down because the two are a pair that is *meant* to differ and would otherwise read
    /// as one fact held twice. These count what this object did since launch; the spend is
    /// `InterventionLog.budget(on:priorityID:)`, summed from persisted rows on `spendsBudget`, and
    /// it is the only figure any cap is decided by (R-83).
    ///
    /// They part company at exactly one place, deliberately: `undeliverOpenRecord(…)` takes a
    /// delivery off the budget when a rung is stranded or a question's answers go out of reach,
    /// and does **not** decrement `deliveredCount` — because the app really did put something on
    /// the screen, and a counter of attempts that forgot it would be describing a different day
    /// from the one that happened.
    private(set) var deliveredCount = 0
    private(set) var deferredCount = 0

    /// The log row for whatever is on screen, so the person's answer can complete it.
    private var openRecordID: UUID?

    /// **The question on screen, as one value** (focus-zrs).
    ///
    /// It was six independent stored properties — the warrant, the ask time, the priority
    /// identifier, the surface, the reading taken at the ask and the answer identifiers — set on
    /// one line each and cleared on another. Every one of them is a statement about the *same*
    /// question, and each of the last five rounds found a path where some of them had moved and
    /// some had not. The `nil` this round is about is the sixth: `openQuestionPriorityID` came
    /// from a store read that could disagree with the gate that admitted the question, and every
    /// consumer of it opened with `guard let … else { return }` — so a divergence silently
    /// dropped the person's click, and one function on made `displacedQuestion(from:)` answer
    /// `nil` and `PreemptionCredit` go unconsulted.
    ///
    /// One optional cannot be half-set. `priorityID` is **not** optional inside it, because a
    /// question that does not know what commitment it is about is not a question this loop is
    /// allowed to have raised: `ask(…)` refuses to raise one, loudly, rather than raising it with
    /// a `nil` key.
    private struct OpenQuestion {
        let warrant: QueryWarrant
        /// **The commitment it was asked under** (focus-lmo, U-1) — captured, never fetched,
        /// because the panel is sticky (`hidesOnDeactivate` is `false`, R-89) and a person can
        /// commit to something new while a question waits. It is the key the receipt, the learned
        /// rule and every deferral row that stands in for a receipt are written against.
        let priorityID: UUID
        let askedAt: Date
        /// **Which surface the question went to**, and, below, what that surface could be *proven*
        /// to show (focus-kby, U-1). Both, rather than one `Bool`, because the `Bool` was the
        /// defect: it was set outside the `if surface == .panel` branch, so a question routed to
        /// the popover badge was marked presentable having read nothing — and the popover opens
        /// only when a person clicks the status item.
        ///
        /// `nil` while the ask has chosen no surface at all, which is the deferral path.
        var surface: NudgeSurface?
        /// | surface | readable means |
        /// |---|---|
        /// | `panel` | on screen, on a display, and every answer in reach |
        /// | `popoverBadge` | the popover is **open and showing this question** |
        ///
        /// Nothing infers readability from having called `show(…)`, and nothing infers it from
        /// falling through a branch. A *settling* receipt about a question nobody saw does not
        /// merely mis-record history — `isSettled(…)` is gate 11, so it permanently silences that
        /// question.
        var readingAtAsk: SurfaceReadability = .unknowable
        /// The answers the question is offering, by `rawValue`, so a reading taken as it ends asks
        /// about the same set the panel was drawn with.
        var actions: [String] = []
    }

    private var openQuestion: OpenQuestion?

    /// **The rung on screen, as one value** (focus-zrs) — `OpenQuestion`'s twin, for the twin
    /// reason.
    ///
    /// The rung, the commitment it was raised under, the corrections it is offering and the
    /// notification delivery it went out on are four statements about one interruption, and they
    /// were four properties. The last of them is this round's defect C: a notification's buttons
    /// stay live in Notification Centre indefinitely, and `notifications.onAction` reached
    /// `resolve(…)` with **no check that the rung the button belongs to is still open**.
    private struct OpenRung {
        let rung: LadderRung
        /// The commitment it was raised under: the persisted "this is relevant" rule, the
        /// session-lived "not this time" rule and the deferral row a display change writes when it
        /// strands the rung are all keyed to this rather than to whatever the store happens to
        /// call active at the moment of the click (focus-lmo).
        let priorityID: UUID
        /// **The surface this rung actually reached** (focus-k42).
        ///
        /// Not optional, and that is the whole repair. An `OpenRung` is constructed only at a
        /// landing, so a rung that exists is a rung that is somewhere; a rung that reached nobody
        /// is not a quieter `OpenRung` with a `nil` surface, it is **no** `OpenRung` at all.
        /// Together with `holdsTheInterruptionSlot` below, this is what stops *which rung this is*
        /// and *whether the screen is occupied* from being the same fact.
        let landedOn: NudgeSurface
        /// Empty when the live rung is not on the panel, which is every surface that has no
        /// actions to be out of reach.
        var panelActions: [String] = []
        /// **Whether this rung is occupying the thing the slot is about: an answerable screen.**
        ///
        /// R-84a's argument for a single slot is that *"two panels on screen at once is the
        /// behaviour that makes people uninstall"*. A glyph and a badge are not panels: they carry
        /// no sentence and offer nothing to press, which is exactly what
        /// `NudgeSurface.offersACorrection` already says. A glyph that held the slot would hold it
        /// for ever, because nothing can take an ambient rung down.
        var holdsTheInterruptionSlot: Bool { landedOn.offersACorrection }
    }

    private var openRung: OpenRung?

    /// **One open interruption at a time, derived rather than stored** (R-84a, focus-zrs).
    ///
    /// `slot` was a stored `InterruptionSlot` mutated on eleven lines beside the fields above —
    /// a second representation of *which interruption is on screen*, and the one the **decider**
    /// reads. `NudgeDecider.accuse(…)` computes `preempted` from `memory.slot.offering(rung)`, so
    /// a slot that said "a question holds this" while the host held none produced a
    /// `PreemptedQuery` naming a question `displacedQuestion(from:)` could not find — which is
    /// this round's defect B, arriving from the other side.
    ///
    /// Derived, the two cannot part company: the value the decider is handed *is* the question and
    /// the rung this object is holding. `InterruptionSlot` keeps the ruling; this keeps the
    /// bookkeeping honest.
    ///
    /// **Derived from the right thing, which is not the same as derived** (focus-k42). This read
    /// `openRung != nil`, which made *"a rung exists"* and *"the screen is occupied"* one
    /// statement — so a rung that reached nobody, and a rung sitting on the ambient glyph, both
    /// withheld every interruption that followed. Measured on the shipping loop: one `unrelated`
    /// judgement lights the glyph, and from that moment every `uncertain` judgement for the rest of
    /// the session answers `silent(interruptionInFlight)`. That is U-1's question affordance dead
    /// for the session after a single drift, with no symptom but silence.
    ///
    /// It asks `holdsTheInterruptionSlot` now, which is a fact about **where the rung landed**
    /// rather than about whether this object is holding one.
    var slot: InterruptionSlot {
        if let openRung, openRung.holdsTheInterruptionSlot {
            return InterruptionSlot(holder: .accusation(openRung.rung))
        }
        if let openQuestion { return InterruptionSlot(holder: .query(openQuestion.warrant)) }
        return .open
    }

    /// **Every refusal this host has had to make because two readings of one fact disagreed.**
    ///
    /// Stated as counts rather than as comments, so the unit lane and `--focus-self-check` can
    /// read them and a regression is a number rather than an argument. Both must be zero in
    /// every automated run; a non-zero one is the class these rounds exist to end, recurring.
    /// The corrections the rung on the panel is offering, by `rawValue`, so a reading taken later
    /// asks about the same set the panel was drawn with. Derived from the open rung rather than
    /// stored beside it (focus-zrs): empty is *"no rung, or a rung on a surface with nothing to
    /// press"*, and there is no third state it can drift into.
    var openRungPanelActions: [String] { openRung?.panelActions ?? [] }

    private(set) var mandatesWithoutACommitment = 0
    private(set) var staleNotificationActions = 0

    init(
        context: ModelContext,
        sessionRules: SessionRuleBox,
        panel: NudgePanelController,
        menuBar: MenuBarController,
        notifications: NotificationDelivery,
        workspace: any ReturnWorkspace,
        monotonicClock: any MonotonicClock,
        dateProvider: any DateProvider,
        calendar: Calendar
    ) {
        self.ledger = QueryLedger(context: context, dateProvider: dateProvider)
        self.log = InterventionLog(
            context: context,
            dateProvider: dateProvider,
            calendar: calendar
        )
        self.priorities = PriorityStore(context: context)
        self.sessionRules = sessionRules
        self.panel = panel
        self.menuBar = menuBar
        self.notifications = notifications
        self.workspace = workspace
        self.monotonicClock = monotonicClock
        self.dateProvider = dateProvider

        panel.onDismiss = { [weak self] in self?.dismissWhateverIsOpen() }
        // **The display can be replaced under a panel that is already up** (focus-56y). The panel
        // re-measures and re-places itself for whatever is there now; this is the loop being told
        // so it can read the result and decide what it means.
        panel.onDisplaysChanged = { [weak self] in self?.displaysChanged() }
        // **An action names the delivery it belongs to, and a stale one is refused** (focus-zrs).
        //
        // This was `resolve(action.correction, snoozeDuration: nil)` with no check of any kind. A
        // notification's buttons stay live in Notification Centre indefinitely — long after the
        // rung has been answered, escalated past, withdrawn or replaced — so a click on an hour-old
        // banner reached the live loop and closed whatever happened to be on screen. Driven while a
        // **question** was on the panel it turned `query/delivered/nil` into
        // `query/delivered/corrected` and took the panel away: a falsified row, and a question the
        // person never answered recorded as an answer.
        notifications.onAction = { [weak self] response in
            self?.resolveFromNotification(response)
        }
    }

    // MARK: - The one entry point

    /// One judgement, considered.
    ///
    /// Called from the verdict stream `RelevanceHost` publishes — every accepted activation and
    /// e03's five-second corroboration tick — so the loop advances without this host owning a
    /// timer of its own.
    func consider(_ judgement: NudgeJudgement) {
        guard let surroundings = surroundings?() else { return }

        // **The presentation gate can close while a nudge is already on screen** (R-84, F-35).
        //
        // Gate 7 decides whether the app may *speak*; it has nothing to say about a panel that
        // has already spoken. And a panel is deliberately sticky — `hidesOnDeactivate` is
        // `false`, so a nudge waits for an answer rather than vanishing the moment somebody
        // clicks back into their work (R-89). Put those two together and a panel shown a minute
        // before a full-screen space opens is still there when it does, still carrying the
        // `.fullScreenAuxiliary` the gate reading of that earlier moment granted it — and P-130
        // measured such a panel drawn plainly on top of a real presentation.
        //
        // So the gate closing is an event, not just a condition, and this is where it is
        // noticed: on the next accepted activation or corroboration tick, which is the same
        // cadence every other nudge decision runs at.
        if surroundings.presentation.suppressesOverlays, panel.isVisible {
            withdrawForPresentation()
        }

        // A snooze that has lifted is not a snooze. Pruning here rather than inside the decider
        // keeps the decider a pure function of the values it is handed.
        snoozes = snoozes.pruned(at: surroundings.monotonic)
        rememberAnchor(judgement)

        let subject = NudgeDecider.querySubject(for: judgement)
        // **The commitment gate 1 is decided by, and the key everything this judgement writes is
        // scoped to — one value, read once** (focus-zrs). It was two: `surroundings`' own
        // `hasActivePriority` decided whether the app might speak, and a *second*, live
        // `priorities.activeTask()` decided what the interruption was about. Nothing enforced
        // that they agreed, and on a divergence the app spoke and then dropped the answer.
        let commitment = surroundings.commitment
        let priorityID = commitment?.id

        let memory: NudgeMemory
        do {
            memory = try NudgeMemory.reading(
                ledger: ledger,
                log: log,
                priorityID: priorityID,
                subject: subject,
                slot: slot,
                fatigue: fatigue.state,
                snoozes: snoozes,
                correctedSubjects: correctedSubjects,
                ladder: ladder
            )
        } catch {
            // A store that will not answer is a fact to report, never a reason to guess. The
            // conservative reading of an unreadable ledger is that the question **has** been
            // asked and the budget **is** spent, which is silence — the pre-U-1 posture, which
            // can never be worse than the shipped baseline.
            logger.error(
                "the nudge stores refused a read: \(error.localizedDescription, privacy: .public)"
            )
            return
        }

        let decision = NudgeDecider.decide(
            judgement,
            surroundings: surroundings,
            memory: memory,
            preferences: preferences
        )
        lastDecision = decision
        decisionCount += 1

        perform(
            decision,
            judgement: judgement,
            surroundings: surroundings,
            commitment: commitment
        )
    }

    /// The last application the engine called real work.
    ///
    /// Recorded here rather than inferred later, because by the time a mandate exists the
    /// frontmost application is the *distraction* — asking the workspace then would offer to
    /// return somebody to the thing they were being nudged about.
    private func rememberAnchor(_ judgement: NudgeJudgement) {
        guard judgement.verdict == .relevant, let subject = judgement.subject else { return }
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        returnAnchor = trimmed
    }

    // MARK: - Performing what was decided

    private func perform(
        _ decision: NudgeDecision,
        judgement: NudgeJudgement,
        surroundings: NudgeSurroundings,
        commitment: ActiveCommitment?
    ) {
        switch decision {
        case .silent:
            // Nothing to do and nothing to write. The app is quiet far more often than it
            // speaks, and a row per silence would drown the record of what it actually did.
            break

        case .deferred(let reason):
            record(
                deferral: reason,
                kind: judgement.eligibility.mandate != nil ? .accusation : .query,
                subject: judgement.subject,
                priorityID: commitment?.id
            )

        case .accuse(let rung, let route):
            guard let commitment = mandated(commitment, kind: .accusation, subject: rung.subject)
            else { return }
            accuse(
                rung: rung,
                route: route,
                surroundings: surroundings,
                commitment: commitment
            )

        case .ask(let warrant, let route):
            guard let commitment = mandated(
                commitment, kind: .query, subject: warrant.subject.identifier
            ) else { return }
            ask(
                warrant: warrant,
                route: route,
                surroundings: surroundings,
                commitment: commitment
            )
        }
    }

    /// **Gate 1 said yes; this insists it said yes about something** (focus-zrs).
    ///
    /// `NudgeDecider` mandates an interruption only through `SuppressionStack`, whose first gate is
    /// `hasActivePriority` — which is now `commitment != nil` on the very value passed in here, so
    /// this cannot fire. It is written down anyway, and loudly, because the whole subject of this
    /// round is that "cannot" was a belief about two values nobody compared. If a future edit
    /// re-opens a second door to the active priority, the app **defers** rather than raising an
    /// interruption it has no key for — and the count says it happened rather than a `nil` doing it
    /// in silence.
    private func mandated(
        _ commitment: ActiveCommitment?,
        kind: InterruptionKind,
        subject: String?
    ) -> ActiveCommitment? {
        if let commitment { return commitment }
        mandatesWithoutACommitment += 1
        logger.fault(
            """
            the decider mandated a \(kind.rawValue, privacy: .public) with no commitment: \
            gate 1 and the key it writes disagree, so nothing is raised
            """
        )
        record(deferral: .noSurfaceAvailable, kind: kind, subject: subject, priorityID: nil)
        return nil
    }

    /// **R-81, at the point it costs something.** A rung nobody could see is written down as a
    /// deferral, and the ladder is told — which, because `LadderMachine` writes no `deliveredAt`
    /// for one, is how the escalation clock stays stopped and how
    /// `nudge.escalationsFromDeferred == 0` becomes a property of the arithmetic.
    ///
    /// - Parameters:
    ///   - kind: which interruption could not be seen. A deferral has no surface to infer it
    ///     from, so the caller says which it was rather than the record guessing.
    ///   - subject: what it would have been about. Empty for a mixed accusation, which names
    ///     nobody.
    private func record(
        deferral: DeferralReason,
        kind: InterruptionKind,
        subject: String?,
        priorityID: UUID?
    ) {
        deferredCount += 1
        ladder.reduce(.delivery(.deferred(deferral)), now: monotonicClock.elapsed)
        write(
            InterventionEvent(
                kind: kind,
                subject: subject ?? "",
                disposition: .deferred,
                deferralReason: deferral
            ),
            priorityID: priorityID
        )
    }

    /// **Raise one rung, and take the slot only if it actually lands** (U-2, focus-k42).
    ///
    /// ## What this function no longer does
    ///
    /// It used to open by closing whatever question was on screen — and closing meant *settling*,
    /// so the question was never asked again for the life of the commitment. That ran before the
    /// code knew whether a surface was available, before the panel's actions were checked for
    /// reach, and before the notification had been delivered or suppressed. Seven rounds of
    /// repairs to that one interaction, and U-2 deleted it: `InterruptionSlot.offering(_ rung:)`
    /// now **withholds** against an open question, so by the time control reaches here there is no
    /// question to displace and nothing to settle.
    ///
    /// ## Ownership is established by landing, not by intent
    ///
    /// `openRung` used to be assigned on the first line — before anything knew where the rung was
    /// going — and released on no deferral path at all. Because `slot` read `openRung != nil`,
    /// *"a rung is being raised"* and *"the screen is occupied"* were the same statement, so a rung
    /// that reached nobody went on holding the one interruption slot for the rest of the session.
    ///
    /// The rung is therefore recorded **only where it lands**, carrying the surface it landed on.
    /// Every path that reaches nobody calls `forgetOpenRung()` instead: a rung with no surface is
    /// not a quieter interruption, it is not an interruption at all.
    private func accuse(
        rung: LadderRung,
        route: SurfaceRoute,
        surroundings: NudgeSurroundings,
        commitment: ActiveCommitment
    ) {
        let priorityID = commitment.id
        // Nothing is displaced here any more. The decider offered this rung to the slot and the
        // slot withheld it if a question was open, so control only reaches this line when the
        // screen is the accusation's to take (U-2).
        //
        // **The mandate reaches the ladder that persists** (focus-56y, R-80).
        //
        // `NudgeDecider.accuse(…)` folds the mandate into a **copy** of this machine to work out
        // which rung is next, and that copy is discarded with the decision. Without the same fold
        // here, `liveMandate` stayed `nil` on the ladder that survives the call — so
        // `candidate(at:budgetPermits:)` answered `nil`, `offer(…)` recorded nothing, and
        // `reduce(.delivery(.delivered(_)))` found no attempt to resolve and returned without
        // touching the state. The ladder never left `.idle`, every judgement re-entered at
        // `LadderRung.entry(for:)`, and the app could not escalate past the ambient glyph however
        // long somebody drifted. The panel and recommitment rungs were unreachable in the running
        // loop, which is why the whole of R-80's escalation story had no test that ran it.
        //
        // Folded here rather than in `consider(_:)` because this is the branch that has a mandate:
        // the decision carries the rung, and the rung carries the mandate it was built for.
        ladder.reduce(.mandate(rung.mandate), now: surroundings.monotonic)
        ladder.offer(at: surroundings.monotonic, budgetPermits: true)

        let presentation = accusationPresentation(for: rung, commitment: commitment)
        guard let surface = route.surface else {
            record(
                deferral: route.deferralReason ?? .noSurfaceAvailable,
                kind: .accusation,
                subject: rung.subject,
                priorityID: priorityID
            )
            // Reached nobody at all, so there is no rung on any surface — and nothing may go on
            // holding the interruption slot in its name (focus-k42).
            forgetOpenRung()
            return
        }

        switch surface {
        case .menuBar, .popoverBadge:
            // The glyph and the badge are drawn by the composition root's own menu-bar refresh;
            // nothing here has to raise a window for them.
            //
            // It landed, so the rung is recorded against the surface it landed on — but
            // `offersACorrection` is `false` for both of these, so it does not hold the
            // interruption slot. Nothing can ever take an ambient glyph down, and a rung that held
            // the slot from a glyph would silence the question affordance for the rest of the
            // session (focus-k42).
            openRung = OpenRung(rung: rung, priorityID: priorityID, landedOn: surface)
            delivered(surface: surface, rung: rung, priorityID: priorityID)

        case .panel:
            panel.update(AccusationPanelView(presentation: presentation) { [weak self] action, span in
                self?.resolve(action, snoozeDuration: span)
            })
            panel.show(
                presentationIsClear: !surroundings.presentation.suppressesOverlays,
                announcement: presentation.announcement()
            )

            // **R-81 at the level that matters: a rung whose corrections are out of reach was
            // not delivered** (focus-vpu). A live drive read this panel with Pause and Change
            // priority below the clip — the two actions a person most needs when the app is
            // wrong. An accusation you cannot answer back to is the anti-pattern the Court's
            // product boundary forbids, so it is a deferral: the ladder's clock stays stopped,
            // nothing is counted, and the rung is offered again.
            //
            // The reading is taken against the presentation's own action list rather than against
            // a list written onto the open rung first: the rung is not recorded at all until it is
            // known to have landed somewhere answerable, so there is no half-built rung for this
            // guard to have to unwind (focus-k42).
            let reading = panel.decisionSurfaceReading(
                offering: presentation.offeredActionIdentifiers
            )
            guard reading.everyActionIsReachable else {
                logger.error(
                    "a rung was put on an unreadable panel: \(reading.summary, privacy: .public)"
                )
                panel.hide()
                record(
                    deferral: .noSurfaceAvailable,
                    kind: .accusation,
                    subject: rung.subject,
                    priorityID: priorityID
                )
                // The panel has just been hidden, so this rung is on no surface at all. It gives
                // the slot back and stops offering corrections nobody can see (focus-k42).
                forgetOpenRung()
                return
            }
            // Landed, answerable, and therefore genuinely occupying the one interruption slot —
            // the case R-84a is actually about.
            openRung = OpenRung(
                rung: rung,
                priorityID: priorityID,
                landedOn: .panel,
                panelActions: presentation.offeredActionIdentifiers
            )
            delivered(surface: .panel, rung: rung, priorityID: priorityID)

        case .notification:
            // **No rung routes here any more** (U-2). The notification was the recommitment rung's
            // surface and nothing else's, and that rung is deferred to focus-5ab — so
            // `SurfaceRouter` has no branch that can answer `.notification` for an accusation.
            //
            // This is a refusal rather than a deleted branch because the surface is still a
            // declared one (the settings pane still reads and reports notification authorisation),
            // and a routing bug that sent a rung here must be a loud deferral rather than a
            // silently swallowed nudge.
            logger.fault("a rung was routed to a notification, which no rung reaches since U-2")
            record(
                deferral: .noSurfaceAvailable,
                kind: .accusation,
                subject: rung.subject,
                priorityID: priorityID
            )
            forgetOpenRung()

        }
    }

    private func ask(
        warrant: QueryWarrant,
        route: SurfaceRoute,
        surroundings: NudgeSurroundings,
        commitment: ActiveCommitment
    ) {
        let priorityID = commitment.id
        // The slot's own rule, still the slot's: a question is admitted only against an empty
        // slot, including against another question. `slot` is derived from the two values below,
        // so taking it *is* assigning them (focus-zrs).
        guard case .admitted = slot.offering(warrant) else { return }
        // One value, set once. The commitment as it stands **now**, at the ask, travels inside it:
        // everything this question ever writes is keyed to that and never to a later store read
        // (focus-lmo, focus-zrs).
        openQuestion = OpenQuestion(
            warrant: warrant,
            priorityID: priorityID,
            askedAt: dateProvider.now
        )
        forgetOpenRung()

        let presentation = QueryPresentation(
            voice: preferences.voice,
            // The commitment's own sentence, carried in with it rather than fetched again — so the
            // question on the screen names the task the receipt will be written against.
            task: commitment.intent,
            subject: warrant.subject.identifier,
            reason: warrant.reason,
            dwelled: warrant.dwelled
        )

        guard let surface = route.surface else {
            record(
                deferral: route.deferralReason ?? .noSurfaceAvailable,
                kind: .query,
                subject: warrant.subject.identifier,
                priorityID: priorityID
            )
            return
        }
        openQuestion?.surface = surface
        openQuestion?.actions = presentation.offeredAnswerIdentifiers

        switch surface {
        case .panel:
            panel.update(QueryPanelView(presentation: presentation) { [weak self] answer in
                self?.answer(answer)
            })
            panel.show(
                presentationIsClear: !surroundings.presentation.suppressesOverlays,
                announcement: presentation.announcement()
            )

            // **The question is only asked if it is askable** (focus-x7d, focus-vpu).
            //
            // `RungDelivery`'s own doctrine, applied to the one surface it was not applied to:
            // *a window being listed on screen is not a window being visible.* The reading is
            // taken here, from the panel, rather than trusted from the show path — and it is
            // about the **answers**, not about the frame: a panel of exactly the agreed size with
            // "Not now" past its edge is a question the person cannot answer.
            //
            // A question that fails it is a **deferral**: nothing is counted, nothing is
            // written, the slot is given back, and the subject stays askable. Deferring costs
            // the person one more moment of drift; recording it would cost them the question.
            // **The reading is derived once and the guard tests the derived value.** It used to
            // be derived twice — the property from `everyActionIsReachable`, the guard from
            // `everyActionIsReachable` again — and the duplication made the property unfalsifiable:
            // replacing the whole expression with a constant `.readable` changed nothing a test
            // could observe, because the guard still read the panel and the failing branch called
            // `forgetOpenQuestion()`, which overwrote the constant with `.unknowable` on its way
            // out. One derivation, one gate: a question is delivered only if the value the ledger
            // will later be handed says it could be read.
            let reading = panel.decisionSurfaceReading(
                offering: openQuestion?.actions ?? []
            )
            openQuestion?.readingAtAsk = reading.everyActionIsReachable ? .readable : .notReadable
            guard openQuestion?.readingAtAsk == .readable else {
                logger.error(
                    """
                    a question was put on a panel nobody could answer and was left unwritten: \
                    \(reading.summary, privacy: .public)
                    """
                )
                endOpenQuestion(.neverDelivered)
                record(
                    deferral: .noSurfaceAvailable,
                    kind: .query,
                    subject: warrant.subject.identifier,
                    priorityID: priorityID
                )
                return
            }

        case .popoverBadge:
            // **The badge is an invitation, not a delivery** (focus-kby).
            //
            // The popover is drawn by the composition root's menu-bar refresh, which reads
            // `pendingPopoverQuery` below, and it opens **only when a person clicks the status
            // item**. So a question routed here has reached nobody yet: the reading is taken
            // now, and taken again when the popover actually opens
            // (`popoverPresentedTheQuestion()`). Until then nothing is counted and nothing is
            // written, which is what stops a question burning its one asking behind a click that
            // opens it.
            openQuestion?.readingAtAsk = popoverReadability()
            guard openQuestion?.readingAtAsk == .readable else { return }

        case .menuBar, .notification:
            // A question is never a notification (R-82), and the glyph has no answer affordance.
            // Reaching either would be a routing bug; it is a deferral, never a receipt.
            endOpenQuestion(.neverDelivered)
            record(
                deferral: .noSurfaceAvailable,
                kind: .query,
                subject: warrant.subject.identifier,
                priorityID: priorityID
            )
            return
        }

        deliverQuestion(
            surface: surface,
            warrant: warrant,
            priorityID: priorityID,
            now: surroundings.monotonic
        )
    }

    /// The bookkeeping of a question that has actually reached somebody.
    ///
    /// One function and one call per question, so "delivered" cannot be recorded twice for a
    /// badge question that is asked once and read once.
    private func deliverQuestion(
        surface: NudgeSurface,
        warrant: QueryWarrant,
        priorityID: UUID?,
        now: Duration
    ) {
        deliveredCount += 1
        fatigue.reduce(.delivered(.query), now: now)
        openRecordID = write(
            InterventionEvent(
                kind: .query,
                subject: warrant.subject.identifier,
                surface: surface,
                disposition: .delivered,
                queryReason: warrant.reason
            ),
            priorityID: priorityID
        )
    }

    /// **The popover has opened, and the question is on it** (focus-kby).
    ///
    /// Wired from the composition root, which is the only object that knows the menu bar and the
    /// nudge loop both exist. This is the moment a badge question stops being an invitation and
    /// becomes an asking — and it is the only moment at which one may be counted as delivered.
    func popoverPresentedTheQuestion() {
        guard let question = openQuestion,
              question.surface == .popoverBadge,
              question.readingAtAsk != .readable,
              popoverReadability() == .readable
        else { return }

        openQuestion?.readingAtAsk = .readable
        deliverQuestion(
            surface: .popoverBadge,
            warrant: question.warrant,
            priorityID: question.priorityID,
            now: monotonicClock.elapsed
        )
    }

    private func delivered(surface: NudgeSurface, rung: LadderRung, priorityID: UUID?) {
        let now = monotonicClock.elapsed
        deliveredCount += 1
        ladder.reduce(.delivery(.delivered(surface)), now: now)
        fatigue.reduce(.delivered(.accusation), now: now)
        openRecordID = write(
            InterventionEvent(
                kind: .accusation,
                rung: rung.kind,
                subject: rung.subject ?? "",
                surface: surface,
                disposition: .delivered
            ),
            priorityID: priorityID
        )
    }

    @discardableResult
    private func write(_ event: InterventionEvent, priorityID: UUID?) -> UUID? {
        do {
            return try log.record(event, priorityID: priorityID)
        } catch {
            logger.error(
                "the intervention log refused a write: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    // MARK: - What the person did about it

    /// One click on an accusation surface.
    ///
    /// The write itself is `CorrectionAction.outcome(scope:at:)`'s — one function, one shape of
    /// row, whichever surface the click came from — and everything below is the bookkeeping that
    /// makes the ladder, the fatigue controller and the log agree about what just happened.
    func resolve(_ action: CorrectionAction, snoozeDuration: Duration?) {
        let now = monotonicClock.elapsed
        let scope = openRung.map(\.rung.mandate).flatMap(CorrectionScope.from)

        // **The rung's own key, not the live pointer** (focus-lmo). Read before `apply(…)`,
        // which is the function that hands the outcome to whoever writes it.
        let priorityID = openRung?.priorityID

        let outcome = action.outcome(
            scope: scope,
            at: dateProvider.now,
            snoozeDuration: snoozeDuration
        )
        apply(outcome, action: action, now: now, priorityID: priorityID)

        if let interventionOutcome = Self.outcome(of: action) {
            complete(interventionOutcome)
            fatigue.reduce(.accusationResolved(interventionOutcome), now: now)
        }

        if let deEscalation = action.deEscalation {
            ladder.reduce(.deEscalated(deEscalation), now: now)
        } else {
            // A dismissal is not an answer. It counts towards the backoff, which is what stops
            // the app talking to itself (R-83).
            ladder.reduce(.rungIgnored, now: now)
        }

        // A rung is being answered, not a question — but if one is somehow still open it ends
        // here rather than surviving into the next turn, and it ends as what it is: something the
        // world moved past.
        closeSurfaces(endingAnyQuestionAs: .worldMovedOn)
    }

    /// **A press on a notification's button, always refused** (focus-zrs, U-2).
    ///
    /// A banner is not a window: it does not close when the moment it was about ends, and its
    /// buttons stay live in Notification Centre for as long as the person leaves it there. So the
    /// only honest question to ask of one is *which delivery is this?* — and the only honest
    /// answer to a delivery this loop is no longer holding is to refuse it.
    ///
    /// Refused rather than re-interpreted: there is no correct thing to do with a correction aimed
    /// at a rung that is over. Obeying it closed whatever was on screen instead — measured turning
    /// a live question's `query/delivered/nil` row into `query/delivered/corrected` and taking the
    /// panel away, which records an answer the person never gave and loses the one they were about
    /// to.
    ///
    /// Since U-2 **no rung is delivered by notification at all**, so this loop never holds a
    /// notification delivery and every press is refused. It is kept rather than deleted because
    /// the banners themselves outlive the code: somebody upgrading with a recommitment notification
    /// still sitting in Notification Centre can press it, and this is what makes that press
    /// harmless rather than a correction applied to whatever happens to be on screen.
    private func resolveFromNotification(_ response: NudgeNotificationResponse) {
        staleNotificationActions += 1
        logger.error(
            """
            a notification action named a delivery this loop is not holding \
            (\(response.deliveryID, privacy: .public)); it is refused
            """
        )
    }

    /// One click on the question.
    ///
    /// **R-78's atomic transaction**, performed by the ledger: the rule and the immutable
    /// receipt commit together or neither does, so the app is never in the state where it has
    /// learned the answer but forgotten the asking.
    func answer(_ answer: QueryAnswer) {
        defer { closeSurfaces(endingAnyQuestionAs: .answered) }

        // **One guard, because there is one value** (focus-zrs). This was two — the warrant, then
        // `guard let priorityID = openQuestionPriorityID else { return }` inside the `do` — and
        // the second one is where the person's click went when the two readings of the active
        // priority disagreed: dropped in silence, with the `defer` above tidying the panel away.
        // A question that exists knows what commitment it is about, because it cannot be
        // constructed without one.
        guard let question = openQuestion else { return }
        let scope = CorrectionScope.from(question.warrant)
        let now = monotonicClock.elapsed

        do {
            // **The priority the question was asked under, not the one that happens to be
            // active now** (focus-lmo). The task row is fetched *by that identifier*, so the
            // rule the ledger writes in the same transaction is scoped to the commitment the
            // person was answering about.
            let task = try priorities.task(id: question.priorityID)
            let outcome = try ledger.answer(
                answer,
                priorityID: question.priorityID,
                task: task,
                scope: scope,
                reason: question.warrant.reason,
                askedAt: question.askedAt
            )
            if answer == .yesAddIt { correctedSubjects.insert(scope.subject) }
            // The question's own key, so the undo the composition root registers belongs to the
            // same commitment the ledger just wrote the rule under (focus-lmo).
            onCorrection?(outcome, question.priorityID)
        } catch {
            logger.error(
                "the query ledger refused an answer: \(error.localizedDescription, privacy: .public)"
            )
        }

        complete(.answered)
        fatigue.reduce(.queryResolved(answer.outcome), now: now)
    }

    /// Escape, or the panel's close affordance.
    ///
    /// `.declined` for a question — because a person who closed the panel has answered it, and
    /// treating that as "nothing happened" is what makes an app ask again tomorrow — and
    /// `.dismissed` for an accusation, which writes nothing and is allowed to (D-07).
    private func dismissWhateverIsOpen() {
        if openQuestion != nil {
            answer(.notNow)
            return
        }
        resolve(.dismiss, snoozeDuration: nil)
    }

    private func apply(
        _ outcome: CorrectionOutcome,
        action: CorrectionAction,
        now: Duration,
        priorityID: UUID?
    ) {
        switch outcome {
        case .rule(let rule):
            // The subject leaves the accusable set immediately, so nothing gets through the gap
            // between the click and the next classification.
            correctedSubjects.insert(rule.subject)
            onCorrection?(outcome, priorityID)

        case .sessionRule(let rule):
            guard let sessionID = currentSessionID?() else { return }
            // The rung's commitment, not the live one (focus-lmo). `SessionRuleBox` is keyed on
            // the priority as well as the session, so a live read would file "not this time"
            // under a commitment the accusation was never about — and it would be invisible
            // under the one it was.
            sessionRules.insert(rule, forSession: sessionID, priorityID: priorityID)

        case .snooze(let subject, let duration):
            snoozes = snoozes.adding(
                SnoozeState.starting(subject: subject, for: duration, now: now)
            )

        case .returnToTask:
            let target = ReturnToTask.target(anchor: returnAnchor, workspace: workspace)
            ReturnToTask.perform(target, workspace: workspace) { _ in }

        case .pause, .priorityChangeRequested:
            onCorrection?(outcome, priorityID)

        case .ruleAndReceipt, .receiptOnly:
            // Only `QueryLedger.answer(…)` may write these, and it does so atomically. A path
            // that reached one here would be a second writer of the receipt.
            logger.error("a correction produced a receipt outside the ledger's transaction")

        case .nothing:
            break
        }
        _ = action
    }

    /// What a click is recorded as. `nil` for an action with no log outcome of its own.
    private static func outcome(of action: CorrectionAction) -> InterventionOutcome? {
        switch action {
        case .thisIsRelevant: .corrected
        case .notThisTime: .corrected
        case .snooze: .snoozed
        case .changePriority: .priorityChanged
        case .pause: .pausedSession
        case .returnToTask: .returned
        case .dismiss: .dismissed
        }
    }

    /// **A nudge the loop has taken back, in the ledger as well as on the ladder** (R-81,
    /// focus-mfc, U-1).
    ///
    /// `LadderMachine.undeliver(at:)` stops the escalation clock. This stops the **spend**:
    /// `spendsBudget` is `disposition == .delivered`, and both `budget(on:priorityID:)` and
    /// `deliveredCount(kind:on:)` sum on it, so a stranded nudge left as a delivery went on
    /// charging the day's interruption budget for something nobody saw. Under U-1 the budget is
    /// what decides whether the app may speak again at all.
    ///
    /// The row that was written when the nudge went up **becomes** the deferral. One row per
    /// interruption, not two: writing a fresh deferral beside a delivery that is being taken back
    /// would count one attempt twice in every counter e09 renders. A fresh row is written only
    /// when there is no open row to turn — a delivery whose write failed, which is the one case
    /// where the alternative is no record at all.
    private func undeliverOpenRecord(
        kind: InterruptionKind,
        subject: String?,
        priorityID: UUID?
    ) {
        guard withdrawOpenRecord() else {
            record(
                deferral: .noSurfaceAvailable,
                kind: kind,
                subject: subject,
                priorityID: priorityID
            )
            return
        }
        deferredCount += 1
        ladder.reduce(
            .delivery(.deferred(.noSurfaceAvailable)),
            now: monotonicClock.elapsed
        )
    }

    /// Take the open row off the day's spend, and forget it.
    ///
    /// The counterpart of `complete(_:)` for an interruption that ended without ever reaching
    /// anybody. One place, so a path that un-delivers a nudge cannot take it off the ladder and
    /// leave it on the budget.
    ///
    /// - Returns: whether a delivery was actually taken back.
    @discardableResult
    private func withdrawOpenRecord() -> Bool {
        guard let id = openRecordID else { return false }
        openRecordID = nil
        do {
            return try log.withdraw(id)
        } catch {
            logger.error(
                "the intervention log refused a withdrawal: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    private func complete(_ outcome: InterventionOutcome) {
        complete(outcome, recordID: openRecordID)
        openRecordID = nil
    }

    /// Complete one named row, whichever row happens to be open.
    ///
    /// A preemption needs this: its write happens after the accusation has been delivered, and
    /// delivery assigns `openRecordID` to the accusation's row (focus-7w3).
    private func complete(_ outcome: InterventionOutcome, recordID: UUID?) {
        guard let id = recordID else { return }
        do {
            try log.complete(id, outcome: outcome)
        } catch {
            logger.error(
                "the intervention log refused a completion: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Withdraw whatever is on screen because a presentation has claimed the display (R-84).
    ///
    /// **The ladder is not reset.** R-81's corollary is that during a presentation the app is
    /// mute rather than quietly escalating, and that when the presentation ends the ladder
    /// resumes at the rung it never left — so this touches the window and the slot, and nothing
    /// that would cost the person their place in the escalation story.
    ///
    /// An open question is written down as `expired` on the way out. The asking happened, and a
    /// question whose receipt was never written is a question that comes back tomorrow. The slot
    /// is released for the same reason in the other direction: a surface nobody can see must not
    /// hold the one open interruption for the rest of the session.
    private func withdrawForPresentation() {
        // Before the window goes, never after: the reading the ledger needs is a reading of the
        // surface as it was while the question was still on it.
        expireOpenQuestion()
        panel.withdrawForPresentation()
        // The slot is released by these two and by nothing else: it is derived from the question
        // and the rung, so forgetting them **is** giving it back (focus-zrs).
        endOpenQuestion(.worldMovedOn)
        forgetOpenRung()
    }

    // MARK: - The display changed under something that was already up (focus-56y)

    /// **A nudge is placed once; the display it was placed on is not** (focus-56y, U-1, R-81).
    ///
    /// Every reading this loop takes of the panel used to be taken at the show and never again
    /// for an accusation — `accuse` at the guard below `panel.show(…)`, `ask` at the equivalent
    /// one — so a rung was read once, counted delivered, and never revisited. A panel is
    /// deliberately sticky (`hidesOnDeactivate` is `false`, R-89) precisely so it waits for an
    /// answer, which means it is still there when somebody undocks, plugs in a projector, starts
    /// Sidecar or changes resolution. Read in a clean clone: a recommitment placed at 380 × 772 on
    /// 1920 × 1080, then the display became 800 × 600 — AppKit origin y = 600 − 30 − 772 = −202,
    /// with the three snooze spans, Pause and Change priority off the bottom of the screen and the
    /// Snooze label cut through. Five of six actions unreachable, on the one rung that demands an
    /// explicit choice and does not auto-dismiss.
    ///
    /// By the time this runs the panel has already been re-measured and re-placed for the display
    /// that is actually there, which is the repair that matters to the person: most of the time
    /// the nudge simply moves and everything below is a no-op. What is left is the case where the
    /// new display cannot hold it — the actions are behind a scroll, or off the edge — and R-81's
    /// rule applies at this second moment exactly as it does at the show:
    ///
    /// * an **accusation** is un-delivered. The panel goes, the ladder is put back where it stood
    ///   so the escalation clock stops and the same rung is offered again, and the withdrawal is
    ///   written down as a deferral. Under U-1 a rung nobody can answer has not been delivered,
    ///   whether it became unanswerable in the first millisecond or the first minute.
    /// * a **question** is un-asked. Nothing is written — a receipt is immutable and
    ///   `isSettled(…)` is gate 11, so writing one here would spend the app's single licensed
    ///   interruption on a surface that had gone — the slot is given back, and the subject stays
    ///   askable.
    private func displaysChanged() {
        guard panel.isVisible else { return }

        if let question = openQuestion, question.surface == .panel {
            guard currentReadability() != .readable else { return }
            let summary = panel.decisionSurfaceReading(offering: question.actions).summary
            logger.error(
                """
                the display changed under a question and its answers went out of reach; \
                it is un-asked rather than counted: \(summary, privacy: .public)
                """
            )
            endOpenQuestion(.surfaceWentOutOfReach)
            // The delivery is taken off the budget as well as off the screen (focus-mfc), against
            // the question's own key rather than the live pointer (focus-lmo).
            undeliverOpenRecord(
                kind: .query,
                subject: question.warrant.subject.identifier,
                priorityID: question.priorityID
            )
            return
        }

        guard let open = openRung, !open.panelActions.isEmpty else { return }
        let reading = panel.decisionSurfaceReading(offering: open.panelActions)
        guard !reading.everyActionIsReachable else { return }
        logger.error(
            "the display changed under a rung and stranded it: \(reading.summary, privacy: .public)"
        )
        panel.hide()
        // Before the deferral is written, so the record and the ladder agree: the attempt ended
        // as a deferral, and there is no delivery left standing for it to have escalated from.
        //
        // **Both halves of "un-delivered", together** (focus-mfc). `ladder.undeliver` stops the
        // escalation clock; `InterventionLog.withdraw` stops the spend. Without the second one a
        // rung nobody saw kept `disposition == .delivered`, which is exactly what
        // `spendsBudget` reads, so the stranded nudge went on charging the day's interruption
        // budget — and under U-1 the budget is what decides whether the app may speak again.
        ladder.undeliver(at: monotonicClock.elapsed)
        // The rung's own key, not the live pointer (focus-lmo): this row is a statement about
        // the accusation that was stranded, and that accusation was about one commitment.
        undeliverOpenRecord(
            kind: .accusation,
            subject: open.rung.subject,
            priorityID: open.priorityID
        )
        forgetOpenRung()
    }

    /// Everything comes down, and any open question ends by the named exit.
    private func closeSurfaces(endingAnyQuestionAs exit: QuestionExit) {
        endOpenQuestion(exit)
        panel.hide()
        forgetOpenRung()
    }

    /// **The one door out of an open question** (focus-v0u).
    ///
    /// Three things have to happen when a question ends — the record, the slot, and the
    /// **surface** — and five consecutive rounds of this epic each found a different exit that did
    /// two of the three. The record is `recordQuestion(…)`; this is the other two, and it is the
    /// only place in this object that forgets a question.
    ///
    /// The surface clause is the one that was missing. `accuse(…)` used to clear `openWarrant` on
    /// its own line and then touch the panel **on the `.panel` branch alone** — so a question
    /// displaced onto the menu-bar glyph, the popover badge or a notification was left on the
    /// screen, fully drawn and fully clickable, while the host had forgotten it. `answer(_:)`
    /// then hit `guard let warrant = openWarrant else { return }` and dropped the click, and
    /// `defer { closeSurfaces() }` tidied the evidence away. Measured: before `visible=true
    /// reachable=true`, ordinary glyph preemption, after `visible=true reachable=true` and *"every
    /// offered action is reachable"* — the person clicks *"Yes, add it"*, **zero** rules are
    /// written, the receipt says `expired`, and the question is asked again. Every earlier finding
    /// in this epic was the app silencing itself; this one is the app ignoring the person and
    /// asking again, which is U-1's repeat-asking clause broken from the other side.
    ///
    /// Since U-2 there is no exit that hands its surface to somebody else in the same turn: an
    /// accusation can no longer displace a question, so **every** ending takes the question's
    /// surface down. The `replacedOn:` parameter that used to carry the accusation's route went
    /// with the mechanism.
    private func endOpenQuestion(_ exit: QuestionExit) {
        guard let question = openQuestion else { return }
        let surface = question.surface

        // One assignment, because the question is one value. It used to be six lines, and the
        // whole of this round's defect A was that a path could take some of them and not others —
        // or, worse, that one of them was `nil` from the beginning (focus-zrs).
        openQuestion = nil

        switch surface {
        case .panel:
            panel.hide()
        case .popoverBadge:
            // `pendingPopoverQuery` reads `openWarrant`, which is now `nil` — but the popover on
            // screen is an `NSHostingController` built from the presentation the menu bar was
            // last handed, and it does not rebuild itself. The composition root is the only
            // object that knows the menu bar and the nudge loop both exist, so it redraws.
            onQuestionSurfacesChanged?()
        case .menuBar, .notification, nil:
            // Neither can carry a question; reaching one is a routing bug that `ask(…)` already
            // records as a deferral. There is nothing on screen to take down.
            break
        }

        // **The slot is derived, so forgetting the question above has already released it**
        // (focus-zrs). Every exit releases it now — the one that did not was `preempted`, and it
        // is gone (U-2) — so this is a statement with no remaining exception.
        assert(
            openQuestion == nil,
            "a question ended by \(exit.rawValue) and is somehow still open"
        )
    }

    /// Forget the rung on the surface, the corrections it was offering, and the notification
    /// delivery it went out on.
    ///
    /// One assignment, for the reason `endOpenQuestion(_:)` is one: a reading taken
    /// against a stale action list is a reading of a nudge nobody is looking at, and a delivery
    /// token that outlived its rung is a banner whose buttons still work.
    private func forgetOpenRung() {
        openRung = nil
    }

    /// **A question the person can still see and answer that this host has forgotten** — and it
    /// is always empty (focus-v0u).
    ///
    /// The invariant `endOpenQuestion(_:)` exists to keep, stated as a reading rather
    /// than as a comment so the unit lane can drive every exit and the self-check can report it.
    /// A non-empty answer is the defect itself: a live panel or an open popover offering three
    /// answers that `answer(_:)` will drop in a `guard`, and a question that will therefore be
    /// asked again.
    var orphanedQuestionSurfaces: [NudgeSurface] {
        guard openQuestion == nil else { return [] }
        var orphans: [NudgeSurface] = []
        if panel.isVisible, panel.showing == .question { orphans.append(.panel) }
        if menuBar.isShowingQuery { orphans.append(.popoverBadge) }
        return orphans
    }

    /// Wired by the composition root, which is the only object that knows the menu bar and the
    /// nudge loop both exist. Called when a question leaves a menu-bar surface, because the
    /// popover on screen is a hosting controller built from the presentation the menu bar was
    /// last handed and does not rebuild itself.
    var onQuestionSurfacesChanged: (@MainActor () -> Void)?

    // MARK: - Transitions that end everything

    /// The session ended. Both fatigue runs die with it, the ladder resets, and every snooze and
    /// correction goes with them — because all three are statements about a session that is over.
    func sessionEnded() {
        expireOpenQuestion()
        let now = monotonicClock.elapsed
        fatigue.reduce(.sessionEnded, now: now)
        ladder.reduce(.deEscalated(.sessionEnded), now: now)
        clearSessionState()
    }

    /// The session left `.focus` — a break, a detour, an interruption, completion.
    func phaseLeftFocus() {
        expireOpenQuestion()
        ladder.reduce(.deEscalated(.phaseLeftFocus), now: monotonicClock.elapsed)
        closeSurfaces(endingAnyQuestionAs: .worldMovedOn)
    }

    /// A different commitment. Every earlier observation is evidence about a different question,
    /// and — because the ledger is keyed on the priority — every question legitimately re-opens.
    func priorityChanged() {
        expireOpenQuestion()
        ladder.reduce(.deEscalated(.priorityChanged), now: monotonicClock.elapsed)
        clearSessionState()
    }

    /// **What the open question's surface can be proven to show, right now** (focus-kby, U-1).
    ///
    /// Per surface, and taken from the surface itself. There is no fallback that answers *yes*
    /// for a surface that has gone: the previous shape did — `guard panel.isVisible else { return
    /// true }` — which meant a question routed to a popover that was never open was "readable"
    /// for its whole life, because a closed popover has `isVisible == false` from beginning to
    /// end. Under default-deny the honest answer when a surface cannot be re-read is
    /// **`unknowable`**, and `QuestionLedgerPolicy` refuses to write on one.
    ///
    /// The question a person actually answered is not lost by that: an answer travels through
    /// `answer(_:)` and `QueryLedger.answer(…)`, which is a different path with a different
    /// end — `.answered`, which always writes.
    private func currentReadability() -> SurfaceReadability {
        switch openQuestion?.surface {
        case .panel:
            guard panel.isVisible else { return .unknowable }
            return panel.decisionSurfaceReading(offering: openQuestion?.actions ?? [])
                .everyActionIsReachable ? .readable : .notReadable
        case .popoverBadge:
            return popoverReadability()
        case .menuBar, .notification, nil:
            return .unknowable
        }
    }

    /// **Whether the popover is open and showing this question** (focus-kby).
    ///
    /// `MenuBarController.isPopoverShown` and `isShowingQuery` are both knowable and were both
    /// unread. A closed popover is `unknowable` rather than `notReadable`: nothing can be
    /// established about a surface that is not on screen, and both answers refuse the write.
    private func popoverReadability() -> SurfaceReadability {
        guard menuBar.isPopoverShown else { return .unknowable }
        return menuBar.isShowingQuery ? .readable : .notReadable
    }

    /// A question that has ended, offered to the ledger.
    ///
    /// The host states the four facts — which surface, what it showed at the ask, what it shows
    /// now, and how the question ended — and `QueryLedger.recordResolution(…)` decides. The
    /// decision is `QuestionLedgerPolicy`'s, in `FocusCore`, where a test can instantiate it;
    /// this function has no rule of its own to get wrong.
    ///
    /// - Returns: whether a receipt was written.
    @discardableResult
    /// - Parameters:
    ///   - askedAt, surface, readingAtAsk, readingNow: defaulted to the open question's own,
    ///     which is what every caller wants **except** a preemption. A preemption's write happens
    ///     after the accusation has taken the surface, so its four readings are captured at the
    ///     moment of displacement and passed in; re-reading them there would be reading the
    ///     accusation and answering `notReadable` for a question the person could see perfectly
    ///     well (focus-7w3).
    private func recordQuestion(
        subjectKind: RuleSubjectKind,
        subject: String,
        reason: QueryableUncertainty,
        outcome: AskedQuestionOutcome,
        ending: QuestionEnding,
        priorityID: UUID,
        askedAt: Date? = nil,
        surface: NudgeSurface? = nil,
        readingAtAsk: SurfaceReadability? = nil,
        readingNow: SurfaceReadability? = nil
    ) -> Bool {
        do {
            let action = try ledger.recordResolution(
                priorityID: priorityID,
                subjectKind: subjectKind,
                subject: subject,
                reason: reason,
                outcome: outcome,
                askedAt: askedAt ?? openQuestion?.askedAt,
                surface: surface ?? openQuestion?.surface,
                readingAtAsk: readingAtAsk ?? openQuestion?.readingAtAsk ?? .unknowable,
                readingNow: readingNow ?? currentReadability(),
                ending: ending
            )
            if case .stayAskable(let reason) = action {
                logger.error(
                    """
                    a question nobody could be shown was not written down \
                    (\(reason.rawValue, privacy: .public)), so it stays askable
                    """
                )
                return false
            }
            return true
        } catch {
            logger.error(
                "the question could not be recorded: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    /// A question that was on screen when the world changed under it.
    ///
    /// Written down as `expired` rather than left unrecorded: the asking happened, and the
    /// record of the day should say so.
    ///
    /// **And written down is not settled** (focus-qds, U-1). This is the path a break, a session
    /// ending, a new commitment and a projector all travel down, and until this epic it had no
    /// callers at all. Wiring the three lifecycle callbacks turned it into the most ordinary way
    /// a question ends — so if an `expired` receipt silenced its subject, *taking a break* would
    /// permanently answer a question the person never saw the end of, and gate 11 would never let
    /// the app ask again for the life of the commitment. `QuestionEnding.expired` therefore does
    /// not settle, `AskedQuestionOutcome.expired` does not settle, and `isSettled(…)` reads the
    /// stored outcome. The question comes back.
    ///
    /// **Unless the asking did not happen.** `QuestionLedgerPolicy` still refuses to write
    /// anything at all about a question that never reached a readable surface (focus-kby); that
    /// row would be a fact about an asking nobody experienced.
    private func expireOpenQuestion() {
        // The ask-time key, for the reason `OpenQuestion` carries one: this is the path a priority
        // change itself travels down, so reading the live pointer here would write the receipt
        // against the commitment that has just replaced the one asked about (focus-lmo).
        guard let question = openQuestion else { return }
        let warrant = question.warrant
        let priorityID = question.priorityID
        recordQuestion(
            subjectKind: warrant.subject.kind,
            subject: warrant.subject.identifier,
            reason: warrant.reason,
            outcome: .expired,
            ending: .expired,
            priorityID: priorityID
        )
    }

    private func clearSessionState() {
        snoozes = .none
        correctedSubjects = []
        closeSurfaces(endingAnyQuestionAs: .worldMovedOn)
    }

    // MARK: - What the surfaces and the self-check read

    /// The question waiting in the menu-bar popover, when reduced interruption or the
    /// `silentVisual` deck routed one there (R-92). `nil` the rest of the time.
    var pendingPopoverQuery: QueryPresentation? {
        // **The surface the router chose, not "the panel is not up"** (focus-kby). The old test
        // was the second one, so a question the panel had just deferred appeared in the popover
        // as though it had been routed there — and would have been read as a badge question by
        // anything that asked.
        guard let question = openQuestion, question.surface == .popoverBadge else { return nil }
        return QueryPresentation(
            voice: preferences.voice,
            // The commitment the app is acting under, from the one place that states it. It was
            // `activeIntent()` — a third read of the priority store, which could name a different
            // commitment from the one the receipt will be keyed to (focus-zrs).
            task: activeCommitment()?.intent ?? "",
            subject: question.warrant.subject.identifier,
            reason: question.warrant.reason,
            dwelled: question.warrant.dwelled
        )
    }

    /// What is snoozed right now, for the popover's list and its countdowns.
    func activeSnoozes() -> [MenuBarSnooze] {
        let now = monotonicClock.elapsed
        return snoozes.active(at: now).map {
            MenuBarSnooze(subject: $0.subject, remaining: $0.remaining(at: now))
        }
    }

    /// Cancel one subject's snooze from the popover.
    func cancelSnooze(subject: String) {
        snoozes = snoozes.cancelling(subject: subject)
    }

    // MARK: - The keyboard's own route to the economy (F-145, F-81)

    /// One of the four View-menu verbs.
    ///
    /// Every one of them is an action a person can already take by clicking, and F-145's rule is
    /// that a click is never the *only* way. The two that answer a nudge go through
    /// `resolve(_:snoozeDuration:)` — the same function the buttons call — so a key equivalent
    /// and a click are one code path rather than two implementations of one idea.
    func perform(_ command: PriorityCommand) {
        switch command {
        case .thisIsRelevant:
            guard openRung != nil else { return }
            resolve(.thisIsRelevant, snoozeDuration: nil)
        case .snoozeNudge:
            guard openRung != nil else { return }
            // The shortest span, because a menu item cannot offer three without three items and
            // the shortest is the least presumptuous of them.
            resolve(.snooze, snoozeDuration: InterventionPolicy.snoozeDurations.first)
        case .hideOverlays:
            hideOverlays()
        case .showMenuBar:
            menuBar.togglePopover()
        case .newPriority, .completePriority, .addFilesToContext,
             .startSession, .pauseSession, .completeSession, .pauseSensing:
            break
        }
    }

    /// **F-81's one command: take every overlay off the screen, and write nothing.**
    ///
    /// Not a dismissal and not an answer. The panel goes away, the slot is released so the next
    /// judgement is not withheld against a surface nobody can see any more, and **no receipt and
    /// no rule is written** — because the person asked for their screen back, not to tell the
    /// app anything. A question hidden this way is still unanswered and will be offered again;
    /// that is the honest reading of "hide", and it is why this is not `.dismiss`.
    func hideOverlays() {
        panel.hide()
        menuBar.closePopover()
        // **The open question goes with the screen it was on** (focus-kby, F-81).
        //
        // It used to survive: the panel went away and the warrant and its readability stayed,
        // so the next thing to end a question — a session end, a phase change — read the
        // *previous* question's reading against a surface that had been gone for an hour, and
        // the reading it read was the `isVisible` fallback's cheerful `true`. Nothing is written
        // here, which is the whole of F-81: the person asked for their screen back, not to tell
        // the app anything, so the question is still unanswered and will be offered again.
        endOpenQuestion(.worldMovedOn)
        forgetOpenRung()
        openRecordID = nil
    }

    /// The rung the ladder has reached, for the popover.
    var currentRung: LadderRung.Kind? { ladder.state.rung?.kind }

    /// Today's spend, for the settings pane's usage rows.
    ///
    /// Keyed to the same commitment every row it is summing was written against — read from the
    /// surroundings, which is the one statement of it, rather than from a store read of this
    /// host's own (focus-zrs). A budget summed under a different key from the rows it is about is
    /// a cap that silently stops applying.
    func todaysUsage() -> InterruptionBudget {
        (try? log.budget(on: log.today, priorityID: activeCommitment()?.id)) ?? .empty
    }

    /// The four grant-free focus readings from the last time the panel was shown (R-89, §4.5).
    var lastPanelReadings: NudgePanelController.FocusReadings? { panel.readingsAfterShow }
    var readingsBeforePanelShow: NudgePanelController.FocusReadings? { panel.readingsBeforeShow }
    var panelProperties: NudgePanelController.PanelProperties { panel.properties }

    /// **Must be zero in every automated run** (§3.F.37). Published here so the self-check does
    /// not have to reach into the notification boundary for it.
    var requestAuthorizationCallCount: Int { notifications.requestAuthorizationCallCount }
    var notificationAuthorisation: NotificationAuthorisation { notifications.authorisation }

    // MARK: - Helpers

    /// **The one statement of the active commitment this host has** (focus-zrs).
    ///
    /// It reads the surroundings closure — the value the composition root builds from
    /// `PriorityHost`, which is the object that owns the projection — rather than opening
    /// `PriorityStore` again. There were three store reads here (`activePriorityID()`,
    /// `activeIntent()`, `activeTask()`), and each of them was a second opinion about the fact
    /// gate 1 had already been decided by.
    ///
    /// Used only where no judgement is in flight — the settings pane's usage rows and the
    /// popover's redraw. Every path that *writes* takes the commitment handed to it by
    /// `consider(_:)`, so a receipt can never be keyed to a reading taken later than the ask.
    private func activeCommitment() -> ActiveCommitment? {
        surroundings?().commitment
    }

    private func accusationPresentation(
        for rung: LadderRung,
        commitment: ActiveCommitment
    ) -> AccusationPresentation {
        let target = ReturnToTask.target(anchor: returnAnchor, workspace: workspace)
        let subject = rung.subject
        return AccusationPresentation(
            rung: rung.kind,
            voice: preferences.voice,
            // The commitment the rung was raised under, carried in — so the sentence on the panel
            // names the task the click will be written against (focus-zrs, focus-lmo).
            task: commitment.intent,
            subject: subject,
            dwelled: rung.mandate.sustainedFor,
            returnTarget: target?.displayName,
            snoozeRemaining: subject.flatMap { snoozes.snooze(for: $0) }?
                .remaining(at: monotonicClock.elapsed)
        )
    }
}
