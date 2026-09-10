import FocusCore
import FocusEvaluateCore
import Foundation
import Testing

@testable import FocusClassify

/// The headless sequence-replay harness (R-69, F-158, F-48, F-49).
///
/// The Court downgraded F-158 to exactly this — JSON fixtures replayed against an injected
/// clock, no recorder UI, no debugger surface — on the explicit grounds that F-151's
/// single-shot fixtures **cannot express time**. Everything here is something a single-shot
/// case could not have said: that a short return does not reset, that hopping accumulates, that
/// `uncertain` freezes rather than muting, that an anchored detour gets a second grace period,
/// and that a cooldown ends the way R-60's table says it does.
@Suite("Sequence replay")
struct SequenceReplayTests {
    static func fixtures() throws -> [SequenceFixture] {
        try CorpusFixtures.loaded().sequences
    }

    static var harness: SequenceReplayHarness {
        SequenceReplayHarness(runner: CorpusFixtures.runner)
    }

    // MARK: - The fixtures themselves

    @Test("the sequence directory meets its committed floor")
    func theSequenceFloorIsMet() throws {
        let fixtures = try Self.fixtures()
        #expect(fixtures.count >= EvaluationPolicy.sequenceFloor)
        for fixture in fixtures {
            #expect(!fixture.note.isEmpty, "\(fixture.id) carries no note")
            #expect(fixture.id.hasPrefix("seq-"), "\(fixture.id) is not a sequence id")
            #expect(!fixture.steps.isEmpty)
        }
        let ids = fixtures.map(\.id)
        #expect(Set(ids).count == ids.count, "a sequence id is used twice")
    }

    // MARK: - Every fixture replays to what it claims

