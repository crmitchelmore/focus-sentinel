import AppKit
import FocusCore
import Foundation

/// The seam between this app and `NSScreen.screens`.
///
/// Injectable because the rig has exactly **one** display, `2490W1` at `1920×1080`, with no
/// notch (probe P-90). Multi-display behaviour is therefore code that must be written correctly
/// and tested against fixtures, never a claim this machine can confirm — and a seam is what
/// lets the fixture exist.
@MainActor
public protocol ScreenListReading: AnyObject {
    func screens() -> [DisplayGeometry]
}

/// The production screen list.
@MainActor
public final class SystemScreenList: ScreenListReading {
    public init() {}

    public func screens() -> [DisplayGeometry] {
        Self.geometry(of: NSScreen.screens)
    }

    /// Project `NSScreen`s into the domain's value type.
    ///
    /// Index `0` is the primary by AppKit's own contract, and the flip every consumer performs
    /// is anchored on it. `NSScreenNumber` is the `CGDirectDisplayID`, carried as an `Int` so
    /// that nothing above this file needs CoreGraphics.
    public static func geometry(of screens: [NSScreen]) -> [DisplayGeometry] {
        screens.enumerated().map { index, screen in
            DisplayGeometry(
                displayID: displayID(of: screen) ?? index,
                screenIndex: index,
                isPrimary: index == 0,
                frame: rect(screen.frame),
                visibleFrame: rect(screen.visibleFrame),
                backingScaleFactor: Double(screen.backingScaleFactor)
            )
        }
    }

    /// The `CGDirectDisplayID`, which AppKit publishes under `NSScreenNumber` in the device
    /// description. `nil` for a screen that has just been unplugged between the enumeration
    /// and the read, which is a real thing that happens and not a reason to crash.
    static func displayID(of screen: NSScreen) -> Int? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.intValue
    }

    static func rect(_ rect: NSRect) -> ScreenRect {
        ScreenRect(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.size.width),
            height: Double(rect.size.height)
        )
    }
}

/// A screen list pinned to injected fixtures, so the multi-display cases are testable on a rig
/// that has one display.
public final class FixedScreenList: ScreenListReading {
    private let fixtures: [DisplayGeometry]

    public init(_ fixtures: [DisplayGeometry]) {
        self.fixtures = fixtures
    }

    public func screens() -> [DisplayGeometry] { fixtures }
}

/// Which display the person is actually looking at work on.
///
/// ## Re-evaluation is a contract, not a notification
///
/// `NSWorkspace.activeSpaceDidChangeNotification` **never fired** across four full-screen
/// enter/exit cycles, two bundle identifiers, and both a windowless `.accessory` observer and a
/// windowed `.regular` one — while activation notifications flowed to the same observers
/// throughout (probe P-92). So the contract is: re-evaluate on **every accepted activation**,
/// plus a bounded corroboration tick. The notification is subscribed as an optimisation and
/// the behaviour is identical when it never arrives.
///
/// ## Per-Space memory is dropped
///
/// Nothing here persists a Space identity, because no public API exposes a stable one (Court).
///
/// ## Secondary-display fairness is a value, not a vibe
///
/// `DisplayGeometry.isPrimary == false` rides on the activation and is handed to e04's engine,
/// which will weigh it. **e03 records it and acts on nothing.**
@MainActor
public final class DisplayGeometryReader {
    private let list: any ScreenListReading

    public init(list: any ScreenListReading = SystemScreenList()) {
        self.list = list
    }

    /// Every display, in `NSScreen.screens` order.
    public func screens() -> [DisplayGeometry] {
        list.screens()
    }

    /// The display the cleared application's frontmost ordinary window is on, or `nil` if it
    /// is on none of them.
    ///
    /// `nil` is a real answer and deliberately not display zero: a window on a display that has
    /// just been unplugged must not be reported as being on the primary, because a caller would
    /// then weigh it as if the person were looking at it.
    ///
    /// The windows are passed in rather than read here, so that one window-list call serves the
    /// display mapping, the presentation quorum and the event's window count — 0.296 ms is
    /// cheap, but three reads of the same instant could disagree with each other.
    public func display(
        for activation: ClearedActivation,
        windows: [WindowMetadataValue]
    ) -> DisplayGeometry? {
        guard let window = windows.applicationWindows(of: activation.pid).first else { return nil }
        return DisplayMapper.display(quartzBounds: window.bounds, screens: screens())
    }

    /// The whole mapping, for a surface or an evidence lane that wants to show its working.
    public func mapping(
        for activation: ClearedActivation,
        windows: [WindowMetadataValue]
    ) -> DisplayMapper.Mapping? {
        guard let window = windows.applicationWindows(of: activation.pid).first else { return nil }
        return DisplayMapper.map(quartzBounds: window.bounds, screens: screens())
    }
}
