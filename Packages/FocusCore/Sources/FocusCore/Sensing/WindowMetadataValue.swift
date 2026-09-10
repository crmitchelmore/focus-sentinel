import Foundation

/// One on-screen window, as the window list describes it — **minus the one key this
/// programme will never ask for**.
///
/// ## There is nowhere to put a title
///
/// This type has no `title`, no `name`, and no untyped dictionary escape hatch. That is the
/// enforcement, not the documentation: the reader decodes exactly the seven fields below by
/// name and discards the rest of the dictionary, so nothing above it ever sees a
/// `[String: Any]` and no consumer can reach a key the reader did not decode. `kCGWindowName`
/// is banned repository-wide in source **and** at the symbol level, so the ban survives
/// somebody building the string at runtime.
///
/// It is also worthless without a grant this app will never request: measured from an
/// ad-hoc-signed bundle holding no TCC row, the key was present on **1 of 25** on-screen
/// windows and on **2 of 128** with `.optionAll` — and both of those two belonged to Window
/// Server (`"Menubar"`, `"Wallpaper-"`), not to any application (probe P-75). With the grant,
/// the same call returned 34 of 35 names. The whole difference is TCC.
///
/// ## Layer semantics, recorded so nobody re-derives them
///
/// `0` ordinary application windows · `3` floating panels · `20` the Dock · `24` the menu bar
/// · `25` Control Centre · `2147483630` and `-2147483601` system surfaces.
///
/// **`layer == 0` plus an owner-PID match is the only definition of "the frontmost app's
/// window".** The PID half is not tidiness: the Dock permanently owns a window whose bounds
/// are the entire display (`1920×1080 @ (0,0)`, layer 20 — probe P-78), so a bounds-equals-
/// screen test without the filter matches the Dock for ever.
public struct WindowMetadataValue: Sendable, Equatable, Hashable {
    public let ownerName: String
    public let ownerPID: pid_t
    public let layer: Int
    public let number: Int
    /// **Quartz** coordinates: origin at the top left of the primary display, y growing
    /// downward. `ScreenRect.flippedFromQuartz(primaryMaxY:)` is the one sanctioned way into
    /// AppKit's space.
    public let bounds: ScreenRect
    public let isOnScreen: Bool
    public let alpha: Double

    public init(
        ownerName: String,
        ownerPID: pid_t,
        layer: Int,
        number: Int,
        bounds: ScreenRect,
        isOnScreen: Bool,
        alpha: Double
    ) {
        self.ownerName = ownerName
        self.ownerPID = ownerPID
        self.layer = layer
        self.number = number
        self.bounds = bounds
        self.isOnScreen = isOnScreen
        self.alpha = alpha
    }

    /// The layer ordinary application windows live on.
    public static let applicationWindowLayer = 0

    /// Whether this window is an ordinary application window belonging to `pid`.
    ///
    /// The **only** definition of "the frontmost app's window". Both halves are load-bearing
    /// and both are asserted by test, including against a corpus that contains the Dock's
    /// display-sized layer-20 window.
    public func isApplicationWindow(of pid: pid_t) -> Bool {
        layer == Self.applicationWindowLayer && ownerPID == pid
    }
}

extension Array where Element == WindowMetadataValue {
    /// The frontmost application's own windows, and nothing else.
    ///
    /// Every consumer of window metadata goes through this before drawing any conclusion.
    /// The filter is not optional: `.optionOnScreenOnly` is **not** scoped to the current
    /// Space — measured by a third zero-grant process while a second was full-screen on its
    /// own Space, which listed the full-screen app's window *and* seven applications from the
    /// other Space together, 27 rows in one call (probe P-77). "On screen" does not mean "on
    /// the Space the person is looking at", so any heuristic that asks "is *some* window
    /// full-screen" is wrong; it must ask about **this** application's windows.
    public func applicationWindows(of pid: pid_t) -> [WindowMetadataValue] {
        filter { $0.isApplicationWindow(of: pid) }
    }
}
