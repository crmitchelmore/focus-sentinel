import FocusCore
import Foundation
import Testing

@testable import FocusSensing

/// An idle source a test can move, so the twenty-one-minute divergence probe P-85 caught once
/// can be reproduced in a microsecond.
final class ScriptedIdleSource: IdleSourceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var hardware: Double
    private var session: Double

    init(hardwareSeconds: Double = 0, sessionSeconds: Double = 0) {
        self.hardware = hardwareSeconds
        self.session = sessionSeconds
    }

    var hardwareSeconds: Double {
        lock.lock()
        defer { lock.unlock() }
        return hardware
    }

    var sessionSeconds: Double {
        lock.lock()
        defer { lock.unlock() }
        return session
    }

    func set(hardware: Double, session: Double) {
        lock.lock()
        defer { lock.unlock() }
        self.hardware = hardware
        self.session = session
    }
}

@MainActor
@Suite("Idle reader")
struct IdleReaderTests {
    // MARK: - Both sources, hardware primary (R-36)

    @Test("Both counters are read on every sample")
    func readsBothSources() {
        let source = ScriptedIdleSource(hardwareSeconds: 1536.37, sessionSeconds: 267.14)
        let reader = IdleReader(source: source, thresholdSeconds: 180)

        let sample = reader.sample()

        // The figures probe P-85 measured on this machine at one instant.
        #expect(sample.reading.hardwareSeconds == 1536.37)
        #expect(sample.reading.sessionSeconds == 267.14)
    }

    @Test("The hardware counter decides, even when the session counter says the user is here")
    func hardwareSourceIsThePrimary() {
        // The exact P-85 divergence: something is posting synthetic events while nobody has
        // touched the keyboard for twenty-five minutes.
        let source = ScriptedIdleSource(hardwareSeconds: 1536.37, sessionSeconds: 267.14)
        let reader = IdleReader(source: source, thresholdSeconds: 180)

        let sample = reader.sample()

        #expect(sample.isIdle)
        #expect(sample.reading.isIdle(threshold: 180))
    }

    @Test("hardwareSeconds >= sessionSeconds holds, because combined counts a superset")
    func sourcesAreInTheRightOrder() {
        let source = ScriptedIdleSource(hardwareSeconds: 1536.37, sessionSeconds: 267.14)
        let reader = IdleReader(source: source, thresholdSeconds: 180)

        #expect(reader.read().sourcesAreInTheRightOrder)
    }

    @Test("The threshold is injected, and moving it moves the verdict")
    func thresholdIsInjected() {
        let source = ScriptedIdleSource(hardwareSeconds: 200, sessionSeconds: 200)
        let reader = IdleReader(source: source, thresholdSeconds: 180)

        #expect(reader.sample().isIdle)

        reader.thresholdSeconds = 600
        #expect(reader.sample().isIdle == false)
    }

    @Test("The default threshold is the stored one, 180 seconds")
    func defaultThresholdIsTheStoredOne() {
        let reader = IdleReader(source: ScriptedIdleSource())
        #expect(reader.thresholdSeconds == Double(FocusSchemaV3.defaultIdleThresholdSeconds))
    }

    // MARK: - One event per transition

    @Test("Presence transitions are reported once each, not once per tick")
    func idleTransitionsAreReportedOnce() {
        let source = ScriptedIdleSource(hardwareSeconds: 0, sessionSeconds: 0)
        let reader = IdleReader(source: source, thresholdSeconds: 180)

        #expect(reader.sample().idleTransition == nil)

        source.set(hardware: 200, session: 200)
        #expect(reader.sample().idleTransition == .becameIdle)
        // Still idle, three ticks later: no second event.
        #expect(reader.sample().idleTransition == nil)
        #expect(reader.sample().idleTransition == nil)

        source.set(hardware: 0, session: 0)
        #expect(reader.sample().idleTransition == .becameActive)
        #expect(reader.sample().idleTransition == nil)
    }

