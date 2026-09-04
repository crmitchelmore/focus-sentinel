import AppKit
import FocusCore

/// **Which of P-133's two timer shapes a session draws**, chosen once and not again.
///
/// P-133 measured `NSFont.monospacedDigitSystemFont(ofSize: .smallSystemFontSize)` rendering
/// `00:00`, `11:11`, `59:59` and `88:88` at **31.302734375 pt — identical to the last digit** —
/// against a **7.69 pt** jitter on the proportional system font between `11:11` and `88:88`.
/// That jitter would visibly shove every menu-bar item to its left once a second, so the
/// monospaced face is not a nicety.
///
/// What the monospaced face does **not** fix is the digit *count*: `1:00:00` measured 41.63 pt
/// and `12:34:56` 48.62 pt. A timer that grew a field at the hour mark would move every item
/// beside it exactly once, unpredictably — so the form is decided **once per session** from the
/// session's planned duration, and an open-ended session that crosses an hour changes it exactly
/// once, at a moment the app chooses rather than at a moment a nudge is in flight.
public enum MenuBarTimerFormat: String, Sendable, CaseIterable, Codable, Hashable {
    /// `mm:ss`. Constant width for every value below an hour.
    case minuteSecond
    /// `h:mm:ss`. Constant width for every value below ten hours, which is longer than any
    /// focus session this product is about.
    case hourMinuteSecond

    /// The form a session starts in.
    ///
    /// - Parameter planned: the timebox, or `nil` for an open-ended session. A planned session
    ///   that will cross the hour starts in the long form, so it never changes at all.
    public static func chosen(forPlanned planned: Duration?) -> MenuBarTimerFormat {
        guard let planned, planned >= .seconds(3600) else { return .minuteSecond }
        return .hourMinuteSecond
    }

    /// The form after `elapsed`, given the form the session is in.
    ///
    /// **Monotone**: it can widen once and can never narrow again. A timer that dropped back to
    /// `mm:ss` at the top of the next hour would move the menu bar twice per session instead of
    /// once, which is the defect the once-per-session rule exists to prevent.
    public func advanced(elapsed: Duration) -> MenuBarTimerFormat {
        if self == .hourMinuteSecond { return .hourMinuteSecond }
        return elapsed >= .seconds(3600) ? .hourMinuteSecond : .minuteSecond
    }

    /// The string this form draws for a span.
    public func render(_ span: Duration) -> String {
        switch self {
        case .minuteSecond: NudgeCopy.countdown(span)
        case .hourMinuteSecond: NudgeCopy.longCountdown(span)
        }
    }
}

/// One snooze, as the popover lists it.
public struct MenuBarSnooze: Sendable, Equatable, Hashable, Identifiable {
    /// **Both halves** (focus-ebv). This was a `String` carrying the snooze's own key, so the
    /// popover's Snoozed row read *"com.apple.Safari"* beside its countdown while the chip row
    /// above it drew *"Safari"*. The row is still identified and cancelled by
    /// `subject.identifier`; the word drawn is `subject.displayName`.
    public let subject: NudgeSubject
    public let remaining: Duration

    /// **The subject itself, not either half as a string.** Two applications may share a display
    /// name, so a list keyed on the name would draw one row for two snoozes; and an `id` of type
    /// `String` is a key a view could draw by mistake, which is the whole of focus-ebv. Keyed on
    /// the value, a row cannot be identified by anything a sentence would want.
    public var id: NudgeSubject { subject }

    public init(subject: NudgeSubject, remaining: Duration) {
        self.subject = subject
        self.remaining = remaining
    }
}

/// **The two kinds of nudge the popover can be carrying** (focus-xix).
///
/// A named, `CaseIterable` pair rather than two `Bool`s read at each call site, because the
/// question half of every reading in this file existed and the accusation half did not: the loop
/// could ask *"is the popover showing the question?"* and had no way at all to ask the same about
/// a rung — so a rung routed to the badge was counted as delivered to somebody who had not
/// clicked. `allCases` is what makes the next reading impossible to write for one and forget for
/// the other.
public enum MenuBarNudge: String, Sendable, CaseIterable, Codable, Hashable {
    /// U-1's question — *"is this part of it?"* — with its answers.
    case query
    /// A ladder rung, with the panel's whole correction economy.
    case accusation
}

