import AppKit
import FocusCore
import FocusUI
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// **Every control the menu bar draws, in the state the menu bar exists for** (focus-mwm).
///
/// ## Why the state is the fold and not the fixture
///
/// `AppComposition.perform(_ action: MenuBarAction)` was private and had **zero** references
/// anywhere in `Packages/FocusHost/Tests`; no self-check probe drove one either. What stood in
/// for coverage was `MenuBarTests.popoverReportsActions`, titled *"every popover control reports
/// its own typed request"*, whose body calls the closure the test itself injected — it observes
/// no effect, and for four of these actions there was none to observe.
///
/// All four sent a `PriorityCommand` to `FocusCommandCenter`, which delivers to the cockpit's
/// registered handler and otherwise stores the command. `CockpitView` registers that handler on
/// `.onAppear` and unregisters it on `.onDisappear`, so **"no handler" is exactly "the main
/// window is closed"** — which for a menu-bar app is not an edge case, it is the state the menu
/// bar is *for*. ⌘W is bound, the window has a close button, and
/// `applicationShouldTerminateAfterLastWindowClosed` answers `false` on purpose.
///
/// So the window is a column here, and the table does not have a column for it: what each control
/// does is the same fact in both, which is the whole claim.
@Suite("Every menu-bar control acts with the cockpit closed", .serialized)
@MainActor
struct MenuBarActionTotalityTests {
    /// What one click must actually do. `CaseIterable` so the coverage check below can prove
    /// every declared effect is driven by at least one action in `everyAction`.
    enum Effect: CaseIterable {
        /// Bring the main window forward. The only one that needs a window at all, and it asks
        /// for one **by name** rather than by sending a command that happens to open one.
        case raisesTheCockpit
        case startsASession
        case pausesTheSession
        case completesTheSession
        case pausesSensing
        /// **Opens the Settings window** (focus-odz.2). It performs the app menu's own ⌘, item
        /// rather than opening a second Settings surface, so what a unit process can observe is
        /// the request; whether the menu bar was holding an item to perform is the self-check's.
        case opensSettings
        /// **Leaves.** Recorded rather than performed here: the shipping closure calls
        /// `NSApp.terminate(nil)`, which in this process would take the runner with it.
        case quits
        /// Straight to the nudge loop, which is an object rather than a window. These three were
        /// already right, and they are the pattern the four above now follow.
        case reachesTheNudgeLoop
    }

    /// **The table.** Exhaustive over `MenuBarAction`, so a case added by a later epic stops the
    /// build here rather than shipping as a button with nothing behind it.
    static func effect(of action: MenuBarAction) -> Effect {
        switch action {
        case .openCockpit: .raisesTheCockpit
        case .startSession: .startsASession
        case .pauseSession: .pausesTheSession
        case .completeSession: .completesTheSession
        case .setSensingPaused: .pausesSensing
        case .openSettings: .opensSettings
        case .quit: .quits
        case .cancelSnooze, .answerQuery, .selectQueryScope, .correct: .reachesTheNudgeLoop
        }
    }

    /// One representative of every case. `MenuBarAction` carries payloads, so it cannot be
    /// `CaseIterable`; `everyEffectIsDriven` below is what keeps this list honest.
    /// `NudgeHostFixture.decoy`, spelled here because this list is `nonisolated` — the test
    /// framework reads it off the main actor — and the fixture's copy is not.
    nonisolated static let decoySubject = "com.chrismitchelmore.FocusDecoy"

    nonisolated static let everyAction: [MenuBarAction] = [
        .openCockpit,
        .startSession,
        .pauseSession,
        .completeSession,
        .setSensingPaused(true),
        .openSettings,
        .quit,
        // Force-unwrapped, as the other menu-bar suites do: `named(_:)` answers `nil` only for
        // an identifier that is empty or whitespace, and this one is a compiled constant.
        .cancelSnooze(subject: NudgeSubject.named(decoySubject)!),
        .answerQuery(.yesAddIt),
        .correct(.dismiss, snoozeDuration: nil)
    ]

    /// The list above covers every effect the table can name. A new `MenuBarAction` whose
    /// treatment is genuinely new gets a new `Effect`, and this fails until a representative of
    /// it is driven.
    @Test("every declared effect is driven by an action this suite performs")
    func everyEffectIsDriven() {
        let driven = Set(Self.everyAction.map(Self.effect(of:)))
        #expect(driven == Set(Effect.allCases))
        // …and the local copy of the decoy identifier has not drifted from the fixture's.
        #expect(Self.decoySubject == NudgeHostFixture.decoy)
    }

    /// A recorder standing where the cockpit stands.
    @MainActor
    final class CommandSink {
        private(set) var commands: [PriorityCommand] = []
        func install() { FocusCommandCenter.shared.register { [self] in commands.append($0) } }
        func remove() { FocusCommandCenter.shared.unregister() }
    }

