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

        /// **All four readings, together.** Three of them are absolute; the fourth is a
        /// comparison against the reading taken before the show, because "unchanged" is the
        /// claim and an absolute value could not express it.
        public func tookNothing(comparedTo before: FocusReadings) -> Bool {
            frontmostBundleIdentifier == before.frontmostBundleIdentifier
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
        public func changedNothing(comparedTo before: FocusReadings) -> Bool {
            frontmostBundleIdentifier == before.frontmostBundleIdentifier
                && applicationIsActive == before.applicationIsActive
                && panelIsKey == before.panelIsKey
                && applicationKeyWindowIsNil == before.applicationKeyWindowIsNil
        }

        /// The report the self-check serialises and `focus-steal` reads.
        public var dictionary: [String: Any] {
            [
                "frontmostBundleIdentifier": frontmostBundleIdentifier ?? "",
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

    /// The panel's content size. Compact on purpose — a nudge that fills a quarter of the screen
    /// is a nudge that has stopped being proportionate.
    public static let contentSize = CGSize(width: 380, height: 190)

    /// The window itself. **Internal, not public**: R-89's properties are asserted on this
    /// object by the unit lane through `@testable import`, and nothing outside this package has
    /// any business reaching for a window when the readings and the properties are published as
    /// values above.
    let panel: NudgePanel
    private let hosting: NSHostingView<AnyView>

    /// Escape, or the panel's own close affordance. Wired by whoever put content in the panel.
    public var onDismiss: (() -> Void)?

    /// The readings taken immediately **before** the last show, so "unchanged" is checkable.
    public private(set) var readingsBeforeShow: FocusReadings?
    /// The readings taken immediately **after** the last show.
    public private(set) var readingsAfterShow: FocusReadings?
    /// Whether the presentation gate had cleared at the last show.
    public private(set) var lastPresentationWasClear = false

    public init(traits: AppearanceTraits = .systemDefault) {
        let hosting = NSHostingView(rootView: AnyView(EmptyView().appearanceTraits(traits)))
        self.hosting = hosting

        panel = NudgePanel(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
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

        panel.onCancel = { [weak self] in self?.onDismiss?() }
    }

    // MARK: - Content

    /// Put a view in the panel.
    ///
    /// The hosting view is built once, in `init`, and its root view is replaced — so showing a
    /// nudge is a state change on objects that already exist, exactly as the capture panel's
    /// 34 ms depends on (P-57) and for the same reason.
    public func update(content: some View, traits: AppearanceTraits = .systemDefault) {
        hosting.rootView = AnyView(content.appearanceTraits(traits))
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
        panel.orderOut(nil)
    }

    public var isVisible: Bool { panel.isVisible }

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
            screens: Self.currentScreens()
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
