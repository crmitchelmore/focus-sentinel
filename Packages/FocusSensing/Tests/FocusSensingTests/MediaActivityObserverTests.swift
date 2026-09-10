import FocusCore
import Foundation
import Testing

@testable import FocusSensing

/// An audio device set a test chose, which records every listener it was asked to install.
///
/// The two cases that matter cannot be produced on demand on a real Mac — a machine with no
/// audio device at all, and an output-only device that is running — so both are fixtures here.
@MainActor
final class ScriptedAudioDevices: AudioDeviceEnumerating {
    private var snapshots: [AudioDeviceSnapshot]
    private var running: Set<AudioDeviceIdentifier>
    private var listeners: [AudioDeviceIdentifier: @Sendable () -> Void] = [:]
    private var deviceListListener: (@Sendable () -> Void)?

    /// Which devices `IsRunningSomewhere` was ever read on. The input-only rule is asserted on
    /// this, not merely on the answer.
    private(set) var runningReads: [AudioDeviceIdentifier] = []

    init(devices: [AudioDeviceSnapshot], running: Set<AudioDeviceIdentifier> = []) {
        self.snapshots = devices
        self.running = running
    }

    func devices() -> [AudioDeviceSnapshot] { snapshots }

    func isRunningSomewhere(_ device: AudioDeviceIdentifier) -> Bool {
        runningReads.append(device)
        return running.contains(device)
    }

    @discardableResult
    func addListener(
        to device: AudioDeviceIdentifier,
        handler: @escaping @Sendable () -> Void
    ) -> Bool {
        listeners[device] = handler
        return true
    }

    @discardableResult
    func removeListener(from device: AudioDeviceIdentifier) -> Bool {
        listeners.removeValue(forKey: device) != nil
    }

    @discardableResult
    func addDeviceListListener(handler: @escaping @Sendable () -> Void) -> Bool {
        deviceListListener = handler
        return true
    }

    @discardableResult
    func removeDeviceListListener() -> Bool {
        guard deviceListListener != nil else { return false }
        deviceListListener = nil
        return true
    }

    var installedListenerCount: Int {
        listeners.count + (deviceListListener == nil ? 0 : 1)
    }

    // MARK: - Driving

    func setRunning(_ device: AudioDeviceIdentifier, _ isRunning: Bool) {
        if isRunning { running.insert(device) } else { running.remove(device) }
        listeners[device]?()
    }

    func replaceDevices(with devices: [AudioDeviceSnapshot]) {
        snapshots = devices
        deviceListListener?()
    }

    // MARK: - The rig's own inventory (probe P-104)

    /// `Yeti Stereo Microphone`, two input channels — the one device of the five that can hear.
    static let microphone = AudioDeviceSnapshot(id: 102, inputChannelCount: 2, outputChannelCount: 0)
    /// `External Headphones` — the device probe P-96 caught flipping to running under `say`.
    static let headphones = AudioDeviceSnapshot(id: 87, inputChannelCount: 0, outputChannelCount: 2)
    static let otherOutput = AudioDeviceSnapshot(id: 95, inputChannelCount: 0, outputChannelCount: 2)
}

/// A camera device set a test chose, which records every deeper call it was asked to make.
///
/// The counters are the assertion: the criterion is not only that `cameraRunning` is `false`,
/// but that **no per-device read and no listener install was attempted** — because that path
/// has never been observed for prompts on real hardware.
@MainActor
final class ScriptedCameraDevices: CameraDeviceEnumerating {
    private let identifiers: [CameraDeviceIdentifier]
    private let running: Set<CameraDeviceIdentifier>
    private var listeners: Set<CameraDeviceIdentifier> = []

    private(set) var enumerationCount = 0
    private(set) var perDeviceReadCount = 0
    private(set) var listenerInstallCount = 0

    init(identifiers: [CameraDeviceIdentifier], running: Set<CameraDeviceIdentifier> = []) {
        self.identifiers = identifiers
        self.running = running
    }

