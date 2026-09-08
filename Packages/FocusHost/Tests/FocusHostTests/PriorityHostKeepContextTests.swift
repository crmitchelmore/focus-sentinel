import FocusCore
import Foundation
import Testing
@testable import FocusHost

/// **A new priority on the same desk** (focus-1rj7), driven through the live composition root the
/// way the cockpit drives it, and read back from the state the cockpit draws.
@Suite("A new priority that keeps the desk", .serialized)
@MainActor
struct PriorityHostKeepContextTests {
    @Test("the new priority carries every context item and every live rule of the old one")
    func theDeskIsCopied() throws {
        let root = CompositionRootTests.root()
        defer { root.stop() }
        let actions = root.cockpitActions

        actions.setPriority(intent: "Write the Q3 proposal for Acme", doneWhen: "Sent")
        let old = try #require(root.cockpitState.priority)
        actions.addContext(taskID: old.id, item: try #require(ContextItemDraft.keyword("proposal")))
        actions.addContext(taskID: old.id, item: ContextItemDraft(kind: .domain, value: "docs.example.com", displayName: "docs.example.com"))
        actions.addRule(taskID: old.id, scope: .app, subject: "com.apple.Safari", verdict: .relevant)
        actions.addRule(taskID: old.id, scope: .domain, subject: "news.example.com", verdict: .unrelated)
        let desk = try #require(root.cockpitState.priority)
        #expect(desk.contextItems.count == 2)
        #expect(desk.rules.count == 2)

        actions.setPriority(intent: "Draft the Q4 proposal", doneWhen: nil, keepingContextOf: desk.id)

        let new = try #require(root.cockpitState.priority)
        #expect(new.id != desk.id, "the same task was re-pointed rather than a new one set")
        #expect(new.intent == "Draft the Q4 proposal")
        #expect(new.doneWhen == nil)
        #expect(
            new.contextItems.map { "\($0.kind.rawValue)|\($0.value)" }.sorted()
                == desk.contextItems.map { "\($0.kind.rawValue)|\($0.value)" }.sorted(),
            "the desk did not come across whole"
        )
        #expect(
            new.rules.map { "\($0.scope.rawValue)|\($0.subject)|\($0.verdict.rawValue)" }.sorted()
                == desk.rules.map { "\($0.scope.rawValue)|\($0.subject)|\($0.verdict.rawValue)" }.sorted(),
            "the rules did not come across whole"
        )
        // Copies, not moves: every item and rule on the new task has its own identity.
        #expect(Set(new.contextItems.map(\.id)).isDisjoint(with: desk.contextItems.map(\.id)))
        #expect(Set(new.rules.map(\.id)).isDisjoint(with: desk.rules.map(\.id)))
        // And the old priority is still there to come back to, desk intact.
        #expect(root.cockpitState.recent.contains { $0.id == desk.id })
    }

    @Test("naming a task that is not the current priority sets plainly and copies nothing")
    func aStrangerTaskCopiesNothing() throws {
        let root = CompositionRootTests.root()
        defer { root.stop() }
        let actions = root.cockpitActions
        actions.setPriority(intent: "Write the Q3 proposal for Acme", doneWhen: nil)
        let old = try #require(root.cockpitState.priority)
        actions.addContext(taskID: old.id, item: try #require(ContextItemDraft.keyword("proposal")))

        actions.setPriority(intent: "Draft the Q4 proposal", doneWhen: nil, keepingContextOf: UUID())

        let new = try #require(root.cockpitState.priority)
        #expect(new.id != old.id)
        #expect(new.contextItems.isEmpty, "a desk nobody could see was copied")
    }
}
