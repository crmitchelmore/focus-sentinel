import Foundation

/// The committed English lexicon the intent validator reads with.
///
/// This is the whole of the "determinism, honestly bounded" bargain. There is no model here
/// and no `NaturalLanguage` import — `FocusCore` may not have one (R-03), and moving the
/// validator to `FocusClassify` would put it behind a package `FocusUI` is not allowed to
/// import, dragging the capture field through two modules to reach it.
///
/// A list of English words is only true of English, and the validator says so: outside an
/// English locale it returns `.notAssessable` and the surface shows nothing. That limitation
/// is stated in the acceptance criteria and in the Settings copy rather than hidden behind a
/// confident-looking suggestion.
///
/// Both spellings of the -ise/-ize pairs are present on purpose: a British user typing
/// "organise" is not writing a noun phrase.
public enum VerbLexicon {
    /// Imperative work verbs — the way a person names a job they are about to do.
    public static let imperatives: Set<String> = [
        "add", "adjust", "align", "analyse", "analyze", "announce", "answer", "apply",
        "approve", "archive", "arrange", "ask", "assemble", "assess", "assign", "attend",
        "audit", "book", "brief", "budget", "build", "buy", "call", "cancel", "capture",
        "categorise", "categorize", "change", "check", "choose", "clarify", "clean", "clear",
        "close", "collect", "compare", "compile", "complete", "compose", "configure",
        "confirm", "connect", "consolidate", "contact", "convert", "correct", "create", "cut",
        "debug", "decide", "define", "delete", "deliver", "deploy", "describe", "design",
        "diagnose", "do", "document", "download", "draft", "draw", "edit", "email", "enable",
        "ensure", "enter", "estimate", "evaluate", "expand", "explain", "export", "extract",
        "file", "fill", "filter", "finalise", "finalize", "find", "finish", "fix", "follow",
        "format", "gather", "generate", "group", "handle", "identify", "implement", "import",
        "improve", "index", "install", "integrate", "interview", "investigate", "invoice",
        "join", "launch", "learn", "list", "load", "log", "make", "map", "measure", "meet",
        "merge", "message", "migrate", "model", "move", "name", "negotiate", "note",
        "onboard", "open", "optimise", "optimize", "order", "organise", "organize", "outline",
        "package", "patch", "pay", "plan", "polish", "post", "prepare", "present", "print",
        "prioritise", "prioritize", "process", "produce", "profile", "proofread", "prototype",
        "publish", "pull", "push", "read", "rebuild", "record", "redesign", "reduce",
        "refactor", "register", "rehearse", "reject", "release", "remove", "renew", "rename",
        "render", "reorganise", "reorganize", "repair", "replace", "reply", "report",
        "request", "research", "reschedule", "reset", "resolve", "respond", "restore",
        "restructure", "return", "review", "revise", "revisit", "rewrite", "run", "scan",
        "schedule", "scope", "script", "search", "select", "sell", "send", "set", "settle",
        "ship", "sign", "simplify", "sketch", "solve", "sort", "specify", "split", "start",
        "submit", "summarise", "summarize", "sync", "tag", "test", "tidy", "track", "train",
        "transcribe", "translate", "trim", "triage", "tune", "update", "upgrade", "upload",
        "validate", "verify", "work", "wrap", "write"
    ]

    /// Articles. A sentence that opens with one is naming a topic, not a job.
    public static let articles: Set<String> = ["a", "an", "the"]

    /// Words that cannot on their own be the outcome of a task.
    ///
    /// "Fix it" has a verb and no outcome; "Fix the login bug" has both. The difference is
    /// entirely whether anything survives this filter.
    public static let nonOutcomeWords: Set<String> = [
        "a", "an", "the", "it", "this", "that", "these", "those", "some", "any", "thing",
        "things", "stuff", "and", "or", "but", "to", "of", "for", "on", "in", "at", "with",
        "by", "from", "up", "out", "off", "over", "more", "again", "my", "our", "your",
        "their", "his", "her", "its", "me", "us", "them", "i", "we", "you", "they", "he",
        "she", "now", "today", "tonight", "tomorrow", "soon", "later", "please", "just",
        "really", "very", "bit", "little", "stuff"
    ]

    /// Words that only ever *join* a phrase to what precedes it.
    ///
    /// Dropped from the **front** of a suggested "done when" phrase, and only from the front:
    /// "working **on** the proposal" yields "the proposal", which reads correctly in the
    /// surface's format string. Interior articles are kept for the same reason — "the
    /// proposal is finished" is English and "proposal is finished" is not.
    public static let leadingConnectors: Set<String> = [
        "and", "or", "but", "to", "of", "for", "on", "in", "at", "with", "by", "from", "up",
        "out", "off", "over", "about", "into", "through", "around"
    ]

    /// Whether a token is shaped like a gerund, whether or not the lexicon can undo it.
    ///
    /// `"thinking"` is a gerund this lexicon cannot turn into an imperative, and saying so is
    /// more useful than pretending otherwise: the phrase after it is still the object.
    public static func looksLikeAGerund(_ token: String) -> Bool {
        token.count > 4 && token.hasSuffix("ing") && !imperatives.contains(token)
    }

    /// Whether a lowercased token is an imperative work verb this lexicon knows.
    public static func isImperative(_ token: String) -> Bool {
        imperatives.contains(token)
    }

    public static func isArticle(_ token: String) -> Bool {
        articles.contains(token)
    }

    public static func canBeAnOutcome(_ token: String) -> Bool {
        !nonOutcomeWords.contains(token)
    }

    /// The imperative a leading gerund was formed from, if the lexicon recognises one.
    ///
    /// `"working"` → `"work"`, `"writing"` → `"write"`, `"running"` → `"run"`. Returns `nil`
    /// when nothing in the lexicon matches, which is the honest answer for `"nothing"` or
    /// `"something"`.
    ///
    /// Order matters: a token that is *itself* an imperative — `bring`, `ring`, `string` —
    /// is never treated as a gerund, because it is the caller's job to check that first and
    /// this function is only ever reached when that check failed.
    public static func imperativeBehindGerund(_ token: String) -> String? {
        guard token.count > 4, token.hasSuffix("ing") else { return nil }
        let stem = String(token.dropLast(3))

        // "work" → work; "writ" + e → write; "runn" → run (an undoubled final consonant).
        var candidates = [stem, stem + "e"]
        if let last = stem.last, stem.dropLast().last == last {
            candidates.append(String(stem.dropLast()))
        }

        return candidates.first { imperatives.contains($0) }
    }
}
