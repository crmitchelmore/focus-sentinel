import CoreAudio
import FocusCore
import Foundation

/// A CoreAudio device identifier, as a plain integer.
public typealias AudioDeviceIdentifier = UInt32

/// One audio device, reduced to the two facts that decide whether it may be read at all.
///
/// The **input** channel count is the whole ruling. Probe P-96 measured an *output* device
/// flipping to running merely because `say` was speaking: a person listening to music, not a
/// meeting, and precisely the false positive the Court warned about. So a device is read only
/// if `kAudioDevicePropertyStreamConfiguration` on `kAudioDevicePropertyScopeInput` reports at
/// least one channel — which, on the rig, is exactly one of the five.
public struct AudioDeviceSnapshot: Sendable, Equatable, Hashable {
    public let id: AudioDeviceIdentifier
    public let inputChannelCount: Int
    public let outputChannelCount: Int

    public init(id: AudioDeviceIdentifier, inputChannelCount: Int, outputChannelCount: Int) {
        self.id = id
        self.inputChannelCount = inputChannelCount
        self.outputChannelCount = outputChannelCount
    }

    /// Whether this device can hear anything. The only devices `IsRunningSomewhere` is read on.
    public var hasInput: Bool { inputChannelCount > 0 }
}

/// The seam between this app and CoreAudio.
///
/// Injectable because the two cases that matter cannot be produced on demand on a rig: a Mac
/// with **no** audio device at all, and an output-only device that is running. Both are
/// assertions this epic makes, so both are fixtures.
@MainActor
public protocol AudioDeviceEnumerating: AnyObject {
    /// Every device, with its input and output channel counts.
    func devices() -> [AudioDeviceSnapshot]

    /// `kAudioDevicePropertyDeviceIsRunningSomewhere` on one device.
    func isRunningSomewhere(_ device: AudioDeviceIdentifier) -> Bool

    /// Install a property listener on one device. `false` if the platform refused.
    @discardableResult
    func addListener(to device: AudioDeviceIdentifier, handler: @escaping @Sendable () -> Void) -> Bool

    /// Remove it. Removing one that is not installed is harmless.
    @discardableResult
    func removeListener(from device: AudioDeviceIdentifier) -> Bool

    /// Watch `kAudioHardwarePropertyDevices` so a device appearing or disappearing
    /// re-enumerates rather than being missed until the next restart.
    @discardableResult
    func addDeviceListListener(handler: @escaping @Sendable () -> Void) -> Bool

    @discardableResult
    func removeDeviceListListener() -> Bool

    /// How many listeners are installed right now, across every device and the device list.
    var installedListenerCount: Int { get }
}

/// The production CoreAudio enumerator.
///
/// ## Observing is grant-free, and that is measured rather than assumed
///
/// From a bundle holding **no TCC row of any kind**: five devices enumerated,
/// `AudioObjectGetPropertyData` status `0` for the list and for every `IsRunningSomewhere`
/// read, `AudioObjectHasProperty` true on all five, and `AudioObjectAddPropertyListenerBlock`
/// returning `0` on all five — the whole pass in 35.7 ms (probes P-94, P-104). Four independent
/// instruments say nothing asked the user anything: both TCC databases byte-identical before
/// and after, no `com.apple.TCC` log line naming the process, no authorisation surface on
/// screen before or after, and an unchanged on-screen window count (probe P-95).
///
/// **Observing is not opening.** Nothing here starts a capture, and the app declares no
/// microphone usage string, because declaring one for a capture it never performs would be a
/// claim it cannot honour.
@MainActor
public final class SystemAudioDeviceEnumerator: AudioDeviceEnumerating {
    /// The listener blocks, kept alive and kept identifiable so that each can be removed by
    /// the same block value it was installed with — CoreAudio matches on the block, so a
    /// re-created closure would not remove anything.
    private var deviceListeners: [AudioDeviceIdentifier: AudioObjectPropertyListenerBlock] = [:]
    private var deviceListListener: AudioObjectPropertyListenerBlock?

    private let queue = DispatchQueue(label: "com.chrismitchelmore.FocusSentinel.audio-observation")

    public init() {}

    // MARK: - Enumeration

    public func devices() -> [AudioDeviceSnapshot] {
        var address = Self.address(
            selector: kAudioHardwarePropertyDevices,
            scope: kAudioObjectPropertyScopeGlobal
        )
        var byteSize: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &byteSize
            ) == noErr,
            byteSize > 0
        else {
            return []
        }

