import Foundation

/// **What a surface can say about whether a person could read the question on it** (U-1).
///
/// Three values, not two, and the third is the one the round-1 fix got wrong. A surface that has
/// gone — a panel ordered out, a popover closed — cannot be re-read, and the old code answered
/// `true` for exactly that case (`guard panel.isVisible else { return true }`), which meant every
/// question routed to a surface that was never visible in the first place was "readable" for its
/// whole life. Under default-deny the honest answer to "can you prove a person could read it?"
/// when the surface is gone is **no**, and that is what `unknowable` is for.
public enum SurfaceReadability: String, Sendable, CaseIterable, Codable, Hashable {
    /// Proven: the surface was on screen, on a display, with every offered action in reach.
    case readable
    /// Proven otherwise: it was on screen and something the person needed was not.
    case notReadable
    /// Cannot be established now. Never evidence of readability.
    case unknowable
}

/// **How a question stopped being open.**
///
/// The three end-paths a receipt can be written from. `answered` is the person's own click —
/// through `QueryLedger.answer(…)`, which writes the rule and the receipt as one transaction —
/// and the other two are the app ending a question nobody answered.
public enum QuestionEnding: String, Sendable, CaseIterable, Codable, Hashable {
    /// The person clicked one of the three answers, or pressed Escape (which is "Not now").
    case answered
    /// The session ended, the phase left focus, the priority changed, or a presentation claimed
    /// the display.
    case expired

    /// **What this ending means for askability** (focus-qds, U-1).
    ///
    /// Never-ask-twice is a promise about questions that were **answered**, and this is where
    /// the programme says so instead of leaving it to be inferred from which branch a receipt
    /// happened to be written down.
    ///
    /// | ending | settles | why |
    /// |---|---|---|
    /// | `answered` | **yes** | the person chose. "Yes, add it", "No", and "Not now" are all choices, and Escape is "Not now". U-1: *"every answered question is remembered"*. |
    /// | `expired` | **no** | the world ended it. A break, a session ending, a new commitment, a projector. **An expiry is not an answer**, and settling on one would spend the app's single licensed interruption on a question the person never saw the end of — permanently, because the receipt is immutable and gate 11 reads it before any warrant is built. |
    ///
    /// The frequency argument is what makes the third row urgent rather than theoretical.
    /// `sessionEnded()`, `phaseLeftFocus()` and `priorityChanged()` acquired their first callers
    /// in this epic, so the expiry channel went from unreachable to *the most ordinary way a
    /// question ends*: taking a break settles it. That is the burn U-1 names — the app spends its
    /// one chance to ask and never asks again — arriving through the path a person walks several
    /// times a day.
    public var settlesTheQuestion: Bool {
        switch self {
        case .answered: true
        case .expired: false
        }
    }
}

/// Why a question was **not** written down, and therefore comes back.
public enum QuestionStaysAskableReason: String, Sendable, CaseIterable, Codable, Hashable {
    /// It never reached a surface that can carry a question at all.
    case neverReachedAQuestionSurface
    /// It reached one, and that surface never showed it to anybody.
    case neverReachedAReadableSurface
    /// It was readable once, and nothing can now prove it was readable at the end.
    case readabilityCouldNotBeProven
}

/// What the ledger does about a question that has ended.
///
/// **Three outcomes, not two, and the third is focus-qds** (U-1). "Was it written down?" and
/// "is it still askable?" used to be the same question, and they are not: a question the person
/// saw and did not answer *happened* — it belongs in the record of the day — and it is still
/// unanswered. Collapsing the two meant every expiry silenced its subject for the life of the
/// commitment.
public enum QuestionLedgerAction: Sendable, Equatable, Hashable {
    /// Write the immutable receipt **and settle the question**: it is never asked again for
    /// this priority. Reached only from an ending `QuestionEnding.settlesTheQuestion` allows.
    case settle
    /// Write a receipt that records the asking and **leaves the question askable**.
    ///
    /// The person could read it at both ends — so the asking is a fact, and `askedCount(…)`
    /// counts it — and they never answered it. An expiry is not an answer.
    case recordUnanswered
    /// Write nothing at all. Nobody could be shown the question, so nothing about it happened
    /// that is worth remembering, and it stays askable.
    case stayAskable(QuestionStaysAskableReason)

