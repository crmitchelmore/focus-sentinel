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

    public init(
        displayID: Int,
        screenIndex: Int,
        isPrimary: Bool,
        frame: ScreenRect,
        visibleFrame: ScreenRect,
        backingScaleFactor: Double
    ) {
        self.displayID = displayID
        self.screenIndex = screenIndex
        self.isPrimary = isPrimary
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.backingScaleFactor = backingScaleFactor
    }

    /// Whether work on this display should be weighed differently.
    ///
    /// F-34's secondary-display fairness promise is a **value**, not a vibe: e03 records it on
    /// the activation and hands it to e04's engine, which will weigh it. **e03 acts on
    /// nothing.**
    public var isSecondary: Bool { !isPrimary }
}
