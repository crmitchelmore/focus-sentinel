import Foundation

/// One thing the system told us, or failed to tell us.
///
/// Seven signals, in both directions, plus the undocumented pair. Every one of them may be
/// **silent**: measured across a real `pmset displaysleepnow`, `screensDidSleepNotification`,
/// `screensDidWakeNotification`, `sessionDidResignActiveNotification` and
/// `sessionDidBecomeActiveNotification` did not fire at all (probe P-88). An observer written
/// as "when this arrives, do that" would simply never have run, which is why the reduction
/// takes a list and treats every entry as optional.
public enum LifecycleInput: Sendable, Equatable, Hashable {
    /// `NSWorkspace.didActivateApplicationNotification`.
    ///
    /// **This is the primary lock signal**, and it is a public, documented API. Measured
    /// across a real lock (probe P-87): `com.apple.loginwindow` became the frontmost
    /// application, with `frontmostApplication` already agreeing — **1.5 ms before** the
    /// undocumented distributed notification arrived. The reverse fires on unlock.
    case applicationActivated(bundleIdentifier: String?)
    /// `NSWorkspace.willSleepNotification`. Not drivable on the rig (probe P-86: this Mac is
    /// configured never to sleep and has not slept in 8.55 days). Observed, never required.
    case willSleep
    /// `NSWorkspace.didWakeNotification`.
    case didWake
    /// `NSWorkspace.screensDidSleepNotification`. **Measured not to fire** for a
    /// `pmset displaysleepnow` on macOS 26.5.2 (probe P-88).
    case screensDidSleep
    /// `NSWorkspace.screensDidWakeNotification`. Likewise.
    case screensDidWake
    /// `NSWorkspace.sessionDidResignActiveNotification` — fast user switching, not lock.
    case sessionDidResignActive
    /// `NSWorkspace.sessionDidBecomeActiveNotification`.
    case sessionDidBecomeActive
    /// `NSWorkspace.willPowerOffNotification`.
    case willPowerOff
    /// The **undocumented** `com.apple.screenIsLocked` distributed notification.
    /// Corroboration only — see `LifecycleReducer`.
    case distributedScreenLocked
    /// The **undocumented** `com.apple.screenIsUnlocked` distributed notification.
    /// Corroboration only.
    case distributedScreenUnlocked

    /// Whether this input is one of the two undocumented ones.
    public var isDistributed: Bool {
        self == .distributedScreenLocked || self == .distributedScreenUnlocked
    }

    /// The bundle identifier the login window activates under.
    public static let loginWindowBundleIdentifier = "com.apple.loginwindow"
}

/// One reason the Mac is not simply awake and in front of its owner.
///
/// Conditions are tracked as a **set** for the same reason session pauses are: the display can
/// sleep while the screen is also locked, and each condition's "off" signal must clear its own
/// condition and no other. A single mutable enum would let `screensDidWake` silently unlock a
/// locked screen.
public enum LifecycleCondition: String, Sendable, CaseIterable, Codable, Hashable {
    case screenLocked
    case displaysAsleep
    case systemAsleep
    case sessionInactive
    case poweringOff

    /// The typed state this condition projects to.
    public var lifecycle: SystemLifecycle {
        switch self {
        case .screenLocked: .screenLocked
        case .displaysAsleep: .displaysAsleep
        case .systemAsleep: .systemAsleep
        case .sessionInactive: .sessionInactive
        case .poweringOff: .poweringOff
        }
    }

    /// Most severe first. A Mac that is powering off is not merely locked.
    public var severity: Int {
        switch self {
        case .poweringOff: 4
        case .systemAsleep: 3
        case .screenLocked: 2
        case .displaysAsleep: 1
        case .sessionInactive: 0
        }
    }

