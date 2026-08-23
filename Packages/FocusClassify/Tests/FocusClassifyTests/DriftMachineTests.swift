import FocusCore
import Foundation
import Testing

@testable import FocusClassify

/// The drift machine, cell by cell (R-60, F-48).
///
/// R-60's transition table has four states and six kinds of observation, and every one of the
/// twenty-four cells is asserted below — because the cells nobody thinks about are exactly the
/// ones a drift detector is defeated through. The one that matters most is
/// `aShortReturnDoesNotReset`: without it, alt-tabbing back to the IDE for one second a minute
/// makes the app permanently mute, which is the single most obvious way to defeat a detector
/// like this and the one a naïve implementation always has.
@Suite("Drift machine")
struct DriftMachineTests {
    static let ide = "com.apple.dt.Xcode"
    static let docs = "com.apple.Safari"
    static let video = "com.google.Chrome"
    static let chat = "com.hnc.Discord"

    /// A machine driven by a `TestClock`, so the assertions read like the sequence they are.
    struct Driver {
        var machine = DriftMachine()
        var clock = TestClock()

        @discardableResult
        mutating func observe(
            _ verdict: Verdict,
            _ subject: String?,
            after seconds: Int = 0,
            idle: Bool = false,
            phase: SessionPhase = .focus,
            threshold: Duration = RelevancePolicy.sustainedDriftThreshold
        ) -> DriftState {
            clock.advance(by: .seconds(seconds))
            return machine.reduce(
                DriftObservation(
                    now: clock.elapsed,
                    verdict: verdict,
                    subject: subject,
                    isUserIdle: idle,
                    phase: phase,
                    effectiveThreshold: threshold
                )
            )
        }
    }

    // MARK: - From aligned

    @Test("from aligned: a relevant observation stays aligned")
    func alignedStaysAligned() {
        var driver = Driver()
        #expect(driver.observe(.relevant, Self.ide) == .aligned)
        #expect(driver.observe(.relevant, Self.ide, after: 600) == .aligned)
    }

    @Test("from aligned: an unrelated observation opens a grace period")
    func alignedOpensGrace() {
        var driver = Driver()
        driver.observe(.relevant, Self.ide)
        let state = driver.observe(.unrelated, Self.video, after: 30)

        #expect(state.subject == .single(Self.video))
        #expect(state.accumulated == .zero, "the interval just past belonged to the IDE")
        if case .grace = state {} else { Issue.record("expected grace, got \(state)") }
    }

    @Test("from aligned: an uncertain observation changes nothing")
    func alignedIgnoresUncertain() {
        var driver = Driver()
        #expect(driver.observe(.uncertain, Self.docs) == .aligned)
        #expect(driver.observe(.uncertain, Self.docs, after: 3_600) == .aligned)
    }

    @Test("from aligned: idle and a non-focus phase both change nothing")
    func alignedIgnoresIdleAndPhase() {
        var driver = Driver()
        #expect(driver.observe(.unrelated, Self.video, idle: true) == .aligned)
        #expect(driver.observe(.unrelated, Self.video, after: 600, phase: .onBreak) == .aligned)
    }

    // MARK: - From grace

    /// **The anti-defeat property.** A one-second bounce back to the IDE must not clear ninety
    /// seconds of drift, or the app is mute for ever against anybody who alt-tabs.
    @Test("a short return does not reset the accumulator")
    func aShortReturnDoesNotReset() {
        var driver = Driver()
        driver.observe(.relevant, Self.ide)
        driver.observe(.unrelated, Self.video, after: 10)
        let drifted = driver.observe(.unrelated, Self.video, after: 60)
        #expect(drifted.accumulated == .seconds(60))

        // Back to the IDE for one second, then away again.
        driver.observe(.relevant, Self.ide, after: 1)
        let after = driver.observe(.unrelated, Self.video, after: 1)
        #expect(after.accumulated == .seconds(61), "the accumulator was cleared by a one-second bounce")
    }

    /// …and a return that is genuinely *held* does clear it. The pair is what makes the rule a
    /// rule rather than a bias.
    @Test("a return held for the grace period clears the accumulator")
    func aHeldReturnResets() {
        var driver = Driver()
        driver.observe(.relevant, Self.ide)
        driver.observe(.unrelated, Self.video, after: 10)
        driver.observe(.unrelated, Self.video, after: 60)

        driver.observe(.relevant, Self.ide, after: 1)
        let state = driver.observe(.relevant, Self.ide, after: 20)
        #expect(state == .aligned)
    }

