import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusUI

/// **The three intents, driven** (F-141, focus-mn7).
///
/// `AppIntent.perform()` runs inside a process the unit lane does not own, so what is driven here
/// is `FocusIntentRunner` — the whole of what the three intents do, minus three lines of
/// framework shell. That is deliberate rather than convenient: the interesting half of an intent
/// is **when it refuses**, and a refusal that could only be exercised through Shortcuts is a
/// refusal nobody would ever see fail.
///
/// The world and the send are the command host's own in the shipping runner, so an intent and a
/// menu item can never disagree about whether a verb would do anything. Here they are the same
/// two values a menu item reads, supplied by the test.
@Suite("App Intents")
@MainActor
struct FocusIntentTests {
    /// What the runner was asked to do, so a refusal can be told from a silent success.
    final class Recorder {
        var commands: [PriorityCommand] = []
        var committed: [String] = []
    }

    static func runner(
        world: ShellCommandWorld,
        delivery: CommandDelivery = .delivered,
        commits: Bool = true,
        into recorder: Recorder
    ) -> FocusIntentRunner {
        FocusIntentRunner(
            world: { world },
            send: { command in
                recorder.commands.append(command)
                return delivery
            },
            commit: { text in
                recorder.committed.append(text)
                return commits
            }
        )
    }

    // MARK: - Setting the priority

    @Test("setting a priority commits the words the person gave")
    func settingAPriorityCommits() throws {
        let recorder = Recorder()
        let runner = Self.runner(world: .nothingIsCommitted, into: recorder)

        try runner.setPriority("  Write the Q3 proposal  ")

        // Trimmed, because a shortcut that appends a space is not a different commitment.
        #expect(recorder.committed == ["Write the Q3 proposal"])
        #expect(recorder.commands.isEmpty, "setting a priority is not a session command")
    }