    /// **The invariant, over the whole vocabulary**: nothing a person clicks in the menu bar goes
    /// down a channel a window owns.
    ///
    /// The handler is installed here on purpose — the opposite of the state under test — because
    /// a registered handler is what makes a stray send *visible*. With none registered the send
    /// would be swallowed and this reading would pass on the defect.
    @Test("no menu-bar click routes anything through the cockpit's command channel",
          arguments: MenuBarActionTotalityTests.everyAction)
    func nothingGoesThroughTheWindowsChannel(action: MenuBarAction) throws {
        let clock = FixedMonotonicClock()
        let (root, _) = try CompositionRootWireTests.joinedRoot(clock: clock)
        // **Disarmed before anything is driven** (focus-odz.2). This suite is exhaustive over
        // `MenuBarAction`, and one of them leaves: the shipping closure calls
        // `NSApp.terminate(nil)`, which in this process is the test runner.
        root.terminate = {}
        let sink = CommandSink()
        sink.install()
        defer {
            sink.remove()
            CompositionRootWireTests.tearDown(root)
        }

        let wire = try #require(root.menuBar.onAction, "the status item has nobody to tell")
        wire(action)

        #expect(
            sink.commands.isEmpty,
            "\(action) sent \(sink.commands) to a handler only an open cockpit registers"
        )
    }

    /// **What each control does, with nothing listening.**
    @Test("every menu-bar control does what its label says with the main window closed",
          arguments: MenuBarActionTotalityTests.everyAction)
    func everyControlActsWithTheCockpitClosed(action: MenuBarAction) throws {
        let clock = FixedMonotonicClock()
        let (root, _) = try CompositionRootWireTests.joinedRoot(clock: clock)
        defer { CompositionRootWireTests.tearDown(root) }
        // Disarmed for the reason the suite above states: one of these actions is Quit.
        root.terminate = {}

        // The state under test, asserted rather than assumed. `joinHosts()` does not register a
        // command handler — only `CockpitView.onAppear` does — but a suite that ran after one
        // which left one installed would be running a different test.
        FocusCommandCenter.shared.unregister()
        #expect(!FocusCommandCenter.shared.isConnected)

        let effect = Self.effect(of: action)

        // The two session effects need a session to act on, and starting needs there not to be
        // one. Set up by the app's own verb, so the precondition is a state the app can be in.
        if effect == .pausesTheSession || effect == .completesTheSession {
            root.sessionActions.startSession(kind: .openEnded, plannedSeconds: nil, deadlineAt: nil)
            try #require(root.sessionHost.snapshot != nil, "there is no session to act on")
        }

        let requestsBefore = FocusCommandCenter.shared.cockpitRequests
        // **Through the wire the status item calls, not past it** (focus-w3f).
        //
        // This was `root.perform(action)`, which is exactly what `CompositionRootWireTests`'
        // doctrine forbids and says about `onCorrection` in so many words. The table below is
        // exhaustive over `MenuBarAction`, and an exhaustive table over the wrong entry point is
        // still not a test of the wire: `menuBar.onAction` could be replaced with `{ _ in }` and
        // all thirteen items in the shipping menu would go dead with this suite green.
        let wire = try #require(root.menuBar.onAction, "the status item has nobody to tell")
        wire(action)

        switch effect {
        case .raisesTheCockpit:
            // The **request**, which is observable whether a scene is there to answer it or not.
            // Whether this process can answer one is a different fact, asserted where it can be:
            // the self-check reads `canRaiseCockpit` in the shipping application, because only a
            // launch with a scene graph has an `openWindow` to install.
            #expect(FocusCommandCenter.shared.cockpitRequests == requestsBefore + 1)
        case .startsASession:
            #expect(root.sessionHost.snapshot != nil, "Start session started none")
        case .pausesTheSession:
            #expect(root.sessionHost.snapshot?.phase == .paused, "Pause paused nothing")
        case .completesTheSession:
            #expect(
                root.sessionHost.snapshot == nil,
                "Complete session left the session running"
            )
        case .pausesSensing:
            #expect(root.sensingHost.settings.sensingPaused, "the switch reached no setting")
            // …and it is the stored value, not a flag this process is holding: F-119 detaches
            // observers from one row that every surface is bound to.
            #expect(
                FocusStore.sensingSettings(in: root.modelContainer.mainContext).sensingPaused
            )
        case .opensSettings:
            // The **request**, which is observable whether there is a menu bar to perform or not.
            // A unit process has no ⌘, item, so `settingsMenuItemFound` is `false` here and is
            // asserted in the shipping application by the self-check — the same division
            // `raisesTheCockpit` above draws.
            #expect(root.settingsOpenRequests == 1, "Settings… asked for nothing")
        case .quits:
            #expect(root.quitRequests == 1, "Quit left the application running")
            // …and it did not go looking for a window on the way out.
            #expect(FocusCommandCenter.shared.cockpitRequests == requestsBefore)
        case .reachesTheNudgeLoop:
            // These three were already objects rather than windows. What is asserted is that they
            // still are: nothing was raised and nothing was buffered on their behalf.
            #expect(FocusCommandCenter.shared.cockpitRequests == requestsBefore)
        }
    }
}