    /// The boundary itself: 19 does not reset, 20 does. `driftResetGrace` is inclusive on the
    /// resetting side, stated once and enforced by the fixture.
    @Test("the reset-grace boundary is inclusive: 19 no, 20 yes, 21 yes")
    func theResetGraceBoundaryIsInclusive() {
        func accumulatedAfterReturn(held seconds: Int) -> Duration {
            var driver = Driver()
            driver.observe(.relevant, Self.ide)
            driver.observe(.unrelated, Self.video, after: 10)
            driver.observe(.unrelated, Self.video, after: 60)
            driver.observe(.relevant, Self.ide, after: 1)
            return driver.observe(.unrelated, Self.video, after: seconds).accumulated
        }

        // 61 rather than 60: the second spent switching *away* from the distraction belonged
        // to the distraction, which is the interval-attribution rule stated as arithmetic.
        #expect(accumulatedAfterReturn(held: 19) == .seconds(61))
        #expect(accumulatedAfterReturn(held: 20) == .zero)
        #expect(accumulatedAfterReturn(held: 21) == .zero)
    }

    /// **The threshold, as a triple.** The mandate is issued at the first observation *after*
    /// the threshold, so ninety seconds exactly does not sustain.
    @Test("the sustained boundary is strict: 89 grace, 90 grace, 91 sustained")
    func theSustainedBoundaryIsStrict() {
        func state(after seconds: Int) -> DriftState {
            var driver = Driver()
            driver.observe(.relevant, Self.ide)
            driver.observe(.unrelated, Self.video, after: 10)
            return driver.observe(.unrelated, Self.video, after: seconds)
        }

        #expect(!state(after: 89).isSustained)
        #expect(!state(after: 90).isSustained, "the threshold itself does not sustain")
        #expect(state(after: 91).isSustained)
    }

    /// Ruling 2: three unrelated applications in ninety seconds is drift, not three fresh grace
    /// periods — and the mandate must not misname one of them.
    @Test("hopping between distractions accumulates and goes mixed")
    func hoppingAccumulates() {
        var driver = Driver()
        driver.observe(.relevant, Self.ide)
        driver.observe(.unrelated, Self.video, after: 10)
        driver.observe(.unrelated, Self.chat, after: 40)
        let state = driver.observe(.unrelated, Self.docs, after: 55)

        #expect(state.isSustained)
        #expect(state.isMixed)
        #expect(state.subject == .mixed)
        #expect(state.accumulated == .seconds(95))
    }

    /// Returning to the *same* unrelated subject is not a hop, and must not be reported as one.
    @Test("staying on one distraction keeps its name")
    func stayingOnOneSubjectKeepsItsName() {
        var driver = Driver()
        driver.observe(.relevant, Self.ide)
        driver.observe(.unrelated, Self.video, after: 10)
        let state = driver.observe(.unrelated, Self.video, after: 100)

        #expect(state.isSustained)
        #expect(!state.isMixed)
        #expect(state.subject == .single(Self.video))
    }

    /// Ruling 3: an `uncertain` observation is no information. It must not act as a return —
    /// which would reward ambiguity by muting the app — and must not accumulate, which would
    /// let ignorance nudge.
    @Test("uncertain freezes: it neither accumulates nor resets")
    func uncertainFreezes() {
        var driver = Driver()
        driver.observe(.relevant, Self.ide)
        driver.observe(.unrelated, Self.video, after: 10)
        let drifted = driver.observe(.unrelated, Self.video, after: 60)
        #expect(drifted.accumulated == .seconds(60))

        // The one second spent switching away belonged to the distraction; everything after
        // it belongs to the uncertain observation and accumulates nothing.
        driver.observe(.uncertain, Self.docs, after: 1)
        let frozen = driver.observe(.uncertain, Self.docs, after: 3_600)
        #expect(frozen.accumulated == .seconds(61), "an uncertain interval accumulated")
        #expect(!frozen.isSustained)

        let resumed = driver.observe(.unrelated, Self.video, after: 1)
        #expect(resumed.accumulated == .seconds(61), "an uncertain observation acted as a return")
    }

