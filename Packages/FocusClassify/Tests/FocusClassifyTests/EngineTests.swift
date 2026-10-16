import FocusCore
import Foundation
import Testing

@testable import FocusClassify

/// The whole engine, assembled (F-03, F-42, F-44, F-46, F-47).
///
/// The pieces have their own suites; this one asserts the properties that only exist once they
/// are composed — that the ladder is walked to a depth in range, that the two refusals fire
/// before any rung is consulted, that a mandate can only come from the one route that produces
/// one, and that two constructions of the engine answer identically for identical input, which
/// is what makes a replayed corpus worth committing.
@Suite("Deterministic relevance engine")
struct EngineTests {
    static let reference = Date(timeIntervalSince1970: 1_767_225_600)
    static let priorityID = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

    let normalizer = TokenNormalizer()

    func snapshot(
        intent: String = "write the q3 proposal for acme",
        revision: Int = 1,
        contextPack: [ContextItemValue] = [],
        scorer: SimilarityScorer? = nil
    ) -> RuleSnapshot {
        RuleSnapshotBuilder(normalizer: normalizer, scorer: scorer).build(
            priority: PriorityInput(id: Self.priorityID, revision: revision, intent: intent),
            contextPack: contextPack
        )
    }

    /// A real application that carries **no** seeded opinion — so the only route to a verdict
    /// about it is the heuristic, which is where R-56.1 lives.
    static let distraction = "com.valvesoftware.steam"

    static func pages() -> ContextItemValue {
        .app(bundleID: "com.apple.Pages", displayName: "Pages", addedAt: reference)
    }

    func input(_ bundleID: String?, origin: String? = nil, titleTokens: [String] = []) -> ClassificationInput {
        ClassificationInput(
            priorityIntent: "write the q3 proposal for acme",
            bundleIdentifier: bundleID,
            origin: origin,
            titleTokens: titleTokens
        )
    }

    // MARK: - The seam

    /// e01's assertion, still true: the empty input yields `.undecided`, which suppresses.
    @Test("the empty input still yields undecided through the seam")
    func theEmptyInputIsUndecided() {
        let engine = DeterministicRelevanceEngine()
        let outcome = engine.classify(.empty)
        #expect(outcome.verdict == .uncertain)
        #expect(outcome.source == .undecided)
        #expect(outcome.band == .low)

        let asProtocol: any RelevanceClassifier = engine
        #expect(asProtocol.classify(.empty).verdict == .uncertain)
    }

    // MARK: - Depth

