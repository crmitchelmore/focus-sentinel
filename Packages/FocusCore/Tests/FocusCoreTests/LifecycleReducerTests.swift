import Foundation
import Testing

@testable import FocusCore

private let loginWindow = LifecycleInput.loginWindowBundleIdentifier

/// The whole table: every input, in both directions, alone and in the sequences that were
/// actually measured. Used by the removal test, which replays all of them.
private let wholeTable: [[LifecycleInput]] = [
    // Nothing at all.
    [],

    // The measured lock sequence (probe P-87), in the order it arrived.
    [.applicationActivated(bundleIdentifier: loginWindow), .distributedScreenLocked],
    // …and its unlock, in the order that arrived too: the distributed one came 0.6 ms first.
    [
        .applicationActivated(bundleIdentifier: loginWindow), .distributedScreenLocked,
        .distributedScreenUnlocked, .applicationActivated(bundleIdentifier: "com.apple.finder")
    ],

    // Each public signal alone.
    [.willSleep],
    [.willSleep, .didWake],
    [.screensDidSleep],
    [.screensDidSleep, .screensDidWake],
    [.sessionDidResignActive],
    [.sessionDidResignActive, .sessionDidBecomeActive],
    [.willPowerOff],
    [.applicationActivated(bundleIdentifier: "com.apple.dt.Xcode")],
    [.applicationActivated(bundleIdentifier: nil)],

    // The distributed pair alone, in both orders — the case the Court's downgrade is about.
    [.distributedScreenLocked],
    [.distributedScreenUnlocked],
    [.distributedScreenLocked, .distributedScreenUnlocked],
    [.distributedScreenUnlocked, .distributedScreenLocked],

    // Overlapping conditions: the display sleeps while the screen is locked.
    [
        .screensDidSleep, .applicationActivated(bundleIdentifier: loginWindow),
        .distributedScreenLocked, .screensDidWake
    ],
    // …and the same, unlocked without the displays being mentioned again.
    [
        .screensDidSleep, .applicationActivated(bundleIdentifier: loginWindow),
        .applicationActivated(bundleIdentifier: "com.apple.finder")
    ],

    // Sleep across a lock.
    [.applicationActivated(bundleIdentifier: loginWindow), .willSleep, .didWake],
    // Fast user switching across a lock.
    [
        .sessionDidResignActive, .applicationActivated(bundleIdentifier: loginWindow),
        .sessionDidBecomeActive
    ],
    // Power off wins over everything and never comes back.
    [
        .willPowerOff, .applicationActivated(bundleIdentifier: "com.apple.finder"),
        .didWake, .screensDidWake, .sessionDidBecomeActive, .distributedScreenUnlocked
    ]
]

