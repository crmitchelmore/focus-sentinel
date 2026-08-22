import Foundation

/// A deterministic read of an intent sentence: does it name a job, and does it name an
/// outcome?
///
/// **Pure.** Same input, same output, always. No clock, no `Locale.current`, no store, no
/// model — the locale is a parameter precisely so that a test cannot depend on the machine it
/// runs on, and so that the ≥40-row table is a table rather than a mood.
///
/// **It explains, it never blocks.** Nothing here returns "no". The surface shows the finding
/// and a rewrite built from the user's own words, and the Set Priority button stays enabled
/// throughout: pressing it a second time commits the original sentence unchanged (R-20).
///
/// **Bounded honestly.** The lexicon is English. Outside an English locale the answer is
/// `.notAssessable` and the surface shows nothing, because a confident suggestion in a
/// language the code cannot read is worse than silence.
public enum IntentValidator {
    /// Whether the lexicon covers this locale at all.
    public static func isAssessable(locale: Locale) -> Bool {
        locale.language.languageCode?.identifier == "en"
    }

    /// Assess an intent sentence.
    ///
    /// Findings are emitted in a fixed order — the shape of the phrase first
    /// (`nounOnlyPhrase` or `noLeadingVerb`), then `tooShort`, then `noOutcome` — so that a
    /// table test can compare arrays rather than sets, and so that the surface's first line is
    /// always the most structural thing that is wrong.
    public static func assess(_ intent: String, locale: Locale) -> IntentAssessment {
        guard isAssessable(locale: locale) else { return .notAssessable }

        let trimmed = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = tokenize(trimmed)

        guard let leading = tokens.first else {
            // Nothing at all. There is no sentence to rewrite, so the suggestion carries the
            // empty phrase and the surface says only "say a little more".
            return .needsWork(
                findings: [
                    IntentFinding(
                        kind: .tooShort,
                        suggestion: IntentSuggestion(
                            kind: .sayMore,
                            rewrite: "",
                            doneWhenPhrase: nil
                        )
                    )
                ]
            )
        }

        let hasLeadingVerb = VerbLexicon.isImperative(leading.normalised)
        let objectPhrase = objectPhrase(from: tokens, hasLeadingVerb: hasLeadingVerb)
        let outcomeWords = tokens
            .dropFirst(hasLeadingVerb ? 1 : 0)
            .filter { VerbLexicon.canBeAnOutcome($0.normalised) }

        var findings: [IntentFinding] = []

        if !hasLeadingVerb {
            let looksLikeABareNoun = VerbLexicon.isArticle(leading.normalised) || tokens.count == 1
            findings.append(
                IntentFinding(
                    kind: looksLikeABareNoun ? .nounOnlyPhrase : .noLeadingVerb,
                    suggestion: IntentSuggestion(
                        kind: .startWithVerb,
                        rewrite: rewriteStartingWithAVerb(trimmed, tokens: tokens),
                        doneWhenPhrase: objectPhrase
                    )
                )
            )
        }

        if tokens.count < 2 || trimmed.count < 3 {
            findings.append(
                IntentFinding(
                    kind: .tooShort,
                    suggestion: IntentSuggestion(
                        kind: .sayMore,
                        rewrite: trimmed,
                        doneWhenPhrase: objectPhrase
                    )
                )
            )
        }

        if hasLeadingVerb && outcomeWords.isEmpty {
            findings.append(
                IntentFinding(
                    kind: .noOutcome,
                    suggestion: IntentSuggestion(
                        kind: .nameTheOutcome,
                        rewrite: trimmed,
                        doneWhenPhrase: objectPhrase
                    )
                )
            )
        }

        return findings.isEmpty ? .wellFormed : .needsWork(findings: findings)
    }

    // MARK: - Words

    /// One word of the sentence: what the user typed, and the form the lexicon is asked about.
    struct Token: Sendable, Equatable, Hashable {
        /// The word exactly as it was typed, minus the punctuation around it.
        let original: String
        /// Lowercased, for lexicon lookups.
        let normalised: String
    }

    /// Split on whitespace, strip the punctuation around each word, drop what is left empty.
    ///
    /// Punctuation *inside* a word is kept: `q3`, `read-only` and `v2.1` are words a person
    /// means, and a tokenizer that shreds them would report a missing outcome that is right
    /// there in the sentence.
    static func tokenize(_ text: String) -> [Token] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { raw -> Token in
                let stripped = raw.trimmingCharacters(
                    in: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_/")).inverted
                )
                return Token(original: stripped, normalised: stripped.lowercased())
            }
            .filter { !$0.original.isEmpty }
    }

    /// The words a pre-filled "done when" is built from — the *object* of the sentence.
    ///
    /// The leading word is dropped when it is doing the work of a verb or an article: an
    /// imperative, a gerund (whether or not the lexicon can undo it), or `a`/`an`/`the`. Then
    /// any connectors at the front go too, so `"working on the proposal"` yields
    /// `"the proposal"` and not `"on the proposal"`. Articles *inside* the phrase stay,
    /// because the surface wraps this in "%@ is finished" and "proposal is finished" is not a
    /// sentence.
    private static func objectPhrase(from tokens: [Token], hasLeadingVerb: Bool) -> String? {
        guard let leading = tokens.first else { return nil }

        let dropsLeading = hasLeadingVerb
            || VerbLexicon.isArticle(leading.normalised)
            || VerbLexicon.looksLikeAGerund(leading.normalised)

        var rest = Array(tokens.dropFirst(dropsLeading ? 1 : 0))
        while let first = rest.first, VerbLexicon.leadingConnectors.contains(first.normalised) {
            rest.removeFirst()
        }

        guard !rest.isEmpty else { return nil }
        return rest.map(\.original).joined(separator: " ")
    }

    /// The user's own sentence, turned into an imperative where that can be done without
    /// inventing a word.
    ///
    /// A leading gerund the lexicon recognises is replaced by the imperative behind it
    /// (`"working on the proposal"` → `"Work on the proposal"`); a leading article is dropped
    /// (`"the budget"` → `"Budget"` is *not* attempted — the article is dropped and the noun
    /// stands, and the surface's format string supplies the example verb). Everything else is
    /// returned unchanged, capitalised. No word that the user did not type is ever added here.
    private static func rewriteStartingWithAVerb(_ trimmed: String, tokens: [Token]) -> String {
        guard let leading = tokens.first else { return trimmed }

        if let imperative = VerbLexicon.imperativeBehindGerund(leading.normalised) {
            let rest = tokens.dropFirst().map(\.original)
            return capitalisingFirstLetter(([imperative] + rest).joined(separator: " "))
        }

        if VerbLexicon.isArticle(leading.normalised) {
            let rest = tokens.dropFirst().map(\.original)
            guard !rest.isEmpty else { return capitalisingFirstLetter(trimmed) }
            return capitalisingFirstLetter(rest.joined(separator: " "))
        }

        return capitalisingFirstLetter(trimmed)
    }

    private static func capitalisingFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + text.dropFirst()
    }
}
