import AppKit
import FocusCore
import FocusUI
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// **The wires `startNudgeLoop()` and `joinHosts()` make that nothing was running** (focus-w3f).
///
/// ## How these were found
///
/// Not by reading. Reading is what missed them: `CompositionRootWireTests` documents four wires
/// and `NudgeFloorTests` a fifth, and the composition root makes **seventeen**. Every one of the
/// remaining twelve was replaced with a no-op, one at a time and then in groups, and the whole
/// FocusHost lane — 176 tests — was run against each.
///
/// Six survived. One of them was not untested but **dead**, which is its own commit; the five
/// below are live wires no assertion in the repository ran:
///
/// | wire | what a no-op costs the person |
/// |---|---|
/// | `menuBar.onAction` | **every** menu-bar and popover button stops working — all thirteen items |
/// | `sensingHost.onSensingChanged` | the cockpit never re-projects when sensing changes: the switch says one thing and the app does another |
/// | `sensingHost.onSessionChanged` | a session paused by the sensing switch is not re-read, so the cockpit draws a session that ended |
/// | `relevanceHost.activeCommitment` | the engine judges against no commitment at all, so gate 1 never opens |
/// | `nudgeHost.appearanceTraits` | every nudge is drawn in the system default, so dark mode is ignored on the one surface that appears unbidden |
///
/// **`menuBar.onAction` is the finding this bead predicted.** It sits at `AppComposition.swift:523`
/// — nine lines *above* `onPopoverDidShow`, which has a driven proof, and eighteen above
/// `onGlyphWritten`, which now has one too. Three wires on the same object; two were proved and the
/// one carrying every button was not. That is the shape the bead names: a treatment one half
/// received and the other did not.
///
/// The reason it was missed is visible in the suite that looks like it covers it.
/// `MenuBarActionTotalityTests` is exhaustive over `MenuBarAction` and drives `root.perform(_:)`
/// **directly** — which is precisely what `CompositionRootWireTests`' own doctrine forbids, and
/// what it says about `onCorrection` in so many words. An exhaustive table over the wrong entry
/// point is still not a test of the wire.
///
/// So the rule here is that suite's rule: **drive the shipping closure and observe the effect at
/// the far end.** Never assert non-nil. Never install a closure of its own.
@Suite("The composition root's remaining wires, driven", .serialized)
@MainActor
struct CompositionRootWireSweepTests {
    static func joinedRoot(
        clock: FixedMonotonicClock
    ) throws -> (root: AppComposition, priorityID: UUID) {
        try CompositionRootWireTests.joinedRoot(clock: clock)
    }

    static func tearDown(_ root: AppComposition) {
        CompositionRootWireTests.tearDown(root)
    }

    // MARK: - S6 · every button in the menu bar reaches something

    /// **The menu-bar action wire, run.**
    ///
    /// `MenuBarController` calls `onAction` for every item in its menu and every button in its
    /// popover. With the wire a no-op the status item still draws thirteen items, they still
    /// highlight, they still dismiss the menu — and none of them does anything at all. For a
    /// menu-bar application that is the whole product silently gone, and it survived the entire
    /// lane because every test of these actions calls `root.perform(_:)` instead.
    ///
    /// Driven with `setSensingPaused`, which is the one action whose far end is a fact the test
    /// can read without a window, a session or a store write: F-119's switch, observable as
    /// `SensingHost.isRunning`.
    @Test("a menu-bar action reaches the composition root through the wire the status item calls")
    func theMenuBarActionWireReachesTheRoot() throws {
        let clock = FixedMonotonicClock()
        let (root, _) = try Self.joinedRoot(clock: clock)
        defer { Self.tearDown(root) }

        root.sensingHost.resume()
        try #require(root.sensingHost.isRunning, "sensing was already off, so this drives nothing")

        // Nothing here installs a closure. The root already did, and that closure is under test.
        let wire = try #require(root.menuBar.onAction, "the status item has nobody to tell")
        wire(.setSensingPaused(true))

        #expect(
            !root.sensingHost.isRunning,
            "the menu bar's switch reached nobody: every item in the menu is a dead control"
        )

