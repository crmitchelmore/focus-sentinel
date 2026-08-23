import AppKit
import FocusCore
import Foundation
import Testing

@testable import FocusSensing

/// A notification centre that installs nothing and remembers everything.
///
/// It is what makes F-119's claim checkable headlessly: `liveObserverCount` here is the same
/// number the real centre reports and the same number the self-check prints, so a pause that
/// left an observer attached would fail in the suite rather than in production.
@MainActor
final class RecordingNotificationCentre: NotificationObserving {
    private(set) var handlers: [NotificationToken: @Sendable (ObservedNotification) -> Void] = [:]
    /// Every name ever subscribed to, in order, including ones later removed.
    private(set) var subscribed: [Notification.Name] = []
    private(set) var removedCount = 0

    var liveObserverCount: Int { handlers.count }

    @discardableResult
    func addObserver(
        for name: Notification.Name,
        handler: @escaping @Sendable (ObservedNotification) -> Void
    ) -> NotificationToken {
        let token = NotificationToken(name: name)
        handlers[token] = handler
        subscribed.append(name)
        return token
    }

    func removeObserver(_ token: NotificationToken) {
        guard handlers.removeValue(forKey: token) != nil else { return }
        removedCount += 1
    }

    func removeAllObservers() {
        removedCount += handlers.count
        handlers.removeAll()
    }

    /// Deliver a notification to every observer watching its name.
    func post(_ payload: ObservedNotification) {
        for (token, handler) in handlers where token.name == payload.name {
            handler(payload)
        }
    }

    func post(
        _ name: Notification.Name,
        bundleIdentifier: String? = nil,
        localizedName: String? = nil,
        pid: pid_t = 1
    ) {
        post(
            ObservedNotification(
                name: name,
                bundleIdentifier: bundleIdentifier,
                localizedName: localizedName,
                pid: pid
            )
        )
    }
}

/// A monotonic clock a test can wind forward after injecting it.
///
/// `FocusCore.TestClock` is a value type, so a copy handed to an observer can never be
/// advanced again from the outside. Dwell is the one quantity this suite has to move, so it
/// needs a reference. The lock is what lets it satisfy `MonotonicClock`'s `Sendable`
/// requirement honestly rather than by assertion.
final class AdvancingMonotonicClock: MonotonicClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Duration

    init(elapsed: Duration = .zero) {
        self.value = elapsed
    }

    var elapsed: Duration {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by delta: Duration) {
        precondition(delta >= .zero, "a monotonic clock must never move backwards")
        lock.lock()
        defer { lock.unlock() }
        value += delta
    }
}

/// A wall clock a test can move independently of the monotonic one — which is the whole point
/// of there being two protocols.
final class MovableDateProvider: DateProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(now: Date) {
        self.value = now
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func jump(by seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        value = value.addingTimeInterval(seconds)
    }
}

@MainActor
@Suite("Workspace activity observer")
struct WorkspaceActivityObserverTests {
    private static let origin = Date(timeIntervalSince1970: 1_767_225_600)

    private static func makeObserver(
        centre: RecordingNotificationCentre,
        clock: AdvancingMonotonicClock = AdvancingMonotonicClock(),
        dates: MovableDateProvider = MovableDateProvider(now: origin)
    ) -> WorkspaceActivityObserver {
        WorkspaceActivityObserver(centre: centre, dateProvider: dates, monotonicClock: clock)
    }

    // MARK: - The one trigger

    @Test("It subscribes to didActivateApplication and to nothing else")
    func subscribesToActivationOnly() {
        let centre = RecordingNotificationCentre()
        let observer = Self.makeObserver(centre: centre)

        observer.start()

        #expect(centre.subscribed == [NSWorkspace.didActivateApplicationNotification])
        #expect(observer.liveObserverCount == 1)
    }

    @Test("Starting twice does not subscribe twice")
    func startIsIdempotent() {
        let centre = RecordingNotificationCentre()
        let observer = Self.makeObserver(centre: centre)

        observer.start()
        observer.start()

        #expect(observer.liveObserverCount == 1)
        #expect(centre.liveObserverCount == 1)
    }

    @Test("An activation delivered through the centre becomes a FrontmostActivation")
    func activationArrivesThroughTheCentre() {
        let centre = RecordingNotificationCentre()
        let observer = Self.makeObserver(centre: centre)
        var seen: [FrontmostActivation] = []
        observer.onActivation = { seen.append($0) }
        observer.start()

        centre.post(
            NSWorkspace.didActivateApplicationNotification,
            bundleIdentifier: "com.apple.TextEdit",
            localizedName: "TextEdit",
            pid: 501
        )

        #expect(seen.count == 1)
        #expect(seen.first?.bundleIdentifier == "com.apple.TextEdit")
        #expect(seen.first?.pid == 501)
        #expect(observer.current?.subjectKey == "com.apple.TextEdit")
    }

