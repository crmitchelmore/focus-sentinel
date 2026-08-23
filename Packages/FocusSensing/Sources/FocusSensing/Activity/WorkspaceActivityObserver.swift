import AppKit
import FocusCore
import Foundation

/// One notification, reduced to the facts this app reads off it — and to nothing else.
///
/// ## Why a value type rather than the `Notification`
///
/// Two reasons, and both are load-bearing. `Notification` carries a `userInfo` dictionary of
/// `Any`, so it is not `Sendable` and cannot cross an isolation boundary at all under Swift 6:
/// handing one to a main-actor handler is a compile error, measured. And a dictionary of `Any`
/// is exactly the untyped escape hatch this epic spends its type system avoiding — a payload
/// that could carry a window title is a payload somebody will one day read a window title out
/// of. So the notification is decoded **inside the delivery block**, where the system put it,
/// down to four named fields, and nothing above that ever sees the dictionary.
///
/// The bundle identifier arrives on `NSWorkspaceApplicationKey` on the notification itself
/// (probe P-79): no window read, no `runningApplications` scan, no Accessibility call.
public struct ObservedNotification: Sendable, Equatable, Hashable {
    public let name: Notification.Name
    public let bundleIdentifier: String?
    public let localizedName: String?
    public let pid: pid_t?

    public init(
        name: Notification.Name,
        bundleIdentifier: String? = nil,
        localizedName: String? = nil,
        pid: pid_t? = nil
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.pid = pid
    }
}

/// A handle on one installed observer.
///
/// The token exists so that detaching is an operation on a **thing** rather than on a name: a
/// global pause has to remove every observer it installed and be able to say how many are
/// left, and "remove the observer for this name" cannot express that when two observers watch
/// one name — which is exactly what happens here, because the activation notification is read
/// both by the dwell timeline and by the lifecycle reducer.
public struct NotificationToken: Sendable, Hashable {
    public let id: UUID
    public let name: Notification.Name

    public init(id: UUID = UUID(), name: Notification.Name) {
        self.id = id
        self.name = name
    }
}

/// The seam between the app and a notification centre.
///
/// It exists so that F-119's proof is a **count** rather than a promise: `liveObserverCount`
/// is the number of observers actually installed, the self-check reports it before pause,
/// after pause and after resume, and a recording double asserts the same thing headlessly. A
/// pause implemented as `if paused { return }` inside each handler could not be counted, and
/// would leak the moment somebody added a handler (R-44).
///
/// `@MainActor` throughout: every observer is installed with `queue: .main`, so every handler
/// already runs there and nothing in this package needs a lock.
@MainActor
public protocol NotificationObserving: AnyObject {
    /// How many observers this centre currently has installed.
    var liveObserverCount: Int { get }

    /// Install one observer and get back the handle that detaches it.
    @discardableResult
    func addObserver(
        for name: Notification.Name,
        handler: @escaping @Sendable (ObservedNotification) -> Void
    ) -> NotificationToken

    /// Detach one observer. Detaching a token twice is harmless.
    func removeObserver(_ token: NotificationToken)

    /// Detach everything this centre installed.
    func removeAllObservers()
}

/// The production notification centre, over `NSWorkspace`'s or the distributed one.
///
/// One class serves both because `DistributedNotificationCenter` **is** a `NotificationCenter`;
/// what differs is which names arrive, not how they are subscribed to. The two factories below
/// are named rather than the initialiser being called directly, so that the one undocumented
/// surface this programme touches is visible at its call site.
@MainActor
public final class SystemNotificationCentre: NotificationObserving {
    private let centre: NotificationCenter
    private var installed: [NotificationToken: any NSObjectProtocol] = [:]

    public init(centre: NotificationCenter) {
        self.centre = centre
    }

    /// `NSWorkspace.shared.notificationCenter` — the public, documented source of every
    /// signal this epic relies on. Sixteen observers installed at zero grants, every
    /// activation delivered, no prompt (probe P-79).
    public static func workspace() -> SystemNotificationCentre {
        SystemNotificationCentre(centre: NSWorkspace.shared.notificationCenter)
    }

    /// `DistributedNotificationCenter.default()` — where `com.apple.screenIsLocked` and
    /// `com.apple.screenIsUnlocked` arrive.
    ///
    /// Those two are **undocumented**, and the Court permitted them only as a supplement.
    /// `LifecycleReducer` honours that structurally: the two inputs move a corroboration
    /// counter and change no state at all, so deleting them from any input list whatsoever
    /// leaves the outcome identical (probe P-87 for the public primary they supplement).
    public static func distributed() -> SystemNotificationCentre {
        SystemNotificationCentre(centre: DistributedNotificationCenter.default())
    }

    public var liveObserverCount: Int { installed.count }

