import FocusCore
import Foundation
import Testing

@testable import FocusClassify

/// **Which answers rank 6 may review, enumerated rather than declared.**
///
/// The assertion that matters is not *"the source marks two answers reviewable"* — that is a
/// grep. It is *"running the engine over every shape of input the corpus knows produces
/// reviewable answers at exactly two reasons, and never for a subject §2.3 forbids"*. A third
/// reviewable answer added without a ruling fails this suite; so does a reviewable answer that
/// names a reviewer other than the model; so does one about a browser.
@Suite("Rung finality")
struct RungFinalityTests {
    static let reference = Date(timeIntervalSince1970: 1_767_225_600)
    static let priorityID = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

    let normalizer = TokenNormalizer()

    /// A spread of priorities and subjects wide enough to reach every route through the
    /// heuristic: English and not, judgeable and not, seeded and not, with and without a basis,
    /// on both sides of every dwell threshold.
    static let priorities = [
        "write the q3 proposal for acme",
        "close the bergman audit",
        "stuff",
        "",
        "四半期の提案書を書く",
        "rédiger la proposition du troisième trimestre"
    ]

    static let subjects: [String?] = [
        "com.microsoft.Excel", "com.apple.Pages", "com.apple.dt.Xcode",
        "com.apple.Safari", "com.apple.Terminal", "com.apple.Music",
        "com.acme.unknown", nil
    ]

    static let packs: [[ContextItemValue]] = [
        [],
        [.app(bundleID: "com.microsoft.Excel", displayName: "Excel", addedAt: reference)],
        [.keyword("acme", addedAt: reference)!],
        [.domain(origin: "https://docs.google.com", addedAt: reference)!]
    ]

    func snapshot(intent: String, pack: [ContextItemValue]) -> RuleSnapshot {
        RuleSnapshotBuilder(normalizer: normalizer).build(
            priority: PriorityInput(id: Self.priorityID, revision: 1, intent: intent),
            contextPack: pack
        )
    }

    func evidence(_ bundleID: String?, dwell: Int) -> ClassificationEvidence {
        ClassificationEvidence.make(
            input: ClassificationInput(bundleIdentifier: bundleID, origin: nil, titleTokens: []),
            dwell: .seconds(dwell),
            normalizer: normalizer
        )
    }

    /// Every `(priority, subject, pack, dwell)` the fold above can make, with the answer the
    /// heuristic gave and the subject it was about.
    func sweep() -> [(answer: RungAnswer, subject: String?)] {
        var collected: [(RungAnswer, String?)] = []
        let classifier = HeuristicClassifier()
        for intent in Self.priorities {
            for pack in Self.packs {
                let snap = snapshot(intent: intent, pack: pack)
                for subject in Self.subjects {
                    for dwell in [0, 44, 45, 89, 90, 91, 400, 7_200] {
                        if let answer = classifier.judge(
                            evidence: evidence(subject, dwell: dwell), snapshot: snap
                        ) {
                            collected.append((answer, subject))
                        }
                    }
                }
            }
        }
        return collected
    }

    @Test("the reviewable set is exactly the two instrument-exhaustion reasons")
    func reviewableSetIsExactlyTwo() {
        let reviewable = sweep().filter { $0.answer.finality != .decided }
        #expect(!reviewable.isEmpty, "a sweep that reviewed nothing proves nothing")

        let reasons = Set(reviewable.compactMap { $0.answer.uncertaintyReason })
        #expect(reasons == [.noNegativeBasis, .languageNotSupported])
    }

    @Test("every reviewable answer names the model and nothing else")
    func theOnlyReviewerIsTheModel() {
        for (answer, _) in sweep() where answer.finality != .decided {
            #expect(answer.finality == .reviewable(by: .onDeviceModel))
        }
    }

    @Test("no reviewable answer is about a mixed-use subject (§2.3)")
    func noReviewableAnswerIsAboutABrowser() {
        let mixedUse = Set(RelevanceSeed.fallbackSeeds.keys)
        for (answer, subject) in sweep() where answer.finality != .decided {
            guard let subject else { continue }
            #expect(
                !mixedUse.contains(subject),
                "\(subject) is a seeded mixed-use subject and may never reach the model"
            )
        }
    }

    @Test("no answer that DECIDES is reviewable — a decision is not an admission")
    func decisionsAreNotReviewable() {
        for (answer, _) in sweep() {
            if answer.verdict != .uncertain {
                #expect(answer.finality == .decided, "a \(answer.verdict) answer was reviewable")
            }
            // And the three uncertainties that really are decisions or dead ends.
            if let reason = answer.uncertaintyReason,
               [.mixedUseApplication, .insufficientPriorityEvidence, .noEvidence,
                .conflictingRules, .staleSnapshot, .noIdentifiableSubject].contains(reason) {
                #expect(answer.finality == .decided, "\(reason) is a decision, not an admission")
            }
        }
    }

    @Test("with the deterministic ladder a reviewable answer stands, unchanged")
    func theDeterministicLadderIsUntouched() {
        // No port, `.deterministic` ladder — which is what every shipping composition gets.
        let cascade = RuleCascade(heuristic: HeuristicClassifier())
        let resolution = cascade.evaluate(
            evidence: evidence("com.microsoft.Excel", dwell: 400),
            snapshot: snapshot(intent: "write the q3 proposal for acme", pack: [])
        )
        #expect(resolution.stage == .heuristic)
        #expect(resolution.uncertaintyReason == .noNegativeBasis)
        #expect(resolution.consultedDepth <= CascadeLadder.deterministic.executableRungs.count)
    }
}

