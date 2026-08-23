import CoreMediaIO
import FocusCore
import Foundation

/// A CoreMediaIO device identifier, as a plain integer.
public typealias CameraDeviceIdentifier = UInt32

/// The seam between this app and CoreMediaIO.
///
/// Every method below the enumeration exists so that the **held** path is real code a re-probe
/// can drive, rather than a copy of it written later against a different design. Nothing in
/// the shipping app calls them: `CMIOMediaObserver` reaches them only when `FOCUS_CAMERA_PROBE`
/// is set, and that variable is set nowhere in the app, the gate or any lane.
@MainActor
public protocol CameraDeviceEnumerating: AnyObject {
    /// `kCMIOHardwarePropertyDevices`. **The one call that was measured prompt-free** (probe
    /// P-97): status `0`, zero devices, no prompt.
    func deviceIDs() -> [CameraDeviceIdentifier]

    /// `kCMIODevicePropertyDeviceIsRunningSomewhere` on one device.
    ///
    /// **Never executed on the rig**, because there was no device to execute it against
    /// (probe P-104). Held behind the flag for exactly that reason.
    func isRunningSomewhere(_ device: CameraDeviceIdentifier) -> Bool

    /// `CMIOObjectAddPropertyListenerBlock`. Likewise never executed, likewise held.
    @discardableResult
    func addListener(to device: CameraDeviceIdentifier, handler: @escaping @Sendable () -> Void) -> Bool

    @discardableResult
    func removeListener(from device: CameraDeviceIdentifier) -> Bool

    /// How many listeners are installed. The self-check asserts this is `0` **on every rig,
    /// camera or not** — which is an assertion that the held path was never entered, rather
    /// than an assertion about a hardware accident.
    var installedListenerCount: Int { get }
}

/// The production CoreMediaIO enumerator.
///
/// `kCMIOHardwarePropertyAllowScreenCaptureDevices` is **never set**, flag or no flag: opting
/// screen-capture DAL devices into the enumeration is Screen-Recording-adjacent for no benefit,
/// and this programme does not go near pixel capture (dissent D-04).
@MainActor
public final class SystemCameraDeviceEnumerator: CameraDeviceEnumerating {
    private var listeners: [CameraDeviceIdentifier: CMIOObjectPropertyListenerBlock] = [:]
    private let queue = DispatchQueue(label: "com.chrismitchelmore.FocusSentinel.camera-observation")

    public init() {}

    public func deviceIDs() -> [CameraDeviceIdentifier] {
        var address = Self.address(selector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        var byteSize: UInt32 = 0
        guard
            CMIOObjectGetPropertyDataSize(
                CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &byteSize
            ) == noErr,
            byteSize > 0
        else {
            // Zero devices is a **hardware** fact, not a TCC one — this Mac has no camera, and
            // `system_profiler SPCameraDataType` says so independently (probe P-97).
            return []
        }

        let count = Int(byteSize) / MemoryLayout<CMIOObjectID>.size
        var identifiers = [CMIOObjectID](repeating: 0, count: count)
        var used = byteSize
        guard
            CMIOObjectGetPropertyData(
                CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, byteSize, &used, &identifiers
            ) == noErr
        else {
            return []
        }
        return identifiers
    }

    public func isRunningSomewhere(_ device: CameraDeviceIdentifier) -> Bool {
        var address = Self.address(
            selector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)
        )
        var running: UInt32 = 0
        var used: UInt32 = 0
        let byteSize = UInt32(MemoryLayout<UInt32>.size)
        guard
            CMIOObjectGetPropertyData(device, &address, 0, nil, byteSize, &used, &running) == noErr
        else {
            return false
        }
        return running != 0
    }

    @discardableResult
    public func addListener(
        to device: CameraDeviceIdentifier,
        handler: @escaping @Sendable () -> Void
    ) -> Bool {
        guard listeners[device] == nil else { return true }
        var address = Self.address(
            selector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)
        )
        let block: CMIOObjectPropertyListenerBlock = { _, _ in handler() }
        guard CMIOObjectAddPropertyListenerBlock(device, &address, queue, block) == noErr else {
            return false
        }
        listeners[device] = block
        return true
    }

    @discardableResult
    public func removeListener(from device: CameraDeviceIdentifier) -> Bool {
        guard let block = listeners.removeValue(forKey: device) else { return false }
        var address = Self.address(
            selector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)
        )
        return CMIOObjectRemovePropertyListenerBlock(device, &address, queue, block) == noErr
    }

    public var installedListenerCount: Int { listeners.count }

    private static func address(selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }
}

