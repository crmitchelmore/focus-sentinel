import Foundation

/// The three system signals the presentation quorum counts, and which of them agreed.
///
/// Each is grant-free and each was measured with an eight-second settle across a real
/// windowed → full-screen → windowed cycle (probe P-93).
public struct PresentationSignals: Sendable, Equatable, Hashable {
    /// The **frontmost application's** `layer == 0` window fills an `NSScreen.frame` to within
    /// a point.
    ///
    /// The PID filter is what stops the Dock matching: its window is permanently the size of
    /// the whole display (probe P-78).
    public let frontmostWindowFillsAScreen: Bool
    /// `NSApp.currentSystemPresentationOptions` contains `.fullScreen` (1024).
    ///
    /// **Lags the transition** and may never be the sole test: with a three-second settle it
    /// still read `0` while the window's own `styleMask` already said full screen; with an
    /// eight-second settle it read `1024` (probe P-93).
    public let presentationOptionsSayFullScreen: Bool
    /// `NSMenu.menuBarVisible() == false`. System-wide and immediate — and also false for a
    /// screen saver or a menu-bar-hiding utility, which is the other half of why one signal
    /// may never decide.
    public let menuBarHidden: Bool

    public init(
        frontmostWindowFillsAScreen: Bool,
        presentationOptionsSayFullScreen: Bool,
        menuBarHidden: Bool
    ) {
        self.frontmostWindowFillsAScreen = frontmostWindowFillsAScreen
        self.presentationOptionsSayFullScreen = presentationOptionsSayFullScreen
        self.menuBarHidden = menuBarHidden
    }

    /// How many of the three agree. The quorum is **two**.
    public var agreementCount: Int {
        [frontmostWindowFillsAScreen, presentationOptionsSayFullScreen, menuBarHidden]
            .filter { $0 }
            .count
    }

    public static let none = PresentationSignals(
        frontmostWindowFillsAScreen: false,
        presentationOptionsSayFullScreen: false,
        menuBarHidden: false
    )
}

/// Whether the frontmost application has taken over the screen.
///
/// Detection is heuristic — the Court said so — and this type is explicit about how much it
/// trusts itself: it carries the inputs alongside the verdict, so a surface can show its
/// working and an evidence lane can record it.
public struct PresentationState: Sendable, Equatable, Hashable {
    public let signals: PresentationSignals
    /// The user put this application on the presentation-exclusion list. An **override**, not
    /// a vote: it forces `isPresenting` true on its own, because the person said so.
    ///
    /// The list seeds **empty**. Seeding it with guesses would be a claim about applications
    /// this programme has not measured.
    public let isUserExcluded: Bool
    public let isPresenting: Bool

    public init(signals: PresentationSignals, isUserExcluded: Bool, isPresenting: Bool) {
        self.signals = signals
        self.isUserExcluded = isUserExcluded
        self.isPresenting = isPresenting
    }

    public static let notPresenting = PresentationState(
        signals: .none,
        isUserExcluded: false,
        isPresenting: false
    )

    /// **The contract e05 consumes.** Declared now and used nowhere in e03, because there is
    /// nothing to suppress until e05's overlays exist — so e05 adds a behaviour and not a
    /// state machine.
    public var suppressesOverlays: Bool { isPresenting }
}
