import Foundation

/// One sentence's embedding, as a value.
///
/// Carried rather than recomputed because P-116 measured a sentence vector at **1.75 ms** and a
/// sentence *distance* at **3.48 ms** — the only expensive calls in the engine. R-65 therefore
/// computes the priority side **once per priority revision**, in the rule snapshot, and the
/// evidence side is memoised in a bounded LRU. Neither is possible unless a vector is a value
/// something can hold.
///
/// ## The distance identity, and why it had to be measured
///
/// `NLEmbedding.distance(between:and:distanceType:.cosine)` is **not** `1 − cos` of the vectors
/// `vector(for:)` returns. P-124 measured what it actually is: the **Euclidean distance between
/// the two L2-normalised vectors** — equivalently `sqrt(2·(1 − cos))` — matched to
/// `1.03 × 10⁻⁶` on every one of sixty-two pairs.
///
/// That identity is load-bearing rather than trivia. Without it the cached-vector path would
/// compute a number on a different scale from the one P-113 and P-124 measured through the
/// framework call, and `similarityRelevantCeiling` would be calibrated against a distance
/// nothing in the engine produces. `SimilarityScorerTests` re-asserts the identity against the
/// framework on the committed corpus, so a future OS that changed it fails loudly.
public struct SentenceVector: Sendable, Equatable, Hashable, Codable {
    /// The embedding's components. 512 of them for English on this OS (P-110).
    public let components: [Double]

    /// `nil` for an empty vector: a zero-dimension embedding is an absent one, and an absent
    /// one must not be mistaken for a distance of zero.
    public init?(_ components: [Double]) {
        guard !components.isEmpty else { return nil }
        self.components = components
    }

    /// The engine's distance, computed the way the framework computes it.
    ///
    /// Written as the Euclidean distance between the normalised vectors rather than as
    /// `sqrt(2·(1 − cos))` for two reasons: it is what the quantity *is*, so a reader does not
    /// have to take an algebraic identity on trust; and it introduces no numeric literal, which
    /// R-70f requires of every file in this package but `RelevancePolicy.swift`.
    ///
    /// `nil` when the two vectors have different dimensions, or when either has no length —
    /// both of which mean "there is no distance here", never "the distance is zero".
    public func distance(to other: SentenceVector) -> Double? {
        guard components.count == other.components.count else { return nil }

        var leftSquared: Double = 0
        var rightSquared: Double = 0
        for index in 0..<components.count {
            leftSquared += components[index] * components[index]
            rightSquared += other.components[index] * other.components[index]
        }
        guard leftSquared > 0, rightSquared > 0 else { return nil }

        let leftLength = leftSquared.squareRoot()
        let rightLength = rightSquared.squareRoot()

        var sumOfSquares: Double = 0
        for index in 0..<components.count {
            let delta = components[index] / leftLength - other.components[index] / rightLength
            sumOfSquares += delta * delta
        }
        return sumOfSquares.squareRoot()
    }

    public var dimension: Int { components.count }
}
