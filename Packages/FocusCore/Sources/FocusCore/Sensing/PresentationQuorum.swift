import Foundation

/// Whether the frontmost application has taken over the screen — decided by a **quorum**.
///
/// ## Why a quorum, and why two
///
/// Detection is heuristic (the Court said so), so the design is explicit about how much it
/// trusts itself. Three independent grant-free system signals were measured across a real
/// windowed → full-screen → windowed cycle with an eight-second settle (probe P-93), and two
/// of them are unreliable **on their own**:
///
/// * `NSApp.currentSystemPresentationOptions` **lags the transition**. With a three-second
///   settle it still read `0` while the window's own `styleMask` already said full screen;
///   with an eight-second settle it read `1024`.
/// * `NSMenu.menuBarVisible()` is also false for a screen saver or a menu-bar-hiding utility,
///   neither of which is a presentation.
///
/// So **at least two of the three must agree**. One never decides. The user's exclusion list
/// is not a vote at all — it forces the answer true on its own, because the person said so.
public enum PresentationQuorum {
    /// Two of three. Named rather than inlined, so the surface can say what the rule is.
    public static let requiredAgreement = 2

    /// How close a window's bounds must be to a screen's frame to count as filling it.
    ///
    /// One point. The two figures are computed by different subsystems and agree to a point,
    /// not to a bit.
    public static let boundsTolerance: Double = 1

    /// Decide, from the three signals and the user's list.
    public static func evaluate(
        signals: PresentationSignals,
        isUserExcluded: Bool
    ) -> PresentationState {
        let quorumReached = signals.agreementCount >= requiredAgreement
        return PresentationState(
            signals: signals,
            isUserExcluded: isUserExcluded,
            isPresenting: isUserExcluded || quorumReached
        )
    }

    /// Signal 1, computed: does the **frontmost application's** ordinary window fill a display?
    ///
    /// Three things make this correct rather than nearly correct, and each is a measurement:
    ///
    /// * **The PID filter.** The Dock permanently owns a window whose bounds are the entire
    ///   display — `1920×1080 @ (0,0)` at layer 20 (probe P-78) — so a bounds-equals-screen
    ///   test without the filter matches the Dock for ever.
    /// * **`layer == 0`.** Floating panels, the menu bar and Control Centre are not the
    ///   application's window.
    /// * **The flip.** Window bounds arrive in Quartz coordinates and screen frames are in
    ///   AppKit's, anchored on the **primary** display: `primary.frame.maxY − y − height`.
    ///   Verified against a real window (probe P-91): AppKit `(200, 200) 640×432` appeared as
    ///   Quartz `Y 448`, and `1080 − 448 − 432 = 200` ✓.
    ///
    /// - Parameters:
    ///   - windows: the on-screen window list, unfiltered.
    ///   - frontmostPID: whose windows count. Everyone else's do not.
    ///   - screenFrames: every display's frame, in AppKit coordinates.
    ///   - primaryMaxY: the primary display's `frame.maxY`, which the flip is anchored on.
    public static func frontmostWindowFillsAScreen(
        windows: [WindowMetadataValue],
        frontmostPID: pid_t,
        screenFrames: [ScreenRect],
        primaryMaxY: Double,
        tolerance: Double = boundsTolerance
    ) -> Bool {
        let candidates = windows.applicationWindows(of: frontmostPID)
        guard !candidates.isEmpty, !screenFrames.isEmpty else { return false }

        return candidates.contains { window in
            let flipped = window.bounds.flippedFromQuartz(primaryMaxY: primaryMaxY)
            return screenFrames.contains { frame in
                flipped.isEqual(to: frame, tolerance: tolerance)
            }
        }
    }
}
