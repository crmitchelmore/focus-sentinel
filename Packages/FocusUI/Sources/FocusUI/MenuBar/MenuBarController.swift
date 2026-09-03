import AppKit
import FocusCore
import SwiftUI

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

    /// **The item was actually written to** — the wire that makes a charge a *consequence* of a
    /// write rather than a sibling of one (focus-1b5, focus-nrl).
    ///
    /// Fired at the end of `redraw(force:)`, and only when the picture or the announcement really
    /// changed. The composition root joins it to `NudgeHost.menuBarItemRedrawn()`, which is the
    /// only place in the programme a glyph rung is ever charged.
    ///
    /// ## Why this exists rather than the loop asking
    ///
    /// The loop *did* ask, and the asking is the shape three rounds of this defect kept: the
    /// host requested a redraw and then charged, on the ground that the item would change. It
    /// did not — the request is coalesced away when two consecutive rungs compose the same
    /// picture (focus-1b5), and the picture is the badge's rather than the rung's whenever a
    /// badge nudge is pending (focus-nrl). A request is not a write, and only the object that
    /// makes the assignment knows the difference.
    ///
    /// It carries no payload: the listener reads `glyphWriteCount` and `markOnTheItem` back,
    /// which are what the item *is*, rather than being handed a description of the pass that it
    /// would then have to trust.
    public var onGlyphWritten: (() -> Void)?

    /// **The size the popover is laid out at, and what gives way when it will not fit**
    /// (focus-5yu, focus-din).
    ///
    /// A pair rather than a size alone, because a clipped action is invisible *and* unreported
    /// while a scrolled one is not — and neither is a nudge that may be charged until
    /// `decisionSurfaceReading(of:)` says every action is in reach.
    ///
    /// **The flag became three values** (focus-din). *Does this scroll?* had no answer that let a
    /// scrolling popover ever be charged: at `accessibilityLarge` on a 1080-point display every
    /// state of this surface scrolls, so a large-text user's badge rung was never delivered and
    /// the ladder parked. `DecisionSurfaceOverflow` says **what** scrolls, and its middle value
    /// keeps the corrections and the answers in the viewport while the command centre above them
    /// gives way.
    public struct PopoverLayout: Sendable, Equatable, Hashable {
        public let size: CGSize
        public let overflow: DecisionSurfaceOverflow

        public init(size: CGSize, overflow: DecisionSurfaceOverflow) {
            self.size = size
            self.overflow = overflow
        }

        /// Whether anything gives way at all. The reading `MenuBarPopoverLayoutTests` takes.
        public var scrolls: Bool { overflow != .nothingScrolls }

        /// What a popover that has never been built is laid out at: nothing at all. Read as a
        /// content bounds it contains no action, which is what default-deny requires of a
        /// surface nobody has drawn.
        public static let unbuilt = PopoverLayout(size: .zero, overflow: .nothingScrolls)
    }

    /// **The width the popover commits to** (focus-5yu).
    ///
    /// The number every committed `menuBarPopover.*.png` baseline was already rendered at, which
    /// is exactly why it was not a fact about the product: the snapshot lane supplied it, and the
    /// shipping controller supplied nothing. Committing it here is what turns those pictures
    /// into pictures of the layout the app actually draws.
    public static let popoverContentWidth: Double = 300

    /// **The popover brings no inset of its own.**
    ///
    /// `MenuBarPopoverView.body` already pads itself by its own scaled spacing, and a second
    /// inset here would be a margin nobody chose, growing with the text scale twice over. It is
    /// stated as a constant rather than as a bare literal at the two call sites so that the
    /// measurement and the live layout cannot be given different ones.
    public static let popoverContentInset: Double = 0

    /// The margin between the bottom of the popover and the bottom of the display's visible
    /// frame. The panel's own `edgeMargin`, for the same reason: a surface flush against the
    /// edge of the screen reads as clipped whether it is or not.
    public static let popoverEdgeMargin: Double = 24

    /// **What the popover's own chrome costs, on top of its content.**
    ///
    /// Measured, not assumed: the real popover's window read 855 points tall around a content
    /// view of 829, and 3127 around 3101 — 26 points in both, which is the arrow and the border
    /// AppKit draws around whatever it is given. The ceiling is a statement about the **window**
    /// fitting under the menu bar, so the content's ceiling has to be that much lower.
    public static let popoverChromeAllowance: Double = 26

    /// How far over the ceiling a measurement may land before the content is given a scroll
    /// view. One point, for `NudgePanelController.sizeTolerance`'s reason: a layout escape is
    /// measured in hundreds or thousands of points and a rounding difference in fractions of one.
    public static let popoverSizeTolerance: Double = SurfaceSizeCommitments.tolerance

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    /// **Which displays the popover is being laid out against** (focus-5yu).
    ///
    /// A closure for `NudgePanelController.displays`'s reason: the shipping app reads
    /// `NSScreen.screens` and a test hands over a display of its own, so the clamp and the scroll
    /// past it are drivable without a second Mac.
    public var displays: @MainActor () -> [DisplayGeometry] = {
        NudgePanelController.currentScreens()
    }
    /// The size the **current** popover content view controller was built at. Read by
    /// `decisionSurfaceReading(of:)` as the content a person can see, so a reading is taken
    /// against the layout that is on screen rather than against a constant.
    private var popoverLayout = PopoverLayout.unbuilt
    /// Which layout pass the popover is on, stamped into the action frames it reports so that
    /// two identical layouts are two distinguishable readings and a replaced layout's frames can
    /// be refused rather than believed.
    private var popoverLayoutGeneration = 0
    /// Where the popover's actions actually landed, as the layout itself reported them.
    private var reportedPopoverFrames = NudgeActionFrameSet.empty
    /// **What the item was last asked to draw.** `private(set)` since e08a: the notch companion is
    /// a second renderer of this same value, and the self-check compares the two so that "one
    /// projection, drawn twice" is a comparison rather than a claim. It is deliberately not the
    /// reading a charge rests on — that is `markOnTheItem`, off `drawnGlyph`, which is what was
    /// *assigned* rather than what was *asked for*.
    public private(set) var presentation = MenuBarPresentation(status: .uncertain)
    private var traits: AppearanceTraits = .systemDefault
    /// **Everything the popover's content was last built out of** (focus-tzj.1).
    ///
    /// `nil` until something has been built, which is why the first refresh after an install is
    /// always a build: a popover holding no content view controller is not a popover whose
    /// content is current, whatever the presentation says.
    private var builtPopoverKey: PopoverBuildKey?
    /// **How many times the popover's content view controller has really been rebuilt.**
    ///
    /// The number focus-tzj.1 is about. `update(_:)` is called on every accepted activation and
    /// every five-second corroboration tick, and while the popover was open each of those
    /// assigned a freshly built `NSHostingController` — a whole SwiftUI hierarchy discarded and
    /// remade for a presentation that had not moved. It is a count of assignments and not of
    /// requests, for `glyphWriteCount`'s reason: a reading that could be satisfied by asking is
    /// not a reading of what the app did.
    public private(set) var popoverContentBuildCount = 0
    /// **How many `NSHostingController`s those rebuilds really constructed.**
    ///
    /// Three per rebuild, not one, and that is the measurement rather than an assumption: the
    /// content is one, and `popoverLayout(measuring:)` builds one more for the whole surface and
    /// one for its decision, because a wrapped height is not a value SwiftUI will answer without
    /// a host. Published beside the build count so the amplification is visible rather than
    /// inferred — a future measurement that stopped needing a host would show up here as a
    /// change in the ratio, and a fourth construction sneaking into the build path likewise.
    public private(set) var popoverHostingConstructions = 0
    /// The last string actually written to the button. The coalescing cadence is this
    /// comparison and nothing else.
    private var drawnTitle: String?
    /// The last **glyph state** actually written: the status's silhouette and the mark on it.
    /// The image used to be assigned on every redraw, unconditionally, which made "the item
    /// changed" unobservable — every tick wrote the same picture.
    private var drawnGlyph: DrawnGlyph?
    /// The last accessibility label actually written.
    private var drawnAccessibilityLabel: String?
    /// The last thing **announced**. VoiceOver hears a state change once, when it happens —
    /// not once per corroboration tick, which would be the app reading the same word aloud
    /// every five seconds (F-144, F-146).
    ///
    /// **Keyed on the glyph state, not on `FocusStatus`** (focus-mkk). It was the status alone,
    /// and a rung landing changes no status — a mandate needs ninety seconds of sustained drift,
    /// so by the time one exists the status has been `.unrelated` throughout. Somebody who cannot
    /// see the glyph was told nothing at all, on the one rung whose entire content is the glyph.
    /// It is deliberately **not** keyed on the accessibility label, which carries the timer: that
    /// would read the item aloud once a second while a snooze runs.
    private var announcedGlyph: DrawnGlyph?
    /// How many times the title has actually been rewritten. Reported by the self-check, so
    /// "it does not redraw every tick" is a number rather than a promise.
    public private(set) var titleWriteCount = 0
    /// **How many times the glyph has actually been rewritten** — the number focus-mkk is about.
    ///
    /// The bead's whole finding is a measurement of this: seven drifts, seven hundred seconds
    /// apart, six delivered rows and *one* write to the menu bar, made before the first rung
    /// existed. A predicate saying the glyph "reaches the person on landing" cannot fail; this
    /// can, and `MenuBarStage` and the self-check read it around a real landing rather than
    /// asserting the predicate back.
    public private(set) var glyphWriteCount = 0
    /// How many announcements have actually been posted, for the same reason.
    public private(set) var announcementCount = 0
    /// The last sentence announced, so a test can say **what** VoiceOver heard rather than only
    /// that something was said.
    public private(set) var lastAnnouncement: String?

    /// **The mark the item is actually drawing right now** (focus-nrl).
    ///
    /// Read off `drawnGlyph` — what was last *assigned* — and never off `presentation`, which is
    /// what was last *asked for*. The two differ exactly where focus-nrl lives:
    /// `MenuBarPresentation.attention` is the maximum of the rung's mark and the badge's, so a
    /// glyph rung standing under a pending badge nudge asks the item for `noticing` and the item
    /// goes on drawing `waiting`. The presentation would report the rung was marked; the button
    /// says it was not, and this is the button's answer.
    public var markOnTheItem: MenuBarAttention { drawnGlyph?.attention ?? .unmarked }

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
        // **Both buttons reach the one action** (focus-odz.2). `NSStatusBarButton` sends on
        // `.leftMouseUp` alone by default, so a right-click on the item did nothing at all;
        // `togglePopover` reads which gesture arrived and shows the menu or the popover.
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
        // **The picture goes with the item it was drawn on** (focus-nrl). `markOnTheItem` is a
        // reading of what a person can see, and there is no item to see: leaving the last mark
        // behind would let a re-installed item be charged for a rung it had never drawn.
        drawnGlyph = nil
        drawnAccessibilityLabel = nil
        announcedGlyph = nil
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
        refreshPopoverContent()
        // A nudge that arrived while the popover was already open is a nudge the person is
        // looking at, and the loop is told for the same reason it is told about an opening.
        //
        // **Either kind** (focus-xix). Set subtraction rather than a pair of `Bool`s, so a rung
        // arriving beside a question that was already there still counts as something new.
        if !presentation.carriedNudges.subtracting(carriedBefore).isEmpty { onPopoverDidShow?() }
    }

    /// **The item's three channels, each written only when its own value changed.**
    ///
    /// It used to be two statements: the image was assigned unconditionally on every redraw and
    /// the title was coalesced behind a `guard … else { return }` — and that `return` took the
    /// accessibility label with it, so the label was written only in the ticks where the *timer
    /// string* happened to differ. Splitting the guard per channel is what makes
    /// `glyphWriteCount` a reading of the glyph rather than a reading of the clock.
    private func redraw(force: Bool) {
        guard let button = statusItem?.button else { return }
        // A figure nobody can see is not a figure worth writing (F-163).
        guard isItemVisible || force else { return }

        // **What the item actually did in this pass**, so `onGlyphWritten` fires on a write and
        // never on a request for one. That distinction is focus-1b5's whole mechanism seen from
        // this end: `setOpenRung(_:)` asked for a redraw only when the composed mark changed, and
        // this function then coalesced on the same value, so a "forced refresh" of two
        // consecutive `noticing` rungs assigned nothing at all.
        var theItemMoved = false

        let glyph = DrawnGlyph(status: presentation.status, attention: presentation.attention)
        if force || glyph != drawnGlyph {
            button.image = Self.glyph(for: glyph.status, attention: glyph.attention)
            drawnGlyph = glyph
            glyphWriteCount += 1
            theItemMoved = true
        }
        button.imagePosition = presentation.timerText.isEmpty ? .imageOnly : .imageLeading
        if announceGlyphChange(button: button, glyph: glyph) { theItemMoved = true }

        let label = Self.accessibilityLabel(presentation)
        if force || label != drawnAccessibilityLabel {
            button.setAccessibilityLabel(label)
            drawnAccessibilityLabel = label
        }

        let title = Self.buttonTitle(presentation)
        if force || title != drawnTitle {
            button.attributedTitle = MenuBarTitle.attributed(title)
            drawnTitle = title
            titleWriteCount += 1
        }

        // **Last, and only on a real assignment.** Everything above has settled, so a listener
        // that reads `glyphWriteCount` and `markOnTheItem` back sees the pass it is being told
        // about rather than a half-written one. The title is deliberately not a reason to fire:
        // it is the clock, it moves once a second, and a charge that could be paid for by the
        // timer ticking would be no charge at all.
        if theItemMoved { onGlyphWritten?() }
    }

    /// **What the item is drawing, as one comparable value** (focus-mkk).
    ///
    /// The status *and* the mark, because the pair is what the silhouette is a function of. Two
    /// separate fields would let a future channel be coalesced against one of them, which is the
    /// shape the unconditional image assignment had.
    private struct DrawnGlyph: Equatable {
        let status: FocusStatus
        let attention: MenuBarAttention
    }

    /// The glyph: the status's own SF Symbol, **template-rendered**.
    ///
    /// Template rendering is what makes the menu bar's own light and dark treatments apply, and
    /// it is also what makes the silhouette the whole signal — P-132 read all five in the real
    /// menu bar and confirmed they are distinguishable in monochrome, which is F-146 satisfied by
    /// the tokens e01 already shipped rather than by colour.
    /// **And the mark, when a nudge is standing somewhere the menu bar speaks for** (focus-mkk,
    /// focus-2xw).
    ///
    /// The mark is drawn *into* the glyph, at the glyph's own size, and the status silhouette is
    /// scaled down uniformly to make room for it. That is a deliberate choice of channel: P-133
    /// measured the menu-bar title jittering 7.69 pt between `11:11` and `88:88` on the
    /// proportional face, which is why the timer is monospaced-digit — an indicator that
    /// lengthened the string would shove every item to its left, and focus-2xw names that shape
    /// as the wrong one. The image's bounds do not change, so the item's width does not either.
    ///
    /// A **filled** dot invites the click and a **hollow** ring does not, which is
    /// `MenuBarAttention`'s two marks and `LadderRung.Kind.makesAnAccusation` seen from the menu
    /// bar. Both are shapes and neither is a colour, so the template rendering below carries them
    /// through the menu bar's own light and dark treatments unchanged (F-146) — and the fine
    /// visual difference between a ring and a dot is deliberately *not* the load-bearing one:
    /// that is `accessibilityLabel(_:)`'s sentence and the announcement, which say in words which
    /// of the two this is.
    nonisolated public static func glyph(
        for status: FocusStatus,
        attention: MenuBarAttention = .unmarked
    ) -> NSImage? {
        let image = NSImage(
            systemSymbolName: status.symbolName,
            accessibilityDescription: status.shortLabel
        )
        image?.isTemplate = true
        guard let image, attention.marksTheItem else { return image }
        return marked(image, attention: attention, describing: status)
    }

    /// The diameter of the mark, as a fraction of the glyph's shorter side.
    nonisolated private static let markShare = 0.44
    /// How much clear space the mark keeps between itself and the silhouette, as a fraction of
    /// its own diameter. This is what the status symbol is scaled down by.
    nonisolated private static let markClearance = 0.3
    /// The ring's stroke, as a fraction of the mark's diameter.
    nonisolated private static let markStrokeShare = 0.28

    /// The status silhouette with the attention mark drawn into its top-trailing corner.
    ///
    /// A drawing handler rather than a pre-rendered asset, because the mark has to sit on
    /// whichever of the five symbols the status happens to be and the composite has to stay a
    /// **template** — the menu bar tints it, and a bitmap with its own colours in it would be the
    /// one thing F-146 forbids.
    nonisolated private static func marked(
        _ symbol: NSImage,
        attention: MenuBarAttention,
        describing status: FocusStatus
    ) -> NSImage {
        let size = symbol.size
        let shorter = min(size.width, size.height)
        let diameter = shorter * markShare
        // Uniform, so a non-square symbol is not stretched on its way to making room.
        let scale = (shorter - diameter * markClearance) / shorter
        let stroke = diameter * markStrokeShare

        let composite = NSImage(size: size, flipped: false) { _ in
            symbol.draw(
                in: NSRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            let mark = NSRect(
                x: size.width - diameter,
                y: size.height - diameter,
                width: diameter,
                height: diameter
            )
            // Template images carry alpha, not colour: what is drawn here is a coverage mask and
            // the menu bar decides the ink.
            NSColor.black.setFill()
            NSColor.black.setStroke()
            switch attention {
            case .waiting:
                NSBezierPath(ovalIn: mark).fill()
            case .noticing:
                let ring = NSBezierPath(ovalIn: mark.insetBy(dx: stroke / 2, dy: stroke / 2))
                ring.lineWidth = stroke
                ring.stroke()
            case .unmarked:
                break
            }
            return true
        }
        composite.isTemplate = true
        composite.accessibilityDescription = accessibilityLabel(
            status: status,
            attention: attention,
            timer: ""
        )
        return composite
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
    ///
    /// **The mark's sentence is part of it** (focus-2xw). The bead's finding is that nothing in
    /// the menu bar said a nudge was waiting *at all* — and for somebody using VoiceOver the
    /// glyph's new dot says nothing whatever, so a mark with no words would repair the defect for
    /// sighted people and leave it standing for everybody else. The phrase comes from
    /// `MenuBarAttention.copyResource`, in `FocusCore`, where the vocabulary lives.
    nonisolated public static func accessibilityLabel(_ presentation: MenuBarPresentation) -> String {
        accessibilityLabel(
            status: presentation.status,
            attention: presentation.attention,
            timer: presentation.timerText
        )
    }

    /// The same sentence from its three parts, so the glyph's own description and the button's
    /// label cannot drift.
    nonisolated static func accessibilityLabel(
        status: FocusStatus,
        attention: MenuBarAttention,
        timer: String
    ) -> String {
        let head = timer.isEmpty ? status.shortLabel : "\(status.shortLabel) \(timer)"
        guard let resource = attention.copyResource else { return head }
        return "\(head). \(String(localized: resource))"
    }

    /// **What VoiceOver is told when the item changes**, with no timer in it.
    ///
    /// Deliberately not `accessibilityLabel(_:)`: that carries the countdown, and announcing it
    /// would read the item aloud once a second while a snooze runs. What changes here is a state,
    /// so what is announced is the state.
    nonisolated static func announcement(
        status: FocusStatus,
        attention: MenuBarAttention
    ) -> String {
        accessibilityLabel(status: status, attention: attention, timer: "")
    }

    /// Say the new state out loud, once (F-144).
    ///
    /// The ambient rung is a **silent** surface for somebody who can see it. For somebody who
    /// cannot, silence would mean the rung never happened — so the one channel it has is
    /// announced, and it is announced on the change rather than on the reading, because a state
    /// that is repeated is not a state that changed.
    ///
    /// **And "the state" is the glyph, not the status** (focus-mkk). Keyed on `FocusStatus` this
    /// could not fire for a rung at all: `InterventionPolicy`'s mandate needs ninety seconds of
    /// sustained drift, so the status has been `.unrelated` since long before the rung existed
    /// and `announcedStatus != presentation.status` was false at the exact moment the app first
    /// had something to say. The rung was silent, invisible **and** unannounced, and it was
    /// charged.
    ///
    /// `.medium` priority: it is a fact about the app, not an interruption. A high-priority
    /// announcement would cut across whatever the person is having read to them, which is a
    /// louder thing than the glyph it describes.
    ///
    /// - Returns: whether anything was actually said. Read by `redraw(force:)`, which fires
    ///   `onGlyphWritten` on a real assignment to either channel — the picture or the sentence —
    ///   and on neither channel being touched, on nothing.
    @discardableResult
    private func announceGlyphChange(button: NSStatusBarButton, glyph: DrawnGlyph) -> Bool {
        guard announcedGlyph != glyph else { return false }
        announcedGlyph = glyph
        let sentence = Self.announcement(status: glyph.status, attention: glyph.attention)
        lastAnnouncement = sentence
        announcementCount += 1
        NSAccessibility.post(
            element: button,
            notification: .announcementRequested,
            userInfo: [
                .announcement: sentence,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
        return true
    }

    // MARK: - The popover

    /// **What the world is, for the secondary menu's enabled states** (focus-6uf, focus-odz.2).
    ///
    /// A closure for `FocusCommandCenter.world`'s reason: the answer is read at the moment the
    /// menu is built, out of the hosts the composition root installed, so a menu opened a second
    /// after a session started is a menu about that session. A pushed value would need somebody
    /// to remember to push it.
    public var commandWorld: @MainActor () -> ShellCommandWorld = { FocusCommandCenter.shared.world }

    /// **Whether this click asked for the menu rather than the popover** (focus-odz.2).
    ///
    /// A right-click, or a left-click with Control held — the Mac's two spellings of the same
    /// gesture, and a person who knows only one of them must not find half a status item. Static
    /// and event-taking so the rule is a value a test can drive rather than a condition only a
    /// real mouse can reach.
    nonisolated public static func isSecondaryClick(_ event: NSEvent?) -> Bool {
        guard let event else { return false }
        switch event.type {
        case .rightMouseUp, .rightMouseDown:
            return true
        case .leftMouseUp, .leftMouseDown:
            return event.modifierFlags.contains(.control)
        default:
            return false
        }
    }

    /// **The secondary menu, built from the declared table** (focus-odz.2).
    ///
    /// `public` because it is what the self-check reads: the titles and enabled states the gate
    /// pins are the ones this function really produced, resolved against the app's own bundle,
    /// rather than a second rendering of the table taken in the script.
    ///
    /// `autoenablesItems = false` because AppKit's automatic enabling walks the responder chain
    /// for a selector's validation, and every item here is bound to one method on this object —
    /// so left to itself AppKit would enable all four whatever `isAvailable(in:)` said. The
    /// predicate is the app menu's, and this is what makes it the one that decides.
    public func secondaryMenu() -> NSMenu {
        let menu = NSMenu(title: ShellStrings.string(.menuBarStatusItem))
        menu.autoenablesItems = false
        let world = commandWorld()
        let paused = presentation.sensingPaused
        for entry in StatusItemMenuItem.allCases {
            if entry.isPrecededBySeparator { menu.addItem(.separator()) }
            let item = NSMenuItem(
                title: ShellStrings.string(entry.titleKey(sensingPaused: paused)),
                action: #selector(performSecondaryItem(_:)),
                keyEquivalent: ""
            )
            item.target = self
            // The item carries its own identity rather than an index into `allCases`: a case
            // inserted in the middle of that enum would otherwise silently re-point every item.
            item.representedObject = entry.rawValue
            item.isEnabled = entry.isAvailable(in: world)
            menu.addItem(item)
        }
        return menu
    }

    /// Show it under the item, then take it off again.
    ///
    /// `NSStatusItem.menu` is the only supported way to pop a menu from a status item, and it is
    /// *modal*: while it is set, a left click opens the menu instead of the popover. So it is set
    /// for the length of one click and cleared immediately, which is what leaves the primary
    /// gesture alone.
    private func showSecondaryMenu() {
        guard let statusItem else { return }
        statusItem.menu = secondaryMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc
    private func performSecondaryItem(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let entry = StatusItemMenuItem(rawValue: raw)
        else { return }
        onAction?(entry.action(sensingPaused: presentation.sensingPaused))
    }

    @objc
    public func togglePopover() {
        guard let button = statusItem?.button else { return }
        // **The secondary gesture first** (focus-odz.2). One action is installed for both mouse
        // buttons — `sendAction(on:)` in `install()` — because a status item has one action, so
        // which gesture arrived is a fact about the event rather than about the binding.
        if Self.isSecondaryClick(NSApplication.shared.currentEvent) {
            showSecondaryMenu()
            return
        }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        refreshPopoverContent()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        onPopoverDidShow?()
    }

    /// **Build the popover's content, but only out of something that has moved** (focus-tzj.1).
    ///
    /// ## What this used to be, and what it cost
    ///
    /// `update(_:)` assigned `popover.contentViewController = popoverController()` on every call
    /// where the popover happened to be open — every accepted activation and every five-second
    /// corroboration tick — and `popoverController()` constructs one `NSHostingController` for
    /// the content and, through `popoverLayout(measuring:)`, two more for the measurement. So an
    /// open popover cost **three SwiftUI hosts per tick**, thirty-six a minute, to redraw a
    /// surface whose every input was the same value it had five seconds earlier. It also
    /// re-stamped `popoverLayoutGeneration`, which invalidates the action frames the layout
    /// reported: for the moment between the assignment and SwiftUI delivering the new
    /// preference, `decisionSurfaceReading(of:)` sees no action targets at all and refuses a
    /// charge for a popover the person is looking at.
    ///
    /// ## What decides it
    ///
    /// Everything `popoverController()` reads, as one comparable value: the presentation, the
    /// traits, and the displays the layout is clamped against. All three are value types and the
    /// comparison is over the whole of them, so a field added to `MenuBarPresentation` is
    /// diffed by construction rather than by somebody remembering to add it here — which is the
    /// failure mode a hand-written "did anything important change?" predicate has.
    ///
    /// A popover holding no content view controller is never current, whatever the key says: an
    /// empty popover is not a drawn one, and `togglePopover()` leans on exactly that to reuse a
    /// content it built before the last close.
    ///
    /// It is `public` because it is what a tick does, and the self-check measures the tick by
    /// calling it — the same function, with the same staleness test, on the same builder. It
    /// deliberately does not read `popover.isShown`: whether a tick is worth spending is
    /// `update(_:)`'s question, and re-placing an open popover is `reanchorPopover()`'s, which
    /// keeps its own guard.
    public func refreshPopoverContent() {
        let key = PopoverBuildKey(presentation: presentation, traits: traits, screens: displays())
        guard popover.contentViewController == nil || key != builtPopoverKey else { return }
        let sizeBefore = popoverLayout.size
        popover.contentViewController = popoverController(screens: key.screens)
        builtPopoverKey = key
        popoverContentBuildCount += 1
        // **Only when the size really changed** (focus-5yu). Re-placing it every time would ask
        // AppKit to show an already-shown popover once a tick — a repeated show under a person's
        // cursor — for a size that has not moved. It moves when a nudge arrives or leaves, which
        // is exactly when the content changed anyway.
        if popoverLayout.size != sizeBefore { reanchorPopover() }
    }

    /// **What the popover's content was built out of**, as one value.
    ///
    /// A `struct` of the three inputs rather than three stored fields, so the staleness test is
    /// one `!=` over the whole of them and cannot be written for two of the three.
    private struct PopoverBuildKey: Equatable {
        let presentation: MenuBarPresentation
        let traits: AppearanceTraits
        /// The displays the layout was clamped against. A display arriving, leaving or changing
        /// resolution moves the ceiling `popoverMaximumContentHeight(screens:)` computes, so a
        /// content built against the old geometry is stale even when nothing the person did
        /// changed — and `NudgeHostDisplayChangeTests` is about exactly that transition.
        let screens: [DisplayGeometry]
    }

    /// **Put an already-open popover back under the item it hangs from** (focus-5yu).
    ///
    /// A nudge arriving in a popover somebody is already looking at replaces its content view
    /// controller, and the replacement is a different height. Measured on the real popover,
    /// opened on a plain status row and then handed a question: it read (1383, 830, 326, 466) —
    /// the origin it had at the smaller size, with the new height — so it spanned 830 → 1296 on a
    /// 1080-point display. It had grown **upward**: 216 points above the top of the screen, its
    /// arrow nowhere near the item, and the question in the part that was gone. Asked for again
    /// after the assignment, the same popover reads (1383, 588, 326, 466) — top edge at 1054,
    /// under the item, whole.
    ///
    /// `NSPopover` re-lays-out for a new content size but does not re-place itself for one, so
    /// the placement is asked for again here — the same call `togglePopover()` makes, with the
    /// same anchor. Re-showing an already-shown popover moves it; it does not close it, and it
    /// posts no second appearance, which is why `onPopoverDidShow` stays where it is and is
    /// still fired once, for the nudge rather than for the placement.
    ///
    /// Placed after the assignment, never before: the popover has to be holding the content it
    /// is being placed for, or it would be re-anchored at the size of the thing it is replacing.
    private func reanchorPopover() {
        guard popover.isShown, let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    public var isPopoverShown: Bool { popover.isShown }

    /// **Whether the popover's picture contains one kind of nudge** (focus-kby, focus-xix, U-1).
    ///
    /// Both halves are load-bearing and both were knowable and unread: a popover that is open
    /// but showing snoozes is not showing a nudge, and a nudge in a popover nobody has opened is
    /// a nudge nobody has seen.
    ///
    /// **It takes the kind as an argument**, because it used to exist for the question alone
    /// (`isShowingQuery`, ten call sites) and not at all for a rung (zero) — which is precisely
    /// the shape of focus-xix: the loop could not ask whether the accusation had been looked at,
    /// so it assumed.
    ///
    /// ## This is not the reading a charge may be taken on, and it was called `isShowing`
    ///
    /// Under that name it was read as the whole of the badge route's readability, and it is two
    /// booleans: a popover 3127 points tall with its arrow at the menu bar satisfies both of them
    /// while every correction it offers is above the top of the display. `decisionSurfaceReading(of:)`
    /// is the reading, this is one of its conjuncts, and the rename is what makes the difference
    /// a compiler error at every call site rather than a distinction a reader has to hold.
    ///
    /// It survives as its own question because the **orphan** invariant asks exactly it:
    /// `NudgeHost.orphanedNudgeSurfaces` is about a nudge the host has forgotten while a person
    /// can still press something on it, and an action scrolled below the fold is one scroll away
    /// from being pressed. Answering that question with the stricter reading would file the
    /// dangerous case as no case at all.
    public func isDrawing(_ nudge: MenuBarNudge) -> Bool {
        popover.isShown && presentation.isCarrying(nudge)
    }

    /// **Whether the popover is a surface a person could actually decide on** (focus-5yu,
    /// focus-vpu, focus-kby, U-1).
    ///
    /// The panel has had this reading since focus-vpu and the popover had nothing: the badge's
    /// delivery was counted on `popover.isShown && presentation.isCarrying(nudge)` — two booleans,
    /// never a geometry — so a rung whose Pause and Change priority were off the bottom of the
    /// display still spent one of the day's six accusations, one of its eight interruptions, and
    /// armed the 600-second cooldown. Measured before the repair: the real popover stood 483
    /// points above the top of a 1080-point display with a 21-character priority, and 2755 with a
    /// 185-character one.
    ///
    /// It is the panel's own predicate, on the panel's own value type, taken with four
    /// differences that are all facts about this surface rather than choices:
    ///
    /// * **`isVisible` is `isDrawing(_:)`**, not `NSPopover.isShown` alone. A popover open on
    ///   snoozes is not a surface for a nudge that is not in it — and without that conjunct the
    ///   reading would be vacuously true whenever the popover carries nothing, because a nudge
    ///   that is not there offers no actions to find missing.
    /// * **The offered actions are read off the presentation this controller is drawing**, so
    ///   the set that is required to be reachable and the set that was drawn cannot be two
    ///   different lists.
    /// * **The content bounds are the size the popover was laid out at**, which is a fact since
    ///   `popoverController()` committed one and was not before.
    /// * **The container is the display's whole frame, not its visible frame.** Measured: the
    ///   shipping popover's window reads (1384, 300, 326, 754) on a display whose visible frame
    ///   is (0, 89, 1920, 961) — its top edge stands 4 points inside the menu-bar strip that
    ///   `visibleFrame` excludes, because that is where its arrow points. Judged against
    ///   `visibleFrame` a perfectly drawn popover would read "not wholly on a display", and every
    ///   badge nudge in the programme would be unchargeable for a reason that is about the menu
    ///   bar rather than about the person.
    public func decisionSurfaceReading(of nudge: MenuBarNudge) -> DecisionSurfaceReading {
        SurfaceMeasurer.reading(
            isVisible: isDrawing(nudge),
            surfaceFrame: popoverFrame,
            screens: Self.popoverContainers(displays()),
            contentSize: popoverLayout.size,
            actionFrames: currentPopoverActionFrames,
            offering: offeredIdentifiers(of: nudge)
        )
    }

    /// Every action the popover is offering for one kind of nudge, by the identifier the layout
    /// reports it under. Empty when it is carrying no nudge of that kind — which is a true
    /// statement about a surface that is offering nothing, and never a reachable one, because
    /// `isDrawing(_:)` is a conjunct of the reading above.
    public func offeredIdentifiers(of nudge: MenuBarNudge) -> [String] {
        switch nudge {
        case .query: presentation.pendingQuery?.offeredAnswerIdentifiers ?? []
        case .accusation: presentation.pendingAccusation?.offeredActionIdentifiers ?? []
        }
    }

    /// The popover's own window, as AppKit placed it, or `.zero` when there is no popover on
    /// screen to have one — which reads as "not wholly on a display" and refuses the charge.
    public var popoverFrame: ScreenRect {
        guard let window = popover.contentViewController?.view.window else { return .zero }
        return ScreenRect(
            x: window.frame.origin.x,
            y: window.frame.origin.y,
            width: window.frame.width,
            height: window.frame.height
        )
    }

    /// The size the popover was last laid out at. Published so the self-check and the test lane
    /// can read the number the shipping controller committed to rather than one they supplied.
    public var currentPopoverLayout: PopoverLayout { popoverLayout }

    /// **The containers a popover has to fit inside** (focus-5yu).
    ///
    /// Each display, with its visible frame replaced by its whole frame. See
    /// `decisionSurfaceReading(of:)`: a popover hangs from the menu bar and its arrow is drawn in
    /// the strip `visibleFrame` excludes, so the visible frame is the wrong container for this
    /// surface and the right one for the panel, which is placed inside it deliberately.
    public static func popoverContainers(_ screens: [DisplayGeometry]) -> [DisplayGeometry] {
        screens.map { display in
            DisplayGeometry(
                displayID: display.displayID,
                screenIndex: display.screenIndex,
                isPrimary: display.isPrimary,
                frame: display.frame,
                visibleFrame: display.frame,
                backingScaleFactor: display.backingScaleFactor
            )
        }
    }

    /// The frames the **current** popover layout reported, and nothing else.
    ///
    /// A layout that has been replaced describes a popover nobody is looking at any more; under
    /// default-deny the honest answer for one is "no frames", which reads as unreachable rather
    /// than as reachable-because-it-used-to-be.
    private var currentPopoverActionFrames: [String: CGRect] {
        reportedPopoverFrames.generation == popoverLayoutGeneration ? reportedPopoverFrames.frames : [:]
    }

    public func closePopover() {
        popover.performClose(nil)
    }

    /// **The popover, laid out into a width it commits to** (focus-5yu, focus-vpu).
    ///
    /// ## What this used to be, and what it measured
    ///
    /// It used to be one expression: `NSHostingController(rootView: MenuBarPopoverView(…))`,
    /// handed to `NSPopover` with no width, no `preferredContentSize`, no min or max, and no
    /// scroll view. `MenuBarPopoverView.body` is a `VStack` whose first row is the person's own
    /// priority as `Text(verbatim:)` with `lineLimit(nil)`, and `IntentValidator` bounds that
    /// sentence only from **below** — two tokens, three characters — so the container's ideal
    /// width was whatever the person typed, set on one line.
    ///
    /// Measured on the real popover, opened on a 1920 × 1080 display whose visible frame is
    /// 1920 × 961:
    ///
    /// | priority | window | content |
    /// |---|---|---|
    /// | `"Write the Q3 proposal"` | 346 × **855** at y = 708 | 320 × 829 |
    /// | 185 characters | 346 × **3127** at y = 708 | 320 × 3101 |
    ///
    /// Both are placed as though they were about 340 points tall, so the short one stands 483
    /// points above the top of the display and the long one 2755 — with the priority, the
    /// accusation and the question all in the part that is off screen. `NSPopover.contentSize`
    /// read (320 × 320) throughout, which is AppKit's default and nobody's decision, and the
    /// hosting view's `fittingSize` read 469 × 186 and then 1255 × 186 — the unconstrained
    /// number, agreeing with neither the window nor the content.
    ///
    /// ## The panel's four commitments, on the panel's twin
    ///
    /// `NudgePanelController.layOutContent()` fixed exactly this defect for the window that
    /// draws the *same* `AccusationPanelView` and `QueryPanelView`, and its four parts are the
    /// four this needs:
    ///
    /// * the **width** is committed — `popoverContentWidth` — so the person's sentence wraps
    ///   into a column instead of setting the surface's width;
    /// * the **height** is measured at that width through `sizeThatFits(in:)`, which is the
    ///   *wrapped* height and is not `NSView.fittingSize`, the unconstrained number above;
    /// * it is **clamped** to what the display below the menu bar can hold;
    /// * and content taller than the clamp **scrolls**, so nothing is ever cut off.
    ///
    /// The fifth thing is this surface's own and is why the content is wrapped in
    /// `NudgePanelContent`: the popover now **reports where its actions landed**, which is what
    /// `decisionSurfaceReading(of:)` reads and what stops a badge nudge being charged to somebody
    /// whose Pause button is off the bottom.
    ///
    /// - Parameter screens: the displays the layout is clamped against, passed in rather than
    ///   read again so that the content and the `PopoverBuildKey` recording what it was built
    ///   from are the same geometry — a second `displays()` call could answer differently.
    private func popoverController(screens: [DisplayGeometry]) -> NSViewController {
        popoverLayoutGeneration += 1
        // The traits are applied through the split rather than to the view, so all three
        // renderings — and the measurement taken of them — are in one environment (focus-din).
        let surface = MenuBarPopoverView(presentation: presentation) { [weak self] action in
            self?.onAction?(action)
        }
        .surfaceLayout
        .modified { $0.appearanceTraits(traits) }

        let layout = Self.popoverLayout(
            measuring: surface,
            screens: screens,
            constructions: &popoverHostingConstructions
        )
        popoverLayout = layout

        popoverHostingConstructions += 1
        let hosting = NSHostingController(
            rootView: AnyView(
                NudgePanelContent(
                    inset: Self.popoverContentInset,
                    overflow: layout.overflow,
                    layout: surface,
                    onFrames: { [weak self] reported in self?.reportedPopoverFrames = reported }
                )
                .environment(\.nudgeLayoutGeneration, popoverLayoutGeneration)
                // The live layout fills the size that was committed to; the measurement above
                // must not, or an unbounded height proposal would come back unbounded.
                .frame(
                    width: layout.size.width,
                    height: layout.size.height,
                    alignment: .topLeading
                )
            )
        )
        // Both halves, because they are two different objects' answers to the same question:
        // `preferredContentSize` is what the popover asks its content view controller for, and
        // `contentSize` is what the popover is. Left unset, AppKit answered (320 × 320) and then
        // let the window grow to 3127.
        hosting.preferredContentSize = layout.size
        popover.contentSize = layout.size
        // Synchronous, for `layOutContent()`'s reason: this is what makes the action frames
        // readable in the same turn, because SwiftUI delivers the preference the action targets
        // publish during that layout rather than one pass later.
        hosting.view.layoutSubtreeIfNeeded()
        return hosting
    }

    /// **How tall the popover may be on the display it hangs from.**
    ///
    /// What the display can hold below the menu bar, with the popover's own margin at the
    /// bottom and its chrome allowed for. There is no absolute cap of the kind
    /// `NudgePanelController.maximumContentHeight(screens:)` carries, and the difference is a
    /// difference between the two surfaces rather than an oversight: a panel is an interruption,
    /// and one that filled a laptop screen would have stopped being proportionate, while this
    /// popover is a command centre a person **clicked**, and shortening it below what they asked
    /// to see would be answering a question they did not ask.
    ///
    /// With no display to read — a headless test rig, a Mac between display configurations —
    /// the answer is `nil`: nothing bounds a surface nobody can point at, and
    /// `popoverLayout(measuring:screens:)` then commits the measured height and scrolls nothing.
    ///
    /// **The arithmetic is `SurfaceSizeCommitments`' now** (focus-nu6): one copy, shared with the
    /// panel and with the five surfaces that never had one. What stays here is what is the
    /// popover's own — the space its arrow and its bottom margin reserve, and the fact that it
    /// has no proportionality limit of its own.
    public static func popoverMaximumContentHeight(screens: [DisplayGeometry]) -> Double? {
        SurfaceSizeCommitments.ceiling(
            screens: screens,
            reserving: popoverChromeAllowance + popoverEdgeMargin,
            absoluteMaximum: nil,
            minimum: 0
        )
    }

    /// **The size the popover commits to for one content, and what gives way if it will not fit.**
    ///
    /// A `static` over the view rather than a method on the live controller, so the number the
    /// shipping popover is built at is the number a test or the self-check can take — at a
    /// priority of any length, at either text scale, in either appearance — without a window
    /// server, a status item or a click. The lane that recorded every popover baseline at a
    /// width it supplied itself is the reason this is reachable at all: a picture rendered at a
    /// width the test chose can never show the width being wrong.
    ///
    /// **Two measurements, not one** (focus-din). The whole surface is measured, and then its
    /// **decision** — the pending accusation's corrections and the pending question's answers —
    /// on its own at the same committed width. A surface that will not fit gives way in whichever
    /// of the two ways those numbers permit, and a caller that hands in something with no
    /// decision at all measures a zero for it, which is the honest height of nothing.
    public static func popoverLayout(
        measuring surface: DecisionSurfaceLayout,
        screens: [DisplayGeometry]
    ) -> PopoverLayout {
        var unread = 0
        return popoverLayout(measuring: surface, screens: screens, constructions: &unread)
    }

    /// The same measurement, **counting the hosts it needs to take it** (focus-tzj.1).
    ///
    /// The two `NSHostingController`s below are two thirds of what one open-popover tick used to
    /// cost, so a reading of the cost that did not count them would be a reading of a third of
    /// it. The tally is an `inout` parameter rather than a static on the type because the survey
    /// that reads it and the snapshot lane that calls the plain overload run in one process:
    /// a shared counter would have every popover baseline in `FocusUITests` adding to a number
    /// that is supposed to describe a controller's ticks.
    static func popoverLayout(
        measuring surface: DecisionSurfaceLayout,
        screens: [DisplayGeometry],
        constructions: inout Int
    ) -> PopoverLayout {
        // **The instrument is `SurfaceMeasurer`'s** (focus-tzj.6), the way the arithmetic became
        // `SurfaceSizeCommitments`' in focus-nu6. What stays here is what is the popover's own:
        // the width it commits to, the inset it wears, and a ceiling with no proportionality
        // limit in it. The panel's copy of the measurement was byte-identical to this one.
        let measurement = SurfaceMeasurer.layout(
            measuring: surface,
            width: popoverContentWidth,
            inset: popoverContentInset,
            ceiling: popoverMaximumContentHeight(screens: screens),
            constructions: &constructions
        )
        return PopoverLayout(size: measurement.size, overflow: measurement.overflow)
    }
}