    @discardableResult
    public func addObserver(
        for name: Notification.Name,
        handler: @escaping @Sendable (ObservedNotification) -> Void
    ) -> NotificationToken {
        let token = NotificationToken(name: name)
        let opaque = centre.addObserver(forName: name, object: nil, queue: .main) { note in
            // Decoded here, on the delivery queue, because `Notification` cannot cross an
            // isolation boundary — and because four named fields is the whole of what this
            // app is entitled to read off one.
            let application = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            handler(
                ObservedNotification(
                    name: note.name,
                    bundleIdentifier: application?.bundleIdentifier,
                    localizedName: application?.localizedName,
                    pid: application?.processIdentifier
                )
            )
        }
        installed[token] = opaque
        return token
    }

    public func removeObserver(_ token: NotificationToken) {
        guard let opaque = installed.removeValue(forKey: token) else { return }
        centre.removeObserver(opaque)
    }

    public func removeAllObservers() {
        for opaque in installed.values {
            centre.removeObserver(opaque)
        }
        installed.removeAll()
    }

    deinit {
        // `installed` is main-actor state and `deinit` is not; the observers are owned by the
        // centre object being torn down, so the system releases them with it. Detaching
        // explicitly is `removeAllObservers()`, which pause() calls.
    }
}

/// Frontmost-application sensing: activation-driven, bundle-debounced, monotonically timed.
///
/// ## One trigger, and it is the cheapest one there is
///
/// `didActivateApplicationNotification` and nothing else. **Not** `didLaunch`, which arrives
/// 75–90 ms later and does not fire at all for an application that was already running; **not**
/// `didDeactivate`, which probe P-80 measured arriving *after* the activation it corresponds
/// to; and not a poll. At the moment the activation is delivered,
/// `NSWorkspace.frontmostApplication` already agrees with it, on every event of every measured
/// run — so the handler may read frontmost state synchronously and never has to wait for a
/// second signal.
///
/// ## Debounced on identity, because the substrate stutters
///
/// Entering full screen produced **activate → deactivate → activate → deactivate for one
/// bundle identifier inside 22 ms** (probe P-82). A re-activation of the application that is
/// already current is therefore not a new dwell: it does not reset the clock, it emits no
/// event, and it increments `redundantActivations`, which the self-check reports so that the
/// stutter is visible rather than merely absorbed.
///
/// ## Two clocks, and they cannot be confused
///
/// Dwell is **monotonic**, from the injected `MonotonicClock`, because it is a duration inside
/// one process and the wall clock moves when NTP corrects it — 2.96 s of drift over 8.55 days
/// was measured on this very machine (probe P-99). The event's `at` is **wall-clock**, from the
/// injected `DateProvider`, because it is persisted and has to mean something to a person
/// reading a timeline tomorrow. The two protocols return different types, so a call site
/// cannot substitute one for the other.
///
/// ## A process with no bundle identifier is recorded, never dropped
///
/// Six of ninety-two running processes had none (probe P-83) — though **none** of the
/// `.regular` ones did, so anything that can actually be frontmost has one. The observation is
/// still filed, under `unbundled:<name>`, because a dropped event is a hole in the timeline;
/// it is never used as a rule subject, because a rule keyed on a display name is not a rule.
@MainActor
public final class WorkspaceActivityObserver: ActivityObserving {
    private let centre: any NotificationObserving
    private let dateProvider: any DateProvider
    private let monotonicClock: any MonotonicClock
    private let stream: AsyncStream<ActivityEventValue>
    private let continuation: AsyncStream<ActivityEventValue>.Continuation

    private var tokens: [NotificationToken] = []
    /// The monotonic reading at the last **accepted** activation, which is what dwell is
    /// measured from. `nil` until the first one, because the first activation of a run has no
    /// predecessor to have dwelt anywhere.
    private var dwellOrigin: Duration?

    /// The application currently frontmost, as far as this observer knows.
    public private(set) var current: FrontmostActivation?

    /// How many activations named the application that was already current (probe P-82).
    public private(set) var redundantActivations = 0

    /// What to do with an accepted activation. `SensingHost` puts the sensitivity gate on the
    /// other end of this, which is why the observer itself has no opinion about which
    /// applications may be looked at more closely: it produces observations, and clearance is
    /// somebody else's job and a different type.
    public var onActivation: ((FrontmostActivation) -> Void)?

    public init(
        centre: any NotificationObserving,
        dateProvider: any DateProvider,
        monotonicClock: any MonotonicClock
    ) {
        self.centre = centre
        self.dateProvider = dateProvider
        self.monotonicClock = monotonicClock
        // Bounded on purpose. The stream is a convenience for anything that wants to consume
        // observations as a sequence; a consumer that stops reading must not be able to grow
        // the app's memory without limit, and the store is the durable record either way.
        var madeContinuation: AsyncStream<ActivityEventValue>.Continuation!
        self.stream = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { madeContinuation = $0 }
        self.continuation = madeContinuation
    }

    // MARK: - Attaching and detaching (F-119)

