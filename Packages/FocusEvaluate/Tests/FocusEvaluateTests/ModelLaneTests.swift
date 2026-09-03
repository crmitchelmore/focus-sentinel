import FocusClassify
import FocusCore
import Foundation
import Testing

@testable import FocusEvaluateCore

/// **Lane 2's fold, its buckets and its thresholds — driven without a model.**
///
/// Every assertion here runs on a Mac with Apple Intelligence off, which is most Macs and is
/// exactly the condition under which a proof must still be able to fail. The system model
/// decides the *numbers*; it must never decide whether the machinery that reads them works.
@Suite("The model lane")
struct ModelLaneTests {
    /// A judge with one opinion, held for every request.
    struct FixedJudge: ModelLaneJudge {
        let answer: ModelAnswer
        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var cache: [String: ModelAnswer] = [:]
            var asked = 0
        }
        let box = Box()

        func prime(_ request: ModelRequest) -> ModelAnswer {
            box.lock.lock(); defer { box.lock.unlock() }
            box.cache[request.cacheKey] = answer
            box.asked += 1
            return answer
        }
        func cachedAnswer(for request: ModelRequest) -> ModelAnswer? {
            box.lock.lock(); defer { box.lock.unlock() }
            return box.cache[request.cacheKey]
        }
        func reset() {
            box.lock.lock(); defer { box.lock.unlock() }
            box.cache.removeAll()
        }
        var promptVersion: Int { 1 }
        var generationCount: Int {
            box.lock.lock(); defer { box.lock.unlock() }
            return box.asked
        }
    }

    /// The judge that answers correctly on every committed expectation. It is what a perfect
    /// tier would do, and it is what the floors were written against.
    struct OracleJudge: ModelLaneJudge {
        let rescueSubjects: Set<String>
        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var cache: [String: ModelAnswer] = [:]
        }
        let box = Box()

        func prime(_ request: ModelRequest) -> ModelAnswer {
            let answer: ModelAnswer =
                rescueSubjects.contains(request.cacheKey)
                    ? .relevant(.direct) : .decline(.modelSaidUnrelated)
            box.lock.lock(); defer { box.lock.unlock() }
            box.cache[request.cacheKey] = answer
            return answer
        }
        func cachedAnswer(for request: ModelRequest) -> ModelAnswer? {
            box.lock.lock(); defer { box.lock.unlock() }
            return box.cache[request.cacheKey]
        }
        func reset() {
            box.lock.lock(); defer { box.lock.unlock() }
            box.cache.removeAll()
        }
        var promptVersion: Int { 1 }
        var generationCount: Int { 0 }
    }

    static var corpus: ModelCorpus {
        get throws { try ModelCorpusLoader.load(goldenCorpusDirectory: CorpusFixtures.directory) }
    }

    static func report(judge: any ModelLaneJudge, repeats: Int = 1) throws -> ModelEvaluationReport {
        ModelEvaluationHarness(
            corpus: try corpus, judge: judge, runID: "unit", generatedAt: "unit", repeats: repeats
        ).run()
    }

    // MARK: - The mutation witness

    /// **A yes-to-everything model scores perfect recall and fails every hold cell.**
    ///
    /// This is the witness R-113 says the grid owes, and it is the reason the hold cells were
    /// written at all. A lane that could not produce this line would be a lane whose central
    /// number cannot fail.
    @Test("a yes-to-everything model scores 100 % recall and is seduced by every hold")
    func yesToEverythingIsSeducedByEveryHold() throws {
        let holds = try Self.corpus.holdCount
        let report = try Self.report(judge: FixedJudge(answer: .relevant(.direct)))
        #expect(report.rescueRecall == 1.0)
        #expect(report.seduced == holds)
        #expect(report.seduced > 0)
        #expect(!ModelEvaluationGate.qualityHolds(report))
        // …and the contract half is untouched by it. A seduction is a quality finding, not a
        // broken mechanism, which is exactly why the two halves are separate.
        #expect(ModelEvaluationGate.passes(report))
    }

    /// The other extreme: a model that declines everything is safe and useless. It seduces
    /// nobody and rescues nobody, and the recall floor is what says so.
    @Test("a no-to-everything model seduces nothing and rescues nothing")
    func noToEverythingIsSafeAndUseless() throws {
        let report = try Self.report(judge: FixedJudge(answer: .decline(.modelSaidUnrelated)))
        #expect(report.seduced == 0)
        #expect(report.rescueRecall == 0.0)
        let holds = try Self.corpus.holdCount
        #expect(report.buckets[ModelBucket.declined.rawValue] == holds)
        #expect(!ModelEvaluationGate.qualityHolds(report))
    }

    /// And the shape a passing tier would have, so the floors are known to be reachable rather
    /// than merely written down.
    @Test("a model that answers every committed expectation passes both halves")
    func anOracleTierPasses() throws {
        let corpus = try Self.corpus
        let runner = ModelCorpusRunner()
        let stamp = EngineStamp.current
        let rescueKeys = Set(
            corpus.cells
                .filter { $0.modelExpectation == .rescue }
                .compactMap { runner.request($0, stamp: stamp)?.cacheKey }
        )
        let report = try Self.report(judge: OracleJudge(rescueSubjects: rescueKeys), repeats: 2)
        #expect(report.seduced == 0)
        #expect(report.rescueRecall == 1.0)
        #expect(report.unstable.isEmpty)
        #expect(ModelEvaluationGate.passes(report))
        #expect(ModelEvaluationGate.qualityHolds(report))
    }

    // MARK: - The fold's own properties

    @Test("every cell lands in exactly one bucket, and they sum to the cell count")
    func theFoldIsTotal() throws {
        for judge: any ModelLaneJudge in [
            FixedJudge(answer: .relevant(.direct)),
            FixedJudge(answer: .relevant(.supporting)),
            FixedJudge(answer: .decline(.modelSaidUncertain)),
            FixedJudge(answer: .decline(.refused))
        ] {
            let report = try Self.report(judge: judge)
            #expect(report.bucketSum == report.cellCount)
            #expect(report.buckets.values.reduce(0, +) == report.cellCount)
            #expect(report.cases.count == report.cellCount)
        }
    }

    /// **§2.4, measured rather than argued.** Whatever the model says, no case's mandate moves
    /// and no case reaches `unrelated` — because `ModelAnswer` has no case that could.
    @Test("no model answer moves a mandate or reaches unrelated, over the whole answer space")
    func nothingCanAccuse() throws {
        var space: [ModelAnswer] = ModelRelevance.allCases.map(ModelAnswer.relevant)
        space += ModelDeclineReason.allCases.map(ModelAnswer.decline)
        for answer in space {
            let report = try Self.report(judge: FixedJudge(answer: answer))
            #expect(report.impossible == 0, "\(answer)")
            #expect(report.mandateParityMismatches == 0, "\(answer)")
            #expect(report.cases.allSatisfy { $0.modelVerdict != Verdict.unrelated.rawValue })
        }
    }

    /// **R-103.** The composed cascade is asked once before anything is primed, and the model
    /// must not answer there. A rung that answered on the first judgement would be a rung on the
    /// classification path.
    @Test("the model never answers on the first judgement of a subject")
    func neverAnswersOnTheFirstJudgement() throws {
        let report = try Self.report(judge: FixedJudge(answer: .relevant(.direct)))
        #expect(report.modelAnsweredOnFirstJudgement == 0)
        #expect(report.modelConsultationCount >= report.cellCount)
    }

    @Test("the composed ladder is nine rungs and the deterministic one is eight")
    func theComposedLadderIsNine() throws {
        let report = try Self.report(judge: FixedJudge(answer: .relevant(.direct)))
        #expect(report.executableRungs == EvaluationPolicy.declaredRungCount)
        #expect(CascadeLadder.deterministic.executableRungs.count
            == EvaluationPolicy.executableRungCeiling)
    }

    /// R-112's stability, checked on the mechanism: a judge that gives the same answer every
    /// time must produce identical bucket vectors, or the repeat comparison is not comparing
    /// what it claims to.
    @Test("a deterministic judge produces identical bucket vectors across repeats")
    func repeatsAgreeForADeterministicJudge() throws {
        let report = try Self.report(judge: FixedJudge(answer: .relevant(.supporting)), repeats: 3)
        #expect(report.repeatCount == 3)
        #expect(Set(report.bucketVectorDigests).count == 1)
        #expect(report.unstable.isEmpty)
    }

    // MARK: - The skip, as an outcome

    @Test("a skipped lane says so, carries its reason, and passes no quality half")
    func aSkipIsAnOutcome() {
        for state in ModelTierAvailability.allCases where state != .available {
            let report = ModelEvaluationReport.skipped(
                reason: state.rawValue, runID: "unit", generatedAt: "unit"
            )
            #expect(report.status == "skipped")
            #expect(report.reason == state.rawValue)
            // No checks at all on a skip: a lane that did not run produces no evidence, and an
            // empty check list is not a passing one — the stage prints SKIP rather than ok.
            #expect(ModelEvaluationGate.contractChecks(for: report).isEmpty)
            #expect(!ModelEvaluationGate.qualityHolds(report))
            #expect(report.executableRungs == CascadeLadder.deterministic.executableRungs.count)
        }
    }
}
