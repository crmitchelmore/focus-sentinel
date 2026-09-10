import Foundation
import SwiftData
import Testing

@testable import FocusCore

/// The domain-level undo journal (F-93).
///
/// Every one of these runs with `groupsByEvent = false`, which is the headless case: without
/// the facade opening its own group, `registerUndo` raises
/// `NSInternalInconsistencyException: … must begin a group before registering undo`. The app
/// runs with `groupsByEvent = true`. The grouping lives inside `PriorityStore` precisely so
/// that the same code is correct in both lanes.
@Suite("Undo journal")
struct UndoJournalTests {
    /// A manager configured the way a headless test gets one.
    private func makeUndoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.levelsOfUndo = 0
        return undo
    }

    // MARK: - The activation swap, which is the case SwiftData's own undo got wrong

    @Test("undo of an activation restores the previous priority, not no priority")
    @MainActor
    func undoOfActivationRestoresThePrevious() throws {
        let harness = try PriorityStoreHarness()
        let undo = makeUndoManager()

        let first = try harness.store.setPriority(intent: "First", undo: undo)
        let second = try harness.store.createTask(intent: "Second", undo: undo)
        try harness.store.activate(taskID: second, undo: undo)
        #expect(try harness.store.activeTask()?.id == second)

        undo.undo()

        // The failure mode this exists to prevent: SwiftData's context undo left *nothing*
        // active here (probe P-48).
        #expect(try harness.store.activeTask()?.id == first)
        #expect(try harness.store.activePointerCount() == 1)
        #expect(try harness.tasks().count == 2)

        undo.redo()
        #expect(try harness.store.activeTask()?.id == second)
        #expect(try harness.store.activePointerCount() == 1)
    }

    @Test("undo of setting a priority removes the new task and restores the old activation")
    @MainActor
    func undoOfSetPriority() throws {
        let harness = try PriorityStoreHarness()
        let undo = makeUndoManager()

        let first = try harness.store.setPriority(intent: "First", undo: undo)
        let second = try harness.store.setPriority(intent: "Second", undo: undo)
        #expect(try harness.tasks().count == 2)

        undo.undo()
        #expect(try harness.store.task(id: second) == nil)
        #expect(try harness.store.activeTask()?.id == first)
        #expect(try harness.tasks().count == 1)

        undo.redo()
        #expect(try harness.tasks().count == 2)
        #expect(try harness.store.activeTask()?.intent == "Second")
    }

    @Test("undo of clearing the priority puts the same task back")
    @MainActor
    func undoOfClear() throws {
        let harness = try PriorityStoreHarness()
        let undo = makeUndoManager()

        let id = try harness.store.setPriority(intent: "Clear me", undo: undo)
        try harness.store.clearPriority(undo: undo)
        #expect(try harness.store.activePointerCount() == 0)

        undo.undo()
        #expect(try harness.store.activeTask()?.id == id)

        undo.redo()
        #expect(try harness.store.activePointerCount() == 0)
    }

    // MARK: - Editing

    @Test("undo of an intent edit restores the previous words and the previous revision")
    @MainActor
    func undoOfIntentEdit() throws {
        let harness = try PriorityStoreHarness()
        let undo = makeUndoManager()

        let id = try harness.store.setPriority(intent: "Draft the proposal", undo: undo)
        try harness.store.editIntent(taskID: id, to: "Finish the proposal", undo: undo)
        #expect(try harness.store.task(id: id)?.revision == 2)

        undo.undo()
        #expect(try harness.store.task(id: id)?.intent == "Draft the proposal")
        // A revision that keeps climbing through undo would keep invalidating a cache that
        // is looking at wording it has already seen.
        #expect(try harness.store.task(id: id)?.revision == 1)

        undo.redo()
        #expect(try harness.store.task(id: id)?.intent == "Finish the proposal")
        #expect(try harness.store.task(id: id)?.revision == 2)
    }

    @Test("undo of a done-when edit restores the previous criterion, including nil")
    @MainActor
    func undoOfDoneWhenEdit() throws {
        let harness = try PriorityStoreHarness()
        let undo = makeUndoManager()

        let id = try harness.store.setPriority(intent: "Do the thing", undo: undo)
        try harness.store.editDoneWhen(taskID: id, to: "It is submitted", undo: undo)
        undo.undo()
        #expect(try harness.store.task(id: id)?.doneWhen == nil)

        undo.redo()
        #expect(try harness.store.task(id: id)?.doneWhen == "It is submitted")
    }

    @Test("undo of a timebox change restores both the duration and the start")
    @MainActor
    func undoOfTimebox() throws {
        let harness = try PriorityStoreHarness()
        let undo = makeUndoManager()

        let id = try harness.store.setPriority(intent: "Timebox me", undo: undo)
        try harness.store.setTimebox(taskID: id, seconds: 1_500, undo: undo)
        try harness.store.setTimebox(taskID: id, seconds: 3_000, undo: undo)

        undo.undo()
        #expect(try harness.store.task(id: id)?.timeboxSeconds == 1_500)

        undo.undo()
        #expect(try harness.store.task(id: id)?.timeboxSeconds == nil)
        #expect(try harness.store.task(id: id)?.startedAt == nil)

        undo.redo()
        #expect(try harness.store.task(id: id)?.timeboxSeconds == 1_500)
    }

    // MARK: - Completion

    @Test("undo of completion restores the active pointer, the reflection and the session rules")
    @MainActor
    func undoOfCompletion() throws {
        let harness = try PriorityStoreHarness()
        let undo = makeUndoManager()

        let id = try harness.store.setPriority(intent: "Complete me", undo: undo)
        let sessionRule = try harness.store.addRule(
            taskID: nil,
            scopeRaw: PriorityStore.sessionRuleScopeRaw,
            subject: "news.example",
            verdictRaw: "unrelated",
            undo: undo
        )
        try harness.store.complete(taskID: id, shipped: "the thing", undo: undo)
        #expect(try harness.store.rule(id: sessionRule) == nil)
        #expect(try harness.store.activePointerCount() == 0)

        undo.undo()

        let task = try #require(try harness.store.task(id: id))
        #expect(task.completedAt == nil)
        #expect(task.shipped == nil)
        #expect(task.isActive == true)
        #expect(try harness.store.rule(id: sessionRule)?.subject == "news.example")

        undo.redo()
        #expect(try harness.store.task(id: id)?.completedAt != nil)
        #expect(try harness.store.rule(id: sessionRule) == nil)
        #expect(try harness.store.activePointerCount() == 0)
    }

    // MARK: - The context pack and rules

    @Test("undo of adding and removing a context item round-trips both ways")
    @MainActor
    func undoOfContextItems() throws {
        let harness = try PriorityStoreHarness()
        let undo = makeUndoManager()

        let id = try harness.store.setPriority(intent: "Pack some context", undo: undo)
        let item = try harness.store.addContextItem(
            taskID: id,
            kindRaw: "file",
            value: "/tmp/notes.md",
            displayName: "notes.md",
            bookmark: Data([0xAB]),
            undo: undo
        )
        undo.undo()
        #expect(try harness.store.contextItem(id: item) == nil)

        undo.redo()
        let restored = try #require(try harness.store.contextItem(id: item))
        #expect(restored.bookmark == Data([0xAB]))

        try harness.store.removeContextItem(id: item, undo: undo)
        #expect(try harness.store.contextItem(id: item) == nil)

        undo.undo()
        let again = try #require(try harness.store.contextItem(id: item))
        #expect(again.displayName == "notes.md")
        #expect(again.task?.id == id)
    }

    @Test("undo of a rule change restores the previous verdict")
    @MainActor
    func undoOfRuleChange() throws {
        let harness = try PriorityStoreHarness()
        let undo = makeUndoManager()

        let id = try harness.store.setPriority(intent: "Rule me", undo: undo)
        let rule = try harness.store.addRule(
            taskID: id,
            scopeRaw: "app",
            subject: "com.apple.Safari",
            verdictRaw: "unrelated",
            undo: undo
        )
        try harness.store.changeRule(id: rule, verdictRaw: "relevant", undo: undo)

        undo.undo()
        #expect(try harness.store.rule(id: rule)?.verdictRaw == "unrelated")

        undo.redo()
        #expect(try harness.store.rule(id: rule)?.verdictRaw == "relevant")

        try harness.store.removeRule(id: rule, undo: undo)
        undo.undo()
        #expect(try harness.store.rule(id: rule)?.subject == "com.apple.Safari")
        #expect(try harness.store.rule(id: rule)?.task?.id == id)
    }

    // MARK: - The destructive delete

    @Test("undo of a delete restores the row, its context items, its rules and its pointer")
    @MainActor
    func undoOfDeleteRestoresEverything() throws {
        let harness = try PriorityStoreHarness()
        let undo = makeUndoManager()

        let id = try harness.store.setPriority(
            intent: "Delete me",
            doneWhen: "It is gone",
            undo: undo
        )
        try harness.store.addContextItem(
            taskID: id,
            kindRaw: "keyword",
            value: "cascade",
            displayName: "cascade",
            undo: undo
        )
        try harness.store.addContextItem(
            taskID: id,
            kindRaw: "app",
            value: "com.apple.dt.Xcode",
            displayName: "Xcode",
            undo: undo
        )
        try harness.store.addRule(
            taskID: id,
            scopeRaw: "app",
            subject: "com.apple.dt.Xcode",
            verdictRaw: "relevant",
            undo: undo
        )
        try harness.store.setTimebox(taskID: id, seconds: 1_500, undo: undo)

        try harness.store.deleteTask(id: id, undo: undo)
        #expect(try harness.tasks().isEmpty)
        #expect(try harness.store.activePointerCount() == 0)

        undo.undo()

        let task = try #require(try harness.store.task(id: id))
        #expect(task.intent == "Delete me")
        #expect(task.doneWhen == "It is gone")
        #expect(task.timeboxSeconds == 1_500)
        #expect(task.contextItems.count == 2)
        #expect(Set(task.contextItems.map(\.displayName)) == ["cascade", "Xcode"])
        #expect(task.rules.count == 1)
        // It was the active priority when it was deleted, so it is the active priority again.
        #expect(task.isActive == true)
        #expect(try harness.store.activePointerCount() == 1)

        undo.redo()
        #expect(try harness.tasks().isEmpty)
        #expect(try harness.contextItems().isEmpty)
    }

    // MARK: - Depth and ordering

    @Test("three-deep undo walks back in order, and redo walks forward again")
    @MainActor
    func threeDeepUndoWalksBackInOrder() throws {
        let harness = try PriorityStoreHarness()
        let undo = makeUndoManager()

        try harness.store.setPriority(intent: "one", undo: undo)
        try harness.store.setPriority(intent: "two", undo: undo)
        try harness.store.setPriority(intent: "three", undo: undo)
        #expect(try harness.store.activeTask()?.intent == "three")

        undo.undo()
        #expect(try harness.store.activeTask()?.intent == "two")
        #expect(try harness.tasks().count == 2)

        undo.undo()
        #expect(try harness.store.activeTask()?.intent == "one")
        #expect(try harness.tasks().count == 1)

        undo.undo()
        #expect(try harness.store.activeTask() == nil)
        #expect(try harness.tasks().isEmpty)

        undo.redo()
        #expect(try harness.store.activeTask()?.intent == "one")
        undo.redo()
        #expect(try harness.store.activeTask()?.intent == "two")
        undo.redo()
        #expect(try harness.store.activeTask()?.intent == "three")
        #expect(try harness.tasks().count == 3)
    }

    @Test("nothing is registered when no UndoManager is supplied")
    @MainActor
    func withoutAnUndoManagerNothingIsRegistered() throws {
        let harness = try PriorityStoreHarness()
        let undo = makeUndoManager()

        try harness.store.setPriority(intent: "unjournalled", undo: nil)
        #expect(undo.canUndo == false)
        #expect(try harness.tasks().count == 1)
    }

    // MARK: - Action names

    @Test("every action name has a catalog key with three components")
    func actionNameKeysAreWellFormed() {
        #expect(UndoActionName.allCases.count == 14)
        for name in UndoActionName.allCases {
            #expect(name.key.hasPrefix("undo."))
            #expect(name.key.filter { $0 == "." }.count >= 2, "\(name.key) is not <namespace>.<surface>.<element>")
        }
        #expect(Set(UndoActionName.allCases.map(\.key)).count == UndoActionName.allCases.count)
    }

    /// Lane-gated, per e01's R-09: under `swift test` SwiftPM copies the String Catalog
    /// instead of compiling it, so every lookup returns its own key. This assertion is only
    /// meaningful — and is therefore only run — in the gate lane.
    @Test(
        "action names resolve to real text, not to their own keys",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func actionNamesResolve() {
        for name in UndoActionName.allCases {
            #expect(name.localizedName != name.key, "\(name.key) echoed its key")
            #expect(!name.localizedName.isEmpty)
        }
        // The one the self-check reads out of the live Edit menu (probe P-50).
        #expect(UndoActionName.changePriority.localizedName == "Change priority")
    }

    @Test("the Edit menu reads the action name of the operation just performed")
    @MainActor
    func undoManagerCarriesTheActionName() throws {
        let harness = try PriorityStoreHarness()
        let undo = makeUndoManager()

        let id = try harness.store.setPriority(intent: "First", undo: undo)
        let second = try harness.store.createTask(intent: "Second", undo: undo)
        try harness.store.activate(taskID: second, undo: undo)

        #expect(undo.canUndo)
        #expect(undo.undoActionName == UndoActionName.changePriority.localizedName)
        #expect(undo.undoMenuItemTitle.contains(UndoActionName.changePriority.localizedName))

        undo.undo()
        #expect(undo.canRedo)
        #expect(undo.redoActionName == UndoActionName.changePriority.localizedName)
        #expect(try harness.store.activeTask()?.id == id)
    }

    // MARK: - The ban, asserted at source level as well as in the lint

    /// `scripts/check-forbidden.sh` bans this repository-wide. The suite asserts it too, so
    /// that a developer running the unit lane alone still finds out.
    @Test("ModelContext.undoManager is assigned nowhere in FocusCore")
    func modelContextUndoManagerIsNeverAssigned() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // FocusCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // FocusCore (package)
            .appending(path: "Sources", directoryHint: .isDirectory)

        let enumerator = try #require(
            FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        )

        var offenders: [String] = []
        var scanned = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            scanned += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                if trimmed.contains(".undoManager") && trimmed.contains("=")
                    && !trimmed.contains("==") {
                    offenders.append("\(url.lastPathComponent): \(trimmed)")
                }
            }
        }

        #expect(scanned > 0, "the source scan found no Swift files — the path is wrong")
        #expect(offenders.isEmpty, "undo is the PriorityStore journal, never SwiftData's: \(offenders)")
    }
}
