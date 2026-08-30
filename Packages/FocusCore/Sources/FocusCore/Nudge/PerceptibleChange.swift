import Foundation

/// **The channel a nudge on one surface can actually be perceived through** (focus-1b5,
/// focus-nrl).
///
/// One per surface, and the mapping is `NudgeSurface.perceptionChannel`. It exists so that
/// *"what would a person have to see for this to have happened?"* is asked once, of a closed
/// set, rather than being reasoned out afresh at each of the four call sites that charge.
public enum PerceptionChannel: String, Sendable, CaseIterable, Codable, Hashable {
    /// The status item's own picture and the sentence VoiceOver reads off it.
    ///
    /// **The one channel whose proof is a difference rather than a state**, and the whole reason
    /// this file exists. The item is always there: it cannot appear, so *"the item is on screen"*
    /// is true of every second of the day and proves nothing. What a person perceives is the
    /// moment the item **starts saying something it was not saying**, and that moment is one
    /// assignment to an `NSStatusBarButton`.
    case menuBarItem
    /// A window ordered in front of the person with every action of the nudge in reach.
    ///
    /// A state, not a difference, and honestly so: a window is absent or present, `isVisible` is
    /// a reading of the real `NSWindow`, and the sentence it carries names its own subject — so a
    /// second accusation in the same frame is a different sentence, which the glyph's two-state
    /// mark can never be.
    case panelWindow
    /// The popover, open, with this nudge drawn in it **and every action it offers in reach**.
    /// A state, for the panel's reason: `NSPopover.isShown` is a reading of the real popover, and
    /// the row carries the subject.
    ///
    /// **The reach clause is focus-5yu's** and it is the same clause `panelWindow` has carried
    /// since focus-vpu. Without it this channel was two booleans — the popover is open, the
    /// popover is carrying this — on the one surface in the app that had committed to no size:
    /// measured, a popover 3127 points tall on a 1080-point display, with the corrections 2755
    /// points above the top of the screen, satisfied both.
    case popoverContents
    /// A posted banner. **Nothing in this app posts one** (U-2, focus-wy0), and nothing can
    /// observe one either — so this channel is unprovable by construction, and a rung misrouted
    /// to a notification is charged nothing rather than charged on trust.
    case banner
}

/// **What the person could be shown, read off the real surfaces at one instant.**
///
/// Every field is a reading of a live AppKit object taken by the host — a count of assignments
/// that actually happened to an `NSStatusBarButton`, the mark that button is actually drawing,
/// `NSWindow.isVisible` conjoined with a hit test of the offered actions, `NSPopover.isShown`
/// conjoined with what the popover is carrying and with where that content actually laid its
/// actions out. **Not one field is a predicate about a surface**,
/// which is the distinction three rounds of this defect turned on: `reachesThePersonOnLanding`
/// answers `true` for `.menuBar` and cannot fail, and it was read as though it were evidence.
public struct SurfaceObservation: Sendable, Equatable, Hashable {
    /// How many times the status item's image has been assigned, ever.
    public let menuBarWrites: Int
    /// How many announcements the status item has actually posted, ever — F-144's channel, and
    /// the whole of the ambient rung for somebody who cannot see the glyph.
    public let menuBarAnnouncements: Int
    /// **The mark the item is actually drawing**, which is not the mark the presentation asked
    /// for. `MenuBarPresentation.attention` is the *maximum* of the rung's mark and the badge's,
    /// so a glyph rung standing underneath a pending badge nudge asks for `noticing` and the item
    /// draws `waiting` — the item says nothing about the rung, and focus-nrl is the six charges
    /// that were taken for it anyway.
    public let markOnTheItem: MenuBarAttention
    /// Whether the panel is on screen, showing this kind of nudge, with every action it offers
    /// somewhere the person could click.
    public let panelIsShowingTheNudge: Bool
    /// Whether the popover is open, drawing this kind of nudge, with every action it offers
    /// somewhere the person could click — the same three-part reading `panelIsShowingTheNudge`
    /// above is, taken on the surface that had none (focus-5yu).
    public let popoverIsShowingTheNudge: Bool

