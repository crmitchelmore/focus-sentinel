import Foundation

/// One display, as the app needs to know it.
///
/// Computed in `FocusSensing` from **injected** screens, so the multi-display cases are unit
/// testable on a rig that has exactly one display and no notch (probe P-90). That is the whole
/// reason this is a value and not a wrapper around `NSScreen`: multi-display behaviour here is
/// code that must be written correctly and tested with fixtures, never a claim this machine
/// can confirm.
public struct DisplayGeometry: Sendable, Equatable, Hashable {
    /// The `CGDirectDisplayID`, as an `Int` so the domain layer needs no CoreGraphics.
    public let displayID: Int
    /// Index into `NSScreen.screens`, where `0` is the primary.
    public let screenIndex: Int
    public let isPrimary: Bool
    /// The whole display, in **AppKit** coordinates.
    public let frame: ScreenRect
    /// The part of it not covered by the menu bar or the Dock, in AppKit coordinates.
    public let visibleFrame: ScreenRect
    public let backingScaleFactor: Double

    // MARK: - The four readings the notch companion is derived from (e08a)
    //
    // Additive, and defaulted to what this rig reports, so every existing construction site keeps
    // compiling and keeps describing the machine it was written on. `NotchLanding.of(_:)` is the
    // only thing in the app that reads them together, and it is a pure function — these four are
    // facts, not a decision.

    /// `NSScreen.safeAreaInsets.top`: how much of the top of this display the system has already
    /// reserved. **`0` on this rig**, and `0` on every notchless panel.
    public let safeAreaTopInset: Double
    /// `NSScreen.auxiliaryTopLeftArea`: the strip of menu bar to the *left* of the housing.
    /// **`nil` on this rig** — measured `nil` rather than a degenerate rectangle, which is why the
    /// absence is modelled as `nil` and not as `.zero`.
    public let auxiliaryTopLeft: ScreenRect?
    /// `NSScreen.auxiliaryTopRightArea`, the same strip on the right. **`nil` on this rig.**
    public let auxiliaryTopRight: ScreenRect?
    /// `CGDisplayIsBuiltin`: whether this is the Mac's own panel.
    ///
    /// **The field the review's §0 finding is about.** "No built-in display" is a stronger fact
    /// than "notchless", F-80's built-in-only policy has no branch without it, and an external
    /// monitor that happened to report a plausible inset would otherwise be indistinguishable from
    /// a MacBook's panel. `false` on this rig, which is a Mac mini.
    public let isBuiltIn: Bool

    public init(
        displayID: Int,
        screenIndex: Int,
        isPrimary: Bool,
        frame: ScreenRect,
        visibleFrame: ScreenRect,
        backingScaleFactor: Double,
        safeAreaTopInset: Double = 0,
        auxiliaryTopLeft: ScreenRect? = nil,
        auxiliaryTopRight: ScreenRect? = nil,
        isBuiltIn: Bool = false
    ) {
        self.displayID = displayID
        self.screenIndex = screenIndex
        self.isPrimary = isPrimary
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.backingScaleFactor = backingScaleFactor
        self.safeAreaTopInset = safeAreaTopInset
        self.auxiliaryTopLeft = auxiliaryTopLeft
        self.auxiliaryTopRight = auxiliaryTopRight
        self.isBuiltIn = isBuiltIn
    }

    /// **The four e08a readings as one value, with no defaults anywhere** (e08a, `focus-26b`).
    ///
    /// This exists because there are **two** AppKit projections of `NSScreen` in this programme
    /// and the package boundary requires it: `SystemScreenList.geometry(of:)` is FocusSensing's
    /// and `NudgePanelController.currentScreens()` is FocusUI's, and FocusUI may not import
    /// FocusSensing. Two readers of one API is two chances to stop short — and stopping short is
    /// *silent and shippable*, because a projection that never read `CGDisplayIsBuiltin` hands the
    /// companion a display list in which no Mac has a built-in panel, and no rig in this programme
    /// has one to notice with.
    ///
    /// So the omission is made a compile error. Every field is a `let` with no default and the
    /// memberwise initialiser is the only one, so a projection that forgot a reading does not
    /// build. What it cannot make an error is a projection that reads the *wrong* value, and on a
    /// Mac with no built-in display that residual is not falsifiable at all — the two honest
    /// answers and the two dishonest ones are the same four values. `NotchGeometrySeamTests` says
    /// so in as many words, and P-e08-B is the receipt that closes it.
    public struct NotchReadings: Sendable, Equatable, Hashable {
        public let safeAreaTopInset: Double
        public let auxiliaryTopLeft: ScreenRect?
        public let auxiliaryTopRight: ScreenRect?
        public let isBuiltIn: Bool

        public init(
            safeAreaTopInset: Double,
            auxiliaryTopLeft: ScreenRect?,
            auxiliaryTopRight: ScreenRect?,
            isBuiltIn: Bool
        ) {
            self.safeAreaTopInset = safeAreaTopInset
            self.auxiliaryTopLeft = auxiliaryTopLeft
            self.auxiliaryTopRight = auxiliaryTopRight
            self.isBuiltIn = isBuiltIn
        }
    }

    /// **The initialiser the two AppKit projections use, and the one a fixture does not.**
    ///
    /// `notch` has no default, which is the whole of its job: the initialiser above defaults the
    /// four readings to this rig's own so that every construction site written before e08a goes on
    /// describing the Mac it was written on, and that convenience is exactly what would let a real
    /// projection forget them.
    public init(
        displayID: Int,
        screenIndex: Int,
        isPrimary: Bool,
        frame: ScreenRect,
        visibleFrame: ScreenRect,
        backingScaleFactor: Double,
        notch: NotchReadings
    ) {
        self.init(
            displayID: displayID,
            screenIndex: screenIndex,
            isPrimary: isPrimary,
            frame: frame,
            visibleFrame: visibleFrame,
            backingScaleFactor: backingScaleFactor,
            safeAreaTopInset: notch.safeAreaTopInset,
            auxiliaryTopLeft: notch.auxiliaryTopLeft,
            auxiliaryTopRight: notch.auxiliaryTopRight,
            isBuiltIn: notch.isBuiltIn
        )
    }

    /// Where the companion may draw on this display, or the named reason it may not.
    ///
    /// Derived rather than stored, for `MenuBarPresentation.attention`'s reason: the facts it is
    /// made of are already here, and a stored landing would be a second statement of the same
    /// thing for a path to get wrong.
    public var notchLanding: NotchLanding { NotchLanding.of(self) }

    /// Whether work on this display should be weighed differently.
    ///
    /// F-34's secondary-display fairness promise is a **value**, not a vibe: e03 records it on
    /// the activation and hands it to e04's engine, which will weigh it. **e03 acts on
    /// nothing.**
    public var isSecondary: Bool { !isPrimary }
}
