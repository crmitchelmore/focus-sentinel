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

    /// What the person set. Re-read whenever the settings pane changes something.
    var preferences = NudgePreferences()

    /// A correction that has to be performed somewhere else — a persisted rule (which goes
    /// through `PriorityHost`, so it lands in the Rules pane with an undo registered), a pause
    /// (which goes through e03's own session machine), or e02's confirm surface.
    ///
    /// The host never writes a rule itself. `CorrectionAction.outcome(scope:at:)` decides
    /// **what** one click writes and this closure performs it, so there is still exactly one
    /// place a click becomes a write (R-86).
    var onCorrection: (@MainActor (CorrectionOutcome) -> Void)?

    /// The session a session-lived rule belongs to. `nil` when there is no open session, in
    /// which case "Not this time" has no session to die with and is not offered.
    var currentSessionID: (@MainActor () -> UUID?)?

    // MARK: - Session state

    private(set) var ladder = LadderMachine()
    private(set) var fatigue = FatigueController()
    private(set) var slot = InterruptionSlot.open
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
    private(set) var deliveredCount = 0
    private(set) var deferredCount = 0

    /// The log row for whatever is on screen, so the person's answer can complete it.
    private var openRecordID: UUID?
    private var openWarrant: QueryWarrant?
    private var openWarrantAskedAt: Date?
    private var openRung: LadderRung?

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
        notifications.onAction = { [weak self] action in
            self?.resolve(action.correction, snoozeDuration: nil)
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

        // A snooze that has lifted is not a snooze. Pruning here rather than inside the decider
        // keeps the decider a pure function of the values it is handed.
        snoozes = snoozes.pruned(at: surroundings.monotonic)
        rememberAnchor(judgement)

        let subject = NudgeDecider.querySubject(for: judgement)
        let priorityID = activePriorityID()

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

        perform(decision, judgement: judgement, surroundings: surroundings, priorityID: priorityID)
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
        priorityID: UUID?
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
                priorityID: priorityID
            )

        case .accuse(let rung, let route, let preempted):
            accuse(
                rung: rung,
                route: route,
                preempted: preempted,
                surroundings: surroundings,
                priorityID: priorityID
            )

        case .ask(let warrant, let route):
            ask(warrant: warrant, route: route, surroundings: surroundings, priorityID: priorityID)
        }
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

    private func accuse(
        rung: LadderRung,
        route: SurfaceRoute,
        preempted: PreemptedQuery?,
        surroundings: NudgeSurroundings,
        priorityID: UUID?
    ) {
        // The question that was on screen is **closed**, not dropped: its receipt is written so
        // it is never asked again. Losing the asking because something more urgent happened is
        // exactly the bug never-ask-twice exists to prevent, and it would be invisible.
        if let preempted { close(preempted) }

        slot = slot.offering(rung).slot ?? slot
        openRung = rung
        openWarrant = nil
        ladder.offer(at: surroundings.monotonic, budgetPermits: true)

        let presentation = accusationPresentation(for: rung)
        guard let surface = route.surface else {
            record(
                deferral: route.deferralReason ?? .noSurfaceAvailable,
                kind: .accusation,
                subject: rung.subject,
                priorityID: priorityID
            )
            return
        }

        switch surface {
        case .menuBar, .popoverBadge:
            // The glyph and the badge are drawn by the composition root's own menu-bar refresh;
            // nothing here has to raise a window for them.
            delivered(surface: surface, rung: rung, priorityID: priorityID)

        case .panel:
            panel.update(content: AccusationPanelView(presentation: presentation) { [weak self] action, span in
                self?.resolve(action, snoozeDuration: span)
            })
            panel.show(
                presentationIsClear: !surroundings.presentation.suppressesOverlays,
                announcement: presentation.announcement()
            )
            delivered(surface: .panel, rung: rung, priorityID: priorityID)

        case .notification:
            notifications.deliver(
                presentation,
                surroundings: NotificationSurroundings(
                    presentation: surroundings.presentation,
                    media: surroundings.media,
                    reducedInterruption: preferences.reducedInterruption,
                    menuBarVisible: surroundings.menuBarVisible
                )
            ) { [weak self] recorded, demotedTo in
                guard let self else { return }
                switch recorded {
                case .delivered:
                    self.delivered(surface: .notification, rung: rung, priorityID: priorityID)
                case .deferred(let reason):
                    // **A route change, not a log line.** The failed attempt is a deferral, and
                    // the rung is re-offered on the surface the router demoted it to.
                    self.record(
                        deferral: reason, kind: .accusation, subject: rung.subject,
                        priorityID: priorityID
                    )
                    self.accuse(
                        rung: rung,
                        route: demotedTo,
                        preempted: nil,
                        surroundings: surroundings,
                        priorityID: priorityID
                    )
                case .suppressed:
                    break
                }
            }
        }
    }

    private func ask(
        warrant: QueryWarrant,
        route: SurfaceRoute,
        surroundings: NudgeSurroundings,
        priorityID: UUID?
    ) {
        guard case .admitted(let taken, _) = slot.offering(warrant) else { return }
        slot = taken
        openWarrant = warrant
        openWarrantAskedAt = dateProvider.now
        openRung = nil

        let presentation = QueryPresentation(
            voice: preferences.voice,
            task: activeIntent() ?? "",
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

        if surface == .panel {
            panel.update(content: QueryPanelView(presentation: presentation) { [weak self] answer in
                self?.answer(answer)
            })
            panel.show(
                presentationIsClear: !surroundings.presentation.suppressesOverlays,
                announcement: presentation.announcement()
            )
        }
        // A `popoverBadge` question is drawn by the menu-bar refresh, which reads
        // `pendingPopoverQuery` below. A question is never a notification (R-82).

        deliveredCount += 1
        fatigue.reduce(.delivered(.query), now: surroundings.monotonic)
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
        let scope = openRung.map(\.mandate).flatMap(CorrectionScope.from)

        let outcome = action.outcome(
            scope: scope,
            at: dateProvider.now,
            snoozeDuration: snoozeDuration
        )
        apply(outcome, action: action, now: now)

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

        closeSurfaces()
    }

    /// One click on the question.
    ///
    /// **R-78's atomic transaction**, performed by the ledger: the rule and the immutable
    /// receipt commit together or neither does, so the app is never in the state where it has
    /// learned the answer but forgotten the asking.
    func answer(_ answer: QueryAnswer) {
        defer { closeSurfaces() }

        guard let warrant = openWarrant else { return }
        let scope = CorrectionScope.from(warrant)
        let now = monotonicClock.elapsed

        do {
            let task = try priorities.activeTask()
            guard let priorityID = task?.id else { return }
            let outcome = try ledger.answer(
                answer,
                priorityID: priorityID,
                task: task,
                scope: scope,
                reason: warrant.reason,
                askedAt: openWarrantAskedAt
            )
            if answer == .yesAddIt { correctedSubjects.insert(scope.subject) }
            onCorrection?(outcome)
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
        if openWarrant != nil {
            answer(.notNow)
            return
        }
        resolve(.dismiss, snoozeDuration: nil)
    }

    private func apply(_ outcome: CorrectionOutcome, action: CorrectionAction, now: Duration) {
        switch outcome {
        case .rule(let rule):
            // The subject leaves the accusable set immediately, so nothing gets through the gap
            // between the click and the next classification.
            correctedSubjects.insert(rule.subject)
            onCorrection?(outcome)

        case .sessionRule(let rule):
            guard let sessionID = currentSessionID?() else { return }
            sessionRules.insert(rule, forSession: sessionID, priorityID: activePriorityID())

        case .snooze(let subject, let duration):
            snoozes = snoozes.adding(
                SnoozeState.starting(subject: subject, for: duration, now: now)
            )

        case .returnToTask:
            let target = ReturnToTask.target(anchor: returnAnchor, workspace: workspace)
            ReturnToTask.perform(target, workspace: workspace) { _ in }

        case .pause, .priorityChangeRequested:
            onCorrection?(outcome)

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

    private func complete(_ outcome: InterventionOutcome) {
        guard let id = openRecordID else { return }
        do {
            try log.complete(id, outcome: outcome)
        } catch {
            logger.error(
                "the intervention log refused a completion: \(error.localizedDescription, privacy: .public)"
            )
        }
        openRecordID = nil
    }

    private func closeSurfaces() {
        panel.hide()
        slot = slot.released()
        openWarrant = nil
        openWarrantAskedAt = nil
        openRung = nil
    }

    /// A question closed to make room for an accusation (R-84a).
    private func close(_ preempted: PreemptedQuery) {
        guard let priorityID = activePriorityID() else { return }
        do {
            try ledger.record(
                priorityID: priorityID,
                subjectKind: preempted.warrant.subject.kind,
                subject: preempted.warrant.subject.identifier,
                reason: preempted.warrant.reason,
                outcome: preempted.outcome,
                askedAt: openWarrantAskedAt
            )
        } catch {
            logger.error(
                "the preempted question could not be recorded: \(error.localizedDescription, privacy: .public)"
            )
        }
        complete(.dismissed)
        fatigue.reduce(.queryResolved(preempted.outcome), now: monotonicClock.elapsed)
    }

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
        closeSurfaces()
    }

    /// A different commitment. Every earlier observation is evidence about a different question,
    /// and — because the ledger is keyed on the priority — every question legitimately re-opens.
    func priorityChanged() {
        expireOpenQuestion()
        ladder.reduce(.deEscalated(.priorityChanged), now: monotonicClock.elapsed)
        clearSessionState()
    }

    /// A question that was on screen when the world changed under it.
    ///
    /// Written down as `expired` rather than left unrecorded: the asking happened, and a
    /// question whose receipt was never written is a question that comes back.
    private func expireOpenQuestion() {
        guard let warrant = openWarrant, let priorityID = activePriorityID() else { return }
        try? ledger.record(
            priorityID: priorityID,
            subjectKind: warrant.subject.kind,
            subject: warrant.subject.identifier,
            reason: warrant.reason,
            outcome: .expired,
            askedAt: openWarrantAskedAt
        )
    }

    private func clearSessionState() {
        snoozes = .none
        correctedSubjects = []
        closeSurfaces()
    }

    // MARK: - What the surfaces and the self-check read

    /// The question waiting in the menu-bar popover, when reduced interruption or the
    /// `silentVisual` deck routed one there (R-92). `nil` the rest of the time.
    var pendingPopoverQuery: QueryPresentation? {
        guard let warrant = openWarrant, !panel.isVisible else { return nil }
        return QueryPresentation(
            voice: preferences.voice,
            task: activeIntent() ?? "",
            subject: warrant.subject.identifier,
            reason: warrant.reason,
            dwelled: warrant.dwelled
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

    /// The rung the ladder has reached, for the popover.
    var currentRung: LadderRung.Kind? { ladder.state.rung?.kind }

    /// Today's spend, for the settings pane's usage rows.
    func todaysUsage() -> InterruptionBudget {
        (try? log.budget(on: log.today, priorityID: activePriorityID())) ?? .empty
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

    private func activePriorityID() -> UUID? {
        activeTask()?.id
    }

    private func activeIntent() -> String? {
        activeTask()?.intent
    }

    private func activeTask() -> FocusSchemaV3.PriorityTask? {
        do {
            return try priorities.activeTask()
        } catch {
            logger.error(
                "the priority store refused a read: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private func accusationPresentation(for rung: LadderRung) -> AccusationPresentation {
        let target = ReturnToTask.target(anchor: returnAnchor, workspace: workspace)
        let subject = rung.subject
        return AccusationPresentation(
            rung: rung.kind,
            voice: preferences.voice,
            task: activeIntent() ?? "",
            subject: subject,
            dwelled: rung.mandate.sustainedFor,
            returnTarget: target?.displayName,
            snoozeRemaining: subject.flatMap { snoozes.snooze(for: $0) }?
                .remaining(at: monotonicClock.elapsed)
        )
    }
}