    // MARK: - The debounce (probe P-82)

    @Test("A same-bundle re-activation does not reset dwell and counts as redundant")
    func sameBundleReactivationIsDebounced() {
        let centre = RecordingNotificationCentre()
        let clock = AdvancingMonotonicClock()
        let observer = Self.makeObserver(centre: centre, clock: clock)
        var seen: [FrontmostActivation] = []
        observer.onActivation = { seen.append($0) }
        observer.start()

        centre.post(NSWorkspace.didActivateApplicationNotification, bundleIdentifier: "com.a")
        clock.advance(by: .seconds(10))
        // The 22 ms full-screen stutter, in the shape probe P-82 measured it.
        centre.post(NSWorkspace.didActivateApplicationNotification, bundleIdentifier: "com.a")
        centre.post(NSWorkspace.didActivateApplicationNotification, bundleIdentifier: "com.a")
        clock.advance(by: .seconds(5))
        centre.post(NSWorkspace.didActivateApplicationNotification, bundleIdentifier: "com.b")

        #expect(seen.count == 2)
        #expect(observer.redundantActivations == 2)
        // Fifteen seconds, not five: the stutter did not restart the clock.
        #expect(seen.last?.dwellSeconds == 15)
    }

    @Test("The redundant counter starts at zero and only the stutter moves it")
    func redundantCounterOnlyCountsStutter() {
        let centre = RecordingNotificationCentre()
        let observer = Self.makeObserver(centre: centre)
        observer.start()

        #expect(observer.redundantActivations == 0)
        centre.post(NSWorkspace.didActivateApplicationNotification, bundleIdentifier: "com.a")
        centre.post(NSWorkspace.didActivateApplicationNotification, bundleIdentifier: "com.b")
        #expect(observer.redundantActivations == 0)
    }

    // MARK: - Two clocks

    @Test("Dwell is monotonic and a wall-clock jump does not touch it")
    func dwellIsMonotonic() {
        let centre = RecordingNotificationCentre()
        let clock = AdvancingMonotonicClock()
        let dates = MovableDateProvider(now: Self.origin)
        let observer = Self.makeObserver(centre: centre, clock: clock, dates: dates)
        var seen: [FrontmostActivation] = []
        observer.onActivation = { seen.append($0) }
        observer.start()

        centre.post(NSWorkspace.didActivateApplicationNotification, bundleIdentifier: "com.a")
        clock.advance(by: .seconds(30))
        // An NTP correction of the kind probe P-99 measured on this machine, only larger.
        dates.jump(by: -600)
        centre.post(NSWorkspace.didActivateApplicationNotification, bundleIdentifier: "com.b")

        #expect(seen.last?.dwellSeconds == 30)
    }

    @Test("The persisted instant is wall-clock, from the injected DateProvider")
    func timestampIsWallClock() {
        let centre = RecordingNotificationCentre()
        let dates = MovableDateProvider(now: Self.origin)
        let observer = Self.makeObserver(centre: centre, dates: dates)
        var seen: [FrontmostActivation] = []
        observer.onActivation = { seen.append($0) }
        observer.start()

        dates.jump(by: 120)
        centre.post(NSWorkspace.didActivateApplicationNotification, bundleIdentifier: "com.a")

        #expect(seen.first?.at == Self.origin.addingTimeInterval(120))
    }

    @Test("The first activation of a run reports no dwell, because it had no predecessor")
    func firstActivationHasNoDwell() {
        let centre = RecordingNotificationCentre()
        let observer = Self.makeObserver(centre: centre)
        var seen: [FrontmostActivation] = []
        observer.onActivation = { seen.append($0) }
        observer.start()

        centre.post(NSWorkspace.didActivateApplicationNotification, bundleIdentifier: "com.a")

        #expect(seen.first?.dwellSeconds == nil)
    }

