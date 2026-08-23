import Foundation
import SwiftData
import Testing

@testable import FocusCore

/// The single-active-priority invariant, proved against the store rather than against a code
/// path.
///
/// The shape under test is the one the probes pinned down (P-44…P-47):
///
/// * the unique attribute lives on `ActivePriority.slot`, never on `PriorityTask` — a unique
///   collision in SwiftData is resolved by **merging whole rows**, so putting the constraint
///   on the task itself would make every priority swap silently delete the previous task and
///   destroy the history F-15 is made of;
/// * the application **re-points** the one pointer row and never inserts a second one, because
///   inserting a colliding row whose target already owns a pointer is a *process fatal error*
///   ("This relationship already has a value but it's not the target") — and re-activating
///   your current priority is an ordinary thing for a person to do;
/// * the constraint stays as the store-level backstop that keeps the invariant true even
///   against a bug, which is what the deliberate-double-insert case below measures.
@Suite("The single-active-priority invariant")
struct ActivePriorityInvariantTests {
    private let clock = FixedDateProvider.reference

    /// The shipping algorithm, in miniature: one row, re-pointed, never re-inserted.
    /// `PriorityStore.activate(_:)` is this, with an undo journal around it.
    @MainActor
    private func setActivePriority(
        _ task: FocusSchemaV3.PriorityTask?,
        in context: ModelContext,
        at date: Date
    ) throws {
        let pointers = try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>())

        guard let task else {
            for pointer in pointers { context.delete(pointer) }
            try context.save()
            return
        }

