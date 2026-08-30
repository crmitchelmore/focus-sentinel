import AppKit
import FocusCore
import Foundation

/// The two AppKit signals the presentation quorum counts, behind a seam.
///
/// Injectable because one of them **lags the transition** and the other is true for things that
/// are not presentations, and both facts have to be reproducible in a test rather than waited
/// for: with a three-second settle `currentSystemPresentationOptions` still read `0` while the
/// window's own style mask already said full screen; with an eight-second settle it read `1024`
/// (probe P-93).
@MainActor
public protocol PresentationSignalReading: AnyObject {
    /// `NSApp.currentSystemPresentationOptions` contains `.fullScreen` (1024).
    var presentationOptionsSayFullScreen: Bool { get }
    /// `NSMenu.menuBarVisible() == false`. System-wide and immediate — and also false for a
    /// screen saver or a menu-bar-hiding utility.
    var menuBarHidden: Bool { get }
}

/// The production AppKit signals.
@MainActor
public final class SystemPresentationSignals: PresentationSignalReading {
    public init() {}

    public var presentationOptionsSayFullScreen: Bool {
        // `NSApp` is `nil` in a headless process — the self-check runs inside a real
        // application, but a unit host need not. A missing application object is not a
        // presentation, and guessing one would be a vote cast by an absent signal.
        guard let application = NSApp else { return false }
        return application.currentSystemPresentationOptions.contains(.fullScreen)
    }

    public var menuBarHidden: Bool {
        !NSMenu.menuBarVisible()
    }
}

/// AppKit signals pinned to values a test chose.
public final class FixedPresentationSignals: PresentationSignalReading {
    public var presentationOptionsSayFullScreen: Bool
    public var menuBarHidden: Bool

    public init(presentationOptionsSayFullScreen: Bool = false, menuBarHidden: Bool = false) {
        self.presentationOptionsSayFullScreen = presentationOptionsSayFullScreen
        self.menuBarHidden = menuBarHidden
    }
}

/// Whether the frontmost application has taken over the screen.
///
/// Three grant-free system signals and a user list, resolved by `PresentationQuorum`: **at
/// least two of the three must agree**, and the user's exclusion list forces the answer true on
/// its own because the person said so.
///
/// This type's job is only to *gather* the inputs; the rule that weighs them is a pure function
/// in `FocusCore`, which is what makes the whole table a unit test.
///
/// ## What is done with the answer
///
/// e03 recorded it and suppressed nothing, because there was nothing yet to suppress. Since e05
/// the state reaches `SurfaceRouter` through the nudge surroundings, so the panel rung raised
/// while somebody is presenting is refused rather than drawn over their audience. This type's
/// job did not change: it gathers, and the rule that weighs the answer stays a pure function
/// elsewhere.
@MainActor
public final class PresentationReader {
    private let signals: any PresentationSignalReading

    public init(signals: any PresentationSignalReading = SystemPresentationSignals()) {
        self.signals = signals
    }

    /// Read the state for one cleared activation.
    ///
    /// - Parameters:
    ///   - activation: whose windows count. Everyone else's do not — the Dock's window is
    ///     permanently the size of the whole display (probe P-78), so a bounds test without
    ///     the PID filter matches the Dock for ever.
    ///   - windows: the on-screen window list, **unfiltered**; the filter happens inside the
    ///     quorum's first signal so that the decoys are visible to it and rejected by it.
    ///   - screens: every display, so that "fills a screen" means any of them and not just
    ///     the primary.
    ///   - isUserExcluded: whether this bundle identifier is on the presentation-exclusion
    ///     list, which seeds **empty**.
    public func read(
        for activation: ClearedActivation,
        windows: [WindowMetadataValue],
        screens: [DisplayGeometry],
        isUserExcluded: Bool
    ) -> PresentationState {
        PresentationQuorum.evaluate(
            signals: read(for: activation, windows: windows, screens: screens),
            isUserExcluded: isUserExcluded
        )
    }

    /// The three system signals alone, so a surface or an evidence lane can show its working
    /// even when the verdict is false.
    public func read(
        for activation: ClearedActivation,
        windows: [WindowMetadataValue],
        screens: [DisplayGeometry]
    ) -> PresentationSignals {
        let primaryMaxY = DisplayMapper.primaryScreen(in: screens)?.frame.maxY ?? 0
        return PresentationSignals(
            frontmostWindowFillsAScreen: PresentationQuorum.frontmostWindowFillsAScreen(
                windows: windows,
                frontmostPID: activation.pid,
                screenFrames: screens.map(\.frame),
                primaryMaxY: primaryMaxY
            ),
            presentationOptionsSayFullScreen: signals.presentationOptionsSayFullScreen,
            menuBarHidden: signals.menuBarHidden
        )
    }
}
