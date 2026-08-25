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

    /// **Which surface the open question went to, and what that surface could be proven to
    /// show** (focus-kby, U-1).
    ///
    /// Three facts rather than one `Bool`, because the `Bool` was the defect. It was set outside
    /// the `if surface == .panel` branch, so a question routed to the popover badge was marked
    /// presentable having read **nothing** — and the popover opens only when a person clicks it,
    /// so the reading it never took would have been `false`. The router sends questions there on
    /// three ordinary conditions: the `silentVisual` deck, reduced interruption (forced on by
    /// Reduce Motion), and a live microphone or camera — which is to say, anybody on a call.
    ///
    /// Every receipt in `QueryLedger` is immutable and `hasAsked(…)` is gate 11 of the
    /// suppression stack, so a receipt about a question nobody saw does not merely mis-record
    /// history — it permanently silences that question. U-1 licenses the app to interrupt on
    /// `uncertain` precisely because the interruption is one cheap click that teaches it;
    /// spending that click on a surface the person never read is the app burning its licence.
    ///
    /// The reading is **per surface** and is taken by the surface itself:
    ///
    /// | surface | readable means |
    /// |---|---|
    /// | `panel` | on screen, on a display, and every answer in reach — `decisionSurfaceReading` |
    /// | `popoverBadge` | the popover is **open and showing this question** |
    ///
    /// Nothing infers readability from having called `show(…)`, and nothing infers it from
    /// falling through a branch.
    private var openQuestionSurface: NudgeSurface?
    private var openQuestionReadingAtAsk: SurfaceReadability = .unknowable
    /// The answers the open question is offering, by `rawValue`, so the reading taken as it ends
    /// asks about the same set the panel was drawn with.
    private var openQuestionActions: [String] = []

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

            // **R-81 at the level that matters: a rung whose corrections are out of reach was
            // not delivered** (focus-vpu). A live drive read this panel with Pause and Change
            // priority below the clip — the two actions a person most needs when the app is
            // wrong. An accusation you cannot answer back to is the anti-pattern the Court's
            // product boundary forbids, so it is a deferral: the ladder's clock stays stopped,
            // nothing is counted, and the rung is offered again.
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
                return
            }
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
        openQuestionSurface = nil
        openQuestionReadingAtAsk = .unknowable
        openQuestionActions = []
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
        openQuestionSurface = surface
        openQuestionActions = presentation.offeredAnswerIdentifiers

        switch surface {
        case .panel:
            panel.update(content: QueryPanelView(presentation: presentation) { [weak self] answer in
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
            let reading = panel.decisionSurfaceReading(offering: openQuestionActions)
            openQuestionReadingAtAsk = reading.everyActionIsReachable ? .readable : .notReadable
            guard openQuestionReadingAtAsk == .readable else {
                logger.error(
                    """
                    a question was put on a panel nobody could answer and was left unwritten: \
                    \(reading.summary, privacy: .public)
                    """
                )
                panel.hide()
                slot = slot.released()
                forgetOpenQuestion()
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
            openQuestionReadingAtAsk = popoverReadability()
            guard openQuestionReadingAtAsk == .readable else { return }

        case .menuBar, .notification:
            // A question is never a notification (R-82), and the glyph has no answer affordance.
            // Reaching either would be a routing bug; it is a deferral, never a receipt.
            slot = slot.released()
            forgetOpenQuestion()
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
        guard let warrant = openWarrant,
              openQuestionSurface == .popoverBadge,
              openQuestionReadingAtAsk != .readable,
              popoverReadability() == .readable
        else { return }

        openQuestionReadingAtAsk = .readable
        deliverQuestion(
            surface: .popoverBadge,
            warrant: warrant,
            priorityID: activePriorityID(),
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
        slot = slot.released()
        forgetOpenQuestion()
        openRung = nil
    }

    private func closeSurfaces() {
        panel.hide()
        slot = slot.released()
        forgetOpenQuestion()
        openRung = nil
    }

    /// Forget the open question **without writing anything**.
    ///
    /// One place, so that every path which ends a question either writes through
    /// `recordQuestion(…)` first or writes nothing at all — and none of them can leave a reading
    /// behind for the next question to inherit.
    private func forgetOpenQuestion() {
        openWarrant = nil
        openWarrantAskedAt = nil
        openQuestionSurface = nil
        openQuestionReadingAtAsk = .unknowable
        openQuestionActions = []
    }

    /// A question closed to make room for an accusation (R-84a).
    private func close(_ preempted: PreemptedQuery) {
        guard let priorityID = activePriorityID() else { return }
        // A question the person could never read is not a question that was asked, so
        // preempting it costs nothing and writes nothing (focus-kby). The ledger decides that,
        // not this host: it is handed the two readings and the end path, and it writes or
        // refuses. The surface is left either way, because the accusation needs it.
        let wrote = recordQuestion(
            subjectKind: preempted.warrant.subject.kind,
            subject: preempted.warrant.subject.identifier,
            reason: preempted.warrant.reason,
            outcome: preempted.outcome,
            ending: .preempted,
            priorityID: priorityID
        )
        complete(.dismissed)
        guard wrote else { return }
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
        switch openQuestionSurface {
        case .panel:
            guard panel.isVisible else { return .unknowable }
            return panel.decisionSurfaceReading(offering: openQuestionActions)
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
    private func recordQuestion(
        subjectKind: RuleSubjectKind,
        subject: String,
        reason: QueryableUncertainty,
        outcome: AskedQuestionOutcome,
        ending: QuestionEnding,
        priorityID: UUID
    ) -> Bool {
        do {
            let action = try ledger.recordResolution(
                priorityID: priorityID,
                subjectKind: subjectKind,
                subject: subject,
                reason: reason,
                outcome: outcome,
                askedAt: openWarrantAskedAt,
                surface: openQuestionSurface,
                readingAtAsk: openQuestionReadingAtAsk,
                readingNow: currentReadability(),
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
    /// Written down as `expired` rather than left unrecorded: the asking happened, and a
    /// question whose receipt was never written is a question that comes back.
    ///
    /// **Unless the asking did not happen.** A receipt is immutable and `hasAsked(…)` is gate 11,
    /// so writing one about a question that never reached a readable surface would silence that
    /// question for the life of the priority — the app spending its single licensed interruption
    /// on a surface nobody saw (focus-kby). That question is left unwritten, on purpose, and
    /// comes back.
    private func expireOpenQuestion() {
        guard let warrant = openWarrant, let priorityID = activePriorityID() else { return }
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
        closeSurfaces()
    }

    // MARK: - What the surfaces and the self-check read

    /// The question waiting in the menu-bar popover, when reduced interruption or the
    /// `silentVisual` deck routed one there (R-92). `nil` the rest of the time.
    var pendingPopoverQuery: QueryPresentation? {
        // **The surface the router chose, not "the panel is not up"** (focus-kby). The old test
        // was the second one, so a question the panel had just deferred appeared in the popover
        // as though it had been routed there — and would have been read as a badge question by
        // anything that asked.
        guard let warrant = openWarrant, openQuestionSurface == .popoverBadge else { return nil }
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
        slot = slot.released()
        // **The open question goes with the screen it was on** (focus-kby, F-81).
        //
        // It used to survive: the panel went away and the warrant and its readability stayed,
        // so the next thing to end a question — a session end, a phase change — read the
        // *previous* question's reading against a surface that had been gone for an hour, and
        // the reading it read was the `isVisible` fallback's cheerful `true`. Nothing is written
        // here, which is the whole of F-81: the person asked for their screen back, not to tell
        // the app anything, so the question is still unanswered and will be offered again.
        forgetOpenQuestion()
        openRung = nil
        openRecordID = nil
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
