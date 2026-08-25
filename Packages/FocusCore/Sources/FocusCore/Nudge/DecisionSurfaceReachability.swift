import Foundation

/// **One action the surface is offering, and where it actually landed.**
///
/// The identifier is the action's own `rawValue` — `CorrectionAction.snooze` is `"snooze"`,
/// `QueryAnswer.yesAddIt` is `"yesAddIt"` — so the set a panel *reports* and the set a
/// presentation *offers* are comparable without a second vocabulary to keep in step.
///
/// The frame is in the surface's own content space, with the origin at the content's top-left
/// corner. Which way `y` runs does not matter to anything here: every comparison is against
/// the content bounds expressed in the same space, so the predicate is convention-free.
public struct ActionHitTarget: Sendable, Equatable, Hashable {
    public let identifier: String
    public let frame: ScreenRect

    public init(identifier: String, frame: ScreenRect) {
        self.identifier = identifier
        self.frame = frame
    }
}

/// **Whether a decision surface is one a person could actually decide on** (focus-kby, U-1).
///
/// A reading rather than a `Bool`, because the four ways it fails are four different defects and
/// a caller that could not tell them apart would report "unreadable" for all of them:
///
/// | field | the defect it names |
/// |---|---|
/// | `isVisible` | the window is not on screen at all |
/// | `isWhollyOnAScreen` | the window is on screen and **off** every display — the y = −1186 case |
/// | `unreportedActions` | an offered action drew nothing: it is not in the layout at any size |
/// | `unreachableActions` | an action was laid out **below the fold**: clipped, or scrolled away |
public struct DecisionSurfaceReading: Sendable, Equatable, Hashable {
    /// Whether the surface is on screen at all.
    public let isVisible: Bool
    /// Whether the surface's whole frame lies inside one display's visible frame.
    public let isWhollyOnAScreen: Bool
    /// Offered actions the surface reported no frame for.
    public let unreportedActions: [String]
    /// Offered actions whose frame is empty, or is not wholly inside the content the person
    /// can see.
    public let unreachableActions: [String]

    public init(
        isVisible: Bool,
        isWhollyOnAScreen: Bool,
        unreportedActions: [String],
        unreachableActions: [String]
    ) {
        self.isVisible = isVisible
        self.isWhollyOnAScreen = isWhollyOnAScreen
        self.unreportedActions = unreportedActions
        self.unreachableActions = unreachableActions
    }

    /// **The one honest predicate**, and the thing that replaced `isPresentedAtIntendedSize`.
    ///
    /// "The frame equals a constant" was the wrong question in both directions: it passed a
    /// panel whose Pause button was below the clip because the *window* was the agreed size, and
    /// it passed a panel at y = −1186 because a frame's size says nothing about where it is. A
    /// decision surface whose Pause button a person cannot reach is not a decision surface, so
    /// this is the conjunction of on-screen, on-a-display, and **every** offered action laid out
    /// somewhere the person can see and click.
    public var everyActionIsReachable: Bool {
        isVisible
            && isWhollyOnAScreen
            && unreportedActions.isEmpty
            && unreachableActions.isEmpty
    }

    /// Why it is not, in one line, for a log or a gate report.
    public var summary: String {
        if everyActionIsReachable { return "every offered action is reachable" }
        var parts: [String] = []
        if !isVisible { parts.append("the surface is not on screen") }
        if !isWhollyOnAScreen { parts.append("the surface is not wholly on a display") }
        if !unreportedActions.isEmpty {
            parts.append("no frame for \(unreportedActions.joined(separator: ", "))")
        }
        if !unreachableActions.isEmpty {
            parts.append("out of reach: \(unreachableActions.joined(separator: ", "))")
        }
        return parts.joined(separator: "; ")
    }

    /// The report a self-check serialises and a gate stage reads.
    public var dictionary: [String: Any] {
        [
            "isVisible": isVisible,
            "isWhollyOnAScreen": isWhollyOnAScreen,
            "unreportedActions": unreportedActions,
            "unreachableActions": unreachableActions,
            "everyActionIsReachable": everyActionIsReachable,
            "summary": summary
        ]
    }
}

/// **The predicate, as a pure function of measured values** (focus-kby, focus-vpu).
///
/// Every input is something an `NSWindow`, an `NSScreen` list and a SwiftUI layout can be asked
/// for, and nothing here touches any of them — which is what makes the invariant table-testable
/// over the full `{query, accusation, recommitment} × {standard, accessibilityLarge}` cross
/// product instead of only being observable on a Mac with a window server.
public enum DecisionSurfaceReachability {
    /// How far outside its container an action may land before it is out of reach.
    ///
    /// One point, for the reason `NudgePanelController.sizeTolerance` was one point: a layout
    /// escape is measured in tens or thousands of points, and a rounding difference between a
    /// SwiftUI frame and an AppKit content rect is measured in fractions of one.
    public static let tolerance: Double = 1

    /// - Parameters:
    ///   - isVisible: `NSWindow.isVisible`.
    ///   - surfaceFrame: the window's frame, in AppKit screen coordinates.
    ///   - screens: every display, as `NudgePanelController.currentScreens()` reports them.
    ///   - contentBounds: the content the person can see, in the same space the action frames
    ///     are reported in. For a panel that is its content view's bounds.
    ///   - actionTargets: what the layout reported. Duplicates keep the last one, which is what
    ///     a preference reduction produces.
    ///   - offering: every action the presentation says it is offering, by `rawValue`.
    public static func evaluate(
        isVisible: Bool,
        surfaceFrame: ScreenRect,
        screens: [DisplayGeometry],
        contentBounds: ScreenRect,
        actionTargets: [ActionHitTarget],
        offering identifiers: [String]
    ) -> DecisionSurfaceReading {
        let onAScreen = !surfaceFrame.isEmpty && screens.contains { screen in
            contains(screen.visibleFrame, surfaceFrame)
        }

        var reported: [String: ScreenRect] = [:]
        for target in actionTargets { reported[target.identifier] = target.frame }

        var unreported: [String] = []
        var unreachable: [String] = []
        for identifier in identifiers {
            guard let frame = reported[identifier] else {
                unreported.append(identifier)
                continue
            }
            if frame.isEmpty || !contains(contentBounds, frame) {
                unreachable.append(identifier)
            }
        }

        return DecisionSurfaceReading(
            isVisible: isVisible,
            isWhollyOnAScreen: onAScreen,
            unreportedActions: unreported,
            unreachableActions: unreachable
        )
    }

    /// Whether `inner` lies wholly inside `outer`, to within `tolerance` on every edge.
    ///
    /// An empty container contains nothing, including an empty rectangle: a panel with no
    /// content area is a panel whose buttons are nowhere, and answering `true` for it would make
    /// the whole predicate vacuous exactly when the surface has collapsed.
    private static func contains(_ outer: ScreenRect, _ inner: ScreenRect) -> Bool {
        guard !outer.isEmpty else { return false }
        return inner.minX >= outer.minX - tolerance
            && inner.maxX <= outer.maxX + tolerance
            && inner.minY >= outer.minY - tolerance
            && inner.maxY <= outer.maxY + tolerance
    }
}
