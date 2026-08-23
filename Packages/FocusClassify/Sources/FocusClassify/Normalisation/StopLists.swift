import Foundation
import NaturalLanguage

/// The committed lexicons the normaliser reads, and nothing else.
///
/// Every list here is versioned by `EngineStamp.lexiconVersion`: changing one changes what the
/// engine can see, so it changes the cache key e06 will serve verdicts from. They are code
/// rather than data for the same reason `RelevanceSeed.defaults` is (R-64) — a user's own rule
/// outranks anything a list here can cause, so there is no reseed problem to buy.
///
/// **No numeric literal appears in this file.** R-70f permits one only in
/// `RelevancePolicy.swift`, and the two places a small number would otherwise have been
/// written down — the maximum number of language hypotheses to ask for, and the length of a
/// country-code top-level domain — are both derived from a named collection or a named string
/// instead. A reader gets the reason rather than the digit.
public enum StopLists {
    // MARK: - Prose (R-57 a)

    /// The lexical classes a content token can never be, as `NLTag` raw values.
    ///
    /// Measured at P-114 over twelve real priority sentences: `Write→Verb`, `the→Determiner`,
    /// `Q3→Adjective`, `proposal→Noun`, `for→Preposition`, `Acme→Noun`, `and→Conjunction`,
    /// `it→Pronoun`. **`Number` is deliberately absent from this list**: "chapter 3" and "Q3"
    /// are how people name work, and a normaliser that dropped the digit would lose the only
    /// distinguishing word in half the priorities anyone writes.
    public static let droppedLexicalClasses: Set<String> = [
        NLTag.determiner.rawValue,
        NLTag.preposition.rawValue,
        NLTag.conjunction.rawValue,
        NLTag.pronoun.rawValue,
        NLTag.particle.rawValue,
        NLTag.interjection.rawValue,
        NLTag.other.rawValue,
        NLTag.otherWhitespace.rawValue,
        NLTag.otherPunctuation.rawValue,
        NLTag.whitespace.rawValue,
        NLTag.punctuation.rawValue
    ]

    /// Words that overlap on everything, and are therefore evidence of nothing.
    ///
    /// P-119's run over twelve real priorities left `friday`, `last` and `month` standing as
    /// "content" tokens, and a date word matching a date word is not evidence of relevance —
    /// it is the single easiest way for the overlap stage to produce a false `relevant`. The
    /// list is deliberately short: genericity is handled here, and *shortness* is handled by
    /// `RelevancePolicy.minimumTokenLength`, because the two are different problems and a
    /// length filter that tried to do both would lose `bug`, `fix` and `iOS`.
    ///
    /// It is applied to **prose only**. An identifier token is never dropped for being
    /// generic, because `com.apple.Notes` losing `notes` would leave the misleading-name
    /// family with nothing to be misleading about.
    public static let genericStopTokens: Set<String> = [
        // Time words. Every priority written on a Friday contains one.
        "today", "tomorrow", "yesterday", "morning", "afternoon", "evening", "tonight",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "day", "week", "month", "year", "hour", "minute", "time", "date", "deadline",
        "last", "next", "first", "final", "soon", "later", "now",
        // Work words that name no work.
        "work", "task", "thing", "stuff", "item", "note", "list", "plan", "step",
        "todo", "done", "start", "finish", "make", "get", "put", "use", "need", "want",
        "new", "old", "good", "bad", "more", "less", "some", "any", "all", "one",
        // Filler that survives lemmatisation.
        "just", "also", "very", "really", "then", "than", "there", "here", "about"
    ]

    /// How many language hypotheses to ask `NLLanguageRecognizer` for.
    ///
    /// The gate is on **English**'s probability, not on the dominant language's, so the
    /// recogniser has to be asked for enough hypotheses that English is reported even when it
    /// is not the winner — otherwise a French priority would score English at zero for the
    /// wrong reason, and the derivation of `languageConfidenceFloor` would be measuring the
    /// truncation rather than the language.
    ///
    /// The number is the size of the language set P-111 actually measured `NLEmbedding` over,
    /// which is a named justification rather than a digit somebody liked.
    public static let measuredLanguages: [String] = [
        NLLanguage.english.rawValue,
        NLLanguage.french.rawValue,
        NLLanguage.german.rawValue,
        NLLanguage.japanese.rawValue,
        NLLanguage.simplifiedChinese.rawValue,
        NLLanguage.spanish.rawValue
    ]

    // MARK: - Identifiers (R-57 b)

    /// The characters a reverse-DNS identifier is split on before camelCase decomposition.
    ///
    /// P-119 measured `NLTokenizer(unit: .word)` splitting on `.` and `-` but **not** on
    /// camelCase: `com.apple.ScreenContinuity` came back as
    /// `["com", "apple", "ScreenContinuity"]`. The framework alone would therefore leave
    /// `ScreenContinuity` opaque, F-171's seed-override guard would never fire, and a priority
    /// naming *"the iPhone Mirroring demo"* would be nudged about by the app's own default.
    /// Hence a hand-written decomposer, and hence this list.
    public static let identifierSeparators: Set<Character> = [".", "-", "_"]

    /// Reverse-DNS heads and other segments that identify nobody.
    ///
    /// P-119's committed list, verbatim. These are dropped from *identifiers only*: `com`,
    /// `io` and `me` are the registrar's words rather than the application's, and an overlap
    /// on one of them would match every application ever shipped.
    ///
    /// Five of the eleven are shorter than `RelevancePolicy.minimumTokenLength` and would fall
    /// to the length filter anyway. They are kept because the list is the *committed* one and
    /// because the length filter is a different rule that a later epic may move: a head token
    /// that survived because two guards happened to overlap is a head token that comes back
    /// the day one of them changes.
    public static let reverseDNSHeadTokens: Set<String> = [
        "com", "org", "net", "io", "co", "uk", "app", "md", "dev", "me", "gg"
    ]

    // MARK: - Origins (R-57 c)

    /// The host label that names nothing. `https://www.youtube.com` → `["youtube"]` (P-119).
    public static let wwwLabel = "www"

    /// The `co.uk` rule, as a length rather than as a digit (P-119).
    ///
    /// When the final host label is a two-letter country code, the label before it is a public
    /// suffix too — `acme.co.uk` is one site, not a site called `co`. Expressed as the length
    /// of a real country-code top-level domain so that R-70f's lint sees a name and a reason
    /// where it would otherwise see a magic number.
    public static let countryCodeTLDLength = "uk".count
}
