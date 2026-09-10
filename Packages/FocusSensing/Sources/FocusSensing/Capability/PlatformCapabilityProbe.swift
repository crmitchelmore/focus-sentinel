import AppKit
import CoreGraphics
import FocusCore
import Foundation

/// The twelve capabilities, read off the platform — **read, never asked**.
///
/// ## A probe that structurally cannot ask
///
/// Every question this answers was measured prompt-free from an ad-hoc-signed bundle launched
/// with `open -a`, holding no TCC row of any kind (probes P-74, P-79, P-84, P-87, P-90/P-91,
/// P-93, P-94/P-95, P-97). Beyond that, the prompting APIs are banned from the shipping graph by
/// lint, so this file could not grow an ask even if somebody wanted one. `AXIsProcessTrusted()`
/// and `CGPreflightScreenCaptureAccess()` would stay permitted — reading trust state is not
/// requesting it — and this probe does not need either, because the two capabilities they
/// describe belong to epics that have not landed.
///
/// ## The three answers that are decisions rather than measurements
///
/// * **`cameraActivity` is pinned `.unavailable`**, on every Mac. Not a denial, and not a
///   hardware accident either: the enumeration was measured prompt-free, the per-device read and
///   listener install never executed for want of a device, and an unanswered question is not a
///   pass (probes P-97/P-104, ruling R-40).
/// * **`screenCapture` is `.unavailable`** because pixel capture is parked by the Feasibility
///   Court (dissent D-04). There is nothing to probe, because there is nothing to use.
/// * **`accessibilityWindowContext`, `notifications` and `onDeviceModel` are `.notRequested`**,
///   which is the literal truth: this epic has not asked, and in this epic it never will.
///   Reporting `.denied` for a question nobody put would be inventing a refusal.
///
/// ## Refreshed on wake, on resume, and on demand — never on a timer
///
/// A timer would turn a capability table into a poll, and a poll into a thing that could ask
/// twice. `SensingHost` calls this at those three moments and at no other.
@MainActor
public final class PlatformCapabilityProbe: CapabilityProbing {
    private let windowList: any WindowListReading
    private let screens: any ScreenListReading
    private let idleSource: any IdleSourceReading
    private let audio: any AudioDeviceEnumerating
    private let camera: CMIOMediaObserver

    /// What the composition layer read from the model tier, or `.notRequested` when nothing
    /// composed a port to read with (e06).
    ///
    /// Handed down rather than read here: `FoundationModels` is named in exactly one file in
    /// this repository, that file is in `Packages/FocusModel`, and this package's framework row
    /// does not permit it and must not. `FocusHost` is the only module that sees both.
    private let onDeviceModel: CapabilityState

    public init(
        windowList: any WindowListReading = SystemWindowList(),
        screens: any ScreenListReading = SystemScreenList(),
        idleSource: any IdleSourceReading = CGEventIdleSource(),
        audio: any AudioDeviceEnumerating = SystemAudioDeviceEnumerator(),
        camera: CMIOMediaObserver = CMIOMediaObserver(),
        onDeviceModel: CapabilityState = .notRequested
    ) {
        self.windowList = windowList
        self.screens = screens
        self.idleSource = idleSource
        self.audio = audio
        self.camera = camera
        self.onDeviceModel = onDeviceModel
    }

    /// `CapabilityProbing` is `Sendable` and its one requirement is not actor-isolated, but
    /// every read below touches AppKit or CoreGraphics. The hop is `assumeIsolated` rather than
    /// a queue because this probe is only ever called from the main actor: at launch, on wake,
    /// on resume from pause, and from the self-check — all of which are main-actor moments.
    ///
    /// **That is a call-site inventory, not an API guarantee** (focus-068's audit). It is the
    /// weaker of the two justifications this codebase uses for `assumeIsolated`, and it is the
    /// one that can be invalidated by adding a caller rather than by a framework changing its
    /// mind. It stands here because the requirement is synchronous — it returns the matrix — so
    /// the alternative is not a hop but an `async` protocol. Whoever adds the fifth caller owns
    /// re-reading this line.
    public nonisolated func probe(at instant: Date) -> CapabilityMatrix {
        MainActor.assumeIsolated { probeOnMainActor(at: instant) }
    }

    /// The twelve answers, each with the probe that produced it.
    public func probeOnMainActor(at instant: Date) -> CapabilityMatrix {
        var matrix = CapabilityMatrix()

        for (capability, state) in states() {
            matrix = matrix.recording(capability, as: state, at: instant)
        }
        return matrix
    }

    /// Every capability with the state this machine reports, in `Capability.allCases` order.
    public func states() -> [(Capability, CapabilityState)] {
        let windows = windowList.copyWindowInfo()
        let displays = screens.screens()
        let audioDevices = audio.devices()
        camera.refresh()

        return [
            // The bundle identifier rides on the activation notification itself; there is no
            // platform state that can withhold it (probe P-79).
            (.frontmostApplication, .available),

            // A window list that comes back empty on a Mac with windows on screen would mean
            // the call is not answering — which is not a thing that was ever observed, and is
            // not a thing to report as available.
            (.windowMetadata, windows.isEmpty ? .unavailable : .available),

            // A live counter, not a cached one: it advanced by exactly the elapsed time across
            // a sleep with no input (probe P-84). A non-finite reading is the only failure.
            (.idle, idleSource.hardwareSeconds.isFinite ? .available : .unavailable),

            // The lock primary is a public notification, and subscribing to it needs nothing.
            (.systemLifecycle, .available),

            (.displayGeometry, displays.isEmpty ? .unavailable : .available),

            // The presentation quorum's inputs are AppKit reads and a window-list read; the
            // second is the only one that can be unavailable, and it is reported above.
            (.presentation, windows.isEmpty ? .unavailable : .available),

            // Zero audio devices is "there is nothing to ask", not "the microphone is idle".
            (.microphoneActivity, audioDevices.contains(where: \.hasInput) ? .available : .unavailable),

            // Pinned. See the type note.
            (.cameraActivity, camera.cameraActivity),

            (.accessibilityWindowContext, .notRequested),
            (.screenCapture, .unavailable),
            (.notifications, .notRequested),

            // e06. `.notRequested` was a lie the moment the app could read the availability, and
            // the reading itself cannot happen here — `FoundationModels` is named in exactly one
            // file in this repository and it is in `Packages/FocusModel`, which this package's
            // matrix row does not permit and must not. So the composition layer, which is the
            // only module that sees both, hands the answer down as a `FocusCore` value.
            // `.notRequested` is what a probe built with no answer reports, and it is honest:
            // nothing has been asked, because nothing composed a port to ask with.
            (.onDeviceModel, onDeviceModel)
        ]
    }

    /// Why the camera is unavailable on **this** rig — the hardware fact or the held path.
    /// Reported by the self-check beside the state, so the two are never confused.
    public var cameraUnavailableReason: CameraUnavailableReason {
        camera.unavailableReason
    }

    /// How many camera devices CoreMediaIO enumerated, and how many listeners the camera path
    /// has installed. The second is asserted `0` on every rig.
    public var cameraDeviceCount: Int { camera.deviceCount }

    public var cameraListenersInstalled: Int { camera.listenersInstalled }
}
