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

    /// **Whether this reading shows `surface` saying what the nudge needs it to say** — the
    /// *state* half of the channel's question, asked without the *difference* half.
    ///
    /// It exists because two different questions were being asked of the same fields by two
    /// different pieces of code. *"Is this panel a surface the person could decide on?"* is a
    /// question about the **surface**, asked once at the show so an unusable panel becomes a
    /// deferral rather than a nudge; *"did the person perceive a change?"* is a question about
    /// the **person**, and it is `PerceptibleChange.proven(on:from:to:)`'s. `accuse(…)` and
    /// `ask(…)` used to ask the first by calling the second, which is why the charge and the
    /// deferral had to be decided in the same breath — and why the charge could not be moved to
    /// the seam without inventing a second rule about panels for a future round to find out of
    /// step with this one. There is one rule; the difference is which half of it is being asked.
    public func carries(_ surface: NudgeSurface) -> Bool {
        switch surface.perceptionChannel {
        case .menuBarItem: markOnTheItem == surface.menuBarAttention
        case .panelWindow: panelIsShowingTheNudge
        case .popoverContents: popoverIsShowingTheNudge
        case .banner: false
        }
    }
}

/// **A reading of surfaces that have stopped moving** (focus-my0).
///
/// A `SurfaceObservation` can be taken at any instant, including an instant that never reaches a
/// screen. This is one that was taken at a **seam** — the end of a turn, after everything that
/// turn was going to do to the surfaces has been done — and it is the only kind of reading
/// `PerceptibleChange.proven(on:from:to:)` will accept as the *after* half of a proof.
///
/// ## The measured defect, which the three conjuncts were all true of
///
/// `NudgeHost.closeSurfaces(endingAnyQuestionAs:)` ends the open question, hides the panel and
/// forgets the open rung in **one synchronous main-actor call stack**. With a badge question
/// pending and a glyph rung standing invisibly under it — the state the `markOnTheItem` conjunct
/// below calls *"the ordinary state of every Reduce Motion user and everybody on a call"* — the
/// first of those three statements drops the item's mark from `waiting` to the rung's own
/// `noticing` and writes the item; the third puts it back to `unmarked`. Between them AppKit
/// composites nothing. Measured on the shipping loop: `writesDuringTeardown=2`, `chargesDelta=1`,
/// `markAfter=unmarked`, one row reading `accusation/delivered/menuBar/ignored`, one of the day's
/// eight interruptions spent — nobody having clicked anything.
///
/// Every conjunct of the invariant was satisfied. The item really was written to, it really was
/// not saying `noticing` before, and at the instant the reading was taken it really was saying
/// `noticing`. What was false is the thing the reading was standing in for: **that a person could
/// have seen it.** A change undone within the same turn is not a perceptible change, and the
/// invariant could not tell, because it was handed a reading of a state that never survived to a
/// frame.
///
/// ## Why this is a type and not a check
///
/// For `PerceptibleChange`'s own reason, stated below and now applied one level down. The five
/// entry points that share `closeSurfaces`' shape could each have been taught to charge later,
/// and that is the repair this epic has now made four times: fix the instance, leave the shape.
/// The shape here is *"take a reading whenever you like and call it evidence"*, so the reading
/// itself is the thing that is now type-checked. The memberwise initialiser is `fileprivate` and
/// `SurfaceTurn.Seam.settled(_:)` is the only producer in the programme — pinned there by
/// `check-forbidden.sh` (R-96s) exactly as this file's other receipt is pinned by R-96p — and a
/// `Seam` is handed out by nothing but the end of a turn. **Proving a change from a reading taken
/// mid-turn is not a bug in this programme; it is a thing that cannot be written down.**
public struct SettledObservation: Sendable, Equatable, Hashable {
    /// What the surfaces were saying once they had stopped moving.
    public let reading: SurfaceObservation

    /// **The only initialiser, and it is `fileprivate`.** See `SurfaceTurn.Seam.settled(_:)`.
    fileprivate init(reading: SurfaceObservation) {
        self.reading = reading
    }
}

