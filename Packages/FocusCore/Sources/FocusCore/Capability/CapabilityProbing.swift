import Foundation

/// The seam between "what the platform reports" and "what the app believes".
///
/// The implementation lives in `FocusSensing`, because answering it means touching AppKit,
/// CoreGraphics, CoreAudio and CoreMediaIO — and because keeping it out of here is what keeps
/// `FocusCore`'s import row three words long.
///
/// **A probe reads and never asks.** Every question it answers in e03 was measured
/// prompt-free from an ad-hoc-signed bundle holding no TCC row of any kind, and the prompting
/// APIs are banned from the shipping graph by lint, so this protocol could not grow an ask
/// even if somebody wanted one. `AXIsProcessTrusted()` and `CGPreflightScreenCaptureAccess()`
/// stay permitted implementations of it: reading trust state is not requesting it.
public protocol CapabilityProbing: Sendable {
    /// Read the state of every capability, at `instant`.
    ///
    /// Called on wake, on resume from global pause, and on demand — never on a timer.
    func probe(at instant: Date) -> CapabilityMatrix
}

/// A probe that answers from a table it was handed.
///
/// This is what makes F-155's permission-absent matrix testable at all: all five states are
/// exercised against injected adapters, on a machine where only three of them occur naturally.
public struct StaticCapabilityProbe: CapabilityProbing {
    private let states: [Capability: CapabilityState]

    public init(_ states: [Capability: CapabilityState]) {
        self.states = states
    }

    /// Every capability at one state — the fastest way to write "and now suppose everything
    /// were denied".
    public init(everything state: CapabilityState) {
        self.states = Dictionary(
            uniqueKeysWithValues: Capability.allCases.map { ($0, state) }
        )
    }

    public func probe(at instant: Date) -> CapabilityMatrix {
        var matrix = CapabilityMatrix()
        for capability in Capability.allCases {
            matrix = matrix.recording(
                capability,
                as: states[capability] ?? .notRequested,
                at: instant
            )
        }
        return matrix
    }
}

extension CapabilityMatrix {
    /// What a probe on a zero-grant Mac reports in e03, and why each answer is what it is.
    ///
    /// Seven capabilities are `.available` because each was measured working from a bundle
    /// holding no TCC row. `cameraActivity` is `.unavailable` **on every rig, not only on the
    /// one with no camera**: the enumeration was measured prompt-free, the deeper path never
    /// executed, and an unanswered question is not a pass. `screenCapture` is `.unavailable`
    /// because pixel capture is parked. Two of the remaining three are `.notRequested` because
    /// the epics that own them have not landed — and in e03 the app has no way to ask.
    ///
    /// **`onDeviceModel` stopped being one of them in e06.** *"Nothing has been asked, and
    /// nothing has been observed"* became a lie the moment the app could read
    /// `SystemLanguageModel.default.availability`, so the row is now whatever
    /// `ModelTierAvailability.capabilityState` says on the machine the probe ran on. It is a
    /// PARAMETER here rather than a literal, because a fixture that pinned one answer would be
    /// pinning a fact about one Mac; `.notRequested` remains the default, and it is the honest
    /// answer for a composition built with no port, which has genuinely not looked.
    ///
    /// This is the shape the platform probe must produce, expressed once so that a test and
    /// the self-check can both compare against it rather than each carrying their own copy.
    public static func zeroGrantExpectation(
        at instant: Date,
        onDeviceModel: CapabilityState = .notRequested
    ) -> CapabilityMatrix {
        StaticCapabilityProbe([
            .frontmostApplication: .available,
            .windowMetadata: .available,
            .idle: .available,
            .systemLifecycle: .available,
            .displayGeometry: .available,
            .presentation: .available,
            .microphoneActivity: .available,
            .cameraActivity: .unavailable,
            .screenCapture: .unavailable,
            .accessibilityWindowContext: .notRequested,
            .notifications: .notRequested,
            .onDeviceModel: onDeviceModel
        ]).probe(at: instant)
    }

    /// The capabilities e03 actually uses. None of them may be `.notRequested` on a rig where
    /// the app is running: `.notRequested` there would mean a facility the epic depends on had
    /// never been looked at.
    public static let capabilitiesUsedInThisEpic: [Capability] = [
        .frontmostApplication, .windowMetadata, .idle, .systemLifecycle,
        .displayGeometry, .presentation, .microphoneActivity
    ]
}
