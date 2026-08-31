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
    /// Another application came frontmost while the probe's subject was on screen. A panel can
    /// only ever move the front *toward* this process, so a front that ended on somebody else is
    /// the world moving under the probe — a delta taken across it describes whoever is using the
    /// Mac rather than the surface being measured.
    case frontMovedToAnotherApplication

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
        case .frontMovedToAnotherApplication:
            "another application came frontmost while the surface was up, so the delta is about "
                + "the world rather than about the surface"
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

/// **Whether a before/after pair taken around a surface may be judged at all** (focus-2uy.3).
///
/// R-89's four focus readings are a *delta*: two readings of who was frontmost, taken two and a
/// half seconds apart with a panel shown between them. Three things can stop that delta being
/// about the panel, and only one of them was ever asked:
///
/// | the run | what it learned |
/// |---|---|
/// | the front was never read at either end | nothing at all — there is no delta between two absences |
/// | the front did not move | the readings are about the panel, and the delta may be judged |
/// | the front moved and ended on **us** | the panel took the front: the defect R-89 forbids |
/// | the front moved and ended elsewhere | the world moved under the probe |
///
/// The first row is the one that was missing, and it was missing in a way that read as the
/// second: the "did it move" predicate conjoined "was it read", so two unread ends produced
/// *did not move*, which published the delta as **taken**. Measured in gate run lens6-1 — both
/// ends `null`, the delta reported taken, and three assertions failing on `(None, None)` while
/// the only fact in evidence was that somebody was using the Mac.
///
/// A pure function of five measured values, for the reason `DecisionSurfaceReachability` is one:
/// the whole table is then reachable from a test process with no window server, and the four
/// rows are four cells rather than four things a reader has to believe.
///
/// This answers **whether the delta may be judged**, never whether it is clean. `.holds` is
/// "go ahead and compare the two readings"; the comparison itself is the caller's, and the caller
/// is what turns red.
public enum SurfaceDeltaReading {
    /// - Parameters:
    ///   - frontWasReadBefore: whether the frontmost application could be read before the show.
    ///   - frontWasReadAfter: whether it could be read after it.
    ///   - frontBefore: who was frontmost before, or `nil` for a reading that was not taken.
    ///   - frontAfter: who was frontmost after, or `nil` for the same.
    ///   - ourIdentifier: this process's own bundle identifier, so "ended on us" is a comparison
    ///     rather than a guess.
    public static func evaluate(
        frontWasReadBefore: Bool,
        frontWasReadAfter: Bool,
        frontBefore: String?,
        frontAfter: String?,
        ourIdentifier: String
    ) -> ProbeOutcome {
        // First, because it is a precondition of the other three rather than a fourth alternative
        // to them: a delta between two readings neither of which exists is not a delta.
        guard frontWasReadBefore, frontWasReadAfter else {
            return .notTaken(.frontmostApplicationUnavailable)
        }
        let moved = frontBefore != frontAfter
        guard moved else { return .holds }
        // A panel can only ever move the front TOWARD this process, so a front that ended on us
        // is the failure the probe exists to find and is handed back to the caller to judge.
        return frontAfter == ourIdentifier ? .holds : .notTaken(.frontMovedToAnotherApplication)
    }
}
