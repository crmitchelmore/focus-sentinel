import Foundation

/// One reading of how long the person has been away from the keyboard, from **both** sources.
///
/// ## Neither source alone is trustworthy — measured, not argued
///
/// `CGEventSource.secondsSinceLastEventType` takes a state, and this app reads both with the
/// `kCGAnyInputEventType` sentinel (`~0`). The old comment here said `.combinedSessionState`
/// counts a strict superset of what `.hidSystemState` counts, so `combined ≤ hid` **always**,
/// and made the hardware figure the primary on that argument. **The premise is false.** Measured
/// on this machine 2026-09-03 (`.agents/plans/idle-sources-investigation.md`):
///
/// * For every *concrete* event type — `.mouseMoved`, `.keyDown`, `.leftMouseDown`,
///   `.scrollWheel` — the two states return the **same** seconds, to the width of a syscall.
///   The divergence exists only at the `~0` sentinel.
/// * Under `.hidSystemState`, that sentinel is **not** "the newest CGEvent of any type". It is
///   IOHIDSystem's raw `HIDIdleTime` clock — byte-identical to `ioreg`'s across six paired
///   samples — and it **resets on HID device reports that never become input events**. On this
///   Mac it read **105.71 s** while every concrete CGEvent type read **14 850 s** and `w`
///   agreed the machine had been untouched for four hours.
/// * Under `.combinedSessionState` the same sentinel returns the session's newest CGEvent, and
///   so misses genuine input outside this login session.
///
/// Neither event set contains the other, so there is no "more pessimistic source" to pick.
///
/// ## What `isIdle` therefore trusts
///
/// The **maximum** of the two. Idle **suppresses** intervention, and the two failure directions
/// are not symmetric: calling a present user idle costs a nudge that would have been welcome,
/// while calling an absent user present nudges an empty chair — the exact failure idle detection
/// exists to prevent. The maximum keeps that asymmetry now that "hardware" no longer supplies
/// it. A person who has produced no input event for the threshold is idle whatever a phantom HID
/// report says about a device that twitched.
///
/// ## The limitation, stated rather than hidden
///
/// A person working over Screen Sharing produces only synthetic events. Those still reset
/// `.combinedSessionState`, so under the maximum they are treated as idle once the HID clock has
/// also climbed past the threshold. That is written into the Settings copy, not buried here.
public struct IdleReading: Sendable, Equatable, Hashable {
    /// `.hidSystemState` at `kCGAnyInputEventType` — IOHIDSystem's `HIDIdleTime`. Resets on HID
    /// reports that never become input events, so it is a floor on absence and never a verdict
    /// on presence.
    public let hardwareSeconds: Double
    /// `.combinedSessionState` at `kCGAnyInputEventType` — this login session's newest CGEvent,
    /// hardware *and* synthetic. Blind to input outside the session.
    public let sessionSeconds: Double

    public init(hardwareSeconds: Double, sessionSeconds: Double) {
        self.hardwareSeconds = hardwareSeconds
        self.sessionSeconds = sessionSeconds
    }

    /// Whether the person is away: **either** counter having climbed past the threshold is
    /// enough.
    ///
    /// `max(hardware, session) >= threshold`. The maximum is the longest silence either source
    /// can testify to, and it is the pessimistic reading in the direction that matters: a source
    /// that has seen nothing for the threshold is evidence of absence, and a source that has
    /// just been reset by a device report nobody touched is not evidence of presence. Under
    /// `hardwareSeconds` alone this returned `false` on a chair that had been empty for four
    /// hours.
    public func isIdle(threshold: Double) -> Bool {
        max(hardwareSeconds, sessionSeconds) >= threshold
    }

    /// Whether something is posting synthetic events while no hardware input arrives.
    ///
    /// The gap is the signature: hardware idle keeps climbing while the session figure keeps
    /// being reset by events nobody's hands produced. When this becomes true, exactly one
    /// `syntheticInputObserved` event is written **per transition**, so a timeline that looks
    /// strange later has an explanation in it rather than a mystery.
    ///
    /// One-sided on purpose, and the other side has a name now: the reverse gap — session far
    /// above hardware — is the phantom-HID reset described above, not synthetic input, and it is
    /// published as a number (`hardwareMinusSessionSeconds`) rather than folded into this
    /// verdict.
    public func syntheticInputSuspected(threshold: Double) -> Bool {
        hardwareSeconds - sessionSeconds > threshold
    }
}
