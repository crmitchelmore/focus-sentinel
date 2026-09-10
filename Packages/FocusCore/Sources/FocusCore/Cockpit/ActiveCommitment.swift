import Foundation

/// **The one thing the person has committed to, as one fact with one owner** (focus-zrs, U-1).
///
/// ## Why a type, rather than a `Bool` and a `UUID` read from two places
///
/// Seven rounds of this epic have each repaired a place where **two values represented one fact**
/// and nothing enforced that they agree. This is that shape at the centre of the nudge loop, and
/// it produced three live defects at once:
///
/// * Gate 1 — *may the app speak at all?* — was decided by `NudgeSurroundings.hasActivePriority`,
///   a `Bool` the composition root built from `priorityHost.state.priority != nil`. That
///   projection is deliberately **seeded with what is already on screen** when the store refuses a
///   read (`PriorityHost.refresh()`), so it outlives a failure rather than blanking the window.
/// * Everything the interruption that gate admitted ever wrote — the receipt, the learned rule,
///   the deferral rows, the budget key — was keyed to `NudgeHost.activePriorityID()`, a
///   **second, live** read of `PriorityStore`.
///
/// Nothing compared them, and there is no reason they must agree. When they diverged the app
/// raised a question, drew it, let somebody read it and answer it, and then dropped the click in
/// `guard let priorityID = openQuestionPriorityID else { return }` — with `defer {
/// closeSurfaces(endingAnyQuestionAs: .answered) }` tidying the panel away. Measured: panel
/// visible showing `.question`, every offered action reachable, **zero** rules written, no
/// receipt, `settled` false, and the same question asked five times. One function on, the same
/// `nil` made `displacedQuestion(from:)` answer `nil`, so `settleOrExpire(…)` returned on its
/// first line and `PreemptionCredit` — the whole substance of two earlier rounds — was never
/// consulted at all.
///
/// The repair is not a check that the two readings agree. It is that **there is one reading**: the
/// commitment travels as a value from the object that owns the store projection, the gate is
/// `commitment != nil`, and the key is `commitment.id`. They are the same optional, so
/// disagreement is not a bug that can recur — it is a state the types cannot express.
///
/// ## Why the intent travels with the identifier
///
/// For exactly the same reason. `NudgeHost` used to draw the question's *"Is this part of &lt;task&gt;?"*
/// from `activeIntent()` — a third read of the same store — so the sentence on the panel could
/// name one commitment while the receipt was keyed to another. One value, read once per judgement,
/// carries both.
public struct ActiveCommitment: Sendable, Equatable, Hashable, Identifiable {
    /// The `PriorityTask` row this commitment is. Every receipt, rule, deferral and budget key
    /// the interruption writes is scoped to it.
    public let id: UUID
    /// The person's own sentence, as the surfaces draw it. Data, never prose (R-24).
    public let intent: String

    public init(id: UUID, intent: String) {
        self.id = id
        self.intent = intent
    }
}
