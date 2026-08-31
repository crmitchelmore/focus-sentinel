import Foundation

/// **The accusation ladder, as a pure reducer on an injected clock** (R-80, R-81, F-57, D-06).
///
/// A value type with a pure `reduce(_:now:)`, exactly as e04's `DriftMachine` is and for the
/// same reason: **there is no timer object anywhere in this programme** (e03's R-46, e04's
/// R-70e, e05's R-96i), so a replayed sequence fixture is an *exact* assertion rather than an
/// approximate one. Time enters only as a `Duration` read from a `MonotonicClock` — never wall
/// time, because a Mac that slept for an hour has not spent that hour ignoring somebody.
///
/// ## The two halves, and why they are separate calls
///
/// A ladder has to answer two different questions and they are asked at different moments:
///
/// * **"What would you show now?"** — `candidate(at:budgetPermits:)`, a pure query that reads
///   the state and returns a rung or `nil`. It writes nothing, so a caller may ask it as often
///   as it likes.
/// * **"What actually happened?"** — `reduce(.delivery(_:), now:)`, which is the only thing
///   that moves the ladder up.
///
/// Between them sits `offer(at:budgetPermits:)`, which records the rung the app is about to
/// attempt. That record exists because `RungDelivery` deliberately carries a **surface** and
/// not a rung: the type's whole job is to make "delivered" and "deferred" impossible to
/// confuse, and giving it a rung as well would invite a call site to reconstruct the ladder's
/// business from a delivery report.
///
/// ## Escalation needs four facts, and R-81 is the one that is easy to lose
///
/// Rung *n* → rung *n+1* requires **all** of:
///
/// 1. a mandate is still live — **about anything**, see the ruling below;
/// 2. the previous rung was **`delivered`** — not `deferred`, not `suppressed`;
/// 3. `RelevancePolicy.escalationDwell` has elapsed **since that delivery**;
/// 4. the budget permits (R-83), which the caller computes with `FatigueController`.
///
/// The second is R-81, and it is the one a naïve implementation loses first, because "I called
/// `orderFront`" *looks* like delivery. P-131 measured that during a full-screen space the
/// menu-bar layer's owners collapse from eleven to one while our own status item stays
/// **listed** as on screen — so an ambient rung shown over a presentation was seen by nobody.
/// A ladder that escalated through it would arrive at the notification rung with its whole
/// proportionality story already spent, and the person would meet the loudest thing the app can
/// do having never been shown the quietest. `.deferred` therefore writes **no** `deliveredAt`,
/// which is what makes `nudge.escalationsFromDeferred == 0` a property of the arithmetic rather
/// than of a separate check.
///
/// ## **The climb is the person's, not the application's** (focus-f2a, U-1)
///
/// `arrive(_:)` used to reset to `.idle` whenever the live mandate named a different subject, on
/// the argument that *"a different subject is a different drift"*. Measured on the shipping
/// composition root, that argument costs the product its whole purpose. A ship lens drove a
/// commoner rhythm than sustained loyalty to one distraction — drift, return, drift, over
/// forty-five minutes and sixteen drifts into nine applications — and read
/// `hasSpokenToday = false`, `accusationsToday = 0`, the panel never once on screen. Twelve of the
/// sixteen drifts showed the person **nothing at all**. Escalation required two consecutive
/// mandates about the same bundle identifier, and nobody who is genuinely losing an afternoon
/// drifts that tidily.
///
/// The user's standing ruling U-1 is directly on point and they made it against this programme's
/// own Feasibility Court: *"we want to use implicit detection and guesses as default, but then
/// assume it's not aligned if we can't tell… we are really trying to get them to focus."* The
/// Court preferred silence; the user ruled that **silence defeats the product**. Applied one level
/// up, that is: **drift accumulates against the person's attention, not against a bundle
/// identifier, and a subject change is not a fresh start.**
///
/// So a mandate about a new subject **continues** the climb. The ladder keeps its height, its
/// `deliveredAt` and its ignore run, and re-points `liveMandate` — and `candidate(at:budgetPermits:)`
/// builds the rung it offers from **that** live mandate, so the sentence names what the person is
/// doing now rather than the application they left.
///
/// ### With one exception, and it is R-80's own argument: **topping out is about the person too**
///
/// A change of subject continues the climb *while the ladder still has somewhere to climb*. Once
/// it has delivered the loudest rung it has, it has said everything it can say, and a change of
/// subject **ends the run**: `arrive(_:)` returns it to `.idle`, the panel comes down with the rung
/// it was drawing, and the next sustained drift is met with the glyph again.
///
/// Two reasons, and they are one reason at two altitudes:
///
/// * **Proportionality.** R-80 is that the ladder never re-enters at the rung it left, *"because
///   starting again at the rung the ladder left would punish somebody for having complied once"*.
///   Carrying a *topped-out* ladder across a subject change would deliver a second panel — not an
///   escalation, a **repetition**, and U-2's ladder tops out precisely so that there is no such
///   thing. A glyph followed by a panel is the story working; a panel followed by a panel is the
///   app saying the same thing twice and spending a second of the day's six accusations on it.
/// * **The sentence has to be true.** A panel is deliberately sticky (R-89): it waits for an answer
///   rather than vanishing when somebody clicks back into their work. So a panel that is up is a
///   panel that stays up, drawing `rung.subject` and offering corrections that
///   `CorrectionScope.from(rung.mandate)` will write about **that** application. If the ladder
///   carried past the top, the run would end only on an answer, and until then the window would go
///   on naming somewhere the person had left. Ending the run takes it down instead.
///
/// The rule, stated once: **the ladder climbs on the person's run of drift, and a change of subject
/// continues that run until there is nothing left to climb to.**
///
/// ### What it costs, stated
///
/// The ladder now climbs on a run of drift that the person has not answered, so a glyph about one
/// application can be followed by a panel about another that the person was never shown a glyph
/// for. That is deliberate: the glyph is a mark on the status item saying *the app has noticed*,
/// not a sentence about an application, and the thing the panel escalates is the noticing.
///
/// The shape a hopping day now produces is glyph, panel, glyph, panel — one sentence per climb and
/// never two in a row — where before it produced glyph, glyph, glyph and never a sentence at all.
///
/// Nothing else was loosened, and the bargain U-1 rests on — an interruption is licensed by a
/// cheap answer — is kept by six bounds that are all still in force:
///
/// * the engine issues at most one mandate per `RelevancePolicy.mandateCooldown` (600 s), so the
///   ladder can take at most one step per ten minutes however many applications are involved;
/// * fact 3 above, `escalationDwell` (300 s) since the last **delivery**;
/// * `FatigueController` keeps `mandateCooldown` between two sentences, and the caps hold the day
///   to `dailyAccusationCap` and `dailyInterruptionCap`;
/// * the ladder tops out at the panel (U-2): a climb buys **one** sentence, never a second, and
///   the clause above is what stops a change of subject buying another;
/// * `FatigueController`'s session-wide run of ignored accusations trips at
///   `InterventionPolicy.ignoredAccusationBackoff` and holds accusations for
///   `InterventionPolicy.backoffSpan` — an hour — with the glyph exempt by name;
/// * every de-escalation below still puts the ladder on the floor, and they are all facts about
///   the *person*: a correction, a session rule, a snooze, a pause, a new priority, a return to
///   task, a break, a session ending, or the engine deciding this is real work. What no longer
///   puts it down is a fact about the *machine* — which window happens to be frontmost.
///
/// ## De-escalation is immediate, total, and never partial
///
/// Any correction, snooze, pause, priority change, return to task, phase change out of
/// `.focus`, session end or `relevant` verdict resets the ladder to `.idle` **and forgets the
/// mandate**. The next mandate observed re-enters at `.ambient`, always — because starting
/// again at the rung the ladder left would punish somebody for having complied once, and
/// because a person who came back and drifted again deserves the silent glyph first.
public struct LadderMachine: Sendable, Equatable {
    /// Where the ladder has got to. Only a **delivered** rung is represented here.
    public private(set) var state: LadderState

