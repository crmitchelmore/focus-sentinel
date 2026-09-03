import Foundation
import SwiftData

/// **Saying *you were wrong to stay quiet*** — the one thing nothing else in this app can do
/// (focus-tee.5, F-104).
///
/// Every other correction in the programme answers something the app said. This answers
/// something it did **not** say: an interval History drew because the app watched it go past in
/// silence, and the person disagrees.
///
/// ## What it writes, and what it deliberately does not
///
/// One row: a `RuleAuthority.task` rule at the verdict `unrelated`, scoped to **the priority that
/// judgement ran under** and never to the current one. The rule is built by
/// `QueryAnswer.no.outcome(scope:at:id:)` — the same function every in-the-moment correction goes
/// through — so a rule written here is byte-identical to one written on the panel but for its
/// `id` and `createdAt` (D5). There is no second shape of rule and no second place the shape is
/// decided.
///
/// `outcome(…)` returns `.ruleAndReceipt`. **History takes the rule half and drops the receipt**,
/// and three independent facts make that structural rather than careful:
///
///  1. this type holds **no `QueryLedger` reference at all** and its one function does not take
///     one, so there is no object here through which a receipt could be written;
///  2. the receipt half is an `AskedQuestionOutcome`, a value — writing it needs
///     `QueryLedger.answer(…)`, which is not called from this file;
///  3. `QueryLedger.count()` and `all()` are therefore byte-identical before and after every
///     correction History makes, which is what `HistoryCorrectionTests` asserts.
///
/// That matters because a receipt is authoritative for never-ask-twice (R-78). Writing one from
/// a ledger surface would settle — or re-open — a question retroactively, and *"I disagree with
/// what you did at eleven"* is not *"and by the way you may stop asking me about it"*.
///
/// ## And the log is never edited
///
/// `InterventionLog.complete(_:outcome:)` fills an outcome once and refuses a second call. A
/// correction **appends** the person's disagreement as a rule; it does not rewrite the day. What
/// happened is what happened, and the record of it is not the place to put a later opinion (F4).
public enum HistoryCorrection {
    /// The verdict *"this was a distraction"* writes.
    ///
    /// `QueryAnswer.no` rather than a literal, because that is the answer whose meaning is
    /// already *"no, this is not part of what I am doing"* — and its `ruleVerdict` is where the
    /// mapping to `unrelated` is written down once for the whole programme.
    public static let answer: QueryAnswer = .no

    /// Write the rule for one silent interval the person has disagreed with.
    ///
    /// - Returns: the identifier of the rule that was written.
    /// - Throws: `HistoryCorrectionError.withdrawn` when the affordance was not offered. The
    ///   surface withdraws it with a stated reason and never draws it as a live control, so this
    ///   is a guard against a caller that ignored the value — not a path a click can reach.
    @discardableResult
    @MainActor
    public static func markAsDistraction(
        _ correctability: HistoryCorrectability,
        priorities: PriorityStore,
        at instant: Date,
        ruleID: UUID = UUID(),
        undo: UndoManager? = nil
    ) throws -> UUID {
        guard case .offered(let subject, let priorityID) = correctability else {
            throw HistoryCorrectionError.withdrawn(correctability.withdrawal ?? .noSubject)
        }
        // The priority is re-read at the moment of the write, not trusted from the value the
        // surface has been holding since the window opened. A priority deleted while History was
        // on screen is exactly the case R-88 is about, and the answer is to refuse rather than to
        // widen the rule to `global`.
        guard let task = try priorities.task(id: priorityID) else {
            throw HistoryCorrectionError.withdrawn(.priorityDeleted)
        }

        let scope = CorrectionScope.from(subject)
        let outcome = answer.outcome(scope: scope, at: instant, id: ruleID)
        // `.no` always carries a rule; the `guard` states that rather than assuming it, so a
        // future answer with no rule half fails loudly here instead of silently doing nothing.
        guard let rule = outcome.persistedRule else {
            throw HistoryCorrectionError.withdrawn(.noSubject)
        }

        // Through `PriorityStore.addRule`, so the write is journalled and undoable exactly like
        // every other rule the person creates. `scopeRaw` is the subject kind's own raw value —
        // the identity `QueryLedger.answer(…)` already relies on, not a second mapping.
        return try priorities.addRule(
            taskID: task.id,
            scopeRaw: rule.subjectKind.rawValue,
            subject: rule.subject,
            verdictRaw: rule.verdict.rawValue,
            undo: undo
        )
    }
}

/// Why a correction could not be written. One case, because there is one reason.
public enum HistoryCorrectionError: Error, Equatable, Sendable {
    /// The affordance was withdrawn, and this is the reason the surface was already drawing.
    case withdrawn(HistoryWithdrawal)
}