    @Test("Synthetic input is suspected once per transition, in both directions")
    func syntheticInputTransitionsAreReportedOnce() {
        let source = ScriptedIdleSource(hardwareSeconds: 10, sessionSeconds: 10)
        let reader = IdleReader(source: source, thresholdSeconds: 180, syntheticToleranceSeconds: 5)

        #expect(reader.sample().syntheticInputTransition == nil)

        source.set(hardware: 1536.37, session: 267.14)
        #expect(reader.sample().syntheticInputTransition == .began)
        #expect(reader.sample().syntheticInputTransition == nil)

        source.set(hardware: 300, session: 299)
        #expect(reader.sample().syntheticInputTransition == .ended)
        #expect(reader.sample().syntheticInputTransition == nil)
    }

    @Test("A gap inside the tolerance is not a suspicion")
    func smallDivergenceIsNotSuspicious() {
        let source = ScriptedIdleSource(hardwareSeconds: 104, sessionSeconds: 100)
        let reader = IdleReader(source: source, thresholdSeconds: 180, syntheticToleranceSeconds: 5)

        #expect(reader.sample().syntheticInputTransition == nil)
        #expect(reader.read().syntheticInputSuspected(threshold: 5) == false)
    }

    @Test("Forgetting the transitions makes the next sample report the state afresh")
    func forgettingTransitionsResetsTheEdgeDetector() {
        let source = ScriptedIdleSource(hardwareSeconds: 400, sessionSeconds: 400)
        let reader = IdleReader(source: source, thresholdSeconds: 180)

        #expect(reader.sample().idleTransition == .becameIdle)
        #expect(reader.sample().idleTransition == nil)

        // What `SensingHost.resume()` does: the observers were detached, so the last thing
        // this reader saw is not evidence about the interval it did not watch.
        reader.forgetTransitions()
        #expect(reader.sample().idleTransition == .becameIdle)
    }

    // MARK: - The seam it satisfies

    @Test("Idle reports itself available, because reading the counter needs no grant")
    func availabilityIsAvailable() {
        let reader = IdleReader(source: ScriptedIdleSource())
        let seam: any IdleObserving = reader
        #expect(seam.availability == .available)
    }

    @Test("idleDuration() answers from the hardware counter")
    func idleDurationUsesTheHardwareCounter() {
        let source = ScriptedIdleSource(hardwareSeconds: 42, sessionSeconds: 1)
        let reader = IdleReader(source: source)
        let seam: any IdleObserving = reader

        #expect(seam.idleDuration() == .seconds(42))
    }

    // MARK: - The real source

    @Test("The production source reads a live counter with no prompt and no error")
    func productionSourceReadsBothCounters() {
        let source = CGEventIdleSource()
        // **Session first, then hardware — the order `IdleReader.read()` itself uses.**
        //
        // The two counters are read microseconds apart, and on a machine where no input arrives
        // between the reads the later one is larger by exactly that elapsed time. Taking hardware
        // first therefore makes the session figure the larger of the two and violates
        // `sourcesAreInTheRightOrder` by a few hundred nanoseconds — which is what happened here,
        // on an unattended gate run against a machine that had been idle for 584 s:
        //
        //     hardware 584.292967667  session 584.292967875   (208 ns the wrong way)
        //
        // The invariant is real and worth asserting: `.combinedSessionState` counts a superset of
        // the events `.hidSystemState` does, so `combined ≤ hid` is a property of the sources
        // rather than a coincidence, and a violation would mean the reader had swapped them. What
        // was wrong was this test reading them in the opposite order from the shipping code —
        // which is why `read()` puts the session figure in a local first, and why `self-check.sh`
        // carries the same note beside its own half-second tolerance.
        let sessionSeconds = source.sessionSeconds
        let reading = IdleReading(
            hardwareSeconds: source.hardwareSeconds,
            sessionSeconds: sessionSeconds
        )

        // Both are real seconds since some real input — never negative, never NaN.
        #expect(reading.hardwareSeconds >= 0)
        #expect(reading.sessionSeconds >= 0)
        #expect(reading.hardwareSeconds.isFinite)
        #expect(reading.sessionSeconds.isFinite)
        // And the invariant that says the sources were not swapped, on a live reading.
        #expect(reading.sourcesAreInTheRightOrder)
    }
}
