import Foundation
import Testing

@testable import FocusCore

/// **The ladder only climbs through rungs somebody could actually see** (R-80, R-81, F-57).
///
/// P-131 is what this suite exists for. During a real full-screen space the menu-bar layer's
/// owners collapsed from eleven to one while our own status item stayed *listed* as on screen —
/// so a rung "shown" there was shown to nobody. Every assertion below about `.deferred` is that
/// measurement expressed as behaviour: no advance, no clock, no spend.
@Suite("Ladder machine")
struct LadderMachineTests {
    // MARK: - Building the one input the ladder takes

    static let stamp = EngineStamp.current

    static func explanation(_ dwellSeconds: Int) -> Explanation {
        Explanation.make(
            stage: .heuristic,
            band: .high,
            clauses: [.sustainedDwell(seconds: dwellSeconds)],
            stamp: stamp
        )
    }

    /// A mandate, produced the only way one can be produced: through e04's sole producer.
    ///
    /// `InterventionMandate`'s memberwise initialiser is `fileprivate` and `@testable` does not
    /// reach it, which is the guarantee working. So the suite asks the real function for one.
    static func mandate(subject: String, isMixed: Bool = false) -> InterventionMandate {
        let driftSubject: DriftSubject = isMixed ? .mixed : .single(subject)
        let eligibility = InterventionEligibility.decide(
            outcome: ClassificationOutcome(
                verdict: .unrelated, source: .heuristic, confidence: 1, band: .high
            ),
            drift: .sustained(subject: driftSubject, accumulated: .seconds(120), isMixed: isMixed),
            phase: .focus,
            status: .unrelated,
            isUserIdle: false,
            hasActivePriority: true,
            explanation: explanation(120),
            stamp: stamp
        )
        guard let mandate = eligibility.mandate else {
            preconditionFailure(
                "e04's sole producer withheld a mandate on its own mandating cell: "
                    + "unrelated, band .high, sustained drift, .focus, not idle, priority set"
            )
        }
        return mandate
    }

    static let decoy = mandate(subject: "com.chrismitchelmore.FocusDecoy")
    static let other = mandate(subject: "com.apple.Safari")
    static let mixed = mandate(subject: "", isMixed: true)

    /// Drive a machine to a delivered rung at `at`, from idle.
    static func delivering(
        _ machine: inout LadderMachine,
        mandate: InterventionMandate,
        at instant: Duration,
        budgetPermits: Bool = true
    ) -> LadderRung? {
        machine.reduce(.mandate(mandate), now: instant)
        let rung = machine.offer(at: instant, budgetPermits: budgetPermits)
        machine.reduce(.delivery(.delivered(.menuBar)), now: instant)
        return rung
    }

    // MARK: - Entry, and the rung it is always at

    @Test("a fresh mandate enters at the ambient rung and nowhere else")
    func entryIsAlwaysAmbient() {
        var machine = LadderMachine()
        #expect(machine.candidate(at: .seconds(0), budgetPermits: true) == nil)

        machine.reduce(.mandate(Self.decoy), now: .seconds(10))
        let candidate = machine.candidate(at: .seconds(10), budgetPermits: true)

        #expect(candidate?.kind == .ambient)
        #expect(candidate?.kind.rank == LadderRung.Kind.allCases.first?.rank)
        #expect(machine.state == .idle)   // offering is not delivering
    }

    @Test("a mandate alone moves nothing: only a delivery does")
    func aMandateIsNotADelivery() {
        var machine = LadderMachine()
        machine.reduce(.mandate(Self.decoy), now: .seconds(10))
        machine.offer(at: .seconds(10), budgetPermits: true)

        #expect(machine.state == .idle)

        machine.reduce(.delivery(.delivered(.menuBar)), now: .seconds(10))
        #expect(machine.state.rung?.kind == .ambient)
    }

    // MARK: - R-81: an undeliverable rung is not a delivered rung

