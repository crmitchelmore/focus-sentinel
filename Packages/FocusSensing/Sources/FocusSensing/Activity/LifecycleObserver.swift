import AppKit
import FocusCore
import Foundation

/// Lock, sleep and session state — seven possibly-silent inputs, folded through a pure
/// reducer.
///
/// ## Every input may be silent, and several of them were
///
/// Measured across a real `pmset displaysleepnow` on macOS 26.5.2 (probe P-88):
/// `screensDidSleepNotification`, `screensDidWakeNotification`,
/// `sessionDidResignActiveNotification` and `sessionDidBecomeActiveNotification` **did not
/// fire at all**. An observer written as "when this notification arrives, do that" would
/// simply never have run. So this type subscribes to all of them, treats each as one input to
/// one typed state, and derives the state from `LifecycleReducer` — a pure function over a
/// list — rather than from any single arrival.
///
/// ## The primary is public, and it is the one that worked
///
/// What *was* observed, 1.5 ms before anything else: `didActivateApplication` with
/// `bundleIdentifier == "com.apple.loginwindow"`, with `frontmostApplication` already
/// agreeing (probe P-87). That is a public, documented API, and it is the trigger.
/// `menuBarOwningApplication` is **not** a substitute: it stayed on Finder throughout the
/// lock (probe P-89).
///
/// ## The undocumented pair supplements and cannot decide
///
/// `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` are subscribed and passed to the
/// reducer, where they move a corroboration counter and change no condition. The Court's
/// downgrade required "supplement, never the sole trigger"; because the two inputs are inert
/// with respect to state, deleting them from **any** input list leaves the outcome identical,
/// which is a property of the function rather than of the sequences somebody thought to test.
@MainActor
public final class LifecycleObserver {
    private let workspaceCentre: any NotificationObserving
    private let distributedCentre: any NotificationObserving

    private var workspaceTokens: [NotificationToken] = []
    private var distributedTokens: [NotificationToken] = []

    /// Everything the reducer has folded so far: the condition set, and how often the
    /// undocumented supplement agreed and disagreed.
    public private(set) var reduction: LifecycleReduction

    /// What the Mac is doing, as one typed value. Nothing else in the app reads the raw
    /// notifications.
    public var state: SystemLifecycle { reduction.state }

    /// Called when — and only when — the **condition set** actually changes.
    ///
    /// It reports the two whole reductions rather than the two collapsed states, because
    /// `SensingHost` turns them into `SessionEvent.paused(cause:)` and `resumed(cause:)`
    /// through `LifecycleReducer.sessionEvents(from:to:)`, and that arithmetic is a set
    /// difference. A collapsed `SystemLifecycle` cannot say what changed: a Mac that is both
    /// locked and asleep reports only `systemAsleep`, so a handler fed states alone pauses
    /// twice and resumes once and strands a cause on a Mac that has woken up (R-45).
    ///
    /// Firing on the *condition* set rather than on the collapsed state also means a change
    /// that the collapse hides — the displays sleeping while the screen is already locked —
    /// is delivered rather than swallowed. The two undocumented distributed inputs change no
    /// condition, so they still fire nothing at all, which is what makes deleting them from
    /// any input list leave behaviour identical.
    public var onChange: ((_ from: LifecycleReduction, _ to: LifecycleReduction) -> Void)?

    public init(
        workspaceCentre: any NotificationObserving,
        distributedCentre: any NotificationObserving,
        initial: LifecycleReduction = LifecycleReduction()
    ) {
        self.workspaceCentre = workspaceCentre
        self.distributedCentre = distributedCentre
        self.reduction = initial
    }

    // MARK: - The subscriptions

    /// The eight public workspace notifications this observer takes as inputs, each paired
    /// with the input it becomes.
    ///
    /// The activation entry is `nil` because its input depends on **which** application
    /// activated — that is the whole lock signal — and is built in `input(for:)`.
    public static var workspaceNotificationNames: [Notification.Name] {
        [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.willSleepNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.willPowerOffNotification
        ]
    }

    /// The two undocumented distributed names. Supplement only.
    public static let screenIsLockedName = Notification.Name("com.apple.screenIsLocked")
    public static let screenIsUnlockedName = Notification.Name("com.apple.screenIsUnlocked")

    public static var distributedNotificationNames: [Notification.Name] {
        [screenIsLockedName, screenIsUnlockedName]
    }

    /// Every observer this object has installed, across both centres.
    public var liveObserverCount: Int { workspaceTokens.count + distributedTokens.count }

    public func start() {
        guard workspaceTokens.isEmpty, distributedTokens.isEmpty else { return }

        for name in Self.workspaceNotificationNames {
            let token = workspaceCentre.addObserver(for: name) { [weak self] payload in
                MainActor.assumeIsolated { self?.receive(payload) }
            }
            workspaceTokens.append(token)
        }

        for name in Self.distributedNotificationNames {
            let token = distributedCentre.addObserver(for: name) { [weak self] payload in
                MainActor.assumeIsolated { self?.receive(payload) }
            }
            distributedTokens.append(token)
        }
    }

    public func stop() {
        for token in workspaceTokens { workspaceCentre.removeObserver(token) }
        for token in distributedTokens { distributedCentre.removeObserver(token) }
        workspaceTokens.removeAll()
        distributedTokens.removeAll()
    }

    public func pause() { stop() }

    public func resume() { start() }

    // MARK: - Folding

    /// Fold one delivered notification in, if it is one of the seven this observer takes.
    public func receive(_ payload: ObservedNotification) {
        guard let input = Self.input(for: payload) else { return }
        apply(input)
    }

    /// Fold one typed input in. The whole table is reachable from here with no notification
    /// centre at all, which is what makes `LifecycleReducerTests` headless.
    public func apply(_ input: LifecycleInput) {
        let before = reduction
        reduction = LifecycleReducer.step(input, into: reduction)
        // The condition set, not the collapsed state: `screensDidSleep` arriving while the
        // screen is already locked moves no state (lock is the more severe of the two) but it
        // is a pause cause the session must acquire, and its wake must lift that cause and no
        // other.
        guard before.conditions != reduction.conditions else { return }
        onChange?(before, reduction)
    }

    /// Which input a delivered notification is, or `nil` if it is not one this observer reads.
    public static func input(for payload: ObservedNotification) -> LifecycleInput? {
        switch payload.name {
        case NSWorkspace.didActivateApplicationNotification:
            .applicationActivated(bundleIdentifier: payload.bundleIdentifier)
        case NSWorkspace.willSleepNotification:
            .willSleep
        case NSWorkspace.didWakeNotification:
            .didWake
        case NSWorkspace.screensDidSleepNotification:
            .screensDidSleep
        case NSWorkspace.screensDidWakeNotification:
            .screensDidWake
        case NSWorkspace.sessionDidResignActiveNotification:
            .sessionDidResignActive
        case NSWorkspace.sessionDidBecomeActiveNotification:
            .sessionDidBecomeActive
        case NSWorkspace.willPowerOffNotification:
            .willPowerOff
        case screenIsLockedName:
            .distributedScreenLocked
        case screenIsUnlockedName:
            .distributedScreenUnlocked
        default:
            nil
        }
    }
}
