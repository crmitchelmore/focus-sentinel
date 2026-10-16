import AppKit
import FocusCore
import FocusUI
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// **What the two scene connections actually carry** (focus-2er).
///
/// ## The mutations these exist for
///
/// The cockpit scene passed five arguments read off the composition root and the Settings scene
/// passed seven, all in `App/`, which is not a package. Eight no-op mutations applied together
/// left the entire nineteen-stage gate at PASS with an empty diff of its ok-assertions: the
/// cockpit's whole live state frozen into a placeholder — priority, session, recents, verdict,
/// capabilities, handoff sheet — the session timer always zero, the Privacy pane always saying
/// nothing is watched, and the Intervention pane's controls reaching nothing.
///
/// Bundling each scene's arguments into one value moved every one of those reads out of `App/`
/// and into this package. They are ordinary function results now, and this suite holds each of
/// them up beside the live host it was read from. `scripts/self-check.sh` proves the scene calls
/// the function; this proves the function tells the truth. Neither is sufficient alone: gut a
/// field here and the self-check's receipts still arrive.
@Suite("The scene connections", .serialized)
@MainActor
struct AppCompositionConnectionTests {
    static func root() -> AppComposition {
        CompositionRootTests.root()
    }

    // MARK: - The cockpit

    /// Every field, against the live host it comes from. A placeholder in any one of them is a
    /// window that draws a fact about nobody.
    @Test("the cockpit connection carries the live graph, field by field")
    func theCockpitConnectionIsLive() throws {
        let root = Self.root()
        defer { root.stop() }
        let priorities = PriorityStore(
            context: root.modelContainer.mainContext,
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference)
        )
        _ = try priorities.setPriority(intent: "Write the Q3 proposal for Acme")
        root.refreshCockpit()

