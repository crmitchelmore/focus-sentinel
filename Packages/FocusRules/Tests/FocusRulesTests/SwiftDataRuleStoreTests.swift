import FocusCore
import Foundation
import SwiftData
import Testing

@testable import FocusRules

/// A rule store, the container that owns its context, and a task to scope rules to.
@MainActor
struct RuleStoreHarness {
    let container: ModelContainer
    let store: SwiftDataRuleStore
    let clock = FixedDateProvider.reference

    init() throws {
        container = try FocusStore.makeContainer(kind: .inMemory)
        store = SwiftDataRuleStore(context: container.mainContext)
    }

    var context: ModelContext { container.mainContext }

    @discardableResult
    func makeTask(_ intent: String) throws -> UUID {
        let task = FocusSchemaV2.PriorityTask(intent: intent, createdAt: clock.now)
        context.insert(task)
        try context.save()
        return task.id
    }

    func task(id: UUID) throws -> FocusSchemaV2.PriorityTask? {
        try context.fetch(FetchDescriptor<FocusSchemaV2.PriorityTask>())
            .first { $0.id == id }
    }

    func storedRuleCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<FocusSchemaV2.RelevanceRule>())
    }

    func rule(
        _ scope: RuleScope,
        _ subject: String,
        _ verdict: RuleVerdict,
        offset: TimeInterval = 0,
        id: UUID = UUID()
    ) -> RelevanceRuleValue {
        RelevanceRuleValue(
            id: id,
            scope: scope,
            subject: subject,
            verdict: verdict,
            createdAt: clock.now.addingTimeInterval(offset)
        )
    }
}

@Suite("SwiftData rule store")
struct SwiftDataRuleStoreTests {
    @Test("insert, read back, and delete")
    @MainActor
    func crud() async throws {
        let harness = try RuleStoreHarness()
        #expect(try await harness.store.allRules().isEmpty)

        let rule = harness.rule(.domain, "news.example", .unrelated)
        try await harness.store.upsert(rule)

        let all = try await harness.store.allRules()
        #expect(all.count == 1)
        #expect(all.first == rule)
        #expect(try await harness.store.rule(for: rule.matchKey) == rule)

        try await harness.store.delete(id: rule.id)
        #expect(try await harness.store.allRules().isEmpty)
        #expect(try harness.storedRuleCount() == 0)
    }

