import FocusClassify
import FocusCore
import Foundation
import Testing

@testable import FocusEvaluateCore

/// **The model corpus, checked as a corpus — before any model has looked at it.**
///
/// None of this runs a model, and that is deliberate: these are properties of the fixtures a
/// human wrote, and they have to hold on a Mac with Apple Intelligence off. R-113's real
/// question is not *"did it rescue?"* but *"is it rescuing for the reason you claim?"*, and the
/// cheapest way to look good is a rescue set that happens to differ from the hold set along
/// some other axis. Everything below exists to make that impossible.
@Suite("Model corpus grid")
struct GridCompletenessTests {
    static var corpus: ModelCorpus {
        get throws { try ModelCorpusLoader.load(goldenCorpusDirectory: CorpusFixtures.directory) }
    }

    @Test("both grids load, and a missing file is a failure rather than a smaller corpus")
    func bothGridsLoad() throws {
        let corpus = try Self.corpus
        #expect(corpus.files.map(\.name) == ["grid", "multilingual"])
        #expect(corpus.cellCount == EvaluationPolicy.modelCorpusFloor)
    }

    @Test("the grid is complete, fail-closed, on both axes")
    func gridIsComplete() throws {
        for file in try Self.corpus.files {
            #expect(file.missingCoordinates.isEmpty, "\(file.name): \(file.missingCoordinates)")
            #expect(file.completeness == 1.0, "\(file.name)")
        }
    }

    @Test("the 6x6 is six by six and the multilingual is three by three")
    func gridDimensions() throws {
        let corpus = try Self.corpus
        let grid = corpus.files[0]
        #expect(grid.rows.count == EvaluationPolicy.modelGridPriorities)
        #expect(grid.columns.count == EvaluationPolicy.modelGridSubjects)
        #expect(grid.cells.count == EvaluationPolicy.modelGridPriorities * EvaluationPolicy.modelGridSubjects)

        let multilingual = corpus.files[1]
        #expect(multilingual.rows.count == EvaluationPolicy.modelLanguageCount)
        #expect(multilingual.columns.count == EvaluationPolicy.modelLanguageSubjects)
    }

    @Test("every row and every column carries both a rescue and a hold")
    func bothAxesMove() throws {
        for file in try Self.corpus.files {
            #expect(
                file.axesWithoutBothExpectations.isEmpty,
                "\(file.name): \(file.axesWithoutBothExpectations)"
            )
        }
    }

    @Test("the committed floor is the sum of the two grids, not a round number")
    func floorIsDerived() throws {
        let corpus = try Self.corpus
        #expect(
            EvaluationPolicy.modelCorpusFloor
                == EvaluationPolicy.modelGridPriorities * EvaluationPolicy.modelGridSubjects
                    + EvaluationPolicy.modelLanguageCount * EvaluationPolicy.modelLanguageSubjects
        )
        #expect(corpus.rescueCount == EvaluationPolicy.modelRescuableCells)
        #expect(corpus.holdCount == corpus.cellCount - corpus.rescueCount)
        // The hold side is the mutation witness and it must not be a rump: a yes-to-everything
        // model scores 100 % recall and has to fail on a real majority of the grid.
        #expect(corpus.holdCount > corpus.rescueCount)
    }

    /// **Every cell must reach the route it claims to probe, in the shipped deterministic
    /// engine.** This is the assertion that stops the grid drifting into fiction: a cell that
    /// resolved somewhere else would be measuring the model against a case the model is never
    /// consulted on.
    @Test("every 6x6 cell is uncertain(noNegativeBasis) in lane 1, at rung 5")
    func everyGridCellReachesTheBasisRoute() throws {
        let corpus = try Self.corpus
        let runner = ModelCorpusRunner()
        for cell in corpus.files[0].cells {
            let resolution = runner.deterministic(cell)
            #expect(resolution.verdict == .uncertain, "\(cell.id)")
            #expect(resolution.stage == .heuristic, "\(cell.id)")
            #expect(resolution.uncertaintyReason == .noNegativeBasis, "\(cell.id)")
        }
    }

    @Test("every multilingual cell is uncertain(languageNotSupported) in lane 1")
    func everyMultilingualCellReachesTheLanguageRoute() throws {
        let corpus = try Self.corpus
        let runner = ModelCorpusRunner()
        for cell in corpus.files[1].cells {
            #expect(runner.deterministic(cell).uncertaintyReason == .languageNotSupported, "\(cell.id)")
        }
    }

    /// And the corollary, which is the one §2.3 cares about: every cell is **reviewable**, so
    /// the grid probes rank 6 and nothing else. A cell whose subject were a seeded mixed-use
    /// application would be `.decided` and the model would never see it.
    @Test("every cell is reviewable by the model, and none is about a mixed-use subject")
    func everyCellIsReviewable() throws {
        let mixedUse = Set(RelevanceSeed.fallbackSeeds.keys)
        let runner = ModelCorpusRunner()
        for cell in try Self.corpus.cells {
            let subject = cell.evidence.bundleIdentifier
            #expect(subject != nil, "\(cell.id)")
            #expect(!mixedUse.contains(subject ?? ""), "\(cell.id): \(subject ?? "")")
            #expect(runner.finality(cell) == .reviewable(by: .onDeviceModel), "\(cell.id)")
        }
    }

    /// A cell whose subject shares a token with its priority would answer `relevant` at rung 5
    /// step 1 and never reach the deferral at all. Asserted rather than eyeballed.
    @Test("no cell's subject shares a word with its priority")
    func noCellIsSolvedByOverlap() throws {
        let runner = ModelCorpusRunner()
        for cell in try Self.corpus.cells {
            #expect(runner.deterministic(cell).verdict != .relevant, "\(cell.id)")
        }
    }

    @Test("every cell id is unique and every cell carries a human note")
    func everyCellIsIdentifiedAndExplained() throws {
        let cells = try Self.corpus.cells
        #expect(Set(cells.map(\.id)).count == cells.count)
        for cell in cells {
            // R-113: every expectation must be justifiable from the case's own prose by a reader
            // who has never run the model. A cell with no prose cannot be.
            #expect(cell.note.count > 40, "\(cell.id)")
        }
    }

    @Test("the model corpus digest is its own, and moves nothing in lane 1")
    func theDigestIsSeparate() throws {
        let corpus = try Self.corpus
        #expect(corpus.digest != 0)
        // The deterministic digest is recomputed from the allow-list, which does not name
        // `Model/`. If this ever became equal, somebody had generalised `corpus_entries`.
        let deterministic = try CorpusLoader.digest(directory: CorpusFixtures.directory)
        #expect(corpus.digest != deterministic)
    }
}
