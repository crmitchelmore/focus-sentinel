import FocusCore
import Foundation
import Testing

@testable import FocusClassify

/// Probe **P-124**'s raw tables, and the two constants **recomputed** from them (R-74.2).
///
/// This is the suite that makes `similarityRelevantCeiling` and `languageConfidenceFloor`
/// *derived* rather than *chosen*. The tables are committed raw; the derivation rules were
/// committed in the plan before the measurement ran; and both constants are recomputed here
/// from the tables and asserted equal to what `RelevancePolicy` declares.
///
/// **A hand-edited constant against an unchanged table is therefore a red gate**, which is the
/// property an earlier draft could not have had: it wrote `1.00` and justified it as "0.0578
/// below the measured unrelated minimum", which was a real fact about *eight* pairs, and eight
/// pairs cannot fix the second decimal place of a float. This table has thirty-two unrelated
/// pairs and four of them sit below 1.00.
@Suite("P-124 — the similarity and language corpora")
struct SimilarityCorpusTests {
    // MARK: - Decoding the committed tables

    struct SimilarityTable: Decodable {
        struct Pair: Decodable {
            let id: String
            let priority: String
            let evidence: String
            let label: String
            let note: String
            let distance: Double
        }
        let probe: String
        let derivation: String
        let pairs: [Pair]

        var related: [Double] { pairs.filter { $0.label == "related" }.map(\.distance) }
        var unrelated: [Double] { pairs.filter { $0.label == "unrelated" }.map(\.distance) }
    }

    struct LanguageTable: Decodable {
        struct Entry: Decodable {
            let id: String
            let text: String
            let label: String
            let note: String
            let dominantLanguage: String
            let englishConfidence: Double
        }
        let probe: String
        let derivation: String
        let strings: [Entry]

        var judgeable: [Double] {
            strings.filter { $0.label == "judgeable" }.map(\.englishConfidence)
        }
        var nonJudgeable: [Double] {
            strings.filter { $0.label != "judgeable" }.map(\.englishConfidence)
        }
    }

    static func load<T: Decodable>(_ type: T.Type, named name: String) throws -> T {
        let url = try #require(
            Bundle.module.url(
                forResource: name,
                withExtension: "json",
                subdirectory: "Resources/Measurements"
            ),
            "P-124's \(name).json is not in the test bundle — check Package.swift's .copy(\"Resources\")"
        )
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    // MARK: - The arithmetic, written out so the rule is auditable

    /// Population standard deviation, which is what the derivation rule names: the table is
    /// the whole measured class, not a sample drawn from a larger one.
    static func populationSigma(_ values: [Double]) -> Double {
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        return variance.squareRoot()
    }

    static func roundedDown(toTwoDecimals value: Double) -> Double {
        (value * 100).rounded(.down) / 100
    }

    static func roundedUp(toTwoDecimals value: Double) -> Double {
        (value * 100).rounded(.up) / 100
    }

    // MARK: - R-74.2's floors on the corpora themselves

    @Test("the similarity table meets R-74.2's floor and is labelled")
    func similarityTableIsBigEnough() throws {
        let table = try Self.load(SimilarityTable.self, named: "similarity-pairs")
        #expect(table.probe == "P-124")
        #expect(table.pairs.count >= 60, "R-74.2 requires ≥ 60 labelled pairs")
        #expect(table.unrelated.count >= 24, "R-74.2 requires ≥ 24 unrelated pairs")
        #expect(Set(table.pairs.map(\.id)).count == table.pairs.count, "duplicate pair id")
        for pair in table.pairs {
            #expect(["related", "unrelated"].contains(pair.label), "\(pair.id): odd label")
            #expect(!pair.note.isEmpty, "\(pair.id) carries no note")
            #expect(pair.distance > 0, "\(pair.id): a distance of zero is not a measurement")
        }
    }

