import AppKit
import FocusCore
import FocusUI
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// **A question belongs to the commitment it was asked under** (focus-lmo, U-1).
///
/// ## The defect these drive
///
/// The open-question fields carried no ask-time priority, so both resolution paths asked the
/// store for the *live* one at the moment the question ended: `answer(_:)` through
/// `priorities.activeTask()`, `expireOpenQuestion()` through `activePriorityID()`. The panel is
/// deliberately sticky — `hidesOnDeactivate` is `false` (R-89) — precisely so a question waits
/// rather than vanishing when somebody clicks back into their work, and one of the things they
/// may do in that interval is commit to a new priority.
///
/// Both halves of U-1 break at once when they do:
///
/// * the **new** commitment is born carrying an immutable receipt about a question nobody put to
///   it, and `hasAsked(…)` is gate 11 of the suppression stack, so the app is permanently silent
///   about that subject under a priority it never asked about;
/// * the **old** commitment keeps no receipt, so the question the person just answered is asked
///   again the next time they come back to it — and *"repeat-asking is a defect"* is U-1's own
///   sentence.
///
/// The rule the answer teaches travels the same way: `QueryLedger.answer(…)` scopes it to the
/// task row it is handed.
@Suite("A question is keyed to the priority it was asked under", .serialized)
@MainActor
struct NudgeHostPriorityKeyTests {
    static let subject = "com.example.Reader"

    /// Every rule row in the store, with the task it is scoped to.
    static func rules(in context: ModelContext) throws -> [FocusSchemaV3.RelevanceRule] {
        try context.fetch(FetchDescriptor<FocusSchemaV3.RelevanceRule>())
    }

    // MARK: - The answered path

    @Test("an answer given after a new commitment writes its receipt and rule on the old one")
    func anAnswerIsKeyedToTheAskTimePriority() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        let asked = fixture.priorityID

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        try #require(fixture.host.deliveredCount == 1)
        try #require(fixture.panel.isVisible)

        // The person commits to something new while the question is still on screen.
        let committed = try fixture.priorities.setPriority(intent: "Review the Acme contract")
        try #require(committed != asked)
        try #require(fixture.panel.isVisible, "the new commitment took the question off screen")

        fixture.host.answer(.yesAddIt)