    @Test("Seeding adopts the frontmost application without emitting an event")
    func seedingEmitsNothing() {
        let centre = RecordingNotificationCentre()
        let clock = AdvancingMonotonicClock()
        let observer = Self.makeObserver(centre: centre, clock: clock)
        var seen: [FrontmostActivation] = []
        observer.onActivation = { seen.append($0) }
        observer.start()

        observer.reseed(
            with: ObservedNotification(
                name: NSWorkspace.didActivateApplicationNotification,
                bundleIdentifier: "com.apple.finder",
                pid: 418
            )
        )

        #expect(seen.isEmpty)
        #expect(observer.current?.bundleIdentifier == "com.apple.finder")

        // And the seed starts a dwell, so the next real activation reports one.
        clock.advance(by: .seconds(7))
        centre.post(NSWorkspace.didActivateApplicationNotification, bundleIdentifier: "com.a")
        #expect(seen.first?.dwellSeconds == 7)
    }

    // MARK: - The nil bundle identifier (probe P-83)

    @Test("An activation with no bundle identifier is recorded, not dropped")
    func unbundledActivationIsRecorded() {
        let centre = RecordingNotificationCentre()
        let observer = Self.makeObserver(centre: centre)
        var seen: [FrontmostActivation] = []
        observer.onActivation = { seen.append($0) }
        observer.start()

        centre.post(
            NSWorkspace.didActivateApplicationNotification,
            bundleIdentifier: nil,
            localizedName: "npm exec something",
            pid: 4242
        )

        #expect(seen.count == 1)
        #expect(seen.first?.isUnbundled == true)
        #expect(seen.first?.subjectKey == "unbundled:npm exec something")
    }

    @Test("Two unbundled activations with different names are two different subjects")
    func unbundledSubjectsAreDistinct() {
        let centre = RecordingNotificationCentre()
        let observer = Self.makeObserver(centre: centre)
        var seen: [FrontmostActivation] = []
        observer.onActivation = { seen.append($0) }
        observer.start()

        centre.post(NSWorkspace.didActivateApplicationNotification, localizedName: "one")
        centre.post(NSWorkspace.didActivateApplicationNotification, localizedName: "two")

        #expect(seen.count == 2)
        #expect(observer.redundantActivations == 0)
    }

    @Test("An unbundled activation with no name at all still has a key")
    func unbundledWithoutNameStillHasAKey() {
        let centre = RecordingNotificationCentre()
        let observer = Self.makeObserver(centre: centre)
        observer.start()

        let accepted = observer.receive(
            ObservedNotification(name: NSWorkspace.didActivateApplicationNotification)
        )

        #expect(accepted?.subjectKey == "unbundled:unknown")
    }

    // MARK: - The global pause (F-119)

    @Test("pause() leaves no live observer and resume() restores the count")
    func pauseDetachesAndResumeReattaches() {
        let centre = RecordingNotificationCentre()
        let observer = Self.makeObserver(centre: centre)

        observer.start()
        let before = observer.liveObserverCount
        #expect(before > 0)

        observer.pause()
        #expect(observer.liveObserverCount == 0)
        #expect(centre.liveObserverCount == 0)

        observer.resume(seedingWith: nil)
        #expect(observer.liveObserverCount == before)
        #expect(centre.liveObserverCount == before)
    }

    @Test("A detached observer receives nothing at all")
    func pausedObserverIsInert() {
        let centre = RecordingNotificationCentre()
        let observer = Self.makeObserver(centre: centre)
        var seen: [FrontmostActivation] = []
        observer.onActivation = { seen.append($0) }

        observer.start()
        observer.pause()
        centre.post(NSWorkspace.didActivateApplicationNotification, bundleIdentifier: "com.a")

        #expect(seen.isEmpty)
    }

    @Test("Resuming with a seed adopts the application that became frontmost while detached")
    func resumeReseeds() {
        let centre = RecordingNotificationCentre()
        let observer = Self.makeObserver(centre: centre)
        observer.start()
        centre.post(NSWorkspace.didActivateApplicationNotification, bundleIdentifier: "com.a")
        observer.pause()

        observer.resume(
            seedingWith: ObservedNotification(
                name: NSWorkspace.didActivateApplicationNotification,
                bundleIdentifier: "com.b",
                pid: 9
            )
        )

        #expect(observer.current?.bundleIdentifier == "com.b")
    }

    // MARK: - The seam it satisfies

    @Test("Frontmost sensing reports itself available, because it needs no grant")
    func availabilityIsAvailable() {
        let observer = Self.makeObserver(centre: RecordingNotificationCentre())
        let seam: any ActivityObserving = observer
        #expect(seam.availability == .available)
    }
}

@MainActor
@Suite("Lifecycle observer")
struct LifecycleObserverTests {
    private static func makeObserver(
        workspace: RecordingNotificationCentre,
        distributed: RecordingNotificationCentre
    ) -> LifecycleObserver {
        LifecycleObserver(workspaceCentre: workspace, distributedCentre: distributed)
    }

