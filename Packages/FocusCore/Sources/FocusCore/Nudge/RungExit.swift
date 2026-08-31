import Foundation

/// **Every way a delivered rung can end, enumerated once** (focus-s4m, focus-fwy, R-80, R-81).
///
/// ## Why this type exists, and it is `QuestionExit`'s twin exactly
///
/// A question's ending has been a closed, `CaseIterable` vocabulary since focus-v0u: five cases,
/// one door — `NudgeHost.endOpenQuestion(_:)` — and two properties, `recordsAnExpiry` and
/// `leavesTheInterruptionUnanswered`, that an exhaustive `switch` cannot skip. Every consequence
/// of an ending is a property of the *kind* of ending rather than a line a caller can omit,
/// because five consecutive rounds of this epic each found a different exit individually wrong
/// and each was repaired individually.
///
/// **A rung's ending was not.** It was four hand-written doors — a correction, a hidden overlay,
/// a presentation, a display that changed underneath — plus two nobody had counted, and the three
/// things an ending has to do were distributed across them by memory:
///
/// | door | the ladder | the row | the backoffs |
/// |---|---|---|---|
/// | `resolve(_:snoozeDuration:)` | de-escalated, or `.rungIgnored` | completed | both told |
/// | `accuse(…)` replacing a rung | — | completed `.ignored` | **neither told** (focus-fwy) |
/// | `hideOverlays()` | **nothing** | completed `.ignored` | neither told |
/// | `withdrawForPresentation()` | **nothing** | completed `.ignored` | neither told |
/// | `displaysChanged()` | `undeliver(at:)` | withdrawn | — |
/// | `applicationWillTerminate()` and the session's own endings | de-escalated, or nothing at quit | completed `.ignored` | — |
///
/// Two of those rows were user-reachable defects. `hideOverlays()` — the ⌃⌘H *Hide overlays*
/// command — took the panel off the screen and told the ladder nothing, so the ladder stayed
/// `.engaged(rung: .panel, deliveredAt:)`; `LadderMachine.arrive(_:)` returns to `.idle` only when
/// the standing rung is the top **and** the subject differs, and on the same subject
/// `candidate(at:budgetPermits:)` answers `rung.escalated(for:)`, which is `nil` at the top. So
/// `NudgeDecider.accuse(…)` turned that `nil` into `.silent(.budgetExhausted)` and **pressing
/// ⌃⌘H permanently silenced the only rung that says anything.** `withdrawForPresentation()` has
/// the same hole, and its own documentation promised the opposite: *"during a presentation the app
/// is mute rather than quietly escalating, and when the presentation ends the ladder resumes at
/// the rung it never left"*.
///
/// ## The three questions, and why each is answered here rather than at the call site
///
/// An ending has to settle three things, and they are the ladder's, the log's, and the two
/// backoffs':
///
/// * `takesBackTheDelivery` — was this a delivery at all, or is R-81 taking it back?
/// * `leavesTheInterruptionUnanswered` — does the row this rung wrote get its one remaining
///   field, *what the person did*?
/// * `countsAsAnIgnoredAccusation` — do `LadderMachine`'s run and `FatigueController`'s
///   session-wide run, both bounded by `InterventionPolicy.ignoredAccusationBackoff`, hear about
///   it?
///
/// Each is an exhaustive `switch`, so a seventh door does not compile until somebody has ruled on
/// all three. That is the whole of the repair: the doors were never the problem, the *by-hand
/// parity between them* was, and it is the shape the charter counts at 41% of this backlog.
public enum RungExit: String, Sendable, CaseIterable, Codable, Hashable {
    /// **The person pressed something on it** — a correction, a snooze, a pause, a dismissal, or
    /// the keyboard equivalent of one.
    ///
    /// The only exit whose consequences are not this type's, and deliberately so:
    /// `NudgeHost.resolve(_:snoozeDuration:)` knows *which* correction it was, writes the outcome
    /// that names it, tells `FatigueController` that outcome, and de-escalates the ladder — or,
    /// for the one action that is not an answer, reduces `.rungIgnored`. All three are already
    /// settled by the time the rung's surface comes down, so this exit adds nothing and must not:
    /// a second `complete(_:recordID:)` would be refused, and a second `.rungIgnored` would count
    /// one dismissal twice.
    case answered
    /// **The loop raised another rung in this one's place.**
    ///
    /// Both halves of `accuse(…)`: the rung that lands on a surface and takes this one's place,
    /// and the rung whose route reached nobody at all — because whether the *new* rung found a
    /// surface is a fact about the new rung, and this one is over either way. The ordinary
    /// escalation is one of these: the glyph is standing when the panel rung lands.
    ///
    /// **The row is completed and neither backoff is told, and the second half of that is
    /// measured rather than argued** (focus-fwy, focus-f2a). The bead asks for both, on the
    /// ground that a person who never touches a nudge advances neither run. Driven, it puts the
    /// app back under the floor focus-f2a raised: two panel rungs the person drifted away from
    /// trip `InterventionPolicy.ignoredAccusationBackoff`, `FatigueController` holds accusations
    /// for `backoffSpan`, and the ladder — standing at `.engaged(.ambient, …)` with only an
    /// escalation left to offer — answers `nil` from `candidate(at:budgetPermits:)`, which
    /// `NudgeDecider.accuse(…)` turns into `.silent(.budgetExhausted)`. **The glyph goes with it**,
    /// though F-63's backoff exempts the ambient rung by name. Measured on the shipping
    /// composition root: the silent-and-visual deck stopped speaking after five drifts with
    /// `accusationsToday == 0`, and the lens's own sixteen-drift day showed the person nothing at
    /// all on **eleven** of them.
    ///
    /// That is `LadderState`'s missing `SilenceSubject` (focus-628) and the ladder's own hold
    /// (focus-50m) reached through a new door, and it has to be repaired before this ending may
    /// advance a backoff. Until then the honest line is the one that survives the measurement:
    /// **the backoffs count the endings the PERSON caused, and a replacement is one the APP
    /// caused** — the loop took the panel down to raise something else, and an app that read its
    /// own escalation as *"you are ignoring me"* would be talking about itself. `screenReclaimed`
    /// is on the other side of that line and is the case this vocabulary advances.
    case replaced
    /// **F-81: the person asked for their screen back.** ⌃⌘H, *Hide overlays*.
    ///
    /// `QuestionExit.screenReclaimed`'s twin, and it is given the same treatment for the same
    /// reason: the nudge was on the screen, the person saw it — they pressed a key to make it go
    /// away — and they answered nothing. So the delivery stands, the row is completed `.ignored`,
    /// and both backoffs hear about it. It is **not** a take-back: withdrawing the row would say
    /// nobody was shown anything, which is false, and returning the ladder to the state before the
    /// delivery would put the same panel back in front of them at the next mandate — the app
    /// arguing with the one command it has for *stop showing me things*.
    ///
    /// What it must not do is nothing, which is what it did.
    case screenReclaimed
    /// **R-84: a presentation claimed the display and the app took its overlays off it.**
    ///
    /// The app withdrew this, not the person, and nobody could have answered it once the overlay
    /// was gone — so R-81 applies exactly as it does at the show: the delivery is taken back, the
    /// escalation clock stops, the day's budget is refunded, and the same rung is offered again
    /// when the presentation ends. That is what `NudgeHost.withdrawForPresentation()` has always
    /// documented and never done.
    case presentationWithdrew
    /// **focus-56y: the display changed under a panel and stranded the corrections on it.**
    ///
    /// The one exit that already had its take-back, and the row this type's table is calibrated
    /// against: undocking, a projector, Sidecar or a resolution change leaves a sticky panel
    /// whose actions are off the edge of the screen. Unanswerable is undelivered, whether it
    /// became unanswerable in the first millisecond or the first minute.
    case displayStranded
    /// **The world ended under it** — the session ended, the phase left `.focus`, the commitment
    /// changed, or the application quit.
    ///
    /// The exit nobody had counted, and the reason it is worth a case of its own is the quit: the
    /// other three de-escalate the ladder on their way past, and `applicationWillTerminate()`
    /// tells it nothing at all. Neither backoff may hear about any of them — a person who ended
    /// their session did not ignore a nudge, and counting it would have `sessionEnded()` reset
    /// `FatigueController`'s run and then immediately dirty it again — but the row still gets its
    /// outcome, which is focus-gmr's ruling and the whole reason quit reaches this loop at all.
    case worldMovedOn

