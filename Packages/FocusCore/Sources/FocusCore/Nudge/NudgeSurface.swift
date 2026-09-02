import Foundation

/// **Where a nudge can actually appear.** Four surfaces, and no fifth.
///
/// The set is closed on purpose. F-148's "reduced interruption" is a **routing flag inside the
/// existing router**, not a parallel surface stack (R-92), and the `silentVisual` voice is a
/// routing deck rather than a copy deck — both of them remap rungs onto the surfaces below
/// rather than adding one. e08's notch is a second *renderer* for the ambient rung, not a fifth
/// surface. That is what keeps the routing table a table a person can read.
public enum NudgeSurface: String, Sendable, CaseIterable, Codable, Hashable {
    /// The status-item glyph. Silent: no panel, no sound, no motion beyond the glyph change.
    /// The only surface the ambient rung has, and the only one a full-screen space can hide
    /// (P-131) — which is why an ambient rung over a presentation is `deferred`, never
    /// `delivered`.
    case menuBar
    /// The non-activating `NSPanel` (R-89), shown with `orderFrontRegardless()` and never made
    /// key programmatically. Carries the whole correction economy, because a nudge you cannot
    /// answer back to is the anti-pattern the product boundary forbids.
    case panel
    /// `UNUserNotificationCenter`. **Declared, and reached by nothing** (U-2, focus-wy0). It was
    /// the recommitment rung's surface and that rung is deferred to focus-5ab, which needs this
    /// case back; and `NudgeHost.resolveFromNotification(…)` must still be able to name the
    /// surface a banner an earlier build posted came from, in order to refuse a press on it.
    /// P-134 measured that at zero grants every setting reads `.notSupported` and `add(_:)` fails
    /// with `UNErrorDomain` code 1 — which is why nothing routes here and nothing asks to.
    case notification
    /// A badge and a row in the menu-bar popover. Where the panel rungs and the query go when
    /// reduced interruption is on, or when the voice is `silentVisual` — quiet, legible, and
    /// still answerable.
    case popoverBadge

    /// **Whether a person looking at this surface has a way to answer the nudge on it**
    /// (focus-uru).
    ///
    /// | surface | can be answered back to | what is actually drawn |
    /// |---|---|---|
    /// | `panel` | **yes** | `AccusationPanelView` / `QueryPanelView`, with the full action set |
    /// | `popoverBadge` | **yes** | the *same two views*, inside `MenuBarPopoverView` |
    /// | `notification` | **no** | nothing can be posted to it, so nobody is offered anything |
    /// | `menuBar` | no | a glyph, and it is not a thing to be answered — see below |
    ///
    /// **The badge answered `false` here, and that was the defect.** Under macOS Reduce Motion —
    /// and under `silentVisual`, and whenever a microphone is running —
    /// `SurfaceRouter.route(rung: .panel, …)` sends the top rung to the badge, and the popover
    /// drew a read-only *"Nudge: Panel"* label: no dismiss, no "this is relevant", no "not this
    /// time", no snooze. `CorrectionAction`'s own rule — *"a nudge you cannot answer back to is
    /// an anti-pattern… Every surface, including the top rung, is dismissible"* — was false for
    /// exactly the people who had asked the system for a calmer one, and U-1's bargain fails at
    /// its root there: the app is licensed to interrupt **because** the answer is one cheap click
    /// that teaches it.
    ///
    /// **The glyph's exemption is a ruling, not an oversight.** The ambient rung says nothing and
    /// accuses nobody; R-87 requires it to keep telling the truth even through a snooze, so there
    /// is no sentence on it to answer and nothing about it that may be taken down.
    /// `LadderRung.Kind.makesAnAccusation` is the other half of that, and
    /// `SurfaceRouterTests.everyRouteCanBeAnsweredBack` joins the two over the routing table.
    /// **The notification's `true` was a claim about a surface that cannot exist** (focus-3vb,
    /// U-2). It read *"the presentation's actions, as notification buttons"*, which describes a
    /// banner nothing can post: no rung routes here since U-2 deferred the recommitment rung, and
    /// P-134 measured that at zero grants every setting reads `.notSupported` and `add(_:)` fails
    /// with `UNErrorDomain` code 1. The cell was not merely unused, it was **load-bearing in the
    /// wrong direction**: `SelfCheck.accusationRouteAudit()` is the 80-cell whole-space fold the
    /// **Release** binary runs, it collects the routes whose surface does not offer an answer, and
    /// with this cell `true` the one fold that covers the space could not see the one outcome U-2
    /// forbids. `everyAccusationRouteCanBeAnswered` would have stayed green with every accusation
    /// on a banner. It is `false` now, so the row is dead in the fold as well as in the router.
    ///
    /// It is deliberately **not** matched by a flip of `holdsTheInterruptionSlot` below, and the
    /// two predicates therefore now differ on two surfaces rather than one. The conservative
    /// direction is opposite for the two questions: a banner that somehow reached a screen really
    /// would take the person's attention, so the slot answer errs towards `true`; and a banner
    /// nobody can post offers nobody anything, so the answerability answer errs towards `false`.
    /// Erring the other way in either case is a fold that cannot fail.
    public var offersAnAnswer: Bool {
        switch self {
        case .panel, .popoverBadge: true
        case .menuBar, .notification: false
        }
    }

