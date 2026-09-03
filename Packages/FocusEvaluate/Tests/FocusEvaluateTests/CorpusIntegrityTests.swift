import FocusCore
import FocusEvaluateCore
import Foundation
import Testing

@testable import FocusClassify

/// The corpus's own properties — the ones that must hold before a single expectation is
/// evaluated (R-66).
///
/// A golden corpus rots in three ways and this suite closes all three. It rots by **shrinking**,
/// which the per-file floors catch. It rots by **renumbering**, which the uniqueness and witness
/// assertions catch — several of these ids are named in `RelevancePolicy.manifest` as mutation
/// witnesses, so a case renamed is a witness lost. And it rots by **silence**: a fixture nobody
/// can explain is a fixture nobody can maintain, and the first person to "fix" it will delete
/// the bug it was catching, so every case carries a non-empty note and this suite fails without
/// one.
@Suite("Golden corpus integrity")
struct CorpusIntegrityTests {
    // MARK: - It loads at all

    /// Strict decoding is the assertion, not a convenience: an unknown key, an unparseable
    /// enumeration or a missing expectation fails the *load*. A corpus that silently accepted a
    /// malformed case would silently stop testing something, and nothing downstream could tell.
    @Test("the committed corpus loads, strictly")
    func theCorpusLoads() throws {
        let corpus = try CorpusFixtures.loaded()
        #expect(!corpus.cases.isEmpty)
        for file in corpus.files {
            #expect(!file.note.isEmpty, "\(file.name).json does not say what it is for")
        }
    }

    // MARK: - The budget, file by file (R-74.3)

    /// Each floor separately, and that is the point. A single total would catch a corpus that
    /// shrank and miss one that was rebalanced towards its easy end — thirty extra baseline
    /// cases standing in for the thirty-three adversarial ones.
    @Test("every committed file meets its own floor")
    func everyFileMeetsItsFloor() throws {
        let corpus = try CorpusFixtures.loaded()
        for budget in EvaluationPolicy.budgets {
            guard let file = corpus.file(named: budget.file) else {
                Issue.record("\(budget.file).json is committed in the budget but was not loaded")
                continue
            }
            let detail = "\(budget.file).json holds \(file.cases.count) cases, "
                + "floor \(budget.floor) (\(budget.covers))"
            #expect(file.cases.count >= budget.floor, "\(detail)")
        }
    }