/// **One turn of the loop, and the seam at the end of it** (focus-my0).
///
/// A turn is everything the nudge loop does from one outside event: a judgement arriving, a click,
/// a phase change, the display changing under a panel. Within a turn the surfaces are *moving* —
/// a question is cleared, a presentation is rebuilt, an item is written, a rung is forgotten —
/// and nothing AppKit draws is settled until the call stack unwinds and the main runloop gets its
/// turn back. The seam is that moment, and it is the only moment a reading of the surfaces is
/// evidence about what a person could have seen.
///
/// ## Why the turn is the host's own entry point rather than the runloop
///
/// The bead offered three mechanisms: a frame boundary, a deferral to the next runloop pass, or
/// refusing to prove a change whose surface is torn down in the same call stack. This is the
/// third, made positive: the proof is not *refused* by recognising a teardown — recognising
/// teardowns one at a time is the method that produced four rounds of this defect — it is simply
/// **taken later**, when there is nothing left in flight to undo it.
///
/// A `DispatchQueue.main.async` hop would be closer to the literal compositing boundary and it
/// buys nothing this does not: everything that could undo the change has already run by the time
/// the outermost call returns, because the loop is `@MainActor` and re-entrant only through its
/// own synchronous callbacks. What it would cost is determinism — every drive in the suite, and
/// the self-check, would have to pump a runloop to find out what the app charged, and a charge
/// you have to wait for is a charge a test can miss.
///
/// ## What it is still green for, deliberately
///
/// A change that is undone in a **later** turn. A rung charged at this seam and torn down two
/// milliseconds later by the next event really was on screen for a frame, and this type takes no
/// view on whether that was long enough — that is a question about duration, and nothing in this
/// programme measures one yet.
@MainActor
public final class SurfaceTurn {
    public init() {}

    /// What to do at the seam. Set once, by the object whose turns these are.
    public var atSeam: (@MainActor (Seam) -> Void)?

    /// How deep the current turn is. A turn entered from inside another turn is the same turn:
    /// `menuBarItemRedrawn()` reached through a redraw that `setOpenRung(_:)` asked for is not a
    /// new event, it is the middle of the one already being served.
    private var depth = 0

    /// Whether the seam handler is running, so that anything it does cannot open a second seam
    /// underneath itself.
    private var settling = false

    /// Whether a turn is open — the reading that says *"the surfaces may still be moving"*.
    public var isOpen: Bool { depth > 0 }

    /// Run `body` as part of one turn, and reach the seam when the outermost one ends.
    ///
    /// The seam runs on the way out of a throwing body too: a turn that failed half way through
    /// has left the surfaces in whatever state it left them, and that state is exactly the one a
    /// person is about to see.
    @discardableResult
    public func run<T>(_ body: () throws -> T) rethrows -> T {
        depth += 1
        defer {
            depth -= 1
            if depth == 0, !settling {
                settling = true
                atSeam?(Seam())
                settling = false
            }
        }
        return try body()
    }

    /// **The witness that a reading was taken at a seam**, and the only producer of a
    /// `SettledObservation`.
    ///
    /// Handed to the seam handler and to nobody else. It carries no state because it is not a
    /// value about the surfaces; it is a value about *when*, and the only thing that can make one
    /// is the end of a turn.
    public struct Seam {
        fileprivate init() {}

        /// Bless a reading taken now, at the seam, as evidence.
        public func settled(_ reading: SurfaceObservation) -> SettledObservation {
            SettledObservation(reading: reading)
        }
    }
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
    ///     anything. An ordinary `SurfaceObservation`, because it is a baseline rather than
    ///     evidence: what it has to be true of is the surfaces the change is measured *from*.
    ///   - after: the reading taken at the seam, once the surfaces had stopped moving. It is a
    ///     `SettledObservation` and nothing else will do — see that type for the day's
    ///     interruption that a mid-turn reading of a mark that never reached a frame paid for.
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
        to settled: SettledObservation
    ) -> PerceptibleChange? {
        let after = settled.reading
        switch surface.perceptionChannel {
        case .menuBarItem:
            let itemMoved = after.menuBarWrites > before.menuBarWrites
                || after.menuBarAnnouncements > before.menuBarAnnouncements
            guard itemMoved,
                  !before.carries(surface),
                  after.carries(surface)
            else { return nil }

        case .panelWindow:
            guard after.carries(surface) else { return nil }

        case .popoverContents:
            guard after.carries(surface) else { return nil }

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
