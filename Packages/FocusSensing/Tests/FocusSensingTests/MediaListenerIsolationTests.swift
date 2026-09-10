import FocusCore
import Foundation
import Testing

@testable import FocusSensing

/// The listener handlers, in a box that any thread can reach.
///
/// `AudioDeviceEnumerating` is `@MainActor`, so a double that conforms to it cannot hand its
/// handlers to a background queue from inside its own methods. CoreAudio has no such manners:
/// `AudioObjectAddPropertyListenerBlock` dispatches on the queue it was given, and for six days
/// that queue was a private serial one. This box is how a test gets to be that queue.
final class AudioListenerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var deviceHandlers: [AudioDeviceIdentifier: @Sendable () -> Void] = [:]
    private var listHandler: (@Sendable () -> Void)?

    func install(_ handler: @escaping @Sendable () -> Void, for device: AudioDeviceIdentifier) {
        lock.lock()
        defer { lock.unlock() }
        deviceHandlers[device] = handler
    }

    func remove(_ device: AudioDeviceIdentifier) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return deviceHandlers.removeValue(forKey: device) != nil
    }

    func installList(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        listHandler = handler
    }

    func removeList() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard listHandler != nil else { return false }
        listHandler = nil
        return true
    }

    func handler(for device: AudioDeviceIdentifier) -> (@Sendable () -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return deviceHandlers[device]
    }

    var deviceListHandler: (@Sendable () -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return listHandler
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return deviceHandlers.count + (listHandler == nil ? 0 : 1)
    }
}

/// An enumerator that hands its handlers out rather than calling them, so a test can deliver one
/// from a queue this app did not choose.
@MainActor
final class QueueChoosingAudioDevices: AudioDeviceEnumerating {
    let box = AudioListenerBox()
    private var snapshots: [AudioDeviceSnapshot]
    private var running: Set<AudioDeviceIdentifier>

    init(devices: [AudioDeviceSnapshot], running: Set<AudioDeviceIdentifier> = []) {
        self.snapshots = devices
        self.running = running
    }

    func devices() -> [AudioDeviceSnapshot] { snapshots }

    func isRunningSomewhere(_ device: AudioDeviceIdentifier) -> Bool { running.contains(device) }

    @discardableResult
    func addListener(
        to device: AudioDeviceIdentifier,
        handler: @escaping @Sendable () -> Void
    ) -> Bool {
        box.install(handler, for: device)
        return true
    }

    @discardableResult
    func removeListener(from device: AudioDeviceIdentifier) -> Bool { box.remove(device) }

    @discardableResult
    func addDeviceListListener(handler: @escaping @Sendable () -> Void) -> Bool {
        box.installList(handler)
        return true
    }

    @discardableResult
    func removeDeviceListListener() -> Bool { box.removeList() }

    var installedListenerCount: Int { box.count }

    /// Change the world without telling anybody. Delivery is the test's job here.
    func setRunning(_ device: AudioDeviceIdentifier, _ isRunning: Bool) {
        if isRunning { running.insert(device) } else { running.remove(device) }
    }

    func replaceDevices(with devices: [AudioDeviceSnapshot]) { snapshots = devices }

    static let microphone = AudioDeviceSnapshot(id: 102, inputChannelCount: 2, outputChannelCount: 0)
    static let secondMicrophone =
        AudioDeviceSnapshot(id: 103, inputChannelCount: 1, outputChannelCount: 0)
}

