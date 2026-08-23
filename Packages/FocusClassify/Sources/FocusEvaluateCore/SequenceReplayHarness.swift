import FocusClassify
import FocusCore
import Foundation

/// One step's whole state, in the order a transcript prints it.
///
/// **Whole**, deliberately. A harness that only counted mandates could not tell a right answer
/// from a right answer for the wrong reason — a sequence that produced one mandate at the right
/// time by way of the wrong rung would look identical to one that did it properly.
public struct SequenceObservationRecord: Sendable, Equatable {
    public let index: Int
    public let nowSeconds: Int
    public let subject: String?
    public let dwellSeconds: Int
    public let verdict: Verdict
    public let source: VerdictSource
    public let stage: CascadeStage
    public let band: EvidenceBand?
    public let driftName: String
    public let accumulatedSeconds: Int
    public let eligibility: CorpusEligibility
    public let clauses: [ExplanationClauseKind]
    public let isMixed: Bool

    /// One line, pipe-separated and fully ordered. This is what the digest is taken over, so it
    /// has to be a total description rather than a summary.
    public var line: String {
        let clauseText = clauses.map(\.rawValue).sorted().joined(separator: ",")
        return [
            "\(index)",
            "\(nowSeconds)",
            subject ?? "-",
            "\(dwellSeconds)",
            verdict.rawValue,
            source.rawValue,
            stage.rawValue,
            band?.rawValue ?? "-",
            driftName,
            "\(accumulatedSeconds)",
            eligibility.encoded,
            clauseText.isEmpty ? "-" : clauseText,
            isMixed ? "mixed" : "single"
        ].joined(separator: "|")
    }
}

/// What a whole replay produced.
public struct SequenceTranscript: Sendable, Equatable {
    public let id: String
    public let records: [SequenceObservationRecord]
    public let mandateCount: Int

    /// The transcript, one line per step. Printed on a failure, so a reviewer reads what
    /// happened rather than which assertion tripped.
    public var text: String { records.map(\.line).joined(separator: "\n") }

    /// FNV-1a over the transcript. Never `Hasher`: P-118 measured it returning a different value
    /// in every process, which would make a cross-process byte-identity assertion meaningless.
    public var digest: UInt64 { FNV1a.hash(text) }
}

/// How a replay differed from what the fixture claimed.
public struct SequenceMismatch: Sendable, Equatable {
    public let id: String
    public let note: String
    public let differences: [String]
    public let transcript: String

    public var description: String {
        """
        \(id): \(differences.joined(separator: "; "))
        \(note)
        \(transcript)
        """
    }
}

/// **Replay, exactly.**
///
/// The drift machine and the transition window are pure reducers on an injected clock reading
/// (R-60, R-61) and there is no timer anywhere in `FocusClassify` (lint R-70e), so a replay is
/// *exact* rather than approximate: the same fixture produces the same transcript, byte for
/// byte, across two runs and two processes. P-118 established the determinism underneath —
/// three CLI launches and two zero-grant `open -a` launches agreed on an FNV over 2 436 vector
/// components — which is what makes committing a transcript digest worth anything.
///
/// The clock is `FocusCore.TestClock`, the shipped value-type `MonotonicClock` whose
/// `advance(by:)` has a `precondition(delta >= .zero)`. No new time source is invented for this.
public struct SequenceReplayHarness: Sendable {
    public let runner: CorpusRunner

    public init(runner: CorpusRunner) {
        self.runner = runner
    }

    public func snapshot(for fixture: SequenceFixture) -> RuleSnapshot {
        // A sequence's snapshot is the same shape a single-shot case builds, so the two lanes
        // cannot drift apart in what a "snapshot" means.
        runner.snapshot(
            for: CorpusCase(
                id: fixture.id,
                note: fixture.note,
                families: [],
                isNegativeControl: false,
                priority: fixture.priority,
                contextPack: fixture.contextPack,
                rules: fixture.rules,
                legacySessionScopedRows: [],
                expectSkippedRuleCount: 0,
                evidence: CorpusEvidence(bundleIdentifier: nil, origin: nil, titleTokens: []),
                evidenceRevision: nil,
                dwellSeconds: 0,
                sessionPhase: .focus,
                focusStatus: nil,
                isUserIdle: false,
                expect: CorpusExpectation(
                    verdict: .uncertain,
                    source: .undecided,
                    stage: .unresolved,
                    band: nil,
                    eligibility: .suppressed(.verdictUncertain),
                    clauses: [],
                    uncertaintyReason: nil
                ),
                expectExplanationTokens: nil,
                file: "sequences"
            )
        )
    }

