import FocusClassify
import FocusCore
import Foundation

/// The prompt, built from tokens rather than from prose.
///
/// `ModelRequest` carries `[NormalisedToken]` and a `NormalisedToken`, neither of which has a
/// public initialiser and both of which reject anything that is not a single token (R-57). So
/// this builder **cannot** be handed a window title, a full URL, a document name or a file
/// path — not because a rule forbids it but because there is no way to express one. That is
/// R-116's *"the prompt builder is typed so that it cannot accept a bare `String` from outside
/// `ClassificationEvidence`"*, and it is why the question below interpolates only two values.
///
/// The question asks about the **relation**, not about the person. Nothing here says
/// "distracted", "off task" or "wasting time": the model's only reachable effect is the absence
/// of a question (§2.4), so a prompt that invited a judgement about behaviour would be inviting
/// an answer the app has nowhere to put.
enum Prompt {
    /// What the model is told it is doing, once per session.
    static let instructions = """
        You are checking one thing: is this application part of the task the person wrote down, \
        or have they gone off on something else?

        Method. Read the task. Name to yourself the small set of applications somebody doing \
        that exact task would have open. Then check whether the application in front of you is \
        in that set.

        yes — it is in that set, and it is where the task's output is made.
        supporting — it is in that set, and it serves the output rather than making it.
        unrelated — it is NOT in that set. Choose this whenever the application merely could be \
        useful, is a capable tool, or is adjacent to the subject area. Most of the time this is \
        the right answer.
        unsure — the task is too vague for that set to have anything in it.

        Saying "yes" about something that is not the task costs the person the interruption they \
        asked for. Saying "unrelated" about something that turns out to be fine costs them one \
        click. Prefer the cheap mistake.
        """

    /// One question, two interpolated values, both of them tokens.
    static func question(for request: ModelRequest) -> String {
        let task = request.priorityTokens.map(\.value).joined(separator: " ")
        return """
            Task: \(task)
            Application: \(request.subject.value)
            Does this application belong to that task?
            """
    }

    /// **The list is the version** — the same shape as `EngineStamp.policyRevisions`.
    ///
    /// A bump is appending a line that says what moved, so a version that changed without a
    /// reason is unrepresentable. `promptVersion` is the count, never a digit somebody edits.
    static let revisions: [String] = [
        "e06 · the first prompt: one task, one application, four labels, greedy sampling.",
        "e06 · the first prompt scored `seduced: 14` on the committed 45-cell grid — the model "
            + "answered `supporting` for any capable tool it could tell a story about. R-111's "
            + "ruling is that a seduction is a PROMPT defect and the remedy is the prompt, never "
            + "the threshold, so: `unrelated` is named as the commonest answer, `supporting` is "
            + "narrowed to what the task cannot be done without, and the model is told that "
            + "needing a story means the answer is `unrelated`.",
        "e06 · the narrowed prompt scored `seduced: 20`, worse: naming `unrelated` as the "
            + "commonest answer did not stop a 3B model reading a bundle identifier as evidence "
            + "of usefulness. Third form gives it a METHOD rather than a definition — name the "
            + "small set of applications this exact task needs, then check membership — and "
            + "states the asymmetry in the person's own currency: a false yes costs them the "
            + "interruption they asked for, a false unrelated costs them one click.",
        "e06 · the method prompt scored `seduced: 15`, `rescueRecall: 0.7333`, `unstable: []` "
            + "across three passes. Three forms measured, best-of-three still fifteen "
            + "seductions against a budget of zero, and the instability is zero — this is a "
            + "property of the tier on this question, not noise a fourth run would wash out. "
            + "The prompt shipped is this one; the rung is NOT composed into the ladder "
            + "(`ModelTierRelease.composesTheRung == false`) until one green quality half "
            + "earns it."
    ]

    static var version: Int { revisions.count }
}