    @Test("a deferred rung does not advance the ladder, and does not start the escalation clock")
    func deferredNeverAdvances() {
        var machine = LadderMachine()
        machine.reduce(.mandate(Self.decoy), now: .seconds(0))
        machine.offer(at: .seconds(0), budgetPermits: true)
        machine.reduce(.delivery(.deferred(.menuBarHidden)), now: .seconds(0))

        // Nothing moved.
        #expect(machine.state == .idle)

        // And the clock never started: an hour later the ladder still offers the BOTTOM rung,
        // not the one above it. This is the assertion that would fail if `.deferred` wrote a
        // `deliveredAt`, and it is the shape `nudge.escalationsFromDeferred == 0` measures.
        let hourLater = Duration.seconds(3600)
        #expect(machine.candidate(at: hourLater, budgetPermits: true)?.kind == .ambient)
    }

    @Test("a suppressed rung likewise moves nothing")
    func suppressedNeverAdvances() {
        var machine = LadderMachine()
        machine.reduce(.mandate(Self.decoy), now: .seconds(0))
        machine.offer(at: .seconds(0), budgetPermits: true)
        machine.reduce(.delivery(.suppressed(.presentationActive)), now: .seconds(0))

        #expect(machine.state == .idle)
        #expect(machine.candidate(at: .seconds(3600), budgetPermits: true)?.kind == .ambient)
    }

    @Test("the presentation ends and the ladder resumes at the rung it never left")
    func theLadderResumesWhereItWas() {
        var machine = LadderMachine()
        _ = Self.delivering(&machine, mandate: Self.decoy, at: .seconds(0))

        // Rung 2 is due, and is deferred over and over while the presentation runs.
        let due = Duration.seconds(0) + RelevancePolicy.escalationDwell
        for step in 0..<3 {
            let at = due + .seconds(step * 30)
            machine.reduce(.mandate(Self.decoy), now: at)
            #expect(machine.offer(at: at, budgetPermits: true)?.kind == .panel)
            machine.reduce(.delivery(.deferred(.presentationActive)), now: at)
        }

        // Still at rung 1, still owing rung 2 — and there is no rung above that to arrive at.
        #expect(machine.state.rung?.kind == .ambient)
        #expect(machine.candidate(at: due + .seconds(300), budgetPermits: true)?.kind == .panel)
    }

    // MARK: - Escalation: four facts, and the boundary

    @Test("escalation needs a delivered rung plus escalationDwell")
    func escalationNeedsTheDwell() {
        var machine = LadderMachine()
        _ = Self.delivering(&machine, mandate: Self.decoy, at: .seconds(100))

        let due = Duration.seconds(100) + RelevancePolicy.escalationDwell

        #expect(machine.candidate(at: due - .seconds(1), budgetPermits: true) == nil)
        #expect(machine.candidate(at: due, budgetPermits: true)?.kind == .panel)
        #expect(machine.candidate(at: due + .seconds(1), budgetPermits: true)?.kind == .panel)
    }

    @Test("escalation needs the budget, and a refusal holds the ladder where it is")
    func escalationNeedsTheBudget() {
        var machine = LadderMachine()
        _ = Self.delivering(&machine, mandate: Self.decoy, at: .seconds(0))
        let due = RelevancePolicy.escalationDwell

        #expect(machine.candidate(at: due, budgetPermits: false) == nil)
        #expect(machine.candidate(at: due, budgetPermits: true)?.kind == .panel)
        #expect(machine.state.rung?.kind == .ambient)
    }

