import Foundation

/// Whether a capture device is running somewhere on this Mac.
///
/// ## Exactly two properties, and nothing a nudge could quote
///
/// There is no `isInMeeting`, no `meetingConfidence` and no string. That is the enforcement of
/// the Court's condition, at the level of the type: this signal may **suppress** an
/// intervention and may never **assert** that a meeting is occurring, and it cannot assert
/// anything because it has no member an assertion could be built from.
///
/// The asymmetry is deliberate and the reason is measured. Cross-device false positives are
/// expected — another Mac, an iPhone on the same Continuity session, or a background utility
/// can make a device run — and suppression is safe under that failure mode where assertion
/// would not be.
///
/// ## `cameraRunning` is always `false` in v1
///
/// Not because no camera is running, but because this epic refuses to claim a path it never
/// measured. CoreMediaIO enumerated **zero** devices on the rig (probe P-97), so the
/// per-device running-state read, the listener install and the TCC observation *of those
/// calls* never executed (probe P-104). "The enumeration is prompt-free" is measured; "the
/// complete camera path is prompt-free" would be an extrapolation from an empty list. So the
/// camera half ships pinned off on **every** Mac, and mic-only suppression is the shipped
/// behaviour.
public struct MediaActivity: Sendable, Equatable, Hashable {
    /// Whether an audio device **with input channels** is running somewhere.
    ///
    /// Input only. Measured (probe P-96): an *output* device flipped to running merely because
    /// `say` was speaking — a person listening to music, not a meeting, and precisely the
    /// false positive the Court warned about.
    public let microphoneRunning: Bool

    /// **Always `false` in v1**, on every Mac, by construction. See the type note.
    public let cameraRunning: Bool

    public init(microphoneRunning: Bool, cameraRunning: Bool = false) {
        self.microphoneRunning = microphoneRunning
        self.cameraRunning = cameraRunning
    }

    public static let idle = MediaActivity(microphoneRunning: false, cameraRunning: false)

    /// Whether this state is a reason to stand down. The only question this type answers.
    public var suppressesIntervention: Bool { microphoneRunning || cameraRunning }
}

/// Why `cameraActivity` is `.unavailable`, which it is on every Mac in v1.
///
/// The distinction is not cosmetic: one of these is a fact about the hardware and the other is
/// a decision about evidence, and a surface that said "no camera on this Mac" to somebody
/// holding a MacBook would be lying to them.
public enum CameraUnavailableReason: String, Sendable, CaseIterable, Codable, Hashable {
    /// CoreMediaIO enumerated zero devices. There is no camera here.
    case noDevices
    /// There are cameras, and the deeper path has never been observed for prompts on real
    /// camera hardware. The surface says "camera activity is not used in this version" — which
    /// is true, and is not a denial, and is not a call to action.
    case unprovenOnThisHardware
}
