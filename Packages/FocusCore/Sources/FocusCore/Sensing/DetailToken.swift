import Foundation

/// The closed vocabulary an event's `detail` may be built from.
///
/// A **fixed** case list. Adding a token is a code change somebody reviews; there is no route
/// by which a string read off a screen becomes one, because `NormalisedDetail` has no `String`
/// initialiser at all.
public enum DetailToken: String, Sendable, CaseIterable, Codable, Hashable, Comparable {
    // Presentation and displays
    case fullScreen
    case windowed
    case primaryDisplay
    case secondaryDisplay
    case presentationExcluded

    // Media
    case micRunning
    case micIdle
    /// Recorded so a reader can see the camera half was considered and held off. It is never
    /// written as a *running* claim, because `cameraRunning` is pinned `false` in v1.
    case cameraHeldOff

    // Privacy
    case sensitiveApp
    case unbundled

    // Input
    case syntheticInput
    case redundantActivation
    case userIdle
    case userActive

    // Session and lifecycle
    case screenLocked
    case screenUnlocked
    case displaysAsleep
    case systemAsleep
    case sessionInactive
    case poweringOff
    case systemActive
    case sessionPaused
    case sessionResumed
    case clockAnomaly
    case rebootedDuringSession
    case restoredStale

    // Sensing lifecycle
    case observersDetached
    case observersAttached

    // The launcher
    case launchAttempted
    case launchSkipped

    // Capabilities
    case capabilityAvailable
    case capabilityDenied
    case capabilityRestricted
    case capabilityUnavailable
    case capabilityNotRequested

    public static func < (lhs: DetailToken, rhs: DetailToken) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension DetailToken {
    /// The token for a capability state, so a `capabilityChanged` row says what changed to
    /// what without a free-text field being invented for it.
    public static func forCapabilityState(_ state: CapabilityState) -> DetailToken {
        switch state {
        case .available: .capabilityAvailable
        case .denied: .capabilityDenied
        case .restricted: .capabilityRestricted
        case .unavailable: .capabilityUnavailable
        case .notRequested: .capabilityNotRequested
        }
    }

    /// The token for a lifecycle state, for the same reason.
    public static func forLifecycle(_ lifecycle: SystemLifecycle) -> DetailToken {
        switch lifecycle {
        case .active: .systemActive
        case .screenLocked: .screenLocked
        case .displaysAsleep: .displaysAsleep
        case .systemAsleep: .systemAsleep
        case .sessionInactive: .sessionInactive
        case .poweringOff: .poweringOff
        }
    }
}

/// What a numeric `detail` measures. A closed list, for the same reason as `DetailToken`.
public enum MeasurementKind: String, Sendable, CaseIterable, Codable, Hashable {
    case dwellSeconds
    case hardwareIdleSeconds
    case sessionIdleSeconds
    case elapsedSeconds
    case driftSeconds
    case displayIndex
    case windowCount
    case observerCount
    case redundantActivations
    case audioInputDeviceCount
    case audioOutputDeviceCount
    case cameraDeviceCount
    case presentationQuorumVotes
}
