import FocusClassify
import FocusCore
import Foundation

/// What a whole replayed day produced.
public struct DayTranscript: Sendable, Equatable {
    public let id: String
    public let records: [SequenceObservationRecord]
    /// Questions delivered across the whole day, every priority together. **The number a person
    /// actually feels**, and the one `dailyQueryCapAllPriorities` exists to bound.
    public let queryCount: Int
    /// Accusation rungs delivered across the whole day.
    public let accusationCount: Int
    /// The heaviest single priority's question count — `queriesPerPriorityMax`'s per-day term.
    public let queriesForBusiestPriority: Int
    public let world: NudgeWorld

    /// **What the day actually cost the person** (focus-d6r).
    ///
    /// Read off the replayed world's own `InterruptionBudget` rather than summed here, and that
    /// is the fix. It was `queryCount + accusationCount`, which counts every delivered rung — so
    /// this was the fourth independent answer in the programme to *"what did that rung cost?"*,
    /// and the one behind a **gated** number: `nudge.interruptionsPerFocusDayMax` is asserted
    /// against `dailyInterruptionCap`, and it was counting ambient glyph landings as
    /// interruptions. Measured on day-01, which delivers five questions and one ambient rung: the
    /// gate read 6 where the app charges 5, and a day of ten glyph landings and no sentence at
    /// all would have failed a cap it never went near.
    ///
    /// `deliveredNudgeCount` below is the other number and it is a different claim: how many
    /// things the app said or drew, which is what a day fixture's `expectQueries` and
    /// `expectAccusations` are about and what the record has to account for.
    public var interruptionCount: Int { world.budget.interruptionsToday }

    /// Everything the app put in front of somebody, whether or not it cost them a unit of the
    /// day: questions plus every rung, ambient ones included.
    public var deliveredNudgeCount: Int { queryCount + accusationCount }

    /// One line per step, in order. Printed on a failure, so a reviewer reads what the day
    /// actually was rather than which assertion tripped.
    public var text: String { records.map(\.line).joined(separator: "\n") }

    public var digest: UInt64 { FNV1a.hash(text) }
}

/// How a replayed day differed from what the fixture claimed.
public struct DayMismatch: Sendable, Equatable {
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

/// **Replay a working day** through the whole decider, ledger and fatigue controller (T143c).
///
/// The same `NudgeWorld` every other lane uses, with one difference that is the entire point:
/// `enforcesFatigue` is **on**, so the caps, the cooldowns, the reserved unit and the backoffs all
/// bind. A corpus of 165 independent claims cannot see a bad day; this can.
///
/// ## What survives what
///
/// Three lifetimes run through a day and confusing them is how a cap becomes fiction:
///
/// * a **relaunch** keeps the day's counts and every receipt, and clears the ladder, the slot, the
///   snoozes and the backoffs — a cap somebody could clear by quitting is not a cap, and a backoff
///   that survived a relaunch would have outlived the situation it was for;
/// * a **priority change** starts a new segment with a new priority identity, so every question
///   legitimately re-opens: a new commitment makes old answers irrelevant;
/// * a **day boundary** empties the budget and keeps the receipts, because a question answered
///   yesterday is still answered.
///
/// The engine is rebuilt at each segment, because e04 invalidates the rule snapshot on a priority
/// change and a drift accumulator carried across two commitments would be counting drift away from
/// a task the person is no longer doing.
public struct DayReplayHarness: Sendable {
    public let runner: CorpusRunner

    public init(runner: CorpusRunner) {
        self.runner = runner
    }