    /// **Whether this ending means the rung was never delivered** (R-81, focus-56y, focus-mfc).
    ///
    /// R-81 is that a rung nobody could see does not advance the ladder, and it has two moments:
    /// the show, where `SurfaceRouter` and the readability guard enforce it, and *afterwards*,
    /// where a panel is deliberately sticky (R-89) and the display it was placed on is not.
    /// `true` here means both halves of the take-back — `LadderMachine.undeliver(at:)` stops the
    /// escalation clock, `InterventionLog.withdraw(_:)` stops the spend — because a stranded nudge
    /// left as a delivery goes on charging the day's interruption budget for something nobody saw,
    /// and under U-1 the budget is what decides whether the app may speak again at all.
    ///
    /// Two exits answer `true`, and what they have in common is that **the app took the surface
    /// away**: a presentation claimed the display, or the display itself was replaced. Every other
    /// exit either had an answer pressed on it or left the nudge standing until something the
    /// person did ended it.
    ///
    /// It is mutually exclusive with the two below and `theTakeBackIsNotAlsoAnIgnore` holds that:
    /// a delivery that is being withdrawn has no row left to complete and cannot have been
    /// ignored, because the app's own case is that nobody was shown it.
    public var takesBackTheDelivery: Bool {
        switch self {
        case .presentationWithdrew, .displayStranded: true
        case .answered, .replaced, .screenReclaimed, .worldMovedOn: false
        }
    }