/// **A CoreAudio callback that arrives on the wrong queue must not kill the app** (focus-068).
///
/// `MediaActivityObserver.attachListeners()` wrapped each listener body in
/// `MainActor.assumeIsolated`, which calls `dispatch_assert_queue(main)` and **traps** anywhere
/// else. `SystemAudioDeviceEnumerator` registered those listeners on a private serial queue, so
/// the first microphone transition while the app was watching killed the process with SIGTRAP.
/// It did: the gate run of 2026-09-02 died at `MediaActivityObserver.swift:352`, Thread 12,
/// `_dispatch_assert_queue_fail <- swift_task_checkIsolated <- HALPropertyListener::Call`, and
/// took 177 `FocusHost` tests with it (focus-jg7).
///
/// Every test in this suite delivers the listener from `DispatchQueue.global()`. At the commit
/// before the repair each one does not fail — it **crashes the test process**, which is the
/// shape of the defect and the reason it survived six days of green gates: no test drove the
/// real enumerator, and every double called the handler on the main thread it was already on.
@MainActor
struct MediaListenerIsolationTests {
    /// Give the observer's main-queue work its turn, without asserting how many turns it takes.
    private func settle(until condition: @MainActor () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Deliver a handler from a background queue and wait for it to return.
    ///
    /// The wait is `await`ed rather than blocked on a semaphore: blocking the main thread here
    /// would stop the very queue the repair hops onto, and the test would be measuring its own
    /// harness.
    private func deliverOffMain(_ handler: (@Sendable () -> Void)?) async {
        #expect(handler != nil, "no listener was installed, so nothing was delivered")
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                handler?()
                continuation.resume()
            }
        }
    }

    @Test("a device running-state callback delivered off the main queue refreshes, and lives")
    func aBackgroundDeviceCallbackRefreshes() async throws {
        let enumerator = QueueChoosingAudioDevices(devices: [QueueChoosingAudioDevices.microphone])
        let observer = MediaActivityObserver(enumerator: enumerator)
        var changes: [MediaActivity] = []
        observer.onChange = { changes.append($0) }
        observer.start()

        #expect(observer.activity == .idle)
        #expect(observer.listenerCount == 2)

        // The world changes, and CoreAudio tells us about it from its own queue.
        enumerator.setRunning(QueueChoosingAudioDevices.microphone.id, true)
        await deliverOffMain(enumerator.box.handler(for: QueueChoosingAudioDevices.microphone.id))
        await settle { observer.activity.microphoneRunning }

        // Reaching this line at all is half the assertion: before the repair the process was
        // gone by now.
        #expect(observer.activity.microphoneRunning)
        #expect(changes.map(\.microphoneRunning) == [true])
    }

    @Test("a device-list callback delivered off the main queue re-attaches, and lives")
    func aBackgroundDeviceListCallbackReattaches() async throws {
        let enumerator = QueueChoosingAudioDevices(devices: [QueueChoosingAudioDevices.microphone])
        let observer = MediaActivityObserver(enumerator: enumerator)
        observer.start()
        #expect(observer.inputDeviceCount == 1)

        enumerator.replaceDevices(with: [
            QueueChoosingAudioDevices.microphone,
            QueueChoosingAudioDevices.secondMicrophone
        ])
        await deliverOffMain(enumerator.box.deviceListHandler)
        await settle { observer.inputDeviceCount == 2 }

        #expect(observer.inputDeviceCount == 2)
        // One per input device, plus the device-list listener: the re-attach really re-attached.
        #expect(observer.listenerCount == 3)
    }

    /// **The main-thread path is still the fast one**, which is the other half of the repair:
    /// the production enumerator now registers on `DispatchQueue.main`, so the ordinary delivery
    /// must still be synchronous. If it ever becomes a hop, a self-check that reads the activity
    /// immediately after a transition reads the previous answer.
    @Test("a callback delivered on the main queue is applied without a hop")
    func aMainQueueCallbackIsSynchronous() throws {
        let enumerator = QueueChoosingAudioDevices(devices: [QueueChoosingAudioDevices.microphone])
        let observer = MediaActivityObserver(enumerator: enumerator)
        observer.start()

        enumerator.setRunning(QueueChoosingAudioDevices.microphone.id, true)
        let handler = try #require(enumerator.box.handler(for: QueueChoosingAudioDevices.microphone.id))
        handler()

        #expect(observer.activity.microphoneRunning)
    }

    /// The production enumerator's own registration queue, named rather than inferred. This is
    /// the fact that makes `assumeIsolated` correct by construction in the shipping app, and the
    /// one a future edit would have to change in order to bring the crash back.
    @Test("the production audio enumerator registers its listeners on the main queue")
    func theProductionEnumeratorRegistersOnMain() {
        #expect(SystemAudioDeviceEnumerator.listenerQueue === DispatchQueue.main)
        #expect(SystemCameraDeviceEnumerator.listenerQueue === DispatchQueue.main)
    }
}