/// The camera half of F-36: **enumerated, written, and switched off**.
///
/// ## Why an unanswered question is not a pass
///
/// The Court's condition was *prove whether merely observing raises any prompt; if it prompts,
/// the feature degrades to absent.* On the rig that question could not be answered for the
/// camera, because the rig has no camera. CoreMediaIO enumerated **zero devices** (probe P-97),
/// so the per-device running-state read, the listener install and remove, a real transition and
/// the TCC observation *of those calls* never executed (probe P-104). "The enumeration is
/// prompt-free" is measured. "The complete camera path is prompt-free" would be an
/// extrapolation from an empty list, and this epic refuses to make it.
///
/// ## So, on every Mac, in v1
///
/// * `cameraRunning` is **`false`**, always, and is never a suppression input. Mic-only
///   suppression is the shipped behaviour and nothing degrades that the microphone provides.
/// * `cameraActivity` is **`.unavailable`**, always — with reason `.noDevices` where there is
///   no hardware and `.unprovenOnThisHardware` where there is. It is **never `.denied`**:
///   nobody refused anything, and offering to "fix" it would be an insult on one Mac and a lie
///   on the other.
/// * The per-device read and the listener install are compiled and sit behind
///   `FOCUS_CAMERA_PROBE=1`, **set nowhere in the app, the gate or any lane**. It exists so the
///   re-probe drives the real code rather than a copy of it.
/// * `listenersInstalled` is asserted `0` by the self-check on every rig, which is an assertion
///   that the held path was never entered rather than an assertion about hardware.
///
/// Turning it on needs the written checklist in the plan's R-40, run on a Mac that has a
/// camera. That is future work, and it is explicitly **not** a close condition of this epic.
@MainActor
public final class CMIOMediaObserver {
    private let enumerator: any CameraDeviceEnumerating
    private let environment: [String: String]

    /// How many camera devices CoreMediaIO enumerated. `0` on the rig, and on any Mac without
    /// a camera.
    public private(set) var deviceCount = 0

    /// What the held path found, when a re-probe drives it. Empty in every shipping build,
    /// and **never** read by `cameraRunning`.
    public private(set) var probeObservations: [CameraDeviceIdentifier: Bool] = [:]

    public init(
        enumerator: any CameraDeviceEnumerating = SystemCameraDeviceEnumerator(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.enumerator = enumerator
        self.environment = environment
    }

    /// The environment variable that unlocks the held path. Named here so that a search for it
    /// lands on this comment rather than on a shell script somewhere.
    public static let probeFlagName = "FOCUS_CAMERA_PROBE"

    /// Whether the held path is unlocked in **this** process. False everywhere the app,
    /// the gate or an evidence lane runs it.
    public var probeFlagIsSet: Bool { environment[Self.probeFlagName] == "1" }

    /// **Always `false`.** Not because no camera is running — because this epic never measured
    /// what asking would do.
    public var cameraRunning: Bool { false }

    /// **Always `.unavailable`.** Never `.denied`, and never `.available`.
    public var cameraActivity: CapabilityState { .unavailable }

    /// Which kind of unavailable. A surface that said "no camera on this Mac" to somebody
    /// holding a MacBook would be lying to them, so the two are distinguished.
    public var unavailableReason: CameraUnavailableReason {
        deviceCount == 0 ? .noDevices : .unprovenOnThisHardware
    }

    /// Zero on every rig in v1. The gate asserts it.
    public var listenersInstalled: Int { enumerator.installedListenerCount }

    /// Enumerate — and, in every shipping build, stop there.
    @discardableResult
    public func refresh() -> Int {
        deviceCount = enumerator.deviceIDs().count

        // The shipping path ends on this line, on every Mac, whatever the enumeration found.
        // Everything below is the held re-probe path (R-40), which exists so that the work
        // which could one day lift the hold drives the real code.
        guard probeFlagIsSet else { return deviceCount }

        probeObservations = [:]
        for device in enumerator.deviceIDs() {
            probeObservations[device] = enumerator.isRunningSomewhere(device)
            enumerator.addListener(to: device) {}
        }
        return deviceCount
    }

    /// Remove whatever the held path installed. A no-op in every shipping build, because the
    /// held path installs nothing there.
    public func detachListeners() {
        for device in enumerator.deviceIDs() {
            enumerator.removeListener(from: device)
        }
        probeObservations = [:]
    }

    public func pause() {
        detachListeners()
    }
}