    /// How many notification observers this object currently has installed.
    ///
    /// The gateable half of the global pause: `n > 0 → 0 → n` across `pause()` and `resume()`,
    /// asserted in-process at zero grants by the self-check and headlessly by a recording
    /// double.
    public var liveObserverCount: Int { tokens.count }

    /// Install the one observer this type needs.
    ///
    /// Idempotent: calling it twice does not subscribe twice, because a doubled subscription
    /// would double every dwell figure and be invisible in the count.
    public func start() {
        guard tokens.isEmpty else { return }
        let token = centre.addObserver(
            for: NSWorkspace.didActivateApplicationNotification
        ) { [weak self] payload in
            MainActor.assumeIsolated {
                // Explicitly discarded: `receive` hands the accepted activation back for a
                // test to assert on, and a debounced one back as `nil`. Neither is of any
                // use to the notification centre.
                _ = self?.receive(payload)
            }
        }
        tokens.append(token)
    }

    /// Detach. A pause that leaves an observer attached is not a pause (R-44).
    public func stop() {
        for token in tokens {
            centre.removeObserver(token)
        }
        tokens.removeAll()
    }

    /// F-119's switch, on this observer.
    public func pause() {
        stop()
    }

    /// Re-attach and re-seed. The re-seed matters: while the observers were detached the
    /// frontmost application may have changed several times, and coming back believing the
    /// old one is still current would produce one wrong dwell figure and one missing event.
    public func resume(seedingWith seed: ObservedNotification?) {
        start()
        if let seed { reseed(with: seed) }
    }

    // MARK: - Seeding

    /// Adopt the frontmost application as the current one **without** emitting an event or
    /// starting a dwell.
    ///
    /// Read once at start-up, and once more on resume from a pause. Never polled: the whole
    /// point of R-34 is that activation is a push, and a poll beside it would be a second,
    /// disagreeing source of the same fact.
    public func reseed(with payload: ObservedNotification) {
        current = activation(from: payload, dwellSeconds: nil)
        dwellOrigin = monotonicClock.elapsed
    }

    /// The frontmost application right now, as a payload this observer can be seeded with.
    ///
    /// `NSWorkspace.frontmostApplication` and nothing else — no window read, no Accessibility
    /// call, no `runningApplications` scan.
    public static func frontmostPayload() -> ObservedNotification? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        return ObservedNotification(
            name: NSWorkspace.didActivateApplicationNotification,
            bundleIdentifier: application.bundleIdentifier,
            localizedName: application.localizedName,
            pid: application.processIdentifier
        )
    }

    // MARK: - The handler

    /// Fold one delivered notification in. Internal to the type in production and the whole
    /// surface a test needs: the debounce, the dwell arithmetic and the `nil`-identifier
    /// fallback are all here, and none of them needs a real notification centre to exercise.
    @discardableResult
    public func receive(_ payload: ObservedNotification) -> FrontmostActivation? {
        let candidate = activation(from: payload, dwellSeconds: nil)

        if let current, current.isSameSubject(as: candidate) {
            // Not a new dwell. The clock is untouched, no event is emitted, and the stutter
            // is counted so that it is visible in the self-check rather than merely absorbed.
            redundantActivations += 1
            return nil
        }

        let now = monotonicClock.elapsed
        let dwellSeconds = dwellOrigin.map { Self.seconds(in: now - $0) }
        let accepted = activation(from: payload, dwellSeconds: dwellSeconds)

        current = accepted
        dwellOrigin = now

        continuation.yield(
            ActivityEventValue(
                at: accepted.at,
                kind: .frontmostApplicationChanged,
                bundleIdentifier: accepted.subjectKey,
                detail: nil
            )
        )
        onActivation?(accepted)
        return accepted
    }

    private func activation(
        from payload: ObservedNotification,
        dwellSeconds: Double?
    ) -> FrontmostActivation {
        FrontmostActivation(
            bundleIdentifier: payload.bundleIdentifier,
            localizedName: payload.localizedName,
            pid: payload.pid ?? 0,
            at: dateProvider.now,
            dwellSeconds: dwellSeconds
        )
    }

    /// `Duration` as a `Double` of seconds. The one place the two meet in this file.
    private static func seconds(in duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    // MARK: - ActivityObserving

    /// Frontmost sensing needs no grant of any kind and was measured working from a bundle
    /// holding no TCC row at all (probe P-79), so there is no state in which this source is
    /// unavailable for a reason the user could act on.
    public nonisolated var availability: ObservationAvailability { .available }

    /// The observation stream, for a consumer that wants a sequence rather than a callback.
    ///
    /// One stream per observer, created in `init` and finished when the object goes away.
    /// `SensingHost` uses `onActivation` instead, because it has to run the sensitivity gate
    /// **before** anything deeper looks at the activation and a callback is where that
    /// ordering is legible.
    public nonisolated func events() -> AsyncStream<ActivityEventValue> { stream }
}
