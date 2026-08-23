import Foundation

/// What a deterministic read of an intent sentence concluded.
///
/// The Court's ruling for F-07 is "deterministic validation requiring verb and outcome"; the
/// product doctrine is that a vague sentence is answered constructively rather than refused.
/// Both are satisfied by putting the *requirement* here and the *generosity* in the surface:
/// this type says what is missing and suggests a rewrite, and the Set Priority button is
/// never disabled and never refuses. Pressing it again commits the user's original words,
/// unchanged.
///
/// The plan lists `notAssessable` among the finding vocabulary. It ships as an assessment
/// case rather than a finding because it carries neither an explanation a person should read
/// nor a suggestion: outside English the surface shows **nothing**, because confident nonsense
/// is worse than silence.
public enum IntentAssessment: Sendable, Equatable, Hashable {
    /// A leading imperative verb and a concrete outcome. Nothing to say.
    case wellFormed
    /// Something is missing, and here is what, with a rewrite made of the user's own words.
    case needsWork(findings: [IntentFinding])
    /// The lexicon does not cover this locale. The surface shows nothing at all.
    case notAssessable

    /// The findings, or an empty array for the two cases that have none.
    public var findings: [IntentFinding] {
        switch self {
        case .needsWork(let findings): findings
        case .wellFormed, .notAssessable: []
        }
    }

    public var isWellFormed: Bool {
        if case .wellFormed = self { return true }
        return false
    }

    /// Whether the surface should show anything at all. `notAssessable` shows nothing.
    public var hasSomethingToSay: Bool {
        if case .needsWork = self { return true }
        return false
    }
}

/// One thing a sentence is missing, and one concrete way to fix it.
///
/// The finding carries a **typed** key rather than a catalog key string. The explanation and
/// the suggestion format live in `FocusUI`'s String Catalog, because that is the module that
/// draws them; `FocusCore` never holds a sentence of English prose.
public struct IntentFinding: Sendable, Equatable, Hashable, Identifiable {
    /// The four things a deterministic reader can actually tell.
    public enum Kind: String, Sendable, CaseIterable, Hashable {
        /// The sentence starts with something that is not an imperative verb — most often a
        /// gerund ("working on…"), which describes a state rather than naming a job.
        case noLeadingVerb
        /// Too little to act on: one word, or barely any characters.
        case tooShort
        /// A bare noun phrase — a topic rather than a task ("proposal", "the budget").
        case nounOnlyPhrase
        /// A verb with nothing concrete attached to it ("fix it", "finish").
        case noOutcome
    }

    public let kind: Kind
    public let suggestion: IntentSuggestion

    public var id: Kind { kind }

    public init(kind: Kind, suggestion: IntentSuggestion) {
        self.kind = kind
        self.suggestion = suggestion
    }
}

/// A concrete suggestion, assembled from the user's own words and nothing else.
///
/// `rewrite` and `doneWhenPhrase` are the user's words — de-gerunded, de-articled, trimmed,
/// but never invented. The surrounding sentence is a format string in `FocusUI`'s catalog with
/// exactly one argument. That is what keeps standing condition 4 true here and in e06: no
/// prose is authored at runtime, by a model or by anything else.
public struct IntentSuggestion: Sendable, Equatable, Hashable {
    /// Which format string the surface should wrap `rewrite` in.
    public enum Kind: String, Sendable, CaseIterable, Hashable {
        /// "Start with a verb — for example …"
        case startWithVerb
        /// "Say a little more about …"
        case sayMore
        /// "Name what will be true when it is done …"
        case nameTheOutcome
    }

    public let kind: Kind
    /// The user's own sentence, rewritten only by transformations that add no new words.
    public let rewrite: String
    /// The object phrase a pre-filled "done when" can be built from, if one was found.
    public let doneWhenPhrase: String?

    public init(kind: Kind, rewrite: String, doneWhenPhrase: String?) {
        self.kind = kind
        self.rewrite = rewrite
        self.doneWhenPhrase = doneWhenPhrase
    }
}