    /// Replay one fixture and record everything.
    ///
    /// `lookBackCapacity` is `RelevancePolicy.maximumLookBackEvents` on every ordinary replay.
    /// R-74.4's sufficiency proof passes an unbounded value and requires the transcript to come
    /// back byte-identical — which is what makes 32 a bound somebody measured rather than a
    /// round number, and what will fail loudly the day a fixture needs a deeper window.
    public func replay(
        _ fixture: SequenceFixture,
        lookBackCapacity: Int = RelevancePolicy.maximumLookBackEvents
    ) -> SequenceTranscript {
        let snapshot = snapshot(for: fixture)
        let engine = DeterministicRelevanceEngine(
            normalizer: runner.normalizer,
            scorer: runner.scorer,
            lookBackCapacity: lookBackCapacity
        )
        var clock = TestClock()

        var records: [SequenceObservationRecord] = []
        var mandateCount = 0
        var currentSubject: String??
        var subjectSince = Duration.zero

        for (index, step) in fixture.steps.enumerated() {
            clock.advance(by: .seconds(step.advanceSeconds))
            let now = clock.elapsed

            // Dwell is time since the subject last changed, which is what the sensing layer
            // reports. A fixture may state it instead when the dwell is the thing under test.
            if currentSubject == nil || currentSubject! != step.subject {
                currentSubject = step.subject
                subjectSince = now
            }
            let dwell = step.dwellSeconds.map { Duration.seconds($0) } ?? (now - subjectSince)

            let judgement = engine.judge(
                input: ClassificationInput(
                    priorityIntent: fixture.priority?.intent ?? "",
                    priorityDoneWhen: fixture.priority?.doneWhen,
                    bundleIdentifier: step.bundleIdentifier,
                    origin: step.origin,
                    titleTokens: step.titleTokens
                ),
                snapshot: snapshot,
                now: now,
                dwell: dwell,
                phase: step.sessionPhase,
                isUserIdle: step.isUserIdle
            )

            if judgement.eligibility.isMandated { mandateCount += 1 }

            records.append(
                SequenceObservationRecord(
                    index: index,
                    nowSeconds: Int(now.components.seconds),
                    subject: step.subject,
                    dwellSeconds: Int(dwell.components.seconds),
                    verdict: judgement.verdict,
                    source: judgement.outcome.source,
                    stage: judgement.stage,
                    band: judgement.verdict == .uncertain ? nil : judgement.outcome.band,
                    driftName: Self.name(of: judgement.drift),
                    accumulatedSeconds: Int(judgement.drift.accumulated.components.seconds),
                    eligibility: judgement.eligibility.isMandated
                        ? .mandated
                        : .suppressed(judgement.eligibility.suppressionReason ?? .verdictUncertain),
                    clauses: judgement.explanation.clauseKinds,
                    isMixed: judgement.drift.isMixed
                )
            )
        }

        return SequenceTranscript(id: fixture.id, records: records, mandateCount: mandateCount)
    }

    /// Compare a replay to what the fixture claimed, step by step.
    public func compare(
        _ fixture: SequenceFixture,
        to transcript: SequenceTranscript
    ) -> SequenceMismatch? {
        var differences: [String] = []

        if transcript.mandateCount != fixture.expectMandates {
            differences.append(
                "mandates \(transcript.mandateCount) ≠ \(fixture.expectMandates)"
            )
        }

        for (record, step) in zip(transcript.records, fixture.steps) {
            let expect = step.expect
            let at = "step \(record.index) at \(record.nowSeconds)s"

            if record.verdict != expect.verdict {
                differences.append("\(at): verdict \(record.verdict.rawValue) ≠ \(expect.verdict.rawValue)")
            }
            if record.driftName != expect.drift {
                differences.append("\(at): drift \(record.driftName) ≠ \(expect.drift)")
            }
            if let stage = expect.stage, record.stage != stage {
                differences.append("\(at): stage \(record.stage.rawValue) ≠ \(stage.rawValue)")
            }
            if let band = expect.band, record.band != band {
                differences.append("\(at): band \(record.band?.rawValue ?? "-") ≠ \(band.rawValue)")
            }
            if let eligibility = expect.eligibility, record.eligibility != eligibility {
                differences.append(
                    "\(at): eligibility \(record.eligibility.encoded) ≠ \(eligibility.encoded)"
                )
            }
            if let clauses = expect.clauses, Set(record.clauses) != clauses {
                differences.append(
                    "\(at): clauses [\(record.clauses.map(\.rawValue).sorted().joined(separator: " "))]"
                        + " ≠ [\(clauses.map(\.rawValue).sorted().joined(separator: " "))]"
                )
            }
            if let accumulated = expect.accumulatedSeconds,
               record.accumulatedSeconds != accumulated {
                differences.append(
                    "\(at): accumulated \(record.accumulatedSeconds)s ≠ \(accumulated)s"
                )
            }
        }

        guard !differences.isEmpty else { return nil }
        return SequenceMismatch(
            id: fixture.id,
            note: fixture.note,
            differences: differences,
            transcript: transcript.text
        )
    }

    /// The most observations any `lookBackSpan`-wide window over this fixture ever holds.
    ///
    /// The *non-vacuity* half of R-74.4's look-back proof. The proof itself is a replay against
    /// an unbounded window compared byte for byte with the bounded one; this number is what says
    /// whether that comparison exercised anything. A corpus in which no window ever reaches the
    /// cap makes the comparison trivially true and proves nothing about the bound, so
    /// `SequenceReplayTests` requires at least one committed fixture whose high-water mark is
    /// **above** `maximumLookBackEvents` — a fixture on which the 33rd-oldest observation really
    /// is discarded, and on which the transcript is nevertheless unchanged.
    public static func maximumWindowOccupancy(of fixture: SequenceFixture) -> Int {
        var instants: [Duration] = []
        var now = Duration.zero
        for step in fixture.steps {
            now += .seconds(step.advanceSeconds)
            instants.append(now)
        }

        var highWater = 0
        for (index, instant) in instants.enumerated() {
            let horizon = instant - RelevancePolicy.lookBackSpan
            let occupancy = instants[0...index].filter { $0 >= horizon }.count
            highWater = max(highWater, occupancy)
        }
        return highWater
    }

    static func name(of drift: DriftState) -> String {
        switch drift {
        case .aligned: "aligned"
        case .grace: "grace"
        case .sustained: "sustained"
        case .cooldown: "cooldown"
        }
    }
}