    /// The mandate the ladder is currently climbing for, if any.
    ///
    /// Cleared by every de-escalation, which is what makes re-entry at `.ambient` a property of
    /// the state rather than a rule somebody has to remember.
    public private(set) var liveMandate: InterventionMandate?

    /// The rung the app is about to attempt, recorded by `offer(at:budgetPermits:)` and
    /// resolved by the next `.delivery` event.
    public private(set) var offered: LadderRung?

    /// **Where the ladder was standing before the last delivery** (focus-56y).
    ///
    /// Kept so that a delivery which turns out not to have been one can be taken back exactly —
    /// see `undeliver(at:)`. It is not a history and it is not an undo stack: one step, cleared
    /// by anything that moves the ladder for a different reason, because a delivery that has been
    /// ignored or de-escalated is no longer a delivery there is anything to take back.
    private var stateBeforeDelivery: LadderState?

    public init(state: LadderState = .idle) {
        self.state = state
        self.liveMandate = state.rung?.mandate
        self.offered = nil
    }

    // MARK: - The pure query

    /// **What the ladder would try to show now**, or `nil` when it would show nothing.
    ///
    /// - Parameters:
    ///   - now: a reading of the injected monotonic clock.
    ///   - budgetPermits: whether `FatigueController` allows one more accusation. Read **only**
    ///     for an escalation: the entry rung's own budget is checked by the caller through the
    ///     suppression stack, and conflating the two here would make the ladder the second
    ///     place a cap lives.
    /// - Returns: the rung to attempt, or `nil`.
    public func candidate(at now: Duration, budgetPermits: Bool) -> LadderRung? {
        guard let mandate = liveMandate else { return nil }

        switch state {
        case .idle:
            // Always the bottom of the ladder. `LadderRung.entry(for:)` has no other answer.
            return LadderRung.entry(for: mandate)

        case .engaged(let rung, let deliveredAt, _):
            // Fact 1 is `liveMandate` above, and **it no longer asks which subject** (focus-f2a).
            // The subject test that stood here was the reset in `arrive(_:)` restated as a
            // backstop. That reset now fires only at the top rung, where it leaves `.idle` rather
            // than a state this branch can be reached in, so the backstop has nothing left to catch
            // and is gone with it.
            //
            // Fact 3. `escalationDwell` measured from the DELIVERY, which is the only reading a
            // `.deferred` rung never writes.
            guard now - deliveredAt >= RelevancePolicy.escalationDwell else { return nil }
            // Fact 4.
            guard budgetPermits else { return nil }
            // `nil` at the top: the ladder tops out at the PANEL and there is no third rung
            // above it (U-2). `rung.escalated(for:)` returns `nil` there, which is what makes
            // this the whole of the top-out rather than a case somebody has to remember to add.
            //
            // **Built for the LIVE mandate, never for the one the rung below carried.** That is
            // the half of this ruling a reader of `arrive(_:)` alone would miss: the panel draws
            // `rung.subject` and `resolve(_:snoozeDuration:)` scopes its correction with
            // `CorrectionScope.from(rung.mandate)`, so a rung built from the old mandate would
            // name — and write a rule about — the application the person has already left.
            return rung.escalated(for: mandate)

        case .heldAtAmbient:
            // `InterventionPolicy.ignoredAccusationBackoff` rungs went unanswered — two — so the
            // ladder holds. The number is named rather than restated, because this comment said
            // "three" against a constant of 2 for as long as the constant has been 2. It is not
            // silent — the glyph
            // delivered at the ambient rung is still on screen and still telling the truth
            // (F-146) — but there is nothing new to show, and re-delivering the same glyph
            // every observation would spend the day's budget on a picture that never changed.
            return nil
        }
    }

