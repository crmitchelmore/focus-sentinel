import Foundation

/// One reading of how long the person has been away from the keyboard, from **both** sources.
///
/// ## Why both, and why the hardware one wins
///
/// `CGEventSource.secondsSinceLastEventType` takes a state, and the two available states do
/// not agree. Measured on this machine at one instant (probe P-85): `.combinedSessionState`
/// read **267 s** while `.hidSystemState` read **1536 s** — a twenty-one-minute disagreement,
/// because the combined source counts **synthetic posted events** and the HID one counts
/// hardware only. A daemon, an automation tool or a Screen Sharing session keeps the combined
/// figure small while the human is demonstrably absent.
///
/// The registry named the combined source. This narrows it to the hardware one, with two
/// reasons:
///
/// * Because combined counts a strict superset of events, `combined ≤ hid` **always**. The HID
///   source is therefore the strictly more pessimistic one: it declares the user idle sooner.
/// * Idle **suppresses** intervention, and the two failure directions are not symmetric.
///   Calling a present user idle costs a nudge that would have been welcome. Calling an absent
///   user present nudges an empty chair — which is the exact failure idle detection exists to
///   prevent. The safer source wins.
///
/// ## The limitation, stated rather than hidden
///
/// A person working over Screen Sharing produces only synthetic events, so this app will
/// consider them idle and will not nudge them. That is written into the Settings copy, not
/// buried here.
public struct IdleReading: Sendable, Equatable, Hashable {
    /// `.hidSystemState` — hardware input only. **The primary.**
    public let hardwareSeconds: Double
    /// `.combinedSessionState` — hardware *and* synthetic posted events. Recorded, never
    /// decisive.
    public let sessionSeconds: Double

    public init(hardwareSeconds: Double, sessionSeconds: Double) {
        self.hardwareSeconds = hardwareSeconds
        self.sessionSeconds = sessionSeconds
    }

    /// Whether the person is away, by the pessimistic source.
    public func isIdle(threshold: Double) -> Bool {
        hardwareSeconds >= threshold
    }

    /// Whether something is posting synthetic events while no hardware input arrives.
    ///
    /// The gap is the signature: hardware idle keeps climbing while the session figure keeps
    /// being reset by events nobody's hands produced. When this becomes true, exactly one
    /// `syntheticInputObserved` event is written **per transition**, so a timeline that looks
    /// strange later has an explanation in it rather than a mystery.
    public func syntheticInputSuspected(threshold: Double) -> Bool {
        hardwareSeconds - sessionSeconds > threshold
    }

    /// `combined ≤ hid` is a property of what the two sources count, not a coincidence.
    ///
    /// A reading that violates it means the reader swapped its sources — which would silently
    /// invert the safe direction — so the self-check asserts it on live readings and the suite
    /// asserts it on every fixture.
    public var sourcesAreInTheRightOrder: Bool {
        hardwareSeconds >= sessionSeconds
    }
}