    @Test("the language table meets R-74.2's floor and covers all three labels")
    func languageTableIsBigEnough() throws {
        let table = try Self.load(LanguageTable.self, named: "language-strings")
        #expect(table.probe == "P-124")
        #expect(table.strings.count >= 40, "R-74.2 requires ≥ 40 labelled strings")
        #expect(Set(table.strings.map(\.label)) == ["judgeable", "fragment", "nonEnglish"])
        #expect(Set(table.strings.map(\.id)).count == table.strings.count, "duplicate string id")
        for entry in table.strings {
            #expect(!entry.note.isEmpty, "\(entry.id) carries no note")
            #expect((0...1).contains(entry.englishConfidence), "\(entry.id): odd confidence")
        }
    }

    // MARK: - The recomputation — R-74.2's whole point

    /// `similarityRelevantCeiling` = unrelated **minimum** − one population σ of the unrelated
    /// class, rounded **down** to two decimals.
    @Test("the ceiling recomputes from the committed table")
    func ceilingRecomputes() throws {
        let table = try Self.load(SimilarityTable.self, named: "similarity-pairs")
        let unrelated = table.unrelated
        let minimum = try #require(unrelated.min())
        let derived = Self.roundedDown(
            toTwoDecimals: minimum - Self.populationSigma(unrelated)
        )

        let committed = try #require(
            RelevancePolicy.similarityRelevantCeiling.value,
            "the ceiling is still .pendingMeasurement — T90a did not land"
        )
        #expect(
            derived == committed,
            """
            The committed ceiling and the committed table disagree.
            unrelated min \(minimum), population σ \(Self.populationSigma(unrelated))
            rule gives \(derived); RelevancePolicy declares \(committed).
            Re-measure with P-124's rig rather than editing either one alone.
            """
        )
    }

    /// `languageConfidenceFloor` = the midpoint between the lowest judgeable English string and
    /// the highest non-judgeable one, rounded **up** to two decimals.
    @Test("the language floor recomputes from the committed table")
    func floorRecomputes() throws {
        let table = try Self.load(LanguageTable.self, named: "language-strings")
        let lowestJudgeable = try #require(table.judgeable.min())
        let highestNonJudgeable = try #require(table.nonJudgeable.max())
        let derived = Self.roundedUp(
            toTwoDecimals: (lowestJudgeable + highestNonJudgeable) / 2
        )

        let committed = try #require(
            RelevancePolicy.languageConfidenceFloor.value,
            "the floor is still .pendingMeasurement — T90a did not land"
        )
        #expect(
            derived == committed,
            """
            The committed floor and the committed table disagree.
            lowest judgeable \(lowestJudgeable), highest non-judgeable \(highestNonJudgeable)
            rule gives \(derived); RelevancePolicy declares \(committed).
            """
        )
    }

    // MARK: - What the derived ceiling actually buys

    /// **Zero false positives at the committed ceiling**, which is the property the gate's
    /// `falseNudgeRate == 0.0` rests on from the similarity side. Misses are cheap: a miss
    /// falls to `uncertain`, which suppresses.
    @Test("the ceiling admits no unrelated pair, and admits a real share of related ones")
    func ceilingIsZeroFalsePositive() throws {
        let table = try Self.load(SimilarityTable.self, named: "similarity-pairs")
        let ceiling = try #require(RelevancePolicy.similarityRelevantCeiling.value)

        let falsePositives = table.unrelated.filter { $0 <= ceiling }
        #expect(falsePositives.isEmpty, "\(falsePositives.count) unrelated pairs sit at or below the ceiling")

        let admitted = table.related.filter { $0 <= ceiling }
        #expect(!admitted.isEmpty, "the ceiling admits nothing at all — the signal is dead")
        #expect(
            Double(admitted.count) / Double(table.related.count) > 0.25,
            "the ceiling admits only \(admitted.count) of \(table.related.count) related pairs"
        )
    }

    /// **The asymmetry, re-asserted at the measured value.**
    ///
    /// P-113 found the two classes overlapping at sixteen pairs. Quadrupling the corpus did not
    /// separate them: **28 of the 32 unrelated pairs sit inside the related range**, and 11 of
    /// the 30 related pairs sit above the unrelated minimum. There is no distance at which
    /// "further than this" means "not your work", and a rule that tried would accuse somebody
    /// on more than a third of their own evidence.
    ///
    /// The four unrelated pairs *above* the related maximum are not a counter-example and must
    /// not be read as one. `relatedMax` is a **sample** maximum over thirty pairs; a single new
    /// related pair above it erases the region entirely — which is R-74.2's own argument, in
    /// the direction that would cost a false accusation rather than a miss. So the ruling is
    /// unconditional: **similarity may corroborate `relevant`; it may never produce `unrelated`,
    /// at any distance** (R-58). `SimilarityCorroboration` ships with no case that could carry
    /// one, and `SimilarityScorerTests` asserts that half.
    @Test("the classes overlap, so no distance can mean unrelated")
    func theClassesOverlapSoSimilarityMayNeverAccuse() throws {
        let table = try Self.load(SimilarityTable.self, named: "similarity-pairs")
        let relatedMax = try #require(table.related.max())
        let relatedMin = try #require(table.related.min())
        let unrelatedMin = try #require(table.unrelated.min())

        // The overlap, from both sides.
        #expect(unrelatedMin < relatedMax, "the classes are separable — re-derive rather than assume")
        let unrelatedInsideRelatedRange = table.unrelated.filter { $0 <= relatedMax && $0 >= relatedMin }
        #expect(
            Double(unrelatedInsideRelatedRange.count) / Double(table.unrelated.count) > 0.75,
            "only \(unrelatedInsideRelatedRange.count) of \(table.unrelated.count) unrelated pairs overlap"
        )
        let relatedAboveUnrelatedMinimum = table.related.filter { $0 >= unrelatedMin }
        #expect(
            Double(relatedAboveUnrelatedMinimum.count) / Double(table.related.count) > 0.25,
            "a threshold above \(unrelatedMin) would misclassify only \(relatedAboveUnrelatedMinimum.count) related pairs"
        )

        // And the ceiling is where it has to be for corroboration to be safe: strictly below
        // every unrelated distance in the table.
        let ceiling = try #require(RelevancePolicy.similarityRelevantCeiling.value)
        #expect(ceiling < unrelatedMin)
    }

    /// The measured **negative result**, committed as an assertion so it cannot be quietly
    /// forgotten: the language classes overlap, so this constant is an English gate and not a
    /// vagueness gate — and every fragment that beats the floor is declined by
    /// `minimumPriorityContentTokens` instead. The two guards are complementary, and asserting
    /// that here is what stops somebody "simplifying" one of them away.
    @Test("the fragments that beat the language floor are declined by the content floor")
    func theTwoGuardsAreComplementary() throws {
        let table = try Self.load(LanguageTable.self, named: "language-strings")
        let floor = try #require(RelevancePolicy.languageConfidenceFloor.value)
        let normalizer = TokenNormalizer()

        let survivors = table.strings.filter {
            $0.label != "judgeable" && $0.englishConfidence >= floor
        }
        #expect(!survivors.isEmpty, "the measured overlap has gone — re-derive rather than delete this")

        for survivor in survivors {
            let tokens = normalizer.tokens(fromProse: survivor.text).tokens
            #expect(
                tokens.count < RelevancePolicy.minimumPriorityContentTokens,
                "\(survivor.id) '\(survivor.text)' beats the language floor AND the content floor"
            )
        }
    }

    /// Every non-English string scores English at essentially nothing, which is the half of
    /// the gate P-111 forces: there is no embedding for any of those languages, so there is
    /// nothing to consult at any confidence.
    @Test("no non-English string comes close to the floor")
    func nonEnglishIsSeparatedCleanly() throws {
        let table = try Self.load(LanguageTable.self, named: "language-strings")
        let floor = try #require(RelevancePolicy.languageConfidenceFloor.value)
        for entry in table.strings where entry.label == "nonEnglish" {
            #expect(
                entry.englishConfidence < floor,
                "\(entry.id) (\(entry.dominantLanguage)) scored English at \(entry.englishConfidence)"
            )
        }
    }
}
