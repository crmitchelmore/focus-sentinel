import AppKit
import FocusCore
import SwiftUI

/// **The panel's one show path** (R-89 as amended by P-139, R-96m).
///
/// ## Why this object exists rather than a `show()` on the panel
///
/// P-139 measured the thing this controller is built around. Shown with
/// `orderFrontRegardless()`, a `.nonactivatingPanel` is visible and takes **nothing**:
/// `panel.isKeyWindow` false, `NSApp.keyWindow` nil, `NSApp.isActive` false, and
/// `NSWorkspace.frontmostApplication` unmoved. Shown with `makeKeyAndOrderFront(nil)` — which an
/// earlier draft of this plan specified — the panel becomes key, a key window is installed, and
/// **`NSApp.isActive` flips `false` → `true`**, all while the frontmost application never moves.
/// The two calls are one word apart in a diff and the frontmost reading cannot tell them apart.
///
/// So the show path is **one function**, `show(presentationIsClear:announcement:)`, it calls
/// `orderFrontRegardless()`, and `check-forbidden.sh` (R-96m) bans `makeKeyAndOrderFront(` and
/// `makeKey(` outright in the nudge module while confining `orderFrontRegardless` to this file.
/// The lint holds the difference, rather than a reviewer's memory.
///
/// ## Four readings, not one
///
/// `show(…)` returns `FocusReadings` — all four of R-89's grant-free instruments, taken at the
/// moment of the show. The unit lane asserts them on the real window object, the self-check
/// reports them, and §4.5's `focus-steal` stage gates on them. Reading 1 is the coarse theft a
/// person would see; readings 2–4 are the one P-139 measured, which reading 1 is blind to.
///
/// The one thing none of them can prove — that a person **typing** while the panel is up keeps
/// their keystrokes — needs a synthesised key event and therefore an Accessibility grant, so it
/// lives in the live lane (§4.9 frame 17) where the driver holds the grant and the app under
/// test holds none.
@MainActor
public final class NudgePanelController {
    /// **What "did not steal focus" means**, as four values rather than one (R-89, §4.5).
    public struct FocusReadings: Sendable, Equatable, Hashable {
        /// `NSWorkspace.shared.frontmostApplication?.bundleIdentifier`. The coarse theft a
        /// person would see, and the **primary** instrument (P-129).
        public let frontmostBundleIdentifier: String?
        /// `NSApp.isActive`. Required **`false`**. Never the primary or the sole instrument —
        /// its job is to be asserted false beside the frontmost reading, because P-139 measured
        /// an activation the frontmost reading cannot see.
        public let applicationIsActive: Bool
        /// `panel.isKeyWindow`. Required **`false`** immediately after a show: the panel becomes
        /// key when the person clicks it, never because the app made it so.
        public let panelIsKey: Bool
        /// `NSApp.keyWindow == nil`. Required **`true`** — the same fact from the application's
        /// side, so a second window cannot hide it.
        public let applicationKeyWindowIsNil: Bool
        /// Whether the panel is on screen at all. Not a focus reading; recorded beside them so a
        /// report cannot claim "took nothing" about a panel that never appeared.
        public let panelIsVisible: Bool

        public init(
            frontmostBundleIdentifier: String?,
            applicationIsActive: Bool,
            panelIsKey: Bool,
            applicationKeyWindowIsNil: Bool,
            panelIsVisible: Bool
        ) {
            self.frontmostBundleIdentifier = frontmostBundleIdentifier
            self.applicationIsActive = applicationIsActive
            self.panelIsKey = panelIsKey
            self.applicationKeyWindowIsNil = applicationKeyWindowIsNil
            self.panelIsVisible = panelIsVisible
        }

        /// **Whether reading 1 was taken at all.**
        ///
        /// `NSWorkspace.shared.frontmostApplication` is `nil` while the front is moving between
        /// two applications, and a process that has just been asked to activate is exactly when
        /// that happens. Measured in a failing gate run: reading 1 was `nil` before the show and
        /// `com.chrismitchelmore.FocusSentinel` after it, while `NSApp.isActive` was `false`
        /// throughout — the activation was in flight across the pair.
        ///
        /// It is published because the two conjunctions below depend on it and a reader of the
        /// report is entitled to see why. **There is no claim to be made about focus from a
        /// reading of who is frontmost that was never taken.**
        public var frontmostWasRead: Bool { frontmostBundleIdentifier != nil }

        /// **All four readings, together.** Three of them are absolute; the fourth is a
        /// comparison against the reading taken before the show, because "unchanged" is the
        /// claim and an absolute value could not express it.
        ///
        /// The comparison is guarded by `frontmostWasRead` on both sides, and that guard is the
        /// difference between a proof and a coincidence: `nil == nil` is `true`, so a pair in
        /// which reading 1 could not be taken at either end used to satisfy "the frontmost
        /// application is unchanged" — a green conjunction resting on a measurement nobody made.
        public func tookNothing(comparedTo before: FocusReadings) -> Bool {
            frontmostWasRead
                && before.frontmostWasRead
                && frontmostBundleIdentifier == before.frontmostBundleIdentifier
                && !applicationIsActive
                && !panelIsKey
                && applicationKeyWindowIsNil
        }

