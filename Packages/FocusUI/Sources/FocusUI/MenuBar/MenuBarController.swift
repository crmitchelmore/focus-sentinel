import AppKit
import FocusCore
import SwiftUI

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
    /// The band behind the current verdict, when there is one.
    public let band: EvidenceBand?
    /// F-119's one global switch, as the popover shows it.
    public let sensingPaused: Bool
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
        band: EvidenceBand? = nil,
        sensingPaused: Bool = false,
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
        self.band = band
        self.sensingPaused = sensingPaused
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
}

/// **The menu-bar command centre: `NSStatusItem` + `NSPopover`** (R-91).
///
/// `NSStatusItem` rather than SwiftUI's `MenuBarExtra`, per the Court's choice, because this
/// surface needs the **button** and the **popover** as objects: the button's frame is what the
/// live lane photographs (P-132 measured status-item window numbers ≥ 2³², so `screencapture -l`
/// cannot address one and the evidence instrument is `screencapture -R` computed from
/// `button.window.frame`), and the popover has to be openable from a command as well as a click.
///
/// ## There is no timer in here
///
/// F-84's minute cadence is achieved by **coalescing**, not by scheduling: `update(_:)` is
/// called by the composition root on the events that already happen — every accepted activation
/// and e03's five-second corroboration tick — and rewrites the item's title only when the
/// *rendered string* actually differs. At `mm:ss` granularity that is once per second while a
/// snooze runs and once per minute otherwise, with no timer for anybody to leak and nothing to
/// cancel. P-133 measured one `attributedTitle` assignment at 49.67 µs, so the cadence is a
/// wakeup-budget decision (F-163) rather than a cost one.
///
/// Updates are also suppressed entirely while the item is hidden, because drawing a figure
/// nobody can see is the menu-bar form of R-81's mistake.
@MainActor
public final class MenuBarController {
    /// What a click asked for. Wired by the composition root.
    public var onAction: ((MenuBarAction) -> Void)?

    /// **The popover has opened, or has just been handed something new to show.**
    ///
    /// Wired by the composition root, because a nudge routed to the badge has reached nobody
    /// until this fires: the popover opens **only** when a person clicks the status item, and
    /// nothing else in the programme can tell the nudge loop that the click happened (focus-kby).
    ///
    /// **It fires for a rung as well as for a question** (focus-xix). It used to fire on
    /// `pendingQuery` alone, which is half of what the badge carries — so the accusation half of
    /// the loop had no moment at which it could learn it had been looked at, and counted itself
    /// delivered on landing instead.
    public var onPopoverDidShow: (() -> Void)?

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var presentation = MenuBarPresentation(status: .uncertain)
    private var traits: AppearanceTraits = .systemDefault
    /// The last string actually written to the button. The coalescing cadence is this
    /// comparison and nothing else.
    private var drawnTitle: String?
    /// The last status **announced**. VoiceOver hears a state change once, when it happens —
    /// not once per corroboration tick, which would be the app reading the same word aloud
    /// every five seconds (F-144, F-146).
    private var announcedStatus: FocusStatus?
    /// How many times the title has actually been rewritten. Reported by the self-check, so
    /// "it does not redraw every tick" is a number rather than a promise.
    public private(set) var titleWriteCount = 0

    public init(traits: AppearanceTraits = .systemDefault) {
        self.traits = traits
        popover.behavior = .transient
        popover.animates = false
    }

    // MARK: - Installing