        // The receipt is the old commitment's…
        let onAsked = try fixture.ledger.receipts(priorityID: asked)
        #expect(onAsked.count == 1, "the question it was asked under kept no receipt")
        #expect(onAsked.first?.subject == Self.subject)
        #expect(
            try fixture.ledger.receipts(priorityID: committed).isEmpty,
            "the new commitment was born with a receipt about a question nobody put to it"
        )

        // …which is the same statement read through gate 11, where it costs something.
        #expect(
            try fixture.ledger.isSettled(
                priorityID: asked, subjectKind: .app, subject: Self.subject
            ),
            "the old priority will re-ask a question that was answered"
        )
        #expect(
            !(try fixture.ledger.isSettled(
                priorityID: committed, subjectKind: .app, subject: Self.subject
            )),
            "gate 11 now silences a subject the new commitment was never asked about"
        )

        // …and so does the rule the answer taught it.
        let rules = try Self.rules(in: fixture.context)
        #expect(rules.count == 1)
        #expect(
            rules.first?.task?.id == asked,
            "what the person taught the app about one commitment landed on another"
        )
    }

    // MARK: - The expiry path

    /// The same claim on the path a priority change itself travels down: whatever ends an open
    /// question, the receipt is written against the commitment it was asked under.
    @Test("a question expired after a new commitment writes its receipt on the old one")
    func anExpiryIsKeyedToTheAskTimePriority() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        let asked = fixture.priorityID

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        try #require(fixture.host.deliveredCount == 1)
        try #require(fixture.panel.isVisible)

        let committed = try fixture.priorities.setPriority(intent: "Review the Acme contract")
        try #require(committed != asked)

        fixture.host.priorityChanged()

        #expect(try fixture.ledger.receipts(priorityID: asked).count == 1)
        #expect(
            try fixture.ledger.receipts(priorityID: committed).isEmpty,
            "the commitment that replaced it inherited the asking"
        )
        #expect(
            !(try fixture.ledger.isSettled(
                priorityID: committed, subjectKind: .app, subject: Self.subject
            ))
        )
    }

    // MARK: - The rule half (focus-lmo)

    /// **What the person taught the app about one commitment must not land on another.**
    ///
    /// The receipt half of focus-lmo was fixed by keying the open question to its ask-time
    /// priority. The rule half was not, and it travels down a different surface: the
    /// **accusation** panel, which is sticky for exactly the same reason (`hidesOnDeactivate` is
    /// `false`, R-89). `NudgeHost` handed the correction outcome on with no key at all, and
    /// `AppComposition.perform(_:)` scoped the row it wrote to
    /// `priorityHost.state.priority?.id` — the priority as it stands when the person *clicks*.
    ///
    /// So: raise a real accusation under one commitment, commit to another while it waits, and
    /// press "this is relevant". The rule belongs to the commitment the accusation was about.
    @Test("a correction made after a new commitment is keyed to the accusation's priority")
    func aCorrectionIsKeyedToTheAccusationsPriority() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        let accused = fixture.priorityID

        var performed: [(CorrectionOutcome, UUID?)] = []
        fixture.host.onCorrection = { outcome, priorityID in
            performed.append((outcome, priorityID))
        }

        // Climb to the panel rung, which is the one that offers corrections at all.
        for _ in 0..<2 {
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
            NudgeHostFixture.settle()
            fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }
        try #require(fixture.host.currentRung == .panel)
        try #require(fixture.panel.isVisible)

        // The person commits to something new while the accusation is still on screen.
        let committed = try fixture.priorities.setPriority(intent: "Review the Acme contract")
        try #require(committed != accused)
        try #require(fixture.panel.isVisible, "the new commitment took the accusation off screen")

        fixture.host.resolve(.thisIsRelevant, snoozeDuration: nil)

        try #require(performed.count == 1, "the correction never reached the root")
        guard case .rule(let rule) = performed[0].0 else {
            Issue.record("'this is relevant' did not produce a rule: \(performed[0].0)")
            return
        }
        #expect(rule.subject == Self.subject)
        #expect(
            performed[0].1 == accused,
            """
            the rule was handed to the root under the commitment the person had just moved to, \
            not the one the app accused them about
            """
        )
    }

    /// The same claim for the **session-lived** rule "Not this time" writes.
    ///
    /// `SessionRuleBox` is keyed on the priority as well as the session, so a live read files the
    /// excuse under a commitment the accusation was never about — where nothing looks for it —
    /// and leaves the one it *was* about un-excused, so the app accuses again immediately.
    @Test("a session-lived excuse is keyed to the accusation's priority")
    func aSessionRuleIsKeyedToTheAccusationsPriority() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        let accused = fixture.priorityID
        let sessionID = UUID()
        fixture.host.currentSessionID = { sessionID }

        for _ in 0..<2 {
            fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
            NudgeHostFixture.settle()
            fixture.clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }
        try #require(fixture.host.currentRung == .panel)

        let committed = try fixture.priorities.setPriority(intent: "Review the Acme contract")
        try #require(committed != accused)

        fixture.host.resolve(.notThisTime, snoozeDuration: nil)

        #expect(
            fixture.sessionRules.rules(forSession: sessionID, priorityID: accused)
                .map(\.subject) == [Self.subject],
            "the excuse is invisible under the commitment it was made about"
        )
        #expect(
            fixture.sessionRules.rules(forSession: sessionID, priorityID: committed).isEmpty,
            "a commitment nobody was accused under inherited an excuse"
        )
    }
}