        /// **What the show changed**, rather than what it left true.
        ///
        /// The absolute form above is the one §4.5's `focus-steal` stage asserts, because that
        /// stage launches the app with `open -g -a` — the posture a nudge actually fires in, in
        /// which the application has never been frontmost and readings 2 and 4 are false and
        /// true respectively before anything happens.
        ///
        /// The **ordinary** self-check is a different situation and this is the honest assertion
        /// for it: that survey deliberately activates the application, because AppKit validates a
        /// menu item by walking the *key window's* responder chain and a background app has no
        /// key window at all. In that process `NSApp.isActive` is legitimately `true` before the
        /// panel is shown — so the claim worth making is that showing the panel **moved
        /// nothing**, which is exactly as strong a statement about the panel and does not
        /// pretend the process was in a posture it was not.
        /// Guarded by `frontmostWasRead` for the reason `tookNothing(comparedTo:)` is: two
        /// readings neither of which was taken are not evidence that nothing moved between them.
        public func changedNothing(comparedTo before: FocusReadings) -> Bool {
            frontmostWasRead
                && before.frontmostWasRead
                && frontmostBundleIdentifier == before.frontmostBundleIdentifier
                && applicationIsActive == before.applicationIsActive
                && panelIsKey == before.panelIsKey
                && applicationKeyWindowIsNil == before.applicationKeyWindowIsNil
        }

        /// The report the self-check serialises and `focus-steal` reads.
        ///
        /// Reading 1 is `null` when it was not taken, never `""`. The empty string was the same
        /// defect as the window count's `-1`: a missing reading serialised as a value, which
        /// then printed as `got: ('', '')` — a failure message about two applications, neither
        /// of which existed.
        public var dictionary: [String: Any] {
            [
                "frontmostBundleIdentifier": frontmostBundleIdentifier.map { $0 as Any } ?? NSNull(),
                "frontmostWasRead": frontmostWasRead,
                "applicationIsActive": applicationIsActive,
                "panelIsKey": panelIsKey,
                "applicationKeyWindowIsNil": applicationKeyWindowIsNil,
                "panelIsVisible": panelIsVisible
            ]
        }
    }

    /// The six properties of R-89, read off the real window object.
    ///
    /// Exposed as a value so the unit lane, the self-check and the live lane all assert the same
    /// six facts about the same object rather than each reaching into AppKit its own way.
    public struct PanelProperties: Sendable, Equatable, Hashable {
        public let isNonActivating: Bool
        public let canBecomeKey: Bool
        public let canBecomeMain: Bool
        public let becomesKeyOnlyIfNeeded: Bool
        public let hidesOnDeactivate: Bool
        public let joinsAllSpaces: Bool
        public let isStationary: Bool
        public let ignoresCycle: Bool
        /// **Conditional, and that is the whole of R-84.** True only when the presentation gate
        /// had already cleared at the last show.
        public let isFullScreenAuxiliary: Bool

        /// Whether every unconditional property holds. The conditional one is asserted against
        /// the gate that was passed in, which only the caller knows.
        public var isCorrect: Bool {
            isNonActivating
                && canBecomeKey
                && !canBecomeMain
                && becomesKeyOnlyIfNeeded
                && !hidesOnDeactivate
                && joinsAllSpaces
                && isStationary
                && ignoresCycle
        }

        public var dictionary: [String: Any] {
            [
                "isNonActivating": isNonActivating,
                "canBecomeKey": canBecomeKey,
                "canBecomeMain": canBecomeMain,
                "becomesKeyOnlyIfNeeded": becomesKeyOnlyIfNeeded,
                "hidesOnDeactivate": hidesOnDeactivate,
                "joinsAllSpaces": joinsAllSpaces,
                "isStationary": isStationary,
                "ignoresCycle": ignoresCycle,
                "isFullScreenAuxiliary": isFullScreenAuxiliary
            ]
        }
    }

    /// How far a nudge panel keeps from the edge of the space it is placed in.
    ///
    /// Not a threshold about a person, so it is not an `InterventionPolicy` constant (R-96j
    /// scopes the numeric-literal ban to the reducers for exactly this reason): a panel has a
    /// frame the way a menu bar has a cadence.
    public static let edgeMargin: Double = 24

    /// **The width is a commitment; the height is measured** (focus-vpu).
    ///
    /// A constant height was the previous fix and it inverted the defect: content needing 237 to
    /// 404 points was laid out into 190 and clipped, so an accusation drew three and a half of
    /// its six actions and the two that were missing — Pause and Change priority — were the two
    /// a person most needs when the app is wrong. A panel is compact because 380 points is a
    /// narrow column of text, not because a number says it is 190 tall.
    public static let contentWidth: Double = 380