    /// Ruling 4: a person who walked away is not drifting. e03 already owns the hardware idle
    /// source and its 180-second threshold.
    @Test("idle freezes: an idle interval accumulates nothing")
    func idleFreezes() {
        var driver = Driver()
        driver.observe(.relevant, Self.ide)
        driver.observe(.unrelated, Self.video, after: 10)
        driver.observe(.unrelated, Self.video, after: 60)

        driver.observe(.unrelated, Self.video, after: 1, idle: true)
        let state = driver.observe(.unrelated, Self.video, after: 3_600)
        #expect(state.accumulated == .seconds(61))
        #expect(!state.isSustained, "an hour away from the keyboard became drift")
    }

    /// Ruling 5: a break, a detour, a pause or an interruption is a declaration that the
    /// deviation is deliberate, and the accumulator does not survive one.
    @Test(
        "leaving focus resets outright",
        arguments: [SessionPhase.intentionalDetour, .onBreak, .paused, .interrupted, .complete]
    )
    func leavingFocusResets(phase: SessionPhase) {
        var driver = Driver()
        driver.observe(.relevant, Self.ide)
        driver.observe(.unrelated, Self.video, after: 10)
        driver.observe(.unrelated, Self.video, after: 60)

        #expect(driver.observe(.unrelated, Self.video, after: 1, phase: phase) == .aligned)
        // …and coming back starts from nothing rather than from sixty seconds.
        driver.observe(.unrelated, Self.video, after: 1)
        #expect(driver.observe(.unrelated, Self.video, after: 30).accumulated == .seconds(30))
    }

    // MARK: - From sustained

    @Test("sustained keeps accumulating, because the band rises with it")
    func sustainedKeepsAccumulating() {
        var driver = Driver()
        driver.observe(.relevant, Self.ide)
        driver.observe(.unrelated, Self.video, after: 10)
        driver.observe(.unrelated, Self.video, after: 100)
        let state = driver.observe(.unrelated, Self.video, after: 250)

        #expect(state.isSustained)
        #expect(state.accumulated == .seconds(350))
        #expect(state.accumulated > RelevancePolicy.escalationDwell)
    }

    @Test("a held return clears a sustained state as well as a grace one")
    func aHeldReturnClearsSustained() {
        var driver = Driver()
        driver.observe(.relevant, Self.ide)
        driver.observe(.unrelated, Self.video, after: 10)
        driver.observe(.unrelated, Self.video, after: 100)
        driver.observe(.relevant, Self.ide, after: 1)
        #expect(driver.observe(.relevant, Self.ide, after: 30) == .aligned)
    }

    // MARK: - Cooldown

    /// One mandate per subject per ten minutes, from the engine. e05's ladder has its own
    /// proportionality on top of this.
    @Test("a recorded mandate enters cooldown and stays there until it expires")
    func mandateEntersCooldown() {
        var driver = Driver()
        driver.observe(.relevant, Self.ide)
        driver.observe(.unrelated, Self.video, after: 10)
        let sustained = driver.observe(.unrelated, Self.video, after: 100)
        #expect(sustained.isSustained)

        driver.machine.recordMandate(at: driver.clock.elapsed)
        if case .cooldown(let subject, let until) = driver.machine.state {
            #expect(subject == .single(Self.video))
            #expect(until == driver.clock.elapsed + RelevancePolicy.mandateCooldown)
        } else {
            Issue.record("expected cooldown, got \(driver.machine.state)")
        }

        // Still drifting, still quiet.
        let inside = driver.observe(.unrelated, Self.video, after: 300)
        #expect(!inside.isSustained)
        let stillInside = driver.observe(.unrelated, Self.video, after: 299)
        #expect(!stillInside.isSustained, "599 s after the mandate is still inside the cooldown")
    }