    /// The session pause cause this condition owns — **and the only cause that can lift the
    /// pause it caused** (R-45).
    ///
    /// The mapping is deliberately **injective**: five conditions, five distinct causes, so
    /// the session's `pauseCauses` set can mirror the lifecycle's `conditions` set exactly and
    /// `sessionEvents(from:to:)` can be a plain set difference. Two conditions sharing a cause
    /// would make "remove the cause this condition owns" ambiguous, and the ambiguity would
    /// resolve into a stranded pause.
    ///
    /// This duplicates `lifecycle.pauseCause` on purpose rather than reading through it: that
    /// property is `Optional` because `SystemLifecycle` has an `.active` case, and a condition
    /// never does. `LifecycleReducerTests` asserts the two agree for every case, so the pair
    /// is kept in step by a test rather than by an unreachable `??` branch.
    public var pauseCause: PauseReason {
        switch self {
        case .screenLocked: .screenLocked
        case .displaysAsleep: .displaysAsleep
        case .systemAsleep: .systemAsleep
        case .sessionInactive: .sessionInactive
        // Powering off is the end of the session as far as the machine is concerned; the
        // system-restart cause is the one a later launch will find and reconcile against.
        case .poweringOff: .systemRestart
        }
    }
}

/// The result of reducing a list of inputs.
public struct LifecycleReduction: Sendable, Equatable, Hashable {
    public let conditions: Set<LifecycleCondition>
    /// How many times an undocumented notification **agreed** with the public state.
    public let corroborations: Int
    /// How many times it disagreed. Recorded so a strange timeline has an explanation in it,
    /// and so the evidence lane can say how reliable the supplement actually was.
    public let contradictions: Int

    public init(
        conditions: Set<LifecycleCondition> = [],
        corroborations: Int = 0,
        contradictions: Int = 0
    ) {
        self.conditions = conditions
        self.corroborations = corroborations
        self.contradictions = contradictions
    }

    /// The one typed state everything else in the app reads.
    public var state: SystemLifecycle {
        conditions.max { $0.severity < $1.severity }?.lifecycle ?? .active
    }
}

/// Seven possibly-silent inputs, reduced into one typed state by a **pure function**.
///
/// ## The undocumented notification changes nothing, by construction
///
/// The Court's downgrade required that `com.apple.screenIsLocked` "may only supplement, never
/// be the sole trigger". This goes further than the downgrade assumed possible, because there
/// is a **public primary** for it to supplement: the `com.apple.loginwindow` activation, which
/// arrives 1.5 ms *earlier* (probe P-87).
///
/// So the two distributed inputs affect the state **not at all**. They increment a
/// corroboration or a contradiction counter and nothing else. That makes "the app's behaviour
/// is identical if they never arrive" a property of the function rather than a property of the
/// particular sequences somebody thought to test: for **every** input list, deleting the
/// distributed entries leaves `conditions` and `state` untouched, and the suite asserts exactly
/// that over the whole table.
///
/// The price is the ~1 ms the distributed unlock could have shaved off an unlock. That is a
/// price worth paying for a guarantee that holds over all inputs rather than over the ones a
/// test author imagined.
///
/// ## Each "off" signal clears its own condition and no other
///
/// The display can wake while the screen is still locked; the login session can become active
/// while the displays are still asleep. Conditions are therefore a set, and `screensDidWake`
/// removes `.displaysAsleep` alone. This is the same authority rule the session's pause causes
/// use, and for the same reason: a subsystem must not be able to clear a state it did not set.
public enum LifecycleReducer {
    /// Fold one input into a reduction.
    public static func step(_ input: LifecycleInput, into reduction: LifecycleReduction) -> LifecycleReduction {
        var conditions = reduction.conditions
        var corroborations = reduction.corroborations
        var contradictions = reduction.contradictions

        switch input {
        case .applicationActivated(let bundleIdentifier):
            if bundleIdentifier == LifecycleInput.loginWindowBundleIdentifier {
                conditions.insert(.screenLocked)
            } else {
                // Activating *away* from the login window is the unlock. It clears the lock
                // and nothing else — a person unlocking their Mac has not woken its displays
                // or ended a fast-user switch.
                conditions.remove(.screenLocked)
            }

        case .willSleep:
            conditions.insert(.systemAsleep)
        case .didWake:
            conditions.remove(.systemAsleep)

        case .screensDidSleep:
            conditions.insert(.displaysAsleep)
        case .screensDidWake:
            conditions.remove(.displaysAsleep)

        case .sessionDidResignActive:
            conditions.insert(.sessionInactive)
        case .sessionDidBecomeActive:
            conditions.remove(.sessionInactive)

        case .willPowerOff:
            // Sticky. There is no signal that takes it back, because there is no coming back.
            conditions.insert(.poweringOff)

        case .distributedScreenLocked:
            if reduction.conditions.contains(.screenLocked) {
                corroborations += 1
            } else {
                contradictions += 1
            }
        case .distributedScreenUnlocked:
            if reduction.conditions.contains(.screenLocked) {
                contradictions += 1
            } else {
                corroborations += 1
            }
        }

        return LifecycleReduction(
            conditions: conditions,
            corroborations: corroborations,
            contradictions: contradictions
        )
    }