    /// Whether a row is inserted.
    public var writesAReceipt: Bool {
        switch self {
        case .settle, .recordUnanswered: true
        case .stayAskable: false
        }
    }

    /// Whether the row that is inserted ends the asking. `false` for every action that writes
    /// nothing, and for the one that writes an unanswered receipt.
    public var settlesTheQuestion: Bool { self == .settle }
}

extension NudgeSurface {
    /// **Whether a question can be asked here at all.**
    ///
    /// The panel and the popover row. Never the menu-bar glyph, which has no answer affordance,
    /// and never a notification — R-82's ruling that *a question is never a notification*, because
    /// a question answered from a summary three hours later is a question about a moment that has
    /// passed.
    public var canCarryAQuestion: Bool {
        switch self {
        case .panel, .popoverBadge: true
        case .menuBar, .notification: false
        }
    }
}

/// **Whether a question that has ended is written down** — the whole of never-ask-twice, and the
/// whole of the hazard on its other side (U-1, R-78, focus-kby).
///
/// ## Why this is a pure function in `FocusCore` and not an `if` in the host
///
/// Every receipt in `QueryLedger` is immutable and `hasAsked(…)` is gate 11 of the suppression
/// stack, so a receipt written about a question nobody saw does not merely mis-record history —
/// it **permanently silences that question** for the life of the priority. U-1 licenses the app
/// to interrupt on `uncertain` precisely because the interruption is one cheap click that teaches
/// it; spending that click on a surface the person never read is the app burning its licence.
///
/// The first attempt at this rule lived in the application target as a private method, and no
/// test target can import that target. The regression test was therefore a **source scan**: it
/// grepped for the substrings the method was spelled with. An adversarial lens replaced the
/// method's body with `return true`, reinstating every burn path, and all 824 tests stayed green
/// — because a scan for spelling cannot see behaviour. So the decision is a value-returning
/// function over typed inputs, `QueryLedger` consults it at the write, and the tests instantiate
/// the real thing over the whole cross product.
///
/// ## The rule, in two sentences
///
/// A person's own answer always counts; anything else is written down only when the surface was
/// **proven readable when the question went up and proven readable when it came down**. And
/// writing it down is not the same as settling it: only an ending
/// `QuestionEnding.settlesTheQuestion` allows ends the asking, so a question the world
/// interrupted is remembered *and* comes back (focus-qds).
public enum QuestionLedgerPolicy {
    /// - Parameters:
    ///   - surface: where the question was routed, or `nil` if it never reached one.
    ///   - readingAtAsk: what the surface said when the question was put on it.
    ///   - readingNow: what the surface says at the moment it ends.
    ///   - ending: which path is ending it.
    public static func decide(
        surface: NudgeSurface?,
        readingAtAsk: SurfaceReadability,
        readingNow: SurfaceReadability,
        ending: QuestionEnding
    ) -> QuestionLedgerAction {
        // **An answer is its own proof of readability**, and it is the only proof that needs no
        // instrument: a person cannot click "Yes, add it" on a panel they could not see. This
        // path also writes the *rule*, so refusing the receipt here would leave the app having
        // learned the answer and forgotten the asking — the one state R-78's transaction exists
        // to make impossible.
        if ending == .answered { return .settle }

        guard let surface, surface.canCarryAQuestion else {
            return .stayAskable(.neverReachedAQuestionSurface)
        }
        guard readingAtAsk == .readable else {
            return .stayAskable(.neverReachedAReadableSurface)
        }
        guard readingNow == .readable else {
            return .stayAskable(.readabilityCouldNotBeProven)
        }
        // Readable at both ends, so the asking is a fact and is written down. Whether it also
        // **ends** the asking is a different question with a different answer, and this is the
        // line focus-qds turns on: an accusation that replaced the question escalated it, and a
        // break did not.
        return ending.settlesTheQuestion ? .settle : .recordUnanswered
    }
}
