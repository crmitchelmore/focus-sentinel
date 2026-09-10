import FocusCore
import Testing

@testable import FocusUI

@Suite("Command shutdown")
@MainActor
struct CommandShutdownTests {
    @Test("shutdown discards pending commands and refuses late scene registration")
    func shutdownIsTerminal() {
        let centre = FocusCommandCenter()
        var calls = 0
        centre.registerCockpitOpener { calls += 1 }
        #expect(centre.send(.newPriority) == .awaitingCockpit)
        #expect(calls == 1)
        centre.observe { _ in calls += 1 }
        centre.registerPrivacyPerformer { _ in calls += 1 }
        centre.registerPriorityWriter { _ in calls += 1; return true }
        centre.shutDown()
        calls = 0

        centre.register { _ in calls += 1 }
        centre.observe { _ in calls += 1 }
        centre.registerCockpitOpener { calls += 1 }
        centre.registerWindowOpener { _ in calls += 1 }
        centre.registerPrivacyPerformer { _ in calls += 1 }
        centre.registerPriorityWriter { _ in calls += 1; return true }
        centre.registerIntentSessionPerformer { _ in calls += 1; return true }

        #expect(centre.send(.newPriority) == .undeliverable)
        #expect(centre.send(.pauseSession) == .undeliverable)
        #expect(!centre.commitPriority("Late commitment"))
        #expect(!centre.perform(.exportData))
        #expect(!centre.performIntentSession(.startSession))
        #expect(!centre.requestCockpit())
        #expect(!centre.open(.history))
        #expect(calls == 0)
    }
}
