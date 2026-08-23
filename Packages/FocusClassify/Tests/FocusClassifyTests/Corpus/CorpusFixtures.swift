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

    static var directory: URL {
        Bundle.module.bundleURL
            .appendingPathComponent(resourcesDirectoryName)
            .appendingPathComponent(CorpusLoader.goldenCorpusDirectoryName)
    }

    /// Loaded once. Decoding 130-odd cases strictly is cheap, but the sentence-embedding
    /// warm-up behind the shared scorer is not (P-116 measured 59.4 ms cold), and a suite that
    /// paid it per test would be reporting the load rather than the engine.
    static let corpus: Result<GoldenCorpus, any Error> = Result {
        try CorpusLoader.load(directory: directory)
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
