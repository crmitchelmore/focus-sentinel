import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **The active priority is one fact, and every gate, key and receipt reads the same one**
/// (focus-zrs, focus-lmo, U-1).
///
/// ## The class these drive, not the instances
///
/// Six rounds of this epic each repaired a place where **two values represented one fact** and
/// nothing enforced that they agree — an `.onAppear` beside an `.onChange`, a receipt beside the
/// value it should have carried, a `QuestionEnding` beside the stored outcome. This is the same
/// shape at the centre of the loop: the **active priority**, held twice.
///
/// * Gate 1 was decided by `NudgeSurroundings.hasActivePriority`, which the composition root built
///   from `priorityHost.state.priority != nil` — a projection that is deliberately *seeded with
///   what is already on screen* when the store refuses a read, so it outlives a failure.
/// * The whole lifecycle of the interruption that gate admitted was keyed to
///   `NudgeHost.activePriorityID()` — a **second, live** read of `PriorityStore`.
///
/// Nothing compared them. When they disagreed the app raised a question, drew it, let the person
/// read it and answer it, and then dropped the click in `guard let priorityID =
/// openQuestionPriorityID else { return }` — with `defer { closeSurfaces(…) }` tidying the panel
/// away, zero rules written, no receipt, and the same question asked again on the next tick.
/// `orphanedQuestionSurfaces` reads empty throughout, so round 6's own invariant cannot see it.
///
/// These three drive the divergence at the loop's own entry point. The repair is not a check that
/// the two readings agree: it is that **there is one reading**. The commitment travels in
/// `NudgeSurroundings.commitment`, the gate and the key are the same optional, and the host has no
/// second door to the store to ask again.
@MainActor
struct NudgeHostOneFactTests {
    static let subject = NudgeHostFixture.decoy