    /// R-54's third length: the **consulted** depth, `1…8`. Never `0`, because `unresolved` is
    /// itself a rung; never `9`, because the model is not in the sequence walked.
    @Test("every judgement reports a consulted depth in range, and never reaches the model")
    func depthIsAlwaysInRange() {
        let engine = DeterministicRelevanceEngine()
        engine.warmUp()

        let subjects = [
            "com.apple.Pages", "com.apple.ScreenContinuity", "com.apple.Safari",
            "com.microsoft.Excel", "com.example.Unknown", nil
        ]
        var clock = TestClock()

        for subject in subjects {
            for dwell in [0, 91, 400] {
                clock.advance(by: .seconds(dwell))
                let judgement = engine.judge(
                    input: input(subject),
                    snapshot: snapshot(contextPack: [Self.pages()]),
                    now: clock.elapsed,
                    dwell: .seconds(dwell)
                )
                #expect((1...CascadePrecedence.executableRungs.count)
                            .contains(judgement.consultedDepth))
                #expect(judgement.stage != .onDeviceModel)
            }
        }
    }

    // MARK: - The two refusals

    /// An edited priority is a different priority: every judgement about the old wording is
    /// stale, which is the corpus half of F-53's cache-key contract.
    @Test("a revision mismatch is refused rather than judged")
    func aRevisionMismatchIsRefused() {
        let engine = DeterministicRelevanceEngine()
        let judgement = engine.judge(
            input: input("com.apple.Pages"),
            snapshot: snapshot(revision: 3, contextPack: [Self.pages()]),
            evidenceRevision: 4,
            now: .seconds(0),
            dwell: .seconds(600)
        )

        #expect(judgement.verdict == .uncertain)
        #expect(judgement.uncertaintyReason == .staleSnapshot)
        #expect(judgement.eligibility == .suppressed(.verdictUncertain))
        #expect(judgement.stage == .unresolved)
    }

    /// A snapshot built under a different policy is refused: the thresholds that produced its
    /// tokens are not the ones about to be applied to them.
    @Test("a policy-digest mismatch is refused rather than judged")
    func aPolicyMismatchIsRefused() {
        let good = snapshot(contextPack: [Self.pages()])
        let stale = RuleSnapshot(
            priorityID: good.priorityID,
            priorityRevision: good.priorityRevision,
            priorityTokens: good.priorityTokens,
            prioritySentence: good.prioritySentence,
            priorityLanguage: good.priorityLanguage,
            rules: good.rules,
            skippedRuleCount: good.skippedRuleCount,
            contextPack: good.contextPack,
            policyDigest: good.policyDigest &+ 1,
            stamp: .current
        )

        let engine = DeterministicRelevanceEngine()
        let judgement = engine.judge(
            input: input("com.microsoft.Excel"),
            snapshot: stale,
            now: .seconds(0),
            dwell: .seconds(600)
        )
        #expect(judgement.uncertaintyReason == .staleSnapshot)
        #expect(!judgement.eligibility.isMandated)
    }

    /// A refusal is not an observation about the person, so it must not move a clock that is
    /// about their afternoon.
    @Test("a refusal does not touch the drift machine")
    func aRefusalDoesNotTouchTheClock() {
        let engine = DeterministicRelevanceEngine()
        var clock = TestClock()

        // Build a real drift first.
        _ = engine.judge(
            input: input("com.apple.Pages"), snapshot: snapshot(contextPack: [Self.pages()]),
            now: clock.elapsed, dwell: .zero
        )
        clock.advance(by: .seconds(30))
        let drifting = engine.judge(
            input: input("com.microsoft.Excel"), snapshot: snapshot(contextPack: [Self.pages()]),
            now: clock.elapsed, dwell: .seconds(30)
        )
        _ = drifting

        let before = engine.driftState
        clock.advance(by: .seconds(300))
        _ = engine.judge(
            input: input("com.microsoft.Excel"),
            snapshot: snapshot(revision: 3, contextPack: [Self.pages()]),
            evidenceRevision: 9,
            now: clock.elapsed,
            dwell: .seconds(300)
        )
        #expect(engine.driftState == before)
    }

    // MARK: - The mandate, end to end

    @Test("drift names the selected view or page, never its whole application",
          arguments: [false, true])
    func driftNamesSelectedContent(browser: Bool) throws {
        let bundle = browser ? "com.apple.Safari" : "com.github.githubapp"
        let item: SelectedItem
        if browser {
            let page = try #require(BrowserPage("https://example.com/holiday"))
            item = try #require(SelectedItem(
                bundleIdentifier: bundle, browserPage: page
            ))
        } else {
            item = try #require(SelectedItem(bundleIdentifier: bundle, label: "Holiday planning"))
        }
        let snapshot = RuleCascadeTests().snapshot(rules: [
            RuleCascadeTests.rule(.task, .app, bundle, .unrelated)
        ])
        let engine = DeterministicRelevanceEngine()
        let judgement = engine.judge(
            input: ClassificationInput(
                bundleIdentifier: bundle, origin: item.browserPage?.origin, selectedItem: item
            ),
            snapshot: snapshot, now: .zero, dwell: .seconds(120)
        )
        #expect(judgement.verdict == .unrelated)
        #expect(engine.driftState.subject?.identifier == item.subject)
    }

    /// The one route from a judgement to an authorisation, exercised through the whole engine:
    /// a well-specified priority, a named identity, a productive tool that is not it, and
    /// sustained drift past the threshold.
    @Test("sustained drift against a named basis mandates exactly once")
    func sustainedDriftMandatesOnce() {
        let engine = DeterministicRelevanceEngine()
        engine.warmUp()
        var clock = TestClock()
        let pack = [Self.pages()]

        func judge(_ bundleID: String, after seconds: Int, dwell: Int) -> Judgement {
            clock.advance(by: .seconds(seconds))
            return engine.judge(
                input: input(bundleID),
                snapshot: snapshot(contextPack: pack),
                now: clock.elapsed,
                dwell: .seconds(dwell)
            )
        }

        // The subject is deliberately **not** a seeded application. A browser, a chat client
        // or a media player carries an `ask each time` seed, and the heuristic declines to
        // accuse one on absence at all (R-56.1's principle applied to a subject whose identity
        // the app itself calls uninformative) — so a mandate against one is unreachable.
        //
        // Two clocks are in play here and they are not the same one. `dwell` is how long *this
        // subject* has been frontmost, which is what the heuristic reads to decide whether an
        // absence has lasted long enough to mean anything; the drift accumulator is how much
        // off-task time has built up *across* subjects, which is what the eligibility reads.
        // A mandate needs both, and the sequence below crosses them in that order.
        #expect(judge("com.apple.Pages", after: 0, dwell: 0).verdict == .relevant)

        // `unrelated` now — the subject has held long enough for its absence to mean
        // something — but the drift accumulator has only just opened, so the app is silent.
        let opened = judge(Self.distraction, after: 91, dwell: 91)
        #expect(opened.verdict == .unrelated)
        #expect(!opened.eligibility.isMandated)
        #expect(opened.eligibility.suppressionReason == .withinGracePeriod)

        // **And D-05's ruling is in force**: Pages held for ninety-one seconds before the
        // switch, which is a return anchor, so this is an anchored detour and the effective
        // threshold is 180 s rather than 90 s. Ninety further seconds is therefore still not a
        // mandate — the look-back made the app *less* likely to speak, which is the only
        // direction it is allowed to move in.
        let stillQuiet = judge(Self.distraction, after: 90, dwell: 181)
        #expect(stillQuiet.verdict == .unrelated)
        #expect(!stillQuiet.eligibility.isMandated)
        #expect(stillQuiet.eligibility.suppressionReason == .withinGracePeriod)

        // Ninety-one further seconds crosses the *extended* threshold.
        let mandated = judge(Self.distraction, after: 91, dwell: 272)
        #expect(mandated.verdict == .unrelated)
        #expect(mandated.eligibility.isMandated)
        if let mandate = mandated.eligibility.mandate {
            #expect(mandate.subject == Self.distraction)
            #expect(!mandate.isMixed)
            #expect(mandate.band >= RelevancePolicy.interventionBandFloor)
            #expect(!mandate.explanation.isEmpty)
            #expect(mandate.explanation.clauseKinds.contains(.sustainedDwell))
        } else {
            Issue.record("expected a mandate")
        }

        // …and not a second one inside the cooldown, however long the drift goes on.
        let quiet = judge(Self.distraction, after: 300, dwell: 572)
        #expect(!quiet.eligibility.isMandated)
        #expect(quiet.eligibility.suppressionReason == .withinMandateCooldown)
    }

    /// The mandate came from the heuristic's negative-basis route rather than from a bundled
    /// opinion, which is what makes the previous test an assertion about R-56.1 rather than
    /// about F-171's one seeded row.
    @Test("the mandate came from the heuristic, behind the negative basis")
    func theMandateCameFromTheHeuristic() {
        let engine = DeterministicRelevanceEngine()
        var clock = TestClock()
        _ = engine.judge(
            input: input("com.apple.Pages"), snapshot: snapshot(contextPack: [Self.pages()]),
            now: clock.elapsed, dwell: .zero
        )
        clock.advance(by: .seconds(91))
        _ = engine.judge(
            input: input(Self.distraction), snapshot: snapshot(contextPack: [Self.pages()]),
            now: clock.elapsed, dwell: .seconds(91)
        )
        clock.advance(by: .seconds(181))
        let judgement = engine.judge(
            input: input(Self.distraction), snapshot: snapshot(contextPack: [Self.pages()]),
            now: clock.elapsed, dwell: .seconds(272)
        )
        #expect(judgement.stage == .heuristic)
        #expect(judgement.eligibility.isMandated)

        // Remove the basis and the same sequence goes quiet — the whole of R-56.1, end to end.
        let bare = DeterministicRelevanceEngine()
        var bareClock = TestClock()
        _ = bare.judge(input: input("com.apple.Pages"), snapshot: snapshot(), now: bareClock.elapsed, dwell: .zero)
        bareClock.advance(by: .seconds(91))
        _ = bare.judge(
            input: input(Self.distraction), snapshot: snapshot(),
            now: bareClock.elapsed, dwell: .seconds(91)
        )
        bareClock.advance(by: .seconds(181))
        let declined = bare.judge(
            input: input(Self.distraction), snapshot: snapshot(),
            now: bareClock.elapsed, dwell: .seconds(272)
        )
        #expect(!declined.eligibility.isMandated)
        #expect(declined.verdict == .uncertain)
    }

    /// **Standing condition 6, through the whole engine.** Every `uncertain` judgement the
    /// engine can produce suppresses with the same reason, whatever its band, dwell, rung or
    /// phase.
    @Test("every uncertain judgement suppresses with the verdict reason")
    func everyUncertainSuppresses() {
        let engine = DeterministicRelevanceEngine()
        engine.warmUp()
        var clock = TestClock()
        var seen = 0

        for subject in ["com.apple.Safari", "com.microsoft.Excel", "com.example.Unknown", nil] {
            for dwell in [0, 91, 400, 3_600] {
                for phase in SessionPhase.allCases {
                    clock.advance(by: .seconds(dwell))
                    let judgement = engine.judge(
                        input: input(subject),
                        snapshot: snapshot(),
                        now: clock.elapsed,
                        dwell: .seconds(dwell),
                        phase: phase
                    )
                    guard judgement.verdict == .uncertain else { continue }
                    seen += 1
                    #expect(judgement.eligibility == .suppressed(.verdictUncertain))
                    #expect(judgement.eligibility.mandate == nil)
                }
            }
        }
        #expect(seen > 0, "no uncertain judgement was produced — the assertion is vacuous")
    }

    // MARK: - Determinism

    /// Two engines fed the same inputs answer identically, which is what makes a replayed
    /// corpus worth committing. P-118 established the determinism underneath it: the embedding
    /// is a pure function of its input on this OS revision.
    @Test("two constructions produce identical answers for identical input")
    func twoConstructionsAgree() {
        func run() -> [String] {
            let engine = DeterministicRelevanceEngine()
            engine.warmUp()
            var clock = TestClock()
            var transcript: [String] = []

            for (subject, seconds) in [
                ("com.apple.Pages", 0), ("com.google.Chrome", 60), ("com.google.Chrome", 60),
                ("com.hnc.Discord", 40), ("com.apple.Pages", 30), ("com.microsoft.Excel", 200)
            ] {
                clock.advance(by: .seconds(seconds))
                let judgement = engine.judge(
                    input: input(subject),
                    snapshot: snapshot(contextPack: [Self.pages()]),
                    now: clock.elapsed,
                    dwell: .seconds(seconds)
                )
                transcript.append(
                    """
                    \(judgement.verdict.rawValue)|\(judgement.stage.rawValue)\
                    |\(judgement.outcome.band.rawValue)|\(judgement.consultedDepth)\
                    |\(judgement.drift.accumulated)|\(judgement.eligibility.isMandated)\
                    |\(judgement.explanation.clauseKinds.map(\.rawValue).joined(separator: ","))
                    """
                )
            }
            return transcript
        }

        let first = run()
        let second = run()
        #expect(first == second)
        #expect(!first.isEmpty)
    }

    /// `reset()` forgets the clock, so a new session starts from nothing rather than from
    /// somebody else's afternoon.
    @Test("reset forgets the drift clock")
    func resetForgetsTheClock() {
        let engine = DeterministicRelevanceEngine()
        var clock = TestClock()
        _ = engine.judge(
            input: input("com.apple.Pages"), snapshot: snapshot(contextPack: [Self.pages()]),
            now: clock.elapsed, dwell: .zero
        )
        clock.advance(by: .seconds(200))
        _ = engine.judge(
            input: input("com.microsoft.Excel"), snapshot: snapshot(contextPack: [Self.pages()]),
            now: clock.elapsed, dwell: .seconds(200)
        )
        #expect(engine.driftState != .aligned)

        engine.reset()
        #expect(engine.driftState == .aligned)
    }

    // MARK: - The stamp

    /// The stamp carries the OS-supplied revision, and the cache key changes with it — which is
    /// what makes an Apple asset bump invalidate e06's cache automatically.
    @Test("the engine stamps itself with the runtime embedding revision")
    func theEngineStampsItself() {
        let engine = DeterministicRelevanceEngine()
        engine.warmUp()
        let stamp = engine.stamp

        #expect(stamp.policyVersion == EngineStamp.current.policyVersion)
        #expect(stamp.promptVersion == 0, "there is no model in this build")
        #expect(stamp.embeddingRevision > 0, "the sentence embedding was not loaded")
        #expect(stamp.cacheKey != EngineStamp.current.cacheKey)
    }

    /// The status a surface draws is the five-case one, and the two states a verdict cannot
    /// describe come from the session rather than from anything on screen.
    @Test("the status maps the verdict, with the session's two states overriding")
    func theStatusMapsTheVerdict() {
        #expect(DeterministicRelevanceEngine.status(for: .relevant, phase: .focus) == .relevant)
        #expect(DeterministicRelevanceEngine.status(for: .unrelated, phase: .focus) == .unrelated)
        #expect(DeterministicRelevanceEngine.status(for: .uncertain, phase: .focus) == .uncertain)
        #expect(DeterministicRelevanceEngine.status(for: .unrelated, phase: .onBreak) == .onBreak)
        #expect(DeterministicRelevanceEngine.status(for: .unrelated, phase: .paused) == .paused)
        #expect(DeterministicRelevanceEngine.status(for: .relevant, phase: .complete) == .paused)
    }

    /// The value the inspector draws, including the band that is deliberately absent when the
    /// engine declined.
    @Test("the render value hides the band when the verdict is uncertain")
    func theRenderValueHidesTheBandWhenUncertain() {
        let engine = DeterministicRelevanceEngine()
        let declined = engine.judge(
            input: input("com.example.Unknown"), snapshot: snapshot(),
            now: .zero, dwell: .seconds(600)
        )
        #expect(declined.verdictSnapshot(stampKey: engine.stamp.cacheKey).band == nil)

        let resolved = engine.judge(
            input: input("com.apple.Pages"), snapshot: snapshot(contextPack: [Self.pages()]),
            now: .seconds(1), dwell: .zero
        )
        #expect(resolved.verdictSnapshot(stampKey: engine.stamp.cacheKey).band == .high)
    }
}