    /// How far the content is held off the window's edges. The snapshot lane renders these views
    /// at the same inset, so what is measured here and what is read there are the same layout.
    public static let contentInset: Double = 16

    /// **An absolute ceiling on how much of a screen a nudge may take.**
    ///
    /// Every real combination measured on this machine fits under it — the tallest is the
    /// recommitment rung at the largest accessibility text size, at 737 points — so it is a bound
    /// on pathology rather than a size anything is squeezed into. Content that exceeds it
    /// **scrolls**; it is never clipped, and while any offered action is out of reach the panel is
    /// not a surface a question may be counted as delivered on.
    public static let absoluteMaximumHeight: Double = 800

    /// How far a measured size may be from the size in force before it is a different size.
    ///
    /// **Not a range and not a fudge factor.** `setContentSize(_:)` sets the content rect, and
    /// on this style mask the frame and the content rect measure equal on this machine. One
    /// point is here so the assertion is about a layout escape rather than about a rounding
    /// difference in some future AppKit — the defect it exists to catch overshot by **two
    /// thousand** points, so nothing real can hide inside it.
    public static let sizeTolerance: Double = 1

    /// The window itself. **Internal, not public**: R-89's properties are asserted on this
    /// object by the unit lane through `@testable import`, and nothing outside this package has
    /// any business reaching for a window when the readings and the properties are published as
    /// values above.
    let panel: NudgePanel
    private let hosting: NSHostingView<AnyView>

    /// **The measuring instrument, and it is never the window.**
    ///
    /// `NSHostingController.sizeThatFits(in:)` answers "how tall is this content when it is
    /// **given this width**" — the wrapped truth, which is the only number worth having. It is
    /// not `NSView.fittingSize`, which is SwiftUI's *unconstrained* fitting size: that is the
    /// number that drove the window to 380 × 2212, because the minimum width of a paragraph is
    /// roughly its longest word and at that width the paragraph is two thousand points tall.
    ///
    /// A second hosting object rather than the live one because measuring must not disturb the
    /// view a person is looking at, and because the live one carries the frame reporter — asking
    /// *it* to measure would collect the frames of a layout nobody was shown.
    private let measurer = NSHostingController(rootView: AnyView(EmptyView()))

    /// The content, before it was wrapped for the panel. Kept so a re-layout — a show, a screen
    /// change — can be performed without the caller handing the content in again.
    private var content: AnyView = AnyView(EmptyView())
    private var traits: AppearanceTraits = .systemDefault

    /// **The traits this panel was last drawn with** (focus-pq8).
    ///
    /// A reading rather than a private field, for the reason every other reading on this
    /// controller is one: the defect was that the panel drew in `AppearanceTraits.systemDefault`
    /// for the life of the process while the Mac said something else, and nothing outside could
    /// tell. `--focus-self-check` and the unit lane can both ask now.
    public var appliedTraits: AppearanceTraits { traits }

    /// **What is on the panel right now, as something anybody can read** (focus-v0u).
    ///
    /// `AnyView` is opaque: nothing outside this object could tell a panel carrying a question
    /// from one carrying an accusation from one carrying nothing at all. That opacity is what let
    /// the most user-visible defect of this epic hide — a question left fully live and fully
    /// clickable on a panel the nudge loop had already forgotten about, so the person's answer was
    /// dropped in a `guard` and the question was asked again. Nothing anywhere could observe the
    /// contradiction, because nothing anywhere could see what the panel was showing.
    ///
    /// `nil` while the panel is off screen: `hide()` and `withdrawForPresentation()` both clear
    /// it, because a panel that has been ordered out is showing nobody anything.
    public private(set) var showing: NudgePanelKind?

    /// Where every offered action landed, in the panel's content space, as the layout last
    /// reported it — **and which layout said so**. A reading from a layout the panel has since
    /// replaced is not a reading of what is on screen, so it is refused rather than trusted.
    private var reportedFrames = NudgeActionFrameSet.empty
    /// Bumped on every layout, so two identical layouts produce two distinguishable readings.
    private var layoutGeneration = 0

    /// Escape, or the panel's own close affordance. Wired by whoever put content in the panel.
    public var onDismiss: (() -> Void)?

    /// **The displays this panel is placed on, as a seam** (focus-56y).
    ///
    /// `currentScreens()` by default, which is `NSScreen.screens` — so the shipping app reads the
    /// real display list and nothing about its behaviour changes. It is a property rather than a
    /// static call so a test can hand the panel the display configuration it is about: a rig has
    /// one screen and cannot be made to grow a second, unplug it, or shrink to 800 × 600, and the
    /// defect this exists for is precisely what happens when it does.
    ///
    /// It is the *display list* that is injectable and nothing else. The panel is a real
    /// `NSPanel`, the layout is the shipping layout, and the reading is
    /// `DecisionSurfaceReachability`'s — a test swaps the world, never the answer.
    public var displays: @MainActor () -> [DisplayGeometry] = { NudgePanelController.currentScreens() }

