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
        You judge whether an application a person has in front of them belongs to the task they \
        wrote down. Answer with one label and nothing else. Answer "yes" when the application is \
        the work itself, "supporting" when it serves the work (documentation, a reference, a \
        tool the work needs), "unrelated" when it is not the work, and "unsure" when the words \
        you were given do not settle it. Prefer "unsure" over a guess.
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
        "e06 · the first prompt: one task, one application, four labels, greedy sampling."
    ]

    static var version: Int { revisions.count }
}