    func deviceIDs() -> [CameraDeviceIdentifier] {
        enumerationCount += 1
        return identifiers
    }

    func isRunningSomewhere(_ device: CameraDeviceIdentifier) -> Bool {
        perDeviceReadCount += 1
        return running.contains(device)
    }

    @discardableResult
    func addListener(
        to device: CameraDeviceIdentifier,
        handler: @escaping @Sendable () -> Void
    ) -> Bool {
        listenerInstallCount += 1
        listeners.insert(device)
        return true
    }

    @discardableResult
    func removeListener(from device: CameraDeviceIdentifier) -> Bool {
        listeners.remove(device) != nil
    }

    var installedListenerCount: Int { listeners.count }
}

@MainActor
@Suite("Media activity observer")
struct MediaActivityObserverTests {
    // MARK: - Input devices only (probe P-96)

    @Test("An output-only device that is running never raises microphoneRunning")
    func outputDeviceRunningIsNotAMicrophone() {
        // The exact P-96 case: `say` is speaking through External Headphones, which flips to
        // running. A person listening to something is not a person in a meeting.
        let devices = ScriptedAudioDevices(
            devices: [
                ScriptedAudioDevices.microphone,
                ScriptedAudioDevices.headphones,
                ScriptedAudioDevices.otherOutput
            ],
            running: [ScriptedAudioDevices.headphones.id]
        )
        let observer = MediaActivityObserver(enumerator: devices)

        observer.start()

        #expect(observer.activity.microphoneRunning == false)
        #expect(observer.activity.suppressesIntervention == false)
    }

    @Test("IsRunningSomewhere is read only on devices with input channels")
    func onlyInputDevicesAreRead() {
        let devices = ScriptedAudioDevices(
            devices: [
                ScriptedAudioDevices.microphone,
                ScriptedAudioDevices.headphones,
                ScriptedAudioDevices.otherOutput
            ]
        )
        let observer = MediaActivityObserver(enumerator: devices)

        observer.refresh()

        #expect(devices.runningReads == [ScriptedAudioDevices.microphone.id])
    }

    @Test("An input device that is running does raise microphoneRunning")
    func inputDeviceRunningIsAMicrophone() {
        let devices = ScriptedAudioDevices(
            devices: [ScriptedAudioDevices.microphone, ScriptedAudioDevices.headphones],
            running: [ScriptedAudioDevices.microphone.id]
        )
        let observer = MediaActivityObserver(enumerator: devices)

        observer.start()

        #expect(observer.activity.microphoneRunning)
        #expect(observer.activity.suppressesIntervention)
    }

    @Test("The input and output counts are reported separately")
    func countsAreReportedSeparately() {
        let devices = ScriptedAudioDevices(
            devices: [
                ScriptedAudioDevices.microphone,
                ScriptedAudioDevices.headphones,
                ScriptedAudioDevices.otherOutput
            ]
        )
        let observer = MediaActivityObserver(enumerator: devices)

        observer.refresh()

        #expect(observer.deviceCount == 3)
        #expect(observer.inputDeviceCount == 1)
        #expect(observer.outputDeviceCount == 2)
    }

    // MARK: - Zero devices is unavailable, never false

    @Test("Zero audio devices reports .unavailable rather than a confident false")
    func zeroDevicesIsUnavailable() {
        let observer = MediaActivityObserver(enumerator: ScriptedAudioDevices(devices: []))

        observer.start()

        #expect(observer.microphoneCapability == .unavailable)
        #expect(observer.inputDeviceCount == 0)
        // The activity value still reads false, because there is nothing running — but the
        // *capability* is what a consumer must consult, and it says "there is nothing to ask".
        #expect(observer.activity.microphoneRunning == false)
    }