    /// **The display configuration changed while this panel was up** (focus-56y).
    ///
    /// Called *after* the panel has been re-measured and re-placed for the displays that are
    /// there now, so whoever is listening reads the panel as it currently is rather than as it
    /// was. Whether what the panel is carrying survives that is not this object's decision — it
    /// draws and it measures; the nudge loop decides what a reading means.
    public var onDisplaysChanged: (@MainActor () -> Void)?

    /// **The screen-parameters observation, in a box that can outlive the actor.**
    ///
    /// `deinit` is nonisolated, so it may not touch main-actor state — and an observation this
    /// object registered must still be removed when it goes. The box owns the token and takes it
    /// down in its own `deinit`, which runs when the controller's last reference does.
    private final class ScreenObservation: @unchecked Sendable {
        var token: (any NSObjectProtocol)?

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }

    private let screenObservation = ScreenObservation()

    /// The readings taken immediately **before** the last show, so "unchanged" is checkable.
    public private(set) var readingsBeforeShow: FocusReadings?
    /// The readings taken immediately **after** the last show.
    public private(set) var readingsAfterShow: FocusReadings?
    /// Whether the presentation gate had cleared at the last show.
    public private(set) var lastPresentationWasClear = false

    public init(traits: AppearanceTraits = .systemDefault) {
        let hosting = NSHostingView(rootView: AnyView(EmptyView().appearanceTraits(traits)))
        // **The whole of focus-x7d, in one property.** See `enforceContentSize()` below for the
        // measurement. An `NSHostingView` installed as a window's `contentView` publishes
        // SwiftUI's fitting sizes as the window's `contentMinSize`/`contentMaxSize` by default
        // (`sizingOptions` defaults to `.standardBounds`), and the next layout pass resizes the
        // window to obey them. `[]` is the statement that this window's size is decided here and
        // by nothing else; the view is laid out into the frame it is given, which is what a
        // fixed-size HUD panel means.
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.frame = NSRect(origin: .zero, size: Self.startingSize)
        hosting.autoresizingMask = [.width, .height]
        self.hosting = hosting

        panel = NudgePanel(
            contentRect: NSRect(origin: .zero, size: Self.startingSize),
            styleMask: NudgePanel.nudgeStyleMask,
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        // **`false`, and R-96h bans the other value.** A nudge that vanished the moment the
        // person clicked back into their work would disappear at exactly the moment it was
        // needed — and would look, from the outside, exactly like a nudge that worked.
        panel.hidesOnDeactivate = false
        // **`true`, and R-96m bans the other value.** The panel takes the keyboard only if
        // something in it genuinely needs it, which is what stops it interrupting typing.
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = NudgePanel.baseCollectionBehavior
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = hosting
        panel.setAccessibilityRole(.window)
        panel.setAccessibilitySubrole(.systemDialog)
        self.traits = traits
        layOutContent()

        panel.onCancel = { [weak self] in self?.onDismiss?() }

        // **The one event a placement decision can go stale on** (focus-56y).
        //
        // Everything else about a nudge is decided at the show and stays decided, and that is
        // correct: a panel is deliberately sticky, because a nudge that vanished when somebody
        // clicked back into their work would disappear at the moment it was needed. But the
        // *display it was placed on* is not a property of the nudge, it is a property of the
        // machine — and undocking, a projector, Sidecar or a resolution change replaces it under
        // a window that is already up. Nothing here observed that, so a recommitment placed at
        // 380 × 772 on a 1920 × 1080 screen stayed at 380 × 772 when the screen became 800 × 600,
        // at an AppKit origin of y = 600 − 30 − 772 = −202, with five of its six actions off the
        // bottom of the display and the sixth cut in half.
        //
        // AppKit posts this from `NSApplication`; the observation is registered against any
        // object so that a test can post the same notification rather than needing a second
        // monitor. It is the *notification wiring itself* that is then under test, which is the
        // half a direct call to the re-placement would leave unproven.
        screenObservation.token = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.displayConfigurationChanged() }
        }
    }

    /// **Re-place a live panel for the displays that are there now** (focus-56y).
    ///
    /// The same two calls `show(…)` makes, in the same order and for the same reason: the height
    /// is measured against the display's own ceiling, so it is re-measured before it is re-placed
    /// rather than the old size being moved about. A panel that is not on screen has no placement
    /// to correct and is left entirely alone — including its layout, because re-laying out an
    /// invisible panel would replace the frames a reading is about to be taken from.
    ///
    /// `onDisplaysChanged` is called **after** both, synchronously — `layOutContent()` ends in
    /// `layoutIfNeeded()`, which is what makes the action frames readable in the same turn, and is
    /// exactly what the show path already relies on when it takes its own reading one line after
    /// `show(…)`.
    private func displayConfigurationChanged() {
        guard panel.isVisible else { return }
        layOutContent()
        position()
        onDisplaysChanged?()
    }

    /// The size the window is built at, before anything has been measured. An empty panel's
    /// content is its inset and nothing else, which is the honest size for a panel with nothing
    /// in it — and it is replaced by a measured one the moment there is content to measure.
    private static var startingSize: CGSize {
        CGSize(width: contentWidth, height: contentInset + contentInset)
    }

    // MARK: - Content

    /// Put a view in the panel, and size the panel to it.
    ///
    /// The hosting view is built once, in `init`, and its root view is replaced — so showing a
    /// nudge is a state change on objects that already exist, exactly as the capture panel's
    /// 34 ms depends on (P-57) and for the same reason.
    /// **The two shipping contents, each naming its own kind** (focus-zrs).
    ///
    /// `showing` and `content` are two statements about one thing, and `update(showing:content:)`
    /// lets a caller make them disagree — a panel drawing an accusation while reporting a
    /// question, which is precisely the contradiction `NudgeHost.orphanedQuestionSurfaces` exists
    /// to catch and would then be catching a lie about. The shipping loop uses these two, where
    /// the kind is derived from the type of the view rather than restated beside it, and there is
    /// no argument to get wrong.
    ///
    /// The general form below stays, for the snapshot lane and the panel's own suites, which put
    /// arbitrary content in a real window to measure it.
    public func update(_ content: QueryPanelView, traits: AppearanceTraits = .systemDefault) {
        update(showing: .question, content: content, traits: traits)
    }

    public func update(_ content: AccusationPanelView, traits: AppearanceTraits = .systemDefault) {
        update(showing: .accusation, content: content, traits: traits)
    }

    /// **Re-draw whatever is up under new appearance traits** (focus-pq8).
    ///
    /// The Mac's appearance can change while a nudge is on the screen — a person switching to dark
    /// mode, or the automatic switch at sunset — and the panel is sticky (`hidesOnDeactivate` is
    /// `false`, R-89), so it really can still be there. Without this the traits would only reach a
    /// panel raised *after* the change.
    ///
    /// It re-lays out only when something is up: applying traits to an empty panel would be a
    /// layout pass for nothing.
    public func update(traits: AppearanceTraits) {
        guard self.traits != traits else { return }
        self.traits = traits
        panel.appearance = NSAppearance(named: traits.colorScheme == .dark ? .darkAqua : .aqua)
        guard showing != nil else { return }
        layOutContent()
    }

    public func update(
        showing: NudgePanelKind,
        content: some View,
        traits: AppearanceTraits = .systemDefault
    ) {
        self.content = AnyView(content)
        self.showing = showing
        self.traits = traits
        // **The window's own appearance follows the traits too** (focus-pq8). SwiftUI's
        // `colorScheme` is set by `appearanceTraits(_:)` inside `layOutContent()`, but the panel's
        // AppKit chrome and any `NSColor`-derived fill resolve against the *window's* appearance.
        // Leaving that at the system's while the content was told something else is what drew a
        // panel half in one scheme and half in the other.
        panel.appearance = NSAppearance(named: traits.colorScheme == .dark ? .darkAqua : .aqua)
        layOutContent()
    }

    /// **A width commitment and a measured height** (focus-vpu).
    ///
    /// ## What each of the two previous shapes did, and why neither was the size of anything
    ///
    /// The first shape let `NSHostingView` publish SwiftUI's own min/ideal/max sizes to the
    /// window (`sizingOptions` defaults to `.standardBounds`) and let the next layout pass resize
    /// the window to obey them. A live drive read the result as a real window **380 × 2212** on a
    /// 1920 × 1080 screen: the *minimum* width of a paragraph is roughly its longest word — 209
    /// points here — and at that width the same paragraph is 1542 points tall. The window grew
    /// into its own minimum and the question ended up somewhere nobody could look.
    ///
    /// The second shape pinned the window to a constant 380 × 190 and left the content to fend
    /// for itself. Measured against the real binary: the accusation needs 237 points at the
    /// **default** text size and 404 at the largest accessibility size, the recommitment rung 262
    /// — so the panel was laid out into 190 and clipped. Read on screen: the title cut through
    /// its first line, the snooze row sliced, and Pause and Change priority below the clip and
    /// unreachable. The size check still said yes, because the frame really was the constant.
    ///
    /// ## What this does instead
    ///
    /// * the **width** is committed — 380 points, a narrow column of text — and text wraps into
    ///   it rather than the window growing sideways;
    /// * the **height** is measured at that width, through `NSHostingController.sizeThatFits(in:)`
    ///   with an unbounded height proposal. That is the *wrapped* height, and it is not
    ///   `NSView.fittingSize`, which is the unconstrained number that produced 2212;
    /// * it is **clamped** to what the display can actually hold, and content that exceeds the
    ///   clamp **scrolls** — the layout adapts, and nothing is ever clipped;
    /// * `contentMinSize`/`contentMaxSize` then hold the window at exactly that size, so a font
    ///   change or a `ViewThatFits` re-evaluation after the panel is up has nothing to grow into.
    ///
    /// `layoutIfNeeded()` is what makes the whole thing synchronous — and it is also what makes
    /// the action frames readable in the same turn, because SwiftUI delivers the preference the
    /// action targets publish during that layout rather than one pass later.
    private func layOutContent() {
        let wrappedForMeasurement = AnyView(
            NudgePanelContent(
                inset: Self.contentInset,
                scrolls: false,
                content: content,
                onFrames: { _ in }
            )
            .appearanceTraits(traits)
        )
        measurer.rootView = wrappedForMeasurement

        let measured = measurer.sizeThatFits(
            in: CGSize(width: Self.contentWidth, height: .greatestFiniteMagnitude)
        )
        let ceiling = Self.maximumContentHeight(screens: displays())
        let height = min(max(measured.height, Self.startingSize.height), ceiling)
        // A hair of slack, so a content that measures a fraction over the ceiling because of a
        // rounding difference does not acquire a scroll view it has no use for.
        let scrolls = measured.height > ceiling + Self.sizeTolerance

        layoutGeneration += 1
        hosting.rootView = AnyView(
            NudgePanelContent(
                inset: Self.contentInset,
                scrolls: scrolls,
                content: content,
                onFrames: { [weak self] reported in self?.reportedFrames = reported }
            )
            .environment(\.nudgeLayoutGeneration, layoutGeneration)
            .appearanceTraits(traits)
            // The live layout fills the window it was sized for; the measurement above must not,
            // or an unbounded height proposal would come back unbounded.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        )

        let size = CGSize(width: Self.contentWidth, height: height)
        panel.contentMinSize = size
        panel.contentMaxSize = size
        panel.setContentSize(size)
        hosting.frame = NSRect(
            origin: .zero,
            size: panel.contentRect(forFrameRect: panel.frame).size
        )
        panel.layoutIfNeeded()
    }

    /// **How tall a nudge may be on the display it is being placed on.**
    ///
    /// The absolute ceiling, or what the display can hold with the panel's own margin at top and
    /// bottom, whichever is smaller. A ceiling taken from a constant alone would put a panel off
    /// the bottom of a small display; one taken from the display alone would let a nudge fill a
    /// laptop screen, which is a nudge that has stopped being proportionate.
    public static func maximumContentHeight(screens: [DisplayGeometry]) -> Double {
        guard let display = DisplayMapper.primaryScreen(in: screens) else {
            return absoluteMaximumHeight
        }
        let usable = display.visibleFrame.height - edgeMargin - edgeMargin
        return max(min(absoluteMaximumHeight, usable), startingSize.height)
    }

    /// The size the window is actually at, as opposed to any size anybody committed to.
    public var contentSize: CGSize {
        panel.contentRect(forFrameRect: panel.frame).size
    }

    // MARK: - Showing, once, in one function

    /// **Show the nudge. This is the only function in the programme that orders the panel
    /// front**, and it never makes it key.
    ///
    /// - Parameters:
    ///   - presentationIsClear: `false` when e03's presentation gate is closed. The caller has
    ///     already suppressed or deferred the rung in that case (R-84, R-81); this argument is
    ///     what decides `.fullScreenAuxiliary`, and passing `false` keeps the panel out of a
    ///     full-screen space entirely.
    ///   - announcement: the sentence VoiceOver speaks. `nil` for a surface with nothing to say,
    ///     which is not the same as a surface that says nothing (F-144).
    /// - Returns: the four grant-free focus readings, taken after the show.
    @discardableResult
    public func show(presentationIsClear: Bool, announcement: String? = nil) -> FocusReadings {
        lastPresentationWasClear = presentationIsClear
        panel.collectionBehavior = NudgePanel.collectionBehavior(
            presentationIsClear: presentationIsClear
        )

        // Before `position()`, never after: placement is computed from `panel.frame.size`, and
        // the height is measured from the content — so a panel whose content changed, or whose
        // display did, is re-measured here rather than being placed at the size of the last one.
        layOutContent()
        position()

        let before = readings()
        readingsBeforeShow = before

        // **The one call.** Not `makeKeyAndOrderFront(nil)`: P-139 measured that flipping
        // `NSApp.isActive` to `true` and installing a key window while the frontmost application
        // never moved. The panel is shown non-key and becomes key only when the person clicks
        // it, which is what `.nonactivatingPanel` exists to make safe.
        panel.orderFrontRegardless()

        if let announcement, !announcement.isEmpty {
            announce(announcement)
        }

        let after = readings()
        readingsAfterShow = after
        return after
    }

    /// Take the panel off screen. Writes nothing and decides nothing.
    public func hide() {
        showing = nil
        panel.orderOut(nil)
    }

    /// **Get off a display a presentation has just claimed** (R-84, F-35, P-130).
    ///
    /// `.fullScreenAuxiliary` is decided at show time, from the gate reading of that moment —
    /// and P-130 measured exactly what the flag does when a full-screen space arrives
    /// afterwards: the panel is drawn plainly on top of the presentation, and the window server
    /// will not protect it for us. The frame was captured and read.
    ///
    /// That matters here because `hidesOnDeactivate` is deliberately `false` (R-89): a nudge
    /// stays on screen until the person answers it, including while they click back into their
    /// work. So a panel shown a minute before somebody starts presenting is still there, still
    /// flagged, when the space opens. The suppression stack cannot reach it — that stack decides
    /// whether to *speak*, and this nudge has already spoken.
    ///
    /// The flag is dropped **before** the window is ordered out, so there is no instant in which
    /// a still-visible panel is eligible to join the space it is being removed from.
    public func withdrawForPresentation() {
        showing = nil
        lastPresentationWasClear = false
        panel.collectionBehavior = NudgePanel.collectionBehavior(presentationIsClear: false)
        panel.orderOut(nil)
    }

    public var isVisible: Bool { panel.isVisible }

    /// **Whether this is a surface a person could actually decide on** (focus-vpu, focus-kby).
    ///
    /// The reading that replaced `isPresentedAtIntendedSize`, and the replacement is not a
    /// widening — it is a different question. "The frame equals a constant" passed a panel at
    /// y = −1186, because a size says nothing about where a window is, and it passed a panel
    /// whose Pause and Change priority rows were below the clip, because the frame really was the
    /// constant. This asks the only thing that matters to somebody being asked to choose: is the
    /// window on a screen, and is **every action it is offering** somewhere they can click?
    ///
    /// The frames come from the layout itself, through the preference the action targets publish,
    /// so this is a reading of what SwiftUI actually did rather than of what the window was told.
    ///
    /// - Parameter identifiers: every action the presentation says it is offering, by `rawValue`.
    ///   `AccusationPresentation.offeredActionIdentifiers` and
    ///   `QueryPresentation.offeredAnswerIdentifiers` are what the callers pass.
    public func decisionSurfaceReading(offering identifiers: [String]) -> DecisionSurfaceReading {
        DecisionSurfaceReachability.evaluate(
            isVisible: panel.isVisible,
            surfaceFrame: frame,
            screens: displays(),
            contentBounds: ScreenRect(
                x: 0,
                y: 0,
                width: contentSize.width,
                height: contentSize.height
            ),
            actionTargets: currentActionFrames.map { identifier, rect in
                ActionHitTarget(
                    identifier: identifier,
                    frame: ScreenRect(
                        x: rect.origin.x,
                        y: rect.origin.y,
                        width: rect.width,
                        height: rect.height
                    )
                )
            },
            offering: identifiers
        )
    }

    /// The frames the **current** layout reported, and nothing else.
    ///
    /// A layout that has been replaced describes a panel nobody is looking at any more; under
    /// default-deny the honest answer for one is "no frames", which reads as unreachable rather
    /// than as reachable-because-it-used-to-be.
    private var currentActionFrames: [String: CGRect] {
        reportedFrames.generation == layoutGeneration ? reportedFrames.frames : [:]
    }

    /// Whether the panel could hit-test a click at the centre of each offered action.
    ///
    /// The geometric reading above says the button is inside the content the person can see; this
    /// says AppKit would route a click there to the panel's content view — the same question a
    /// mouse asks. It is a second instrument on the same claim rather than a replacement for it,
    /// and it is what the self-check reports beside the reading.
    public func hitTestsEveryAction(offering identifiers: [String]) -> Bool {
        guard let contentView = panel.contentView else { return false }
        let height = contentSize.height
        return identifiers.allSatisfy { identifier in
            let frames = currentActionFrames
            guard let rect = frames[identifier], rect.width > 0, rect.height > 0 else {
                return false
            }
            // SwiftUI reports frames from the top-left of the content, AppKit hit-tests from the
            // bottom-left of it. The flip is stated here rather than assumed anywhere.
            let point = NSPoint(x: rect.midX, y: height - rect.midY)
            return contentView.hitTest(point) != nil
        }
    }

    /// The window number, for the live lane's `screencapture -l <windowNumber>` (P-136).
    public var windowNumber: Int { panel.windowNumber }

    /// The panel's frame in AppKit coordinates, for evidence and for tests.
    public var frame: ScreenRect {
        ScreenRect(
            x: panel.frame.origin.x,
            y: panel.frame.origin.y,
            width: panel.frame.width,
            height: panel.frame.height
        )
    }

    /// R-89's six properties, read off the real window object.
    public var properties: PanelProperties {
        let behavior = panel.collectionBehavior
        return PanelProperties(
            isNonActivating: panel.styleMask.contains(.nonactivatingPanel),
            canBecomeKey: panel.canBecomeKey,
            canBecomeMain: panel.canBecomeMain,
            becomesKeyOnlyIfNeeded: panel.becomesKeyOnlyIfNeeded,
            hidesOnDeactivate: panel.hidesOnDeactivate,
            joinsAllSpaces: behavior.contains(.canJoinAllSpaces),
            isStationary: behavior.contains(.stationary),
            ignoresCycle: behavior.contains(.ignoresCycle),
            isFullScreenAuxiliary: behavior.contains(.fullScreenAuxiliary)
        )
    }

    /// The four readings, taken now.
    public func readings() -> FocusReadings {
        FocusReadings(
            frontmostBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            applicationIsActive: NSApp?.isActive ?? false,
            panelIsKey: panel.isKeyWindow,
            applicationKeyWindowIsNil: NSApp?.keyWindow == nil,
            panelIsVisible: panel.isVisible
        )
    }

    // MARK: - Placement

    /// Put the panel inside the visible frame of the display the person is looking at.
    ///
    /// Never over the menu bar — `visibleFrame` already excludes it — and never at the notch,
    /// which is e08's to own and which this margin keeps clear of by construction.
    private func position() {
        let placement = Self.placement(
            size: panel.frame.size,
            focusedWindowQuartzBounds: nil,
            screens: displays()
        )
        guard !placement.isEmpty else { return }
        panel.setFrameOrigin(NSPoint(x: placement.x, y: placement.y))
    }

    /// **Where the panel goes**, as a pure function over injected displays.
    ///
    /// Pure because this rig has one display and no notch (e03's P-90), so multi-display
    /// behaviour is code that must be written correctly and tested with fixtures rather than a
    /// claim this machine can confirm. e03's `DisplayMapper` decides *which* display; this
    /// decides where on it.
    ///
    /// - Parameters:
    ///   - size: the panel's content size.
    ///   - focusedWindowQuartzBounds: the focused window's bounds as the window list reports
    ///     them, or `nil` when there is none — in which case the primary display is used, which
    ///     is where a person with no focused window is looking.
    ///   - screens: every display, in `NSScreen.screens` order.
    /// - Returns: the panel's frame in AppKit coordinates, or `.zero` when there is no display
    ///   to place it on.
    public static func placement(
        size: CGSize,
        focusedWindowQuartzBounds: ScreenRect?,
        screens: [DisplayGeometry],
        margin: Double = NudgePanelController.edgeMargin
    ) -> ScreenRect {
        let chosen: DisplayGeometry?
        if let focusedWindowQuartzBounds {
            chosen = DisplayMapper.display(
                quartzBounds: focusedWindowQuartzBounds,
                screens: screens
            ) ?? DisplayMapper.primaryScreen(in: screens)
        } else {
            chosen = DisplayMapper.primaryScreen(in: screens)
        }
        guard let display = chosen else { return .zero }

        let visible = display.visibleFrame
        guard !visible.isEmpty else { return .zero }

        // Never wider or taller than the space it is being placed in. A panel that overflowed
        // the visible frame would be a panel with buttons off the edge of the screen.
        let width = min(Double(size.width), visible.width)
        let height = min(Double(size.height), visible.height)

        // Top trailing corner of the visible frame: out of the way of a document's own content,
        // and — because `visibleFrame` already excludes the menu bar — never over it.
        let x = max(visible.minX, visible.maxX - margin - width)
        let y = max(visible.minY, visible.maxY - margin - height)

        return ScreenRect(x: x, y: y, width: width, height: height)
    }

    /// Every display, as the domain value `DisplayMapper` consumes.
    public static func currentScreens() -> [DisplayGeometry] {
        NSScreen.screens.enumerated().map { index, screen in
            DisplayGeometry(
                displayID: (screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber)?.intValue ?? index,
                screenIndex: index,
                isPrimary: index == 0,
                frame: ScreenRect(
                    x: screen.frame.origin.x,
                    y: screen.frame.origin.y,
                    width: screen.frame.width,
                    height: screen.frame.height
                ),
                visibleFrame: ScreenRect(
                    x: screen.visibleFrame.origin.x,
                    y: screen.visibleFrame.origin.y,
                    width: screen.visibleFrame.width,
                    height: screen.visibleFrame.height
                ),
                backingScaleFactor: Double(screen.backingScaleFactor)
            )
        }
    }

    // MARK: - VoiceOver

    /// Speak the nudge (F-144).
    ///
    /// A nudge that appeared silently for a VoiceOver user would be a visual event they never
    /// learn about — which is the whole failure `accessibilityDisplayShouldDifferentiateWithoutColor`
    /// and F-146 exist to prevent, at the other end of the same problem.
    private func announce(_ sentence: String) {
        NSAccessibility.post(
            element: panel,
            notification: .announcementRequested,
            userInfo: [
                .announcement: sentence,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}
