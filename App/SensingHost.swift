import AppKit
import FocusCore
import FocusSensing
import Foundation
import Observation
import SwiftData
import os

/// The observer graph: everything that watches the Mac, owned in one place, with the privacy
/// gate wired **in front of** every deeper reader.
///
/// ## The ordering is enforced by the type system, not by this file
///
/// `WindowMetadataReader`, `DisplayGeometryReader` and `PresentationReader` all take a
/// `ClearedActivation`, and the only thing in the programme that can produce one is
/// `SensitivityGate`. So the pipeline below **could not** be written in the wrong order: a
/// deeper read of a sensitive application does not compile. What this file adds is the
/// behaviour on the other branch — a suppressed activation still writes one event carrying the
/// bundle identifier and nothing else, because the person is entitled to see that the app
/// noticed and stood down.
///
/// ## The global pause detaches, it does not check a flag
///
/// A pause implemented as `if paused { return }` inside each handler is a pause that leaks the
/// moment somebody adds a handler. `pause()` removes **every** notification observer token,
/// invalidates the corroboration tick, and removes every CoreAudio property listener;
/// `liveObserverCount` goes to zero and the self-check asserts `n → 0 → n` in-process at zero
/// grants. `resume()` re-installs them and re-seeds from one fresh read of each source, because
/// the world moved while nothing was watching.
///
/// ## Why there is a tick at all
///
/// Two of this epic's signals have no reliable notification.
/// `activeSpaceDidChangeNotification` **never fired** across four full-screen enter/exit
/// cycles, two bundle identifiers, and both a windowless and a windowed observer, while
/// activation notifications flowed to the same observers throughout (probe P-92). So the
/// contract is: re-evaluate on every accepted activation, **plus** a bounded corroboration
/// tick. Five seconds is affordable because a window-list read costs 0.296 ms at the median
/// (probe P-76), and the cold 2–4 ms first call is taken once at start-up by `warm()`.
///
/// This tick is the only periodic thing in the programme. It is **not** a session timer —
/// there is no timer object anywhere for that, and elapsed time is computed on demand from
/// `startedAt` and an injected clock.
@MainActor
@Observable
final class SensingHost {
    // MARK: - The graph

    private let activity: WorkspaceActivityObserver
    private let lifecycle: LifecycleObserver
    private let idle: IdleReader
    private let windows: WindowMetadataReader
    private let displays: DisplayGeometryReader
    private let presentation: PresentationReader
    private let media: MediaActivityObserver
    private let camera: CMIOMediaObserver
    private let capabilityProbe: PlatformCapabilityProbe

    private let events: ActivityEventStore
    private let sessions: SessionStore
    private let dateProvider: any DateProvider
    private let policy = SignalEscalationPolicy()
    private let logger = Logger(subsystem: FocusStore.bundleIdentifier, category: "SensingHost")

    // MARK: - State

    /// The sensitivity gate, rebuilt whenever the stored list changes.
    private(set) var gate: SensitivityGate

    /// The presentation-exclusion list. Seeds **empty**; only the person puts anything on it.
    private(set) var presentationExclusions: Set<String>

    /// The five injected settings. Changing them re-reads rather than restarting the graph.
    private(set) var settings: SensingSettingsValue

    /// What the app currently believes about all twelve capabilities.
    private(set) var capabilities: CapabilityMatrix

    /// The last state each observer reported, kept so that an event is written **once per
    /// transition** rather than once per tick.
    private(set) var lifecycleState: SystemLifecycle = .active
    private(set) var mediaActivity: MediaActivity = .idle
    private(set) var presentationState: PresentationState = .notPresenting
    private(set) var currentDisplay: DisplayGeometry?
    private(set) var isIdle = false

    /// The last cascade the capability matrix permitted, cheapest tier first. In v1 it is two
    /// tiers and stops: the two Accessibility tiers report `.notRequested` until e07 changes a
    /// capability probe and nothing else.
    private(set) var cascade: [SignalTier] = []

    /// Whether the graph is attached right now.
    private(set) var isRunning = false

    /// The corroboration tick, held so that `pause()` can invalidate it. Nothing else in this
    /// programme owns a repeating timer.
    private var tick: Timer?

