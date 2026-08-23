import Foundation

/// A single normalised token — the only textual payload an explanation can carry.
///
/// ## There is no `NormalisedToken("…")`
///
/// The memberwise initialiser is `private`, and the only routes in are the two validating
/// factories below. Both reject anything that is not a *single token*: whitespace of any kind,
/// a control character, and every ASCII punctuation mark except `.`, `-` and `_`. So a window
/// title (spaces), a full URL (`:` `/` `?` `&` `=`), a document name (spaces, `,`) and an
/// absolute path (`/`) cannot be turned into a value of this type by any route.
///
/// That is the same technique e03 used for `NormalisedDetail` (R-41), applied to the other end
/// of the pipeline (R-57). Raw captured content in an explanation is **unrepresentable**, not
/// forbidden — and the hostile-corpus test the explanation builder runs is a check on the
/// enforcement rather than the enforcement itself.
///
/// What *is* allowed is a lowercased word, a lemma, a number-bearing token such as `q3`, a
/// reverse-DNS identifier such as `com.apple.safari`, a host label such as `docs`, and a
/// non-ASCII word such as `提案` or `rédiger` — because the normaliser must be able to say what
/// it saw in the user's own language, and a token is a token in every script.
public struct NormalisedToken: Sendable, Equatable, Hashable, Codable, Comparable,
                               CustomStringConvertible {
    /// The token itself. Safe to render verbatim: by construction it holds no whitespace and
    /// no separator a path, a URL or a sentence would need.
    public let value: String

    /// **Private on purpose.** Making this `public` would be the `String` initialiser this
    /// type exists not to have.
    private init(unchecked value: String) {
        self.value = value
    }

    /// The only route in for a single candidate. `nil` when the candidate is not a token.
    ///
    /// Note what this does *not* do: it does not strip, trim, split or repair. A value that is
    /// not already a token is rejected rather than mangled into one, because a repair here
    /// would be the normaliser's job done twice, in a type that cannot see the language, the
    /// lexical class or the stop list.
    public static func normalised(_ candidate: String) -> NormalisedToken? {
        guard isWellFormed(candidate) else { return nil }
        return NormalisedToken(unchecked: candidate)
    }

    /// The same, over a list: everything that is a token, in order, with the rest dropped.
    public static func normalised(_ candidates: [String]) -> [NormalisedToken] {
        candidates.compactMap(normalised)
    }

    /// Whether a string is a single normalised token.
    ///
    /// Exposed so a test can assert the rule directly rather than by observing a `nil`.
    public static func isWellFormed(_ candidate: String) -> Bool {
        guard !candidate.isEmpty else { return false }
        return candidate.allSatisfy(isTokenCharacter)
    }

    private static func isTokenCharacter(_ character: Character) -> Bool {
        if character.isWhitespace || character.isNewline { return false }
        if character.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return false
        }
        if character.isLetter || character.isNumber { return true }
        return character == "." || character == "-" || character == "_"
    }

    public var description: String { value }

    public static func < (lhs: NormalisedToken, rhs: NormalisedToken) -> Bool {
        lhs.value < rhs.value
    }

    // MARK: - Codable

    /// Decoding is the third construction route, so it validates too — a corpus fixture or a
    /// persisted explanation carrying `"a b"` fails the decode rather than smuggling a
    /// sentence past the factories.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard Self.isWellFormed(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "not a single normalised token: \(raw.debugDescription)"
            )
        }
        self.init(unchecked: raw)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
