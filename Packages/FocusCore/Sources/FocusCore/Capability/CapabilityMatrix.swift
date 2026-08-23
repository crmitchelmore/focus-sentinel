import Foundation

/// One capability's state, and whether the app has already explained it to the user.
public struct CapabilityObservation: Sendable, Equatable, Hashable {
    public let state: CapabilityState
    public let observedAt: Date
    /// When a denial was last explained. **Written once and never re-armed** — the persisted
    /// half of the never-re-prompt policy.
    public let educationShownAt: Date?

    public init(state: CapabilityState, observedAt: Date, educationShownAt: Date? = nil) {
        self.state = state
        self.observedAt = observedAt
        self.educationShownAt = educationShownAt
    }
}

/// What the app currently believes about all twelve capabilities.
///
/// A value type, so a matrix can be handed to a snapshot test, compared, or thrown away. It is
/// refreshed on wake, on resume from global pause and on demand — **never on a timer, and
/// never by asking**. In e03 it cannot ask even by accident: every prompting API is banned
/// from the shipping graph by lint.
///
/// ## The one transition this type forbids
///
/// A `.denied` capability never goes back to `.notRequested`. That looks like housekeeping and
/// is not: `.notRequested` is the state that means "we have not asked yet", and letting a
/// denial decay into it is precisely how an app comes to ask a second time. The user's answer
/// is not a prompt to try again. `.denied` may become `.available` — the user changed their
/// mind in System Settings, and live TCC state is authoritative — but it may never quietly
/// become a question again.
public struct CapabilityMatrix: Sendable, Equatable {
    private var observations: [Capability: CapabilityObservation]

    public init(observations: [Capability: CapabilityObservation] = [:]) {
        self.observations = observations
    }

    /// A matrix in which every capability is `.notRequested` — the honest starting point, and
    /// what a first launch reports before a single probe has run.
    public static func unobserved(at instant: Date) -> CapabilityMatrix {
        CapabilityMatrix(
            observations: Dictionary(
                uniqueKeysWithValues: Capability.allCases.map {
                    ($0, CapabilityObservation(state: .notRequested, observedAt: instant))
                }
            )
        )
    }

    public func observation(of capability: Capability) -> CapabilityObservation? {
        observations[capability]
    }

    /// The state of a capability nobody has observed is `.notRequested`, which is the truth
    /// rather than a default.
    public func state(of capability: Capability) -> CapabilityState {
        observations[capability]?.state ?? .notRequested
    }

    public func isAvailable(_ capability: Capability) -> Bool {
        state(of: capability).isUsable
    }

    /// What `consumer` does about `capability` right now: nothing, if it is available, and the
    /// declared fallback otherwise.
    public func fallback(
        for capability: Capability,
        consumer: SensingConsumer
    ) -> CapabilityFallback? {
        guard !isAvailable(capability) else { return nil }
        return CapabilityContract.fallback(for: capability, consumer: consumer)
    }

    /// Record an observation, refusing the one transition that would let the app ask twice.
    ///
    /// A `.denied` capability offered `.notRequested` keeps its denial — and keeps its
    /// `educationShownAt`, so the explanation is not re-armed either.
    public func recording(
        _ capability: Capability,
        as state: CapabilityState,
        at instant: Date
    ) -> CapabilityMatrix {
        var copy = self
        let existing = observations[capability]

        if existing?.state == .denied && state == .notRequested {
            // Refused. A denial does not decay into a question.
            return self
        }

        copy.observations[capability] = CapabilityObservation(
            state: state,
            observedAt: instant,
            educationShownAt: existing?.educationShownAt
        )
        return copy
    }

    /// Note that the user has been told why a capability is denied. Idempotent: the second
    /// call keeps the first instant, because "written exactly once" is the assertion.
    public func recordingEducationShown(
        for capability: Capability,
        at instant: Date
    ) -> CapabilityMatrix {
        guard let existing = observations[capability] else { return self }
        guard existing.educationShownAt == nil else { return self }

        var copy = self
        copy.observations[capability] = CapabilityObservation(
            state: existing.state,
            observedAt: existing.observedAt,
            educationShownAt: instant
        )
        return copy
    }

    /// Every capability with its state, ordered by `Capability.allCases`, for the self-check
    /// and for the Privacy surface. Twelve rows, always — a capability nobody probed appears
    /// as `.notRequested` rather than not appearing.
    public var allStates: [(capability: Capability, state: CapabilityState)] {
        Capability.allCases.map { ($0, state(of: $0)) }
    }
}
