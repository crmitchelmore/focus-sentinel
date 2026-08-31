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
/// answers the other two — **and now the first as well** (focus-h0s). `recordsAnExpiry` below is
/// what makes the door total: the record was the one of the three that was still a separate call,
/// four exits made it and the fifth forgot, and forgetting it meant a keyboard shortcut aimed at
/// the menu-bar glyph silently destroyed a question the person was looking at.
///
/// Its real work is being `CaseIterable`: `NudgeHost` has exactly one door out of an open
/// question, every case of this enum is a way through that door, and a test walks `allCases` and
/// drives each one. A further exit added without a driver is a non-exhaustive switch, which is a
/// compile error rather than a sixth round.
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
    /// **F-81: the person asked for their screen back.** Not the world moving on and not an
    /// answer — `hideOverlays()` writes no receipt and no rule, because "hide" is a request about
    /// the screen rather than a thing to tell the app, and the question is still unanswered and
    /// will be offered again.
    ///
    /// It used to travel as `worldMovedOn`, which was a false label the moment the exit acquired
    /// a consequence: `worldMovedOn` now means *write the expiry*, and `hideOverlays()` must not.
    /// It was harmless only for as long as nothing read the label — the panel happened to be
    /// ordered out first, so `readingNow` came back `unknowable` and `QuestionLedgerPolicy`
    /// refused the write for a reason nobody had chosen. A rule that holds by accident of
    /// statement order is the shape this type exists to retire.
    case screenReclaimed

    /// **Whether ending this way writes the question down as expired** — the third of the three
    /// things an exit has to do, and the one that was still done by hand (focus-h0s).
    ///
    /// `QuestionExit`'s own header names the class: *"an exit is a place where three things have
    /// to happen together — the record, the slot, and the surface — and each repair fixed the two
    /// the author was thinking about"*. `NudgeHost.endOpenQuestion(_:)` did the slot and the
    /// surface; the record was a separate `expireOpenQuestion()` that four call sites remembered
    /// and a fifth did not. `resolve(_:snoozeDuration:)` — Ctrl-Cmd-R aimed at the glyph, or any
    /// correction pressed on an accusation while a question stood on the panel — destroyed a
    /// question the person could see, wrote nothing, and left the interruption charged.
    ///
    /// So the answer moves onto the exit itself, where it is a property of the *kind* of ending
    /// rather than a line a caller can omit. `answered` writes through `QueryLedger.answer(…)` in
    /// one transaction with the rule; `surfaceWentOutOfReach` and `neverDelivered` are un-askings
    /// and R-81 forbids a receipt for a question that reached nobody; `screenReclaimed` is F-81.
    /// One case is left, and it is the one that means *the question was on screen and the world
    /// ended it*.
    public var recordsAnExpiry: Bool {
        switch self {
        case .worldMovedOn: true
        case .answered, .surfaceWentOutOfReach, .neverDelivered, .screenReclaimed: false
        }
    }

    /// **Whether ending this way leaves the delivered row saying nobody did anything about it**
    /// (focus-gmr, R-79).
    ///
    /// The `InterventionRecord` a delivery writes gains exactly one field afterwards: what the
    /// person did. Nothing filled it in for a question that ended any way other than an answer,
    /// so a question the person really opened and really read stayed `delivered` with
    /// `outcome = nil` **for ever** — a row that says the app interrupted somebody and never says
    /// how it turned out. `InterventionOutcome.ignored` is the value that already means *"nothing
    /// happened at all"*, and it is what `InterventionPolicy.ignoredQueryBackoff` is named for.
    ///
    /// | exit | fills the outcome in | why |
    /// |---|---|---|
    /// | `worldMovedOn` | **yes** | it was on screen, the world ended it, and nobody pressed anything |
    /// | `screenReclaimed` | **yes** | F-81 — the person asked for their screen back, which is not an answer and is not nothing having happened to the interruption |
    /// | `answered` | no | `QueryLedger.answer(…)` has already completed the row with `.answered` |
    /// | `surfaceWentOutOfReach` | no | the delivery is *withdrawn*; an outcome on a row that is being taken off the budget would be the app saying somebody ignored something it has just said reached nobody |
    /// | `neverDelivered` | no | there is no row to complete |
    ///
    /// Stated here rather than at the call site for `recordsAnExpiry`'s reason: it is a property
    /// of the kind of ending, and a line a caller can omit is a line four callers remember and a
    /// fifth does not.
    public var leavesTheInterruptionUnanswered: Bool {
        switch self {
        case .worldMovedOn, .screenReclaimed: true
        case .answered, .surfaceWentOutOfReach, .neverDelivered: false
        }
    }

    /// **Whether `FatigueController`'s run of unanswered questions hears about it** (focus-fwy,
    /// R-83, U-1).
    ///
    /// `InterventionPolicy.ignoredQueryBackoff` is the bound on *the app is asking and nobody is
    /// answering*, and until focus-fwy the controller was told about a question from exactly one
    /// place — `NudgeHost.answer(_:)`, which reduces `.queryResolved(answer.outcome)`. So the run
    /// advanced only for a question the person **pressed something on**: "Not now" and Escape
    /// extend it, because `AskedQuestionOutcome.declined` is not an answer. A question they never
    /// touched advanced nothing at all.
    ///
    /// One exit answers `true`, and it is the accusation's own `RungExit.screenReclaimed` stated
    /// for this half: ⌃⌘H is the person saying *take this off my screen*, the question was in
    /// front of them, and F-81's ruling is that it is **still unanswered and will be offered
    /// again**. Nothing bounded how often, which is what this is.
    ///
    /// The other three are `false` and each for its own reason:
    ///
    /// * `answered` — `answer(_:)` has already reduced the event that carries what they said.
    /// * `surfaceWentOutOfReach` and `neverDelivered` — un-askings. R-81's rule is that a nudge
    ///   nobody could see did not happen, and a backoff advanced by one would be the app punishing
    ///   the person for a display it could not fit on.
    /// * `worldMovedOn` — *"going for lunch is not an answer"* is focus-qds's ruling and it cuts
    ///   both ways: a session ending, a break or a commitment change is the world ending the
    ///   question, not the person ignoring it. It is also the clause that has to be `false` for
    ///   the arithmetic to hold at all — `NudgeHost.sessionEnded()` reduces
    ///   `FatigueEvent.sessionEnded`, which resets both runs, **before** it closes the surfaces, so
    ///   a run advanced here would dirty one that had just been cleared.
    public var countsAsAnUnansweredQuestion: Bool {
        switch self {
        case .screenReclaimed: true
        case .answered, .worldMovedOn, .surfaceWentOutOfReach, .neverDelivered: false
        }
    }
}