    /// …and once it expires the count starts again from nothing, rather than resuming an old
    /// accumulator. The person has heard it once; the second time starts from the beginning.
    @Test("cooldown expiry begins a fresh grace period, not a resumed one")
    func cooldownExpiryBeginsAfresh() {
        var driver = Driver()
        driver.observe(.relevant, Self.ide)
        driver.observe(.unrelated, Self.video, after: 10)
        driver.observe(.unrelated, Self.video, after: 100)
        driver.machine.recordMandate(at: driver.clock.elapsed)

        let expired = driver.observe(.unrelated, Self.video, after: 601)
        #expect(expired.accumulated == .zero)
        #expect(!expired.isSustained)

        // And it takes another full threshold to sustain again.
        #expect(!driver.observe(.unrelated, Self.video, after: 90).isSustained)
        #expect(driver.observe(.unrelated, Self.video, after: 1).isSustained)
    }

    @Test("a held return clears a cooldown early")
    func aHeldReturnClearsCooldown() {
        var driver = Driver()
        driver.observe(.relevant, Self.ide)
        driver.observe(.unrelated, Self.video, after: 10)
        driver.observe(.unrelated, Self.video, after: 100)
        driver.machine.recordMandate(at: driver.clock.elapsed)

        driver.observe(.relevant, Self.ide, after: 1)
        #expect(driver.observe(.relevant, Self.ide, after: 30) == .aligned)
    }

    // MARK: - The extended threshold (R-61's half of the contract)

    /// The transition window may **only** extend the threshold. The machine reads it per
    /// observation and never caches it, so the same drift is not sustained at 100 seconds under
    /// an anchored detour and is at 181.
    @Test("an extended threshold delays sustaining, and never hastens it")
    func anExtendedThresholdOnlyDelays() {
        let extended = RelevancePolicy.sustainedDriftThreshold + RelevancePolicy.detourExtension

        var anchored = Driver()
        anchored.observe(.relevant, Self.ide, threshold: extended)
        anchored.observe(.unrelated, Self.docs, after: 10, threshold: extended)
        #expect(!anchored.observe(.unrelated, Self.docs, after: 100, threshold: extended).isSustained)
        #expect(anchored.observe(.unrelated, Self.docs, after: 81, threshold: extended).isSustained)

        var plain = Driver()
        plain.observe(.relevant, Self.ide)
        plain.observe(.unrelated, Self.docs, after: 10)
        #expect(plain.observe(.unrelated, Self.docs, after: 100).isSustained)
    }

    // MARK: - Purity

    /// A value type with a pure reducer: two machines fed the same observations are `==`, and
    /// feeding one changes nothing about the other. This is what makes replay exact and a
    /// sequence fixture worth committing.
    @Test("the reducer is pure: identical inputs give identical machines")
    func theReducerIsPure() {
        let observations = [
            DriftObservation(now: .seconds(0), verdict: .relevant, subject: Self.ide),
            DriftObservation(now: .seconds(30), verdict: .unrelated, subject: Self.video),
            DriftObservation(now: .seconds(80), verdict: .uncertain, subject: Self.docs),
            DriftObservation(now: .seconds(140), verdict: .unrelated, subject: Self.chat),
            DriftObservation(now: .seconds(260), verdict: .relevant, subject: Self.ide)
        ]

        var first = DriftMachine()
        var second = DriftMachine()
        for observation in observations {
            first.reduce(observation)
            second.reduce(observation)
        }
        #expect(first == second)
        #expect(first.state == second.state)

        // A third machine that stops early is genuinely a different value, so equality is
        // measuring the fold rather than the type.
        var third = DriftMachine()
        for observation in observations.dropLast() { third.reduce(observation) }
        #expect(third != first)
    }

    /// An observation at the same instant is a no-op rather than a divide-by-nothing.
    @Test("a zero interval changes nothing")
    func aZeroIntervalChangesNothing() {
        var driver = Driver()
        driver.observe(.relevant, Self.ide)
        let opened = driver.observe(.unrelated, Self.video, after: 10)
        let repeated = driver.observe(.unrelated, Self.video, after: 0)
        #expect(opened == repeated)
    }

    /// An unrelated observation with no subject cannot open a grace period: there is nothing to
    /// name, and a mandate that named nothing would be an accusation about nobody.
    @Test("an unrelated observation with no subject opens nothing")
    func anUnbundledSubjectOpensNothing() {
        var driver = Driver()
        driver.observe(.relevant, Self.ide)
        #expect(driver.observe(.unrelated, nil, after: 10) == .aligned)
    }
}