    /// Whether the sensitivity gate currently holds a session pause, so that leaving the
    /// sensitive application lifts **that** cause and no other.
    private var holdsSensitivePause = false

    init(
        events: ActivityEventStore,
        sessions: SessionStore,
        settings: SensingSettingsValue,
        gate: SensitivityGate,
        presentationExclusions: Set<String> = [],
        dateProvider: any DateProvider,
        monotonicClock: any MonotonicClock,
        workspaceCentre: any NotificationObserving = SystemNotificationCentre.workspace(),
        distributedCentre: any NotificationObserving = SystemNotificationCentre.distributed(),
        windows: WindowMetadataReader = WindowMetadataReader(),
        displays: DisplayGeometryReader = DisplayGeometryReader(),
        presentation: PresentationReader = PresentationReader(),
        media: MediaActivityObserver = MediaActivityObserver(),
        camera: CMIOMediaObserver = CMIOMediaObserver(),
        capabilityProbe: PlatformCapabilityProbe = PlatformCapabilityProbe()
    ) {
        self.events = events
        self.sessions = sessions
        self.settings = settings
        self.gate = gate
        self.presentationExclusions = presentationExclusions
        self.dateProvider = dateProvider
        self.windows = windows
        self.displays = displays
        self.presentation = presentation
        self.media = media
        self.camera = camera
        self.capabilityProbe = capabilityProbe

        self.activity = WorkspaceActivityObserver(
            centre: workspaceCentre,
            dateProvider: dateProvider,
            monotonicClock: monotonicClock
        )
        self.lifecycle = LifecycleObserver(
            workspaceCentre: workspaceCentre,
            distributedCentre: distributedCentre
        )
        self.idle = IdleReader(thresholdSeconds: settings.idleThresholdInterval)
        self.capabilities = CapabilityMatrix.unobserved(at: dateProvider.now)

        activity.onActivation = { [weak self] activation in
            self?.receive(activation)
        }
        lifecycle.onChange = { [weak self] _, to in
            self?.lifecycleChanged(to: to)
        }
        media.onChange = { [weak self] activity in
            self?.mediaChanged(to: activity)
        }
    }

    // MARK: - Lifecycle

    /// Attach everything, unless the person has the switch off.
    ///
    /// A launch with sensing paused attaches **nothing**: the switch is a detachment, and
    /// attaching-then-detaching at start-up would put one activation in the timeline that the
    /// person had asked not to be recorded.
    func start() {
        refreshCapabilities()
        guard !settings.sensingPaused else {
            isRunning = false
            return
        }
        attach()
    }

    private func attach() {
        guard !isRunning else { return }

        // The cold first call, taken here rather than inside the first decision (probe P-76).
        windows.warm()

        activity.start()
        lifecycle.start()
        media.start()
        camera.refresh()

        if let seed = WorkspaceActivityObserver.frontmostPayload() {
            activity.reseed(with: seed)
        }

        startTick()
        isRunning = true
        refreshCascade()
    }

    /// F-119's switch, off.
    ///
    /// Every observer token removed, the tick invalidated, every CoreAudio listener removed —
    /// and the session told **why** it stopped, so the timeline says so.
    func pause() {
        guard isRunning else { return }

        activity.pause()
        lifecycle.pause()
        media.pause()
        camera.pause()
        stopTick()
        isRunning = false

        record(kind: .sensingPaused, detail: .tokens([.observersDetached]))
        applyToSession(.paused(cause: .globalPause))
    }

    /// F-119's switch, on.
    ///
    /// Re-installs everything and re-seeds from one fresh read of each source, then lifts
    /// **its own** cause and no other — so switching sensing back on can never clear a pause
    /// the user or the screen lock owns.
    func resume() {
        guard !isRunning else { return }

        idle.forgetTransitions()
        attach()
        refreshCapabilities()
        sample()

        record(kind: .sensingResumed, detail: .tokens([.observersAttached]))
        applyToSession(.resumed(cause: .globalPause))
    }

    /// Detach without touching the session. Used at termination, where a pause event would be
    /// a row about the app closing rather than about the person's day.
    func stop() {
        activity.stop()
        lifecycle.stop()
        media.pause()
        camera.pause()
        stopTick()
        isRunning = false
    }