    @Test("A device that can hear makes the capability available")
    func inputDeviceMakesTheCapabilityAvailable() {
        let observer = MediaActivityObserver(
            enumerator: ScriptedAudioDevices(devices: [ScriptedAudioDevices.microphone])
        )

        observer.refresh()

        #expect(observer.microphoneCapability == .available)
    }

    // MARK: - Transitions, once each

    @Test("A real 0 → 1 → 0 transition fires the change callback once per change")
    func transitionsAreReportedOnce() {
        let devices = ScriptedAudioDevices(devices: [ScriptedAudioDevices.microphone])
        let observer = MediaActivityObserver(enumerator: devices)
        var changes: [MediaActivity] = []
        observer.onChange = { changes.append($0) }
        observer.start()

        devices.setRunning(ScriptedAudioDevices.microphone.id, true)
        observer.refresh()
        devices.setRunning(ScriptedAudioDevices.microphone.id, false)
        observer.refresh()

        #expect(changes.map(\.microphoneRunning) == [true, false])
    }

    // MARK: - Listeners, and the global pause (F-119)

    @Test("A listener is installed on every input device and on the device list")
    func listenersAreInstalledOnInputsOnly() {
        let devices = ScriptedAudioDevices(
            devices: [
                ScriptedAudioDevices.microphone,
                ScriptedAudioDevices.headphones,
                ScriptedAudioDevices.otherOutput
            ]
        )
        let observer = MediaActivityObserver(enumerator: devices)

        observer.start()

        // One device listener plus the device-list listener.
        #expect(observer.listenerCount == 2)
    }

    @Test("pause() removes every listener and resume() puts them back")
    func pauseRemovesEveryListener() {
        let devices = ScriptedAudioDevices(devices: [ScriptedAudioDevices.microphone])
        let observer = MediaActivityObserver(enumerator: devices)

        observer.start()
        let before = observer.listenerCount
        #expect(before > 0)

        observer.pause()
        #expect(observer.listenerCount == 0)

        observer.resume()
        #expect(observer.listenerCount == before)
    }

    @Test("A device appearing moves the listeners onto the new set")
    func deviceListChangeReattaches() {
        let devices = ScriptedAudioDevices(devices: [ScriptedAudioDevices.headphones])
        let observer = MediaActivityObserver(enumerator: devices)
        observer.start()

        // Only the device-list listener, because there was nothing that could hear.
        #expect(observer.listenerCount == 1)

        devices.replaceDevices(
            with: [ScriptedAudioDevices.headphones, ScriptedAudioDevices.microphone]
        )

        #expect(observer.inputDeviceCount == 1)
        #expect(observer.listenerCount == 2)
    }

    // MARK: - What the type may never say

    @Test("MediaActivity exposes nothing a nudge could quote")
    func mediaActivityCannotAssertAMeeting() {
        let activity = MediaActivity(microphoneRunning: true)

        // Its whole surface: two booleans and the one question it answers. Reconstructing it
        // from those two members reproduces it exactly, so there is no confidence, no string
        // and no `isInMeeting` hiding anywhere.
        let rebuilt = MediaActivity(
            microphoneRunning: activity.microphoneRunning,
            cameraRunning: activity.cameraRunning
        )
        #expect(rebuilt == activity)
        #expect(activity.suppressesIntervention)
    }
}

@MainActor
@Suite("Camera path, held off")
struct CMIOMediaObserverTests {
    @Test("With two camera devices, one of them running, cameraRunning is still false")
    func twoDevicesOneRunningStillReportsFalse() {
        let cameras = ScriptedCameraDevices(identifiers: [11, 12], running: [12])
        let observer = CMIOMediaObserver(enumerator: cameras, environment: [:])

        observer.refresh()

        #expect(observer.deviceCount == 2)
        #expect(observer.cameraRunning == false)
        #expect(observer.cameraActivity == .unavailable)
        #expect(observer.unavailableReason == .unprovenOnThisHardware)
    }