    // MARK: - The reducer

    /// Record the rung the app is about to attempt, and return it.
    ///
    /// The one mutating step between the query and the delivery. A second `offer` before a
    /// `.delivery` replaces the first, because the app can only be attempting one thing.
    @discardableResult
    public mutating func offer(at now: Duration, budgetPermits: Bool) -> LadderRung? {
        offered = candidate(at: now, budgetPermits: budgetPermits)
        return offered
    }

    /// Fold one event in and return the new state.
    ///
    /// - Parameters:
    ///   - event: what happened.
    ///   - now: a reading of the injected monotonic clock. Every reading the state stores comes
    ///     from here, so two replays of one transcript produce byte-identical states.
    @discardableResult
    public mutating func reduce(_ event: LadderEvent, now: Duration) -> LadderState {
        switch event {
        case .mandate(let mandate):
            arrive(mandate)

        case .delivery(let delivery):
            resolve(delivery, now: now)

        case .rungIgnored:
            ignore(now: now)

        case .deEscalated:
            // Immediate and total. No partial climb-down, no remembered rung, no live mandate:
            // whatever the person did, the ladder starts again from nothing.
            state = .idle
            liveMandate = nil
            offered = nil
            stateBeforeDelivery = nil

        case .tick:
            // Time passing changes no state. The reading it carries is what `candidate(…)`
            // consumes, and a ladder that mutated on a tick would be a ladder with a timer in
            // it by another name.
            break
        }

        return state
    }

    // MARK: - The transitions

