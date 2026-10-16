import Foundation
import SwiftData
import Testing

@testable import FocusCore

/// A store and the container that owns it, kept alive together.
///
/// `ModelContainer` owns `mainContext`; a helper that returned only the context would hand
/// back a context whose container had already been deallocated, which is a crash rather than a
/// test failure.
@MainActor
struct PriorityStoreHarness {
    let container: ModelContainer
    let store: PriorityStore
    let clock: FixedDateProvider

    init(clock: FixedDateProvider = .reference) throws {
        container = try FocusStore.makeContainer(kind: .inMemory)
        self.clock = clock
        store = PriorityStore(context: container.mainContext, dateProvider: clock)
    }

    var context: ModelContext { container.mainContext }

    func pointers() throws -> [FocusSchemaV3.ActivePriority] {
        try context.fetch(FetchDescriptor<FocusSchemaV3.ActivePriority>())
    }

    func tasks() throws -> [FocusSchemaV3.PriorityTask] {
        try context.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>())
    }

    func contextItems() throws -> [FocusSchemaV3.ContextItem] {
        try context.fetch(FetchDescriptor<FocusSchemaV3.ContextItem>())
    }

    func rules() throws -> [FocusSchemaV3.RelevanceRule] {
        try context.fetch(FetchDescriptor<FocusSchemaV3.RelevanceRule>())
    }
}

@Suite("Priority store")
struct PriorityStoreTests {
    @Test("setting a priority creates the task, activates it and stamps lastActivatedAt")
    @MainActor
    func setPriorityCreatesAndActivates() throws {
        let harness = try PriorityStoreHarness()
        let id = try harness.store.setPriority(
            intent: "  Finish and submit the Q3 proposal  ",
            doneWhen: "The proposal is submitted"
        )

        let task = try #require(try harness.store.task(id: id))
        // The intent is trimmed but otherwise the user's own words, unaltered.
        #expect(task.intent == "Finish and submit the Q3 proposal")
        #expect(task.doneWhen == "The proposal is submitted")
        #expect(task.revision == 1)
        #expect(task.isActive == true)
        #expect(task.lastActivatedAt == harness.clock.now)
        #expect(try harness.store.activePointerCount() == 1)
        #expect(try harness.store.activeTask()?.id == id)
    }

