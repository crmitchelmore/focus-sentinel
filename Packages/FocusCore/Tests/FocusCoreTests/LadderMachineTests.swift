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

        // Still at rung 1, still owing rung 2 — not at rung 3.
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

    @Test("the ladder climbs three rungs and stops, because there is no fourth")
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

        #expect(climbed == [.ambient, .panel, .recommitment])
        #expect(climbed.count == InterventionPolicy.ladderRungCount)

        // Nothing above recommitment. D-07 forbids compulsion, so the ladder tops out at an
        // explicit choice and there is no rung that could be a coercion.
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
            #expect(machine.state.rung?.kind == .recommitment, "\(cause)")

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

        // Held is not silent — the glyph is still on screen and still true (F-146) — but there
        // is nothing new to show, however long the person keeps drifting.
        #expect(machine.candidate(at: at + .seconds(86_400), budgetPermits: true) == nil)
    }

    @Test("the hold survives more drift and lifts only on a de-escalation")
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

    // MARK: - Subjects

    @Test("a mandate about a different subject re-enters at the ambient rung")
    func aDifferentSubjectRestartsTheClimb() {
        var machine = LadderMachine()
        var at = Duration.seconds(0)
        _ = Self.delivering(&machine, mandate: Self.decoy, at: at)
        at = at + RelevancePolicy.escalationDwell
        machine.reduce(.mandate(Self.decoy), now: at)
        machine.offer(at: at, budgetPermits: true)
        machine.reduce(.delivery(.delivered(.panel)), now: at)
        #expect(machine.state.rung?.kind == .panel)

        machine.reduce(.mandate(Self.other), now: at)

        #expect(machine.state == .idle)
        #expect(machine.candidate(at: at, budgetPermits: true)?.kind == .ambient)
        #expect(machine.candidate(at: at, budgetPermits: true)?.mandate.subject == "com.apple.Safari")
    }

    @Test("two mixed mandates are the same subject, so the ladder does not restart every observation")
    func mixedDriftIsOneSubject() {
        var machine = LadderMachine()
        _ = Self.delivering(&machine, mandate: Self.mixed, at: .seconds(0))

        let due = RelevancePolicy.escalationDwell
        machine.reduce(.mandate(Self.mixed), now: due)

        #expect(machine.state.rung?.kind == .ambient)
        #expect(machine.candidate(at: due, budgetPermits: true)?.kind == .panel)
        #expect(machine.candidate(at: due, budgetPermits: true)?.subject == nil)
    }

    @Test("a mixed mandate and a named one are different subjects")
    func mixedAndNamedAreDifferent() {
        var machine = LadderMachine()
        _ = Self.delivering(&machine, mandate: Self.decoy, at: .seconds(0))
        machine.reduce(.mandate(Self.mixed), now: RelevancePolicy.escalationDwell)

        #expect(machine.state == .idle)
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
}