    /// A live mandate was observed.
    ///
    /// **The condition on the reset is the ruling** (focus-f2a). This function used to compare the
    /// arriving mandate's subject with the one the standing rung was raised on and drop the ladder
    /// to `.idle` whenever they differed. The whole of the argument for it — *"a different subject
    /// is a different drift"* — is answered at the top of this file: drift accumulates against the
    /// person, and the ladder's height is a fact about how long they have been away from the
    /// commitment, not about their loyalty to one distraction. So the height, the `deliveredAt` the
    /// escalation is measured from, and the ignore run carry across, and the rung the ladder next
    /// offers is built from `liveMandate` in `candidate(at:budgetPermits:)`, which is where the new
    /// subject gets named.
    ///
    /// What survives is the reset **at the top rung**, and its two arguments are written out above:
    /// carrying a topped-out ladder across a subject change would deliver a second panel rather
    /// than an escalation, and would leave a sticky panel naming an application the person had
    /// already left. Asked as `kind.next == nil`, which is `escalated(for:)`'s own question and
    /// needs no mandate to ask it — so a third rung added above the panel moves this clause up with
    /// the ladder instead of leaving it pinned to a case name.
    ///
    /// `.heldAtAmbient` stands at the *ambient* rung, so it is not the top and a change of subject
    /// does not lift it. That is deliberate, and it is the twin of `FatigueController`'s own hold,
    /// which is session-wide and which nothing but time and an answered accusation clears: two
    /// ignored accusations is a fact about the person, and whichever application they moved to next
    /// has no bearing on it.
    private mutating func arrive(_ mandate: InterventionMandate) {
        if let standing = state.rung,
            standing.kind.next == nil,
            !Self.namesTheSameSubject(standing.mandate, mandate) {
            state = .idle
            offered = nil
            stateBeforeDelivery = nil
        }
        liveMandate = mandate
    }

    /// What actually happened when the app tried to speak.
    private mutating func resolve(_ delivery: RungDelivery, now: Duration) {
        // Whatever the answer, the attempt is over.
        let attempted = offered
        offered = nil

        switch delivery {
        case .delivered:
            guard let attempted else { return }
            // Remembered before it is overwritten, so `undeliver(at:)` can put the ladder back
            // where it stood rather than guessing at it. There is nowhere else to recover it
            // from: the state before a rung was delivered is not a function of the rung.
            stateBeforeDelivery = state
            // The ignore count belongs to the run of unanswered rungs, not to the rung, so it
            // is carried across an escalation: three ignored rungs is three, whether they were
            // three glyphs or a glyph, a panel and a notification.
            state = .engaged(
                rung: attempted,
                deliveredAt: now,
                consecutiveIgnored: state.consecutiveIgnored
            )

        case .deferred, .suppressed:
            // **R-81, and this empty branch is the whole of it.** Nothing advances, nothing is
            // spent, and no `deliveredAt` is written — so the escalation clock does not start
            // and the next `candidate(…)` offers the same rung again. During a presentation the
            // app is mute, not quietly escalating, and when the presentation ends the ladder
            // resumes at the rung it never left.
            break
        }
    }

    /// **A rung that was delivered was not delivered after all** (focus-56y, R-81).
    ///
    /// R-81 says a rung nobody could see does not advance the ladder, and the show path enforces
    /// it at the show: a panel whose corrections are out of reach is recorded as a deferral and
    /// the escalation clock never starts. That rule has a second moment, and nothing enforced it
    /// there. A panel is deliberately sticky — it waits for an answer rather than vanishing when
    /// somebody clicks back into their work — so the display it was placed on can be **replaced
    /// underneath it**: undocking, a projector, Sidecar, a resolution change. The rung was seen
    /// for as long as that took and is unanswerable afterwards, and a ladder that escalated
    /// through it would arrive at the loudest rung it has having shown the person nothing.
    ///
    /// So the delivery is taken back, exactly: the ladder returns to the state it was standing in
    /// before it, which is the state whose `candidate(at:budgetPermits:)` offers **this same
    /// rung** again — no `deliveredAt`, so fact 3 is unmet and there is nothing to escalate from,
    /// and no climb-down, so the person is not sent back to the bottom for something the app did.
    ///
    /// Deliberately **not** an undo of anything else. It does nothing at `.idle` (there was no
    /// delivery), nothing at `.heldAtAmbient` (the ladder has already stopped for a different and
    /// stronger reason), and nothing once the rung has been ignored or de-escalated — by then the
    /// delivery has been answered for, and taking it back would be rewriting history rather than
    /// correcting it.
    ///
    /// - Parameter now: a reading of the injected monotonic clock. Unused by the transition and
    ///   required anyway, so that every mutating entry point on this type has the same shape and
    ///   none of them can quietly acquire a clock of its own (R-96i).
    @discardableResult
    public mutating func undeliver(at now: Duration) -> LadderState {
        guard case .engaged = state, let before = stateBeforeDelivery else { return state }
        _ = now
        state = before
        stateBeforeDelivery = nil
        offered = nil
        return state
    }

