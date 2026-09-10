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

/// **What a decision surface amounts to, in the three answers it has** (focus-6pr.4).
///
/// `everyActionIsReachable` was a `Bool` over four conjuncts that are all true of a surface
/// offering nothing, so *"there is nothing here to reach"* and *"everything here is reachable"*
/// were one answer. e07a's popover ruling makes that state ordinary rather than hypothetical: a
/// popover carrying an accusation **and** a question pins the question, and the accusation's
/// corrections scroll with the context, so the accusation offers nothing while it is drawn. It is
/// a `String` enum for `DeferralReason`'s reason — a case is a value a report can carry — and
/// `CaseIterable` so the vocabulary can be folded rather than listed.
public enum DecisionSurfaceStanding: String, Sendable, CaseIterable, Codable, Hashable {
    /// The surface is on a display and every action it offers is somewhere a person can click.
    case reachable
    /// The surface is on a display and offers **nothing**. Not a decision surface, and not a
    /// defect either: it is what the popover's residual nudge is while the other one is pinned.
    case notOffered
    /// The surface is not on screen, is not wholly on a display, or an action it offers is not
    /// where a person could press it. `DecisionSurfaceReading.summary` says which.
    case unreadable
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
/// | `offeredActions` | **nothing was offered at all** — there is no decision here to reach |
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
    /// **Every action the surface said it was offering** (focus-6pr.4).
    ///
    /// Carried rather than summed away, because *"none of the offered actions is out of reach"*
    /// and *"there were no offered actions"* are two different readings and the three lists above
    /// cannot tell them apart: both are three empty arrays. See `standing`.
    public let offeredActions: [String]

    public init(
        isVisible: Bool,
        isWhollyOnAScreen: Bool,
        unreportedActions: [String],
        unreachableActions: [String],
        offeredActions: [String]
    ) {
        self.isVisible = isVisible
        self.isWhollyOnAScreen = isWhollyOnAScreen
        self.unreportedActions = unreportedActions
        self.unreachableActions = unreachableActions
        self.offeredActions = offeredActions
    }

    /// **The one honest predicate**, and the thing that replaced `isPresentedAtIntendedSize`.
    ///
    /// "The frame equals a constant" was the wrong question in both directions: it passed a
    /// panel whose Pause button was below the clip because the *window* was the agreed size, and
    /// it passed a panel at y = −1186 because a frame's size says nothing about where it is. A
    /// decision surface whose Pause button a person cannot reach is not a decision surface, so
    /// this is the conjunction of on-screen, on-a-display, and **every** offered action laid out
    /// somewhere the person can see and click.
    /// **And that there was one to reach** (focus-6pr.4). The four conjuncts are all satisfied by
    /// a surface offering *nothing*, so this answered `true` — "every one of no actions is
    /// reachable" — for the one state e07a's popover ruling creates: an accusation drawn beside a
    /// question, where the question is the pinned decision and the accusation's corrections
    /// scroll with the context. `NudgeHost` charged that rung on this reading. `standing` is the
    /// three-valued form and this is exactly its `reachable` arm, so a caller that asks only the
    /// `Bool` cannot reach the vacuous answer either.
    public var everyActionIsReachable: Bool { standing == .reachable }

    /// **Whether this is a decision surface, and if not, which of the two ways it is not**
    /// (focus-6pr.4).
    ///
    /// The geometry is asked first and the offer second, deliberately: a surface at y = −1186
    /// offering nothing is *off the edge of the world*, and answering `notOffered` for it would
    /// let an empty offer wave a runaway window past the reading that exists to catch one.
    public var standing: DecisionSurfaceStanding {
        guard isVisible,
              isWhollyOnAScreen,
              unreportedActions.isEmpty,
              unreachableActions.isEmpty
        else { return .unreadable }
        return offeredActions.isEmpty ? .notOffered : .reachable
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
        if parts.isEmpty { parts.append("the surface is offering nothing to decide on") }
        return parts.joined(separator: "; ")
    }

    /// The report a self-check serialises and a gate stage reads.
    public var dictionary: [String: Any] {
        [
            "isVisible": isVisible,
            "isWhollyOnAScreen": isWhollyOnAScreen,
            "unreportedActions": unreportedActions,
            "unreachableActions": unreachableActions,
            // `standing` is deliberately not a key of its own: it is **derivable** from the ones
            // that are — both geometry terms true, both lists empty and `everyActionIsReachable`
            // false is `notOffered` and can be nothing else — so a reader loses nothing and the
            // gate gains no unread key (R-168).
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

    /// **The reading, in the three values the situation has** (focus-rxc).
    ///
    /// `everyActionIsReachable` is a `Bool`, and one of the ways it goes false is a property of
    /// the machine rather than of the surface: with no display attached, `isWhollyOnAScreen` is
    /// false because there is no screen for the window to be wholly on. In the shipping app that
    /// conflation is harmless — a Mac with no display genuinely has no surface a person can reach
    /// — but in a lane it means a headless run reports *"the panel is off screen"*, which is a
    /// defect the run did not observe.
    ///
    /// This is the same reading with `notTaken` available, for the call sites whose screen list is
    /// the live `NSScreen.screens` rather than a fixture. A lane that hands over its own displays
    /// should keep asserting on `everyActionIsReachable` directly: a fixture is never unavailable,
    /// and routing it through here would only make a total assertion look conditional.
    ///
    /// - Parameters:
    ///   - reading: what `evaluate(…)` returned.
    ///   - screens: the display list it was evaluated against.
    public static func verdict(
        _ reading: DecisionSurfaceReading,
        screens: [DisplayGeometry]
    ) -> ProbeOutcome {
        guard !screens.isEmpty else { return .notTaken(.noDisplayAttached) }
        guard reading.everyActionIsReachable else { return .broken(reading.summary) }
        return .holds
    }

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
            unreachableActions: unreachable,
            offeredActions: identifiers
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