    /// **Whether the row this rung's delivery wrote gets its one remaining field** (focus-gmr,
    /// R-79).
    ///
    /// `QuestionExit.leavesTheInterruptionUnanswered`, stated for the other half. An
    /// `InterventionRecord` gains exactly one thing after it is written — what the person did —
    /// and a rung that was delivered and then replaced, hidden or outlived stayed `delivered` with
    /// `outcome = nil` for ever: the app saying it interrupted somebody and never saying how it
    /// turned out.
    ///
    /// `answered` is the exception because `resolve(_:snoozeDuration:)` has already written the
    /// outcome that names the correction, and `InterventionLog.complete` is first-wins. The two
    /// take-backs are the other exception, and for a stronger reason: their row is being withdrawn
    /// from the day's spend, so an outcome on it would be the app saying somebody ignored
    /// something it has just said reached nobody.
    public var leavesTheInterruptionUnanswered: Bool {
        switch self {
        case .replaced, .screenReclaimed, .worldMovedOn: true
        case .answered, .presentationWithdrew, .displayStranded: false
        }
    }

    /// **Whether the two instruments named for "the app is talking to itself" hear about it**
    /// (focus-fwy, R-83, F-63).
    ///
    /// `LadderMachine`'s own run of unanswered rungs and `FatigueController`'s session-wide one
    /// are both bounded by `InterventionPolicy.ignoredAccusationBackoff`, and until focus-fwy both
    /// were reduced from exactly one place — `resolve(_:snoozeDuration:)`, for the single
    /// non-de-escalating `CorrectionAction` there is. So they counted only accusations the person
    /// actively **clicked away**, and never the ones they left on screen and walked past: somebody
    /// who never touches a nudge could be shown the full `dailyAccusationCap` without either
    /// backoff advancing a single step.
    ///
    /// **One exit answers `true`, and the line it draws is who caused the ending.** ⌃⌘H is the
    /// person acting on the nudge: they read it, they pressed a key aimed at it, and they answered
    /// nothing. Every other ending here was caused by the app or by the world:
    ///
    /// * `answered` — `resolve(…)` has already reduced whichever of the two events the click
    ///   deserved, and a second would count one dismissal twice.
    /// * `replaced` — the loop took this rung down to raise another. See the case's own note: it
    ///   is the half of focus-fwy that is **held**, because driving it puts the app back under
    ///   focus-f2a's floor by way of `LadderState`'s missing silence subject (focus-628).
    /// * `worldMovedOn` — ending a session is not ignoring a nudge, and `sessionEnded()` reduces
    ///   `FatigueEvent.sessionEnded` before it closes the surfaces, so an ignore counted here would
    ///   dirty a run that has just been reset.
    /// * the two take-backs — R-81: an un-delivery cannot be an ignore.
    ///
    /// **The rung is asked as well as the exit, twice over.** `NudgeHost` reduces these only for a
    /// leaving rung that `LadderRung.Kind.makesAnAccusation` — the ladder's own derivation of
    /// *"does this rung say something a person could answer?"*, which `SilenceSubject` and
    /// `InterventionEvent.spendsTheAccusationCap` already read, so a glyph is a state nobody can
    /// ignore — and only for one the seam could prove somebody was **shown**, because
    /// `PerceptibleChange` is the whole of what *"an accusation reached them"* means.
    public var countsAsAnIgnoredAccusation: Bool {
        switch self {
        case .screenReclaimed: true
        case .answered, .replaced, .presentationWithdrew, .displayStranded, .worldMovedOn: false
        }
    }
}