    /// Reduce a whole list. Order matters; nothing else does.
    public static func reduce(
        _ inputs: [LifecycleInput],
        from initial: LifecycleReduction = LifecycleReduction()
    ) -> LifecycleReduction {
        inputs.reduce(initial) { step($1, into: $0) }
    }

    /// The state alone, for callers that do not care how well the supplement behaved.
    public static func state(
        of inputs: [LifecycleInput],
        from initial: LifecycleReduction = LifecycleReduction()
    ) -> SystemLifecycle {
        reduce(inputs, from: initial).state
    }

    /// The session events that carry the lifecycle's pause causes from one condition set to
    /// the next: one `paused(cause:)` per condition that arrived, one `resumed(cause:)` per
    /// condition that left, and nothing for the ones that stayed.
    ///
    /// ## Why this takes two *sets* rather than two states
    ///
    /// `LifecycleReduction.state` collapses the condition set to its most severe member, and
    /// a collapsed state cannot say what changed. Driving pauses from it strands causes, and
    /// the sequence that does it is an ordinary night: lock the Mac, let it sleep, wake it,
    /// unlock it. The collapse reports `screenLocked → systemAsleep → screenLocked → active`,
    /// so a state-driven handler pauses for `.screenLocked`, pauses for `.systemAsleep`, then
    /// resumes only the last state it saw — leaving `.systemAsleep` held on a Mac that is
    /// demonstrably awake, and a session **permanently paused** with no control that can lift
    /// it, because `resumed(cause:)` rejects any cause the caller does not own (R-45).
    ///
    /// Reconciling the whole set removes the failure mode rather than patching the sequence
    /// that exposed it: for **any** pair of condition sets, the events returned here leave the
    /// session's lifecycle-owned causes exactly equal to `current`.
    ///
    /// ## Pauses are emitted before resumes
    ///
    /// If the resumes went first, a set that empties and refills would take the session out of
    /// `.paused` and back in — overwriting `resumeTo`, writing two phase changes into the
    /// timeline for one lifecycle event, and briefly telling the nudge ladder that
    /// intervention was permitted. Adding first means the phase moves at most once, and only
    /// when the last cause really is gone.
    ///
    /// ## What it never touches
    ///
    /// Only the causes in this injective condition→cause mapping. A `.user`, `.globalPause` or
    /// `.sensitiveApp` pause is owned by somebody else and is not in the image of the mapping,
    /// so no wake, unlock or power-off can produce an event that clears one.
    public static func sessionEvents(
        from previous: Set<LifecycleCondition>,
        to current: Set<LifecycleCondition>
    ) -> [SessionEvent] {
        // Sorted most-severe-first so the order is a decision rather than a hash seed: two
        // runs of the same transition must produce the same rows in the same timeline.
        let arrived = current.subtracting(previous).sorted { $0.severity > $1.severity }
        let departed = previous.subtracting(current).sorted { $0.severity > $1.severity }

        return arrived.map { SessionEvent.paused(cause: $0.pauseCause) }
            + departed.map { SessionEvent.resumed(cause: $0.pauseCause) }
    }
}