@Suite("The lifecycle reducer")
struct LifecycleReducerTests {
    /// **The Court's condition, as an assertion over the whole table.**
    ///
    /// "May only supplement, never be the sole trigger" is proved here by deleting the
    /// undocumented inputs from every sequence and asserting the reduction is identical. It
    /// holds for *every* input list rather than for the ones a test author imagined, because
    /// the distributed inputs affect no condition at all — they only count.
    @Test("the whole table with the distributed inputs removed produces identical states")
    func distributedInputsChangeNothing() {
        for sequence in wholeTable {
            let withThem = LifecycleReducer.reduce(sequence)
            let withoutThem = LifecycleReducer.reduce(sequence.filter { !$0.isDistributed })
            #expect(
                withThem.conditions == withoutThem.conditions,
                "removing the undocumented notification changed the conditions for \(sequence)"
            )
            #expect(
                withThem.state == withoutThem.state,
                "removing the undocumented notification changed the state for \(sequence)"
            )
        }
    }

    /// The public primary, on its own.
    @Test("a loginwindow activation produces .screenLocked, with no distributed input at all")
    func loginWindowActivationLocks() {
        let reduction = LifecycleReducer.reduce([
            .applicationActivated(bundleIdentifier: loginWindow)
        ])
        #expect(reduction.state == .screenLocked)
        #expect(reduction.corroborations == 0)
    }

    @Test("activating away from loginwindow produces .active")
    func activatingAwayUnlocks() {
        let reduction = LifecycleReducer.reduce([
            .applicationActivated(bundleIdentifier: loginWindow),
            .applicationActivated(bundleIdentifier: "com.apple.finder")
        ])
        #expect(reduction.state == .active)
        #expect(reduction.conditions.isEmpty)
    }

    /// The hardest measured negative in the epic: on macOS 26.5.2 a `pmset displaysleepnow`
    /// produced **no** `screensDidSleep`. A reducer that needed it would never have run.
    @Test("a screensDidSleep that never arrives changes nothing")
    func silentScreensDidSleepChangesNothing() {
        let asMeasured = LifecycleReducer.reduce([
            .applicationActivated(bundleIdentifier: loginWindow),
            .distributedScreenLocked
        ])
        #expect(asMeasured.state == .screenLocked, "the lock was detected without it")
        #expect(!asMeasured.conditions.contains(.displaysAsleep))
    }

    /// Each "off" signal clears its own condition and no other. A display waking must not
    /// unlock a locked screen, and a person unlocking must not claim the displays woke.
    @Test("each clearing signal clears its own condition alone")
    func clearingSignalsAreAuthorised() {
        // Locked *and* displays asleep. Waking the display leaves the lock standing.
        var reduction = LifecycleReducer.reduce([
            .screensDidSleep,
            .applicationActivated(bundleIdentifier: loginWindow)
        ])
        #expect(reduction.conditions == [.displaysAsleep, .screenLocked])
        #expect(reduction.state == .screenLocked, "locked is more severe than displays asleep")

        reduction = LifecycleReducer.step(.screensDidWake, into: reduction)
        #expect(reduction.conditions == [.screenLocked], "waking the display unlocked the screen")
        #expect(reduction.state == .screenLocked)

        reduction = LifecycleReducer.step(
            .applicationActivated(bundleIdentifier: "com.apple.finder"),
            into: reduction
        )
        #expect(reduction.conditions.isEmpty)
        #expect(reduction.state == .active)
    }

    @Test("severity decides which condition the single typed state reports")
    func severityOrdersTheConditions() {
        let all = LifecycleReducer.reduce([
            .sessionDidResignActive, .screensDidSleep,
            .applicationActivated(bundleIdentifier: loginWindow),
            .willSleep, .willPowerOff
        ])
        #expect(all.conditions.count == 5)
        #expect(all.state == .poweringOff)

        // And in descending order of severity, as each is cleared.
        var reduction = all
        // (nothing clears poweringOff — see below)
        reduction = LifecycleReducer.reduce(
            [.didWake],
            from: LifecycleReduction(conditions: all.conditions.subtracting([.poweringOff]))
        )
        #expect(reduction.state == .screenLocked)
        reduction = LifecycleReducer.step(
            .applicationActivated(bundleIdentifier: "com.apple.Safari"),
            into: reduction
        )
        #expect(reduction.state == .displaysAsleep)
        reduction = LifecycleReducer.step(.screensDidWake, into: reduction)
        #expect(reduction.state == .sessionInactive)
        reduction = LifecycleReducer.step(.sessionDidBecomeActive, into: reduction)
        #expect(reduction.state == .active)
    }

    /// There is no signal that takes a power-off back, because there is no coming back.
    @Test("poweringOff is sticky")
    func poweringOffIsSticky() {
        let reduction = LifecycleReducer.reduce([
            .willPowerOff,
            .applicationActivated(bundleIdentifier: "com.apple.finder"),
            .didWake, .screensDidWake, .sessionDidBecomeActive
        ])
        #expect(reduction.state == .poweringOff)
    }

    /// Every non-`.active` state maps to its own distinct cause, and `.active` maps to none.
    /// That is what makes an unlock lift the lock's pause and leave every other pause standing.
    @Test("every non-active state carries a distinct pause cause")
    func everyStateHasItsOwnCause() {
        #expect(SystemLifecycle.active.pauseCause == nil)
        #expect(SystemLifecycle.active.isActive)

        var causes: Set<PauseReason> = []
        for state in SystemLifecycle.allCases where state != .active {
            let cause = state.pauseCause
            #expect(cause != nil, "\(state) has no cause, so nothing could ever resume it")
            if let cause { causes.insert(cause) }
        }
        #expect(causes.count == 5, "two lifecycle states share a cause and could clear each other")

        #expect(SystemLifecycle.screenLocked.pauseCause == .screenLocked)
        #expect(SystemLifecycle.displaysAsleep.pauseCause == .displaysAsleep)
        #expect(SystemLifecycle.systemAsleep.pauseCause == .systemAsleep)
        #expect(SystemLifecycle.sessionInactive.pauseCause == .sessionInactive)
        #expect(SystemLifecycle.poweringOff.pauseCause == .systemRestart)
    }

    /// The pause a lifecycle state causes is lifted by that same cause and by nothing else —
    /// asserted end to end against the machine, including the case the ruling exists for: a
    /// user pause taken *during* a screen lock survives the unlock.
    @Test("a user pause taken during a screen lock survives the unlock")
    func userPauseSurvivesTheUnlock() {
        let t0 = Date(timeIntervalSince1970: 1_767_225_600)
        var state = SessionState.started(at: t0)

        // The screen locks.
        let locked = LifecycleReducer.reduce([.applicationActivated(bundleIdentifier: loginWindow)])
        let lockCause = try? #require(locked.state.pauseCause)
        state = SessionMachine.apply(.paused(cause: lockCause!), to: state, at: t0).state!

        // The person pauses too, while it is locked.
        state = SessionMachine.apply(.paused(cause: .user), to: state, at: t0).state!
        #expect(state.pauseCauses == [.screenLocked, .user])

        // They unlock. The observer resumes with the cause it owns, and only that one.
        let unlocked = LifecycleReducer.reduce(
            [.applicationActivated(bundleIdentifier: "com.apple.finder")],
            from: locked
        )
        #expect(unlocked.state == .active)
        let transition = SessionMachine.apply(.resumed(cause: .screenLocked), to: state, at: t0)
        #expect(transition.state?.phase == .paused, "the unlock resumed a pause the person set")
        #expect(transition.state?.pauseCauses == [.user])
    }

    /// The supplement is *counted*, so a strange timeline has an explanation in it and the
    /// evidence lane can say how reliable it actually was.
    @Test("the distributed inputs are counted as corroborations and contradictions")
    func distributedInputsAreCounted() {
        let agreeing = LifecycleReducer.reduce([
            .applicationActivated(bundleIdentifier: loginWindow),
            .distributedScreenLocked
        ])
        #expect(agreeing.corroborations == 1)
        #expect(agreeing.contradictions == 0)

        // A lock notification with no public lock behind it: counted, and ignored.
        let contradicting = LifecycleReducer.reduce([.distributedScreenLocked])
        #expect(contradicting.contradictions == 1)
        #expect(contradicting.state == .active, "the supplement became the sole trigger")

        // An unlock notification while unlocked agrees with the public state.
        #expect(LifecycleReducer.reduce([.distributedScreenUnlocked]).corroborations == 1)
    }

    /// An activation with no bundle identifier is still an activation, and an activation is
    /// not the login window.
    @Test("an unbundled activation is not the login window and clears a lock")
    func unbundledActivationIsNotTheLoginWindow() {
        let reduction = LifecycleReducer.reduce([
            .applicationActivated(bundleIdentifier: loginWindow),
            .applicationActivated(bundleIdentifier: nil)
        ])
        #expect(reduction.state == .active)
    }

    @Test("reduce is pure: the same inputs give the same reduction")
    func reduceIsPure() {
        for sequence in wholeTable {
            #expect(LifecycleReducer.reduce(sequence) == LifecycleReducer.reduce(sequence))
        }
    }
}