        // **With no session open the timer reads nothing, not zero** — which is the shape the
        // "session timer always reads zero" mutation cannot take. A frozen `0` is a number about
        // a session that does not exist, and it is indistinguishable from a real one the instant
        // a session starts, so this is the reading that tells them apart.
        #expect(
            root.cockpitConnection().sessionElapsedSeconds == nil,
            "the cockpit reports an elapsed time for a session nobody started"
        )

        root.sessionActions.startSession(kind: .openEnded, plannedSeconds: nil, deadlineAt: nil)
        root.refreshCockpit()

        let connection = root.cockpitConnection()

        #expect(
            connection.state == root.cockpitState,
            "the window draws a CockpitState nobody is updating"
        )
        #expect(
            connection.state.priority?.intent == "Write the Q3 proposal for Acme",
            "the connection carries a state with no priority in it"
        )
        #expect(
            connection.actions as AnyObject? === root.cockpitActions as AnyObject,
            "the cockpit's buttons reach a different host from the one the app owns"
        )
        #expect(
            connection.sessionActions as AnyObject? === root.sessionActions as AnyObject,
            "the session controls and the session menu items are two different hosts"
        )
        #expect(
            connection.sessionElapsedSeconds != nil,
            "the session timer reads nothing while a session is open"
        )
        #expect(connection.sessionElapsedSeconds == root.sessionElapsedSeconds)
        // Named residue (focus-2er). Both sides are `nil` in a test process, because the observer
        // graph is not attached and nothing has activated: substituting `nil` for this field
        // survives here. What it costs is one line of the interruption sheet — "what was I
        // doing" — and the live lane reads it. Closing it needs an injectable workspace
        // notification centre threaded from this initialiser down to `SensingHost`.
        #expect(connection.lastActiveBundleID == root.lastActiveBundleID)
    }

    /// The receipts, at this end. `cockpitConnected` is recorded when the scene asks;
    /// `cockpitRendered` is recorded by the closure the connection carries, which is what the
    /// view calls from its body — so a connection that never reached a body says so.
    @Test("asking for the connection records the ask, and its closure records the render")
    func theCockpitConnectionRecordsBothHalves() {
        let root = Self.root()
        defer { root.stop() }
        #expect(!root.shellWires.contains(.cockpitConnected))

        let connection = root.cockpitConnection()

        #expect(root.shellWires.contains(.cockpitConnected))
        #expect(
            !root.shellWires.contains(.cockpitRendered),
            "the connection claimed to have been drawn before any view drew it"
        )

        connection.didRender()
        #expect(root.shellWires.contains(.cockpitRendered))
    }

    // MARK: - The Settings window

    /// Every projection the Privacy and Intervention panes draw, against the live graph. The
    /// mutation this kills is the one that made the Privacy pane say nothing was being watched
    /// on a Mac that was watching.
    @Test("the settings connection carries the live graph, field by field")
    func theSettingsConnectionIsLive() throws {
        let root = Self.root()
        defer { root.stop() }
        root.perform(InterventionSettingsAction.setVoice(NudgeVoice.warm))
        root.appearance.preference = .dark
        // The graph is attached and one real judgement is made, so the two Privacy-pane
        // projections are something other than their empty defaults. Without that,
        // `summary: .inactive` and `verdict: nil` are what the live graph says anyway and the
        // two mutations that freeze them are invisible — which is the state the pane was in
        // when it said nothing was being watched on a Mac that was watching.
        root.sensingHost.start()
        root.relevanceHost.observe(
            JudgeableSubject(bundleIdentifier: "com.example.Reader", isSuppressed: false),
            phase: .focus,
            isUserIdle: false
        )
        try #require(root.sensingSummary != .inactive, "the graph never attached")
        try #require(root.verdict != nil, "the engine never judged")

        let connection = root.settingsConnection()

        #expect(connection.preference == .dark)
        // The file this root is writing to — none, for the in-memory store every lane uses
        // (focus-k2in) — never the shipping path it is not writing to.
        #expect(connection.storeURL == root.activeStoreURL)
        #expect(connection.summary == root.sensingSummary)
        #expect(connection.capabilities == root.capabilities)
        #expect(connection.verdict == root.verdict)
        #expect(
            connection.intervention == root.interventionSettings,
            "the Intervention pane draws settings assembled for the occasion"
        )
        #expect(
            connection.intervention.voice == NudgeVoice.warm,
            "the pane does not show what the loop is actually set to"
        )
    }

    /// **focus-cp2's M3, at the end it now lives at.** `onInterventionAction` was gutted to
    /// `{ _ in }` in `App/` and survived the whole gate — and under U-1 it is what decides
    /// whether the app may speak at all. It is a closure on this value now, and calling it
    /// reaches the running loop.
    @Test("the settings connection's action sink reaches the nudge loop")
    func theSettingsActionSinkReachesTheLoop() {
        let root = Self.root()
        defer { root.stop() }
        let connection = root.settingsConnection()

        connection.onInterventionAction(.setVoice(.warm))
        #expect(root.nudgeHost.preferences.voice == NudgeVoice.warm)

        connection.onInterventionAction(.setReducedInterruption(true))
        #expect(root.nudgeHost.preferences.reducedInterruption == true)
        #expect(root.nudgeHost.preferences.voice == NudgeVoice.warm)
    }

    /// **focus-cp2's M4, at the end it now lives at.** The store write was deleted from a
    /// `Binding` setter written by hand in a scene body, and the person's appearance choice was
    /// forgotten the moment they quit. The setter is one verb now, and it does both halves.
    @Test("the settings connection's preference setter updates the shell and the store")
    func theSettingsPreferenceSetterPersists() {
        let root = Self.root()
        defer { root.stop() }
        #expect(root.storedAppearancePreference() == .matchSystem)

        root.settingsConnection().setPreference(.dark)

        #expect(root.appearance.preference == .dark, "the shell did not re-render on the choice")
        #expect(
            root.storedAppearancePreference() == .dark,
            "the person's appearance choice is forgotten when they quit"
        )
        #expect(
            FocusStore.appearancePreference(in: root.modelContainer.mainContext) == .dark,
            "the write went somewhere the rest of the application does not read"
        )
    }

    /// The Settings window may be opened long after launch, so it re-reads the stored value
    /// rather than assuming the observer still matches what the person last chose. Driven the
    /// hard way: something else writes the store, and the window's appearing is what notices.
    @Test("the Settings window's appearance re-reads the stored preference")
    func theSettingsWindowRereadsTheStoredPreference() {
        let root = Self.root()
        defer { root.stop() }
        root.setAppearancePreference(.light)
        // The observer is deliberately left disagreeing with the store, which is the state a
        // window opened long after launch is actually in.
        root.appearance.preference = .dark

        root.settingsWindowAppeared()

        #expect(root.shellWires.contains(.settingsAppeared))
        #expect(
            root.appearance.preference == .light,
            "the Settings window shows an appearance the store does not hold"
        )
    }

    @Test("asking for the settings connection records the ask, and its closure the render")
    func theSettingsConnectionRecordsBothHalves() {
        let root = Self.root()
        defer { root.stop() }

        let connection = root.settingsConnection()

        #expect(root.shellWires.contains(.settingsConnected))
        #expect(!root.shellWires.contains(.settingsRendered))

        connection.didRender()
        #expect(root.shellWires.contains(.settingsRendered))
    }

    // MARK: - The enumeration itself

    /// Every declared wire is fired by something in this package, so a name nobody can produce
    /// cannot be added to the enumeration to make the self-check's set assertion pass vacuously.
    @Test("every wire App/ can fire has a producer the unit lane can reach")
    func everyWireHasAProducer() throws {
        let root = Self.root()
        defer { root.stop() }

        root.undoManagerChanged(UndoManager())
        root.appearanceChanged(root.appearance.traits)
        root.receive(try #require(URL(string: "focus://start?task=Anything")))
        root.priorityHost.cancelHandoff()
        root.cockpitConnection().didRender()
        root.settingsConnection().didRender()
        root.helpWindowRendered(.nothing)
        root.settingsWindowAppeared()
        for surface in ShellThemedSurface.allCases { _ = root.appearanceTraits(for: surface) }

        #expect(
            root.shellWires == Set(ShellWire.allCases),
            """
            a declared wire has no producer in this package: \
            \(Set(ShellWire.allCases).subtracting(root.shellWires).map(\.rawValue).sorted())
            """
        )
    }
}
