import Foundation

/// **What the nudge panel is carrying** (focus-v0u).
///
/// The panel's content is an `AnyView`, which is opaque: nothing outside the controller could tell
/// a panel showing a question from one showing an accusation from one showing nothing. That is how
/// the most user-visible defect of this epic stayed invisible — a question left fully live and
/// fully clickable on a panel the nudge loop had already forgotten — so the panel says which of
/// the two it is holding, and the contradiction becomes a reading anybody can take.
public enum NudgePanelKind: String, Sendable, CaseIterable, Codable, Hashable {
    /// A `QueryPanelView`: *"Is this part of &lt;task&gt;?"*, with the three answers on it.
    case question
    /// An `AccusationPanelView`: the rung's sentence, with the correction ladder on it.
    case accusation
}

/// **Every way an open question can end, enumerated once** (focus-v0u, focus-7w3, focus-qds,
/// focus-kby, U-1).
///
/// ## Why this type exists, and it is not the same reason `QuestionEnding` exists
///
/// Five consecutive rounds of this epic each found a **different** exit from the open-question
/// lifecycle individually wrong, and each was repaired individually:
///
/// | round | the exit | what it did |
/// |---|---|---|
/// | focus-qds | the world moved on | a break or a session ending **settled** a question nobody answered |
/// | focus-kby | the badge | a question routed to a popover nobody opened was counted as asked |
/// | focus-7w3 | a preemption | every displacement settled, including one the person never saw |
/// | focus-vpu | the ask itself | a question on a panel whose answers were out of reach was written down |
/// | focus-v0u | a preemption onto **another** surface | the question's panel was left on screen, fully live, while the host forgot it — so the person's click was dropped in a `guard` and the question was asked again |
///
/// Five different exits, five different mistakes, one class: **an exit is a place where three
/// things have to happen together** — the record, the slot, and the surface — and each repair
/// fixed the two the author was thinking about.
///
/// **Two of those five rows were the same exit** — a preemption — and U-2 deleted it. An
/// accusation can no longer take a question's ask or its surface, so the door it went through is
/// gone rather than guarded, and with it the only exit that did not release the slot and the only
/// one that handed its surface to somebody else in the same turn. What is left is four exits that
/// all mean the same three things: write the record, release the slot, take the surface down.
///
/// `QuestionEnding` already answers the first: what the ledger writes and whether it settles. This
/// answers the other two, and its real work is being `CaseIterable`: `NudgeHost` has exactly one
/// door out of an open question, every case of this enum is a way through that door, and a test
/// walks `allCases` and drives each one. A fifth exit added without a driver is a non-exhaustive
/// switch, which is a compile error rather than a sixth round.
public enum QuestionExit: String, Sendable, CaseIterable, Codable, Hashable {
    /// The person clicked one of the three answers, or pressed Escape — which is *"Not now"*, and
    /// is an answer.
    case answered
    /// The session ended, the phase left focus, or the commitment changed.
    case worldMovedOn
    /// The display changed under the question and its answers went out of reach.
    case surfaceWentOutOfReach
    /// The ask gave itself up before it reached anybody: an unreadable panel, or a route to a
    /// surface that cannot carry a question at all.
    case neverDelivered
}