    public init(
        menuBarWrites: Int,
        menuBarAnnouncements: Int,
        markOnTheItem: MenuBarAttention,
        panelIsShowingTheNudge: Bool,
        popoverIsShowingTheNudge: Bool
    ) {
        self.menuBarWrites = menuBarWrites
        self.menuBarAnnouncements = menuBarAnnouncements
        self.markOnTheItem = markOnTheItem
        self.panelIsShowingTheNudge = panelIsShowingTheNudge
        self.popoverIsShowingTheNudge = popoverIsShowingTheNudge
    }

    /// Nothing has been drawn, nothing is up, and the item is bare. The reading a surface that
    /// does not exist yet gives, and the baseline every fixture starts from.
    public static let nothingSeen = SurfaceObservation(
        menuBarWrites: 0,
        menuBarAnnouncements: 0,
        markOnTheItem: .unmarked,
        panelIsShowingTheNudge: false,
        popoverIsShowingTheNudge: false
    )
}

/// **A change the person could perceive — and the only thing this app is allowed to charge for**
/// (focus-1b5, focus-nrl, focus-mkk, focus-2xw, focus-xix, U-1, U-2).
///
/// ## The invariant, in the app's own words
///
/// `MenuBarAttention`'s documentation has stated it since focus-mkk: *"A rung that changes
/// nothing in the menu bar is not a quieter rung; it is no rung at all, charged at the price of
/// one."* This type is that sentence made into a value, because three consecutive rounds proved
/// that stating it in a doc comment beside the code that violates it does not hold it.
///
/// **Nothing is charged against the person's daily budget unless something they can perceive
/// actually changed.** Not a predicate saying a surface is visible. Not a redraw being
/// *requested*. An observed change, on the surface's own channel.
///
/// ## Why it is a type and not a test
///
/// The three rounds before this one each fixed the instance they were handed and left the shape
/// intact, because the shape was *"charge here, and separately, hope the surface changed"* — two
/// siblings that a reviewer has to keep in step by memory. The repairs were correct and each was
/// blind exactly one step out: for the first glyph rung but not the second; for a bare item but
/// not for one already marked by a badge.
///
/// So the charge is now a **consequence** of the change rather than a sibling of it. This value
/// is the receipt, its memberwise initialiser is `fileprivate`, and `proven(on:from:to:)` below
/// is the only producer in the programme — pinned there by `check-forbidden.sh` (R-96p) exactly
/// as `LadderRung`'s two producers are pinned by R-96c. `NudgeHost.deliveredRung(_:provenBy:)`
/// and `NudgeHost.deliverQuestion(provenBy:…)` take one and have no default, so **a charge
/// without a perceptible change is not a bug in this programme; it is a thing that cannot be
/// written down.**
///
/// ## What it deliberately does not do
///
/// It does not decide whether a nudge was *wanted*, whether a surface was *available*, or
/// whether the ladder may advance. `SuppressionStack`, `SurfaceRouter` and `LadderMachine` own
/// those, and R-81's split between landing and being seen is untouched: a rung still lands, the
/// ladder is still told, and only the **spend** waits for this.
public struct PerceptibleChange: Sendable, Equatable, Hashable {
    /// The surface the change happened on. Carried rather than passed alongside, so a proof
    /// about one surface cannot be spent on another: `deliveredRung(_:provenBy:)` reads the
    /// surface off the receipt and takes no second argument that could disagree with it.
    public let surface: NudgeSurface

    /// The channel it was perceived through — the surface's own, never a second opinion.
    public var channel: PerceptionChannel { surface.perceptionChannel }

    /// **The only initialiser, and it is `fileprivate`.** See `proven(on:from:to:)`.
    fileprivate init(surface: NudgeSurface) {
        self.surface = surface
    }

