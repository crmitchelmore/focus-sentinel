import Foundation
import SwiftData
import Testing
@testable import FocusCore

/// **The standing shortlist: one main priority, two secondary ones** (focus-standing).
@Suite("Standing priorities")
@MainActor
struct StandingPrioritiesTests {
    private func makeUndoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.levelsOfUndo = 0
        return undo
    }

    @Test("a fresh store has no standing priorities")
    func freshIsEmpty() throws {
        let harness = try PriorityStoreHarness()
        #expect(try harness.store.standingPriorities().isEmpty)
    }

    @Test("find-or-create reuses the task with that intent, and creates an inactive one otherwise")
    func findOrCreate() throws {
        let harness = try PriorityStoreHarness()
        let existing = try harness.store.setPriority(intent: "Boulanger qualification")
        #expect(try harness.store.findOrCreateTask(intent: " Boulanger qualification ", doneWhen: "Sent") == existing)
        #expect(try harness.store.task(id: existing)?.doneWhen == "Sent")

        let fresh = try harness.store.findOrCreateTask(intent: "Links pages", doneWhen: nil)
        #expect(fresh != existing)
        #expect(try harness.store.task(id: fresh)?.lastActivatedAt == nil)
        // Setting the shortlist never changes which priority is current.
        #expect(try harness.store.activeTask()?.id == existing)
    }

    @Test("the shortlist is replaced as a whole, in slot order, capped at three and de-duplicated")
    func replacedAsAWhole() throws {
        let harness = try PriorityStoreHarness()
        let ids = try ["A", "B", "C", "D"].map { try harness.store.createTask(intent: $0) }
        try harness.store.setStandingPriorities(taskIDs: [ids[1], ids[1], ids[0], UUID(), ids[2], ids[3]])
        #expect(try harness.store.standingPriorities().map(\.task.intent) == ["B", "A", "C"])
        #expect(try harness.store.standingPriorities().map(\.slot) == [0, 1, 2])

        try harness.store.setStandingPriorities(taskIDs: [ids[3]])
        #expect(try harness.store.standingPriorities().map(\.task.intent) == ["D"])
    }

    @Test("undo puts the previous shortlist back, and redo the new one")
    func undoable() throws {
        let harness = try PriorityStoreHarness()
        let undo = makeUndoManager()
        let a = try harness.store.createTask(intent: "A")
        let b = try harness.store.createTask(intent: "B")
        try harness.store.setStandingPriorities(taskIDs: [a], undo: undo)
        try harness.store.setStandingPriorities(taskIDs: [b, a], undo: undo)
        #expect(undo.undoActionName == UndoActionName.setStanding.localizedName)

        undo.undo()
        #expect(try harness.store.standingPriorities().map(\.task.id) == [a])
        undo.redo()
        #expect(try harness.store.standingPriorities().map(\.task.id) == [b, a])
    }

    @Test("a slot whose task was deleted is skipped, not repaired")
    func deletedTaskIsSkipped() throws {
        let harness = try PriorityStoreHarness()
        let a = try harness.store.createTask(intent: "A")
        let b = try harness.store.createTask(intent: "B")
        try harness.store.setStandingPriorities(taskIDs: [a, b])
        try harness.store.deleteTask(id: a)
        #expect(try harness.store.standingPriorities().map(\.task.id) == [b])
    }
}