    @Test("an empty intent is the one thing capture refuses")
    @MainActor
    func emptyIntentIsRefused() throws {
        let harness = try PriorityStoreHarness()
        #expect(throws: PriorityStoreError.emptyIntent) {
            _ = try harness.store.setPriority(intent: "   \n\t ")
        }
        #expect(try harness.tasks().isEmpty)
    }

    /// Counted, not hoped for. The pointer's `persistentModelID` is the identity of the *row*;
    /// if activation ever inserted a second one, this value would change and the count would
    /// have been two at some point in between.
    @Test("activate re-points the same pointer row and never inserts a second")
    @MainActor
    func activateRePointsRatherThanInserting() throws {
        let harness = try PriorityStoreHarness()
        let first = try harness.store.setPriority(intent: "First")
        let second = try harness.store.createTask(intent: "Second")

        let originalPointerID = try #require(try harness.store.activePointer()).persistentModelID

        try harness.store.activate(taskID: second)
        #expect(try harness.store.activePointerCount() == 1)
        #expect(try #require(try harness.store.activePointer()).persistentModelID == originalPointerID)

        try harness.store.activate(taskID: first)
        #expect(try harness.store.activePointerCount() == 1)
        #expect(try #require(try harness.store.activePointer()).persistentModelID == originalPointerID)

        // Re-activating the task that is already active: an ordinary user action, and a
        // process fatal error if it were implemented as an insert (probe P-46).
        try harness.store.activate(taskID: first)
        #expect(try harness.store.activePointerCount() == 1)
        #expect(try harness.store.activeTask()?.id == first)
        #expect(try harness.tasks().count == 2)
    }

    @Test("work on this again re-points at the existing row and clears completedAt")
    @MainActor
    func workOnThisAgainDoesNotCopy() throws {
        let harness = try PriorityStoreHarness()
        let id = try harness.store.setPriority(intent: "Ship the native shell")
        try harness.store.addContextItem(
            taskID: id,
            kindRaw: "app",
            value: "com.apple.dt.Xcode",
            displayName: "Xcode"
        )
        try harness.store.complete(taskID: id, shipped: "the shell")
        #expect(try harness.store.task(id: id)?.completedAt != nil)
        #expect(try harness.store.activePointerCount() == 0)

        try harness.store.activate(taskID: id)

        let task = try #require(try harness.store.task(id: id))
        #expect(task.completedAt == nil)
        #expect(task.isActive == true)
        // The stored pack came back by construction: nothing was copied, so nothing was lost.
        #expect(task.contextItems.count == 1)
        #expect(task.shipped == "the shell")
        #expect(try harness.tasks().count == 1, "activating again must not clone the task")
    }

    @Test("clearing the priority deletes the pointer and keeps the task")
    @MainActor
    func clearKeepsTheTask() throws {
        let harness = try PriorityStoreHarness()
        let id = try harness.store.setPriority(intent: "Clear me")

        try harness.store.clearPriority()

        #expect(try harness.store.activePointerCount() == 0)
        #expect(try harness.store.task(id: id)?.isActive == false)
        #expect(try harness.tasks().count == 1)
    }

    @Test("editing the intent and the definition of done bumps the revision")
    @MainActor
    func editsBumpRevision() throws {
        let harness = try PriorityStoreHarness()
        let id = try harness.store.setPriority(intent: "Draft the proposal")

        try harness.store.editIntent(taskID: id, to: "Finish the proposal")
        #expect(try harness.store.task(id: id)?.intent == "Finish the proposal")
        #expect(try harness.store.task(id: id)?.revision == 2)

        try harness.store.editDoneWhen(taskID: id, to: "It is submitted")
        #expect(try harness.store.task(id: id)?.doneWhen == "It is submitted")
        #expect(try harness.store.task(id: id)?.revision == 3)

        // An empty definition of done is no definition of done, not an empty string.
        try harness.store.editDoneWhen(taskID: id, to: "   ")
        #expect(try harness.store.task(id: id)?.doneWhen == nil)
    }

    @Test("repeated autosaves of unchanged wording add neither revisions nor undo entries")
    @MainActor
    func unchangedIntentIsNotWritten() throws {
        let harness = try PriorityStoreHarness()
        let id = try harness.store.setPriority(intent: "Draft the proposal")
        let undo = UndoManager()
        undo.groupsByEvent = false
        let mutations = PriorityStore.mutationCount

        try harness.store.editIntent(taskID: id, to: "Draft the proposal", undo: undo)
        try harness.store.editIntent(taskID: id, to: "  Draft the proposal  ", undo: undo)

        #expect(try harness.store.task(id: id)?.revision == 1)
        #expect(PriorityStore.mutationCount == mutations)
        #expect(!undo.canUndo)
    }

    @Test("autosaved wording preserves the task, its context, rules and timebox and remains undoable")
    @MainActor
    func wordingEditsKeepTheTaskIntact() throws {
        let harness = try PriorityStoreHarness()
        let id = try harness.store.setPriority(
            intent: "Draft the proposal", doneWhen: "The proposal is submitted"
        )
        let itemID = try harness.store.addContextItem(
            taskID: id, kindRaw: "app", value: "com.apple.dt.Xcode", displayName: "Xcode"
        )
        let ruleID = try harness.store.addRule(
            taskID: id, scopeRaw: "app", subject: "com.apple.dt.Xcode", verdictRaw: "relevant"
        )
        try harness.store.setTimebox(taskID: id, seconds: 1_500)
        let originalRevision = try #require(try harness.store.task(id: id)).revision
        let undo = UndoManager()
        undo.groupsByEvent = false

        try harness.store.editIntent(taskID: id, to: "Submit the proposal", undo: undo)

        let task = try #require(try harness.store.activeTask())
        #expect(task.id == id)
        #expect(task.intent == "Submit the proposal")
        #expect(task.revision == originalRevision + 1)
        #expect(task.doneWhen == "The proposal is submitted")
        #expect(task.contextItems.map(\.id) == [itemID])
        #expect(task.rules.map(\.id) == [ruleID])
        #expect(task.timeboxSeconds == 1_500)
        #expect(task.startedAt == harness.clock.now)
        #expect(try harness.tasks().count == 1)

        undo.undo()
        #expect(task.intent == "Draft the proposal")
        #expect(task.revision == originalRevision)
        #expect(try harness.store.activeTask()?.id == id)
    }

    @Test("setting a timebox stamps startedAt from the injected clock; clearing removes both")
    @MainActor
    func timeboxUsesTheInjectedClock() throws {
        let harness = try PriorityStoreHarness()
        let id = try harness.store.setPriority(intent: "Timebox me")

        try harness.store.setTimebox(taskID: id, seconds: 1_500)
        #expect(try harness.store.task(id: id)?.timeboxSeconds == 1_500)
        #expect(try harness.store.task(id: id)?.startedAt == harness.clock.now)

        try harness.store.setTimebox(taskID: id, seconds: nil)
        #expect(try harness.store.task(id: id)?.timeboxSeconds == nil)
        #expect(try harness.store.task(id: id)?.startedAt == nil)
    }

    @Test("completion writes completedAt, deletes the pointer and clears session rules")
    @MainActor
    func completionClearsSessionRulesOnly() throws {
        let harness = try PriorityStoreHarness()
        let id = try harness.store.setPriority(intent: "Complete me")

        try harness.store.addRule(
            taskID: nil,
            scopeRaw: PriorityStore.sessionRuleScopeRaw,
            subject: "news.example",
            verdictRaw: "unrelated"
        )
        try harness.store.addRule(
            taskID: id,
            scopeRaw: "app",
            subject: "com.apple.dt.Xcode",
            verdictRaw: "relevant"
        )
        try harness.store.addRule(
            taskID: nil,
            scopeRaw: "domain",
            subject: "developer.apple.com",
            verdictRaw: "relevant"
        )
        #expect(try harness.rules().count == 3)

        try harness.store.complete(taskID: id, shipped: "  the thing  ", restartPoint: nil)

        let task = try #require(try harness.store.task(id: id))
        #expect(task.completedAt == harness.clock.now)
        #expect(task.shipped == "the thing")
        // An untouched reflection field stays nil rather than becoming "".
        #expect(task.restartPoint == nil)
        #expect(try harness.store.activePointerCount() == 0)

        let remaining = try harness.rules()
        #expect(remaining.count == 2)
        #expect(!remaining.contains { $0.scopeRaw == PriorityStore.sessionRuleScopeRaw })
    }

    @Test("completion is possible with both reflection fields empty")
    @MainActor
    func completionNeedsNoReflection() throws {
        let harness = try PriorityStoreHarness()
        let id = try harness.store.setPriority(intent: "Just finish it")

        try harness.store.complete(taskID: id)

        let task = try #require(try harness.store.task(id: id))
        #expect(task.completedAt == harness.clock.now)
        #expect(task.shipped == nil)
        #expect(task.restartPoint == nil)
    }

    @Test("context items round-trip, and removing one leaves the rest")
    @MainActor
    func contextItemsRoundTrip() throws {
        let harness = try PriorityStoreHarness()
        let id = try harness.store.setPriority(intent: "Pack some context")

        let app = try harness.store.addContextItem(
            taskID: id,
            kindRaw: "app",
            value: "com.apple.dt.Xcode",
            displayName: "Xcode"
        )
        try harness.store.addContextItem(
            taskID: id,
            kindRaw: "domain",
            value: "https://developer.apple.com",
            displayName: "developer.apple.com"
        )
        try harness.store.addContextItem(
            taskID: id,
            kindRaw: "keyword",
            value: "swiftdata",
            displayName: "swiftdata"
        )
        try harness.store.addContextItem(
            taskID: id,
            kindRaw: "file",
            value: "/tmp/notes.md",
            displayName: "notes.md",
            bookmark: Data([0x01, 0x02, 0x03])
        )
        #expect(try harness.store.task(id: id)?.contextItems.count == 4)

        let file = try #require(try harness.contextItems().first { $0.kindRaw == "file" })
        #expect(file.bookmark == Data([0x01, 0x02, 0x03]))
        #expect(file.addedAt == harness.clock.now)

        try harness.store.removeContextItem(id: app)
        #expect(try harness.store.task(id: id)?.contextItems.count == 3)
        #expect(try harness.store.contextItem(id: app) == nil)
    }

    @Test("rules are global or scoped to exactly one task, and a verdict can be changed")
    @MainActor
    func rulesScopeAndChange() throws {
        let harness = try PriorityStoreHarness()
        let id = try harness.store.setPriority(intent: "Scope some rules")

        let scoped = try harness.store.addRule(
            taskID: id,
            scopeRaw: "app",
            subject: "com.apple.Safari",
            verdictRaw: "unrelated"
        )
        let global = try harness.store.addRule(
            taskID: nil,
            scopeRaw: "domain",
            subject: "news.example",
            verdictRaw: "unrelated"
        )

        #expect(try harness.store.rule(id: scoped)?.task?.id == id)
        #expect(try harness.store.rule(id: global)?.task == nil)
        #expect(try harness.store.task(id: id)?.rules.count == 1)

        try harness.store.changeRule(id: scoped, verdictRaw: "relevant")
        #expect(try harness.store.rule(id: scoped)?.verdictRaw == "relevant")

        try harness.store.removeRule(id: global)
        #expect(try harness.store.rule(id: global) == nil)
        #expect(try harness.rules().count == 1)
    }

    @Test("deleting a task cascades its context items, its rules and its pointer")
    @MainActor
    func deleteCascades() throws {
        let harness = try PriorityStoreHarness()
        let id = try harness.store.setPriority(intent: "Delete me")
        try harness.store.addContextItem(
            taskID: id,
            kindRaw: "keyword",
            value: "cascade",
            displayName: "cascade"
        )
        try harness.store.addRule(
            taskID: id,
            scopeRaw: "app",
            subject: "com.apple.dt.Xcode",
            verdictRaw: "relevant"
        )
        let survivor = try harness.store.addRule(
            taskID: nil,
            scopeRaw: "domain",
            subject: "news.example",
            verdictRaw: "unrelated"
        )

        try harness.store.deleteTask(id: id)

        #expect(try harness.tasks().isEmpty)
        #expect(try harness.contextItems().isEmpty)
        #expect(try harness.store.activePointerCount() == 0)
        // A global rule is nobody's child and must survive.
        #expect(try harness.rules().map(\.id) == [survivor])
    }

    @Test("every operation names the row it cannot find")
    @MainActor
    func missingRowsAreNamed() throws {
        let harness = try PriorityStoreHarness()
        let absent = UUID()

        #expect(throws: PriorityStoreError.taskNotFound(absent)) {
            try harness.store.activate(taskID: absent)
        }
        #expect(throws: PriorityStoreError.taskNotFound(absent)) {
            try harness.store.editIntent(taskID: absent, to: "anything")
        }
        #expect(throws: PriorityStoreError.contextItemNotFound(absent)) {
            try harness.store.removeContextItem(id: absent)
        }
        #expect(throws: PriorityStoreError.ruleNotFound(absent)) {
            try harness.store.removeRule(id: absent)
        }
        #expect(throws: PriorityStoreError.ruleNotFound(absent)) {
            try harness.store.changeRule(id: absent, verdictRaw: "relevant")
        }
    }

    @Test("history is ordered by lastActivatedAt, newest first, never-activated last")
    @MainActor
    func historyOrdering() throws {
        let harness = try PriorityStoreHarness()
        let first = try harness.store.setPriority(intent: "First")
        let second = try harness.store.setPriority(intent: "Second")
        let never = try harness.store.createTask(intent: "Never activated")

        // Re-activate the first one so it becomes the most recent.
        let later = PriorityStore(
            context: harness.context,
            dateProvider: FixedDateProvider(now: harness.clock.now.addingTimeInterval(600))
        )
        try later.activate(taskID: first)

        let ordered = try harness.store.recentTasks().map(\.id)
        #expect(ordered == [first, second, never])
        #expect(try harness.store.recentTasks(limit: 2).map(\.id) == [first, second])
    }

    /// **The order and the limit are the store's, and the `nil` placement is checked** (focus-tzj.2).
    ///
    /// `recentTasks(limit:)` used to fetch every row in the table and sort them in Swift, with a
    /// doc comment saying that was deliberate: the placement of a never-activated task should be
    /// a decision rather than whatever SQLite felt like. The descriptor carries the sort and the
    /// limit now — the tick reads eight rows instead of all of them — and that trade is only safe
    /// if the store really does order `nil` last under a reverse sort. So this asks it, with more
    /// never-activated rows than the limit and the limit cutting **through** them: a store that
    /// put `nil` first would answer with a page of never-activated tasks and this goes red.
    ///
    /// The counter is read across the call because "it no longer fetches the whole table" and "it
    /// makes one round trip" are different claims, and the second one is the one a tick pays.
    @Test("the history's order and its limit are the store's, with never-activated rows last")
    @MainActor
    func historyOrderingAndLimitComeFromTheStore() throws {
        let harness = try PriorityStoreHarness()
        // Three never-activated rows, created first, so a store that ordered `nil` before the
        // activated rows would have them at the head of every page below.
        let neverA = try harness.store.createTask(intent: "Never A")
        let neverB = try harness.store.createTask(intent: "Never B")
        let neverC = try harness.store.createTask(intent: "Never C")
        let older = try harness.store.setPriority(intent: "Older")
        let newer = try harness.store.setPriority(intent: "Newer")
        let newest = PriorityStore(
            context: harness.context,
            dateProvider: FixedDateProvider(now: harness.clock.now.addingTimeInterval(900))
        )
        try newest.activate(taskID: older)

        #expect(try harness.store.recentTasks(limit: 2).map(\.id) == [older, newer])
        // The limit cuts through the never-activated block: three of them exist, one is in the
        // page. Which one is settled by the total order, so the page is stable rather than
        // whatever the store returned.
        let page = try harness.store.recentTasks(limit: 3).map(\.id)
        #expect(page.count == 3)
        #expect(Array(page.prefix(2)) == [older, newer])
        #expect([neverA, neverB, neverC].contains(page[2]))

        StoreFetchCounter.reset()
        _ = try harness.store.recentTasks(limit: 8)
        #expect(
            StoreFetchCounter.count == 1,
            "the history cost \(StoreFetchCounter.count) fetches, and it is one round trip"
        )
    }
}