    /// **The one producer: two readings of the real surfaces, and the answer `nil` unless the
    /// person was shown something.**
    ///
    /// - Parameters:
    ///   - surface: where the nudge landed. Its `perceptionChannel` chooses the question asked.
    ///   - before: the reading taken immediately before the landing was allowed to redraw
    ///     anything.
    ///   - after: the reading taken now.
    /// - Returns: the receipt, or `nil` — which means *"charge nothing"*, and never *"charge a
    ///   little less"*.
    ///
    /// ## The menu bar's three conjuncts, one bead each
    ///
    /// 1. **The item was written to, or it spoke.** A count of assignments that really happened
    ///    to an `NSStatusBarButton`, or of announcements really posted. focus-mkk: six delivered
    ///    rows against one write, made by `install()` before the first rung existed.
    /// 2. **It was not already saying this.** focus-1b5: two consecutive glyph rungs are both
    ///    `noticing`, the mark carries no subject, and so a second accusation about a *different*
    ///    application is a picture identical to the one already on screen. Six charges, one
    ///    write.
    /// 3. **It is saying this now.** focus-nrl: with any badge nudge pending the item is drawn
    ///    from the **maximum** of the rung's mark and the badge's, so the glyph rung's `noticing`
    ///    is subsumed by `waiting` and the item says nothing about the rung at all — from the
    ///    *first* landing, for every Reduce Motion user and everybody on a call. The doc there
    ///    argued the stronger mark subsumes the weaker; that is true about what to **draw** and
    ///    false about what to **charge**, and this conjunct is the difference.
    ///
    /// Conjuncts 2 and 3 together are one statement — *the item started saying what this rung
    /// needs it to say* — and they are written as two because each is a bead and each has to be
    /// separately mutable for the mutation proof to mean anything.
    ///
    /// The rung is not lost when this answers `nil`: it stays open and unpaid, and the next time
    /// the item is written this is asked again. That is what makes focus-nrl's rung recoverable —
    /// when the badge question is answered the mark falls from `waiting` to `noticing`, the item
    /// is written, and the rung is charged then, for the first moment anybody could see it.
    public static func proven(
        on surface: NudgeSurface,
        from before: SurfaceObservation,
        to after: SurfaceObservation
    ) -> PerceptibleChange? {
        switch surface.perceptionChannel {
        case .menuBarItem:
            let itemMoved = after.menuBarWrites > before.menuBarWrites
                || after.menuBarAnnouncements > before.menuBarAnnouncements
            guard itemMoved,
                  before.markOnTheItem != surface.menuBarAttention,
                  after.markOnTheItem == surface.menuBarAttention
            else { return nil }

        case .panelWindow:
            guard after.panelIsShowingTheNudge else { return nil }

        case .popoverContents:
            guard after.popoverIsShowingTheNudge else { return nil }

        case .banner:
            // Unobservable, therefore unprovable, therefore free. Nothing routes here (U-2) and
            // `NudgeHost.accuse(…)` faults on a rung that does; this is the arithmetic agreeing
            // with that rather than a second policy about notifications.
            return nil
        }
        return PerceptibleChange(surface: surface)
    }
}

extension NudgeSurface {
    /// **The one channel a nudge on this surface can be perceived through** (focus-1b5,
    /// focus-nrl).
    ///
    /// | surface | channel | what has to be observed |
    /// |---|---|---|
    /// | `menuBar` | `menuBarItem` | the item was written to, and it started saying `noticing` |
    /// | `panel` | `panelWindow` | the window is up, with every correction in reach |
    /// | `popoverBadge` | `popoverContents` | the popover is open, drawing this nudge, with every action in reach |
    /// | `notification` | `banner` | nothing; no rung routes here and nothing can observe one |
    ///
    /// Stated on the surface, beside `menuBarAttention` and `reachesThePersonOnLanding`, for the
    /// reason those two are: the question path and the accusation path both charge, and a rule
    /// written at either call site is a rule the other half can be missing. That is the shape of
    /// every bead in this sequence.
    public var perceptionChannel: PerceptionChannel {
        switch self {
        case .menuBar: .menuBarItem
        case .panel: .panelWindow
        case .popoverBadge: .popoverContents
        case .notification: .banner
        }
    }
}