    /// **Whether a nudge placed here occupies the one interruption slot the moment it lands.**
    ///
    /// Not the same question as `offersAnAnswer` above, and the pair differ in exactly one cell
    /// for exactly one reason: **the badge is an invitation, not a delivery** (focus-kby). The
    /// popover opens only when a person clicks the status item, so a nudge routed there has
    /// reached nobody yet — it is answerable *once looked at*, and until then it is no more on
    /// screen than the glyph is.
    ///
    /// | surface | holds the slot | why |
    /// |---|---|---|
    /// | `panel` | **yes** | it is on screen, and every action is in reach |
    /// | `notification` | **yes** | its buttons are live wherever the banner is |
    /// | `menuBar` | no | nothing can take an ambient glyph down |
    /// | `popoverBadge` | no | it is behind a click nobody has made yet |
    ///
    /// It arrived as `PreemptionCredit`'s test for whether a displaced question had been handed
    /// something richer in its place, and it outlived preemption because it answers a question the
    /// interruption slot needs answered too: **a rung standing on a surface nobody is looking at
    /// is not occupying the screen** (focus-k42). A glyph or a badge that held the slot would
    /// hold it for the life of the session.
    ///
    /// It was called `offersACorrection`, which stopped being true of the badge the moment the
    /// popover grew the correction economy (focus-uru). The values are unchanged; the name now
    /// says which of the two questions it answers.
    public var holdsTheInterruptionSlot: Bool {
        switch self {
        case .panel, .notification: true
        case .menuBar, .popoverBadge: false
        }
    }

    /// **Whether a nudge placed here has reached the person the moment it lands** (focus-xix,
    /// focus-kby).
    ///
    /// | surface | reaches somebody on landing | what happens when it lands |
    /// |---|---|---|
    /// | `panel` | **yes** | the window is ordered front |
    /// | `menuBar` | **yes** | the item is marked `noticing`, in the landing itself |
    /// | `notification` | **yes** | the banner is posted |
    /// | `popoverBadge` | no | it is behind a click nobody has made yet |
    ///
    /// The badge is the only `false`, and it is `false` for **both** kinds of nudge. That is the
    /// whole of this predicate's job: the question path had the rule and the accusation path did
    /// not, so a rung routed here spent one of the day's six accusations, one of its eight
    /// interruptions and a 600-second cooldown on somebody who had been shown nothing but the
    /// glyph they already had. `NudgeHost` now asks *this* rather than remembering it twice, and
    /// `NudgeHost.popoverPresented()` is the one moment either kind may be counted.
    ///
    /// **`.menuBar`'s `true` was a promise nothing kept, and `menuBarAttention` below is the
    /// keeping of it** (focus-mkk). The row above used to read *"the glyph is redrawn on the next
    /// refresh"*. It was not: the item was drawn from the status and the timer alone, and the
    /// status has been `.unrelated` for the ninety seconds the mandate took to form, so nothing
    /// changed — not the glyph, not the title, not the VoiceOver announcement — while the landing
    /// spent an accusation, an interruption and a ten-minute cooldown. This cell is now true
    /// because the cell below makes it true, and the proof of it counts writes to the status item
    /// rather than reading this predicate back.
    ///
    /// **Deliberately not `holdsTheInterruptionSlot` re-spelled**, though the two agree in three
    /// of four cells. The glyph is on screen the moment it lands *and* occupies no screen a
    /// second nudge could want, so the cells differ exactly where the two questions do. One
    /// predicate for both would make *"the person saw it"* and *"the screen is busy"* one
    /// statement, which is the identity focus-k42 spent a round undoing.
    public var reachesThePersonOnLanding: Bool {
        switch self {
        case .panel, .menuBar, .notification: true
        case .popoverBadge: false
        }
    }