    /// The total is a **consequence** of the per-file budget rather than a round number chosen
    /// first — which is what stops somebody meeting it by adding easy cases to whichever file is
    /// cheapest. e05 adds the third term: the realistic-day fixtures, on which
    /// `queriesPerFocusDay` and `interruptionsPerFocusDayMax` are the only metrics that can see a
    /// bad day (R-94a).
    @Test("the per-file floors add up to the committed total")
    func theBudgetAddsUp() {
        let fromFiles = EvaluationPolicy.budgets.reduce(0) { $0 + $1.floor }
        #expect(
            fromFiles + EvaluationPolicy.sequenceFloor + EvaluationPolicy.dayFloor
                == EvaluationPolicy.corpusFloor
        )
        #expect(EvaluationPolicy.corpusFloor >= 132, "R-74.3 commits the floor at 132")
    }

    // MARK: - Every case can explain itself

    @Test("every case carries a non-empty note")
    func everyCaseIsExplained() throws {
        for testCase in try CorpusFixtures.loaded().cases {
            #expect(
                !testCase.note.trimmingCharacters(in: .whitespaces).isEmpty,
                "\(testCase.id) carries no note"
            )
        }
    }

    @Test("ids are unique, stable and well formed")
    func idsAreUniqueAndStable() throws {
        let cases = try CorpusFixtures.loaded().cases
        let ids = cases.map(\.id)
        #expect(Set(ids).count == ids.count, "a case id is used twice")
        for id in ids {
            #expect(id.hasPrefix("gc-"), "\(id) is not a corpus case id")
        }
    }

    // MARK: - The expectation is total

    /// An `uncertain` verdict has no evidence to band, and a decided one always does. Asserting
    /// this over the corpus rather than only in the decoder is what stops a future file being
    /// loaded by a different route and slipping past.
    @Test("a band is recorded exactly when the verdict decides something")
    func bandsAccompanyDecisionsOnly() throws {
        for testCase in try CorpusFixtures.loaded().cases {
            if testCase.expect.verdict == .uncertain {
                #expect(testCase.expect.band == nil, "\(testCase.id) bands an uncertain verdict")
                #expect(
                    testCase.expect.uncertaintyReason != nil,
                    "\(testCase.id) declines without naming a reason"
                )
            } else {
                #expect(testCase.expect.band != nil, "\(testCase.id) decides without a band")
                #expect(testCase.expect.uncertaintyReason == nil)
            }
        }
    }

    /// Every expectation names at least one clause. An explanation that is empty is a judgement
    /// a person cannot check, and `ExplanationBuilder` guarantees it never happens — this is the
    /// corpus asserting the same thing from the outside.
    @Test("every case expects at least one explanation clause")
    func everyCaseExpectsAtLeastOneClause() throws {
        for testCase in try CorpusFixtures.loaded().cases {
            #expect(!testCase.expect.clauses.isEmpty, "\(testCase.id) expects no explanation")
        }
    }

    /// **Standing condition 6, read off the corpus.** Whatever its band, its dwell, its rung or
    /// its session phase, an `uncertain` case suppresses — and by exactly one route.
    @Test("every uncertain expectation suppresses, by the verdict route")
    func uncertainAlwaysSuppresses() throws {
        for testCase in try CorpusFixtures.loaded().cases
        where testCase.expect.verdict == .uncertain {
            #expect(
                testCase.expect.eligibility == .suppressed(.verdictUncertain),
                "\(testCase.id) is uncertain but expects \(testCase.expect.eligibility.encoded)"
            )
        }
    }

    /// A mandate needs all seven guards, and `.unrelated` is the first of them. This is the
    /// corpus's own statement of the invariant `InterventionInvariantTests` proves over the
    /// 4 320-combination cross-product.
    @Test("only an unrelated expectation ever mandates")
    func onlyUnrelatedMandates() throws {
        for testCase in try CorpusFixtures.loaded().cases
        where testCase.expect.eligibility == .mandated {
            #expect(testCase.expect.verdict == .unrelated, "\(testCase.id) mandates on a non-unrelated verdict")
            #expect(
                (testCase.expect.band ?? .low) >= RelevancePolicy.interventionBandFloor,
                "\(testCase.id) mandates below the intervention band floor"
            )
            #expect(testCase.sessionPhase == .focus, "\(testCase.id) mandates outside focus")
            #expect(!testCase.isUserIdle, "\(testCase.id) mandates while the person is away")
        }
    }

    // MARK: - Every case is exercised, and its FULL expectation asserted

    /// R-66 rule 6. Asserting the verdict alone would let a case pass for the wrong reason: a
    /// case that reaches the right answer by the wrong rung stops catching its bug the next time
    /// somebody touches the ladder. So verdict, source, rung, band, eligibility, the clause set,
    /// the uncertainty reason and `skippedRuleCount` are all compared.
    @Test("every committed case produces exactly what it promised")
    func everyCaseIsExercised() throws {
        let corpus = try CorpusFixtures.loaded()
        let runner = CorpusFixtures.runner
        var mismatches: [CorpusMismatch] = []

        for testCase in corpus.cases {
            if let mismatch = runner.compare(testCase, to: runner.run(testCase)) {
                mismatches.append(mismatch)
            }
        }

        #expect(
            mismatches.isEmpty,
            """
            \(mismatches.count) of \(corpus.cases.count) corpus cases did not match:
            \(mismatches.map(\.description).joined(separator: "\n"))
            """
        )
    }

    /// R-54's third length. Never `0`, because `unresolved` is itself a rung and always
    /// answers; never `9`, because `onDeviceModel` is not in the sequence `RuleCascade` walks —
    /// which is measured here rather than assumed.
    @Test("no case consults a depth outside 1…8, and none reaches the model")
    func consultedDepthStaysInRange() throws {
        let runner = CorpusFixtures.runner
        for testCase in try CorpusFixtures.loaded().cases {
            let outcome = runner.run(testCase)
            #expect(
                (1...CascadePrecedence.executableRungs.count).contains(outcome.consultedDepth),
                "\(testCase.id) consulted \(outcome.consultedDepth) rungs"
            )
            #expect(outcome.stage != .onDeviceModel, "\(testCase.id) reached e06's rung")
        }
    }

    // MARK: - The corpus digest

    /// R-75.5's instrument. The digest must be a pure function of the committed bytes: two
    /// loads of the same tree agree, and it is FNV-1a rather than `Hasher`, which P-118
    /// measured returning a different value in every process.
    @Test("the corpus digest is stable across loads")
    func theCorpusDigestIsStable() throws {
        let first = try CorpusLoader.load(directory: CorpusFixtures.directory)
        let second = try CorpusLoader.digest(directory: CorpusFixtures.directory)
        #expect(first.digest == second)
        #expect(first.digest != 0)
    }

    // MARK: - Strictness, proved rather than claimed

    @Test("an unknown key fails the load rather than defaulting")
    func anUnknownKeyIsRefused() throws {
        let malformed = Data(
            """
            { "file": "baseline", "note": "n", "cases": [ { "id": "gc-9999", "note": "n",
              "dwellSecods": 5, "evidence": { "titleTokens": [] }, "dwellSeconds": 5,
              "sessionPhase": "focus", "isUserIdle": false,
              "expect": { "verdict": "uncertain", "source": "undecided", "stage": "unresolved",
                          "eligibility": "suppressed:verdictUncertain",
                          "clauses": ["insufficientEvidence"], "uncertaintyReason": "noEvidence" } } ] }
            """.utf8
        )
        let object = try StrictObject.parse(data: malformed, path: "malformed")
        #expect(throws: CorpusDecodingError.self) {
            _ = try object.objects("cases").map { try CorpusCase.decode($0, file: "baseline") }
        }
    }

    @Test("an unparseable enumeration fails the load")
    func anUnparseableEnumerationIsRefused() throws {
        let malformed = Data(
            """
            { "id": "gc-9999", "note": "n", "evidence": { "titleTokens": [] }, "dwellSeconds": 5,
              "sessionPhase": "focus", "isUserIdle": false,
              "expect": { "verdict": "irrelevant", "source": "undecided", "stage": "unresolved",
                          "eligibility": "suppressed:verdictUncertain",
                          "clauses": ["insufficientEvidence"] } }
            """.utf8
        )
        let object = try StrictObject.parse(data: malformed, path: "malformed")
        #expect(throws: CorpusDecodingError.self) {
            _ = try CorpusCase.decode(object, file: "baseline")
        }
    }

    @Test("a missing expectation fails the load")
    func aMissingExpectationIsRefused() throws {
        let malformed = Data(
            """
            { "id": "gc-9999", "note": "n", "evidence": { "titleTokens": [] }, "dwellSeconds": 5,
              "sessionPhase": "focus", "isUserIdle": false }
            """.utf8
        )
        let object = try StrictObject.parse(data: malformed, path: "malformed")
        #expect(throws: CorpusDecodingError.self) {
            _ = try CorpusCase.decode(object, file: "baseline")
        }
    }

    @Test("an empty note fails the load")
    func anEmptyNoteIsRefused() throws {
        let malformed = Data(
            """
            { "id": "gc-9999", "note": "  ", "evidence": { "titleTokens": [] }, "dwellSeconds": 5,
              "sessionPhase": "focus", "isUserIdle": false,
              "expect": { "verdict": "uncertain", "source": "undecided", "stage": "unresolved",
                          "eligibility": "suppressed:verdictUncertain",
                          "clauses": ["insufficientEvidence"], "uncertaintyReason": "noEvidence" } }
            """.utf8
        )
        let object = try StrictObject.parse(data: malformed, path: "malformed")
        #expect(throws: CorpusDecodingError.self) {
            _ = try CorpusCase.decode(object, file: "baseline")
        }
    }

    /// The declared family set is closed, and `CorpusLoader.validateIdentity` refuses a case
    /// naming anything outside it. A family name nobody declared is a family that meets no floor
    /// and is asserted by nothing, which is worse than an absent one because it looks like
    /// coverage.
    @Test("the eleven families are declared exactly once each")
    func theFamiliesAreDeclaredExactlyOnce() {
        let names = EvaluationPolicy.families.map(\.name)
        #expect(names.count == EvaluationPolicy.declaredFamilyCount)
        #expect(Set(names).count == names.count, "a family name is declared twice")
        for family in EvaluationPolicy.families {
            #expect(family.floor >= EvaluationPolicy.familyFloor, "\(family.name) is below the floor")
            #expect(!family.mechanism.isEmpty, "\(family.name) names no mechanism")
        }
        #expect(
            EvaluationPolicy.families
                .first { $0.name == EvaluationPolicy.productiveToolFamily }?.floor
                == EvaluationPolicy.productiveToolFamilyFloor
        )
    }
}