        wire(.setSensingPaused(false))
        #expect(root.sensingHost.isRunning, "the switch only works in one direction")
    }

    /// The same wire carrying a nudge verb rather than a session one, because `perform(_:)` routes
    /// the two through different objects and a wire proved with only one of them is proved for
    /// half of what it carries.
    @Test("a correction sent through the menu-bar wire reaches the nudge loop")
    func theMenuBarActionWireCarriesACorrection() throws {
        let clock = FixedMonotonicClock()
        let (root, priorityID) = try Self.joinedRoot(clock: clock)
        defer { Self.tearDown(root) }

        root.sessionActions.startSession(kind: .openEnded, plannedSeconds: nil, deadlineAt: nil)
        let rung = CompositionRootWireTests.escalateToARung(root, clock: clock)
        try #require(rung != nil, "the ladder never reached a rung, so there is nothing to correct")
        try #require(
            root.sessionHost.sessionRules(forPriority: priorityID).isEmpty,
            "the session already carried a rule"
        )

        // Nothing here installs a closure: the popover's buttons call `onAction`, and that is what
        // the root wired.
        let wire = try #require(root.menuBar.onAction)
        wire(.correct(.notThisTime, snoozeDuration: nil))
        NudgeHostFixture.settle()

        #expect(
            root.sessionHost.sessionRules(forPriority: priorityID).count == 1,
            """
            a correction pressed in the popover wrote nothing: it reached the cockpit and not \
            the loop
            """
        )
    }

    // MARK: - S7 · the cockpit follows what sensing is doing

    /// **The sensing-changed wire, run** (F-119).
    ///
    /// `SensingHost` fires `onSensingChanged` on every accepted activation, every capability
    /// change and both halves of the pause switch; the root's closure re-projects the value the
    /// cockpit draws. With it a no-op the switch turns sensing off and the window goes on saying
    /// the app is observing — a surface reporting the opposite of what the app is doing, which is
    /// worse than a surface reporting nothing.
    @Test("turning sensing off re-projects the cockpit, through the wire that says it changed")
    func theSensingChangedWireReprojectsTheCockpit() throws {
        let clock = FixedMonotonicClock()
        let (root, _) = try Self.joinedRoot(clock: clock)
        defer { Self.tearDown(root) }

        root.sensingHost.resume()
        root.refreshCockpit()
        try #require(
            root.priorityHost.state.isObservingActivity,
            "the cockpit did not start out observing, so this drives nothing"
        )

        // Straight at the host. Nothing calls `refreshCockpit()` here — that is the whole point:
        // the wire is what carries the change, and a test that re-projected by hand would prove
        // the projection and not the wire.
        root.sensingHost.pause()

        // Through a local `Bool`: handing the macro `state` puts the whole CockpitState — every
        // capability, the whole verdict — into the failure message and buries the one fact.
        let cockpitSaysObserving = root.priorityHost.state.isObservingActivity
        #expect(
            !cockpitSaysObserving,
            """
            sensing is off and the cockpit still says the app is observing: nothing told it, so \
            the window reports the opposite of what the app is doing
            """
        )
    }

    /// **The sensing-session wire, run.**
    ///
    /// The other half of the same switch, and a different destination: pausing sensing while a
    /// session is open applies `paused(cause: .globalPause)` to the session, and `SessionHost` is
    /// what the cockpit draws a session from. With this wire a no-op the session really is paused
    /// in the store and the host goes on holding the phase it had before, so the app's own idea of
    /// the session and the record of it disagree.
    @Test("pausing sensing during a session re-reads the session, through its own wire")
    func theSensingSessionWireReReadsTheSession() throws {
        let clock = FixedMonotonicClock()
        let (root, _) = try Self.joinedRoot(clock: clock)
        defer { Self.tearDown(root) }

        root.sensingHost.resume()
        root.sessionActions.startSession(kind: .openEnded, plannedSeconds: nil, deadlineAt: nil)
        let started = try #require(root.sessionHost.snapshot, "no session was opened")
        try #require(started.phase != .paused, "the session was already paused")

        root.sensingHost.pause()

        #expect(
            root.sessionHost.snapshot?.phase == .paused,
            """
            the session was paused in the store and the host still reads \
            \(String(describing: root.sessionHost.snapshot?.phase)): nothing re-read it
            """
        )
    }

    // MARK: - S8 · the engine judges against the commitment the app is acting under

    /// **The active-commitment wire, run** (focus-zrs).
    ///
    /// Gate 1 is `commitment != nil`. This closure is how the relevance engine learns what the
    /// person committed to, and it exists precisely so the engine does not open `PriorityStore` and
    /// decide for itself — which was a fourth independent read of the one fact gate 1 turns on.
    /// With it answering `nil` the engine judges against nothing at all: no judgement is ever
    /// relevant to anything, for the life of the process.
    @Test("the engine is handed the commitment the app is acting under, not nil")
    func theActiveCommitmentWireCarriesTheCommitment() throws {
        let clock = FixedMonotonicClock()
        let (root, priorityID) = try Self.joinedRoot(clock: clock)
        defer { Self.tearDown(root) }

        let wire = try #require(root.relevanceHost.activeCommitment, "the engine has nobody to ask")
        let commitment = wire()

        #expect(
            commitment != nil,
            "the engine is judging against no commitment, so gate 1 can never open"
        )
        #expect(
            commitment?.id == priorityID,
            """
            the engine was handed \(String(describing: commitment?.id)) and the app is acting \
            under \(priorityID): two independent reads of the one fact gate 1 is decided by
            """
        )
        // The same value the priority host states, rather than a second opinion about it.
        #expect(commitment == root.priorityHost.activeCommitment)
    }

    // MARK: - S9 · a nudge is drawn in the appearance the person is in

    /// **The appearance wire, run** (focus-pq8).
    ///
    /// Read at the moment a nudge is raised rather than captured once, because the panel is sticky
    /// enough to still be up when somebody switches to dark mode. With the wire returning
    /// `.systemDefault` every nudge is drawn light on a dark Mac — on the one surface in the
    /// application that appears without being asked for, and the one whose whole job is to be
    /// read at a glance.
    @Test("the nudge loop is handed the appearance the shell actually resolved")
    func theAppearanceWireCarriesTheResolvedTraits() throws {
        let clock = FixedMonotonicClock()
        let (root, _) = try Self.joinedRoot(clock: clock)
        defer { Self.tearDown(root) }

        let wire = try #require(root.nudgeHost.appearanceTraits, "the loop has nobody to ask")

        #expect(
            wire() == root.appearance.traits,
            """
            the loop is drawing nudges in \(wire()) and the shell resolved \
            \(root.appearance.traits): a nudge is the one surface that appears unbidden
            """
        )
        // …and it is a live read rather than a value captured at construction, which is the
        // difference between a person who switched to dark mode being followed and being ignored.
        // `preference` recomputes `traits` on set, so this is the shell resolving a new
        // appearance exactly as it does when the person changes their choice.
        root.appearance.preference = .dark
        #expect(
            wire() == root.appearance.traits,
            "the appearance was captured once: a nudge raised after the switch is drawn stale"
        )
        #expect(
            wire().colorScheme == .dark,
            "the loop is drawing light nudges for somebody who asked for dark"
        )
    }
}
