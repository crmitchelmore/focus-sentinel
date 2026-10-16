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
    /// **What the app calls the thing it is nudging about** (focus-ebv).
    ///
    /// Built from the same `ReturnWorkspace` the return action uses, because the panel saying
    /// "Back to Pages" three lines under "com.apple.Safari" was one object asking two different
    /// questions about the same kind of thing. It memoises, so a sticky panel and a running
    /// snooze keep the name they were raised with even after the application quits.
    private let naming: SubjectNaming
    private let monotonicClock: any MonotonicClock
    private let dateProvider: any DateProvider
    private let logger = Logger(
        subsystem: FocusStore.bundleIdentifier,
        category: "NudgeHost"
    )

    /// **One turn of this loop, the seam at the end of it, and the baselines it leaves**
    /// (focus-my0, focus-r28.1, focus-tzj.6).
    ///
    /// Every door into this object from outside — a judgement, a click, a redraw, a phase change,
    /// the display changing — runs inside `proofs.run { … }`, and nothing is charged until the
    /// outermost one ends. `SurfaceProofAccountant` holds that turn, what has asked to be proven
    /// at the end of it, and what the surfaces were saying the last time they stopped moving; the
    /// two things it cannot hold are the question and the rung themselves, which is why the proof
    /// of each is a closure back into this object, wired once in `init`.
    private let proofs = SurfaceProofAccountant()

    // MARK: - What the composition root wires in

    /// Everything the world is doing, gathered by the root from e03's sensing types.
    ///
    /// A closure rather than a reference to `SensingHost`, for the reason `RelevanceHost`'s
    /// session-rule closure is one: the only facts this host needs are the ones
    /// `NudgeSurroundings` names, and a reference to the whole host would be a licence to reach
    /// for the rest of it.
    var surroundings: (@MainActor () -> NudgeSurroundings)?

    /// **What the person chose** — the two things, and only the two things, they set in a pane.
    ///
    /// It carried a third, the notification authorisation, and it carried it twice over two
    /// rounds. First as a stored **copy** (focus-zrs): `AppComposition` wrote it in at launch,
    /// `NotificationDelivery.deliver(…)` moved its own to `.denied` on a failure, and nothing told
    /// the copy — so the router went on aiming at a channel the boundary knew was shut while the
    /// Settings pane drew `.denied`. That was repaired by deriving it. Then as a derived value
    /// nobody read (focus-wy0): U-2 took the notification rung out of the ladder, so
    /// `SurfaceRouter` stopped consulting it, and this went on computing it for a router that
    /// discarded it. The field is gone rather than derived, because a value carried to no reader
    /// is the shape both defects lived in.
    var preferences: NudgePreferences {
        NudgePreferences(
            voice: chosenVoice,
            // **Either the person asked for it or the Mac did** (focus-w7v). `||`, not an
            // assignment, and the direction matters both ways: the system cannot un-choose what
            // the person chose, and the person cannot switch off what Reduce Motion turned on —
            // which is what makes `reducedInterruptionIsForced` an honest thing for the pane to
            // draw a disabled switch from rather than a claim about a setting they could beat.
            reducedInterruption: chosenReducedInterruption || systemForcesReducedInterruption
        )
    }

    private var chosenVoice: NudgeVoice = .standard
    private var chosenReducedInterruption = false

    /// **The window the person set**, and the whole of what gate 8 evaluates (focus-z7g).
    ///
    /// It is not part of `preferences` because it is not a preference the *decider* consults: it
    /// is a fact about the surroundings, evaluated against the wall clock and an injected
    /// calendar by `SuppressionStack`'s eighth gate, exactly as a running microphone or a
    /// full-screen presentation is. The composition root reads it here and puts it in the
    /// `NudgeSurroundings` it builds, so there is one statement of the window and the pane and
    /// the gate cannot hold two.
    /// **Every policy dial the loop decides with** (focus-exdi). Handed in by the composition
    /// root from the store at launch and on every change; the shipped constants until then.
    var tunings: PolicyTunings = .shipped

    private var chosenQuietHours: QuietHoursWindow? = InterventionPolicy.quietHoursDefault

    /// What gate 8 is given. `QuietHours.off` until the person sets a window, which is R-85's
    /// shipped default and a real answer rather than an absent one.
    var quietHours: QuietHours { QuietHours(window: chosenQuietHours) }

    /// **Whether macOS Reduce Motion is what turned reduced interruption on** (focus-w7v).
    ///
    /// Read by the Intervention pane through `AppComposition.interventionSettings`, which is
    /// what puts the switch in its disabled state and draws *"Reduce Motion is on, so this stays
    /// on."* — a string that shipped in the catalog and could not be reached, because nothing
    /// ever set this.
    private(set) var systemForcesReducedInterruption = false

    /// **Exactly what the person set**, and nothing the Mac decided for them (focus-40i).
    ///
    /// This is what the store holds. `preferences` is what the *loop* runs on, and its
    /// `reducedInterruption` is the person's choice **or** what Reduce Motion forces — writing
    /// that down would mean somebody who turns Reduce Motion off later is left holding a setting
    /// they never chose, which is the "two writers, one field" defect focus-zrs removed from the
    /// notification authorisation and focus-w7v kept out of this flag.
    var chosen: InterventionPreferences {
        InterventionPreferences(
            voice: chosenVoice,
            reducedInterruption: chosenReducedInterruption,
            quietHours: chosenQuietHours
        )
    }

    /// Everything the person set, restored in one call at launch.
    func adopt(_ preferences: InterventionPreferences) {
        chosenVoice = preferences.voice
        chosenReducedInterruption = preferences.reducedInterruption
        chosenQuietHours = preferences.quietHours
    }

    /// The three things the Intervention pane can set. Two of them are `preferences`; the third
    /// is the window gate 8 evaluates.
    func choose(voice: NudgeVoice) { chosenVoice = voice }
    func choose(reducedInterruption: Bool) { chosenReducedInterruption = reducedInterruption }
    func choose(quietHours: QuietHoursWindow?) { chosenQuietHours = quietHours }

    /// **The Mac's Reduce Motion setting, observed** (focus-w7v).
    ///
    /// Six places in this repository asserted that `AppearanceObserver` forced
    /// `reducedInterruption` on under Reduce Motion, and nothing did: the only shipping caller of
    /// `choose(reducedInterruption:)` was the pane's own checkbox, and `appearanceChanged(_:)`
    /// re-themed three surfaces and never reached this host. So a person who had told macOS they
    /// wanted less motion got a full animated `NSPanel`, and the app shipped a sentence saying
    /// otherwise.
    ///
    /// Wired rather than deleted, and the deciding fact is that wiring costs **nothing**:
    /// `NSWorkspace.accessibilityDisplayShouldReduceMotion` is readable with no TCC grant of any
    /// kind (the zero-grant doctrine is untouched), the copy becomes true instead of being
    /// removed, and the people it changes the product for are precisely the people who asked the
    /// system for calm. Deleting the claims would have cost the same edit and left them with the
    /// panel.
    ///
    /// Separate from `choose(reducedInterruption:)` on purpose. One field for both would let the
    /// next appearance notification silently discard a preference the person set in the pane —
    /// the same "two writers, one field" shape `focus-zrs` removed from the notification
    /// authorisation.
    func observe(reduceMotion: Bool) { systemForcesReducedInterruption = reduceMotion }

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
    /// `InterventionLog.budget(on:priorityID:)`, folded from the delivered rows that
    /// `InterruptionCharge` says actually said something, and it is the only figure any cap is
    /// decided by (R-83). Not `spendsBudget`, which this comment named until focus-d6r and which
    /// is `disposition == .delivered`: a glyph landing is a delivery and interrupts nobody.
    ///
    /// They part company at exactly one place, deliberately: `undeliverRecord(…)` takes a
    /// delivery off the budget when a rung is stranded or a question's answers go out of reach,
    /// and does **not** decrement `deliveredCount` — because the app really did put something on
    /// the screen, and a counter of attempts that forgot it would be describing a different day
    /// from the one that happened.
    private(set) var deliveredCount = 0
    private(set) var deferredCount = 0

    /// **The same deferrals, by the reason each one names** (focus-6pr.4).
    ///
    /// `deferredCount` is one number for five reasons, and a total cannot say whether the one
    /// this round added ever happened: a self-check that published the sum would report the same
    /// figure whether an accusation beside a pinned question was deferred or charged. Keyed by
    /// the reason, so the gate can seed the state and read back the cell it seeded.
    ///
    /// Written in `record(deferral:…)` and in `undeliverRecord(…)`'s own take-back, which are the
    /// two places `deferredCount` moves, so the two counters cannot part company.
    private(set) var deferralsByReason: [DeferralReason: Int] = [:]

    /// **Every charge this loop has made, and the proof it was made on** (focus-1b5, focus-nrl).
    ///
    /// One `PerceptibleChange` per unit of the person's day that has been spent, in the order
    /// they were spent. It exists to be **joined against the store**: the day's caps are summed
    /// from `InterventionRecord` rows marked `delivered`, and this is the list of receipts the
    /// perception path issued, so `rows == receipts` is a statement that no delivered row in the
    /// store came from anywhere but a proof.
    ///
    /// That join is the reading three rounds of this defect did not have. `deliveredCount` above
    /// is a count of *attempts the loop believes reached somebody* and cannot fail; the self-check
    /// published `menuBarGlyphWrites` and `menuBarAnnouncements` as raw counters and paired them
    /// with nothing. A counter that is always zero would be the same green that means nothing —
    /// this is not one: it is a list that grows, whose length has to match a number computed a
    /// completely different way, from persisted rows.
    private(set) var chargesPaidFor: [PerceptibleChange] = []


    /// **The question on screen, as one value** (focus-zrs).
    ///
    /// It was six independent stored properties — the warrant, the ask time, the priority
    /// identifier, the surface, the reading taken at the ask and the answer identifiers — set on
    /// one line each and cleared on another. Every one of them is a statement about the *same*
    /// question, and each of the last five rounds found a path where some of them had moved and
    /// some had not. The one that produced this type was the sixth: `openQuestionPriorityID` came
    /// from a store read that could disagree with the gate that admitted the question, and every
    /// consumer of it opened with `guard let … else { return }` — so a divergence silently
    /// dropped the person's click.
    ///
    /// One optional cannot be half-set. `priorityID` is **not** optional inside it, because a
    /// question that does not know what commitment it is about is not a question this loop is
    /// allowed to have raised: `ask(…)` refuses to raise one, loudly, rather than raising it with
    /// a `nil` key.
    private struct OpenQuestion {
        let warrant: QueryWarrant
        var selectedScope: CorrectionScope?
        /// **The commitment it was asked under** (focus-lmo, U-1) — captured, never fetched,
        /// because the panel is sticky (`hidesOnDeactivate` is `false`, R-89) and a person can
        /// commit to something new while a question waits. It is the key the receipt, the learned
        /// rule and every deferral row that stands in for a receipt are written against.
        ///
        /// **Both halves of it, because the badge draws the other half** (focus-xix). It was the
        /// `UUID` alone, so `pendingPopoverQuery` had to fetch the sentence again from a live
        /// reading — `activeCommitment()?.intent ?? ""` — and a popover redrawn after the
        /// commitment had gone drew the question under an empty task. The key and the sentence
        /// are one fact about one commitment, and a value that carries one of them is the shape
        /// focus-lmo condemned.
        let commitment: ActiveCommitment
        /// The key everything this question writes is scoped to.
        var priorityID: UUID { commitment.id }
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
        ///
        /// **It is now a consequence of `perceived` below** rather than a second derivation
        /// beside it: one reading of the real surfaces decides both whether the question is
        /// charged and what the ledger is later told about it, so the two cannot disagree.
        var readingAtAsk: SurfaceReadability = .unknowable
        /// What every surface was doing immediately before this question was allowed to change
        /// one — `OpenRung.observedAtLanding`'s twin, for the twin reason.
        var observedAtAsk: SurfaceObservation = .nothingSeen
        /// **The receipt this question was charged on**, or `nil` while nobody has been shown it.
        var perceived: PerceptibleChange?
        /// The answers the question is offering, by `rawValue`, so a reading taken as it ends asks
        /// about the same set the panel was drawn with.
        var actions: [String] = []
        /// **The log row this question's delivery wrote** (focus-xix), so the person's answer
        /// completes *this* intervention rather than whichever row was written most recently.
        /// `nil` until the question has actually reached somebody, which for the badge is the
        /// moment the popover shows it.
        var recordID: UUID?

        /// **Whether this question is occupying the thing the slot is about: an answerable
        /// screen** — `OpenRung.holdsTheInterruptionSlot`'s twin, for the twin reason.
        ///
        /// focus-k42's repair separated *which interruption this is* from *whether the screen is
        /// occupied*, and it was applied to the rung and not to the question. The asymmetry was
        /// the whole of the cut's own defect: `slot` asked `openQuestion != nil`, so **every**
        /// state in which this object holds a question — including the two in which the question
        /// has reached nobody at all — withheld every accusation that followed, for the life of
        /// the session. U-2 says an accusation *waits* for a question; it does not say an
        /// accusation waits for a question nobody was ever shown.
        ///
        /// The two states that reach nobody, and now do not hold the slot:
        ///
        /// * `surface == nil` — the route offered no surface. `ask(…)` records a deferral, which
        ///   is R-81's *"reached nobody"*, and this question is over.
        /// * `surface == .popoverBadge` while the popover is shut — *"the badge is an invitation,
        ///   not a delivery"*. Nothing is counted and nothing is written, and the popover opens
        ///   only when a person clicks the status item. It is exactly the glyph's case:
        ///   `holdsTheInterruptionSlot` is `false`, and a badge that held the slot would hold it until
        ///   the session ended, because nothing on screen can be pressed to take it down.
        ///
        /// The predicate is `NudgeSurface.holdsTheInterruptionSlot` for the same reason the rung's is,
        /// and it is deliberately **not** `readingAtAsk`: a panel question that could not be read
        /// is ended by `ask(…)` rather than left open, so readability is not a state this can be
        /// asked in, and adding it would be the second derivation of one fact that focus-k42
        /// condemned.
        ///
        /// This is ownership. *Identity* — "is a question already open?" — is a different
        /// question with a different answer, and `ask(…)` asks it separately so that a badge
        /// question waiting behind a click is never silently replaced by a second one.
        var holdsTheInterruptionSlot: Bool { surface?.holdsTheInterruptionSlot ?? false }
    }

    /// **The appearance the person is actually running in** (focus-pq8).
    ///
    /// A seam, like `surroundings`, and for the same reason: this object must not read
    /// `NSWorkspace` or the store directly, and the snapshot lane must be able to drive every
    /// variant without touching System Settings. The composition root wires it to
    /// `AppearanceObserver.traits`.
    ///
    /// Its absence *was* the defect. `panel.update(…)` and `menuBar.update(…)` were called with
    /// the default argument, which is `AppearanceTraits.systemDefault` — light, every accessibility
    /// setting off — so the nudge panel and the popover were pinned to light for the life of the
    /// process while the window around them followed the Mac. In dark mode that is a panel whose
    /// text is drawn for a light background on a dark one.
    var appearanceTraits: @MainActor () -> AppearanceTraits = { .systemDefault }

    private var openQuestion: OpenQuestion?

    /// **The rung on screen, as one value** (focus-zrs) — `OpenQuestion`'s twin, for the twin
    /// reason.
    ///
    /// The rung, the commitment it was raised under, the corrections it is offering and the
    /// notification delivery it went out on are four statements about one interruption, and they
    /// were four properties. The last of them is why `deliveryID` is in here: a notification's
    /// buttons stay live in Notification Centre indefinitely, and `notifications.onAction`
    /// reached `resolve(…)` with **no check that the rung the button belongs to is still open**.
    private struct OpenRung {
        let rung: LadderRung
        /// The commitment it was raised under: the persisted "this is relevant" rule, the
        /// session-lived "not this time" rule and the deferral row a display change writes when it
        /// strands the rung are all keyed to this rather than to whatever the store happens to
        /// call active at the moment of the click (focus-lmo).
        ///
        /// **Both halves, and the second half is a defect this fixes** (focus-xix). The panel's
        /// `AccusationPresentation` is built from the commitment `accuse(…)` was handed; the
        /// badge's was built by `pendingPopoverAccusation` from a **second, live** reading, which
        /// meant the same rung could name one task on one surface and another task on the other,
        /// and — because that property guards `activeCommitment()` with a `return nil` its twin
        /// does not have — the badge simply went blank on any redraw taken after the commitment
        /// had gone. A rung that reached a surface knows what it is about, because it cannot be
        /// constructed without one.
        let commitment: ActiveCommitment
        /// The key everything this rung writes is scoped to.
        var priorityID: UUID { commitment.id }
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
        /// **What every surface was doing at the instant before this rung was allowed to change
        /// any of them** (focus-1b5, focus-nrl).
        ///
        /// The baseline half of the charge's proof, and it is fixed at the landing and never
        /// re-taken: a rung that reaches nobody now may reach somebody later — when the badge
        /// question above it is answered and the item's mark falls from `waiting` to the rung's
        /// own `noticing` — and the change that has to be proven then is the change since the
        /// **landing**, not since the last redraw.
        ///
        /// It replaced a `SurfaceReadability` written by hand at each landing. The readability
        /// was the right shape for the badge, where "the popover is showing it" really is the
        /// whole question, and the wrong shape for the glyph, where the item is always on screen
        /// and only a *difference* is perceptible. One field for both meant the glyph's cell was
        /// filled in from `reachesThePersonOnLanding` — a predicate that answers `true` and
        /// cannot fail — which is the defect three rounds have now fixed one instance at a time.
        let observedAtLanding: SurfaceObservation
        /// **The receipt this rung was charged on, or `nil` while it has been shown to nobody.**
        ///
        /// The flag that says whether this rung has been counted, and it is a *proof* rather than
        /// a `Bool`, so the answer to "why was this charged?" is a value naming the surface and
        /// the channel. `proveOpenRung(at:)` refuses to charge twice, so a rung that lands on
        /// an already-open popover and a rung the person opens the popover onto are one delivery.
        var perceived: PerceptibleChange?
        /// **The log row this rung's delivery wrote** (focus-xix) — `OpenQuestion.recordID`'s
        /// twin, and for the twin reason: the correction the person presses must complete the
        /// row for the rung they pressed it on.
        var recordID: UUID?
        /// **Whether this rung has already been written down as unanswerable beside a pinned
        /// question** (focus-6pr.4).
        ///
        /// `proveOpenRung(at:)` is offered again at **every** seam — a landing, a click, a write
        /// to the status item, a redraw — so the deferral it records for a both-state popover
        /// would otherwise be a row per redraw for one rung nobody could answer. `perceived` is
        /// the same guard for the charge; this is its twin for the row, and the two are separate
        /// because a deferred rung is not a charged one and must stay chargeable: answering the
        /// question unpins the accusation, the popover redraws offering its corrections, and the
        /// rung is charged then — for the first moment anybody could have pressed one.
        ///
        /// It is read by `recordUnopenedInvitation(_:)` as well, so a rung that has said *nobody
        /// could answer this* does not also say *nobody opened this* when the person takes their
        /// screen back. One attempt, one row.
        var deferredBehindThePinnedQuestion = false
        /// **Whether this rung is occupying the thing the slot is about: an answerable screen.**
        ///
        /// R-84a's argument for a single slot is that *"two panels on screen at once is the
        /// behaviour that makes people uninstall"*. A glyph and a badge are not panels: they carry
        /// no sentence and offer nothing to press, which is exactly what
        /// `NudgeSurface.holdsTheInterruptionSlot` already says. A glyph that held the slot would hold it
        /// for ever, because nothing can take an ambient rung down.
        var holdsTheInterruptionSlot: Bool { landedOn.holdsTheInterruptionSlot }
    }

    private var openRung: OpenRung?

    /// **One open interruption at a time, derived rather than stored** (R-84a, focus-zrs).
    ///
    /// `slot` was a stored `InterruptionSlot` mutated on eleven lines beside the fields above —
    /// a second representation of *which interruption is on screen*, and the one the **decider**
    /// reads. A stored slot could say "a question holds this" while this object held none, and
    /// the decider had no way to tell.
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
    ///
    /// **And it asks the same of the question** (U-2's own defect). The line below used to read
    /// `if let openQuestion`, so the separation focus-k42 established survived on one side of the
    /// slot and not the other — and once `offering(_ rung:)` began withholding against an open
    /// query, that asymmetry stopped being latent and became the loudest failure in the epic: a
    /// question routed to the badge and never opened, or routed to no surface at all, silenced
    /// **every** accusation for the rest of the session, with no symptom but silence. Both
    /// branches now ask where the interruption landed, and neither asks whether this object is
    /// holding one.
    var slot: InterruptionSlot {
        if let openRung, openRung.holdsTheInterruptionSlot {
            return InterruptionSlot(holder: .accusation(openRung.rung))
        }
        if let openQuestion, openQuestion.holdsTheInterruptionSlot {
            return InterruptionSlot(holder: .query(openQuestion.warrant))
        }
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

    /// **Whether there is a nudge for the two View-menu verbs to answer** (focus-6uf).
    ///
    /// The exact condition `perform(_:)`'s two guards read, published so the menu item that sends
    /// those commands can ask it rather than offering them always and dropping them silently.
    var hasOpenNudge: Bool { openRung != nil }

    /// **Whether there is a question for the three answering verbs to answer** (e07a T1).
    ///
    /// Deliberately *not* folded into `hasOpenNudge`. That property is `openRung != nil` — the
    /// **accusation** — and the two nudges have been separate values in this object since
    /// focus-k42 precisely because reading one for the other silenced the loop for a whole
    /// session. *Mark as Relevant* and *Snooze Nudge* answer a rung; *Yes*, *Unrelated* and
    /// *Later* answer a question; a world that could not tell them apart would offer all five
    /// whenever either was on screen and drop three of them silently, which is the defect
    /// focus-6uf repaired at the other end.
    var hasOpenQuestion: Bool { openQuestion != nil }

    /// The world as the nudge loop can see it.
    ///
    /// Two fields, and the other two left at their defaults, because the loop answers exactly
    /// the commands that turn on these: a priority and a session are the cockpit's facts, and
    /// the composition root is the only object that holds all four at once — which is why the
    /// *menu's* world comes from there rather than from here.
    var commandWorld: ShellCommandWorld {
        ShellCommandWorld(hasOpenNudge: hasOpenNudge, hasOpenQuestion: hasOpenQuestion)
    }

    private(set) var mandatesWithoutACommitment = 0
    private(set) var staleNotificationActions = 0

    /// **A proof offered while no turn was open** (focus-my0) — always zero, and it is the one
    /// number that says the seam is actually reached. The accountant's count; read here because
    /// this is the object the unit lane and `--focus-self-check` hold.
    var proofsOfferedOutsideATurn: Int { proofs.offeredOutsideATurn }

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
        self.naming = SubjectNaming(workspace: workspace)
        self.monotonicClock = monotonicClock
        self.dateProvider = dateProvider

        // **The seam** (focus-my0). Wired once, here, so that there is one place in the
        // programme where a reading of the surfaces becomes evidence, and it is a place that can
        // only be reached with the call stack unwound. The accountant decides *when*; these two
        // closures are the *what*, and they are this object's because only it holds the question
        // and the rung.
        proofs.observe = { [weak self] nudge in
            self?.observation(of: nudge) ?? .nothingSeen
        }
        proofs.prove = { [weak self] nudge, seam in
            guard let self else { return }
            // Exhaustive, so a third thing the badge learns to carry stops the build here rather
            // than being settled for one kind and forgotten for the other.
            switch nudge {
            case .query: self.proveOpenQuestion(at: seam)
            case .accusation: self.proveOpenRung(at: seam)
            }
        }
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

    func stopForStoreDeletion() {
        hideOverlays()
        notifications.onAction = nil
        panel.onDismiss = nil
        panel.onDisplaysChanged = nil
        onCorrection = nil
        onQuestionSurfacesChanged = nil
    }

    /// One judgement, considered.
    ///
    /// Called from the verdict stream `RelevanceHost` publishes — every accepted activation and
    /// e03's five-second corroboration tick — so the loop advances without this host owning a
    /// timer of its own.
    func consider(_ judgement: NudgeJudgement) {
        proofs.run {
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
            noticeAHeldReturn(judgement, at: surroundings.monotonic)

            let subject = NudgeDecider.querySubject(for: judgement)
            // **The commitment gate 1 is decided by, and the key everything this judgement writes
            // is scoped to — one value, read once** (focus-zrs). It was two: `surroundings`' own
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
                    """
                    the nudge stores refused a read: \
                    \(error.localizedDescription, privacy: .public)
                    """
                )
                return
            }

            let decision = NudgeDecider.decide(
                judgement,
                surroundings: surroundings,
                memory: memory,
                preferences: preferences,
                tunings: tunings
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
    }

    /// The last application the engine called real work.
    ///
    /// Recorded here rather than inferred later, because by the time a mandate exists the
    /// frontmost application is the *distraction* — asking the workspace then would offer to
    /// return somebody to the thing they were being nudged about.
    /// **How long the engine has said, unbroken, that this is real work** (focus-4xy).
    ///
    /// `nil` when the last judgement was not `.aligned`. Reset on every de-escalation this
    /// produces, so a standing alignment cannot put the ladder down twice for one return.
    private var alignedSince: Duration?

    /// **The half of U-1's bargain the ladder never heard about** (focus-4xy).
    ///
    /// `LadderDeEscalation.verdictRelevant` — documented as *"the engine now says this is real
    /// work"* — was a case in the vocabulary that no producer emitted. So the ladder was put down
    /// by things the PERSON does — a correction, a snooze, a pause, a priority change, the end of
    /// a session — and never by the app getting better at recognising the work in front of it,
    /// which is the half of the ruling that says *getting better at recognising real work is how
    /// the app avoids interrupting*.
    ///
    /// **Held, not instantaneous, and that is the whole design decision.** A single `.aligned`
    /// judgement is one alt-tab back, and a ladder that reset on one would be defeated exactly
    /// the way `focus-f2a` measured: the drift-return-drift rhythm resets the accumulator between
    /// every pair of drifts, and the accumulator is the thing that repair exists to protect. So
    /// the predicate is the one `DriftMachine` ruling 1 already uses to credit a return —
    /// alignment **held past `RelevancePolicy.driftResetGrace`** — read from the value the loop is
    /// already handed rather than from the accumulator itself. That is why this reads
    /// `judgement.drift` and never `DriftMachine`: tying the ladder to the accumulator's own reset
    /// would undo `focus-f2a`, which is why that round deliberately left this case unwired.
    ///
    /// It does nothing while the ladder is idle. A ladder that is not standing has nothing to put
    /// down, and starting the clock for one would be the app remembering an alignment from before
    /// the drift that provoked the rung.
    private func noticeAHeldReturn(_ judgement: NudgeJudgement, at now: Duration) {
        guard judgement.drift == .aligned, ladder.state.kind != .idle else {
            alignedSince = nil
            return
        }
        guard let since = alignedSince else {
            alignedSince = now
            return
        }
        guard now - since >= tunings.duration(.driftResetGrace) else { return }
        alignedSince = nil
        ladder.reduce(.deEscalated(.verdictRelevant), now: now, tunings: tunings)
        // The rung on screen is over with the ladder that raised it, and it ended because the
        // world moved rather than because anybody answered — the same ending a phase change out
        // of `.focus` writes, and for the same reason (focus-qds: an expiry is not an answer).
        closeSurfaces(endingAnyQuestionAs: .worldMovedOn, andAnyRungAs: .worldMovedOn)
    }

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
        deferralsByReason[deferral, default: 0] += 1
        ladder.reduce(.delivery(.deferred(deferral)), now: monotonicClock.elapsed, tunings: tunings)
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
    /// The path that reaches nobody has already called `endOpenRung(.replaced)`, once, above the
    /// route: a rung with no surface is not a quieter interruption, it is not an interruption at
    /// all, and whether *this* rung found one is a fact about this rung rather than about the one
    /// it displaced.
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
        ladder.reduce(.mandate(rung.mandate), now: surroundings.monotonic, tunings: tunings)
        // **The rung the decision carries, not a second derivation of it** (focus-628). This line
        // used to re-run `candidate(at:budgetPermits:)` on the ladder that persists and trust the
        // two answers to agree. They agreed only for as long as they were the same expression, and
        // they stopped being one when a refusal about the app *speaking* could send the decider to
        // `retainedRung`: the host would have recorded the escalation as offered and resolved the
        // glyph's delivery against it.
        ladder.offer(rung)

        let presentation = presentations.accusation(for: rung, commitment: commitment)

        // **What every surface was doing before this rung was allowed to touch one — as the
        // person last saw them** (focus-1b5, focus-nrl, focus-r28.1).
        //
        // It was `observation(of: .accusation)`, taken here, mid-turn. Both halves of a proof are
        // supposed to be states AppKit could composite, and only one of them was: the *after* half
        // has been a `SettledObservation` since focus-my0 and the *before* half was whatever the
        // surfaces happened to be saying at this line. A transient mark written and reverted
        // earlier in the same turn is recorded in it, `before.carries(surface)` is then true of a
        // state nobody ever saw, and the rung becomes permanently unprovable — recorded unopened
        // rather than charged. The direction is safe, which is why it survived a round; it is
        // still a comparison against an arbitrary instant.
        //
        // The accountant's baseline is the last reading taken at a **seam**, so a perceptible
        // change is
        // now the difference between two composited states. It also retires the ordering rule the
        // comment here used to carry — *"above the line that ends the rung this loop is
        // holding"* — because a baseline from the previous seam cannot be disturbed by anything
        // this turn does, in either order.
        let observedBeforeLanding = proofs.settledObservation(of: .accusation)

        // **The rung this loop is holding ends here, before the next one lands** (focus-s4m,
        // focus-fwy).
        //
        // One statement covering what used to be four — the three `forgetOpenRung()` calls in the
        // deferral branches below and the replacement hidden inside `setOpenRung(_:)` — because
        // whether the *new* rung finds a surface is a fact about the new rung, and the old one is
        // over either way. `RungExit.replaced` is what that means.
        //
        // **Before `landed(on:)`, and that is why it cannot live inside the assignment.**
        // `RungExit.countsAsAnIgnoredAccusation` reduces `LadderEvent.rungIgnored`, and
        // `LadderMachine.ignore(now:)` reads the state it is standing in — so an ignore reduced
        // after the new delivery had been recorded would be counted against the rung that has just
        // landed rather than the one that just ended, and at the top rung it would return the
        // ladder to `.idle` and destroy the panel delivery in the same breath as making it.
        //
        // The extra status-item write this can cost inside one turn is exactly what `SurfaceTurn`
        // exists to absorb: the charge is settled at the seam, from the baseline above, once
        // nothing is left in flight to undo the surface.
        endOpenRung(.replaced)

        guard let surface = route.surface else {
            record(
                deferral: route.deferralReason ?? .noSurfaceAvailable,
                kind: .accusation,
                subject: rung.subject,
                priorityID: priorityID
            )
            // Reached nobody at all, so there is no rung on any surface — and nothing may go on
            // holding the interruption slot in its name (focus-k42). The line that gives it back
            // is `endOpenRung(.replaced)` above, which has already run.
            return
        }

        switch surface {
        case .menuBar, .popoverBadge:
            // The glyph and the badge are drawn by the composition root's own menu-bar refresh;
            // nothing here has to raise a window for them.
            //
            // It landed, so the rung is recorded against the surface it landed on — but
            // `holdsTheInterruptionSlot` is `false` for both of these, so it does not hold the
            // interruption slot. Nothing can ever take an ambient glyph down, and a badge is
            // behind a click nobody has made yet, so a rung that held the slot from either would
            // silence the question affordance for the rest of the session (focus-k42).
            //
            // **Landing and being seen are two different facts, and this branch used to make
            // them one** (focus-xix). `delivered(…)` advanced the ladder, spent
            // `fatigue.reduce(.delivered(.accusation))` and wrote a `disposition = .delivered`
            // row, unconditionally, for both surfaces. For the badge that is a rung nobody has
            // been shown: the popover opens only on a click, `MenuBarController.redraw` draws
            // from the status and the timer alone, and `announceStatusChange` does not fire
            // because the ambient rung already set `.unrelated`. So the climb from rung 1 to rung
            // 2 was silent, invisible AND unannounced, while it spent one of the day's six
            // accusations, one of its eight interruptions and armed a 600-second cooldown — and
            // the Intervention pane then printed *"Nudges today 3 / 6"* to somebody who had been
            // shown a glyph.
            //
            // The split is `NudgeSurface.reachesThePersonOnLanding`'s, which is the question
            // path's own rule stated once for both: the ladder is told the rung landed either
            // way, and the spend and the row wait for `popoverPresented()`.
            // `setOpenRung(…)` below asks the composition root for a refresh, and that refresh
            // is what may or may not write to the item. The baseline above is older than the
            // write it will be compared against, which is what makes the comparison a
            // measurement.
            landed(on: surface)
            setOpenRung(
                OpenRung(
                    rung: rung,
                    commitment: commitment,
                    landedOn: surface,
                    observedAtLanding: observedBeforeLanding
                )
            )
            // **The rung is charged if — and only if — that redraw showed somebody something.**
            //
            // It used to be charged on `reachesThePersonOnLanding`, a predicate that answers
            // `true` for `.menuBar` and cannot fail. Measured on the shipping loop, that
            // predicate paid for six glyph landings with one write to the status item
            // (focus-mkk), then for six more with none at all once a second subject was driven
            // (focus-1b5), and for six more with none ever whenever a badge nudge was pending —
            // which is the ordinary state of every Reduce Motion user (focus-nrl).
            //
            // This call is idempotent and it is not the only one: the same door is opened by
            // `popoverPresented()` when somebody clicks the item, and by `menuBarItemRedrawn()`
            // every time the item is really written to. A rung that reaches nobody now is not
            // discarded — it stays open and unpaid, and is charged at the first moment the person
            // can see it, which is what makes focus-nrl's rung recoverable instead of lost.
            offerRungForProof()

        case .panel:
            panel.update(
                AccusationPanelView(presentation: presentation) { [weak self] action, span in
                    self?.resolve(action, snoozeDuration: span)
                },
                traits: appearanceTraits()
            )
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
            // **One derivation, and the charge is its consequence** (focus-1b5). The reading is
            // taken through `SurfaceObservation.carries(_:)`, which is the state half of the
            // very clause `PerceptibleChange` asks of this channel — so there is no second rule
            // here for a future round to find out of step with the other two. For a window the
            // proof is a state and honestly so: a window is absent or present, `isVisible` is a
            // reading of the real `NSWindow`, and every action is hit-tested where it actually is.
            //
            // **What this decides is the deferral, and no longer the charge** (focus-my0). Those
            // were one statement, and they are two questions: *"is this panel a surface somebody
            // could decide on?"* is about the panel and is answered now, at the show, because a
            // panel nobody can answer must become a deferral rather than a nudge; *"did anybody
            // see it?"* is about the person and cannot be answered until this turn stops moving
            // the surfaces. A panel shown and hidden inside one call stack satisfied the second
            // question here and was composited never.
            let atLanding = observation(
                of: .accusation,
                panelActions: presentation.offeredActionIdentifiers
            )
            guard atLanding.carries(.panel) else {
                let summary = panel.decisionSurfaceReading(
                    offering: presentation.offeredActionIdentifiers
                ).summary
                logger.error("a rung was put on an unreadable panel: \(summary, privacy: .public)")
                panel.hide()
                record(
                    deferral: .noSurfaceAvailable,
                    kind: .accusation,
                    subject: rung.subject,
                    priorityID: priorityID
                )
                // The panel has just been hidden, so this rung is on no surface at all. The slot
                // was given back and the corrections nobody can see were withdrawn by
                // `endOpenRung(.replaced)` above (focus-k42, focus-s4m).
                return
            }
            // Landed, answerable, and therefore genuinely occupying the one interruption slot —
            // the case R-84a is actually about.
            landed(on: .panel)
            setOpenRung(
                OpenRung(
                    rung: rung,
                    commitment: commitment,
                    landedOn: .panel,
                    panelActions: presentation.offeredActionIdentifiers,
                    observedAtLanding: observedBeforeLanding
                )
            )
            // **The panel goes through the one door too** (focus-my0). It used to charge on this
            // line, which made two charging sites that a reviewer had to keep in step by memory —
            // the shape every bead in this sequence has. The rung is offered here and proven at
            // the seam, so there is exactly one place in this object that spends a unit of the
            // person's day, and it is a place with nothing left in flight to undo the surface.
            offerRungForProof()

        case .notification:
            // **No rung routes here any more** (U-2). The notification was the recommitment rung's
            // surface and nothing else's, and that rung is deferred to focus-5ab — so
            // `SurfaceRouter` has no branch that can answer `.notification` for an accusation.
            //
            // This is a refusal rather than a deleted branch because the surface is still a
            // declared one — focus-5ab brings the rung back, and `resolveFromNotification(…)`
            // must be able to name it in order to refuse a press on a banner an earlier build
            // posted — and a routing bug that sent a rung here must be a loud deferral rather
            // than a silently swallowed nudge.
            logger.fault("a rung was routed to a notification, which no rung reaches since U-2")
            record(
                deferral: .noSurfaceAvailable,
                kind: .accusation,
                subject: rung.subject,
                priorityID: priorityID
            )

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
        // **Ownership is not identity, so the slot cannot answer this one** (U-2's defect).
        // A question waiting behind a click — routed to the badge, popover shut — deliberately
        // does *not* hold the slot, because it has reached nobody and an accusation must not wait
        // for it. That is the right answer for the accusation and the wrong one here: overwriting
        // `openQuestion` below would strand the badge the menu bar is already drawing, drop the
        // subject the person was about to be asked about, and leave `popoverPresented()`
        // to deliver a question about something else. One question at a time is a fact about this
        // object, so it is asked of this object.
        guard openQuestion == nil else { return }
        // One value, set once. The commitment as it stands **now**, at the ask, travels inside it:
        // everything this question ever writes is keyed to that and never to a later store read
        // (focus-lmo, focus-zrs).
        openQuestion = OpenQuestion(
            warrant: warrant,
            commitment: commitment,
            askedAt: dateProvider.now
        )
        // **Nothing is taken down here** (focus-2rg, U-2).
        //
        // This line forgot the open rung, unconditional, and it is preemption's other direction
        // outliving the mechanism. Ask what it could still reach: `slot.offering(warrant)` above
        // withholds against any rung that `holdsTheInterruptionSlot`, so a rung on the **panel**
        // never gets here. What did was exactly the two rungs that hold no slot — the ambient
        // glyph and the badge — and the badge is the one it cost something.
        //
        // Driven on the shipping loop with reduced interruption on: ladder at `.panel`, the rung
        // on the badge with five answers on it, then one ordinary uncertain judgement about
        // another application, and `pendingPopoverAccusation` went to `nil`. Nothing was recorded
        // — no deferral, no `ladder.undeliver`, no withdrawal — while the delivered row went on
        // charging the day's budget and `openRecordID` was overwritten by the question's own write
        // so that row could never be completed either. The accusation had five answers a moment
        // earlier and now had no surface, because the person was asked about something else.
        //
        // The two do not collide. `MenuBarPopoverView` draws `pendingAccusation` and
        // `pendingQuery` as two rows of one popover, and the reverse order was already proved to
        // keep both (`NudgeHostSlotOwnershipTests.aBadgeQuestionDoesNotSilenceTheAccusation`) —
        // so this direction was the asymmetry, not the rule.

        let presentation = QueryPresentation(
            voice: preferences.voice,
            // The commitment's own sentence, carried in with it rather than fetched again — so the
            // question on the screen names the task the receipt will be written against.
            task: commitment.intent,
            // **The name, resolved once, at the moment the question goes up** (focus-ebv). The
            // rule the answer writes is still keyed on `warrant.subject.identifier` — every
            // `record(…)` and every ledger write below reads that same value, unchanged.
            subject: naming.subject(of: warrant.subject),
            reason: warrant.reason,
            dwelled: warrant.dwelled,
            answerScopes: CorrectionScope.from(warrant).answerScopes
        )

        guard let surface = route.surface else {
            // **A question that reached no surface at all is over** (focus-k42's shape, on the
            // question side). `record(deferral:)` writes `disposition = deferred`, which is
            // R-81's *"reached nobody"* — and this object used to keep the question anyway, with
            // a `nil` surface, unanswerable and unexpirable. `accuse(…)` ends its own open rung
            // on precisely this path; this is the same statement, and it is made before the
            // deferral is written so no reader can observe the two disagreeing.
            endOpenQuestion(.neverDelivered)
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
        // **What every surface was doing before this question was allowed to touch one**
        // (focus-1b5, focus-r28.1). The question path's twin of `accuse(…)`'s baseline, and the
        // same repair: the last reading taken at a seam, so both halves of the proof are states
        // that reached a frame.
        let observedBeforeAsking = proofs.settledObservation(of: .query)
        openQuestion?.observedAtAsk = observedBeforeAsking

        switch surface {
        case .panel:
            panel.update(
                QueryPanelView(presentation: presentation, onSelectScope: { [weak self] scope in
                    self?.selectQueryScope(scope)
                }) { [weak self] answer in
                    self?.answer(answer)
                },
                traits: appearanceTraits()
            )
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
            // **One derivation, and both the deferral and the ledger's input are its
            // consequences** (focus-1b5). The reading goes through
            // `SurfaceObservation.carries(_:)`, which is the state half of the clause
            // `PerceptibleChange` asks of this channel — the door the glyph, the badge and the
            // panel's rung all go through; `readingAtAsk` — the value `QuestionLedgerPolicy` is
            // handed later — is filled in from the same answer rather than derived a second time
            // beside it.
            //
            // **`.readable` is written at the seam and not here** (focus-my0). A panel put up and
            // taken down inside one call stack is a panel nobody was shown, and a receipt saying
            // the question was readable is exactly the falsified row this round is about. The
            // unreadable answer is written now, because that is the branch that ends the question
            // on the spot; the readable one is written by the proof, which cannot run until the
            // surfaces have stopped moving.
            let atAsk = observation(
                of: .query,
                panelActions: presentation.offeredAnswerIdentifiers
            )
            guard atAsk.carries(.panel) else {
                openQuestion?.readingAtAsk = .notReadable
                let summary = panel.decisionSurfaceReading(
                    offering: presentation.offeredAnswerIdentifiers
                ).summary
                logger.error(
                    """
                    a question was put on a panel nobody could answer and was left unwritten: \
                    \(summary, privacy: .public)
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
            // On screen, and every answer in reach: the panel is the surface that reaches
            // somebody the moment it lands — so the question is offered to the seam of this very
            // turn, and unless something in the rest of it takes the panel away again, it is
            // charged before this call returns.
            offerQuestionForProof()
            return

        case .popoverBadge:
            // **The badge is an invitation, not a delivery** (focus-kby).
            //
            // The popover is drawn by the composition root's menu-bar refresh, which reads
            // `pendingPopoverQuery` below, and it opens **only when a person clicks the status
            // item**. So a question routed here has reached nobody yet: nothing is counted and
            // nothing is written until `popoverPresented()` says the popover is showing it, which
            // is what stops a question burning its one asking behind a click that opens it.
            //
            // **The redraw is the rung's** (focus-xix, focus-uru). `accuse(…)` has always asked
            // the composition root to redraw when a rung reached the badge, because the popover
            // on screen is a hosting controller built from the presentation the menu bar was last
            // handed. The question needed it for the same reason and never had it: a question
            // raised while the popover was already open was invisible in it until the next
            // five-second refresh, and could not be counted until then either. One shape now, for
            // both.
            onQuestionSurfacesChanged?()
            offerQuestionForProof()
            return

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
    }

    /// The bookkeeping of a question that has actually reached somebody.
    ///
    /// One function and one call per question, so "delivered" cannot be recorded twice for a
    /// badge question that is asked once and read once.
    /// - Parameter change: the receipt, with no default, for the reason `deliveredRung(_:…)`
    ///   has one. The question path already waited on a real reading of a real surface — it is
    ///   where the badge's rule was invented — and it goes through the same door so that the
    ///   invariant is one statement rather than two that agree today.
    private func deliverQuestion(
        provenBy change: PerceptibleChange,
        warrant: QueryWarrant,
        priorityID: UUID?,
        now: Duration
    ) {
        deliveredCount += 1
        chargesPaidFor.append(change)
        fatigue.reduce(.delivered(InterruptionCharge(.query, priorityID: priorityID)), now: now, tunings: tunings)
        openQuestion?.recordID = write(
            InterventionEvent(
                kind: .query,
                subject: warrant.subject.identifier,
                surface: change.surface,
                disposition: .delivered,
                queryReason: warrant.reason
            ),
            priorityID: priorityID
        )
    }

    /// **The popover has opened, and whatever it is carrying is now in front of somebody**
    /// (focus-kby, focus-xix).
    ///
    /// Wired from the composition root, which is the only object that knows the menu bar and the
    /// nudge loop both exist. This is the moment a badge nudge stops being an invitation and
    /// becomes a delivery — and it is the only moment at which one may be counted.
    ///
    /// **It was `popoverPresented()`, and the name was the defect** (focus-xix). The
    /// question got this treatment; the rung got none, so `accuse(…)` counted a badge accusation
    /// at landing. The fix is not a second function beside this one — parity maintained by hand
    /// is what produced the bead — it is **one wire and one loop over `MenuBarNudge.allCases`**,
    /// so a third thing the badge learns to carry cannot be added to one half and forgotten by
    /// the other. The switch is exhaustive; adding a case stops the build here.
    func popoverPresented() {
        proofs.run {
            for nudge in MenuBarNudge.allCases {
                switch nudge {
                case .query: offerQuestionForProof()
                case .accusation: offerRungForProof()
                }
            }
        }
    }

    /// **The status item was actually written to** (focus-1b5, focus-nrl).
    ///
    /// Wired by the composition root from `MenuBarController.onGlyphWritten`, which fires at the
    /// end of a redraw and only when the picture or the announcement really changed. This is the
    /// second half of *"the charge is a consequence of the write"*: the loop no longer asks for a
    /// redraw and then charges on the assumption that one happened, because three rounds measured
    /// that assumption false — a redraw is coalesced away when two consecutive rungs compose the
    /// same picture, and the picture is the badge's rather than the rung's whenever a badge nudge
    /// is pending.
    ///
    /// It is also what makes an unpaid rung **recoverable**. focus-nrl's rung landed on the glyph
    /// under a pending question, was charged, and appeared in no channel at all — not even in the
    /// popover, which draws only what landed on the badge. Now it is charged nothing and stays
    /// open; when the question is answered the badge's `waiting` goes, the item is written with
    /// the rung's own `noticing`, and this door opens on the first moment anybody could see it.
    func menuBarItemRedrawn() {
        proofs.run { offerRungForProof() }
    }

    /// **Offer the open question to the seam of this turn** (focus-my0).
    ///
    /// Two callers — the ask itself, and the click that opens the popover — and neither of them
    /// charges. They say *"something that might have shown this to somebody just happened"*, and
    /// the answer is taken when the surfaces have stopped moving.
    ///
    /// It was `deliverPendingBadgeQuestion()`, and it proved the change on the spot from a reading
    /// taken mid-turn. That is what a settled reading now makes impossible.
    private func offerQuestionForProof() {
        proofs.offer(.query)
    }

    /// **Offer the open rung to the seam of this turn** (focus-1b5, focus-nrl, focus-my0).
    ///
    /// It was `deliverPendingRung()` — *"the one door to a rung's charge, for every surface"* —
    /// and the door is still one and still the same three callers: the landing itself, a click
    /// that opens the popover, and a write to the status item. What changed is that the door opens
    /// onto the seam rather than onto the charge.
    ///
    /// The offer matters: a redraw that never happens offers nothing, so a composition root that
    /// forgot to wire `MenuBarController.onGlyphWritten` still charges nothing for a glyph rung,
    /// exactly as before. The seam settles what was offered, never everything it can find.
    private func offerRungForProof() {
        proofs.offer(.accusation)
    }

    /// Charge the open question if the surfaces, settled, show it was put in front of somebody.
    ///
    /// Idempotent on the receipt, and over **every** surface a question can reach rather than over
    /// the badge alone: the panel's question used to be charged inline at the ask and the badge's
    /// here, which is one more instance of the treatment-one-half-received shape. `readingAtAsk`
    /// — what `QuestionLedgerPolicy` is handed — is written from the same answer, so a question
    /// the seam could not prove never claims to have been readable.
    private func proveOpenQuestion(at seam: borrowing SurfaceTurn.Seam) {
        guard let question = openQuestion,
              let surface = question.surface,
              question.perceived == nil,
              let change = PerceptibleChange.proven(
                  on: surface,
                  from: question.observedAtAsk,
                  to: seam.settled(observation(of: .query, panelActions: question.actions))
              )
        else { return }

        openQuestion?.perceived = change
        openQuestion?.readingAtAsk = .readable
        deliverQuestion(
            provenBy: change,
            warrant: question.warrant,
            priorityID: question.priorityID,
            now: monotonicClock.elapsed
        )
    }

    /// **The one place a rung is charged, for every surface** (focus-1b5, focus-nrl, focus-my0).
    ///
    /// It was `deliverPendingBadgeRung()`, and the word *badge* in its name was the defect. The
    /// badge had a door — it waited for `popoverPresented()` to prove the popover was showing the
    /// rung — and the glyph had none: `accuse(…)` charged it at the landing on the strength of
    /// `NudgeSurface.reachesThePersonOnLanding`, which answers `true` for `.menuBar` and cannot
    /// fail. Every bead in this sequence has that shape: a treatment one surface received and
    /// another did not. The panel was the last of them, and it charged inline in `accuse(…)` until
    /// focus-my0 brought it here.
    ///
    /// So there is one place, and it is reached only from the seam: `offerRungForProof()`'s three
    /// callers say a redraw happened, and this asks — once the call stack has unwound and nothing
    /// is left to undo the surface — whether `PerceptibleChange.proven(on:from:to:)` can show the
    /// person was shown something on that surface's own channel since the landing.
    ///
    /// Idempotent, on the receipt: a rung that has been charged holds one, and a second offer
    /// finds it and refuses.
    private func proveOpenRung(at seam: borrowing SurfaceTurn.Seam) {
        guard let open = openRung, open.perceived == nil else { return }
        guard let change = PerceptibleChange.proven(
            on: open.landedOn,
            from: open.observedAtLanding,
            to: seam.settled(observation(of: .accusation, panelActions: open.panelActions))
        ) else {
            deferBehindThePinnedQuestion(open)
            return
        }

        openRung?.perceived = change
        deliveredRung(rung: open.rung, provenBy: change, priorityID: open.priorityID)
    }

    /// **A rung the person is looking at and could not answer** (e07a, focus-cxb, focus-6pr.4).
    ///
    /// The one shape of *"the proof failed"* that is not silence. Every other way
    /// `PerceptibleChange.proven(…)` answers `nil` is a nudge nobody has been shown — the popover
    /// is shut, the item is already saying this, the panel is not up — and those stay open and
    /// unpaid, because the next redraw may well show them. This one cannot: the popover **is**
    /// open, it **is** drawing the accusation, and the decision on it belongs to the question
    /// pinned beside it, so the corrections are in the scrolling context and there is nothing
    /// there for anybody to press. That is a deferral in the word's own sense — nobody could see
    /// the surface *as a surface for this rung* — and `record(deferral:…)` does the rest: the
    /// ladder is told `.delivery(.deferred(_))`, which advances nothing and spends nothing, and
    /// the row says `deferred/questionPinned` rather than nothing at all.
    ///
    /// **Once per rung**, because this is offered again at every seam and a redraw is not a
    /// second attempt. The rung stays chargeable: answering the question unpins the accusation
    /// and the next seam proves the change for real.
    private func deferBehindThePinnedQuestion(_ open: OpenRung) {
        guard !open.deferredBehindThePinnedQuestion,
              open.landedOn == .popoverBadge,
              menuBar.isDrawnBesideThePinnedDecision(.accusation)
        else { return }
        openRung?.deferredBehindThePinnedQuestion = true
        record(
            deferral: .questionPinned,
            kind: .accusation,
            subject: open.rung.subject,
            priorityID: open.priorityID
        )
    }

    /// **What a person could actually be shown of one kind of nudge, right now** (focus-1b5).
    ///
    /// Every field is read off a live AppKit object: counts of assignments that really happened
    /// to the `NSStatusBarButton`, the mark that button is really drawing, `NSWindow.isVisible`
    /// conjoined with a hit test of the actions on offer, and `NSPopover.isShown` conjoined with
    /// what the popover is carrying and with where that layout put the actions. Not one of them
    /// is a predicate about a surface, which is the distinction the whole of this round turns on.
    ///
    /// - Parameters:
    ///   - nudge: which half of the loop is asking, because the panel and the popover each carry
    ///     one kind at a time and *"a panel is up"* is not *"my panel is up"*.
    ///   - panelActions: the actions to hit-test, defaulted to whatever the live nudge of that
    ///     kind is offering. Passed explicitly at a landing, where the rung being measured has
    ///     not been written into `openRung` yet.
    private func observation(
        of nudge: MenuBarNudge,
        panelActions: [String]? = nil
    ) -> SurfaceObservation {
        let actions: [String]
        switch nudge {
        case .query: actions = panelActions ?? openQuestion?.actions ?? []
        case .accusation: actions = panelActions ?? openRung?.panelActions ?? []
        }
        let panelKind = Self.panelKind(of: nudge)
        // **The reading travels, not its conclusion** (focus-2bj). These two lines used to hand
        // `SurfaceObservation` a `Bool` each, and this programme has twice watched a predicate be
        // substituted for a reading behind such a field — the popover's was
        // `menuBar.isPopoverShown && menuBar.isShowing(nudge)`, two booleans and no geometry, on
        // the one surface in the app that had committed to no size, and a popover measured at
        // 3127 points on a 1080-point display satisfied both of them with every correction above
        // the top of the screen. Repairing the field left the shape; carrying the
        // `DecisionSurfaceReading` removes it.
        //
        // The panel's `isCarryingTheNudge` is short-circuited deliberately:
        // `decisionSurfaceReading(offering:)` lays the panel's action frames out, and this
        // function is called on every write to the status item.
        let panelCarries = panel.isVisible && panel.showing == panelKind
        let popoverCarries = menuBar.isDrawing(nudge)
        return SurfaceObservation(
            menuBarWrites: menuBar.glyphWriteCount,
            menuBarAnnouncements: menuBar.announcementCount,
            markOnTheItem: menuBar.markOnTheItem,
            panel: WindowSurfaceReading(
                isCarryingTheNudge: panelCarries,
                reading: panelCarries
                    ? panel.decisionSurfaceReading(offering: actions)
                    : WindowSurfaceReading.nothingUp.reading
            ),
            popover: WindowSurfaceReading(
                isCarryingTheNudge: popoverCarries,
                reading: popoverCarries
                    ? menuBar.decisionSurfaceReading(of: nudge)
                    : WindowSurfaceReading.nothingUp.reading
            )
        )
    }

    /// **Which panel draws which kind of nudge** — one mapping, read by the observation the
    /// charge is proven from and by the orphan reading alike.
    ///
    /// It was written out twice, once as a `switch` inside `observation(of:)` and once as a pair
    /// of hand-written `panel.showing == .accusation` clauses in `orphanedNudgeSurfaces`. Two
    /// spellings of one table is the shape every bead in this sequence has.
    private static func panelKind(of nudge: MenuBarNudge) -> NudgePanelKind {
        switch nudge {
        case .query: .question
        case .accusation: .accusation
        }
    }

    /// **An invitation that reached a surface and was never opened** (focus-sq7).
    ///
    /// The badge is the only surface where landing is not reaching: the popover opens on a click,
    /// so a nudge routed there waits. `popoverPresented()` is the moment it becomes a delivery. If
    /// that moment never comes — the person never clicks, or the rung is replaced before they do —
    /// the record used to say **nothing at all**, for either kind. A day on which the app raised
    /// its top rung and nobody ever looked read exactly like a day on which the ladder never left
    /// the glyph, which is precisely the signal that would have shown focus-2xw in the wild.
    ///
    /// It is `.unopened` and not `.deferred`. A deferral is a statement that no surface could
    /// carry it; this one reached a surface and waited, `DeferralReason.noSurfaceAvailable` would
    /// be false about it, and `NudgeHostSlotOwnershipTests` reads `deferredCount` as a proxy for
    /// *"the route offered nothing"*. It spends nothing either way — `spendsBudget` is
    /// `disposition == .delivered` — so this adds a row to the record and not a unit to any cap.
    ///
    /// **One function over `MenuBarNudge`, not one per kind.** The question path has had the
    /// badge's rule since focus-kby and the accusation path acquired it in focus-xix, both by
    /// hand; the shape of every bead in this sequence is a treatment one half received and the
    /// other did not. The switch is exhaustive, so a third thing the badge learns to carry stops
    /// the build here rather than being written down for one kind and forgotten for the other.
    ///
    /// - Parameter nudge: which half of the badge is ending. Read off the live value, because both
    ///   callers are the single door for their own half and call this **before** forgetting it.
    private func recordUnopenedInvitation(_ nudge: MenuBarNudge) {
        switch nudge {
        case .query:
            // **The receipt, exactly as its accusation twin** (focus-6vz). This arm was keyed on
            // `!surface.reachesThePersonOnLanding` — the predicate the whole charging round
            // exists to retire, which answers `true` for `.menuBar` and cannot fail — conjoined
            // with `readingAtAsk`, a field written from the proof rather than the proof itself.
            // `OpenQuestion` has carried `perceived` since focus-my0 and this did not read it,
            // which is the shape of every bead in this sequence: one half of a doctrine applied
            // to the accusation and not to the question standing beside it.
            guard let question = openQuestion,
                  let surface = question.surface,
                  question.perceived == nil
            else { return }
            write(
                InterventionEvent(
                    kind: .query,
                    subject: question.warrant.subject.identifier,
                    surface: surface,
                    disposition: .unopened,
                    queryReason: question.warrant.reason
                ),
                priorityID: question.priorityID
            )

        case .accusation:
            // **Every rung nobody was shown, not only the ones behind a click** (focus-1b5,
            // focus-nrl). The guard was `!landedOn.reachesThePersonOnLanding`, which is `false`
            // for `.menuBar` — so the glyph rungs this round stops charging would have left no
            // row at all, and focus-sq7's ruling is that a thing the app did gets a row. The
            // receipt is the whole condition now: a rung that was never perceived is `unopened`,
            // whichever surface it was standing on.
            // **…and not one the ledger has already spoken for** (focus-6pr.4). A rung that was
            // written down as `deferred(questionPinned)` was drawn to the person and could not be
            // answered; adding `unopened` beside it when they take their screen back would count
            // one attempt twice, which is exactly what `NudgeUnseenAttemptTests` forbids.
            guard let open = openRung,
                  open.perceived == nil,
                  !open.deferredBehindThePinnedQuestion
            else { return }
            write(
                InterventionEvent(
                    kind: .accusation,
                    rung: open.rung.kind,
                    subject: open.rung.subject ?? "",
                    surface: open.landedOn,
                    disposition: .unopened,
                    // The same reading as the delivered twin: a rung nobody looked at still had
                    // a reason, and a row that omitted it here would make History's "why" depend
                    // on whether the person happened to open the popover.
                    explanationKinds: open.rung.mandate.explanation.clauses.map(\.kind)
                ),
                priorityID: open.priorityID
            )
        }
    }

    /// **The rung is on the surface it was routed to** — and that is all this says (focus-xix).
    ///
    /// The ladder's business, and only the ladder's: `LadderMachine` resolves the attempt it
    /// recorded in `offer(at:budgetPermits:)` and writes `deliveredAt`, so `currentRung` names the
    /// rung the popover is actually drawing rather than the one below it.
    ///
    /// **Why this is honest for a badge nobody has opened**, when R-81 says a rung nobody could
    /// see must not advance the ladder: R-81's failure is *"arriving at the loudest rung having
    /// shown the person nothing"*, and it cannot happen here. `SurfaceRouter` reaches
    /// `.popoverBadge` from the `.panel` rung alone, `LadderRung.Kind.panel.escalated()` is `nil`,
    /// and U-2 deleted the rung above it — so this advance can never carry the ladder past
    /// anything. What R-81 protects that *is* still at stake — the day's budget, the fatigue run
    /// and the ledger — is exactly what `deliveredRung(…)` holds back until somebody looks.
    private func landed(on surface: NudgeSurface) {
        ladder.reduce(.delivery(.delivered(surface)), now: monotonicClock.elapsed, tunings: tunings)
    }

    /// The bookkeeping of a rung that has actually reached somebody — `deliverQuestion(…)`'s twin,
    /// and now a twin in the one respect that matters: it is called from the moment of *reaching*,
    /// never from the moment of landing.
    ///
    /// One function and one call per rung, so "delivered" cannot be recorded twice for a badge
    /// rung that lands once and is looked at once.
    /// - Parameter change: **the receipt, and there is no default** (focus-1b5, focus-nrl). The
    ///   surface is read off it rather than passed beside it, so a proof taken on one surface
    ///   cannot be spent on another. `PerceptibleChange` has a `fileprivate` initialiser and one
    ///   producer, pinned by R-96p — which is what makes *charging without a perceptible change*
    ///   a thing that cannot be written down rather than a thing a test hopes to catch.
    private func deliveredRung(
        rung: LadderRung,
        provenBy change: PerceptibleChange,
        priorityID: UUID?
    ) {
        deliveredCount += 1
        chargesPaidFor.append(change)

        // **The row, and the charge FROM the row** — the shape `NudgeReplay` uses, for the same
        // reason. The event is built once and every consumer is derived from it, so the record
        // and the price of the rung cannot disagree.
        let event = InterventionEvent(
            kind: .accusation,
            rung: rung.kind,
            subject: rung.subject ?? "",
            surface: change.surface,
            disposition: .delivered,
            // **The shape of the reason, off the mandate the rung was raised on** (v7,
            // focus-tee.3). `LadderRung` carries the mandate and the mandate carries the
            // `Explanation`, so the row records what the verdict was going on rather than what a
            // later replay would decide today — which is the conflation the epic's §8.4 forbids.
            // Only the clause *kinds*: closed enum, no payload, no token, no number.
            explanationKinds: rung.mandate.explanation.clauses.map(\.kind)
        )

        // **The cooldown is a spend, and it is charged like one** (focus-uru). This line read
        // `fatigue.reduce(.delivered(.accusation), …)`, unconditionally, on a branch that reaches
        // the glyph as well as the panel — so an ambient rung that spent neither cap still armed
        // `RelevancePolicy.mandateCooldown`. `InterruptionCharge` is the single derivation of
        // *"did this speak to anybody?"* and `FatigueEvent.delivered` now takes one, so the
        // question is asked once and answered for both.
        //
        // The **row** is written either way and that is deliberate: a delivered ambient rung is a
        // delivery — the Intervention pane draws it, `deferredRungShare` counts it (focus-sq7) —
        // and it is not an interruption.
        if let charge = InterruptionCharge(event, priorityID: priorityID) {
            fatigue.reduce(.delivered(charge), now: monotonicClock.elapsed, tunings: tunings)
        }
        openRung?.recordID = write(event, priorityID: priorityID)
    }

    @discardableResult
    private func write(_ event: InterventionEvent, priorityID: UUID?) -> UUID? {
        do {
            return try log.record(event, priorityID: priorityID)
        } catch {
            logger.error(
                """
                the intervention log refused a write: \
                \(error.localizedDescription, privacy: .public)
                """
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
        proofs.run {
            // **An action that cannot write what it promises is refused whole** (focus-rdw).
            //
            // Every surface withdraws these two when there is no session — `offeredActions` asks
            // the same question this does — so no click can arrive here. It is a guard rather than
            // a comment because the alternative shape is what the defect *was*: `apply(_:…)`
            // returned early on the missing session id and the rest of this function ran on,
            // completing the row as `.corrected`, spending fatigue and de-escalating the ladder for
            // a write that never happened. Refusing before any of that is what makes "offered or
            // nothing" one rule rather than two places that have to agree.
            //
            // Nothing is taken off screen: a click the loop refused must not look to the person
            // like a click it obeyed.
            if action.requiresOpenSession, currentSessionID?() == nil {
                logger.error(
                    """
                    a correction that needs an open session reached the loop with none \
                    (\(action.rawValue, privacy: .public)); it is refused
                    """
                )
                return
            }

            let now = monotonicClock.elapsed
            let scope = openRung.map(\.rung.mandate).flatMap(CorrectionScope.from)

            // **The rung's own key and the rung's own row, not the live pointer** (focus-lmo,
            // focus-xix). Read before `apply(…)`, which is the function that hands the outcome to
            // whoever writes it. The row is the rung's because the click was on the rung: a badge
            // question can be delivered and open at the same moment, and the outcome of a
            // correction belongs to the accusation it corrected.
            let priorityID = openRung?.priorityID
            let recordID = openRung?.recordID

            let outcome = action.outcome(
                scope: scope,
                at: dateProvider.now,
                snoozeDuration: snoozeDuration
            )
            // **The record is completed before the world moves** (focus-mwm).
            //
            // This was below `apply(…)`, and `apply(…)` is the statement that hands the outcome to
            // whoever performs it — which for "Pause" is now e03's session machine, reached
            // directly. Pausing takes the session out of `.focus`, `NudgeLifecycleWatch` turns that
            // level into an edge, and `phaseLeftFocus()` closes the open rung as **`.ignored`** —
            // all of it synchronously, inside this function, before the line that used to write the
            // outcome. `InterventionLog.complete` is first-wins, so the day's record said the
            // person had ignored the very nudge they had just answered.
            //
            // Measured only once "Pause" actually paused: with the cockpit closed the old code sent
            // a command into a buffer and nothing moved, and with it open `CorrectionTotalityTests`
            // registered a handler that recorded the command and did not pause either. The
            // falsified row was reachable in the shipping app the whole time, on the ordinary path,
            // whenever the main window happened to be open.
            //
            // Recording first is not "record before you know": the refusal above has already run,
            // so by this line the loop has decided the click is one it will honour.
            if let interventionOutcome = Self.outcome(of: action) {
                complete(interventionOutcome, recordID: recordID)
                fatigue.reduce(.accusationResolved(interventionOutcome), now: now, tunings: tunings)
            }

            apply(outcome, action: action, now: now, priorityID: priorityID)

            if let deEscalation = action.deEscalation {
                ladder.reduce(.deEscalated(deEscalation), now: now, tunings: tunings)
            } else {
                // A dismissal is not an answer. It counts towards the backoff, which is what stops
                // the app talking to itself (R-83).
                ladder.reduce(.rungIgnored, now: now, tunings: tunings)
            }

            // A rung is being answered, not a question. What comes down is **the rung's surface**,
            // and a question ends here only if it was sharing it.
            //
            // **And when it was sharing it, the question is written down** (focus-h0s). This branch
            // was the fifth producer of `.worldMovedOn` and the only one that did not call
            // `expireOpenQuestion()` first, so Ctrl-Cmd-R aimed at the menu-bar glyph — or any
            // correction pressed on an accusation while a question stood on the panel — destroyed a
            // question the person could see, wrote nothing about it, and asked it again later. It
            // is not repaired by a sixth caller remembering: the record moved inside
            // `endOpenQuestion(_:)`, which is the one door, and the exit carries whether one is
            // owed.
            //
            // This was `closeSurfaces(endingAnyQuestionAs: .worldMovedOn)` on the argument that a
            // question still open at this point was an anomaly to be tidied away. It is no longer
            // an anomaly: a badge question waiting behind a click does not hold the slot, so an
            // accusation is admitted while one pends, and the unconditional form threw that
            // question away — the badge went dark and the subject the person was about to be asked
            // about was dropped — because they dismissed a nudge about something else. U-2 keeps
            // the question affordance in full; a correction aimed at an accusation must not spend
            // it.
            if let openQuestion, openQuestion.surface == .panel {
                closeSurfaces(endingAnyQuestionAs: .worldMovedOn, andAnyRungAs: .answered)
            } else {
                panel.hide()
                endOpenRung(.answered)
            }
        }
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
    func selectQueryScope(_ scope: CorrectionScope) {
        guard let question = openQuestion,
              CorrectionScope.from(question.warrant).answerScopes.contains(scope)
        else {
            logger.error("refused a query scope outside the content the question identified")
            return
        }
        openQuestion?.selectedScope = scope
    }

    func answer(_ answer: QueryAnswer) {
        proofs.run {
            // **Answering a question ends the question, and nothing else** (focus-ti4, focus-nrl).
            //
            // This was `closeSurfaces(endingAnyQuestionAs: .answered)`, which is *take everything
            // down*: the question, then `panel.hide()`, then the rung. The last two
            // belong to a session ending or a commitment changing, and they are wrong here — an
            // answer is a statement about one subject, and the accusation standing beside it is
            // about another.
            //
            // Found by folding the charging invariant over the space rather than down a scenario.
            // With a question waiting behind the click and an ambient rung under it, the sequence
            // was: the rung lands, the item goes on drawing the badge's `waiting` so nothing is
            // charged (focus-nrl, repaired) — then the answer clears the badge, the redraw drops
            // the item to the rung's own `noticing`, **the rung is charged for that write**, and
            // the very next statement forgets the rung and writes the item back to `unmarked`. Two
            // assignments in one turn, a charge taken for the first, and a person who saw a flash
            // between two frames if they saw anything at all. That is this epic's defect one
            // generalisation further out, and the honest repair is not to refuse the charge — the
            // item really did change — but to stop destroying a rung nobody asked to have
            // destroyed.
            //
            // R-87 is the same ruling from the other side: the ambient rung stays on through a
            // *snooze*, because it is a state and not a sentence. A question about another
            // application is far less than a snooze.
            //
            // `endOpenQuestion(_:)` still takes down the surface the question was on — it hides the
            // panel for a panel question and redraws the popover for a badge one — so the surface
            // half of the exit is unchanged. What is gone is the collateral.
            defer { endOpenQuestion(.answered) }

            // **One guard, because there is one value** (focus-zrs). This was two — the warrant,
            // then `guard let priorityID = openQuestionPriorityID else { return }` inside the `do`
            // — and the second one is where the person's click went when the two readings of the
            // active priority disagreed: dropped in silence, with the `defer` above tidying the
            // panel away. A question that exists knows what commitment it is about, because it
            // cannot be constructed without one.
            guard let question = openQuestion else { return }
            let questionScope = CorrectionScope.from(question.warrant)
            let scope = question.selectedScope ?? questionScope
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
                    questionScope: questionScope,
                    reason: question.warrant.reason,
                    askedAt: question.askedAt
                )
                if answer == .yesAddIt { correctedSubjects.insert(scope.subject) }
                // The question's own key, so the undo the composition root registers belongs to the
                // same commitment the ledger just wrote the rule under (focus-lmo).
                onCorrection?(outcome, question.priorityID)
            } catch {
                logger.error(
                    """
                    the query ledger refused an answer: \
                    \(error.localizedDescription, privacy: .public)
                    """
                )
            }

            // The question's own row (focus-xix), read off the value that has carried every other
            // fact about this asking since `ask(…)` built it.
            complete(.answered, recordID: question.recordID)
            fatigue.reduce(.queryResolved(answer.outcome), now: now, tunings: tunings)
        }
    }

    /// Escape, or the panel's close affordance.
    ///
    /// `.declined` for a question — because a person who closed the panel has answered it, and
    /// treating that as "nothing happened" is what makes an app ask again tomorrow — and
    /// `.dismissed` for an accusation, which writes nothing and is allowed to (D-07).
    private func dismissWhateverIsOpen() {
        // **This is the *panel's* Escape, so it asks what the panel is carrying** — not whether
        // this object is holding a question anywhere.
        //
        // `openQuestion != nil` was a safe spelling only for as long as a question on any surface
        // held the interruption slot, because that made "a question exists" and "the panel is
        // showing it" the same state. They are no longer the same state: a badge question waiting
        // behind a click does not hold the slot, so an accusation can be on the panel while one
        // pends. Under the old spelling, Escape on that accusation panel would answer `.notNow`
        // to a question that is not on the screen — writing a receipt, settling the subject under
        // gate 11, and leaving the accusation the person actually meant to dismiss still up.
        if let openQuestion, openQuestion.surface == .panel {
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
            // `resolve(_:snoozeDuration:)` refuses the action outright when there is no session,
            // so this is unreachable rather than load-bearing — and it stays, because the
            // identifier has to be unwrapped to key the box either way.
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
    ///
    /// - Parameter recordID: the row belonging to **this** interruption. Named rather than read
    ///   off a shared field, for the reason `complete(_:recordID:)` takes one.
    private func undeliverRecord(
        _ recordID: UUID?,
        kind: InterruptionKind,
        subject: String?,
        priorityID: UUID?
    ) {
        guard withdraw(recordID) else {
            record(
                deferral: .noSurfaceAvailable,
                kind: kind,
                subject: subject,
                priorityID: priorityID
            )
            return
        }
        deferredCount += 1
        deferralsByReason[.noSurfaceAvailable, default: 0] += 1
        ladder.reduce(
            .delivery(.deferred(.noSurfaceAvailable)),
            now: monotonicClock.elapsed,
            tunings: tunings
        )
    }

    /// Take one named row off the day's spend.
    ///
    /// The counterpart of `complete(_:recordID:)` for an interruption that ended without ever
    /// reaching anybody. One place, so a path that un-delivers a nudge cannot take it off the
    /// ladder and leave it on the budget.
    ///
    /// - Returns: whether a delivery was actually taken back.
    @discardableResult
    private func withdraw(_ recordID: UUID?) -> Bool {
        guard let recordID else { return false }
        do {
            return try log.withdraw(recordID)
        } catch {
            logger.error(
                """
                the intervention log refused a withdrawal: \
                \(error.localizedDescription, privacy: .public)
                """
            )
            return false
        }
    }

    /// Complete one named row.
    ///
    /// **There is no unnamed form of this any more** (focus-7w3, focus-xix). It used to have one:
    /// `complete(_:)` read a single `openRecordID` field, on the assumption that this loop can
    /// only ever be holding one row. The badge broke that assumption for both kinds of nudge —
    /// a delivered badge accusation and a delivered badge question can be open at the same time,
    /// in the same popover, because neither holds the interruption slot — so the field named
    /// whichever was written **last**. Answering the question then completed the accusation's row
    /// with `.answered` and left the question's open for ever, and answering the accusation
    /// completed the question's row with `.corrected`: an outcome written onto an intervention
    /// nobody performed it on, which is exactly the falsified row focus-7w3 was about, reached by
    /// a different door.
    ///
    /// The row now lives **on** the interruption it belongs to — `OpenQuestion.recordID` and
    /// `OpenRung.recordID` — so there is no shared field left for two open nudges to fight over,
    /// and a caller cannot ask for "the open row" because no such thing is offered.
    private func complete(_ outcome: InterventionOutcome, recordID: UUID?) {
        guard let id = recordID else { return }
        do {
            try log.complete(id, outcome: outcome)
        } catch {
            logger.error(
                """
                the intervention log refused a completion: \
                \(error.localizedDescription, privacy: .public)
                """
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
        // **The question ends before the window goes, never after** (focus-h0s). The ledger's
        // rule is that a receipt needs the surface provably readable at both ends, so the record
        // has to be taken while the panel is still up — which is why this line moved above the
        // withdrawal rather than the expiry staying beside it as a second statement. The panel is
        // ordered out by `endOpenQuestion(_:)` on its way through; the withdrawal below is still
        // what drops `.fullScreenAuxiliary`, which `hide()` does not.
        //
        // The slot is released by this and `endOpenRung(_:)` and by nothing else: it is derived
        // from the question and the rung, so forgetting them **is** giving it back (focus-zrs).
        endOpenQuestion(.worldMovedOn)
        panel.withdrawForPresentation()
        // **And the ladder is finally told** (focus-s4m). This was `forgetOpenRung()`, which
        // touched no ladder state at all — so the promise three paragraphs up was kept for the
        // *rung* the ladder was standing on and broken for the delivery underneath it: the panel
        // came off the screen, `deliveredAt` stayed written, the escalation clock went on running
        // through the presentation, and at the top rung `candidate(at:budgetPermits:)` answered
        // `nil` for the rest of the run. `RungExit.presentationWithdrew` takes the delivery back,
        // which is what "resumes at the rung it never left" has always meant.
        endOpenRung(.presentationWithdrew)
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
        proofs.run {
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
                // The row is read off the question before `endOpenQuestion(_:)` forgets it: the id
                // lives on the question now, so the order of these two lines is load-bearing.
                let recordID = question.recordID
                endOpenQuestion(.surfaceWentOutOfReach)
                // The delivery is taken off the budget as well as off the screen (focus-mfc),
                // against the question's own key rather than the live pointer (focus-lmo).
                undeliverRecord(
                    recordID,
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
                """
                the display changed under a rung and stranded it: \
                \(reading.summary, privacy: .public)
                """
            )
            panel.hide()
            // **One door, and the take-back is what the door is for** (focus-s4m). This was three
            // statements — `ladder.undeliver`, `undeliverRecord(…)` and `forgetOpenRung()` — and
            // it was the *only* one of the six rung endings that took a delivery back. Two of the
            // other five needed one and had none. `RungExit.displayStranded` is this ending stated
            // as a case, and `takesBackTheDelivery` is the property the other two are now measured
            // against rather than compared with by eye.
            endOpenRung(.displayStranded)
        }
    }

    /// Everything comes down, and each open nudge ends by the exit named for it.
    ///
    /// **Two exits, because there are two nudges** (focus-s4m). This took one, and the rung's half
    /// was `forgetOpenRung()` — a call that says nothing about *why*, which is how the same
    /// statement came to serve a correction the person pressed, a session that ended and an
    /// application that quit. `RungExit` makes the caller say which.
    private func closeSurfaces(
        endingAnyQuestionAs questionExit: QuestionExit,
        andAnyRungAs rungExit: RungExit
    ) {
        endOpenQuestion(questionExit)
        panel.hide()
        endOpenRung(rungExit)
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

        // **The record, and it is the first of the three because it is a reading** (focus-h0s).
        //
        // `QuestionLedgerPolicy` refuses a receipt unless the surface is provably readable *now*
        // as well as at the ask, so the write has to happen while the question is still on the
        // screen it was asked on — before the two statements below take that screen away. This
        // was four callers each remembering to call `expireOpenQuestion()` first, and
        // `resolve(_:snoozeDuration:)` was the fifth and did not: an accusation dismissed on the
        // glyph took a question off the panel with no row, no receipt and the interruption still
        // charged. The exit says whether a record is owed; nobody has to remember one.
        if exit.recordsAnExpiry { expireOpenQuestion() }
        // **And the other record: an invitation that was never opened** (focus-sq7, focus-6vz).
        // Keyed on the receipt inside — a question that was never perceived is unopened, whichever
        // surface it was standing on — and refused for the one ending where the app has already
        // written a row of its own: `ask(…)`'s refusal to deliver into an unreadable panel writes
        // the deferral itself, and a second row here would count one attempt twice.
        if exit.owesAnUnopenedRow { recordUnopenedInvitation(.query) }
        // **And the row this question's delivery wrote gets its one remaining field** (focus-gmr,
        // R-79). An `InterventionRecord` gains exactly one thing after it is written: what the
        // person did. Nothing filled it in for a question that ended any way but an answer, so a
        // question somebody really opened and really read stayed `delivered` with `outcome = nil`
        // for ever — the app saying it interrupted somebody and never saying how it turned out.
        // Which endings owe it is `QuestionExit`'s answer, beside `recordsAnExpiry`, for the
        // reason that one is there: a line a caller can omit is a line four callers remember and
        // a fifth does not.
        if let outcome = exit.aftermath.outcome {
            complete(outcome, recordID: question.recordID)
        }
        // **And the run that bounds how often the app may ask** (focus-fwy). The accusation's twin,
        // one function over: `FatigueController` heard about a question from `answer(_:)` alone, so
        // `InterventionPolicy.ignoredQueryBackoff` counted only questions the person **pressed
        // something on** — "Not now" and Escape extend the run because `.declined` is not an
        // answer — and a question they never touched advanced nothing at all. ⌃⌘H is the exit that
        // makes that reachable on purpose: F-81 says the question is still unanswered and will be
        // offered again, and until this line nothing bounded how often.
        if exit.countsAsAnUnansweredQuestion {
            fatigue.reduce(.queryResolved(.expired), now: monotonicClock.elapsed, tunings: tunings)
        }

        let surface = question.surface

        // One assignment, because the question is one value. It used to be six lines, and the
        // whole of focus-zrs was that a path could take some of them and not others — or, worse,
        // that one of them was `nil` from the beginning.
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

    /// **The one door out of a delivered rung** — `endOpenQuestion(_:)`'s twin, for the twin
    /// reason (focus-s4m, focus-fwy, focus-uru, focus-v0u, focus-xix).
    ///
    /// A question's ending has been a closed vocabulary with one door since focus-v0u. A rung's
    /// ending was six hand-written doors, and the three things an ending has to settle — the
    /// ladder, the row, the two backoffs — were distributed across them by memory. Two of the six
    /// told the ladder nothing at all: `hideOverlays()` left it standing at
    /// `.engaged(rung: .panel, deliveredAt:)` with `candidate(at:budgetPermits:)` answering `nil`
    /// for ever, so ⌃⌘H **permanently silenced the only rung that says anything**, and
    /// `withdrawForPresentation()` had the same hole under a doc comment promising the opposite.
    ///
    /// So every consequence moves onto `RungExit`, where it is a property of the *kind* of ending
    /// rather than a line a caller can omit, and this is the only place in this object that lets a
    /// rung go. `RungExit`'s three `switch`es are exhaustive: a seventh door does not compile
    /// until somebody has ruled on the ladder, the row and the backoffs for it.
    ///
    /// The badge's answers go with the rung they belonged to. An open popover still offering
    /// *"this is relevant"* for a rung this host has forgotten is the accusation half of
    /// focus-v0u's orphan, and `resolve(…)` would drop the click in a `guard`.
    private func endOpenRung(_ exit: RungExit) {
        guard let leaving = openRung else { return }
        let now = monotonicClock.elapsed

        // **Before the rung this host is holding is let go of** (focus-sq7). Replacement counts as
        // much as forgetting: a fresh rung replaces a badge rung and the first invitation used to
        // vanish with no row at all.
        recordUnopenedInvitation(.accusation)

        if exit.takesBackTheDelivery {
            // **Both halves of "un-delivered", together** (R-81, focus-mfc). `ladder.undeliver`
            // stops the escalation clock and puts the ladder back where it stood, so the same rung
            // is offered again; `undeliverRecord(…)` stops the spend, because a nudge nobody could
            // answer that kept `disposition == .delivered` went on charging the day's interruption
            // budget — and under U-1 the budget is what decides whether the app may speak again.
            //
            // The rung's own key, not the live pointer (focus-lmo): this row is a statement about
            // the accusation that was taken back, and that accusation was about one commitment.
            ladder.undeliver(at: now)
            // **And only a rung somebody was shown has a spend to take off.** The ladder is told
            // either way — `landed(on:)` advances it whether or not the seam could prove anybody
            // saw the rung — but the budget is not: an unpaid rung has no delivered row, and
            // `recordUnopenedInvitation(.accusation)` above has already written the `unopened` one
            // that is true of it. `undeliverRecord(…)` writes a fresh deferral when it finds no
            // open row to turn, which is right for a delivery whose write failed and wrong here:
            // it would record one attempt twice, as a deferral and as an unopened invitation.
            if leaving.perceived != nil {
                undeliverRecord(
                    leaving.recordID,
                    kind: .accusation,
                    subject: leaving.rung.subject,
                    priorityID: leaving.priorityID
                )
            }
        }
        // **The question's treatment, given to the accusation** (focus-gmr's shape). A rung that
        // was delivered and is now being replaced, hidden or outlived with nothing pressed on it
        // was ignored, and its row said `delivered` with no outcome for ever, exactly as the
        // question's did. `complete(_:recordID:)` is first-wins and refuses a row that is no
        // longer a delivery, so a correction that has already filled this in is safe — and the
        // take-back above is why this is asked of the exit rather than done unconditionally: a row
        // being withdrawn from the day's spend must not also carry an outcome.
        if exit.leavesTheInterruptionUnanswered {
            complete(.ignored, recordID: leaving.recordID)
        }
        // **The two instruments named for "the app is talking to itself"** (focus-fwy). Both are
        // bounded by `InterventionPolicy.ignoredAccusationBackoff` and both were reduced from one
        // place — `resolve(_:snoozeDuration:)`, for the single non-de-escalating correction there
        // is — so they counted accusations the person clicked away and never the ones they left on
        // screen and pressed a key to be rid of.
        //
        // **Asked of the rung twice as well as of the exit**, and both clauses were measured
        // rather than reasoned. `makesAnAccusation` is the ladder's own derivation of *"does this
        // rung say something a person could answer?"*, the one `SilenceSubject` and
        // `InterventionEvent.spendsTheAccusationCap` already read: the glyph accuses nobody, so it
        // cannot be ignored, and without this the ordinary glyph-to-panel escalation would spend a
        // step of the backoff on the app's own climb. `perceived` is `PerceptibleChange`'s receipt
        // and it is the whole of what *"it reached them"* means: without it, a panel rung routed to
        // the popover badge under the silent-and-visual deck — landed, never opened, charged
        // nothing — counted as an accusation somebody ignored, and two of them held the app silent
        // for `InterventionPolicy.backoffSpan`.
        if exit.countsAsAnIgnoredAccusation,
            leaving.rung.kind.makesAnAccusation,
            leaving.perceived != nil {
            ladder.reduce(.rungIgnored, now: now, tunings: tunings)
            fatigue.reduce(.accusationResolved(.ignored), now: now, tunings: tunings)
        }

        openRung = nil
        // **And the panel is taken down when the rung leaves it** (focus-my0). The badge has had
        // this since focus-uru — *"replacing a rung is as much a change as forgetting one"* — and
        // the panel, which is the surface that carries a sentence and six things to press, had
        // nothing. Driven: sustained drift into one application reaches its panel rung, then one
        // judgement about a **second** application resets the ladder and the ambient rung replaces
        // the panel rung. The panel stayed on screen naming the first application, with Pause and
        // Change priority live, while `resolve(_:snoozeDuration:)` reads whatever rung this host is
        // holding now — so the click would have written a correction about the wrong application.
        //
        // Asked of what the panel is actually drawing rather than of `landedOn == .panel` alone: a
        // panel showing a question is not this rung's to order out, and `endOpenQuestion(_:)` owns
        // that half.
        if leaving.landedOn == .panel, panel.showing == .accusation { panel.hide() }
        redrawTheMenuBar(movingFrom: leaving.landedOn, to: nil)

        assert(openRung == nil, "a rung ended by \(exit.rawValue) and is somehow still open")
    }

    /// **The one place a rung that has landed is written down**, and it ends nothing.
    ///
    /// Every ending goes through `endOpenRung(_:)`, including the replacement that used to be
    /// hidden here: `accuse(…)` calls it before `landed(on:)`, because
    /// `RungExit.countsAsAnIgnoredAccusation` reduces an event `LadderMachine` interprets against
    /// the state it is standing in, and an ignore reduced after the new delivery had been recorded
    /// would be counted against the rung that has just landed. So by this line there is nothing to
    /// let go of, and the assertion says so rather than a comment hoping it.
    private func setOpenRung(_ rung: OpenRung) {
        assert(openRung == nil, "a rung landed on top of one this host had not ended")
        openRung = rung
        redrawTheMenuBar(movingFrom: nil, to: rung.landedOn)
    }

    /// Ask the composition root to redraw the menu bar, when this rung's move changed what it is
    /// drawing.
    ///
    /// The popover's *contents* changed: a badge rung arriving, leaving, or being replaced by
    /// another badge rung. That last one is why this is not folded into the mark below — the mark
    /// is `.waiting` on both sides of a replacement, and the popover would go on drawing the
    /// accusation this host has already forgotten.
    ///
    /// **And the status ITEM changed** (focus-mkk). `accuse(…)` records the glyph landing as a
    /// delivery on the ground that "the glyph is redrawn on the next refresh", and until that
    /// clause nothing asked for one: the redraw was requested only when the badge was involved, so
    /// an ambient rung landed, was charged, and reached a menu bar that would not be told about it
    /// until the next five-second corroboration tick — which drew from the status and the timer
    /// anyway, and both were unchanged.
    ///
    /// Asked as `menuBarAttention`, which is the surface's own answer, rather than as
    /// `== .menuBar`: a fifth surface that the item speaks for inherits the redraw instead of
    /// needing a second clause here.
    private func redrawTheMenuBar(movingFrom before: NudgeSurface?, to after: NudgeSurface?) {
        let touchesTheBadge = before == .popoverBadge || after == .popoverBadge
        let markChanged = (before?.menuBarAttention ?? .unmarked)
            != (after?.menuBarAttention ?? .unmarked)
        if touchesTheBadge || markChanged { onQuestionSurfacesChanged?() }
    }

    /// **A nudge the person can still see and answer that this host has forgotten** — and it is
    /// always empty (focus-v0u, focus-xix).
    ///
    /// The invariant `endOpenQuestion(_:)` and `endOpenRung(_:)` exist to keep, stated as a
    /// reading rather than as a comment so the unit lane can drive every exit and the self-check
    /// can report it. A non-empty answer is the defect itself: a live panel or an open popover
    /// offering answers that `answer(_:)` or `resolve(_:snoozeDuration:)` will drop in a `guard`,
    /// and a nudge that will therefore be raised again.
    ///
    /// **It was `orphanedQuestionSurfaces` and it read half the screen.** The reading was built
    /// for focus-v0u, which was a question left drawn on a surface the loop had forgotten — and
    /// the accusation can be left in exactly the same state on exactly the same two surfaces,
    /// with a worse consequence, because `resolve(…)` does *not* drop the click: it applies the
    /// correction to whatever rung this host is holding now. So the invariant that watched one
    /// half now watches both, and `MenuBarNudge.allCases` in `isDrawing(_:)` is what stops a
    /// third from being watched for one and not the other.
    ///
    /// **`isDrawing(_:)` and deliberately not `decisionSurfaceReading(of:)`** (focus-5yu). This
    /// invariant is about a nudge a person can still press something on, and an action scrolled
    /// below the fold is one scroll away from being pressed. The stricter reading is what decides
    /// a *charge*; asking it here would file the dangerous case as no case at all.
    ///
    /// **And it asks where the nudge is, not whether there is one** (focus-my0). This read
    /// `openQuestion == nil` and `openRung == nil` — *"is this host holding nothing?"* — which is
    /// the same question as the one in the title only if the loop holds at most one nudge at a
    /// time across all surfaces. It does not, and that is deliberate: the glyph and the badge
    /// exist precisely so an accusation can stand somewhere while something else is on the panel.
    /// So the one state this reading was built for was a state it answered `[]` for. Driven:
    /// drift into one application to its panel rung, then drift into a second, and the ambient
    /// rung for the second replaces the panel rung for the first with the panel still up and
    /// still clickable — `openRung != nil`, and the reading saw nothing, in every suite that
    /// asserts it and in the self-check that publishes it.
    ///
    /// Over `MenuBarNudge.allCases` rather than as two hand-written pairs, for the reason
    /// `popoverPresented()` and the accountant's seam are: the question and the accusation have
    /// been given this treatment by hand before, and the hand has been wrong.
    var orphanedNudgeSurfaces: [NudgeSurface] {
        var orphans: Set<NudgeSurface> = []
        for nudge in MenuBarNudge.allCases {
            let heldOn: NudgeSurface?
            switch nudge {
            case .query: heldOn = openQuestion?.surface
            case .accusation: heldOn = openRung?.landedOn
            }
            if panel.isVisible, panel.showing == Self.panelKind(of: nudge), heldOn != .panel {
                orphans.insert(.panel)
            }
            if menuBar.isDrawing(nudge), heldOn != .popoverBadge {
                orphans.insert(.popoverBadge)
            }
        }
        return orphans.sorted { $0.rawValue < $1.rawValue }
    }

    /// Wired by the composition root, which is the only object that knows the menu bar and the
    /// nudge loop both exist. Called when a question **or an accusation** arrives at or leaves a
    /// menu-bar surface, because the popover on screen is a hosting controller built from the
    /// presentation the menu bar was last handed and does not rebuild itself.
    ///
    /// The accusation half is focus-uru's: the badge only became something a person can answer
    /// once the popover started drawing `pendingPopoverAccusation`, and a surface that gains
    /// answers on the next unrelated refresh is a surface whose answers arrive late.
    var onQuestionSurfacesChanged: (@MainActor () -> Void)?

    // MARK: - Transitions that end everything

    /// The session ended. Both fatigue runs die with it, the ladder resets, and every snooze and
    /// correction goes with them — because all three are statements about a session that is over.
    func sessionEnded() {
        proofs.run {
            let now = monotonicClock.elapsed
            fatigue.reduce(.sessionEnded, now: now, tunings: tunings)
            ladder.reduce(.deEscalated(.sessionEnded), now: now, tunings: tunings)
            clearSessionState()
        }
    }

    /// The session left `.focus` — a break, a detour, an interruption, completion.
    func phaseLeftFocus() {
        proofs.run {
            ladder.reduce(.deEscalated(.phaseLeftFocus), now: monotonicClock.elapsed, tunings: tunings)
            closeSurfaces(endingAnyQuestionAs: .worldMovedOn, andAnyRungAs: .worldMovedOn)
        }
    }

    /// **The application is quitting** (focus-gmr).
    ///
    /// Quit is an exit, and it was the one exit the nudge loop had never heard of: nothing in the
    /// programme reached this object from `applicationWillTerminate`, so an unopened badge
    /// invitation at quit wrote no `unopened` row and a delivered nudge on screen at quit left its
    /// `InterventionRecord` at `delivered` with no outcome for ever. That is the record focus-sq7
    /// exists to produce, missing at one of the commonest exits of the day — a day on which the
    /// app raised its top rung and the person quit without looking read exactly like a day the
    /// ladder never left the glyph.
    ///
    /// It is `worldMovedOn` and not `screenReclaimed`: quitting is not the person asking for the
    /// screen back mid-nudge, it is the world ending under a question that was on screen — so the
    /// asking is written down as an expiry, and, because an expiry is not an answer (focus-qds),
    /// the question is still askable tomorrow.
    ///
    /// It writes and it decides nothing else. No ladder reset, no snooze cleared, no session
    /// touched: quitting is not a correction and must not read as one.
    func applicationWillTerminate() {
        proofs.run {
            closeSurfaces(endingAnyQuestionAs: .worldMovedOn, andAnyRungAs: .worldMovedOn)
        }
    }

    /// A different commitment. Every earlier observation is evidence about a different question,
    /// and — because the ledger is keyed on the priority — every question legitimately re-opens.
    func priorityChanged() {
        proofs.run {
            ladder.reduce(.deEscalated(.priorityChanged), now: monotonicClock.elapsed, tunings: tunings)
            // The anchor was judged relevant to the commitment that was left; "Back to …" must
            // not offer it as the way back to a different one.
            returnAnchor = nil
            clearSessionState()
        }
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
            return badgeReadability(of: .query)
        case .menuBar, .notification, nil:
            return .unknowable
        }
    }

    /// **Whether the popover is a surface this question could be read and answered on**
    /// (focus-kby, focus-xix, focus-5yu).
    ///
    /// `MenuBarController.isPopoverShown` and `isDrawing(_:)` are both knowable and were both
    /// unread. A closed popover is `unknowable` rather than `notReadable`: nothing can be
    /// established about a surface that is not on screen, and both answers refuse the write.
    ///
    /// **One function taking the kind**, rather than one that hard-codes the question. That
    /// hard-coding was focus-xix's root at this level: the reading existed, the rung had no way
    /// to ask for it, and the branch that should have taken it assumed instead.
    ///
    /// **And the open case is a geometry now, not a second boolean** (focus-5yu). The `.panel`
    /// case above has asked `everyActionIsReachable` since focus-vpu; this one asked whether the
    /// popover was carrying the question, which a popover whose three answers are off the bottom
    /// of the display answers yes to. A receipt written on that reading silences the question for
    /// the life of the priority.
    private func badgeReadability(of nudge: MenuBarNudge) -> SurfaceReadability {
        guard menuBar.isPopoverShown else { return .unknowable }
        guard menuBar.isDrawing(nudge) else { return .notReadable }
        return menuBar.decisionSurfaceReading(of: nudge).everyActionIsReachable
            ? .readable
            : .notReadable
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
                """
                the question could not be recorded: \
                \(error.localizedDescription, privacy: .public)
                """
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
    ///
    /// **One caller, and it is the door** (focus-h0s). It had five, of which four were the
    /// lifecycle callbacks and the fifth — `resolve(_:snoozeDuration:)` — was missing. Four call
    /// sites remembering and one forgetting is the by-hand parity that produced the badge beads,
    /// and it produced this one too: a keyboard shortcut aimed at the glyph destroyed a question
    /// on the panel with nothing written down. `endOpenQuestion(_:)` asks
    /// `QuestionExit.recordsAnExpiry` and calls this; nothing else may.
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
        closeSurfaces(endingAnyQuestionAs: .worldMovedOn, andAnyRungAs: .worldMovedOn)
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
        return presentations.query(
            question.warrant, under: question.commitment, selectedScope: question.selectedScope
        )
    }

    /// **The accusation waiting in the menu-bar popover** (focus-uru), when reduced interruption,
    /// the `silentVisual` deck or a running microphone routed the top rung there (R-92). `nil`
    /// the rest of the time.
    ///
    /// `pendingPopoverQuery`'s twin, and it is a twin down to the guard: the test is **the
    /// surface the router chose**, not "the panel is not up", so a rung the panel deferred cannot
    /// appear in the popover as though it had been routed there.
    ///
    /// It did not exist, and that was the defect: the composition root handed the popover
    /// `currentRung` alone, so the surface drew *"Nudge: Panel"* and offered nothing to press.
    /// The presentation is built by the same `NudgePresentationBuilder` the panel
    /// is drawn from, so the two surfaces cannot disagree about what the rung says, which actions
    /// it offers, or which commitment the click will be written against.
    var pendingPopoverAccusation: AccusationPresentation? {
        guard let open = openRung, open.landedOn == .popoverBadge else { return nil }
        return openRungPresentation
    }

    /// **What the open rung is being drawn from**, whatever surface it landed on.
    ///
    /// One builder, so the panel, the badge and anything that asks *which corrections is this
    /// nudge offering* read the same answer. It is the reading `resolve(_:snoozeDuration:)` has
    /// to agree with: an action this does not offer is one the loop must refuse, and a test that
    /// derived the expected list for itself would be a proof that agrees with itself rather than
    /// with the app (focus-rdw).
    ///
    /// **The rung's own commitment, so a second reading cannot empty it** (focus-xix). This was
    /// `guard let commitment = activeCommitment() else { return nil }` — a guard taken against a
    /// live reading of the surroundings rather than against the value the rung was raised with.
    /// Every redraw of an open popover re-ran it, so the one taken after the commitment went away
    /// answered `nil`: the badge's answers vanished mid-nudge, on a surface the person was
    /// looking at, with the rung still open and `resolve(…)` still willing to write a correction
    /// nothing was offering.
    var openRungPresentation: AccusationPresentation? {
        guard let open = openRung else { return nil }
        return presentations.accusation(for: open.rung, commitment: open.commitment)
    }

    /// What is snoozed right now, for the popover's list and its countdowns.
    func activeSnoozes() -> [MenuBarSnooze] {
        let now = monotonicClock.elapsed
        // Named here rather than in the view, so the popover's Snoozed row says what the panel
        // that raised it said (focus-ebv), and through the same memo — a snooze outlives the
        // application it suppresses far more often than a panel does. `cancelSnooze(subject:)`
        // still takes the identifier, which is what a suppression is filed under.
        //
        // `compactMap` rather than `map`: a snooze on nobody is not a row a person could cancel,
        // and `SnoozeBook` is the only judge of whether one can exist.
        return snoozes.active(at: now).compactMap { snooze in
            naming.subject(snooze.subject).map {
                MenuBarSnooze(subject: $0, remaining: snooze.remaining(at: now))
            }
        }
    }

    /// Cancel one subject's snooze from the popover.
    func cancelSnooze(subject: String) {
        proofs.run {
            snoozes = snoozes.cancelling(subject: subject)
        }
    }

    // MARK: - The keyboard's own route to the economy (F-145, F-81)

    /// One of the four View-menu verbs.
    ///
    /// Every one of them is an action a person can already take by clicking, and F-145's rule is
    /// that a click is never the *only* way. The two that answer a nudge go through
    /// `resolve(_:snoozeDuration:)` — the same function the buttons call — so a key equivalent
    /// and a click are one code path rather than two implementations of one idea.
    func perform(_ command: PriorityCommand) {
        proofs.run {
            // **The same predicate the menu item disables on** (focus-6uf). `guard openRung != nil`
            // was written here twice and nowhere on the item that sends the command, so *Mark as
            // Relevant* and *Snooze Nudge* were permanently enabled and silently did nothing with
            // no nudge on screen. `ShellActionButton` withdraws them from `commandWorld` now, and
            // this refuses on the same question — a stale menu cannot get a verb past the loop.
            guard command.isAvailable(in: commandWorld) else { return }
            switch command {
            case .thisIsRelevant:
                resolve(.thisIsRelevant, snoozeDuration: nil)
            case .snoozeNudge:
                // The shortest span, because a menu item cannot offer three without three items and
                // the shortest is the least presumptuous of them.
                resolve(.snooze, snoozeDuration: tunings.snoozeDurations.first)
            case .hideOverlays:
                hideOverlays()
            case .showMenuBar:
                menuBar.togglePopover()
            // **The three answers, into the one door every answer goes through** (e07a, R-78).
            // `answer(_:)` is what the panel's buttons and the popover's `.answerQuery` reach, so
            // a keyboard answer is the same transaction as a click: the rule and the receipt
            // commit together or neither does. The guard above has already asked
            // `hasOpenQuestion`, and `answer(_:)` asks it again — a key that slipped past a stale
            // menu writes nothing.
            case .answerYes, .answerNo, .answerNotNow:
                guard let queryAnswer = command.queryAnswer else { return }
                answer(queryAnswer)
            case .newPriority, .completePriority, .addFilesToContext,
                 .startSession, .pauseSession, .completeSession, .pauseSensing,
                 .showWalkthrough:
                break
            }
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
        proofs.run {
            panel.hide()
            menuBar.closePopover()
            // **The open question goes with the screen it was on** (focus-kby, F-81).
            //
            // It used to survive: the panel went away and the warrant and its readability stayed,
            // so the next thing to end a question — a session end, a phase change — read the
            // *previous* question's reading against a surface that had been gone for an hour, and
            // the reading it read was the `isVisible` fallback's cheerful `true`. Nothing is
            // written here, which is the whole of F-81: the person asked for their screen back, not
            // to tell the app anything, so the question is still unanswered and will be offered
            // again.
            //
            // **And the exit says so** (focus-h0s). It travelled as `.worldMovedOn`, which is now
            // the exit that *writes*, and it wrote nothing here only because the panel above had
            // already been ordered out and `QuestionLedgerPolicy` refused a receipt it could not
            // prove readable. A rule that holds by accident of statement order is not a rule;
            // `screenReclaimed` is F-81 stated as a case.
            endOpenQuestion(.screenReclaimed)
            // **And the rung gets the same exit, which is the whole of focus-s4m.** This was
            // `forgetOpenRung()`, which touched no ladder state, so the ladder stayed
            // `.engaged(rung: .panel, deliveredAt:)`: `arrive(_:)` returns to `.idle` only at the
            // top rung and only for a different subject, and on the same subject
            // `candidate(at:budgetPermits:)` answers `rung.escalated(for:)`, which is `nil` there —
            // which `NudgeDecider.accuse(…)` turns into `.silent(.budgetExhausted)`. One press of
            // ⌃⌘H and the only rung that says anything never spoke again for the rest of the run.
            //
            // `RungExit.screenReclaimed` is the question's own treatment given to the accusation:
            // the delivery stands, because the person saw it — they pressed a key to make it go
            // away — the row is completed `.ignored`, and both backoffs hear about it. What it is
            // not is a take-back: putting the ladder back where it stood would put the same panel
            // in front of them at the next mandate, which is the app arguing with the one command
            // it has for *stop showing me things*.
            endOpenRung(.screenReclaimed)
            // The rows go with the values that carried them: there is no shared `openRecordID` left
            // to clear, and forgetting the question and the rung above **is** forgetting their rows
            // (focus-xix). It used to be a third line here, and a third line is a third thing a
            // path can fail to do.
        }
    }

    /// The rung the ladder has reached, for the popover.
    var currentRung: LadderRung.Kind? { ladder.state.rung?.kind }

    /// **The surface that rung is actually standing on**, or `nil` when this loop is holding no
    /// rung at all (focus-mkk).
    ///
    /// `currentRung` above is the ladder's name for what it reached; this is where it went, and
    /// the menu bar needs it because the item's mark is a function of the surface rather than of
    /// the rung. Without it `MenuBarPresentation` could not tell an ambient rung on the glyph
    /// from a panel rung in front of the person — and it drew neither, which is how a landing on
    /// the glyph spent an accusation while the glyph did not change.
    ///
    /// The **open** rung, not the ladder's state: the ladder remembers the rung it climbed to
    /// through a deferral and a withdrawal, and the item must go back to being unmarked the
    /// moment the nudge is over.
    var landedRungSurface: NudgeSurface? { openRung?.landedOn }

    /// Today's spend, for the settings pane's usage rows.
    ///
    /// Keyed to the same commitment every row it is summing was written against — read from the
    /// surroundings, which is the one statement of it, rather than from a store read of this
    /// host's own (focus-zrs). A budget summed under a different key from the rows it is about is
    /// a cap that silently stops applying.
    func todaysUsage() -> InterruptionBudget {
        (try? log.budget(on: log.today, priorityID: activeCommitment()?.id)) ?? .empty
    }

    /// **Delivered rows in the store today** — the other half of the charging invariant's join
    /// (focus-1b5, focus-nrl).
    ///
    /// Summed from persisted rows, the way the day's caps are, so that comparing it with
    /// `chargesPaidFor.count` compares two numbers computed by completely different routes: one
    /// from the receipts the perception path issued, one from what is actually written down. A
    /// delivered row with no receipt behind it is a charge that did not go through the door.
    func deliveredRowsToday() throws -> Int {
        try InterruptionKind.allCases.reduce(0) { total, kind in
            total + (try log.deliveredCount(kind: kind, on: log.today))
        }
    }

    /// The four grant-free focus readings from the last time the panel was shown (R-89, §4.5).
    var lastPanelReadings: NudgePanelController.FocusReadings? { panel.readingsAfterShow }
    var readingsBeforePanelShow: NudgePanelController.FocusReadings? { panel.readingsBeforeShow }
    var panelProperties: NudgePanelController.PanelProperties { panel.properties }

    /// **Must be zero in every automated run** (§3.F.37). Published here so the self-check does
    /// not have to reach into the notification boundary for it.
    var requestAuthorizationCallCount: Int { notifications.requestAuthorizationCallCount }
    /// **`nil` until a read has landed** (focus-652). The self-check publishes `"unread"` for it
    /// rather than a fifth enum case, so the absence of a reading is legible as an absence rather
    /// than as `notRequested` — which is also a real OS answer.
    var notificationAuthorisation: NotificationAuthorisation? { notifications.authorisation }
    /// How many `getNotificationSettings` reads have completed in this process (focus-652).
    var notificationAuthorisationReads: Int { notifications.authorisationReadCount }

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

    /// **What a surface is told to draw, built from what this object is holding right now**
    /// (focus-tzj.6).
    ///
    /// A value per read, so nothing in it can take a second reading of anything: the commitment a
    /// nudge was raised with is carried in by the caller that holds it, and the two facts that are
    /// genuinely live — the snooze countdown and whether there is a session to scope a rule to —
    /// are read inside the one presentation that draws them.
    private var presentations: NudgePresentationBuilder {
        NudgePresentationBuilder(
            voice: preferences.voice,
            naming: naming,
            returnAnchor: returnAnchor,
            workspace: workspace,
            snoozes: snoozes,
            monotonicClock: monotonicClock,
            tunings: tunings,
            hasOpenSession: { [weak self] in self?.currentSessionID?() != nil }
        )
    }
}