    /// **The name said three and the body has asserted two since U-2** (focus-yln). It is the
    /// same defect `anAccusationWaitsBehindAnOpenQuestion` carried in the sequence suite: a green
    /// assertion under a caption describing a mechanism the product does not have. The count is
    /// read from `LadderRung.Kind.allCases` and `InterventionPolicy.ladderRungCount` below, so
    /// the name is the only place a number could have been wrong — and was.
    @Test("the ladder climbs both its rungs and stops, because there is no third")
    func theLadderTopsOut() {
        var machine = LadderMachine()
        var at = Duration.seconds(0)

        var climbed: [LadderRung.Kind] = []
        for _ in 0..<LadderRung.Kind.allCases.count {
            machine.reduce(.mandate(Self.decoy), now: at)
            guard let rung = machine.offer(at: at, budgetPermits: true) else { break }
            climbed.append(rung.kind)
            machine.reduce(.delivery(.delivered(.panel)), now: at)
            at = at + RelevancePolicy.escalationDwell
        }

        #expect(climbed == [.ambient, .panel])
        #expect(climbed.count == InterventionPolicy.ladderRungCount)

        // Nothing above the panel. The recommitment rung is deferred to focus-5ab, and D-07
        // forbids compulsion above it in any case, so the ladder tops out here.
        machine.reduce(.mandate(Self.decoy), now: at)
        #expect(machine.candidate(at: at, budgetPermits: true) == nil)
    }

    // MARK: - De-escalation is total, and re-entry is at the bottom

