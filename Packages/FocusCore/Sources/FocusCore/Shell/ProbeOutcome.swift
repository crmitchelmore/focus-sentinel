import Foundation

/// **Why a reading could not be taken** (focus-rxc, focus-2vi, focus-jax).
///
/// Every case is a property of the *machine* the gate happened to run on, never of the tree under
/// test. A run that meets one of these has not found a defect and has not proved the absence of
/// one either — it has failed to measure, and the only honest thing it can say is so.
public enum ReadingObstacle: String, Sendable, Equatable, Hashable, CaseIterable {
    /// `NSWorkspace.shared.frontmostApplication` answered `nil`. It does that while the front is
    /// moving between two applications, which is exactly when a process that has just been asked
    /// to activate is looking. Measured in a failing gate run under contention: `nil` on both
    /// sides of a probe whose whole subject is whether the front moved.
    case frontmostApplicationUnavailable
    /// `NSScreen.screens` was empty — a headless rig, or a Mac between display configurations.
    /// Nothing can be said about whether a window is wholly on a display that is not there.
    case noDisplayAttached
    /// The application had no key window, so a reading taken by walking the key window's
    /// responder chain had nothing to walk.
    case noKeyWindow
    /// The journal the probe would have read its undo from was never installed.
    case noUndoManager

    /// The sentence a report or a log line carries. One per obstacle, so a NOT TAKEN reading
    /// always names which of them stopped it.
    public var sentence: String {
        switch self {
        case .frontmostApplicationUnavailable:
            "the frontmost application could not be read at one or both ends of the probe"
        case .noDisplayAttached:
            "no display was attached, so there is no screen for the surface to be on"
        case .noKeyWindow:
            "the application had no key window to read through"
        case .noUndoManager:
            "no undo manager was installed on the journal"
        }
    }
}

/// **What a probe found, when its subject is a reading the machine may not be able to take**
/// (focus-rxc).
///
/// ## The defect this exists to end
///
/// Three times in three rounds, a probe whose subject was an unavailable reading reported
/// **failure** — the sensing seed, the undo probe, and `NudgePanelTests.showingTakesNothing`,
/// where `tookNothing(comparedTo:)` goes false whenever `NSWorkspace.frontmostApplication`
/// answers `nil` at either end. Each was fixed one probe at a time, and the shape came back.
///
/// The guard in each case was **right**: it refused to claim a proof from a measurement nobody
/// made, and `nil == nil` satisfying "the frontmost application is unchanged" is precisely the
/// green-on-nothing this programme keeps finding. What was wrong is that a two-valued answer has
/// no room for the third thing that actually happened. `Bool` cannot say *not taken*, so a
/// conjunction guarded against an unmade reading has only `false` left to return, and `false`
/// reads as "the panel stole focus".
///
/// Three values, so it can:
///
/// | value | what the run learned | what it should cost |
/// |---|---|---|
/// | `holds` | the property was measured and is true | nothing |
/// | `broken` | the property was measured and is **false** | a red run — this is the defect |
/// | `notTaken` | the property was not measured at all | nothing, **and a line saying so** |
///
/// ## How a call site uses it
///
/// Two lines, and they are two rather than one because `#expect` is a macro that has to be at the
/// call site and `FocusCore` may not import a testing library:
///
/// ```swift
/// let outcome = controller.focusVerdict(comparedTo: before)
/// if let banner = outcome.banner { print(banner) }
/// #expect(!outcome.isBroken, "\(outcome.summary)")
/// ```
///
/// A `notTaken` run is green and **loud**: the banner is a fixed, greppable string in the stage
/// log, so "the gate could not measure this" is a fact a reader of the evidence can find rather
/// than an absence they would have to notice.
///
/// **What this must never become**: a way to make an inconvenient assertion go quiet. `notTaken`
/// is only ever returned for an obstacle in `ReadingObstacle` — a closed list of machine
/// properties — and never for a value the tree under test decides.
public enum ProbeOutcome: Sendable, Equatable, Hashable {
    /// Measured, and true.
    case holds
    /// Measured, and false. The failure the probe exists to find.
    case broken(String)
    /// Not measured. Neither a pass nor a failure: an absence of evidence.
    case notTaken(ReadingObstacle)

    /// Whether this is the defect. The **only** thing a call site asserts on.
    public var isBroken: Bool {
        if case .broken = self { return true }
        return false
    }

    /// Whether the reading happened at all.
    public var wasTaken: Bool {
        if case .notTaken = self { return false }
        return true
    }

    /// The obstacle, when there was one.
    public var obstacle: ReadingObstacle? {
        if case .notTaken(let obstacle) = self { return obstacle }
        return nil
    }

    /// One line, for a failure message or a report.
    public var summary: String {
        switch self {
        case .holds: "the property was measured and holds"
        case .broken(let why): why
        case .notTaken(let obstacle): "NOT TAKEN: \(obstacle.sentence)"
        }
    }

    /// The fixed, greppable line a stage log carries when a reading could not be taken, and `nil`
    /// when it could. A gate stage or a person reading the evidence finds these by searching for
    /// `NOT TAKEN`; a run with none of them measured everything it claims to have measured.
    public var banner: String? {
        guard case .notTaken(let obstacle) = self else { return nil }
        return "NOT TAKEN [\(obstacle.rawValue)]: \(obstacle.sentence)"
    }

    /// The report a self-check serialises, in the shape `SelfCheck` already publishes: the value,
    /// whether it was taken, and — when it was not — which obstacle stopped it.
    public var dictionary: [String: Any] {
        [
            "wasTaken": wasTaken,
            "holds": self == .holds,
            "notTakenBecause": obstacle?.rawValue ?? "",
            "summary": summary
        ]
    }
}