    @Test("an empty priority is refused rather than committed")
    func anEmptyPriorityIsRefused() {
        let recorder = Recorder()
        let runner = Self.runner(world: .nothingIsCommitted, into: recorder)

        for text in ["", "   ", "\n\t "] {
            #expect(throws: FocusIntentRefusal.emptyPriority) {
                try runner.setPriority(text)
            }
        }
        #expect(recorder.committed.isEmpty, "a refused intent wrote a commitment anyway")
    }

    @Test("a commit that did not land is a refusal, not a silence")
    func aCommitThatDidNotLandIsARefusal() {
        let recorder = Recorder()
        let runner = Self.runner(world: .nothingIsCommitted, commits: false, into: recorder)

        #expect(throws: FocusIntentRefusal.unavailable) {
            try runner.setPriority("Write the Q3 proposal")
        }
    }

    // MARK: - The two session verbs

    /// **The bead's own refusal**: there is no session, so there is nothing to finish, and an
    /// intent that reported success would be an intent that lied to a shortcut.
    @Test("finishing refuses when there is no session")
    func finishingRefusesWithNoSession() {
        let recorder = Recorder()
        let runner = Self.runner(world: .nothingIsCommitted, into: recorder)

        #expect(throws: FocusIntentRefusal.noSessionToFinish) { try runner.finishSession() }
        #expect(recorder.commands.isEmpty, "a refused intent sent the command anyway")
    }

    @Test("starting refuses when a session is already running")
    func startingRefusesWhenOneIsRunning() {
        let recorder = Recorder()
        let running = ShellCommandWorld(hasPriority: true, sessionPhase: .focus)
        let runner = Self.runner(world: running, into: recorder)

        #expect(throws: FocusIntentRefusal.sessionAlreadyRunning) { try runner.startSession() }
        #expect(recorder.commands.isEmpty)
    }

    @Test("starting sends the command the File menu sends")
    func startingSendsTheMenusCommand() throws {
        let recorder = Recorder()
        let runner = Self.runner(world: .nothingIsCommitted, into: recorder)

        try runner.startSession()
        #expect(recorder.commands == [.startSession])
    }

    @Test("finishing a running session sends the command the File menu sends")
    func finishingSendsTheMenusCommand() throws {
        let recorder = Recorder()
        let running = ShellCommandWorld(hasPriority: true, sessionPhase: .focus)
        let runner = Self.runner(world: running, into: recorder)

        try runner.finishSession()
        #expect(recorder.commands == [.completeSession])
    }

    @Test("a command nothing is listening to is a refusal, not a silence")
    func anUndeliverableCommandIsARefusal() {
        let recorder = Recorder()
        let runner = Self.runner(
            world: .nothingIsCommitted, delivery: .undeliverable, into: recorder
        )
        #expect(throws: FocusIntentRefusal.unavailable) { try runner.startSession() }
    }

    // MARK: - The intents and the menu bar cannot disagree

    /// **The whole of "performs through the same command host the menu bar uses"**, folded over
    /// every world the menu bar can be in: the intent refuses in exactly the states the menu item
    /// would be drawn disabled in, because both read the same predicate.
    @Test(
        "the intents refuse exactly where the menu would disable the item",
        arguments: [nil] + SessionPhase.allCases.map { Optional($0) }
    )
    func theIntentsAgreeWithTheMenu(phase: SessionPhase?) {
        let recorder = Recorder()
        let world = ShellCommandWorld(hasPriority: phase != nil, sessionPhase: phase)
        let runner = Self.runner(world: world, into: recorder)

        let startWouldBeOffered = PriorityCommand.startSession.isAvailable(in: world)
        let finishWouldBeOffered = PriorityCommand.completeSession.isAvailable(in: world)

        var started = true
        do { try runner.startSession() } catch { started = false }
        var finished = true
        do { try runner.finishSession() } catch { finished = false }

        #expect(started == startWouldBeOffered, "start disagreed with the menu at \(String(describing: phase))")
        #expect(finished == finishWouldBeOffered, "finish disagreed with the menu at \(String(describing: phase))")
    }

    // MARK: - The words

    /// Every refusal has its own sentence, and the two vocabularies agree. A refusal with no
    /// sentence is *"the operation could not be completed"* said to somebody who asked Siri.
    @Test("every refusal has its own sentence, and the two vocabularies are the same set")
    func everyRefusalHasItsOwnSentence() {
        let refusals: [FocusIntentRefusal] = [
            .unavailable, .emptyPriority, .sessionAlreadyRunning, .noSessionToFinish
        ]
        #expect(Set(refusals.map(\.copy)) == Set(FocusIntentCopy.Refusal.allCases))
        #expect(refusals.count == FocusIntentCopy.Refusal.allCases.count)

        let sentences = refusals.map(\.reason)
        #expect(sentences.allSatisfy { !$0.isEmpty })
        #expect(Set(sentences).count == sentences.count, "two refusals say the same thing")
    }

    @Test("a buffered command is not a completed shortcut")
    func bufferedCommandIsRefused() {
        let recorder = Recorder()
        let runner = Self.runner(world: .nothingIsCommitted, delivery: .awaitingCockpit, into: recorder)
        #expect(throws: FocusIntentRefusal.unavailable) { try runner.startSession() }
    }

    @Test("priority and session writers register, refuse, and unregister")
    func writerLifecycle() {
        let center = FocusCommandCenter()
        #expect(!center.commitPriority("Write proposal"))
        #expect(!center.performIntentSession(.startSession))
        var texts: [String] = []
        var commands: [PriorityCommand] = []
        center.registerPriorityWriter { texts.append($0); return true }
        center.registerIntentSessionPerformer { commands.append($0); return true }
        #expect(center.commitPriority("Write proposal"))
        #expect(center.performIntentSession(.startSession))
        #expect(!center.performIntentSession(.completeSession))
        #expect(!center.performIntentSession(.newPriority))
        #expect(texts == ["Write proposal"])
        #expect(commands == [.startSession])
        center.unregisterPriorityWriter()
        center.unregisterIntentSessionPerformer()
        #expect(!center.commitPriority("Another"))
        #expect(!center.performIntentSession(.startSession))
    }
}