    @Test("every de-escalation resets to idle, forgets the mandate, and re-enters at ambient")
    func everyDeEscalationResets() {
        for cause in LadderDeEscalation.allCases {
            var machine = LadderMachine()
            var at = Duration.seconds(0)

            // Climb to the top so that a partial climb-down would be visible.
            for _ in 0..<LadderRung.Kind.allCases.count {
                machine.reduce(.mandate(Self.decoy), now: at)
                guard machine.offer(at: at, budgetPermits: true) != nil else { break }
                machine.reduce(.delivery(.delivered(.panel)), now: at)
                at = at + RelevancePolicy.escalationDwell
            }
            #expect(machine.state.rung?.kind == .panel, "\(cause)")

            machine.reduce(.deEscalated(cause), now: at)

            #expect(machine.state == .idle, "\(cause) left the ladder engaged")
            #expect(machine.liveMandate == nil, "\(cause) kept the mandate alive")
            #expect(
                machine.candidate(at: at, budgetPermits: true) == nil,
                "\(cause) left a rung on offer with no mandate"
            )

            // Drifting again starts at the silent glyph — never at the rung the ladder left.
            machine.reduce(.mandate(Self.decoy), now: at + .seconds(1))
            #expect(
                machine.candidate(at: at + .seconds(1), budgetPermits: true)?.kind == .ambient,
                "\(cause) re-entered above the ambient rung"
            )
        }
    }

    @Test("a correction does not leave the escalation clock running behind it")
    func aCorrectionClearsTheClock() {
        var machine = LadderMachine()
        _ = Self.delivering(&machine, mandate: Self.decoy, at: .seconds(0))
        machine.reduce(.deEscalated(.corrected), now: .seconds(10))

        // An hour later, a fresh mandate. If the reset had kept `deliveredAt`, this would
        // arrive already owing rung 2.
        machine.reduce(.mandate(Self.decoy), now: .seconds(3600))
        #expect(machine.candidate(at: .seconds(3600), budgetPermits: true)?.kind == .ambient)
    }

    // MARK: - The ignored backoff

    @Test("three ignored rungs drop the ladder to ambient and hold it there")
    func ignoredRungsHoldTheLadder() {
        var machine = LadderMachine()
        var at = Duration.seconds(0)
        _ = Self.delivering(&machine, mandate: Self.decoy, at: at)

        for step in 1..<InterventionPolicy.ignoredAccusationBackoff {
            machine.reduce(.rungIgnored, now: at)
            #expect(machine.state.consecutiveIgnored == step)
            if case .heldAtAmbient = machine.state {
                Issue.record("the ladder held after \(step) ignored rungs, not after the third")
            }
            at = at + RelevancePolicy.escalationDwell
        }

        machine.reduce(.rungIgnored, now: at)

        guard case .heldAtAmbient(let rung, let since) = machine.state else {
            Issue.record("the ladder did not hold after \(InterventionPolicy.ignoredAccusationBackoff)")
            return
        }
        #expect(rung.kind == .ambient)
        #expect(since == at)

        // Held is not silent, and **it is the ladder that has to say so** (focus-50m, focus-628).
        // There is nothing to CLIMB to — that is what the hold is — but the rung that says
        // nothing is still owed, and the silence names itself so the decider can ask.
        let held = machine.step(at: at + .seconds(60), budgetPermits: true)
        #expect(held.rung == nil)
        #expect(held.silence == .heldAtAmbient)
        #expect(held.silence?.retainsTheAmbientRung == true, "the hold stopped owing the mark")
        #expect(machine.retainedRung?.kind == .ambient)

        // **And it has an expiry** (focus-50m, focus-845). It used to hold for the rest of the
        // session, which is a sentence no other backoff in this app is allowed to say: the twin
        // hold in `FatigueController` was bounded to `InterventionPolicy.backoffSpan` a round ago
        // on the argument that a backoff this app imposes lasts an hour.
        #expect(
            machine.candidate(
                at: at + InterventionPolicy.backoffSpan - .seconds(1), budgetPermits: true
            ) == nil,
            "the hold lifted before backoffSpan had elapsed"
        )
        #expect(
            machine.candidate(at: at + InterventionPolicy.backoffSpan, budgetPermits: true)?.kind
                == .ambient,
            "the hold outlived InterventionPolicy.backoffSpan"
        )
        #expect(
            machine.candidate(at: at + .seconds(86_400), budgetPermits: true)?.kind == .ambient,
            "a day later the ladder was still held"
        )
    }

    @Test("the hold survives more drift and lifts on a de-escalation or on its own expiry")
    func theHoldLiftsOnlyOnDeEscalation() {
        var machine = LadderMachine()
        _ = Self.delivering(&machine, mandate: Self.decoy, at: .seconds(0))
        for _ in 0..<InterventionPolicy.ignoredAccusationBackoff {
            machine.reduce(.rungIgnored, now: .seconds(0))
        }
        #expect(machine.candidate(at: .seconds(1000), budgetPermits: true) == nil)

        machine.reduce(.mandate(Self.decoy), now: .seconds(1000))
        #expect(machine.candidate(at: .seconds(1000), budgetPermits: true) == nil)

        machine.reduce(.deEscalated(.returnedToTask), now: .seconds(1010))
        machine.reduce(.mandate(Self.decoy), now: .seconds(1020))
        #expect(machine.candidate(at: .seconds(1020), budgetPermits: true)?.kind == .ambient)

        // The other way out, on a ladder nobody de-escalated: time (focus-50m). Driven through
        // the reducer rather than the query, because the state a reader inspects has to be the
        // state the ladder is really in.
        var patient = LadderMachine()
        _ = Self.delivering(&patient, mandate: Self.decoy, at: .seconds(0))
        for _ in 0..<InterventionPolicy.ignoredAccusationBackoff {
            patient.reduce(.rungIgnored, now: .seconds(0))
        }
        patient.reduce(.tick(InterventionPolicy.backoffSpan), now: InterventionPolicy.backoffSpan)
        #expect(patient.state == .idle, "a tick past backoffSpan left the hold standing")
    }

    @Test("an ignore before anything was delivered changes nothing")
    func anIgnoreWithNothingDeliveredIsANoOp() {
        var machine = LadderMachine()
        machine.reduce(.mandate(Self.decoy), now: .seconds(0))
        machine.reduce(.rungIgnored, now: .seconds(0))

        #expect(machine.state == .idle)
        #expect(machine.state.consecutiveIgnored == 0)
    }

    @Test("the ignore count is carried across an escalation, not reset by it")
    func theIgnoreCountSurvivesAnEscalation() {
        var machine = LadderMachine()
        _ = Self.delivering(&machine, mandate: Self.decoy, at: .seconds(0))
        machine.reduce(.rungIgnored, now: .seconds(0))
        #expect(machine.state.consecutiveIgnored == 1)

        let due = RelevancePolicy.escalationDwell
        machine.reduce(.mandate(Self.decoy), now: due)
        machine.offer(at: due, budgetPermits: true)
        machine.reduce(.delivery(.delivered(.panel)), now: due)

        #expect(machine.state.rung?.kind == .panel)
        #expect(machine.state.consecutiveIgnored == 1)
    }

    // MARK: - Subjects, and the ruling that they do not restart the climb (focus-f2a)

    /// **A glyph about one application, then a panel about another** (focus-f2a, U-1).
    ///
    /// This test asserted the opposite until this round, and the thing it asserted was the defect:
    /// a ship lens drove sixteen drifts into nine applications through the shipping composition
    /// root and read `accusationsToday == 0` and a panel that never appeared, because escalation
    /// needed two consecutive mandates about the same bundle identifier. Drift accumulates against
    /// the person, not against an identifier.
    ///
    /// Both halves are asserted, because the second is the one a reader of `arrive(_:)` alone
    /// would miss: the climb continues, **and** the rung it continues to is built for the mandate
    /// that is live now — not for the application the person has already left.
    @Test("a mandate about a different subject continues the climb, and names the new subject")
    func aDifferentSubjectContinuesTheClimb() {
        var machine = LadderMachine()
        let at = Duration.seconds(0)
        _ = Self.delivering(&machine, mandate: Self.decoy, at: at)
        #expect(machine.state.rung?.kind == .ambient)

        let due = at + RelevancePolicy.escalationDwell
        machine.reduce(.mandate(Self.other), now: due)

        // The height is kept: the glyph really was delivered and the person really is still away.
        #expect(machine.state.rung?.kind == .ambient, "a change of subject unwound the climb")
        let next = machine.candidate(at: due, budgetPermits: true)
        #expect(next?.kind == .panel, "the ladder re-entered at the bottom for a second subject")
        // And the sentence is about what they are doing now. `AccusationPanelView` draws this and
        // `CorrectionScope.from(rung.mandate)` writes a rule from it.
        #expect(next?.mandate.subject == "com.apple.Safari")
        #expect(next?.subject == "com.apple.Safari")

        // The dwell still binds across the change: a subject change buys no shortcut.
        var impatient = LadderMachine()
        _ = Self.delivering(&impatient, mandate: Self.decoy, at: at)
        impatient.reduce(.mandate(Self.other), now: due - .seconds(1))
        #expect(
            impatient.candidate(at: due - .seconds(1), budgetPermits: true) == nil,
            "a change of subject escalated inside the escalation dwell"
        )
    }

    /// Mixed drift never had a subject to match on, so it was the one shape the old rule already
    /// let climb. It still climbs, and now for the same reason as every other shape.
    @Test("mixed drift climbs, and so does mixed drift that becomes named drift")
    func mixedDriftClimbsLikeAnyOther() {
        var machine = LadderMachine()
        _ = Self.delivering(&machine, mandate: Self.mixed, at: .seconds(0))

        let due = RelevancePolicy.escalationDwell
        machine.reduce(.mandate(Self.mixed), now: due)

        #expect(machine.state.rung?.kind == .ambient)
        #expect(machine.candidate(at: due, budgetPermits: true)?.kind == .panel)
        // Still nameless: a mandate about "several unrelated apps" must not be drawn as one of
        // them, and the rung carries the live mandate, which is the mixed one.
        #expect(machine.candidate(at: due, budgetPermits: true)?.subject == nil)
    }

    /// **The one reset that survives, and the two things it is for** (focus-f2a).
    ///
    /// A change of subject continues the climb *while there is somewhere to climb to*. At the top
    /// there is not, so the run ends: a second panel would be a repetition rather than an
    /// escalation, and — because a panel is sticky (R-89) — carrying on would leave a window naming
    /// an application the person had already left, offering corrections scoped to it.
    ///
    /// Both halves are asserted. The reset happens **and** the ladder is standing somewhere the
    /// next drift can be met from, which is the difference between ending a run and going silent.
    @Test("a change of subject at the top rung ends the run and starts again at the glyph")
    func aChangeOfSubjectAtTheTopEndsTheRun() {
        var machine = LadderMachine()
        var at = Duration.seconds(0)
        _ = Self.delivering(&machine, mandate: Self.decoy, at: at)
        at = at + RelevancePolicy.escalationDwell
        machine.reduce(.mandate(Self.decoy), now: at)
        machine.offer(at: at, budgetPermits: true)
        machine.reduce(.delivery(.delivered(.panel)), now: at)
        try! #require(machine.state.rung?.kind == .panel)

        machine.reduce(.mandate(Self.other), now: at)

        #expect(machine.state == .idle, "the topped-out ladder carried a second panel across")
        #expect(machine.offered == nil, "an offer survived the end of the run")
        let next = machine.candidate(at: at, budgetPermits: true)
        #expect(next?.kind == .ambient, "the new subject was met above the glyph")
        #expect(next?.mandate.subject == "com.apple.Safari")

        // And the same subject at the top is not a change: the panel that is up stays up, and the
        // ladder has nothing to add to it.
        var staying = LadderMachine()
        var stayingAt = Duration.seconds(0)
        _ = Self.delivering(&staying, mandate: Self.decoy, at: stayingAt)
        stayingAt = stayingAt + RelevancePolicy.escalationDwell
        staying.reduce(.mandate(Self.decoy), now: stayingAt)
        staying.offer(at: stayingAt, budgetPermits: true)
        staying.reduce(.delivery(.delivered(.panel)), now: stayingAt)
        staying.reduce(.mandate(Self.decoy), now: stayingAt + .seconds(86_400))
        #expect(staying.state.rung?.kind == .panel)
        #expect(staying.candidate(at: stayingAt + .seconds(86_400), budgetPermits: true) == nil)
    }

    /// The two directions across the mixed boundary, which is where a "same subject" comparison
    /// used to answer `false` in both. Folded rather than written twice, so neither direction can
    /// be repaired without the other.
    @Test("a named rung followed by mixed drift, and mixed followed by named, both climb")
    func theMixedBoundaryIsNotAReset() {
        let crossings: [(standing: InterventionMandate, arriving: InterventionMandate, named: String?)] = [
            (Self.decoy, Self.mixed, nil),
            (Self.mixed, Self.decoy, "com.chrismitchelmore.FocusDecoy")
        ]
        for crossing in crossings {
            var machine = LadderMachine()
            _ = Self.delivering(&machine, mandate: crossing.standing, at: .seconds(0))
            let due = RelevancePolicy.escalationDwell
            machine.reduce(.mandate(crossing.arriving), now: due)

            #expect(
                machine.state.rung?.kind == .ambient,
                "crossing the mixed boundary unwound the climb"
            )
            let next = machine.candidate(at: due, budgetPermits: true)
            #expect(next?.kind == .panel, "crossing the mixed boundary re-entered at the bottom")
            #expect(next?.subject == crossing.named, "the rung named the mandate it left behind")
        }
    }

    // MARK: - Time, and replayability

    @Test("a tick changes no state, because there is no timer for it to stand in for")
    func aTickIsInert() {
        var machine = LadderMachine()
        _ = Self.delivering(&machine, mandate: Self.decoy, at: .seconds(0))
        let before = machine

        for step in 1...10 {
            machine.reduce(.tick(.seconds(step * 60)), now: .seconds(step * 60))
        }

        #expect(machine == before)
    }

    @Test("two machines fed the same transcript in two runs end identical")
    func replayIsExact() {
        let transcript: [(LadderEvent, Duration)] = [
            (.mandate(Self.decoy), .seconds(0)),
            (.delivery(.delivered(.menuBar)), .seconds(0)),
            (.tick(.seconds(120)), .seconds(120)),
            (.rungIgnored, .seconds(200)),
            (.mandate(Self.decoy), RelevancePolicy.escalationDwell),
            (.delivery(.deferred(.presentationActive)), RelevancePolicy.escalationDwell),
            (.mandate(Self.decoy), .seconds(1000)),
            (.delivery(.delivered(.panel)), .seconds(1000)),
            (.deEscalated(.snoozed), .seconds(1100))
        ]

        func run() -> LadderMachine {
            var machine = LadderMachine()
            for (event, at) in transcript {
                if case .delivery = event { machine.offer(at: at, budgetPermits: true) }
                machine.reduce(event, now: at)
            }
            return machine
        }

        #expect(run() == run())
        #expect(run().state == .idle)
    }

    @Test("a delivery with nothing offered is ignored rather than inventing a rung")
    func aDeliveryWithNothingOfferedIsInert() {
        var machine = LadderMachine()
        machine.reduce(.mandate(Self.decoy), now: .seconds(0))
        machine.reduce(.delivery(.delivered(.panel)), now: .seconds(0))

        #expect(machine.state == .idle)
    }

    // MARK: - A delivery that turned out not to be one (focus-56y)

    /// **R-81 has a second moment, and the ladder can be told about it.**
    ///
    /// A panel is deliberately sticky, so the display it was placed on can be replaced underneath
    /// it — undocking, a projector, Sidecar. The rung was on screen for as long as that took and
    /// is unanswerable afterwards, and a ladder that escalated through it would arrive at the
    /// loudest rung it has having shown the person nothing. So the delivery is taken back
    /// **exactly**: not a climb-down to the bottom, which would punish somebody for something the
    /// app did, and not a no-op, which is the defect.
    @Test("un-delivering a rung offers that same rung again rather than the one above it")
    func undeliveringOffersTheSameRungAgain() {
        var machine = LadderMachine()
        // Two real deliveries, so the ladder is standing at the panel rung with a history behind
        // it — the case where "back to idle" and "back to where it was" are different answers.
        let ambient = Self.delivering(&machine, mandate: Self.decoy, at: .seconds(0))
        #expect(ambient?.kind == .ambient)

        let at = RelevancePolicy.escalationDwell
        machine.reduce(.mandate(Self.decoy), now: at)
        let panel = machine.offer(at: at, budgetPermits: true)
        #expect(panel?.kind == .panel)
        machine.reduce(.delivery(.delivered(.panel)), now: at)
        #expect(machine.state.rung?.kind == .panel)

        // The display changes and the panel rung is stranded.
        machine.undeliver(at: at + .seconds(30))

        // Not idle: the ambient rung really was delivered and is not being re-shown.
        #expect(machine.state.rung?.kind == .ambient)
        #expect(
            machine.candidate(at: at + .seconds(30), budgetPermits: true)?.kind == .panel,
            "the ladder does not offer the stranded rung again"
        )
        // And no escalation clock is running from a delivery that did not happen: the next rung
        // up is never offered on the strength of it.
        #expect(machine.offered == nil)
    }

    /// **It is a correction, not an undo stack.** One step, and only while there is a delivery
    /// standing that nothing else has already answered for.
    @Test("un-delivering does nothing at idle, at a held ladder, or twice")
    func undeliveringIsOneStepAndOnlyWhereThereIsADelivery() {
        var idle = LadderMachine()
        idle.reduce(.mandate(Self.decoy), now: .seconds(0))
        #expect(idle.undeliver(at: .seconds(0)) == .idle)

        // Twice is once: the second call has nothing left to take back.
        var machine = LadderMachine()
        _ = Self.delivering(&machine, mandate: Self.decoy, at: .seconds(0))
        let at = RelevancePolicy.escalationDwell
        machine.reduce(.mandate(Self.decoy), now: at)
        machine.offer(at: at, budgetPermits: true)
        machine.reduce(.delivery(.delivered(.panel)), now: at)
        machine.undeliver(at: at)
        #expect(machine.state.rung?.kind == .ambient)
        machine.undeliver(at: at)
        #expect(machine.state.rung?.kind == .ambient, "a second un-delivery unwound a delivery it had no claim on")

        // A rung the person has already ignored has been answered for. Taking the delivery back
        // afterwards would be rewriting history rather than correcting it.
        var ignored = LadderMachine()
        _ = Self.delivering(&ignored, mandate: Self.decoy, at: .seconds(0))
        ignored.reduce(.rungIgnored, now: .seconds(10))
        let after = ignored.state
        ignored.undeliver(at: .seconds(20))
        #expect(ignored.state == after)
    }
}