    @Test("It subscribes to eight public names and the two undocumented ones")
    func subscribesToEveryInput() {
        let workspace = RecordingNotificationCentre()
        let distributed = RecordingNotificationCentre()
        let observer = Self.makeObserver(workspace: workspace, distributed: distributed)

        observer.start()

        #expect(workspace.liveObserverCount == 8)
        #expect(distributed.liveObserverCount == 2)
        #expect(observer.liveObserverCount == 10)
    }

    @Test("A loginwindow activation locks the screen; activating away unlocks it")
    func loginWindowActivationIsThePrimary() {
        let workspace = RecordingNotificationCentre()
        let distributed = RecordingNotificationCentre()
        let observer = Self.makeObserver(workspace: workspace, distributed: distributed)
        var changes: [SystemLifecycle] = []
        observer.onChange = { _, to in changes.append(to) }
        observer.start()

        workspace.post(
            NSWorkspace.didActivateApplicationNotification,
            bundleIdentifier: "com.apple.loginwindow"
        )
        #expect(observer.state == .screenLocked)

        workspace.post(
            NSWorkspace.didActivateApplicationNotification,
            bundleIdentifier: "com.apple.finder"
        )
        #expect(observer.state == .active)
        #expect(changes == [.screenLocked, .active])
    }

    @Test("The undocumented notifications corroborate and change no state")
    func distributedInputsOnlyCorroborate() {
        let workspace = RecordingNotificationCentre()
        let distributed = RecordingNotificationCentre()
        let observer = Self.makeObserver(workspace: workspace, distributed: distributed)
        var changes: [SystemLifecycle] = []
        observer.onChange = { _, to in changes.append(to) }
        observer.start()

        distributed.post(LifecycleObserver.screenIsLockedName)
        #expect(observer.state == .active)
        #expect(changes.isEmpty)
        #expect(observer.reduction.contradictions == 1)

        workspace.post(
            NSWorkspace.didActivateApplicationNotification,
            bundleIdentifier: "com.apple.loginwindow"
        )
        distributed.post(LifecycleObserver.screenIsLockedName)
        #expect(observer.state == .screenLocked)
        #expect(observer.reduction.corroborations == 1)
    }

    @Test("A screensDidSleep that never arrives changes nothing (probe P-88)")
    func silentInputsAreHarmless() {
        let workspace = RecordingNotificationCentre()
        let distributed = RecordingNotificationCentre()
        let observer = Self.makeObserver(workspace: workspace, distributed: distributed)
        observer.start()

        workspace.post(
            NSWorkspace.didActivateApplicationNotification,
            bundleIdentifier: "com.apple.loginwindow"
        )

        // The lock is detected by the public primary alone, exactly as it was on the rig.
        #expect(observer.state == .screenLocked)
        #expect(observer.reduction.conditions == [.screenLocked])
    }

    @Test("Each state carries its own pause cause, and only that one")
    func everyStateOwnsItsCause() {
        let workspace = RecordingNotificationCentre()
        let distributed = RecordingNotificationCentre()
        let observer = Self.makeObserver(workspace: workspace, distributed: distributed)
        observer.start()

        workspace.post(NSWorkspace.willSleepNotification)
        #expect(observer.state.pauseCause == .systemAsleep)

        workspace.post(NSWorkspace.didWakeNotification)
        #expect(observer.state == .active)
        #expect(observer.state.pauseCause == nil)
    }

    @Test("pause() detaches every observer on both centres and resume() restores them")
    func pauseDetachesBothCentres() {
        let workspace = RecordingNotificationCentre()
        let distributed = RecordingNotificationCentre()
        let observer = Self.makeObserver(workspace: workspace, distributed: distributed)

        observer.start()
        let before = observer.liveObserverCount

        observer.pause()
        #expect(observer.liveObserverCount == 0)
        #expect(workspace.liveObserverCount == 0)
        #expect(distributed.liveObserverCount == 0)

        observer.resume()
        #expect(observer.liveObserverCount == before)
    }

    @Test("A notification this observer does not read is ignored rather than mis-folded")
    func unknownNotificationIsIgnored() {
        let workspace = RecordingNotificationCentre()
        let distributed = RecordingNotificationCentre()
        let observer = Self.makeObserver(workspace: workspace, distributed: distributed)
        observer.start()

        observer.receive(ObservedNotification(name: Notification.Name("com.example.nothing")))

        #expect(observer.state == .active)
        #expect(observer.reduction == LifecycleReduction())
    }
}