/// **What the menu bar draws**, as one value (R-91, F-82, F-83, F-84).
///
/// The controller holds no model and reads no store: the composition root projects this and
/// hands it over, exactly as it does for the cockpit. That is what lets the popover be
/// snapshot-tested with no host and what keeps `FocusUI` free of every sibling package.
public struct MenuBarPresentation: Sendable, Equatable {
    /// The five-state token set e01 shipped. P-132 read all five in the real menu bar and found
    /// the silhouettes distinguishable in monochrome, so F-83/F-146 are satisfiable without
    /// colour using the symbols already in the repository.
    public let status: FocusStatus
    /// The priority's own sentence, or `nil` when there is none.
    public let priorityIntent: String?
    /// Session elapsed, or `nil` when no session is open.
    public let elapsed: Duration?
    /// Timebox remaining, when there is a timebox.
    public let remaining: Duration?
    /// The form the timer draws in, chosen once per session.
    public let timerFormat: MenuBarTimerFormat
    /// What is snoozed and for how long. A suppression a person cannot see is a suppression
    /// they cannot trust (R-87).
    public let snoozes: [MenuBarSnooze]
    /// The question waiting in the popover, when reduced interruption or the `silentVisual`
    /// deck routed it here instead of to a panel (R-92). `nil` the rest of the time.
    public let pendingQuery: QueryPresentation?
    /// **The accusation waiting in the popover**, when reduced interruption, the `silentVisual`
    /// deck or a running microphone routed the top rung here instead of to a panel (R-92).
    /// `nil` the rest of the time.
    ///
    /// **It is a presentation and not a rung label, and that is the fix** (focus-uru). The
    /// popover was handed `rung` alone and drew *"Nudge: Panel"* — a read-only sentence about an
    /// accusation with no dismiss, no "this is relevant", no "not this time" and no snooze. For
    /// a Reduce Motion user the top rung was a label, not a decision surface, and
    /// `CorrectionAction`'s "every surface, including the top rung, is dismissible" was false.
    /// Carrying the whole presentation is what lets this surface draw the *same*
    /// `AccusationPanelView` the panel draws, with the same actions in the same order.
    public let pendingAccusation: AccusationPresentation?
    /// The rung the ladder has reached, when it has reached one.
    public let rung: LadderRung.Kind?
    /// **The surface that rung actually landed on**, or `nil` when this loop is holding none
    /// (focus-mkk).
    ///
    /// `rung` above is the ladder's *name* for what it reached and has never said where it went;
    /// this is the other half, and its absence is what let an ambient rung be charged as a
    /// delivery while the item it was supposedly drawn on never changed. The item reads it
    /// through `attention` below and nowhere else.
    public let rungSurface: NudgeSurface?
    /// The band behind the current verdict, when there is one.
    public let band: EvidenceBand?
    /// F-119's one global switch, as the popover shows it.
    public let sensingPaused: Bool
    /// **Whether the break is over and the person has not gone back** (F-67, focus-2w1).
    ///
    /// Carried rather than derived, because the two facts it is made of are not here: how long
    /// ago this session came back from a break is the session host's, and whether what is in
    /// front of the person supports the commitment is the relevance host's.
    /// `RestartCue.state(phase:sinceBreakEnded:isBackOnTask:)` is where the rule lives; this is
    /// the answer it gave, and `.silent` carries **why** so a reading can tell a cue that is not
    /// due from one that was never computed.
    public let restartCue: RestartCue
    /// Whether the person has asked to differentiate without colour. When they have, the short
    /// label is drawn **beside** the glyph in the menu bar itself rather than only in the
    /// popover — at that point the label has stopped being decoration and become the channel
    /// they are relying on (F-146).
    public let differentiateWithoutColor: Bool

    public init(
        status: FocusStatus,
        priorityIntent: String? = nil,
        elapsed: Duration? = nil,
        remaining: Duration? = nil,
        timerFormat: MenuBarTimerFormat = .minuteSecond,
        snoozes: [MenuBarSnooze] = [],
        pendingQuery: QueryPresentation? = nil,
        pendingAccusation: AccusationPresentation? = nil,
        rung: LadderRung.Kind? = nil,
        rungSurface: NudgeSurface? = nil,
        band: EvidenceBand? = nil,
        sensingPaused: Bool = false,
        restartCue: RestartCue = .silent(.noSession),
        differentiateWithoutColor: Bool = false
    ) {
        self.status = status
        self.priorityIntent = priorityIntent
        self.elapsed = elapsed
        self.remaining = remaining
        self.timerFormat = timerFormat
        self.snoozes = snoozes
        self.pendingQuery = pendingQuery
        self.pendingAccusation = pendingAccusation
        self.rung = rung
        self.rungSurface = rungSurface
        self.band = band
        self.sensingPaused = sensingPaused
        self.restartCue = restartCue
        self.differentiateWithoutColor = differentiateWithoutColor
    }

    /// **Whether this presentation is carrying one kind of nudge** (focus-xix).
    ///
    /// One function over `MenuBarNudge` rather than two properties, so `carriedNudges` below and
    /// every reading built on it are exhaustive by construction.
    public func isCarrying(_ nudge: MenuBarNudge) -> Bool {
        switch nudge {
        case .query: pendingQuery != nil
        case .accusation: pendingAccusation != nil
        }
    }

    /// Every kind of nudge this presentation is carrying.
    public var carriedNudges: Set<MenuBarNudge> {
        Set(MenuBarNudge.allCases.filter(isCarrying))
    }