    @Test("deleting a rule that is not there names the identifier")
    @MainActor
    func deletingAnAbsentRule() async throws {
        let harness = try RuleStoreHarness()
        let absent = UUID()
        await #expect(throws: RuleStoreError.notFound(absent)) {
            try await harness.store.delete(id: absent)
        }
    }

    @Test("rules read back oldest first, with the identifier breaking a tie")
    @MainActor
    func ordering() async throws {
        let harness = try RuleStoreHarness()
        let oldest = harness.rule(.app, "com.apple.Safari", .unrelated, offset: 0)
        let middle = harness.rule(.domain, "news.example", .unrelated, offset: 60)
        let newest = harness.rule(.titleToken, "shopping", .unrelated, offset: 120)

        try await harness.store.upsert(newest)
        try await harness.store.upsert(oldest)
        try await harness.store.upsert(middle)

        #expect(try await harness.store.allRules().map(\.id) == [oldest.id, middle.id, newest.id])
    }

    /// Re-deciding about the same subject replaces the old decision. Two contradictory rules
    /// about one subject is not a richer model, it is a store that cannot answer the question.
    @Test("upsert by match key replaces rather than accumulating")
    @MainActor
    func upsertReplaces() async throws {
        let harness = try RuleStoreHarness()

        try await harness.store.upsert(harness.rule(.app, "com.apple.Safari", .unrelated))
        try await harness.store.upsert(harness.rule(.app, "com.apple.Safari", .relevant, offset: 60))

        let all = try await harness.store.allRules()
        #expect(all.count == 1, "a second decision about the same subject accumulated")
        #expect(all.first?.verdict == .relevant)
        #expect(try harness.storedRuleCount() == 1, "a superseded row was left in the store")

        // A different scope is a different subject: "Safari the app" and "Safari the title
        // token" are not the same judgement.
        try await harness.store.upsert(harness.rule(.titleToken, "com.apple.Safari", .unrelated))
        #expect(try await harness.store.allRules().count == 2)
    }

    @Test("updating a rule in place keeps its identifier")
    @MainActor
    func upsertByIdentifierUpdatesInPlace() async throws {
        let harness = try RuleStoreHarness()
        let id = UUID()
        try await harness.store.upsert(harness.rule(.domain, "news.example", .unrelated, id: id))
        try await harness.store.upsert(harness.rule(.domain, "news.example", .relevant, id: id))

        let all = try await harness.store.allRules()
        #expect(all.count == 1)
        #expect(all.first?.id == id)
        #expect(all.first?.verdict == .relevant)
    }

    // MARK: - Scoping

    @Test("a task's rules are not global rules")
    @MainActor
    func perTaskScoping() async throws {
        let harness = try RuleStoreHarness()
        let first = try harness.makeTask("Ship the native shell")
        let second = try harness.makeTask("Ship the one thing")

        let scopedToFirst = harness.rule(.app, "com.apple.dt.Xcode", .relevant)
        let scopedToSecond = harness.rule(.app, "com.apple.dt.Xcode", .unrelated, offset: 60)
        let global = harness.rule(.domain, "news.example", .unrelated, offset: 120)

        try await harness.store.upsert(scopedToFirst, taskID: first)
        try await harness.store.upsert(scopedToSecond, taskID: second)
        try await harness.store.upsert(global, taskID: nil)

        #expect(try await harness.store.rules(forTask: first).map(\.id) == [scopedToFirst.id])
        #expect(try await harness.store.rules(forTask: second).map(\.id) == [scopedToSecond.id])
        #expect(try await harness.store.globalRules().map(\.id) == [global.id])
        #expect(try await harness.store.allRules().count == 3)

        #expect(try await harness.store.taskID(forRule: scopedToFirst.id) == first)
        #expect(try await harness.store.taskID(forRule: global.id) == nil)
    }

    /// The same subject, decided differently for two priorities, must not collapse. "Safari is
    /// unrelated while I am writing the proposal" is not "Safari is unrelated".
    @Test("the same subject can be decided differently in different scopes")
    @MainActor
    func theSameSubjectInTwoScopes() async throws {
        let harness = try RuleStoreHarness()
        let task = try harness.makeTask("Write the proposal")

        try await harness.store.upsert(harness.rule(.app, "com.apple.Safari", .relevant), taskID: nil)
        try await harness.store.upsert(
            harness.rule(.app, "com.apple.Safari", .unrelated, offset: 60),
            taskID: task
        )

        #expect(try await harness.store.allRules().count == 2)
        #expect(try await harness.store.globalRules().first?.verdict == .relevant)
        #expect(try await harness.store.rules(forTask: task).first?.verdict == .unrelated)
    }

    @Test("scoping a rule to a task that does not exist names the task")
    @MainActor
    func scopingToAnAbsentTask() async throws {
        let harness = try RuleStoreHarness()
        let absent = UUID()
        await #expect(throws: RuleStoreError.notFound(absent)) {
            try await harness.store.upsert(
                harness.rule(.domain, "news.example", .unrelated),
                taskID: absent
            )
        }
        #expect(try harness.storedRuleCount() == 0)
    }

    @Test("deleting a task cascades its rules and leaves the global ones")
    @MainActor
    func deletingATaskCascadesItsRules() async throws {
        let harness = try RuleStoreHarness()
        let taskID = try harness.makeTask("Delete me")

        let scoped = harness.rule(.app, "com.apple.dt.Xcode", .relevant)
        let global = harness.rule(.domain, "news.example", .unrelated, offset: 60)
        try await harness.store.upsert(scoped, taskID: taskID)
        try await harness.store.upsert(global, taskID: nil)
        #expect(try await harness.store.allRules().count == 2)

        let task = try #require(try harness.task(id: taskID))
        harness.context.delete(task)
        try harness.context.save()

        #expect(try await harness.store.allRules().map(\.id) == [global.id])
        #expect(try harness.storedRuleCount() == 1)
    }

    // MARK: - Sessions

    @Test("clearing session rules clears only the session ones")
    @MainActor
    func clearSessionRules() async throws {
        let harness = try RuleStoreHarness()
        let taskID = try harness.makeTask("Complete me")

        let session = harness.rule(.session, "com.apple.Safari", .relevant)
        let scopedSession = harness.rule(.session, "news.example", .relevant, offset: 30)
        let app = harness.rule(.app, "com.apple.dt.Xcode", .relevant, offset: 60)
        let domain = harness.rule(.domain, "news.example", .unrelated, offset: 120)

        try await harness.store.upsert(session, taskID: nil)
        try await harness.store.upsert(scopedSession, taskID: taskID)
        try await harness.store.upsert(app, taskID: taskID)
        try await harness.store.upsert(domain, taskID: nil)
        #expect(try await harness.store.allRules().count == 4)

        try await harness.store.clearSessionRules()

        let remaining = try await harness.store.allRules()
        #expect(remaining.count == 2)
        #expect(Set(remaining.map(\.id)) == [app.id, domain.id])
        #expect(!remaining.contains { $0.scope == .session })
    }

    // MARK: - Rows this build cannot read

    @Test("a row written by a newer build is skipped, counted, and never deleted")
    @MainActor
    func unreadableRowsAreSkippedNotDeleted() async throws {
        let harness = try RuleStoreHarness()
        try await harness.store.upsert(harness.rule(.domain, "news.example", .unrelated))

        harness.context.insert(
            FocusSchemaV2.RelevanceRule(
                scopeRaw: "personFromTheFuture",
                subject: "someone",
                verdictRaw: "relevant",
                createdAt: harness.clock.now
            )
        )
        harness.context.insert(
            FocusSchemaV2.RelevanceRule(
                scopeRaw: "domain",
                subject: "example.com",
                verdictRaw: "gloriouslyUndecided",
                createdAt: harness.clock.now
            )
        )
        try harness.context.save()

        #expect(try await harness.store.allRules().count == 1, "an unreadable row was returned")
        #expect(try await harness.store.unreadableRuleCount() == 2)
        // Skipped is not deleted: the rows a newer version wrote are still there for it.
        #expect(try harness.storedRuleCount() == 3)
    }

    @Test("the store survives a reopen with its rules and their scoping intact")
    @MainActor
    func rulesSurviveAReopen() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "focus-rules-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: FocusStore.storeFileName, directoryHint: .notDirectory)
        let clock = FixedDateProvider.reference
        let taskID = UUID()
        let scopedID = UUID()

        do {
            let container = try FocusStore.makeContainer(kind: .temporary(url))
            let context = container.mainContext
            context.insert(
                FocusSchemaV2.PriorityTask(id: taskID, intent: "Persist me", createdAt: clock.now)
            )
            try context.save()

            let store = SwiftDataRuleStore(context: context)
            try await store.upsert(
                RelevanceRuleValue(
                    id: scopedID,
                    scope: .app,
                    subject: "com.apple.dt.Xcode",
                    verdict: .relevant,
                    createdAt: clock.now
                ),
                taskID: taskID
            )
        }

        let reopened = try FocusStore.makeContainer(kind: .temporary(url))
        let store = SwiftDataRuleStore(context: reopened.mainContext)
        #expect(try await store.allRules().map(\.id) == [scopedID])
        #expect(try await store.rules(forTask: taskID).map(\.id) == [scopedID])
        #expect(try await store.globalRules().isEmpty)
    }
}
