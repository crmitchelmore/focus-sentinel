import FocusCore
import FocusUI
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// **The one screen that says what this app looks at, shown once** (focus-odz.7).
///
/// A first launch installed a status item and started recording activations with nothing on screen
/// saying so. Every claim the product rests on — it reads the frontmost application and nothing
/// else, it asks for no permissions, everything stays on this Mac — was true and reachable only by
/// opening Settings and choosing the Privacy tab.
///
/// What this suite can hold is the decision and the wiring around it. What it **cannot** hold is
/// the half that spans two processes: a flag set and read back in one process is satisfied by a
/// plain in-memory `Bool`. `MigrationV6Tests` holds the store's half — that a fresh store owes the
/// explanation and a migrated one never does — and the self-check holds the two-launch half, by
/// opening one store twice.
@Suite("The first-run explanation", .serialized)
@MainActor
struct FirstRunExplanationTests {
    static func root() -> AppComposition {
        CompositionRootWireTests.root(clock: FixedMonotonicClock())
    }

    /// **A store the app has never opened owes the explanation**, and joining the hosts is where
    /// that is decided — once per launch, because the projection that would otherwise ask it runs
    /// on every corroboration tick.
    @Test("a fresh store is owed the explanation, and the cockpit shows it")
    func aFreshStoreIsOwedTheFirstRunScreen() {
        let root = Self.root()
        defer { CompositionRootWireTests.tearDown(root) }

        #expect(FocusStore.shellState(in: root.modelContainer.mainContext).owesFirstRunExplanation)
        root.joinHosts()

        #expect(root.showsFirstRunExplanation)
        #expect(root.cockpitState.showsFirstRunExplanation)
    }

    /// **The showing is written down at the moment the app decides to show it**, so the store the
    /// next launch reads is already stamped. The alternative — recording on dismissal — shows it
    /// again to somebody who quit with it on screen.
    @Test("deciding to show it records it, so a second decision in the same store shows nothing")
    func theShowingIsRecordedWhenItIsDecided() {
        let root = Self.root()
        defer { CompositionRootWireTests.tearDown(root) }
        root.joinHosts()
        #expect(root.showsFirstRunExplanation)

        #expect(
            !FocusStore.shellState(in: root.modelContainer.mainContext).owesFirstRunExplanation,
            "showing it wrote nothing the next launch could read"
        )

        // Idempotent: a delegate notification arriving twice cannot raise a second sheet.
        root.decideFirstRunScreen()
        #expect(!root.showsFirstRunExplanation)
    }

    /// Dismissal takes it off *this* launch's screen and writes nothing further — the record was
    /// made when it went up.
    @Test("dismissing it takes the sheet down")
    func dismissingTakesItDown() {
        let root = Self.root()
        defer { CompositionRootWireTests.tearDown(root) }
        root.joinHosts()
        #expect(root.cockpitState.showsFirstRunExplanation)

        root.dismissFirstRunScreen()

        #expect(!root.showsFirstRunExplanation)
        #expect(!root.cockpitState.showsFirstRunExplanation)
    }

    /// **A store that has already been explained is never explained again**, which is the half a
    /// person upgrading depends on: the v5 → v6 migration stamps every carried-forward store, so
    /// this is the shape they arrive in.
    @Test("a store that has already been explained shows nothing")
    func anExplainedStoreShowsNothing() throws {
        let root = Self.root()
        defer { CompositionRootWireTests.tearDown(root) }

        try FocusStore.recordFirstRunExplanationShown(
            in: root.modelContainer.mainContext,
            now: NudgeHostFixture.reference
        )
        root.joinHosts()

        #expect(!root.showsFirstRunExplanation)
        #expect(!root.cockpitState.showsFirstRunExplanation)
    }

    /// **The connection carries the sheet's one route out**, and it reaches the root.
    ///
    /// A sink: no lane in this programme holds the Accessibility grant it would take to press the
    /// button, so the closure is handed back and driven rather than clicked — the same division
    /// `onInterventionAction` is under.
    @Test("the cockpit connection's dismissal closure reaches the composition root")
    func theConnectionCarriesTheDismissal() {
        let root = Self.root()
        defer { CompositionRootWireTests.tearDown(root) }
        root.joinHosts()

        let connection = root.cockpitConnection()
        #expect(connection.state.showsFirstRunExplanation)

        connection.onFirstRunExplanationDismissed()

        #expect(!root.showsFirstRunExplanation)
        #expect(!root.cockpitConnection().state.showsFirstRunExplanation)
    }
}