    // MARK: - What the self-check reports

    /// Every notification observer this graph currently holds. `n > 0 → 0 → n` across pause and
    /// resume, asserted in-process at zero grants.
    var liveObserverCount: Int {
        activity.liveObserverCount + lifecycle.liveObserverCount
    }

    /// How many activations named the application that was already current (probe P-82).
    var redundantActivations: Int { activity.redundantActivations }

    /// Every CoreAudio listener installed. Zero after `pause()`.
    var audioListenerCount: Int { media.listenerCount }

    /// **Zero on every rig, camera or not.** The assertion is that the held camera path was
    /// never entered, rather than an assertion about a hardware accident (probes P-97/P-104).
    var cameraListenersInstalled: Int { camera.listenersInstalled }

    var cameraDeviceCount: Int { camera.deviceCount }

    var cameraUnavailableReason: CameraUnavailableReason { camera.unavailableReason }

    var audioInputDeviceCount: Int { media.inputDeviceCount }

    var audioOutputDeviceCount: Int { media.outputDeviceCount }

    /// The current idle reading, both sources, without disturbing the transition edges.
    var idleReading: IdleReading { idle.read() }

    /// The seven keys the window reader decodes, and the assertion that none of them names a
    /// window.
    var windowDecodedKeys: [String] { WindowMetadataReader.decodedKeys }

    var windowDecodedKeysAreTitleFree: Bool { WindowMetadataReader.decodedKeysAreTitleFree }

    /// The current on-screen window count, read through the gate like everything else. `nil`
    /// when the frontmost application is one the app has stood down from.
    func currentWindowCount() -> Int? {
        guard let cleared = clearedFrontmost() else { return nil }
        return windows.windows(for: cleared).count
    }

    /// The presentation quorum's three inputs as they stand, for the self-check and the
    /// evidence lane to record — including when the verdict is false, because a surface that
    /// only showed its working when it said yes would be showing half of it.
    func currentPresentationSignals() -> PresentationSignals? {
        guard let cleared = clearedFrontmost() else { return nil }
        return presentation.read(
            for: cleared,
            windows: windows.windows(for: cleared),
            screens: displays.screens()
        )
    }

    /// The frontmost application, if the gate cleared it. `nil` is the honest answer for a
    /// sensitive application: there is nothing deeper to say about it, on purpose.
    private func clearedFrontmost() -> ClearedActivation? {
        guard let current = activity.current else { return nil }
        return gate.evaluate(current).clearedActivation
    }

    // MARK: - Settings and the lists

    /// Adopt new settings. Re-reads rather than restarting: the threshold and the tick are
    /// values the graph consults, not things it was built around.
    func update(settings: SensingSettingsValue) {
        let tickChanged = settings.corroborationTickSeconds != self.settings.corroborationTickSeconds
        self.settings = settings
        idle.thresholdSeconds = settings.idleThresholdInterval
        if tickChanged, isRunning { startTick() }
    }

    func update(gate: SensitivityGate, presentationExclusions: Set<String>) {
        self.gate = gate
        self.presentationExclusions = presentationExclusions
    }

    // MARK: - The capability matrix (F-126)

    /// Re-probe, and write one `capabilityChanged` row per capability that actually moved.
    ///
    /// Called at start-up, on wake, and on resume from a global pause — **never on a timer, and
    /// never by asking**. In this epic it could not ask even by accident: every prompting API is
    /// banned from the shipping graph by lint.
    func refreshCapabilities() {
        let now = dateProvider.now
        let probed = capabilityProbe.probeOnMainActor(at: now)

        var updated = capabilities
        for capability in Capability.allCases {
            let before = updated.state(of: capability)
            let after = probed.state(of: capability)
            updated = updated.recording(capability, as: after, at: now)
            guard updated.state(of: capability) != before else { continue }
            record(
                kind: .capabilityChanged,
                detail: .tokens([.forCapabilityState(updated.state(of: capability))])
            )
        }
        capabilities = updated
        refreshCascade()
    }

    private func refreshCascade() {
        cascade = policy.availableCascade(capabilities: capabilities)
    }

    // MARK: - The activation pipeline