    /// **What the status item itself must say while a nudge is standing on this surface**
    /// (focus-mkk, focus-2xw).
    ///
    /// | surface | the item says | why |
    /// |---|---|---|
    /// | `menuBar` | `noticing` | the ambient rung *is* the item; if it changes nothing, rung 1 of a two-rung ladder does not exist |
    /// | `popoverBadge` | `waiting` | the popover opens only on a click, and nothing was asking for one |
    /// | `panel` | `unmarked` | it is a window in front of the person; the menu bar has nothing to add |
    /// | `notification` | `unmarked` | the banner is the surface, and no rung routes to one (U-2) |
    ///
    /// **This is the missing half of `reachesThePersonOnLanding`, and its absence was the
    /// defect.** That predicate answers `true` for `.menuBar` on the stated ground that *"the
    /// glyph is redrawn on the next refresh"* — and nothing redrew it. `MenuBarPresentation`
    /// carried the status, the timer and the popover's contents, and the item was a function of
    /// those alone: `currentStatus` never read the ladder, the announcement fired on a
    /// `FocusStatus` change, and a mandate needs ninety seconds of sustained drift, so the status
    /// had already been `.unrelated` throughout. Measured on the shipping loop with a real
    /// installed `NSStatusItem` — seven drifts, seven hundred seconds apart: six delivered rows,
    /// the whole day's accusation cap spent, the query budget squeezed from four to one, and
    /// **one** write to the menu bar, made before the first rung existed.
    ///
    /// So the predicate above is now a claim this one has to make good on: a surface that reaches
    /// somebody in the menu bar the moment it lands must mark the item, and the mark is a write
    /// a test can count. `MenuBarControllerAttentionTests` counts them; `NudgeSurfaceTests` joins
    /// the two columns so a future `true` in the left one with `unmarked` in the right one is a
    /// build that does not pass.
    ///
    /// Stated **here**, on the surface, for the reason `reachesThePersonOnLanding` is: the
    /// question path and the accusation path both reach the badge and only the rung reaches the
    /// glyph, so a rule written at either call site is a rule the other half can be missing.
    public var menuBarAttention: MenuBarAttention {
        switch self {
        case .menuBar: .noticing
        case .popoverBadge: .waiting
        case .panel, .notification: .unmarked
        }
    }

    /// Whether this surface belongs to the application itself rather than to the system.
    ///
    /// The three in-app surfaces are what make the `notification-denied` gate stage possible:
    /// every rung is deliverable with no grant of any kind, which is what discharges standing
    /// condition 5 for this epic.
    public var isInApp: Bool { self != .notification }

    /// Whether reaching this surface needs a TCC-style authorisation the user may refuse.
    public var requiresNotificationAuthorisation: Bool { self == .notification }
}

/// **What the menu-bar item is saying about a nudge, over and above the status** (focus-mkk,
/// focus-2xw).
///
/// Three states, and the middle one exists because U-2's ladder has two rungs and the lower one
/// *is* the status item. A rung that changes nothing in the menu bar is not a quieter rung; it is
/// no rung at all, charged at the price of one.
///
/// ## Why the two marks are different marks
///
/// `.waiting` asks for a click and `.noticing` does not, and that difference is the whole of
/// `LadderRung.Kind.makesAnAccusation` seen from the menu bar. R-87 keeps the ambient rung on
/// through a snooze precisely because it is a *state* rather than a sentence — there is nothing
/// on it to answer — while a badge nudge is a question or an accusation sitting behind a click
/// nobody has been invited to make. One mark for both would invite a click that finds nothing to
/// press, which is the badge defect run backwards.
///
/// ## The channel, and why it is the glyph and not the title
///
/// P-133 measured the proportional system font jittering the menu-bar title by 7.69 pt between
/// `11:11` and `88:88`, which is why the timer is drawn in `monospacedDigitSystemFont`. An
/// indicator that lengthened that string would shove every item to its left once a second, so the
/// mark is drawn **into the glyph, at the glyph's own size**: the item's width is untouched, and
/// `MenuBarTitleWidthTests` still holds.
///
/// The mark is a shape, never a colour (F-146), and it carries a sentence for VoiceOver, because
/// `MenuBarController.announceStatusChange` was keyed to `FocusStatus` and a rung landing changes
/// no status.
public enum MenuBarAttention: String, Sendable, CaseIterable, Codable, Hashable, Comparable {
    /// Nothing is standing anywhere the menu bar speaks for. The item is the status and the
    /// timer, exactly as it has always been.
    case unmarked
    /// **The ambient rung is on the glyph itself.** The app has escalated to saying *something*,
    /// and this is the whole of what it says. Nothing to answer, and no click asked for.
    case noticing
    /// **A nudge is waiting behind the click.** Either kind: the badge carries the question and
    /// the accusation through one surface, so it carries one mark.
    case waiting