    /// The divergence, made by hand at the only place it can now be made: the store's own pointer
    /// moves while the surroundings the loop is handed still name the commitment.
    ///
    /// Before the repair this was the difference between the two readings the loop took for
    /// itself. After it, it is the difference between the commitment the app is *acting under* and
    /// a pointer row — and the whole point is that the question is keyed to the first, because the
    /// first is what the person was shown.
    @Test(
        "the click on a question is written against the commitment the question was asked under",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func theAnsweredQuestionIsNeverDropped() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        // The second reading diverges from the first.
        try fixture.priorities.clearPriority()

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        #expect(fixture.panel.showing == .question, "no question reached the panel to be answered")

        fixture.host.answer(.yesAddIt)
        NudgeHostFixture.settle()

        let receipts = try fixture.receipts()
        #expect(
            receipts.count == 1,
            "the person's click was dropped: receipts \(receipts.map(\.outcome))"
        )
        let rules = try fixture.priorities.task(id: fixture.priorityID)?.rules ?? []
        #expect(
            rules.count == 1,
            "the person answered and the app learned nothing: \(rules.count) rules"
        )
    }

    /// **The same nil key, one function further on** (focus-zrs B).
    ///
    /// `displacedQuestion(from:)` opened with `guard let priorityID = openQuestionPriorityID else
    /// { return nil }`, so on the divergent key it answered `nil` — and `settleOrExpire(…)`
    /// returns on its first line for a `nil` displacement. By then
    /// `endOpenQuestion(.preempted, replacedOn:)` had already cleared the warrant, so the question
    /// was off the screen, un-weighed and unrecorded: `PreemptionCredit` — the entire substance of
    /// two previous rounds — was never consulted, and the question's own log row stayed open for
    /// ever because `openRecordID` had been overwritten by the accusation's.
    @Test(
        "a displaced question is always weighed, and its own row is always closed",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func theDisplacedQuestionIsAlwaysWeighed() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        try fixture.priorities.clearPriority()

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        #expect(fixture.panel.isVisible, "no question was on screen to displace")

        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.subject))
        NudgeHostFixture.settle()

        #expect(
            fixture.host.lastPreemptionCredit != nil,
            "the accusation took the question off the screen without weighing it"
        )

        let rows = try fixture.interventions()
        let questions = rows.filter { $0.kindRaw == InterruptionKind.query.rawValue }
        #expect(questions.count == 1, "expected one question row, got \(rows.map(\.kindRaw))")
        #expect(
            questions.first?.outcomeRaw == InterventionOutcome.dismissed.rawValue,
            """
            the question's row was left open for ever: \
            \(String(describing: questions.first?.outcomeRaw))
            """
        )
    }

    /// **A notification's buttons stay live in Notification Centre indefinitely** (focus-zrs C).
    ///
    /// `NudgeHost.init` wired `notifications.onAction` to `resolve(action.correction,
    /// snoozeDuration: nil)` with no check that the rung the button belongs to is still open. So a
    /// click on a notification from an hour ago — a rung that has been answered, escalated past or
    /// withdrawn — reached the live loop, closed whatever was on screen and completed whatever row
    /// happened to be open. Driven while a **question** is on the panel it turns
    /// `query/delivered/nil` into `query/delivered/corrected` and takes the panel away: a
    /// falsified row and a question the person never answered, recorded as an answer.
    ///
    /// The repair is the one the class asks for: the action names the delivery it belongs to, and
    /// a delivery the host is no longer holding is refused rather than obeyed.
    @Test(
        "a notification action from a delivery that is no longer open is refused",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func aStaleNotificationActionIsRefused() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        #expect(fixture.panel.showing == .question, "no question reached the panel")

        fixture.notifications.handle(
            actionIdentifier: NudgeNotificationAction.thisIsRelevant.identifier,
            requestIdentifier: "a notification delivered an hour ago"
        )
        NudgeHostFixture.settle()

        #expect(
            fixture.panel.showing == .question,
            "a stale notification click took the question off the screen"
        )
        let rows = try fixture.interventions()
        let questions = rows.filter { $0.kindRaw == InterruptionKind.query.rawValue }
        #expect(
            questions.first?.outcomeRaw == nil,
            """
            a stale click falsified the question's row: \
            \(String(describing: questions.first?.outcomeRaw))
            """
        )
        #expect(
            fixture.host.staleNotificationActions == 1,
            "the refusal was not counted, so no lane could see it happen"
        )
    }

    /// **The owner's own three statements, checked from inside the moment they used to disagree**
    /// (focus-zrs).
    ///
    /// `PriorityHost` stated the active priority three ways — the projection the cockpit draws,
    /// the snapshot key the engine invalidates on, and (once this round added it) the commitment
    /// the nudge loop is handed. It fired `onSnapshotInvalidated` **between** moving the key and
    /// assigning the state, so for the whole length of that callback the object told two different
    /// stories about which commitment was active. `AppComposition.noticeLifecycleTransitions()` ran
    /// inside that callback and carried a comment explaining which of the two to read — a rule for
    /// living with a disagreement rather than the removal of one, which is this class exactly.
    ///
    /// Everything is assigned before anything is announced now, so the reading is taken from the
    /// worst possible vantage point: inside the announcement.
    @Test("the owner of the active commitment never states two of them, even mid-announcement")
    func theCommitmentIsOneFactEvenInsideTheAnnouncement() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let host = PriorityHost(
            context: container.mainContext,
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference),
            calendar: NudgeHostFixture.londonCalendar,
            locale: Locale(identifier: "en_GB"),
            environment: PriorityHost.Environment(
                status: .paused,
                storeIsReady: true,
                isObservingActivity: false
            )
        )

        var readingsInsideTheAnnouncement: [[String]] = []
        host.onSnapshotInvalidated = { readingsInsideTheAnnouncement.append(host.commitmentDisagreements) }

        host.setPriority(intent: "Write the Q3 proposal for Acme", doneWhen: nil)
        host.setPriority(intent: "Review the compliance pack", doneWhen: "it is signed off")
        host.clear()

        #expect(
            readingsInsideTheAnnouncement.count >= 3,
            "the announcement did not fire for the three commitments this drove"
        )
        let contradictions = readingsInsideTheAnnouncement.filter { !$0.isEmpty }
        #expect(
            contradictions.isEmpty,
            "the owner told two stories while announcing a change: \(contradictions)"
        )
        #expect(host.commitmentDisagreements.isEmpty)
        #expect(host.activeCommitment == nil, "the cleared commitment survived in one of the three")
    }

    /// **The notification authorisation, held twice** (focus-zrs).
    ///
    /// `NudgePreferences.authorisation` was a copy. `AppComposition` read it from
    /// `NotificationDelivery` at launch and again after the settings pane's one sanctioned request,
    /// and wrote it into the loop. But `NotificationDelivery.deliver(…)` sets its **own** to
    /// `.denied` the moment a delivery actually fails — the route change R-82.4 requires — and
    /// nothing told the copy. So `SurfaceRouter` went on being handed `.authorised` and went on
    /// sending the next recommitment rung to a channel the boundary already knew was shut, while
    /// the Settings pane, which reads the boundary, drew `.denied`. One question, two answers, in
    /// two windows and a router.
    @Test("what the loop routes on is what the notification boundary currently believes")
    func theAuthorisationIsOneFact() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        // The boundary reads the centre, which answers `denied` — the fixture's whole posture.
        fixture.notifications.refresh()
        NudgeHostFixture.settle(0.1)

        #expect(
            fixture.host.preferences.authorisation == fixture.notifications.authorisation,
            """
            the loop routes on \(fixture.host.preferences.authorisation) while the boundary \
            believes \(fixture.notifications.authorisation)
            """
        )
        #expect(fixture.host.notificationAuthorisation == fixture.notifications.authorisation)

        // What a person sets is still what a person set, and it does not disturb the other half.
        fixture.host.choose(voice: .warm)
        fixture.host.choose(reducedInterruption: true)
        #expect(fixture.host.preferences.voice == .warm)
        #expect(fixture.host.preferences.reducedInterruption)
        #expect(fixture.host.preferences.authorisation == fixture.notifications.authorisation)
    }
}