    /// One accepted activation, taken through the gate and then — only then — through the
    /// cascade the capability matrix permits.
    private func receive(_ activation: FrontmostActivation) {
        switch gate.evaluate(activation) {
        case .suppressed(let reason):
            suppress(activation, reason: reason)

        case .cleared(let cleared):
            lookDeeper(at: cleared, activation: activation)
        }
    }

    /// The frontmost application is on a list, so nothing deeper is read.
    ///
    /// One event, carrying the bundle identifier and nothing else. Nothing here was inferred
    /// from what is on the screen: "is this banking?" was answered by an identifier being on a
    /// list, and there is no capability in this epic that could answer it any other way.
    private func suppress(_ activation: FrontmostActivation, reason: SensitiveReason) {
        record(
            kind: .sensitiveAppSuppressed,
            bundleID: activation.bundleIdentifier,
            detail: .tokens([reason == .unbundled ? .unbundled : .sensitiveApp]),
            at: activation.at
        )

        guard !holdsSensitivePause else { return }
        holdsSensitivePause = true
        applyToSession(.paused(cause: .sensitiveApp))
    }

    /// The cascade, cheapest tier first, on an activation that has passed the gate.
    private func lookDeeper(at cleared: ClearedActivation, activation: FrontmostActivation) {
        // Leaving a sensitive application lifts **that** cause and no other: a user pause taken
        // while the password manager was forward survives.
        if holdsSensitivePause {
            holdsSensitivePause = false
            applyToSession(.resumed(cause: .sensitiveApp))
        }

        var tokens: [DetailToken] = []
        var displayID: Int?

        // Tier 1 — the bundle identifier, off the notification itself. Free, and always
        // available.
        if activation.isUnbundled { tokens.append(.unbundled) }

        // Tier 2 — window metadata, if the matrix says the capability is there. This is the
        // policy being consumed rather than decorated: a rig where the window list answered
        // nothing would take the frontmost identifier and stop.
        if cascade.contains(.windowMetadata) {
            let onScreen = windows.windows(for: cleared)
            let screens = displays.screens()

            let display = DisplayMapper.display(
                quartzBounds: onScreen.applicationWindows(of: cleared.pid).first?.bounds ?? .zero,
                screens: screens
            )
            displayID = display?.displayID
            if let display {
                tokens.append(display.isPrimary ? .primaryDisplay : .secondaryDisplay)
                noteDisplayChange(to: display)
            }

            let state = presentation.read(
                for: cleared,
                windows: onScreen,
                screens: screens,
                isUserExcluded: presentationExclusions.contains(cleared.bundleIdentifier)
            )
            tokens.append(state.isPresenting ? .fullScreen : .windowed)
            if state.isUserExcluded { tokens.append(.presentationExcluded) }
            notePresentationChange(to: state)
        }

        record(
            kind: .frontmostApplicationChanged,
            bundleID: activation.subjectKey,
            detail: tokens.isEmpty ? .empty : .tokens(tokens),
            dwellSeconds: activation.dwellSeconds,
            displayID: displayID,
            at: activation.at
        )
    }

    // MARK: - The corroboration tick