    /// The whole state at every step — verdict, source, rung, band, drift state, accumulated
    /// duration, eligibility and clauses — not the mandate count alone. A harness that only
    /// counted nudges could not tell a right answer from a right answer for the wrong reason.
    @Test("every sequence replays to its committed transcript")
    func everySequenceReplaysAsCommitted() throws {
        let harness = Self.harness
        var mismatches: [String] = []
        for fixture in try Self.fixtures() {
            let transcript = harness.replay(fixture)
            if let mismatch = harness.compare(fixture, to: transcript) {
                mismatches.append(mismatch.description)
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.joined(separator: "\n\n"))")
    }

    /// **Byte-identical, twice.** The drift machine and the transition window are pure reducers
    /// on an injected clock reading and there is no timer anywhere in this package, so a replay
    /// is exact rather than approximate. The cross-*process* half of this assertion lives in
    /// `EvaluationGateTests`: the `FocusEvaluate` executable writes `sequences.transcriptDigest`
    /// into its report and the test process recomputes the same digest from the same fixtures.
    /// Two processes, one number, and FNV-1a rather than `Hasher` — which P-118 measured
    /// returning a different value in every process, and which would have made this assertion
    /// meaningless.
    @Test("two replays of one fixture produce byte-identical transcripts")
    func replayIsByteIdentical() throws {
        let harness = Self.harness
        for fixture in try Self.fixtures() {
            let first = harness.replay(fixture)
            let second = harness.replay(fixture)
            #expect(first.text == second.text, "\(fixture.id) is not deterministic")
            #expect(first.digest == second.digest)
        }
    }

    /// A second harness, over a second engine, on the same shared scorer. The drift accumulator
    /// is per-engine state; if a fixture's answer depended on the engine having seen an earlier
    /// fixture, this is where it would show.
    @Test("a fresh harness produces the same transcript as the first")
    func replayIsIndependentOfHistory() throws {
        let fixtures = try Self.fixtures()
        let first = SequenceReplayHarness(runner: CorpusFixtures.runner)
        let second = SequenceReplayHarness(runner: CorpusFixtures.runner)

        // Replaying every fixture through `first` before `second` touches any of them is the
        // part that would fail if state leaked between replays.
        let firstPass = fixtures.map { first.replay($0).digest }
        let secondPass = fixtures.reversed().map { second.replay($0).digest }.reversed()
        #expect(Array(firstPass) == Array(secondPass))
    }

    // MARK: - The look-back bound is sufficient, not merely present (R-74.4)

    /// **R-74.4's assertion, in the form the ruling names it.**
    ///
    /// `maximumLookBackEvents` is class **C** and owes a workload argument rather than a
    /// per-call figure: *"an assertion, over every sequence fixture, that truncating the window
    /// to 32 events produces a transcript byte-identical to an untruncated replay — which is
    /// what makes 32 sufficient rather than merely bounded."* So every committed fixture is
    /// replayed twice, once against the shipped bound and once against an engine whose window
    /// keeps everything, and the two transcripts are compared byte for byte.
    ///
    /// The comparison is only worth making if the bound actually bites somewhere, which is what
    /// the second assertion is for. An earlier form of this test asserted instead that no
    /// fixture's window ever *reaches* the bound — true, and a valid proof that truncation was a
    /// no-op, but a vacuous one: if the thirty-third-oldest observation is never introduced, no
    /// evidence has been produced about what discarding it would do. `seq-0017` exists to
    /// introduce it.
    @Test("truncating the look-back to its bound changes no transcript")
    func theLookBackBoundIsSufficient() throws {
        let harness = Self.harness
        let fixtures = try Self.fixtures()

        for fixture in fixtures {
            let bounded = harness.replay(fixture, lookBackCapacity: RelevancePolicy.maximumLookBackEvents)
            let unbounded = harness.replay(fixture, lookBackCapacity: .max)
            #expect(
                bounded.text == unbounded.text,
                "\(fixture.id): the look-back bound changed the transcript"
            )
            #expect(bounded.digest == unbounded.digest)
        }

        let deepest = fixtures.map(SequenceReplayHarness.maximumWindowOccupancy(of:)).max() ?? 0
        #expect(
            deepest > RelevancePolicy.maximumLookBackEvents,
            """
            No committed fixture ever fills more than \(deepest) of \
            \(RelevancePolicy.maximumLookBackEvents) look-back slots, so the comparison above \
            discarded nothing and proved nothing. R-74.4 needs a fixture on which the bound bites.
            """
        )
    }

    // MARK: - D-05's two cases, named

    /// D-05 ruled F-49 ships as a bounded deterministic look-back with the worked example
    /// *"left IDE <90s ago for docs" ≠ drift*. Both halves are committed fixtures, and the
    /// difference between them is exactly whether there was somewhere to be detouring **from**.
    @Test("D-05's two cases are committed and behave as the ruling says")
    func theCourtsExampleIsCommitted() throws {
        let fixtures = try Self.fixtures()
        let detour = try #require(fixtures.first { $0.id == "seq-0010" })
        let noAnchor = try #require(fixtures.first { $0.id == "seq-0012" })

        #expect(detour.expectMandates == 0, "IDE → docs → IDE must not mandate")
        #expect(noAnchor.expectMandates == 1, "docs → shorts must mandate exactly once")

        let harness = Self.harness
        #expect(harness.replay(detour).mandateCount == 0)
        #expect(harness.replay(noAnchor).mandateCount == 1)
    }

    /// R-60's five rulings, read off the committed fixtures rather than restated. Each names the
    /// sequence that would go red if the ruling were reversed.
    @Test("the transition table's five rulings each have a fixture")
    func theTransitionTableIsCovered() throws {
        let byID = Dictionary(uniqueKeysWithValues: try Self.fixtures().map { ($0.id, $0) })
        let harness = Self.harness

        // 1 — a short return does not reset; a held one does.
        let reset = try #require(byID["seq-0005"])
        #expect(harness.replay(reset).mandateCount == 1)

        // 2 — hopping between distractions accumulates and reports isMixed.
        let mixed = try #require(byID["seq-0004"])
        let mixedTranscript = harness.replay(mixed)
        #expect(mixedTranscript.mandateCount == 1)
        #expect(
            mixedTranscript.records.last?.isMixed == true,
            "the mandate does not report several unrelated subjects"
        )
        #expect(
            mixedTranscript.records.last?.clauses.contains(.mixedSubjects) == true,
            "the explanation misnames one application instead of saying there were several"
        )

        // 3 — uncertain freezes: neither a return nor drift.
        let frozen = try #require(byID["seq-0002"])
        #expect(harness.replay(frozen).mandateCount == 1)

        // 4 — idle freezes.
        let idle = try #require(byID["seq-0013"])
        let idleTranscript = harness.replay(idle)
        #expect(idleTranscript.mandateCount == 1)
        #expect(
            idleTranscript.records.contains { $0.eligibility == .suppressed(.userIdle) },
            "no step was suppressed for idleness"
        )

        // 5 — leaving focus resets outright.
        let onBreak = try #require(byID["seq-0014"])
        let breakTranscript = harness.replay(onBreak)
        #expect(breakTranscript.mandateCount == 1)
        #expect(
            breakTranscript.records.contains {
                $0.eligibility == .suppressed(.sessionPhaseForbids) && $0.driftName == "aligned"
            },
            "the break neither suppressed nor reset"
        )
    }

    /// The cooldown is the engine's own proportionality and e05's ladder will have its own on
    /// top. Two fixtures cover the two ways out of it: waiting, and going back to work.
    @Test("the mandate cooldown holds and both exits from it are covered")
    func theCooldownHolds() throws {
        let byID = Dictionary(uniqueKeysWithValues: try Self.fixtures().map { ($0.id, $0) })
        let harness = Self.harness

        let waited = try #require(byID["seq-0007"])
        let waitedTranscript = harness.replay(waited)
        #expect(waitedTranscript.mandateCount == 2)
        #expect(
            waitedTranscript.records.contains {
                $0.eligibility == .suppressed(.withinMandateCooldown)
            },
            "nothing was ever suppressed by the cooldown"
        )

        let returned = try #require(byID["seq-0015"])
        #expect(harness.replay(returned).mandateCount == 2)
    }

    // MARK: - The bridge from a real run (R-69)

    /// `ActivityEventStore.exportJSON` is the recording route the Court kept when it cut the
    /// recorder UI: already shipped, already deterministic, and already re-checking every stored
    /// `detail` through `NormalisedDetail.inspect`, so what crosses this boundary is
    /// closed-vocabulary tokens, bundle identifiers, numbers and timestamps — never raw captured
    /// content. This is the payload that store emits, converted into a fixture.
    @Test("an exportJSON payload converts into a replayable fixture")
    func theExportBridgeRoundTrips() throws {
        let export = Data(
            """
            [
              { "at": "2026-01-01T09:00:00Z", "bundleID": "com.apple.Pages",
                "displayID": null, "dwellSeconds": 0,
                "kind": "frontmostApplicationChanged", "measurement": null,
                "measurementValue": null, "sessionID": null, "tokens": null },
              { "at": "2026-01-01T09:02:00Z", "bundleID": "com.valvesoftware.steam",
                "displayID": null, "dwellSeconds": 0,
                "kind": "frontmostApplicationChanged", "measurement": null,
                "measurementValue": null, "sessionID": null, "tokens": null },
              { "at": "2026-01-01T09:02:30Z", "bundleID": null,
                "displayID": null, "dwellSeconds": null,
                "kind": "userIdle", "measurement": null,
                "measurementValue": null, "sessionID": null, "tokens": null },
              { "at": "2026-01-01T09:04:00Z", "bundleID": "com.valvesoftware.steam",
                "displayID": null, "dwellSeconds": 120,
                "kind": "frontmostApplicationChanged", "measurement": null,
                "measurementValue": null, "sessionID": null, "tokens": null }
            ]
            """.utf8
        )

        let fixture = try SequenceFixture.decode(
            fromExport: export,
            id: "seq-recorded",
            note: "recorded from a real run",
            priority: CorpusPriority(
                intent: "Write the Q3 proposal for Acme", doneWhen: "sent to Dana", revision: 1
            ),
            contextPack: [CorpusContextItem(kind: .app, value: "com.apple.Pages")],
            rules: [
                CorpusRule(
                    authority: .global,
                    subjectKind: .app,
                    subject: "com.valvesoftware.steam",
                    verdict: .unrelated
                )
            ]
        )

        // Only the frontmost activations become steps; the idle row describes the session
        // rather than what was on screen.
        #expect(fixture.steps.count == 3)
        #expect(fixture.steps.map(\.advanceSeconds) == [0, 120, 120])
        #expect(fixture.steps.map(\.bundleIdentifier) == [
            "com.apple.Pages", "com.valvesoftware.steam", "com.valvesoftware.steam"
        ])

        // And it replays. A recording asserts nothing — turning one into a golden fixture means
        // a person reading this transcript and committing what they agree with — so the
        // assertion here is that the harness produces one at all, and that the drift it reports
        // is the drift the recorded stream implies.
        //
        // Worth reading rather than skimming: the recorded stream is two minutes in Pages and
        // then four minutes in a game, and it produces **no mandate**. Pages held for a hundred
        // and twenty seconds, which is past `returnAnchorDwell`, so the transition window found
        // a return anchor and the effective threshold became a hundred and eighty seconds —
        // and the drift accumulator had only reached a hundred and twenty when the recording
        // ended. That is D-05's ruling arriving from a real event stream rather than from a
        // hand-written fixture, which is exactly what this bridge is for.
        let transcript = Self.harness.replay(fixture)
        #expect(transcript.records.count == 3)
        #expect(transcript.records[0].verdict == .relevant)
        #expect(transcript.records[1].verdict == .unrelated)
        #expect(transcript.records[2].driftName == "grace")
        #expect(transcript.records[2].accumulatedSeconds == 120)
        #expect(transcript.mandateCount == 0)
        #expect(!transcript.text.isEmpty)
    }

    @Test("an export carrying no activation is refused rather than replayed empty")
    func anEmptyExportIsRefused() {
        let export = Data("[]".utf8)
        #expect(throws: CorpusDecodingError.self) {
            _ = try SequenceFixture.decode(
                fromExport: export, id: "seq-empty", note: "n", priority: nil
            )
        }
    }

    // MARK: - e05 · the nudge lane (T143d)

    /// The fourteen fixtures e05 owes, by id. A fixture that vanished would take an invariant
    /// with it silently — and several of these are named as mutation witnesses in
    /// `InterventionPolicy.manifest`, where a lost witness is a constant nothing tests.
    @Test("every nudge sequence fixture e05 committed is present")
    func theNudgeFixturesArePresent() throws {
        let ids = Set(try Self.fixtures().map(\.id))
        for number in 19...32 {
            let id = String(format: "seq-%04d", number)
            #expect(ids.contains(id), "\(id) is missing")
        }
    }

    /// **A defect's gate is zero** (R-94, U-1). Asserted over every fixture rather than only the
    /// ones written about it, because a question asked twice is a defect wherever it happens.
    @Test("no sequence asks the same question twice")
    func noSequenceRepeatsAQuestion() throws {
        let harness = Self.harness
        for fixture in try Self.fixtures() {
            let transcript = harness.replay(fixture)
            #expect(
                transcript.world.repeatQueries == 0,
                "\(fixture.id) asked \(transcript.world.repeatQueries) question(s) twice"
            )
            #expect(
                transcript.world.accusationsFromQuery == 0,
                "\(fixture.id) produced an accusation from an uncertain verdict"
            )
            #expect(
                transcript.world.escalationsFromDeferred == 0,
                "\(fixture.id) escalated past a rung nobody could see"
            )
            #expect(
                transcript.world.queriesOnUnaskable == 0,
                "\(fixture.id) asked a question R-77 marks unaskable"
            )
        }
    }

    /// **R-81, as arithmetic.** seq-0025 offers the ambient rung twice over a full-screen space
    /// and delivers neither; the ladder does not advance, so when the presentation ends the rung
    /// that arrives is the one it never left — the quietest thing the app can do rather than the
    /// loudest.
    @Test("a deferred rung advances nothing and spends nothing")
    func aDeferredRungAdvancesNothing() throws {
        let fixture = try #require(try Self.fixtures().first { $0.id == "seq-0025" })
        let transcript = Self.harness.replay(fixture)

        let deferred = transcript.records.filter { $0.nudge == .deferred(.menuBarHidden) }
        #expect(deferred.count == 2, "seq-0025 must defer twice before it delivers once")
        #expect(transcript.accusationCount == 1)
        let delivered = transcript.records.compactMap { record -> LadderRung.Kind? in
            if case .accuse(let kind) = record.nudge { return kind }
            return nil
        }
        #expect(delivered == [.ambient], "the ladder resumed above the rung it never delivered")
    }

    /// **Adversarial review finding 3.** Ask, answer "Yes", delete the learned rule, and the app
    /// still says nothing — because gate 11 reads the immutable receipt and never the rule.
    @Test("deleting the rule an answer wrote does not re-open the question")
    func deletingTheRuleDoesNotReopenTheQuestion() throws {
        let fixture = try #require(try Self.fixtures().first { $0.id == "seq-0027" })
        let transcript = Self.harness.replay(fixture)

        #expect(transcript.records.contains { $0.action.contains("deleted=") })
        // After the deletion the subject is uncertain again — a warrant IS constructible — and
        // the app is silent anyway, by name.
        let afterDeletion = transcript.records.drop { !$0.action.contains("deleted=") }.dropFirst()
        #expect(
            afterDeletion.contains { $0.verdict == .uncertain },
            "the deletion must return the subject to uncertain, or the fixture proves nothing"
        )
        #expect(
            afterDeletion.contains { $0.nudge == .silent(.alreadyAsked) },
            "the receipt must be what holds once the session's own memory is gone"
        )
        #expect(transcript.queryCount == 2)
    }

    /// **U-2, and the rule that replaced R-84a's asymmetry — now driven at both rungs.**
    ///
    /// An accusation arriving while a question is on screen is **withheld and waits**. It does
    /// not close the question, does not decline it and does not take the slot: the person
    /// finishes answering the cheap teaching question, and only then does the accusation arrive.
    /// The rung is not lost by waiting — no delivery is recorded and the escalation clock does
    /// not start — and the question stays remembered, so it is never asked twice.
    ///
    /// **"An accusation" meant the rung that speaks, and this fixture used to apply it to the
    /// glyph as well** (focus-0y6). Gate 9 is an occupancy rule and
    /// `NudgeSurface.menuBar.holdsTheInterruptionSlot` is `false`, so withholding the ambient rung
    /// was refusing a thing on the grounds of a property it does not have — and the consequence
    /// reached the person as the status item going blank for as long as one question sat on the
    /// screen. The sequence now runs the question past **both** rungs: the glyph lands under it at
    /// 142 s, the panel rung is withheld at 835 s, and it arrives at 1528 s once the question has
    /// been answered. Nothing about U-2 is loosened; what changed is which rung the ruling was
    /// ever about.
    ///
    /// **This test was called `anAccusationPreemptsAQuestion` and its failure message read "the
    /// preempted question came back".** Its own fixture had said the opposite since U-2 deleted
    /// preemption, and the body passed throughout because the behaviour was right and only the
    /// caption was false. A green assertion under a false caption teaches the next reader the
    /// mechanism the product does not have, which is how preemption kept coming back. The
    /// assertions below now name the waiting rather than counting around it.
    @Test("the panel rung waits behind an open question and the glyph does not")
    func anAccusationWaitsBehindAnOpenQuestion() throws {
        let fixture = try #require(try Self.fixtures().first { $0.id == "seq-0032" })
        let transcript = Self.harness.replay(fixture)

        #expect(transcript.queryCount == 1)
        #expect(transcript.accusationCount == 2, "the glyph and the panel are two deliveries")

        func index(ofRung rung: LadderRung.Kind) throws -> Int {
            let found = transcript.records.firstIndex(where: { record in
                if case .accuse(let delivered) = record.nudge { return delivered == rung }
                return false
            })
            return try #require(found, "the \(rung.rawValue) rung never arrived at all")
        }

        // **The withholding itself**, which counting alone cannot see: a preempting accusation
        // and a waiting one both end with the same rungs in the transcript.
        let withheld = transcript.records.filter { $0.nudge == .silent(.interruptionInFlight) }
        #expect(!withheld.isEmpty, "the accusation never waited — nothing was withheld in flight")

        // And the rung that SPEAKS waited: every withholding precedes the panel's delivery.
        let panelAt = try index(ofRung: .panel)
        #expect(
            withheld.allSatisfy { record in
                transcript.records.firstIndex(of: record).map { $0 < panelAt } ?? false
            },
            "an accusation was withheld after the panel rung had already been delivered"
        )

        // **And the glyph did not.** It landed under the open question, before the withholding
        // that held the panel back — the half that used to go the other way, silently.
        let glyphAt = try index(ofRung: .ambient)
        #expect(
            glyphAt < panelAt,
            "the ladder reached the panel without ever marking the item"
        )
        #expect(
            withheld.contains { record in
                transcript.records.firstIndex(of: record).map { $0 > glyphAt } ?? false
            },
            """
            nothing was withheld after the glyph landed, so this fixture never puts the panel \
            rung and an open question in the same moment and proves neither half
            """
        )

        // The question was never closed as declined by the arrival of either rung: the only
        // thing that ends it is the person answering it.
        #expect(
            transcript.records.last?.nudge == .silent(.alreadyAsked),
            "the question the person answered was not remembered"
        )
    }
}
