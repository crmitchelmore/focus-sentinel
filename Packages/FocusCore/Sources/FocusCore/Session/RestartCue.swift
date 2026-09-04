import Foundation

/// **The break is over, and the person has not gone back** (F-67, focus-2w1).
///
/// ## What was missing
///
/// `SessionEvent.breakEnded` and the break's own suppression have shipped since e03: the machine
/// knows a break began, knows it ended, and holds every nudge while it runs. What it did with
/// the ending was nothing at all. A person who takes fifteen minutes and comes back is exactly
/// the person the app is for; a person who takes fifteen minutes and then reads the news for
/// twenty more is the case F-67 names, and until now the only thing that would eventually say
/// anything was the ordinary drift ladder — which starts from scratch, ninety seconds of
/// sustained drift at a time, as though the break had never happened.
///
/// ## What it is, and the four things it is not
///
/// It is **one sentence on the ambient rung** — the menu-bar item's tooltip and the line
/// VoiceOver reads off it. That is the whole surface.
///
/// * **Not a panel.** U-2 left the app one panel nudge, for an unrelated verdict. A break ending
///   is not an accusation and must not spend the interruption slot.
/// * **Not a notification.** PD-1: this app asks for no permission of any kind, and there is no
///   notification for it to post.
/// * **Not praise, and not a score.** There is no *"well done, you took a break"* here and no
///   count of breaks taken or returned from (D-01, R-93). The cue states a fact about right now
///   and holds no history.
/// * **Not a nag.** It is a *state*, not an event: it is true while it is true and stops being
///   true the moment the person is back on task, so there is nothing to repeat and nothing to
///   dismiss.
///
/// ## Why it is a fold over the phases rather than an `if`
///
/// A break ends into `focus`, but `focus` is also where a session *starts*, and every other
/// phase reaches this function too — a paused session, an intentional detour, a session that has
/// been completed while the tooltip was still being computed. Each of those has an answer and
/// each answer is a different sentence about why nothing is being said, so the type carries the
/// reason and `RestartCueTests` folds over `SessionPhase.allCases` rather than over the one arm
/// somebody remembered.
public enum RestartCue: Sendable, Equatable, Hashable {
    /// Say it: the break is over and the person is somewhere else.
    case due
    /// Say nothing, and this is why.
    case silent(Reason)

    /// Why the cue is not showing. One case per way of being quiet, so a fold can require that
    /// every phase produces a **named** silence rather than a `false` that covers six situations.
    public enum Reason: String, Sendable, CaseIterable, Hashable, Codable {
        /// There is no session, so there has been no break.
        case noSession
        /// This session has not come back from a break — it may never have taken one.
        case noBreakHasEnded
        /// The break ended, and the grace has not run out yet. The person is allowed to take a
        /// moment: a cue that fired the instant a break ended would be the app standing over
        /// somebody as they sat down.
        case withinGrace
        /// They are back on the thing they said they were doing, which is the outcome. The cue
        /// clears itself; it is never dismissed.
        case backOnTask
        /// The session is over. A break inside a session that has ended is history.
        case sessionIsOver
        /// The session is paused or on a break right now. Whatever happened earlier, the person
        /// is not being asked to restart something they have deliberately stopped.
        case notRunning
    }

    /// Whether anything is being said.
    public var isDue: Bool { self == .due }

    /// **How long after a break ends before the app says anything.**
    ///
    /// Two minutes, and chosen rather than measured — said so here, as `RetentionPolicy`'s
    /// ninety days is. It is long enough that walking back to the desk, unlocking the Mac and
    /// opening the thing you were doing all happen inside it, and short enough that a break that
    /// has quietly become an afternoon is caught while the person still remembers taking it.
    public static let grace: Duration = .seconds(120)

    /// The whole rule, as a total function.
    ///
    /// - Parameters:
    ///   - phase: the session's phase, or `nil` for no session at all.
    ///   - sinceBreakEnded: how long ago this session last came back from a break, or `nil` if it
    ///     never has.
    ///   - isBackOnTask: whether what is in front of the person right now supports the
    ///     commitment. The **outcome**: while this is true there is nothing to say, whatever the
    ///     clock says.
    public static func state(
        phase: SessionPhase?,
        sinceBreakEnded: Duration?,
        isBackOnTask: Bool
    ) -> RestartCue {
        guard let phase else { return .silent(.noSession) }
        switch phase {
        case .complete, .interrupted:
            return .silent(.sessionIsOver)
        case .paused, .onBreak:
            return .silent(.notRunning)
        case .focus, .intentionalDetour:
            break
        }
        guard let sinceBreakEnded else { return .silent(.noBreakHasEnded) }
        guard !isBackOnTask else { return .silent(.backOnTask) }
        guard sinceBreakEnded >= grace else { return .silent(.withinGrace) }
        return .due
    }
}

extension RestartCue {
    /// The String Catalog key for the sentence the ambient rung says, or `nil` when it is silent
    /// — which must add no word at all, for `MenuBarAttention.copyKey`'s reason: an empty
    /// sentence appended to the status label reads as a pause to somebody listening.
    public var copyKey: String? {
        switch self {
        case .due: "nudge.restart.cue"
        case .silent: nil
        }
    }

    /// The sentence itself, resolved against `FocusCore`'s own bundle, in the shape
    /// `MenuBarAttention.copyResource` already ships.
    public var copyResource: LocalizedStringResource? {
        guard let copyKey else { return nil }
        return LocalizedStringResource(
            String.LocalizationValue(copyKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }
}
