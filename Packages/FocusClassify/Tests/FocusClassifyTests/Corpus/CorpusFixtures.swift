import FocusClassify
import FocusEvaluateCore
import Foundation
import Testing

/// Where the committed corpus is, and one loaded copy of it.
///
/// `FocusEvaluateCore` reads a **directory**, never a bundle, because two processes need the
/// same bytes: the swift-testing suites reach the fixtures through the test bundle, and the
/// `FocusEvaluate` executable reaches them through the working tree. This is the test lane's
/// half of that — it turns `Bundle.module` into the directory URL the library asks for.
///
/// The resource is declared `.copy("Resources")` rather than `.process(…)` — e02's ruling, for
/// e02's reason: a directory of fixtures must reach the bundle with its subdirectory structure
/// intact, so `Resources/GoldenCorpus/sequences/*.json` resolves identically under `swift test`
/// and under `xcodebuild test`. `.process` would flatten it and the sequence fixtures would
/// vanish without a single test failing.
enum CorpusFixtures {
    static let resourcesDirectoryName = "Resources"

    /// The subdirectory the fixtures live in, as `Bundle` understands it.
    static let corpusSubdirectory =
        "\(resourcesDirectoryName)/\(CorpusLoader.goldenCorpusDirectoryName)"

    /// Resolved through `Bundle.url(forResource:withExtension:subdirectory:)` and **not** by
    /// appending path components to `bundleURL`.
    ///
    /// The difference is not cosmetic and it cost a red gate to find. Under `swift test` the
    /// resource bundle is flat, so `bundleURL/Resources/GoldenCorpus` resolves; under
    /// `xcodebuild test` the same bundle is a real macOS bundle and the fixtures sit under
    /// `Contents/Resources/Resources/GoldenCorpus`, so the hand-built path resolves to nothing.
    /// The failure was silent in the worst way: the loader records a missing file rather than
    /// throwing, so `AdversarialTests` and `SequenceReplayTests` iterated an empty corpus and
    /// several of them **passed**.
    ///
    /// Two things follow, and both are here rather than in a comment somewhere else. The lookup
    /// goes through the API that knows about both layouts — the same one `SimilarityCorpusTests`
    /// already uses for P-124's tables — and `loaded()` below refuses an incomplete corpus, so a
    /// resolution failure is loud in every suite instead of quiet in most of them.
    static var directory: URL {
        if let anchor = Bundle.module.url(
            forResource: EvaluationPolicy.budgets[0].file,
            withExtension: "json",
            subdirectory: corpusSubdirectory
        ) {
            return anchor.deletingLastPathComponent()
        }
        // Nothing resolved. Return the path the flat layout would have used so the loader's
        // error names a directory a person can go and look at.
        return (Bundle.module.resourceURL ?? Bundle.module.bundleURL)
            .appendingPathComponent(resourcesDirectoryName)
            .appendingPathComponent(CorpusLoader.goldenCorpusDirectoryName)
    }

    /// Loaded once, and **validated** once.
    ///
    /// Decoding 180-odd cases strictly is cheap, but the sentence-embedding warm-up behind the
    /// shared scorer is not (P-116 measured 59.4 ms cold), and a suite that paid it per test
    /// would be reporting the load rather than the engine.
    ///
    /// `validateComplete()` is called here rather than only in the metric gate, because an
    /// incomplete corpus must fail *everything* that reads it. A suite iterating zero cases is
    /// a suite that passes while testing nothing, which is the shape of failure a golden corpus
    /// exists to make impossible.
    static let corpus: Result<GoldenCorpus, any Error> = Result {
        let loaded = try CorpusLoader.load(directory: directory)
        try loaded.validateComplete()
        return loaded
    }

    static func loaded() throws -> GoldenCorpus {
        try corpus.get()
    }

    /// One scorer for the whole test lane, warmed off the measured path — the same shape the
    /// composition root uses, and the only shape in which the bounded LRU's hit rate means
    /// anything.
    static let scorer: SimilarityScorer = {
        let scorer = SimilarityScorer()
        scorer.warmUp()
        return scorer
    }()

    static var runner: CorpusRunner { CorpusRunner(scorer: scorer) }
}
