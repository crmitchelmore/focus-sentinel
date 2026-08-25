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
/// 1. the mandate is still live, and for the **same subject**;
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
            // Fact 1. A different subject is not this ladder's business; `reduce(.mandate(_:))`
            // has already reset to `.idle` for one, so this is a backstop rather than a path.
            guard Self.sameSubject(rung.mandate, mandate) else { return nil }
            // Fact 3. `escalationDwell` measured from the DELIVERY, which is the only reading a
            // `.deferred` rung never writes.
            guard now - deliveredAt >= RelevancePolicy.escalationDwell else { return nil }
            // Fact 4.
            guard budgetPermits else { return nil }
            // `nil` at the top: the ladder tops out at explicit recommitment and there is no
            // fourth stage above it (D-07, R-99).
            return rung.escalated()

        case .heldAtAmbient:
            // Three rungs went unanswered, so the ladder holds. It is not silent — the glyph
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
    private mutating func arrive(_ mandate: InterventionMandate) {
        if let rung = state.rung, !Self.sameSubject(rung.mandate, mandate) {
            // A different subject is a different drift. The ladder does not carry its height
            // across: re-entry is at `.ambient`, for the new subject, exactly as it is after a
            // de-escalation.
            state = .idle
            offered = nil
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

    /// A delivered rung went unanswered — no correction, no snooze, no pause, no return.
    private mutating func ignore(now: Duration) {
        guard case .engaged(let rung, let deliveredAt, let ignored) = state else { return }

        let count = ignored + 1
        guard count >= InterventionPolicy.ignoredAccusationBackoff else {
            state = .engaged(rung: rung, deliveredAt: deliveredAt, consecutiveIgnored: count)
            return
        }

        // F-63's "back off when ignored", with the ambient rung **retained**: going fully
        // silent would lose the one channel the person has not objected to, and the glyph is
        // the channel that costs them nothing. The ladder drops to the bottom and holds there
        // for the rest of the session.
        state = .heldAtAmbient(rung: LadderRung.entry(for: rung.mandate), since: now)
    }

    /// Whether two mandates are about the same thing.
    ///
    /// Mixed drift is compared as mixed rather than by name: an accusation about "several
    /// unrelated apps" carries no subject to match on, and treating two mixed mandates as
    /// different subjects would reset the ladder every observation and leave it permanently at
    /// the ambient rung.
    private static func sameSubject(
        _ lhs: InterventionMandate,
        _ rhs: InterventionMandate
    ) -> Bool {
        if lhs.isMixed || rhs.isMixed { return lhs.isMixed && rhs.isMixed }
        return lhs.subject == rhs.subject
    }
}
