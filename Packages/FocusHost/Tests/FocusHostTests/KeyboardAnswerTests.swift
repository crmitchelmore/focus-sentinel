import AppKit
import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **A question is answerable with no mouse** (e07a, U-1, F-145).
///
/// U-1 licenses the interruption *because* the question is cheaply answerable. Until this suite
/// existed the panel it is drawn on could not carry a keystroke at all: `NudgePanel` is a
/// `.nonactivatingPanel` with `becomesKeyOnlyIfNeeded`, shown with `orderFrontRegardless()` and
/// never made key (R-96m), so `cancelOperation(_:)` never fires from another application and no
/// `.keyboardShortcut` under `Nudge/` would ever be evaluated. The route that does exist is the
/// app menu: one ⌘-Tab to Focus, then a View-menu key equivalent — which is only a route if
/// activating Focus leaves the question standing. That is the first test, and it was the
/// blocker the plan asked to have measured before the commands were written.
@Suite("A question can be answered with no mouse", .serialized)
@MainActor
struct KeyboardAnswerTests {
    static let subject = "com.example.Reader"

    /// The identifier the shipping app is built with. Read from the store's own constant rather
    /// than from `Bundle.main`, which in a test process names the test runner.
    static let ownBundleIdentifier = FocusStore.bundleIdentifier

    // MARK: - The blocker, measured

    /// **Activating Focus does not withdraw the open question.**
    ///
    /// The route the three commands are reached by is *activate Focus, then press the key*, and
    /// it is void if the activation is itself an event that ends the question. It is not, and the
    /// reason is structural rather than lucky: an activation reaches this loop only as a
    /// `NudgeJudgement` through `consider(_:)`, and no branch of `consider(_:)` ends a question
    /// about another subject — U-2 makes an accusation *wait* behind an open question rather
    /// than displace it, a second question waits the same way, and the callers of
    /// `closeSurfaces(…)` are a session ending, a phase leaving focus, a commitment changing and
    /// the process quitting. None of those is a ⌘-Tab.
    ///
    /// Both inputs the engine could produce for the app's own bundle are driven — a sustained
    /// `unrelated` (a mandate, the harshest) and an `uncertain` (a second question wanting the
    /// slot) — and the control is a third application, so the assertion is about the question
    /// surviving and not about an inert loop. The live half of the same measurement is
    /// `SelfCheck.keyboardAnswerReport()`, which really activates the running application.
    @Test("activating Focus itself leaves the open question standing")
    func activatingTheAppDoesNotWithdrawTheQuestion() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        #expect(fixture.host.hasOpenQuestion, "the fixture did not open a question to measure")
        let deliveredBefore = fixture.host.deliveredCount