    private func startTick() {
        stopTick()
        // The person's figure, clamped to a second: the stored value is theirs, but a tick of
        // zero would be a spin and is not honoured literally.
        let interval = TimeInterval(max(1, settings.corroborationTickSeconds))
        tick = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            // The timer fires on the main run loop, which is this actor's queue. The hop is
            // `assumeIsolated` rather than a `Task`, so a tick cannot be delivered after
            // `pause()` has invalidated the timer that scheduled it.
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    private func stopTick() {
        tick?.invalidate()
        tick = nil
    }

    /// One corroboration pass: the idle pair, the media state, and — through the gate — the
    /// display and presentation state of whatever is frontmost.
    func sample() {
        sampleIdle()
        _ = media.refresh()

        guard let current = activity.current, let cleared = gate.evaluate(current).clearedActivation
        else { return }

        let onScreen = windows.windows(for: cleared)
        let screens = displays.screens()

        if let display = DisplayMapper.display(
            quartzBounds: onScreen.applicationWindows(of: cleared.pid).first?.bounds ?? .zero,
            screens: screens
        ) {
            noteDisplayChange(to: display)
        }

        notePresentationChange(
            to: presentation.read(
                for: cleared,
                windows: onScreen,
                screens: screens,
                isUserExcluded: presentationExclusions.contains(cleared.bundleIdentifier)
            )
        )
    }

    // MARK: - Transitions, once each

    private func sampleIdle() {
        let sample = idle.sample()
        isIdle = sample.isIdle

        if let transition = sample.idleTransition {
            record(
                kind: transition == .becameIdle ? .userIdle : .userActive,
                detail: .measurement(.hardwareIdleSeconds, Int(sample.reading.hardwareSeconds))
            )
        }

        // Written **once per transition**, so a timeline that looks strange later has an
        // explanation in it rather than a mystery. The known limitation is stated in Settings:
        // a person working over Screen Sharing produces only synthetic events and will be
        // treated as idle.
        if sample.syntheticInputTransition == .began {
            record(
                kind: .syntheticInputObserved,
                detail: .tokens([.syntheticInput])
            )
        }
    }

    private func lifecycleChanged(to state: SystemLifecycle) {
        let previous = lifecycleState
        lifecycleState = state
        record(kind: .displayInactive, detail: .tokens([.forLifecycle(state)]))

        // Every non-active state pauses with **its own** cause, and the return to active
        // resumes with that same value and no other — so an unlock lifts the lock's pause and
        // leaves every other pause standing.
        if let cause = state.pauseCause {
            applyToSession(.paused(cause: cause))
        } else if let lifted = previous.pauseCause {
            applyToSession(.resumed(cause: lifted))
            refreshCapabilities()
        }
    }

    private func mediaChanged(to activity: MediaActivity) {
        mediaActivity = activity
        record(
            kind: .mediaActivityChanged,
            detail: .tokens([activity.microphoneRunning ? .micRunning : .micIdle, .cameraHeldOff])
        )
    }

    private func notePresentationChange(to state: PresentationState) {
        guard state.isPresenting != presentationState.isPresenting else {
            presentationState = state
            return
        }
        presentationState = state
        record(
            kind: .presentationChanged,
            detail: .tokens([state.isPresenting ? .fullScreen : .windowed])
        )
    }

    private func noteDisplayChange(to display: DisplayGeometry) {
        guard display.displayID != currentDisplay?.displayID else {
            currentDisplay = display
            return
        }
        currentDisplay = display
        record(
            kind: .displayChanged,
            detail: .tokens([display.isPrimary ? .primaryDisplay : .secondaryDisplay]),
            displayID: display.displayID
        )
    }

    // MARK: - Writing

    /// Append one row. **Normalised evidence only** — the argument is a `NormalisedDetail`,
    /// which has no `String` initialiser, so a window title or a URL is not forbidden here, it
    /// is unrepresentable.
    private func record(
        kind: ActivityEventKind,
        bundleID: String? = nil,
        detail: NormalisedDetail = .empty,
        dwellSeconds: Double? = nil,
        displayID: Int? = nil,
        at instant: Date? = nil
    ) {
        do {
            try events.append(
                kind: kind,
                bundleID: bundleID,
                detail: detail,
                sessionID: try sessions.openSession()?.id,
                dwellSeconds: dwellSeconds,
                displayID: displayID,
                at: instant
            )
        } catch {
            // The timeline is evidence, not the product: a store that will not take a row is a
            // thing to report, never a thing to crash the observer graph over.
            logger.error("the event store refused a row: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Offer an event to the session, if there is one open.
    ///
    /// A rejection is expected and is not a failure: `resumed(cause: .globalPause)` against a
    /// session that is not paused for the global switch is exactly the mismatched resume the
    /// machine exists to refuse, and refusing it is the feature.
    private func applyToSession(_ event: SessionEvent) {
        do {
            let transition = try sessions.apply(event)
            guard transition.value != nil else { return }
            record(kind: .sessionPhaseChanged, detail: .tokens([sessionToken(for: event)]))
        } catch SessionStoreError.noOpenSession {
            // Nothing to pause. Sensing runs whether or not a session does.
        } catch {
            logger.error("the session store refused an event: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func sessionToken(for event: SessionEvent) -> DetailToken {
        switch event {
        case .paused: .sessionPaused
        case .resumed: .sessionResumed
        default: .sessionPaused
        }
    }
}