    /// Rank, derived from `allCases` exactly as `LadderRung.Kind.rank` is (R-96j).
    public var rank: Int { Self.allCases.firstIndex(of: self) ?? Self.allCases.count }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }

    /// Whether the item carries a mark at all — the reading a write-counting test asserts on.
    public var marksTheItem: Bool { self != .unmarked }

    /// Whether this mark is inviting a click, which is the half `.noticing` must not claim.
    public var invitesAClick: Bool { self == .waiting }

    /// The String Catalog key for the sentence VoiceOver reads, or `nil` for the unmarked item —
    /// which has nothing to add and must not add a word.
    ///
    /// `nil` rather than an empty key: an empty sentence appended to the status label would read
    /// as a pause to somebody listening, and `check-strings.sh` would bless a key nothing says.
    public var copyKey: String? {
        switch self {
        case .unmarked: nil
        case .noticing: "nudge.attention.noticing"
        case .waiting: "nudge.attention.waiting"
        }
    }

    /// The sentence itself, resolved against `FocusCore`'s own bundle, in the shape
    /// `FocusStatus.shortLabelResource` already ships.
    public var copyResource: LocalizedStringResource? {
        guard let copyKey else { return nil }
        return LocalizedStringResource(
            String.LocalizationValue(copyKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }
}

/// Whether the system will deliver a notification for us.
///
/// A **plain** enum. `FocusCore` imports no UserNotifications — the R-14 matrix forbids it —
/// so this package does not name `UNAuthorizationStatus` and does not pretend to read it. The
/// mapping from the framework's raw status lives at the boundary, in `NotificationDelivery`
/// (T137), where the import is permitted; here it is four cases and their two rulings.
///
/// P-134 settles the shape: `getNotificationSettings` is obtainable at zero grants, **never
/// prompts**, and answers completely — so what this app knows about notifications, it knows
/// without ever asking anybody anything.
///
/// **It decides nothing, and that is the whole of its remaining job** (focus-wy0). This app posts
/// no notifications: since U-2 no rung routes to one, and `SurfaceRouter` does not take this type
/// at all. What is left is a *reading* — reported by the self-check so the `notification-denied`
/// gate stage can say what grant state this Mac was actually in when it proved the app works
/// without one. A reading is evidence. It is not a switch, and this type deliberately no longer
/// offers one:
///
/// * `permitsDelivery` went with `deliver(…)`. An app that delivers nothing has no business
///   publishing a belief about whether it may.
/// * `mayOfferToEnable` went with the button it gated. It answered `true` for `notRequested`
///   alone — which is **every fresh install** — so the pane offered a system permission prompt to
///   everybody who had never seen one, for a capability the router could not spend.
public enum NotificationAuthorisation: String, Sendable, CaseIterable, Codable, Hashable {
    /// The user said yes.
    case authorised
    /// The user said no.
    case denied
    /// Nobody has asked, and since focus-wy0 nothing in this app ever will. P-134 measured
    /// `authorizationStatus == 0` from an ad-hoc-signed bundle that never called
    /// `requestAuthorization`, with every setting `.notSupported`.
    case notRequested
    /// Provisional (quiet) delivery.
    case provisional
}

/// **Which surface a rung reaches, or why none can.**
///
/// The router's answer. It is deliberately not a `NudgeSurface?`: an absent surface has a
/// reason, the reason is what the record carries and what a person is told, and an `Optional`
/// would throw it away at exactly the moment R-81 needs it — `deferred` must be
/// distinguishable from `delivered`, and a `nil` surface with no reason attached cannot be.
public enum SurfaceRoute: Sendable, Equatable, Hashable {
    /// The rung reaches this surface.
    case surface(NudgeSurface)
    /// No surface can carry it in the state the app is actually in. The payload becomes
    /// `RungDelivery.deferred(_:)` and `InterventionRecord.disposition == "deferred"`.
    case unavailable(DeferralReason)

    /// The surface, when there is one.
    public var surface: NudgeSurface? {
        switch self {
        case .surface(let surface): surface
        case .unavailable: nil
        }
    }

    /// Why there is none, when there is none.
    public var deferralReason: DeferralReason? {
        switch self {
        case .surface: nil
        case .unavailable(let reason): reason
        }
    }

    /// The delivery this route produces once it has been acted on.
    ///
    /// The one sanctioned bridge between the router's answer and the ladder's input, so that
    /// "the route said no surface" and "the rung was deferred" cannot drift apart.
    public var delivery: RungDelivery {
        switch self {
        case .surface(let surface): .delivered(surface)
        case .unavailable(let reason): .deferred(reason)
        }
    }
}
