import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

@Suite("App Intents use the persistent hosts", .serialized)
@MainActor
struct FocusIntentIntegrationTests {
    @Test("priority, start and finish persist without a cockpit handler")
    func roundTrip() throws {
        let root = CompositionRootTests.root()
        defer { root.stop() }
        let center = FocusCommandCenter()
        center.provideWorld {
            ShellCommandWorld(
                hasPriority: root.priorityHost.state.priority != nil,
                sessionPhase: root.sessionHost.snapshot?.phase
            )
        }
        root.registerIntentPerformers(on: center)
        let runner = FocusIntentRunner(center: center)
        #expect(!center.isConnected)
        #expect(!center.canRaiseCockpit)
        #expect(throws: FocusIntentRefusal.noSessionToFinish) { try runner.finishSession() }
        try runner.setPriority("  Write the Q3 proposal  ")
        #expect(root.priorityHost.state.priority?.intent == "Write the Q3 proposal")
        let priorityID = root.priorityHost.state.priority?.id
        try runner.startSession()
        #expect(root.sessionHost.snapshot?.phase == .focus)
        let sessionID = root.sessionHost.snapshot?.sessionID
        #expect(sessionID != nil)
        #expect(throws: FocusIntentRefusal.sessionAlreadyRunning) { try runner.startSession() }
        #expect(root.sessionHost.snapshot?.sessionID == sessionID)
        try runner.finishSession()
        #expect(root.sessionHost.snapshot == nil)
        #expect(root.priorityHost.state.priority?.id == priorityID)
        #expect(throws: FocusIntentRefusal.noSessionToFinish) { try runner.finishSession() }
        try runner.startSession()
        #expect(root.sessionHost.snapshot?.sessionID != sessionID)
    }

    @Test("an unregistered or released composition refuses instead of reporting success")
    func missingComposition() {
        let center = FocusCommandCenter()
        let runner = FocusIntentRunner(center: center)
        #expect(throws: FocusIntentRefusal.unavailable) { try runner.setPriority("Write proposal") }
        #expect(throws: FocusIntentRefusal.unavailable) { try runner.startSession() }
        var root: AppComposition? = CompositionRootTests.root()
        root?.registerIntentPerformers(on: center)
        root?.stop()
        root = nil
        #expect(throws: FocusIntentRefusal.unavailable) { try runner.setPriority("Write proposal") }
        #expect(throws: FocusIntentRefusal.unavailable) { try runner.startSession() }
    }
}
