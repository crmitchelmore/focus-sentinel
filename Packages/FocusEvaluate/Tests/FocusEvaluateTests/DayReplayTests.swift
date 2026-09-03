import FocusCore
import FocusEvaluateCore
import Foundation
import Testing

/// **A whole working day, replayed** (T143c, R-94a, goal §3.D.27a).
///
/// A per-judgement rate can look excellent while a day still contains twelve questions, and a bad
/// day is what a person quits over. The corpus is 166 independent claims — several of them
/// deliberately the same situation one second apart — and it cannot see a day at all. These three
/// fixtures can:
///
/// | day | what it is for |
/// |---|---|
/// | `day-01` | three commitments in one day — `dailyQueryCapAllPriorities`' witness |
/// | `day-02` | one long commitment with many askable subjects, across a relaunch |
/// | `day-03` | the day the app says **nothing** |
/// | `day-04` | the day the person **hops** — drift, return, drift, into four applications |
///
/// Every one of them carries the things a real day has and a fixture usually does not: a break, a
/// pause, an idle span, a presentation, a priority change and a relaunch.
///
/// **day-04 is the shape none of the first three had** (focus-f2a). Not one of them contains a
/// person who drifts into more than one application, so the corpus could not see the defect a ship
/// lens measured on the shipping composition root — sixteen drifts into nine applications, and
/// `hasSpokenToday = false`. It is committed for the reading `interruptions = 2`: against the
/// pre-repair reducer the same day replays as four glyph landings, no sentence and a day that cost
/// the person nothing.
@Suite("Day replay")
struct DayReplayTests {
    static var harness: DayReplayHarness { DayReplayHarness(runner: CorpusFixtures.runner) }

    static func days() throws -> [DayFixture] {
        try CorpusFixtures.loaded().days.sorted { $0.id < $1.id }
    }

    // MARK: - The committed claims

    @Test("every committed day replays to exactly what it claims")
    func everyDayReplaysAsCommitted() throws {
        let harness = Self.harness
        for fixture in try Self.days() {
            let transcript = harness.replay(fixture)
            if let mismatch = harness.compare(fixture, to: transcript) {
                Issue.record("\(mismatch.description)")
            }
        }
    }

    /// R-69's byte-identity property, applied to the day lane. The decider is pure and there is no
    /// timer anywhere in the nudge module (R-96i), so a replay is *exact* rather than approximate
    /// — which is the only thing that makes a committed day worth anything.
    @Test("two replays of one day produce byte-identical transcripts")
    func replayIsExact() throws {
        let first = Self.harness
        let second = Self.harness
        for fixture in try Self.days() {
            #expect(first.replay(fixture).digest == second.replay(fixture).digest)
        }
    }

    // MARK: - The day-level ceilings