        if let pointer = pointers.first {
            // Any stray extras are removed rather than left for the constraint to merge:
            // the app never relies on collision resolution, it only survives it.
            for extra in pointers.dropFirst() { context.delete(extra) }
            pointer.task = task
            pointer.activatedAt = date
        } else {
            context.insert(FocusSchemaV3.ActivePriority(task: task, activatedAt: date))
        }
        try context.save()
    }

    @MainActor
    private func makeTask(
        _ intent: String,
        in context: ModelContext,
        offset: TimeInterval = 0
    ) -> FocusSchemaV3.PriorityTask {
        let task = FocusSchemaV3.PriorityTask(
            intent: intent,
            createdAt: clock.now.addingTimeInterval(offset)
        )
        context.insert(task)
        return task
    }

    @Test("a second activation replaces the pointer and leaves both tasks whole")
    @MainActor
    func replacingPreservesThePreviousTask() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        let first = makeTask("Ship the native shell", in: context)
        let second = makeTask("Ship the one thing", in: context, offset: 60)
        context.insert(
            FocusSchemaV3.ContextItem(
                kindRaw: "app",
                value: "com.apple.dt.Xcode",
                displayName: "Xcode",
                addedAt: clock.now,
                task: first
            )
        )
        try context.save()

        try setActivePriority(first, in: context, at: clock.now)
        #expect(try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>()).count == 1)

        try setActivePriority(second, in: context, at: clock.now.addingTimeInterval(120))

        let pointers = try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>())
        #expect(pointers.count == 1, "activation must replace, never queue")
        #expect(pointers.first?.task?.id == second.id)

        // The whole point of the pointer design: the replaced task keeps every word it had.
        let tasks = try context.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>())
        #expect(tasks.count == 2, "the replaced task was destroyed by the swap")
        #expect(first.intent == "Ship the native shell")
        #expect(first.contextItems.count == 1)
        #expect(first.isActive == false)
        #expect(second.isActive == true)
    }

    @Test("re-activating the current priority does not throw and does not duplicate the row")
    @MainActor
    func rePointingAtTheCurrentTaskIsSafe() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        let task = makeTask("Finish and submit the Q3 proposal", in: context)
        try context.save()

        try setActivePriority(task, in: context, at: clock.now)
        try setActivePriority(task, in: context, at: clock.now.addingTimeInterval(30))
        try setActivePriority(task, in: context, at: clock.now.addingTimeInterval(60))

        let pointers = try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>())
        #expect(pointers.count == 1)
        #expect(pointers.first?.task?.id == task.id)
        #expect(pointers.first?.activatedAt == clock.now.addingTimeInterval(60))
    }

    @Test("clearing the priority deletes the pointer and leaves the task")
    @MainActor
    func clearingDeletesOnlyThePointer() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        let task = makeTask("Write the migration stage", in: context)
        try context.save()
        try setActivePriority(task, in: context, at: clock.now)

        try setActivePriority(nil, in: context, at: clock.now)

        #expect(try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>()).isEmpty)
        let tasks = try context.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>())
        #expect(tasks.count == 1)
        #expect(tasks.first?.isActive == false)
        #expect(tasks.first?.activePointer == nil)
    }

    @Test("deleting the active task cascades its pointer away, leaving nothing dangling")
    @MainActor
    func deletingTheActiveTaskCascadesThePointer() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        let task = makeTask("Delete me", in: context)
        context.insert(
            FocusSchemaV3.ContextItem(
                kindRaw: "keyword",
                value: "migration",
                displayName: "migration",
                addedAt: clock.now,
                task: task
            )
        )
        context.insert(
            FocusSchemaV3.RelevanceRule(
                scopeRaw: "app",
                subject: "com.apple.dt.Xcode",
                verdictRaw: "relevant",
                createdAt: clock.now,
                task: task
            )
        )
        try context.save()
        try setActivePriority(task, in: context, at: clock.now)

        context.delete(task)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FocusSchemaV3.ContextItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FocusSchemaV3.RelevanceRule>()).isEmpty)
    }

    /// The backstop. The app never does this — but a bug might, and the store is what makes
    /// the invariant true anyway. Two pointer rows for two *different* tasks are inserted
    /// deliberately; the unique constraint collapses them to one and no task is lost.
    @Test("two pointer rows inserted deliberately collapse to one, with no task lost")
    @MainActor
    func deliberateDoubleInsertCollapses() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        let first = makeTask("First", in: context)
        let second = makeTask("Second", in: context, offset: 60)
        try context.save()

        context.insert(FocusSchemaV3.ActivePriority(task: first, activatedAt: clock.now))
        context.insert(
            FocusSchemaV3.ActivePriority(task: second, activatedAt: clock.now.addingTimeInterval(1))
        )
        try context.save()

        let pointers = try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>())
        #expect(pointers.count == 1, "the store must never hold two active priorities")

        let tasks = try context.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>())
        #expect(tasks.count == 2, "a pointer collision must never destroy a user's words")
        #expect(Set(tasks.map(\.intent)) == ["First", "Second"])
    }

    @Test("the invariant survives a container reopen, on disk")
    @MainActor
    func invariantSurvivesReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "focus-invariant-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: FocusStore.storeFileName, directoryHint: .notDirectory)
        let secondID = UUID()

        do {
            let container = try FocusStore.makeContainer(kind: .temporary(url))
            let context = container.mainContext
            let first = makeTask("First", in: context)
            let second = FocusSchemaV3.PriorityTask(
                id: secondID,
                intent: "Second",
                createdAt: clock.now.addingTimeInterval(60)
            )
            context.insert(second)
            try context.save()

            try setActivePriority(first, in: context, at: clock.now)
            try setActivePriority(second, in: context, at: clock.now.addingTimeInterval(60))
        }

        let reopened = try FocusStore.makeContainer(kind: .temporary(url))
        let context = reopened.mainContext

        let pointers = try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>())
        #expect(pointers.count == 1)
        #expect(pointers.first?.slot == FocusSchemaV3.ActivePriority.singletonSlot)
        #expect(pointers.first?.task?.id == secondID)
        #expect(try context.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>()).count == 2)
    }

    @Test("isActive is a projection of the pointer and nothing else")
    @MainActor
    func isActiveIsAProjection() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        let task = makeTask("Projected", in: context)
        try context.save()
        #expect(task.isActive == false)

        try setActivePriority(task, in: context, at: clock.now)
        #expect(task.isActive == true)
        #expect(task.activePointer?.task?.id == task.id)

        try setActivePriority(nil, in: context, at: clock.now)
        #expect(task.isActive == false)
    }
}
