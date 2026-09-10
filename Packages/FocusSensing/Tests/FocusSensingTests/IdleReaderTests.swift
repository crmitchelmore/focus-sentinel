import CoreGraphics
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
    // MARK: - Both sources, neither of them primary (R-36, focus-7az)

    @Test("Both counters are read on every sample")
    func readsBothSources() {
        let source = ScriptedIdleSource(hardwareSeconds: 1536.37, sessionSeconds: 267.14)
        let reader = IdleReader(source: source, thresholdSeconds: 180)

        let sample = reader.sample()

        // The figures probe P-85 measured on this machine at one instant.
        #expect(sample.reading.hardwareSeconds == 1536.37)
        #expect(sample.reading.sessionSeconds == 267.14)
    }

    @Test("A counter past the threshold is enough, even when the other says the user is here")
    func eitherCounterPastTheThresholdIsIdle() {
        // The exact P-85 divergence: something is posting synthetic events while nobody has
        // touched the keyboard for twenty-five minutes. The session figure is well under the
        // threshold and the verdict is still idle, because the hardware clock's silence is
        // evidence of absence and the session clock's noise is not evidence of presence.
        let source = ScriptedIdleSource(hardwareSeconds: 1536.37, sessionSeconds: 267.14)
        let reader = IdleReader(source: source, thresholdSeconds: 1000)

        let sample = reader.sample()

        #expect(sample.reading.sessionSeconds < 1000)
        #expect(sample.isIdle)
        #expect(sample.reading.isIdle(threshold: 1000))
    }

    /// The figures are the ones probe `/private/tmp/idleprobe` read off this Mac on 2026-09-03
    /// while `w` said every tty had been idle 4:08 and nobody was in the room.
    ///
    /// At HEAD this returned **false** — `isIdle` was `hardwareSeconds >= threshold`, and
    /// `.hidSystemState` at the `~0` sentinel is IOHIDSystem's `HIDIdleTime`, which a HID device
    /// report resets without producing an input event. The app called a four-hours-absent person
    /// present and kept nudging an empty chair, which is the exact failure idle detection exists
    /// to prevent.
    @Test("A phantom HID reset does not make an absent person present")
    func phantomHardwareResetDoesNotDefeatIdle() {
        let reading = IdleReading(hardwareSeconds: 105.71, sessionSeconds: 14850.04)

        #expect(reading.isIdle(threshold: 180))
    }

    /// The mirror: the session counter is the blind one when input arrives from outside this
    /// login session, so neither source may be trusted to say "present" on its own.
    @Test("A busy session counter does not make an absent person present either")
    func phantomSessionResetDoesNotDefeatIdle() {
        let reading = IdleReading(hardwareSeconds: 14850.04, sessionSeconds: 105.71)

        #expect(reading.isIdle(threshold: 180))
    }

    @Test("Both counters quiet for less than the threshold is present, not idle")
    func bothCountersBelowTheThresholdIsPresent() {
        let reading = IdleReading(hardwareSeconds: 105.71, sessionSeconds: 179.99)

        #expect(!reading.isIdle(threshold: 180))
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

    /// The seam answers the same figure `isIdle` compares against the threshold — the longest
    /// silence either source can testify to — rather than the hardware clock alone, which on
    /// this Mac read 105 s for a chair that had been empty four hours (focus-7az).
    @Test("idleDuration() answers the longer of the two counters, whichever it is")
    func idleDurationTakesTheLongerSilence() {
        let hardwareIsLonger: any IdleObserving = IdleReader(
            source: ScriptedIdleSource(hardwareSeconds: 42, sessionSeconds: 1)
        )
        #expect(hardwareIsLonger.idleDuration() == .seconds(42))

        let sessionIsLonger: any IdleObserving = IdleReader(
            source: ScriptedIdleSource(hardwareSeconds: 1, sessionSeconds: 42)
        )
        #expect(sessionIsLonger.idleDuration() == .seconds(42))
    }

    // MARK: - The real source

    @Test("The production source reads a live counter with no prompt and no error")
    func productionSourceReadsBothCounters() {
        let source = CGEventIdleSource()
        // **Session first, then hardware — the order `IdleReader.read()` itself uses**, so that
        // the syscall's worth of elapsed time between the two reads always lands on the same
        // side and the published gap is a fact about the sources rather than about read order.
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
        // NO ORDERING IS ASSERTED HERE. `hardware >= session` was never a property of the two
        // states at the `~0` sentinel; see the agreement test below for the one that is.
    }

    /// Live tables can disagree, including for concrete event types on a hosted login session.
    @Test("Concrete event types return finite readings from both independent source tables")
    func concreteEventTypesHaveValidReadings() {
        let rows = CGEventIdleSource.secondsPerConcreteEventType()

        // Non-vacuity: "every row agrees" is satisfied by no rows at all.
        #expect(rows.count >= 4)
        #expect(Set(rows.map(\.eventType)).count >= 4)

        for row in rows {
            #expect(row.hardwareSeconds.isFinite, "\(row.eventType) hardware is not finite")
            #expect(row.sessionSeconds.isFinite, "\(row.eventType) session is not finite")
            #expect(row.hardwareSeconds >= 0, "\(row.eventType) hardware is negative")
            #expect(row.sessionSeconds >= 0, "\(row.eventType) session is negative")
            #expect(row.differenceSeconds.isFinite)
        }
    }

    @Test("Concrete idle diagnostics preserve both source tables and each event type")
    func concreteEventTypesPreserveIndependentSources() {
        var calls: [(CGEventSourceStateID, CGEventType)] = []
        let rows = CGEventIdleSource.secondsPerConcreteEventType { state, eventType in
            calls.append((state, eventType))
            return Double(eventType.rawValue) + (state == .hidSystemState ? 100 : 200)
        }
        #expect(calls.count == 8)
        for (index, entry) in CGEventIdleSource.concreteEventTypes.enumerated() {
            #expect(calls[index * 2].0 == .combinedSessionState)
            #expect(calls[index * 2 + 1].0 == .hidSystemState)
            #expect(calls[index * 2].1 == entry.type)
            #expect(calls[index * 2 + 1].1 == entry.type)
            #expect(rows[index].eventType == entry.name)
            #expect(rows[index].hardwareSeconds == Double(entry.type.rawValue) + 100)
            #expect(rows[index].sessionSeconds == Double(entry.type.rawValue) + 200)
            #expect(rows[index].differenceSeconds == -100)
        }
    }

}
