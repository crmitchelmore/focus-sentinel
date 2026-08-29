import Foundation

/// **Why an accusation did or did not earn the right to settle the question it displaced**
/// (focus-7w3, R-84a, U-1).
///
/// A reason rather than a `Bool`, because the four ways it fails are four different things that
/// happened to the person, and a caller that could not tell them apart would log "not credited"
/// for all of them.
public enum PreemptionCreditReason: String, Sendable, CaseIterable, Codable, Hashable {
    /// The accusation reached a surface, named the same subject, and offered the correction.
    /// This is the only value that settles.
    case credited
    /// The accusation was never delivered: no surface was available, the panel it was put on had
    /// its actions out of reach, or the notification was suppressed. The person saw nothing.
    case accusationWasNotDelivered
    /// It was delivered somewhere that offers no correction — the menu-bar glyph, the popover
    /// badge. There is nothing on it to press, so nothing richer was offered.
    case surfaceOffersNoCorrection
    /// It named a different subject, or named nobody. A mixed accusation names nobody by
    /// construction.
    case aDifferentSubject
}

/// **Whether a preemption may spend the one ask** (focus-7w3, U-1).
///
/// ## The defect this exists to close
///
/// `QuestionEnding.preempted.settlesTheQuestion` is `true`, and the justification written beside
/// it is R-84a: *the app replaced the question with an accusation about the same subject, on the
/// same surface, offering "this is relevant" — a strictly richer affordance than the question's.
/// The chance to be taught was escalated, not lost.*
///
/// That justification was enforced **nowhere**. `NudgeHost.accuse(…)` closed the open question on
/// its first line, before it knew whether a surface was even available, before the panel's
/// actions were checked for reach, and before the notification had been delivered or suppressed —
/// and nothing anywhere compared the accusation's subject with the question's. So every
/// preemption settled, including one the person never saw: the app spent its single licensed
/// interruption on a question that was taken off the screen and replaced with nothing.
///
/// It is not a rare path. The preemption channel was measured as **more frequent** than the lunch
/// channel it replaced, which is the burn U-1 names arriving through an ordinary route.
///
/// ## The rule
///
/// A pure function over typed inputs, in `FocusCore` where a test can instantiate it, for exactly
/// the reason `QuestionLedgerPolicy` is: the first version of that rule lived in the application
/// target as a private method, its regression test was a **source scan**, and an adversarial lens
/// replaced the body with `return true` while 824 tests stayed green. A scan for spelling cannot
/// see behaviour.
///
/// Under default-deny the question is only settled where all three clauses of the justification
/// actually hold. Anything else ends it as `expired`, which `QuestionLedgerPolicy` already
/// handles correctly: the asking is written down if the person could read it at both ends, and
/// the question **comes back**.
public enum PreemptionCredit {
    /// - Parameters:
    ///   - questionSubject: the subject the question named, as `QueryWarrant.subject.identifier`.
    ///   - accusationSubject: the subject the rung names. `nil` for a mixed accusation, which
    ///     names nobody.
    ///   - deliveredOn: the surface the accusation actually reached, or `nil` if it reached none.
    ///     A deferral, an unreachable panel and a suppressed notification are all `nil`: in every
    ///     one of them the person was shown nothing.
    public static func decide(
        questionSubject: String,
        accusationSubject: String?,
        deliveredOn surface: NudgeSurface?
    ) -> PreemptionCreditReason {
        guard let surface else { return .accusationWasNotDelivered }
        guard surface.offersACorrection else { return .surfaceOffersNoCorrection }
        guard let accusationSubject, !accusationSubject.isEmpty else { return .aDifferentSubject }
        guard accusationSubject == questionSubject else { return .aDifferentSubject }
        return .credited
    }

    /// How the displaced question ends, given what the accusation managed to do.
    ///
    /// `.preempted` settles it; `.expired` does not. Everything downstream of this — whether a
    /// receipt is written at all, whether `askedCount(…)` counts it, whether gate 11 will ever
    /// let the question be asked again — is `QuestionLedgerPolicy`'s, unchanged.
    public static func ending(for reason: PreemptionCreditReason) -> QuestionEnding {
        reason == .credited ? .preempted : .expired
    }
}

extension NudgeSurface {
    /// **Whether an accusation placed here offers the correction R-84a's argument rests on.**
    ///
    /// The whole justification for settling a question on a preemption is that the person was
    /// handed something *richer* in its place: an accusation with *"this is relevant"* on it. A
    /// surface with nothing to press offers nothing richer, and a preemption onto one is the
    /// question disappearing.
    ///
    /// | surface | offers a correction | what is actually drawn |
    /// |---|---|---|
    /// | `panel` | **yes** | `AccusationPanelView`, with the rung's full action set |
    /// | `notification` | **yes** | the presentation's actions, as notification buttons |
    /// | `menuBar` | no | a glyph. There is nothing on it to press |
    /// | `popoverBadge` | no | a badge row. It carries a *question*, not the correction ladder |
    public var offersACorrection: Bool {
        switch self {
        case .panel, .notification: true
        case .menuBar, .popoverBadge: false
        }
    }
}
