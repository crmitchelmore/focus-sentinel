import Foundation
import Testing

@testable import FocusCore

/// The value the verdict inspector draws, and the drift state underneath it (R-60, R-71).
@Suite("Verdict snapshot")
struct VerdictSnapshotTests {
    private static func snapshot(
        status: FocusStatus = .unrelated,
        drift: DriftState = .aligned,
        band: EvidenceBand? = .medium
    ) -> VerdictSnapshot {
        VerdictSnapshot(
            status: status,
            stage: .heuristic,
            band: band,
            drift: drift,
            eligibility: .suppressed(.withinGracePeriod),
            explanation: Explanation.make(
                stage: .heuristic, band: band ?? .low,
                clauses: [.sustainedDwell(seconds: 30)], stamp: .current
            ),
            stampKey: EngineStamp.current.cacheKey
        )
    }

    /// `nil` is the honest default. An app that drew a verdict before it had judged anything
    /// would be inventing one, which is the same failure `CockpitState.ready` avoids by being
    /// `paused` rather than `relevant`.
    @Test("a cockpit with nothing judged carries no verdict at all")
    func nothingJudgedIsNil() {
        #expect(CockpitState.ready.verdict == nil)
        #expect(CockpitState.storeUnavailable.verdict == nil)
        #expect(CockpitState.ready.status == .paused)
    }

    @Test("a cockpit can carry a verdict without disturbing anything else")
    func cockpitCarriesAVerdict() {
        var state = CockpitState.ready
        state.verdict = Self.snapshot()

        #expect(state.verdict?.status == .unrelated)
        #expect(state.verdict?.stage == .heuristic)
        #expect(state.verdict?.stampKey == "s1.p3.l1.e0.m0")
        #expect(state.storeIsReady)
        #expect(state != CockpitState.ready, "the verdict is part of the value's identity")
    }

    /// An `uncertain` verdict has no evidence to band, and drawing `.low` there would imply a
    /// weak *decision* rather than no decision at all.
    @Test("an uncertain snapshot carries no band")
    func uncertainCarriesNoBand() {
        let snapshot = Self.snapshot(status: .uncertain, band: nil)
        #expect(snapshot.band == nil)
        #expect(snapshot.status == .uncertain)
    }

    @Test("a snapshot resolves the rung that decided, with its copy")
    func snapshotResolvesItsRung() throws {
        let rung = try #require(Self.snapshot().rung)
        #expect(rung.stage == .heuristic)
        #expect(rung.isExecutable)
        #expect(rung.settingsCopyKey == "cascade.rung.heuristic")
    }

    /// e04 emits mandates and nobody consumes them. The property exists so the inspector can
    /// show the eligibility; the nudge is e05's.
    @Test("a suppressed snapshot is not mandated, and says why")
    func suppressedSnapshotSaysWhy() {
        let snapshot = Self.snapshot()
        #expect(!snapshot.isMandated)
        #expect(snapshot.eligibility.suppressionReason == .withinGracePeriod)
        #expect(snapshot.eligibility.mandate == nil)
    }

    // MARK: - DriftState

    @Test("an aligned state accumulates nothing and is about nobody")
    func alignedIsEmpty() {
        #expect(DriftState.aligned.subject == nil)
        #expect(DriftState.aligned.accumulated == .zero)
        #expect(!DriftState.aligned.isMixed)
        #expect(!DriftState.aligned.isSustained)
    }

    @Test("each drift state reports its own subject and accumulator")
    func driftStatesProjectTheirPayloads() {
        let grace = DriftState.grace(
            subject: .single("com.apple.Safari"), since: .seconds(5), accumulated: .seconds(40)
        )
        #expect(grace.subject == .single("com.apple.Safari"))
        #expect(grace.accumulated == .seconds(40))
        #expect(!grace.isSustained)

        let sustained = DriftState.sustained(
            subject: .single("com.apple.Safari"), accumulated: .seconds(120), isMixed: false
        )
        #expect(sustained.accumulated == .seconds(120))
        #expect(sustained.isSustained)
        #expect(!sustained.isMixed)

        let cooldown = DriftState.cooldown(subject: .mixed, until: .seconds(700))
        #expect(cooldown.accumulated == .zero)
        #expect(cooldown.isMixed)
        #expect(!cooldown.isSustained)
    }

    /// Hopping between distractions accumulates rather than resetting, and the resulting
    /// subject names nobody — so a mandate says "several unrelated apps" instead of misnaming
    /// the last application somebody happened to touch (R-60).
    @Test("a mixed subject names nobody, by either route")
    func mixedSubjectNamesNobody() {
        #expect(DriftSubject.mixed.identifier == nil)
        #expect(DriftSubject.mixed.isMixed)
        #expect(DriftSubject.single("com.apple.Safari").identifier == "com.apple.Safari")
        #expect(!DriftSubject.single("com.apple.Safari").isMixed)

        // Either the subject is mixed, or the flag says so: both routes report mixed drift.
        let flagged = DriftState.sustained(
            subject: .single("com.apple.Safari"), accumulated: .seconds(120), isMixed: true
        )
        let subjectMixed = DriftState.sustained(
            subject: .mixed, accumulated: .seconds(120), isMixed: false
        )
        #expect(flagged.isMixed)
        #expect(subjectMixed.isMixed)
    }

    @Test("every drift state round-trips through Codable")
    func driftStatesRoundTrip() throws {
        let states: [DriftState] = [
            .aligned,
            .grace(subject: .single("com.apple.Safari"), since: .seconds(5), accumulated: .seconds(40)),
            .sustained(subject: .mixed, accumulated: .seconds(120), isMixed: true),
            .cooldown(subject: .single("com.apple.Notes"), until: .seconds(700))
        ]
        for state in states {
            let decoded = try JSONDecoder().decode(DriftState.self, from: JSONEncoder().encode(state))
            #expect(decoded == state)
        }
    }
}