    /// **What the status item says about a nudge, over and above the status** (focus-mkk,
    /// focus-2xw).
    ///
    /// Derived, never passed in: the two facts it is made of — what the popover is carrying and
    /// where the rung landed — are already here, and a fourth stored field would be a third
    /// statement of the same thing for a path to get wrong.
    ///
    /// The **stronger** of the two, because the badge's invitation subsumes the glyph's mark: a
    /// person with a question waiting behind the click needs to be told to click, and telling
    /// them instead that there is nothing to answer would be the worse of the two truths. The
    /// order is `MenuBarAttention`'s own rank, not a comparison written here.
    ///
    /// `carriedNudges` rather than `rungSurface == .popoverBadge`, so the **question** half is
    /// covered by the same line: a badge question is exactly as invisible in the menu bar as a
    /// badge accusation was, and `MenuBarNudge.allCases` is what stops a third kind being marked
    /// for one and forgotten for the other.
    public var attention: MenuBarAttention {
        Swift.max(
            rungSurface?.menuBarAttention ?? .unmarked,
            carriedNudges.isEmpty ? .unmarked : NudgeSurface.popoverBadge.menuBarAttention
        )
    }

    /// The span the menu-bar timer counts.
    ///
    /// The snooze first, because a running snooze is the thing the person most recently asked
    /// for and the one with a deadline; then the timebox's remaining time; then the session's
    /// elapsed time. `nil` when there is nothing to count, in which case the item is a glyph
    /// alone — which is honest, and narrower.
    public var timedSpan: Duration? {
        snoozes.first?.remaining ?? remaining ?? elapsed
    }

    /// What the item's text field says, or `""` when there is nothing to count.
    public var timerText: String {
        guard let timedSpan else { return "" }
        return timerFormat.render(timedSpan)
    }
}

/// **The menu-bar item's text, and the reason it is measured rather than asserted** (P-133).
///
/// A pure value: it builds the attributed string the status item draws and can measure it
/// without a status bar, a window server or a running application. That is what makes "the
/// width does not change" a **test** rather than a claim — and P-133 is the measurement that
/// says the claim is worth testing.
public enum MenuBarTitle {
    /// The face every menu-bar figure is drawn in.
    ///
    /// `monospacedDigitSystemFont`, at `smallSystemFontSize`, which is the size P-133 measured.
    /// Not `monospacedSystemFont`: only the *digits* need to be fixed-width, and a fully
    /// monospaced menu-bar item would read as a terminal rather than as part of macOS.
    public static var font: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    }

    /// The attributed title for a rendered timer string.
    public static func attributed(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font])
    }

    /// How wide that title draws, in points.
    ///
    /// The instrument P-133 used, kept in the shipping code so the property can be asserted on
    /// the shipping font rather than on a font a test chose.
    public static func width(of text: String) -> Double {
        Double(attributed(text).size().width)
    }
}

/// **What a click in the menu bar asks for.**
///
/// A closed set of typed requests. The controller performs none of them: it reports, and the
/// composition root — which is the only object that knows about stores, sessions and the nudge
/// host — decides. That is the same one-way rule every other surface in this package follows.
public enum MenuBarAction: Sendable, Equatable, Hashable {
    case openCockpit
    case startSession
    case pauseSession
    case completeSession
    /// F-119's switch. The value is what the person asked *for*, not a toggle, so a stale view
    /// cannot invert it.
    case setSensingPaused(Bool)
    /// Cancel one subject's snooze from the popover (R-87).
    ///
    /// It carries the **subject**, not its identifier: a surface reports which row was pressed,
    /// as the value it was handed, and which half of that value keys a suppression is the host's
    /// business — the same division `correct(_:snoozeDuration:)` draws, where the view reports
    /// and `CorrectionAction.outcome(…)` decides. It is also what lets `check-forbidden.sh`
    /// (R-96o) ban the word `identifier` from the three views outright (focus-ebv).
    case cancelSnooze(subject: NudgeSubject)
    /// Answer the question the popover is carrying, when reduced interruption routed one here.
    case answerQuery(QueryAnswer)
    /// **Answer the accusation the popover is carrying** (focus-uru), when reduced interruption,
    /// the `silentVisual` deck or a running microphone routed the top rung here instead of to a
    /// panel. The `Duration` is the chosen snooze span and is `nil` for every other action — the
    /// same shape `AccusationPanelView` reports on the panel, because it *is* the same view.
    case correct(CorrectionAction, snoozeDuration: Duration?)
    /// **Open Settings, from a surface SwiftUI's environment does not reach** (focus-odz.2).
    ///
    /// An `NSStatusItem`'s menu is AppKit and lives outside every SwiftUI environment, so it has
    /// no `openSettings` to call. `ShellSettingsMenu` performs the app menu's own item instead,
    /// which is what keeps this the *same* route to the *same* single Settings scene.
    case openSettings
    /// **Leave.** `applicationShouldTerminateAfterLastWindowClosed` answers `false` on purpose, so
    /// with the cockpit shut the only way out was the Dock icon's own menu — which is AppKit's,
    /// and which the nudge loop's `applicationWillTerminate` write hangs off just as this does.
    case quit
}