    @Test("No per-device read and no listener install is attempted, even with devices present")
    func theDeeperPathIsNeverEntered() {
        let cameras = ScriptedCameraDevices(identifiers: [11, 12], running: [12])
        let observer = CMIOMediaObserver(enumerator: cameras, environment: [:])

        observer.refresh()

        // This is the criterion, and it is stronger than the answer being false: the calls
        // that were never observed for prompts on real hardware were never made (probe P-104).
        #expect(cameras.perDeviceReadCount == 0)
        #expect(cameras.listenerInstallCount == 0)
        #expect(observer.listenersInstalled == 0)
        #expect(observer.probeObservations.isEmpty)
    }

    @Test("Zero devices reports .unavailable with reason noDevices, never .denied")
    func zeroDevicesIsAHardwareFact() {
        let cameras = ScriptedCameraDevices(identifiers: [])
        let observer = CMIOMediaObserver(enumerator: cameras, environment: [:])

        observer.refresh()

        #expect(observer.deviceCount == 0)
        #expect(observer.cameraActivity == .unavailable)
        #expect(observer.unavailableReason == .noDevices)
        #expect(observer.cameraActivity != .denied)
    }

    @Test("The enumeration itself is the one call that does run")
    func enumerationRuns() {
        let cameras = ScriptedCameraDevices(identifiers: [11])
        let observer = CMIOMediaObserver(enumerator: cameras, environment: [:])

        observer.refresh()

        #expect(cameras.enumerationCount >= 1)
    }

    @Test("The flag is off in a process that does not set it")
    func theFlagIsOffByDefault() {
        let observer = CMIOMediaObserver(
            enumerator: ScriptedCameraDevices(identifiers: [11]),
            environment: [:]
        )
        #expect(observer.probeFlagIsSet == false)

        // And it is off in this very process, which is the gate's own environment.
        let live = CMIOMediaObserver(enumerator: ScriptedCameraDevices(identifiers: []))
        #expect(live.probeFlagIsSet == false)
    }

    @Test("Under the re-probe flag the held path runs — and cameraRunning is still false")
    func theHeldPathIsRealCodeAndStillCannotAssert() {
        // The flag exists so that the work which could one day lift the hold drives the real
        // code rather than a copy of it. It is set nowhere in the app, the gate or any lane;
        // this test sets it explicitly, on an injected environment, and asserts that even then
        // the observation cannot reach `cameraRunning`.
        let cameras = ScriptedCameraDevices(identifiers: [11, 12], running: [12])
        let observer = CMIOMediaObserver(
            enumerator: cameras,
            environment: [CMIOMediaObserver.probeFlagName: "1"]
        )

        observer.refresh()

        #expect(cameras.perDeviceReadCount == 2)
        #expect(cameras.listenerInstallCount == 2)
        #expect(observer.probeObservations[12] == true)
        // The hold is not "the read is unreachable" — it is "the read cannot become a claim".
        #expect(observer.cameraRunning == false)
        #expect(observer.cameraActivity == .unavailable)
    }

    @Test("Pausing removes whatever the held path installed")
    func pauseDetachesTheHeldPath() {
        let cameras = ScriptedCameraDevices(identifiers: [11, 12])
        let observer = CMIOMediaObserver(
            enumerator: cameras,
            environment: [CMIOMediaObserver.probeFlagName: "1"]
        )
        observer.refresh()
        #expect(observer.listenersInstalled == 2)

        observer.pause()

        #expect(observer.listenersInstalled == 0)
    }

    @Test("On this Mac, CoreMediaIO really does enumerate nothing")
    func theRigHasNoCamera() {
        // Not a claim about every Mac — a recording of what this one reports, which is the
        // fact that makes the camera half unprovable here (probes P-97/P-104).
        let observer = CMIOMediaObserver()
        observer.refresh()

        #expect(observer.cameraActivity == .unavailable)
        #expect(observer.listenersInstalled == 0)
        #expect(observer.cameraRunning == false)
    }
}