        let count = Int(byteSize) / MemoryLayout<AudioObjectID>.size
        var identifiers = [AudioObjectID](repeating: 0, count: count)
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &byteSize, &identifiers
            ) == noErr
        else {
            return []
        }

        return identifiers.map { identifier in
            AudioDeviceSnapshot(
                id: identifier,
                inputChannelCount: Self.channelCount(of: identifier, scope: kAudioDevicePropertyScopeInput),
                outputChannelCount: Self.channelCount(of: identifier, scope: kAudioDevicePropertyScopeOutput)
            )
        }
    }

    public func isRunningSomewhere(_ device: AudioDeviceIdentifier) -> Bool {
        var address = Self.address(
            selector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            scope: kAudioObjectPropertyScopeGlobal
        )
        guard AudioObjectHasProperty(device, &address) else { return false }

        var running: UInt32 = 0
        var byteSize = UInt32(MemoryLayout<UInt32>.size)
        guard
            AudioObjectGetPropertyData(device, &address, 0, nil, &byteSize, &running) == noErr
        else {
            return false
        }
        return running != 0
    }

    // MARK: - Listeners

    @discardableResult
    public func addListener(
        to device: AudioDeviceIdentifier,
        handler: @escaping @Sendable () -> Void
    ) -> Bool {
        guard deviceListeners[device] == nil else { return true }
        var address = Self.address(
            selector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            scope: kAudioObjectPropertyScopeGlobal
        )
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        guard AudioObjectAddPropertyListenerBlock(device, &address, queue, block) == noErr else {
            return false
        }
        deviceListeners[device] = block
        return true
    }

    @discardableResult
    public func removeListener(from device: AudioDeviceIdentifier) -> Bool {
        guard let block = deviceListeners.removeValue(forKey: device) else { return false }
        var address = Self.address(
            selector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            scope: kAudioObjectPropertyScopeGlobal
        )
        return AudioObjectRemovePropertyListenerBlock(device, &address, queue, block) == noErr
    }

    @discardableResult
    public func addDeviceListListener(handler: @escaping @Sendable () -> Void) -> Bool {
        guard deviceListListener == nil else { return true }
        var address = Self.address(
            selector: kAudioHardwarePropertyDevices,
            scope: kAudioObjectPropertyScopeGlobal
        )
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        guard
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, queue, block
            ) == noErr
        else {
            return false
        }
        deviceListListener = block
        return true
    }

    @discardableResult
    public func removeDeviceListListener() -> Bool {
        guard let block = deviceListListener else { return false }
        deviceListListener = nil
        var address = Self.address(
            selector: kAudioHardwarePropertyDevices,
            scope: kAudioObjectPropertyScopeGlobal
        )
        return AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, queue, block
        ) == noErr
    }

    public var installedListenerCount: Int {
        deviceListeners.count + (deviceListListener == nil ? 0 : 1)
    }

    // MARK: - Plumbing

    private static func address(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// How many channels a device has in one scope.
    ///
    /// `kAudioDevicePropertyStreamConfiguration` returns an `AudioBufferList` whose buffers
    /// each carry a channel count; the total across them is the device's channel count in that
    /// scope. Measured on the rig: five devices, of which exactly one reported input channels
    /// (`Yeti Stereo Microphone`, two of them) — probe P-104.
    private static func channelCount(
        of device: AudioDeviceIdentifier,
        scope: AudioObjectPropertyScope
    ) -> Int {
        var address = Self.address(selector: kAudioDevicePropertyStreamConfiguration, scope: scope)
        var byteSize: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(device, &address, 0, nil, &byteSize) == noErr,
            byteSize >= UInt32(MemoryLayout<AudioBufferList>.size)
        else {
            return 0
        }

        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(byteSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }

        guard AudioObjectGetPropertyData(device, &address, 0, nil, &byteSize, storage) == noErr else {
            return 0
        }

        let list = UnsafeMutableAudioBufferListPointer(
            storage.assumingMemoryBound(to: AudioBufferList.self)
        )
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

/// Whether a microphone is running somewhere — **observed, never opened**, and read only on
/// devices that can hear.
///
/// ## What this may say, and what it may never say
///
/// `MediaActivity` has exactly `microphoneRunning` and `cameraRunning`, no `isInMeeting`, no
/// confidence and no string. The signal may **suppress** an intervention and can never
/// **assert** that a meeting is occurring, because the type has no member an assertion could
/// be built from. Cross-device false positives are expected — another Mac, an iPhone on the
/// same Continuity session, a background utility — and suppression is safe under that failure
/// mode where assertion would not be.
///
/// ## Zero devices is `.unavailable`, not `false`
///
/// A Mac with no audio input hardware has not told us the microphone is off; it has told us
/// there is nothing to ask. Reporting `false` there would let a consumer treat "we cannot know"
/// as "we know it is idle", which is the same mistake the camera half is held back for.
///
/// ## Pausing removes every listener
///
/// F-119's switch is not a boolean handlers consult. `pause()` removes every CoreAudio property
/// listener and the device-list listener, and `listenerCount` goes to zero — which is the
/// number the self-check reports and a test asserts.
@MainActor
public final class MediaActivityObserver {
    private let enumerator: any AudioDeviceEnumerating

    /// The devices as of the last enumeration, with their channel counts.
    public private(set) var devices: [AudioDeviceSnapshot] = []

    /// What the app currently believes. `cameraRunning` is pinned `false` (R-40).
    public private(set) var activity: MediaActivity = .idle

    /// Called when — and only when — the activity actually changes, so a caller writes one
    /// `mediaActivityChanged` row per transition rather than one per read.
    public var onChange: ((MediaActivity) -> Void)?

    public init(enumerator: any AudioDeviceEnumerating = SystemAudioDeviceEnumerator()) {
        self.enumerator = enumerator
    }

    // MARK: - What the matrix reports

    /// How many devices can hear. The self-check reports this and the output count separately,
    /// so the input-only rule is visible rather than merely claimed.
    public var inputDeviceCount: Int { devices.filter(\.hasInput).count }

    public var outputDeviceCount: Int { devices.filter { $0.outputChannelCount > 0 }.count }

    public var deviceCount: Int { devices.count }

    /// `.available` when there is a device to ask about, `.unavailable` when there is not.
    public var microphoneCapability: CapabilityState {
        devices.isEmpty ? .unavailable : .available
    }

    /// Every listener this observer has installed. Zero after `pause()`.
    public var listenerCount: Int { enumerator.installedListenerCount }

    // MARK: - Lifecycle

    /// Enumerate once, install a listener on every **input** device, and watch the device list.
    public func start() {
        refresh()
        attachListeners()
    }

    /// Re-enumerate and re-read. Called at start-up, on a device-list change, and on the
    /// corroboration tick.
    @discardableResult
    public func refresh() -> MediaActivity {
        devices = enumerator.devices()

        // Input devices only. An output device running is a person listening to something
        // (probe P-96), and treating that as a call would be the exact false positive the
        // Court warned about.
        let microphoneRunning = devices
            .filter(\.hasInput)
            .contains { enumerator.isRunningSomewhere($0.id) }

        let updated = MediaActivity(microphoneRunning: microphoneRunning, cameraRunning: false)
        guard updated != activity else { return activity }
        activity = updated
        onChange?(updated)
        return updated
    }

    /// Install a running-state listener on every input device, plus one on the device list.
    ///
    /// Observation rather than polling: every one of the five listener installs returned `0` at
    /// zero grants on the rig (probes P-94/P-104).
    public func attachListeners() {
        for device in devices where device.hasInput {
            enumerator.addListener(to: device.id) { [weak self] in
                MainActor.assumeIsolated { _ = self?.refresh() }
            }
        }
        enumerator.addDeviceListListener { [weak self] in
            MainActor.assumeIsolated { self?.reattach() }
        }
    }

    /// Remove every listener this observer installed.
    public func detachListeners() {
        for device in devices {
            enumerator.removeListener(from: device.id)
        }
        enumerator.removeDeviceListListener()
    }

    /// A device appeared or disappeared: re-enumerate, then move the listeners onto the new
    /// set. Leaving them on the old set would watch a device that is no longer there and miss
    /// one that is.
    public func reattach() {
        detachListeners()
        refresh()
        attachListeners()
    }

    /// F-119's switch. Every listener goes, and `listenerCount` is zero afterwards.
    public func pause() {
        detachListeners()
    }

    /// Re-install, and re-seed from **one fresh read** — the state may have changed several
    /// times while nothing was watching, and coming back believing the old answer would put a
    /// transition in the timeline at the wrong instant.
    public func resume() {
        refresh()
        attachListeners()
    }

    deinit {
        // Listener removal is main-actor work and `deinit` is not, so it cannot happen here.
        // Every owner detaches explicitly: `SensingHost` on pause and on tear-down, and the
        // suite asserts the count reaches zero rather than trusting a destructor to do it.
    }
}
