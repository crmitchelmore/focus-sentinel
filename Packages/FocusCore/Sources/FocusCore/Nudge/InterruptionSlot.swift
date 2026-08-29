import Foundation

/// What became of a question that was asked.
///
/// Declared here because the slot is the **first** thing in the programme that can close a
/// question, and a preemption has to be able to say which outcome it wrote. `QueryAnswer`
/// (T119), the `AskedQuestion` row (T126) and `QueryLedger` (T127) all consume this one
/// vocabulary rather than restating it; the persisted column is its raw value, decoded through
/// an exhaustive switch in the shape e03's R-49 established.
public enum AskedQuestionOutcome: String, Sendable, CaseIterable, Codable, Hashable {
    /// "Yes, add it" — a `RuleAuthority.task` rule with verdict `relevant`, plus this receipt,
    /// in one atomic transaction (R-78).
    case answeredRelevant
    /// "No" — the same pair, with rule verdict `unrelated`.
    case answeredUnrelated
    /// "Not now", Escape, or a preemption. **No rule is written** — there is no answer to
    /// record — but the asking still happened and is still remembered, which is what stops the
    /// question coming back.
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
    /// "Yes, add it", "No", and "Not now" (which Escape and a preemption both write). U-1's
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

/// A question that was on screen when an accusation arrived.
///
/// It is **closed**, not dropped: the receipt is written with `outcome == .declined`, so the
/// person is never asked it again. Losing the asking because something more urgent happened
/// would be exactly the bug never-ask-twice exists to prevent — and it would be invisible,
/// because the symptom is a question that comes back weeks later.
public struct PreemptedQuery: Sendable, Equatable, Hashable {
    public let warrant: QueryWarrant
    /// Always `.declined`. A preemption is not an answer, and the type says so by having no
    /// other value to carry.
    public let outcome: AskedQuestionOutcome

    fileprivate init(warrant: QueryWarrant) {
        self.warrant = warrant
        self.outcome = .declined
    }
}

/// What happened when an interruption was offered the slot.
public enum SlotOutcome: Sendable, Equatable, Hashable {
    /// It takes the slot. `preempted` names the question that was closed to make room, when
    /// there was one.
    case admitted(slot: InterruptionSlot, preempted: PreemptedQuery?)
    /// The slot is held by something that outranks this. Always `.interruptionInFlight`; the
    /// case carries the full reason type so that a surface draws it from the same stack every
    /// other silence comes from.
    case withheld(NudgeSuppressionReason)

    public var slot: InterruptionSlot? {
        switch self {
        case .admitted(let slot, _): slot
        case .withheld: nil
        }
    }

    public var preempted: PreemptedQuery? {
        switch self {
        case .admitted(_, let preempted): preempted
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

/// **One open interruption at a time**, and the accusation wins (R-84a).
///
/// A value type with pure transitions, like every other machine in this programme. The
/// asymmetry is the whole ruling:
///
/// | offered | slot open | slot held by a query | slot held by an accusation |
/// |---|---|---|---|
/// | a **query** | admitted | withheld | **withheld** |
/// | an **accusation** | admitted | admitted, **closing the query as `declined`** | admitted (the ladder's own escalation) |
///
/// Two reasons, and neither is about tidiness. *"You are off task"* outranks *"is this part of
/// it?"* — a person who has drifted needs the more important sentence, and a question about
/// the very application they have drifted into would be the app arguing with itself. And two
/// panels on screen at once is the behaviour that makes people uninstall.
///
/// **The reverse never happens.** There is no code path by which a question closes an
/// accusation, which is a fourth small structural fact beside R-76's four: even the surface
/// arbitration runs one way.
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
            .admitted(slot: InterruptionSlot(holder: .query(warrant)), preempted: nil)
        case .query, .accusation:
            .withheld(.interruptionInFlight)
        }
    }

    /// Offer the slot to an **accusation rung**.
    ///
    /// Always admitted. An open question is closed as `declined` and reported, so its receipt
    /// is written and it is never asked again; an open accusation is simply replaced, because
    /// that is the ladder escalating and `LadderMachine` decides whether it may.
    public func offering(_ rung: LadderRung) -> SlotOutcome {
        let taken = InterruptionSlot(holder: .accusation(rung))
        switch holder {
        case .nobody, .accusation:
            return .admitted(slot: taken, preempted: nil)
        case .query(let warrant):
            return .admitted(slot: taken, preempted: PreemptedQuery(warrant: warrant))
        }
    }

    /// The slot after whatever held it has been dismissed, answered or has expired.
    public func released() -> InterruptionSlot { .open }
}