/// The composed ladder itself.
@Suite("Cascade ladder")
struct CascadeLadderTests {
    @Test("the deterministic ladder is what CascadePrecedence declares, rung for rung")
    func deterministicMatchesTheDeclaration() {
        #expect(CascadeLadder.deterministic.rungs == CascadePrecedence.rungs)
        #expect(CascadeLadder.deterministic.executableRungs == CascadePrecedence.executableRungs)
        #expect(CascadeLadder.deterministic.executableRungs.count == 8)
    }

    @Test("composing a model adds exactly one rung and moves no rank")
    func modelAddsOneRung() {
        let composed = CascadeLadder(modelAvailable: true)
        #expect(composed.rungs.count == CascadeLadder.deterministic.rungs.count)
        #expect(composed.executableRungs.count == 9)

        let difference = zip(composed.rungs, CascadeLadder.deterministic.rungs)
            .filter { $0 != $1 }
        #expect(difference.count == 1)
        #expect(difference.first?.0.stage == .onDeviceModel)

        // Rank order, both ways, with no gaps.
        for ladder in [CascadeLadder.deterministic, composed] {
            #expect(ladder.rungs.map(\.rank) == Array(0..<CascadeStage.allCases.count))
            #expect(ladder.executableRungs.map(\.rank) == ladder.executableRungs.map(\.rank).sorted())
        }
    }

    @Test("only a composed ladder can execute the model rung")
    func canExecuteIsAPropertyOfTheComposition() {
        #expect(!CascadeLadder.deterministic.canExecute(.onDeviceModel))
        #expect(CascadeLadder(modelAvailable: true).canExecute(.onDeviceModel))
        for stage in CascadeStage.allCases where stage != .onDeviceModel {
            #expect(CascadeLadder.deterministic.canExecute(stage))
            #expect(CascadeLadder(modelAvailable: true).canExecute(stage))
        }
    }
}

/// The reviewed answer, driven by a stub port — so the branch is exercised without a model.
@Suite("Rank 6, reviewed")
struct ModelReviewTests {
    struct StubModel: ModelRung {
        let answer: ModelAnswer?
        var promptVersion: Int { 1 }
        func cachedAnswer(for request: ModelRequest) -> ModelAnswer? { answer }
        func request(_ request: ModelRequest) {}
        func invalidate(subject: String) {}
        func reset() {}
    }

    static let priorityID = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!
    let normalizer = TokenNormalizer()

    func resolve(_ model: StubModel, ladder: CascadeLadder = CascadeLadder(modelAvailable: true))
        -> CascadeResolution
    {
        let snapshot = RuleSnapshotBuilder(normalizer: normalizer).build(
            priority: PriorityInput(
                id: Self.priorityID, revision: 1, intent: "write the q3 proposal for acme"
            ),
            contextPack: []
        )
        return RuleCascade(heuristic: HeuristicClassifier(), model: model, ladder: ladder)
            .evaluate(
                evidence: ClassificationEvidence.make(
                    input: ClassificationInput(
                        bundleIdentifier: "com.microsoft.Excel", origin: nil, titleTokens: []
                    ),
                    dwell: .seconds(400),
                    normalizer: normalizer
                ),
                snapshot: snapshot
            )
    }

    @Test("a cached rescue answers at rank 6, relevant, banded low")
    func aRescueAnswersAtRankSix() {
        let resolution = resolve(StubModel(answer: .relevant(.direct)))
        #expect(resolution.stage == .onDeviceModel)
        #expect(resolution.verdict == .relevant)
        #expect(resolution.band == .low)
        #expect(resolution.clauses.map(\.kind) == [.modelDirect])
        #expect(resolution.consultedDepth == 7)
    }

    @Test("a supporting rescue draws the other clause")
    func aSupportingRescueDrawsItsOwnClause() {
        let resolution = resolve(StubModel(answer: .relevant(.supporting)))
        #expect(resolution.clauses.map(\.kind) == [.modelSupporting])
    }

    @Test("every decline leaves the deterministic answer exactly where it was")
    func aDeclineChangesNothing() {
        let deterministic = resolve(StubModel(answer: nil), ladder: .deterministic)
        for reason in ModelDeclineReason.allCases {
            let reviewed = resolve(StubModel(answer: .decline(reason)))
            #expect(reviewed.stage == deterministic.stage, "\(reason)")
            #expect(reviewed.verdict == deterministic.verdict, "\(reason)")
            #expect(reviewed.uncertaintyReason == deterministic.uncertaintyReason, "\(reason)")
            #expect(reviewed.clauses == deterministic.clauses, "\(reason)")
        }
    }

    @Test("a cache miss leaves the deterministic answer standing")
    func aMissChangesNothing() {
        let deterministic = resolve(StubModel(answer: nil), ladder: .deterministic)
        let reviewed = resolve(StubModel(answer: nil))
        #expect(reviewed.stage == deterministic.stage)
        #expect(reviewed.uncertaintyReason == deterministic.uncertaintyReason)
    }

    @Test("a rescue the ladder cannot execute is not a rescue")
    func anUncomposedLadderIgnoresThePort() {
        // The port is present and answering; the ladder is `.deterministic`. Rank 6 is not in
        // the sequence, so nothing consults it — which is the build fact R-100 asks for.
        let resolution = resolve(StubModel(answer: .relevant(.direct)), ladder: .deterministic)
        #expect(resolution.stage == .heuristic)
        #expect(resolution.verdict == .uncertain)
    }

    @Test("no model answer can reach unrelated, over the whole answer space")
    func noModelAnswerAccuses() {
        var space: [ModelAnswer] = ModelRelevance.allCases.map(ModelAnswer.relevant)
        space += ModelDeclineReason.allCases.map(ModelAnswer.decline)
        for answer in space {
            let resolution = resolve(StubModel(answer: answer))
            #expect(resolution.verdict != .unrelated, "\(answer)")
        }
    }
}
