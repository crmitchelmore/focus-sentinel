import Foundation

/// What became of a question that was asked.
///
/// Declared here beside the slot, which is where a question's life is arbitrated. `QueryAnswer`
/// (T119), the `AskedQuestion` row (T126) and `QueryLedger` (T127) all consume this one
/// vocabulary rather than restating it; the persisted column is its raw value, decoded through
/// an exhaustive switch in the shape e03's R-49 established.
public enum AskedQuestionOutcome: String, Sendable, CaseIterable, Codable, Hashable {
    /// "Yes, add it" — a `RuleAuthority.task` rule with verdict `relevant`, plus this receipt,
    /// in one atomic transaction (R-78).
    case answeredRelevant
    /// "No" — the same pair, with rule verdict `unrelated`.
    case answeredUnrelated
    /// "Not now" or Escape. **No rule is written** — there is no answer to record — but the
    /// asking still happened and is still remembered, which is what stops the question coming
    /// back.
    case declined
    /// **The world ended the question; the person did not.** The session ended, the phase left
    /// focus, the priority changed, or a presentation claimed the display while the panel was
    /// still on screen.
    ///
    /// This outcome is written down and it does **not** settle the question — see
    /// `settlesTheQuestion`.
    case expired

    /// Whether this outcome wrote a rule as well as a receipt.
    public var wroteRule: Bool {
        switch self {
        case .answeredRelevant, .answeredUnrelated: true
        case .declined, .expired: false
        }
    }

    /// Whether the person actually answered.
    ///
    /// Read by the fatigue controller: `InterventionPolicy.ignoredQueryBackoff` counts
    /// consecutive questions that were **not** answered, because two unanswered questions is the
    /// point at which the app is talking to itself.
    public var isAnswer: Bool { wroteRule }

    /// **Whether a receipt carrying this outcome ends the asking for good** (focus-qds, U-1).
    ///
    /// The store-level half of the ruling `QuestionEnding.settlesTheQuestion` states. It is a
    /// property of the *stored* value rather than of the code path that wrote it, because
    /// `QueryLedger.isSettled(…)` is gate 11 and gate 11 reads rows, not call stacks — a row
    /// written by a path nobody thought about must still answer this question correctly.
    ///
    /// Three of the four settle, and they are exactly the three a **person** can produce:
    /// "Yes, add it", "No", and "Not now" (which Escape writes). U-1's
    /// sentence is *"every **answered** question is remembered"*, and closing the panel is an
    /// answer — treating a dismissal as nothing happened is what makes an app ask again
    /// tomorrow.
    ///
    /// `expired` is the one that does not, and it is the whole of focus-qds. Going for lunch is
    /// not an answer. A receipt is immutable and gate 11 is consulted before any warrant is
    /// constructed, so settling on an expiry would mean the app spends its single licensed
    /// interruption every time somebody takes a break with a question on screen — and then never
    /// asks again for the life of the commitment. The asking is still written down, because it
    /// happened and `askedCount(…)` is a fact about the day; what it no longer does is answer
    /// the question on the person's behalf.
    public var settlesTheQuestion: Bool {
        switch self {
        case .answeredRelevant, .answeredUnrelated, .declined: true
        case .expired: false
        }
    }
}

/// What happened when an interruption was offered the slot.
public enum SlotOutcome: Sendable, Equatable, Hashable {
    /// It takes the slot.
    case admitted(slot: InterruptionSlot)
    /// The slot is held by something else. Always `.interruptionInFlight`; the case carries the
    /// full reason type so that a surface draws it from the same stack every other silence comes
    /// from.
    case withheld(NudgeSuppressionReason)

    public var slot: InterruptionSlot? {
        switch self {
        case .admitted(let slot): slot
        case .withheld: nil
        }
    }

    public var withholdingReason: NudgeSuppressionReason? {
        switch self {
        case .admitted: nil
        case .withheld(let reason): reason
        }
    }
}

/// **One open interruption at a time, and whoever got there first keeps it** (R-84a as amended
/// by U-2).
///
/// A value type with pure transitions, like every other machine in this programme.
///
/// | offered | slot open | slot held by a query | slot held by an accusation |
/// |---|---|---|---|
/// | a **query** | admitted | withheld | withheld |
/// | an **accusation** | admitted | **withheld** | admitted (the ladder's own escalation) |
///
/// ## The asymmetry this table used to have, and why it is gone
///
/// The accusation used to win. An accusation offered against an open question was *always*
/// admitted, closing the question as `declined` and reporting it as a `PreemptedQuery` — on the
/// argument that *"you are off task"* outranks *"is this part of it?"*, and that a question about
/// the very application somebody had drifted into would be the app arguing with itself.
///
/// Seven repair rounds found roughly **eleven** defects living in that one interaction, and the
/// user ruled the mechanism out rather than patching its eleventh instance (U-2). Preemption is
/// gone: a question that is on the screen keeps the slot, and **the accusation waits**. It is not
/// lost — the ladder holds its rung, the mandate is still live, and the next judgement offers it
/// again the moment the question is answered or expires.
///
/// It is also better product than the rule it replaces. The person is not interrupted twice about
/// two different things in the same moment, and the cheap teaching interaction U-1 licensed the
/// app to interrupt for is never taken off the screen half-answered.
///
/// What survives unchanged is the reason the slot exists at all: two panels on screen at once is
/// the behaviour that makes people uninstall.
public struct InterruptionSlot: Sendable, Equatable, Hashable {
    /// Who holds the slot.
    public enum Holder: Sendable, Equatable, Hashable {
        case nobody
        case query(QueryWarrant)
        case accusation(LadderRung)
    }

    public let holder: Holder

    public init(holder: Holder = .nobody) {
        self.holder = holder
    }

    /// Nothing is on screen.
    public static let open = InterruptionSlot()

    public var isOpen: Bool { holder == .nobody }

    /// The question currently on screen, if one is.
    public var openQuery: QueryWarrant? {
        switch holder {
        case .query(let warrant): warrant
        case .nobody, .accusation: nil
        }
    }

    /// The accusation rung currently on screen, if one is.
    public var openAccusation: LadderRung? {
        switch holder {
        case .accusation(let rung): rung
        case .nobody, .query: nil
        }
    }

    /// Offer the slot to a **question**.
    ///
    /// Withheld against anything already holding it — including another question, because a
    /// second panel over the first is the same failure as a panel over a nudge.
    public func offering(_ warrant: QueryWarrant) -> SlotOutcome {
        switch holder {
        case .nobody:
            .admitted(slot: InterruptionSlot(holder: .query(warrant)))
        case .query, .accusation:
            .withheld(.interruptionInFlight)
        }
    }

    /// Offer the slot to an **accusation rung**.
    ///
    /// Admitted against an empty slot, and against an accusation — that second case is the ladder
    /// escalating onto its own rung, and `LadderMachine` is what decides whether it may.
    ///
    /// **Withheld against an open question** (U-2). This is where preemption used to happen and
    /// the single most important line of the scope cut: the accusation does not displace the
    /// question, it waits for it. The rung is not consumed by being withheld — `LadderMachine`
    /// records no delivery, the escalation clock does not start, and the next judgement offers the
    /// same rung again.
    public func offering(_ rung: LadderRung) -> SlotOutcome {
        switch holder {
        case .nobody, .accusation:
            .admitted(slot: InterruptionSlot(holder: .accusation(rung)))
        case .query:
            .withheld(.interruptionInFlight)
        }
    }

    /// The slot after whatever held it has been dismissed, answered or has expired.
    public func released() -> InterruptionSlot { .open }
}