    public func replay(_ fixture: DayFixture) -> DayTranscript {
        var clock = TestClock()
        var world = NudgeWorld(enforcesFatigue: true)
        var records: [SequenceObservationRecord] = []
        var queriesByPriority: [UUID: Int] = [:]
        var index = 0

        for segment in fixture.segments {
            let priorityID = CorpusRunner.priorityID(for: segment.priority)
            let decidable = DecidableSubjects(
                contextPack: segment.contextPack, rules: segment.rules
            )
            var learned: [CorpusRule] = []
            var snapshot = self.snapshot(for: segment, id: fixture.id, learned: learned)
            let engine = DeterministicRelevanceEngine(
                normalizer: runner.normalizer, scorer: runner.scorer
            )
            if index > 0 { world.changePriority(now: clock.elapsed) }

            var currentSubject: String??
            var subjectSince = clock.elapsed

            for step in segment.steps {
                clock.advance(by: .seconds(step.advanceSeconds))
                let now = clock.elapsed

                if currentSubject == nil || currentSubject! != step.subject {
                    currentSubject = step.subject
                    subjectSince = now
                }
                let dwell = step.dwellSeconds.map { Duration.seconds($0) } ?? (now - subjectSince)

                let judgement = engine.judge(
                    input: ClassificationInput(
                        priorityIntent: segment.priority?.intent ?? "",
                        priorityDoneWhen: segment.priority?.doneWhen,
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

                let before = world.deliveredQueries.count
                let observation = world.decide(
                    NudgeJudgement(
                        outcome: judgement.outcome,
                        uncertainty: judgement.uncertaintyReason,
                        subject: step.subject,
                        dwelled: dwell,
                        snapshot: judgement.verdictSnapshot(
                            stampKey: EngineStamp.current.cacheKey
                        ),
                        stamp: EngineStamp.current
                    ),
                    surroundings: NudgeLane.surroundings(
                        subject: step.subject,
                        hasActivePriority: segment.priority != nil,
                        phase: step.sessionPhase,
                        isUserIdle: step.isUserIdle,
                        presentation: step.isPresenting,
                        menuBarVisible: step.menuBarVisible,
                        monotonic: now
                    ),
                    priorityID: priorityID,
                    decidable: decidable
                )
                if world.deliveredQueries.count > before, let priorityID {
                    queriesByPriority[priorityID, default: 0] += 1
                }

                var actions: [String] = []
                if let answer = step.then.answer {
                    world.resolveQuery(answer, now: now)
                    actions.append("answer=\(answer.rawValue)")
                    if let verdict = answer.ruleVerdict,
                       let subject = observation.decision.warrant?.subject {
                        learned.append(
                            CorpusRule(
                                authority: .task,
                                subjectKind: subject.kind,
                                subject: subject.identifier,
                                verdict: verdict
                            )
                        )
                        snapshot = self.snapshot(for: segment, id: fixture.id, learned: learned)
                    }
                }
                if let outcome = step.then.accusationOutcome {
                    world.resolveAccusation(outcome, now: now)
                    actions.append("rung=\(outcome.rawValue)")
                }
                if let subject = step.then.deleteLearnedRule {
                    learned.removeAll { $0.subject == subject }
                    snapshot = self.snapshot(for: segment, id: fixture.id, learned: learned)
                    actions.append("deleted=\(subject)")
                }
                if step.then.newDay {
                    world.startNewDay()
                    actions.append("newDay")
                }
                if step.then.relaunch {
                    world.relaunch()
                    actions.append("relaunch")
                }

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
                        driftName: SequenceReplayHarness.name(of: judgement.drift),
                        accumulatedSeconds: Int(judgement.drift.accumulated.components.seconds),
                        eligibility: judgement.eligibility.isMandated
                            ? .mandated
                            : .suppressed(
                                judgement.eligibility.suppressionReason ?? .verdictUncertain
                            ),
                        clauses: judgement.explanation.clauseKinds,
                        isMixed: judgement.drift.isMixed,
                        nudge: observation.expectation,
                        action: actions.isEmpty ? "-" : actions.joined(separator: ",")
                    )
                )
                index += 1
            }
        }

        return DayTranscript(
            id: fixture.id,
            records: records,
            queryCount: world.deliveredQueries.count,
            accusationCount: world.deliveredAccusations,
            queriesForBusiestPriority: queriesByPriority.values.max() ?? 0,
            world: world
        )
    }

    /// Compare a replayed day to what the fixture claimed.
    public func compare(_ fixture: DayFixture, to transcript: DayTranscript) -> DayMismatch? {
        var differences: [String] = []

        if transcript.queryCount != fixture.expectQueries {
            differences.append("questions \(transcript.queryCount) ≠ \(fixture.expectQueries)")
        }
        if transcript.accusationCount != fixture.expectAccusations {
            differences.append("rungs \(transcript.accusationCount) ≠ \(fixture.expectAccusations)")
        }
        if transcript.interruptionCount != fixture.expectInterruptions {
            differences.append(
                "interruptions \(transcript.interruptionCount) ≠ \(fixture.expectInterruptions)"
            )
        }
        if transcript.world.repeatQueries != 0 {
            differences.append("asked \(transcript.world.repeatQueries) question(s) twice")
        }
        // A day fixture may not commit a day the shipped caps forbid. The decoder checks the
        // *claim*; this checks what the run actually did, which is the half that would catch a cap
        // that had quietly stopped binding.
        if transcript.queryCount > InterventionPolicy.dailyQueryCapAllPriorities {
            differences.append(
                "delivered \(transcript.queryCount) questions, above dailyQueryCapAllPriorities "
                    + "(\(InterventionPolicy.dailyQueryCapAllPriorities))"
            )
        }
        if transcript.interruptionCount > InterventionPolicy.dailyInterruptionCap {
            differences.append(
                "delivered \(transcript.interruptionCount) interruptions, above "
                    + "dailyInterruptionCap (\(InterventionPolicy.dailyInterruptionCap))"
            )
        }
        if transcript.queriesForBusiestPriority > InterventionPolicy.dailyQueryCap {
            differences.append(
                "one priority took \(transcript.queriesForBusiestPriority) questions, above "
                    + "dailyQueryCap (\(InterventionPolicy.dailyQueryCap))"
            )
        }

        for (record, step) in zip(transcript.records, fixture.segments.flatMap(\.steps)) {
            let at = "step \(record.index) at \(record.nowSeconds)s"
            if record.verdict != step.expect.verdict {
                differences.append(
                    "\(at): verdict \(record.verdict.rawValue) ≠ \(step.expect.verdict.rawValue)"
                )
            }
            if let nudge = step.expect.nudge, record.nudge != nudge {
                differences.append("\(at): nudge \(record.nudge.encoded) ≠ \(nudge.encoded)")
            }
        }

        guard !differences.isEmpty else { return nil }
        return DayMismatch(
            id: fixture.id,
            note: fixture.note,
            differences: differences,
            transcript: transcript.text
        )
    }

    /// A segment's snapshot, built by the same builder every other lane uses.
    private func snapshot(
        for segment: DaySegment,
        id: String,
        learned: [CorpusRule]
    ) -> RuleSnapshot {
        runner.snapshot(
            for: CorpusCase(
                id: id,
                note: "day segment",
                families: [],
                isNegativeControl: false,
                priority: segment.priority,
                contextPack: segment.contextPack,
                rules: segment.rules + learned,
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
                expectNudge: .silent(.verdictDoesNotAuthorise),
                queryGroundTruth: nil,
                expectExplanationTokens: nil,
                file: "days"
            )
        )
    }
}
