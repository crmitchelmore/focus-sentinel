import FocusCore
import FocusRules
import Foundation
import Testing

@testable import FocusHost

/// **The selected item reaches the judgement, and only from the application it was read in**
/// (issue #24).
///
/// The Accessibility read itself is the platform's and is not driven here: a test process that
/// is trusted for Accessibility would read this Mac's own windows, and one that is not would
/// prove nothing. What is held is everything on either side of it — the reader's refusals, which
/// need no grant, and what the engine does with an item once it has one.
@Suite("A selected item narrows the judgement")
@MainActor
struct SelectedItemJudgementTests {
    static let copilot = "com.github.githubapp"

    static func cleared(_ bundleIdentifier: String) throws -> ClearedActivation {
        try #require(
            SensitivityGate().evaluate(
                FrontmostActivation(
                    bundleIdentifier: bundleIdentifier,
                    pid: 501,
                    at: NudgeHostFixture.reference
                )
            ).clearedActivation
        )
    }

    // MARK: - The reader's refusals

    @Test("a default install reads nothing, not even an attempt")
    func aDefaultInstallReadsNothing() throws {
        let reader = SystemSelectedItemReader()
        #expect(reader.selectedItem(in: try Self.cleared(Self.copilot), optIns: .none) == nil)
        #expect(
            reader.selectedItem(
                in: try Self.cleared(Self.copilot),
                optIns: GrantOptIns(enabled: [.screenCapture])
            ) == nil
        )
        #expect(reader.readCount == 0)
    }

    @Test("an application not on the list is never read, even with the switch on")
    func anUnlistedApplicationIsNeverRead() throws {
        let reader = SystemSelectedItemReader()
        let optedIn = GrantOptIns(enabled: [.accessibilityWindowContext])
        for bundle in ["com.apple.Safari", "com.apple.mail", "com.apple.MobileSMS"] {
            #expect(reader.selectedItem(in: try Self.cleared(bundle), optIns: optedIn) == nil)
        }
        #expect(reader.readCount == 0)
    }

    // MARK: - The subject

    @Test("an item read from another application is dropped, and an item is its own dwell")
    func theSubjectKeepsOnlyItsOwnItem() throws {
        let item = try #require(SelectedItem(bundleIdentifier: Self.copilot, label: "Plan the holiday"))
        let elsewhere = JudgeableSubject(
            bundleIdentifier: "com.microsoft.VSCode", isSuppressed: false, selectedItem: item
        )
        #expect(elsewhere.selectedItem == nil)
        #expect(elsewhere.dwellKey == "com.microsoft.VSCode")

        let here = JudgeableSubject(bundleIdentifier: Self.copilot, isSuppressed: false, selectedItem: item)
        #expect(here.selectedItem == item)
        #expect(here.dwellKey == item.subject)
        #expect(here.dwellKey != JudgeableSubject(bundleIdentifier: Self.copilot, isSuppressed: false).dwellKey)
    }

    // MARK: - End to end through the engine

    /// The rule the question writes, read back by the engine: Copilot is on task, this one chat
    /// in it is not, and the chat beside it is still on task.
    @Test("a rule about one chat decides that chat and leaves the application's rule standing")
    func anItemRuleDecidesItsItem() async throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        let host = RelevanceHost(
            context: context,
            ruleStore: SwiftDataRuleStore(context: context),
            monotonicClock: FixedMonotonicClock(),
            modelRung: nil
        )
        let priorities = PriorityStore(
            context: context,
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference)
        )
        try priorities.setPriority(intent: "Write the Q3 proposal for Acme")
        let taskID = try #require(try priorities.activeTask()?.id)
        let holiday = try #require(SelectedItem(bundleIdentifier: Self.copilot, label: "Plan the holiday"))
        try priorities.addRule(
            taskID: taskID, scopeRaw: "app", subject: Self.copilot, verdictRaw: "relevant"
        )
        try priorities.addRule(
            taskID: taskID, scopeRaw: "titleToken", subject: holiday.subject, verdictRaw: "unrelated"
        )
        host.activeCommitment = { ActiveCommitment(id: taskID, intent: "Write the Q3 proposal for Acme") }
        await host.rebuildSnapshot()

        var published: [NudgeJudgement] = []
        host.onJudgement = { published.append($0) }

        host.observe(
            JudgeableSubject(bundleIdentifier: Self.copilot, isSuppressed: false, selectedItem: holiday),
            phase: .focus,
            isUserIdle: false
        )
        let onHoliday = try #require(published.last)
        #expect(onHoliday.selectedItem == holiday)
        #expect(onHoliday.verdict == .unrelated)

        let race = try #require(SelectedItem(bundleIdentifier: Self.copilot, label: "Fix the login race"))
        host.observe(
            JudgeableSubject(bundleIdentifier: Self.copilot, isSuppressed: false, selectedItem: race),
            phase: .focus,
            isUserIdle: false
        )
        let onRace = try #require(published.last)
        #expect(onRace.selectedItem == race)
        #expect(onRace.verdict == .relevant)

        // A question about this judgement would be about the chat, keyed so its answer files the
        // rule this test began by writing.
        let asked = try #require(NudgeDecider.querySubject(for: onRace))
        #expect(asked.kind == .titleToken)
        #expect(asked.identifier == race.subject)
        #expect(asked.provenance == .selectedItem)
    }
}