    /// `nudge.queriesPerFocusDay ≤ 5` and `nudge.interruptionsPerFocusDayMax ≤ 8`, asserted on
    /// **every** day rather than on their mean. A metric that averages a bad day away is a metric
    /// that ships a bad day.
    @Test("no committed day exceeds a shipped cap")
    func noDayExceedsACap() throws {
        let harness = Self.harness
        for fixture in try Self.days() {
            let transcript = harness.replay(fixture)
            #expect(
                transcript.queryCount <= InterventionPolicy.dailyQueryCapAllPriorities,
                "\(fixture.id) delivered \(transcript.queryCount) questions"
            )
            #expect(
                transcript.accusationCount <= InterventionPolicy.dailyAccusationCap,
                "\(fixture.id) delivered \(transcript.accusationCount) rungs"
            )
            #expect(
                transcript.interruptionCount <= InterventionPolicy.dailyInterruptionCap,
                "\(fixture.id) delivered \(transcript.interruptionCount) interruptions"
            )
            #expect(
                transcript.queriesForBusiestPriority <= InterventionPolicy.dailyQueryCap,
                "\(fixture.id)'s busiest priority took \(transcript.queriesForBusiestPriority)"
            )
        }
    }

    /// **The defect `dailyQueryCapAllPriorities` closes.** day-01 carries three commitments; the
    /// per-priority cap alone would license twelve questions across them, bounded only by the
    /// shared budget at seven. The day cap holds it at five — and the fifth is followed by a sixth
    /// attempt under a **fresh** priority whose own cap has barely been touched, which is exactly
    /// the shape of the hole.
    @Test("day-01 carries three priorities and is held at the day cap")
    func theThreePriorityDayIsHeldAtTheDayCap() throws {
        let fixture = try #require(try Self.days().first { $0.id == "day-01" })
        #expect(fixture.segments.count == 3, "day-01 is the three-priority witness")
        let intents = Set(fixture.segments.compactMap { $0.priority?.intent })
        #expect(intents.count == 3, "day-01's three segments must be three different commitments")

        let transcript = Self.harness.replay(fixture)
        #expect(transcript.queryCount == InterventionPolicy.dailyQueryCapAllPriorities)
        let detail = "the day cap must bite before any single priority's cap does, or day-01 "
            + "witnesses dailyQueryCap rather than dailyQueryCapAllPriorities"
        #expect(
            transcript.queriesForBusiestPriority < InterventionPolicy.dailyQueryCap,
            "\(detail)"
        )
    }

    /// The caps are rows in a store keyed by local day, not a number in memory. A cap somebody
    /// could clear by quitting is not a cap.
    @Test("day-02 relaunches, and the day's counts survive it")
    func theCapsSurviveARelaunch() throws {
        let fixture = try #require(try Self.days().first { $0.id == "day-02" })
        let steps = fixture.segments.flatMap(\.steps)
        #expect(steps.contains { $0.then.relaunch }, "day-02 must contain a relaunch")

        let transcript = Self.harness.replay(fixture)
        #expect(transcript.queryCount == InterventionPolicy.dailyQueryCap)
        #expect(fixture.segments.count == 1, "day-02 is the single-commitment day")
    }

    /// **A guardian that could not produce a silent day would be a guardian nobody keeps
    /// installed.** Every gate that buys silence is exercised in turn, and the day ends with
    /// nothing said.
    /// **The day the corpus did not have, and the two halves of the ruling it holds** (focus-f2a).
    ///
    /// The floor: a day of drift into four applications reaches the rung that carries a sentence,
    /// twice, and costs the person the two units those sentences are worth. The ceiling, in the
    /// same fixture: the ladder **alternates**, because a change of subject at the top rung ends
    /// the run rather than buying a second panel. Asserted on the fixture's own committed
    /// expectations rather than on the transcript, so the claim is the one a reader checks.
    @Test("day-04 hops between applications and is answered at the rung that speaks")
    func dayFourHopsAndIsSpokenTo() throws {
        let fixture = try #require(try Self.days().first { $0.id == "day-04" })
        let subjects = Set(fixture.segments.flatMap(\.steps).compactMap(\.subject))
        #expect(
            subjects.count >= 4,
            "day-04 is the hopping day and it visits \(subjects.count) application(s)"
        )
        #expect(fixture.expectInterruptions > 0, "day-04 is committed for a day the app spoke on")

        let transcript = Self.harness.replay(fixture)
        #expect(
            transcript.interruptionCount == fixture.expectInterruptions,
            "day-04 cost \(transcript.interruptionCount) and claims \(fixture.expectInterruptions)"
        )
        // The alternation, read off the day's own nudges: no two panel rungs running.
        var rungs: [LadderRung.Kind] = []
        for step in fixture.segments.flatMap(\.steps) {
            guard case .accuse(let rung) = step.expect.nudge else { continue }
            rungs.append(rung)
        }
        #expect(
            rungs.contains(.panel),
            "day-04 never climbed, so it is day-03 with more applications in it — \(rungs)"
        )
        #expect(
            rungs.contains(.ambient),
            "day-04 never showed the glyph first, so it skipped a rung — \(rungs)"
        )
        let repeated = zip(rungs, rungs.dropFirst()).contains { $0 == .panel && $1 == .panel }
        #expect(
            !repeated,
            "day-04 says its sentence twice running, which is a repetition — \(rungs)"
        )
    }

    @Test("day-03 is a whole day with no interruption at all")
    func theQuietDayIsSilent() throws {
        let fixture = try #require(try Self.days().first { $0.id == "day-03" })
        let transcript = Self.harness.replay(fixture)
        #expect(transcript.queryCount == 0)
        #expect(transcript.accusationCount == 0)
        #expect(transcript.interruptionCount == 0)
        #expect(transcript.world.counters.delivered == 0)
    }

    // MARK: - What a day fixture may claim

    /// The decoder refuses a day that claims more interruptions than the shipped caps allow, and
    /// refuses one whose three counts do not agree. A fixture is a claim, and a claim the app
    /// could not honour is a claim nobody should be able to commit.
    @Test("a day fixture may not claim a day the caps forbid")
    func aDayMayNotClaimAnImpossibleDay() {
        func json(queries: Int, accusations: Int, interruptions: Int) -> String {
            """
            { "id": "day-99", "note": "written by this suite to be refused",
              "segments": [ { "priority": { "intent": "write the report", "revision": 1 },
                "steps": [ { "advanceSeconds": 0, "bundleID": "com.example.app",
                  "expect": { "verdict": "uncertain", "drift": "aligned" } } ] } ],
              "expectQueries": \(queries), "expectAccusations": \(accusations),
              "expectInterruptions": \(interruptions) }
            """
        }
        func decode(_ text: String) throws -> DayFixture {
            try DayFixture.decode(try StrictObject.parse(data: Data(text.utf8), path: "day-99"))
        }

        // A person asked ten questions has been interrupted ten times: a day may never claim
        // fewer interruptions than it claims questions.
        #expect(throws: CorpusDecodingError.self) {
            try decode(json(queries: 2, accusations: 1, interruptions: 1))
        }
        // And nothing but a question or an accusing rung can interrupt anybody, so it may never
        // claim more than their sum either.
        #expect(throws: CorpusDecodingError.self) {
            try decode(json(queries: 2, accusations: 1, interruptions: 4))
        }
        // Above dailyInterruptionCap.
        #expect(throws: CorpusDecodingError.self) {
            try decode(json(queries: 5, accusations: 5, interruptions: 10))
        }
        #expect(throws: Never.self) {
            try decode(json(queries: 2, accusations: 1, interruptions: 3))
        }
        // **And the case the equality used to forbid** (focus-d6r): a day with a rung that
        // accuses nobody. `LadderRung.Kind.ambient.makesAnAccusation` is false, so an ambient
        // landing is a delivered rung that costs no unit of the day — which is exactly what
        // day-01 is, and the equality made that day unstatable.
        #expect(throws: Never.self) {
            try decode(json(queries: 2, accusations: 1, interruptions: 2))
        }
    }

    /// The realistic-day fixtures exist and the floor is met. `queriesPerFocusDay` and
    /// `interruptionsPerFocusDayMax` are measured on these, and a gate scoring a metric on absent
    /// data is a gate reporting a pass it did not measure.
    @Test("the committed day floor is met")
    func theDayFloorIsMet() throws {
        #expect(try Self.days().count >= EvaluationPolicy.dayFloor)
    }
}
