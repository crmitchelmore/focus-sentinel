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

    /// `maximumLookBackEvents` is class **C** and owes a workload argument rather than a
    /// per-call figure. `TransitionWindow` prunes by span first and by count second, so the
    /// count bound only bites once a span-wide window already holds more than that many
    /// observations. No fixture's window comes close, so truncating to the bound is provably a
    /// no-op over this corpus — which is the stronger form of "sufficient", and the one that
    /// fails loudly if a future fixture ever needs a deeper window.
    @Test("no fixture's look-back window ever reaches the committed bound")
    func theLookBackBoundIsSufficient() throws {
        for fixture in try Self.fixtures() {
            let occupancy = SequenceReplayHarness.maximumWindowOccupancy(of: fixture)
            #expect(
                occupancy <= RelevancePolicy.maximumLookBackEvents,
                "\(fixture.id) fills \(occupancy) of \(RelevancePolicy.maximumLookBackEvents) look-back slots"
            )
        }
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
}