    /// Put the item in the menu bar.
    ///
    /// Separate from `init` and idempotent, for the same reason `AppComposition.start()` is:
    /// it touches AppKit and must run once the application object exists.
    public func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.setAccessibilityLabel(ShellStrings.string(.menuBarStatusItem))
        statusItem = item
        redraw(force: true)
    }

    /// Take it out again. A quit is not a state change the person made.
    public func remove() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
        drawnTitle = nil
    }

    public var isInstalled: Bool { statusItem != nil }

    /// Whether the item is on screen at all.
    ///
    /// **Not the same question as whether the menu bar is visible.** P-131 measured our own
    /// status-item window staying *listed* during a full-screen space while the menu-bar layer's
    /// owners collapsed from eleven to one — a window being listed is not a window being seen,
    /// which is why the ambient rung's deliverability is decided by `NudgeSurroundings`'s own
    /// `menuBarVisible` reading and never by this property.
    public var isItemVisible: Bool { statusItem?.isVisible ?? false }

    /// The button's frame on screen, for the live lane's `screencapture -R <rect>` (P-132).
    public var buttonFrame: ScreenRect? {
        guard let window = statusItem?.button?.window else { return nil }
        let frame = window.frame
        return ScreenRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.width,
            height: frame.height
        )
    }

    // MARK: - Drawing

    /// Hand the item a new state. Redraws only what changed.
    public func update(_ presentation: MenuBarPresentation, traits: AppearanceTraits? = nil) {
        let carriedBefore = self.presentation.carriedNudges
        self.presentation = presentation
        if let traits {
            self.traits = traits
            // The popover and the status item draw AppKit chrome, which resolves against their
            // own appearance and not against SwiftUI's environment (focus-pq8).
            let appearance = NSAppearance(
                named: traits.colorScheme == .dark ? .darkAqua : .aqua
            )
            popover.appearance = appearance
            statusItem?.button?.appearance = appearance
        }
        redraw(force: false)
        guard popover.isShown else { return }
        popover.contentViewController = popoverController()
        // A nudge that arrived while the popover was already open is a nudge the person is
        // looking at, and the loop is told for the same reason it is told about an opening.
        //
        // **Either kind** (focus-xix). Set subtraction rather than a pair of `Bool`s, so a rung
        // arriving beside a question that was already there still counts as something new.
        if !presentation.carriedNudges.subtracting(carriedBefore).isEmpty { onPopoverDidShow?() }
    }

    private func redraw(force: Bool) {
        guard let button = statusItem?.button else { return }
        // A figure nobody can see is not a figure worth writing (F-163).
        guard isItemVisible || force else { return }

        button.image = Self.glyph(for: presentation.status)
        button.imagePosition = presentation.timerText.isEmpty ? .imageOnly : .imageLeading
        announceStatusChange(button: button)

        let title = Self.buttonTitle(presentation)
        guard force || title != drawnTitle else { return }
        button.attributedTitle = MenuBarTitle.attributed(title)
        drawnTitle = title
        titleWriteCount += 1
        button.setAccessibilityLabel(Self.accessibilityLabel(presentation))
    }

    /// The glyph: the status's own SF Symbol, **template-rendered**.
    ///
    /// Template rendering is what makes the menu bar's own light and dark treatments apply, and
    /// it is also what makes the silhouette the whole signal — P-132 read all five in the real
    /// menu bar and confirmed they are distinguishable in monochrome, which is F-146 satisfied by
    /// the tokens e01 already shipped rather than by colour.
    nonisolated public static func glyph(for status: FocusStatus) -> NSImage? {
        let image = NSImage(
            systemSymbolName: status.symbolName,
            accessibilityDescription: status.shortLabel
        )
        image?.isTemplate = true
        return image
    }

    /// The text drawn beside the glyph.
    ///
    /// The timer, and — under "Differentiate without colour" — the status's short label in front
    /// of it, so a person who cannot use the colour channel is not left with the silhouette
    /// alone at menu-bar size.
    nonisolated public static func buttonTitle(_ presentation: MenuBarPresentation) -> String {
        let timer = presentation.timerText
        guard presentation.differentiateWithoutColor else { return timer }
        let label = presentation.status.shortLabel
        return timer.isEmpty ? label : "\(label) \(timer)"
    }

    /// What VoiceOver reads off the item.
    nonisolated public static func accessibilityLabel(_ presentation: MenuBarPresentation) -> String {
        let timer = presentation.timerText
        let label = presentation.status.shortLabel
        return timer.isEmpty ? label : "\(label) \(timer)"
    }

    /// Say the new state out loud, once (F-144).
    ///
    /// The ambient rung is a **silent** surface for somebody who can see it. For somebody who
    /// cannot, silence would mean the rung never happened — so the one channel it has is
    /// announced, and it is announced on the change rather than on the reading, because a state
    /// that is repeated is not a state that changed.
    ///
    /// `.medium` priority: it is a fact about the app, not an interruption. A high-priority
    /// announcement would cut across whatever the person is having read to them, which is a
    /// louder thing than the glyph it describes.
    private func announceStatusChange(button: NSStatusBarButton) {
        guard announcedStatus != presentation.status else { return }
        announcedStatus = presentation.status
        NSAccessibility.post(
            element: button,
            notification: .announcementRequested,
            userInfo: [
                .announcement: Self.accessibilityLabel(presentation),
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }

    // MARK: - The popover

    @objc
    public func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        popover.contentViewController = popoverController()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        onPopoverDidShow?()
    }

    public var isPopoverShown: Bool { popover.isShown }

    /// **Whether one kind of nudge is on screen in the popover right now** (focus-kby, focus-xix,
    /// U-1).
    ///
    /// Both halves are load-bearing and both were knowable and unread: a popover that is open
    /// but showing snoozes is not showing a nudge, and a nudge in a popover nobody has opened is
    /// a nudge nobody has seen. This is the whole of the badge route's readability reading, and
    /// the nudge loop counts no badge delivery without it.
    ///
    /// **It takes the kind as an argument**, because it used to exist for the question alone
    /// (`isShowingQuery`, ten call sites) and not at all for a rung (zero) — which is precisely
    /// the shape of focus-xix: the loop could not ask whether the accusation had been looked at,
    /// so it assumed.
    public func isShowing(_ nudge: MenuBarNudge) -> Bool {
        popover.isShown && presentation.isCarrying(nudge)
    }

    public func closePopover() {
        popover.performClose(nil)
    }

    private func popoverController() -> NSViewController {
        NSHostingController(
            rootView: MenuBarPopoverView(presentation: presentation) { [weak self] action in
                self?.onAction?(action)
            }
            .appearanceTraits(traits)
        )
    }
}