        // ⌘-Tab to Focus. The frontmost application becomes this app's own bundle and the sensing
        // graph hands it to the engine like any other — there is no self-exclusion anywhere in
        // the tree, and this suite is the measurement that says none is needed.
        fixture.host.consider(
            NudgeHostFixture.unrelatedJudgement(subject: Self.ownBundleIdentifier)
        )
        NudgeHostFixture.settle()
        #expect(
            fixture.host.hasOpenQuestion,
            "an accusation about Focus itself withdrew the open question, so the keyboard route is void"
        )

        fixture.host.consider(
            NudgeHostFixture.uncertainJudgement(subject: Self.ownBundleIdentifier)
        )
        NudgeHostFixture.settle()
        #expect(
            fixture.host.hasOpenQuestion,
            "a question about Focus itself displaced the open question, so the keyboard route is void"
        )
        #expect(fixture.host.deliveredCount == deliveredBefore)
        #expect(fixture.panel.isVisible, "the panel the question is on went away with the activation")

        // The control: an activation of a third application does not end it either.
        fixture.host.consider(
            NudgeHostFixture.unrelatedJudgement(subject: NudgeHostFixture.decoy)
        )
        NudgeHostFixture.settle()
        #expect(fixture.host.hasOpenQuestion)
        #expect(try fixture.receipts().isEmpty, "something answered the question on the person's behalf")
    }

    // MARK: - The world the three commands are gated on

    /// **The question and the accusation are two facts, and the world carries both.**
    ///
    /// Red before `hasOpenQuestion` existed: the world had one nudge field, `openRung != nil`, so
    /// a loop holding a question and no rung published `hasOpenNudge == false` and every one of
    /// the three answering commands would have been withdrawn in exactly the state they exist for.
    @Test("a loop holding only a question publishes a world the answers are available in")
    func theWorldSeparatesTheQuestionFromTheAccusation() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        #expect(!fixture.host.commandWorld.hasOpenQuestion)
        for command in Self.answersByCommand.map(\.command) {
            #expect(
                !command.isAvailable(in: fixture.host.commandWorld),
                "\(command.rawValue) was offered with no question on screen"
            )
        }

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()

        let world = fixture.host.commandWorld
        #expect(world.hasOpenQuestion)
        // The accusation's own field is untouched: there is no rung, so the two rung verbs stay
        // withdrawn. A single widened field would have offered all five.
        #expect(!world.hasOpenNudge)
        #expect(!PriorityCommand.thisIsRelevant.isAvailable(in: world))
        #expect(!PriorityCommand.snoozeNudge.isAvailable(in: world))
        for command in Self.answersByCommand.map(\.command) {
            #expect(
                command.isAvailable(in: world),
                "\(command.rawValue) was withdrawn while a question was on screen"
            )
        }
    }

    // MARK: - The effect, not the item

    /// **Each of the three commands writes the answer its title claims** (focus-cp2's standard).
    ///
    /// Not "the menu item exists" and not "the loop did not crash": the assertion is the ledger
    /// row, the rule, and the question ending, which is what a person pressing the key is asking
    /// for. Driven through `NudgeHost.perform(_:)`, which is the far end of the channel the menu
    /// item sends down, and held against a table written here rather than read off
    /// `PriorityCommand.queryAnswer` — the table is the second statement of the mapping.
    @Test("each keyboard answer writes the answer it names and ends the question")
    func theThreeKeyboardAnswersLand() throws {
        for row in Self.answersByCommand {
            let fixture = try NudgeHostFixture()
            defer { fixture.tearDown() }
            fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
            NudgeHostFixture.settle()
            #expect(fixture.host.hasOpenQuestion)

            fixture.host.perform(row.command)
            NudgeHostFixture.settle()

            #expect(
                !fixture.host.hasOpenQuestion,
                "\(row.command.rawValue) left the question open"
            )
            #expect(!fixture.panel.isVisible, "\(row.command.rawValue) left the panel on screen")
            let receipts = try fixture.receipts()
            #expect(receipts.count == 1, "\(row.command.rawValue) wrote \(receipts.count) receipts")
            #expect(
                receipts.first?.outcomeRaw == row.answer.outcome.rawValue,
                """
                \(row.command.rawValue) wrote \(receipts.first?.outcomeRaw ?? "nothing") \
                rather than \(row.answer.outcome.rawValue)
                """
            )
            // The rule half of R-78's transaction: the two teaching answers write one, on the
            // subject the question was about; "Not now" writes none.
            let rules = try #require(try fixture.priorities.task(id: fixture.priorityID)).rules
            if let verdict = row.answer.ruleVerdict {
                #expect(rules.count == 1, "\(row.command.rawValue) wrote \(rules.count) rules")
                #expect(rules.first?.subject == Self.subject)
                #expect(rules.first?.verdictRaw == verdict.rawValue)
            } else {
                #expect(rules.isEmpty, "\(row.command.rawValue) wrote a rule it does not name")
            }
        }
    }

    /// **A keyboard answer with no question on screen writes nothing.**
    ///
    /// The same refusal `perform(_:)` already makes for the two rung verbs, folded over the three
    /// new ones: a key equivalent that slipped past a stale menu must not reach the ledger.
    @Test("an answer pressed with no question on screen is refused, silently and completely")
    func anAnswerWithNoQuestionIsRefused() throws {
        for command in Self.answersByCommand.map(\.command) {
            let fixture = try NudgeHostFixture()
            defer { fixture.tearDown() }

            fixture.host.perform(command)
            NudgeHostFixture.settle()

            #expect(try fixture.receipts().isEmpty, "\(command.rawValue) wrote a receipt with no question")
            #expect(try fixture.interventions().isEmpty)
            #expect(try #require(try fixture.priorities.task(id: fixture.priorityID)).rules.isEmpty)
        }
    }

    /// **The answers are the question's, not the accusation's.** With an accusation on the
    /// panel and no question anywhere, the three answer nothing and write nothing — which is the
    /// other half of keeping the two nudges apart.
    @Test("an answer pressed over an accusation writes nothing")
    func anAnswerOverAnAccusationIsRefused() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        #expect(fixture.host.hasOpenNudge, "the fixture did not raise an accusation to press over")
        #expect(!fixture.host.hasOpenQuestion)

        for command in Self.answersByCommand.map(\.command) {
            #expect(!command.isAvailable(in: fixture.host.commandWorld))
            fixture.host.perform(command)
            NudgeHostFixture.settle()
        }
        #expect(fixture.host.hasOpenNudge, "an answer took down an accusation it was not about")
        #expect(try fixture.receipts().isEmpty)
    }

    /// The three verbs that answer a question, and the answer each one is — written here, so
    /// that `PriorityCommand.queryAnswer` is held against a second statement rather than against
    /// itself. Ordered as the menu draws them.
    static let answersByCommand: [(command: PriorityCommand, answer: QueryAnswer)] = [
        (.answerYes, .yesAddIt),
        (.answerNo, .no),
        (.answerNotNow, .notNow)
    ]
}