    /// A delivered rung went unanswered — no correction, no snooze, no pause, no return.
    private mutating func ignore(now: Duration) {
        // The delivery has been answered for. Whatever happens next, it is no longer a delivery
        // there is anything to take back.
        stateBeforeDelivery = nil
        guard case .engaged(let rung, let deliveredAt, let ignored) = state else { return }

        let count = ignored + 1
        guard count >= InterventionPolicy.ignoredAccusationBackoff else {
            // **A rung with nothing above it has nothing to hold position for** (focus-f2a).
            //
            // This clause is the way down that the subject reset was quietly providing, and
            // removing that reset is what made its absence reachable. `candidate(…)` answers
            // `nil` at the top rung, because `escalated(for:)` does — so a panel rung the person
            // dismissed left the ladder standing at `.engaged(.panel, consecutiveIgnored: 1)`
            // with no rung to offer and no ignore left to count, and the only thing that ever
            // moved it on was a mandate about a *different* application. With the climb carried
            // across subjects instead, that ladder would be stranded for the whole session after
            // one dismissal: no panel, and — because `NudgeDecider.accuse(…)` turns a `nil`
            // candidate into `.silent(.budgetExhausted)` — **no glyph either**, which is F-146's
            // legibility lost to arithmetic for a second time.
            //
            // So the ladder comes down to the floor. It is neither a de-escalation (the mandate
            // stays live: the person is still drifting and the status item must still say so) nor
            // a hold (they dismissed one sentence, which is not the app talking to itself). The
            // next sustained drift meets the glyph and may climb again, and the second dismissal
            // is caught by `FatigueController`'s session-wide run — the consumer of
            // `InterventionPolicy.ignoredAccusationBackoff` whose count really does cross a
            // subject change, and whose hold is bounded to `backoffSpan` and exempts the glyph
            // by name.
            //
            // Asked as `rung.kind.next`, which is the same question `escalated(for:)` asks and
            // needs no mandate to ask it: a third rung added above the panel makes this clause
            // stop firing at the panel by itself.
            guard rung.kind.next == nil else {
                state = .engaged(rung: rung, deliveredAt: deliveredAt, consecutiveIgnored: count)
                return
            }
            state = .idle
            offered = nil
            return
        }

        // F-63's "back off when ignored", with the ambient rung **retained**: going fully
        // silent would lose the one channel the person has not objected to, and the glyph is
        // the channel that costs them nothing. The ladder drops to the bottom and holds there
        // for the rest of the session.
        //
        // **"Costs them nothing" is now true of the arithmetic as well** (focus-d6r). It was
        // the surviving half of a contradiction: `InterventionCounters` said the shared budget
        // was "spent by everything delivered", which made the rung this line retains cost a unit
        // of the day — so the channel kept *because* it is free was the channel that silenced
        // the other one. `InterventionEvent.spendsTheInterruptionCap` is where that was settled,
        // in favour of this sentence and of `dailyInterruptionCap`'s own words, which are
        // "questions and accusations together".
        state = .heldAtAmbient(rung: LadderRung.entry(for: rung.mandate), since: now)
    }

    /// Whether two mandates are about the same thing.
    ///
    /// **One caller, and a much narrower job than it used to have** (focus-f2a). It was the whole
    /// of *"a different subject is a different drift"* and it ran on every arrival; it now answers
    /// one question in one place — *has the person moved on from the thing the app has already said
    /// its loudest sentence about?* — and everywhere else a change of subject is a continuation the
    /// ladder does not have to ask about.
    ///
    /// Mixed drift is compared as mixed rather than by name: an accusation about "several unrelated
    /// apps" carries no subject to match on, and treating two mixed mandates as different subjects
    /// would end the run every observation.
    private static func namesTheSameSubject(
        _ lhs: InterventionMandate,
        _ rhs: InterventionMandate
    ) -> Bool {
        if lhs.isMixed || rhs.isMixed { return lhs.isMixed && rhs.isMixed }
        return lhs.subject == rhs.subject
    }
}
