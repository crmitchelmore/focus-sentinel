import AppKit
import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **The three readings the host takes, driven on the real surfaces** (focus-kby, U-1).
///
/// ## What used to stand here instead
///
/// `NudgeHostContractTests` grepped `App/NudgeHost.swift` for the substrings these readings were
/// spelled with, because no test target could import the application target. Three separate
/// mutations to this file survived the whole lane untouched:
///
/// 1. `openQuestionReadingAtAsk = reading.everyActionIsReachable ? … : …` → `= .readable`
/// 2. `popoverReadability()`'s two guards → `return .readable`
/// 3. `guard panel.isVisible else { return .unknowable }` → `else { return .readable }`
///
/// Each one reinstates a path by which the app spends its single licensed interruption on a
/// surface nobody read, and each one leaves a receipt behind — which is permanent, because
/// `hasAsked(…)` is gate 11 of the suppression stack. Every test below turns one of them red.
@Suite("The question's readability, on real surfaces", .serialized)
@MainActor
struct NudgeHostQuestionTests {
    static let subject = "com.example.Reader"

    /// A subject long enough to overflow the panel's ceiling once the copy is real.
    ///
    /// The question renders `Is {subject} part of {task}?`, so a subject nobody would ever see is
    /// how this suite builds a **real** panel whose answers are genuinely out of reach — no
    /// contrived view, no injected size, the shipping layout doing what it does with the content
    /// it is given.
    static let overflowingSubject = (1...240)
        .map { "verylongsegmentnumber\($0)" }
        .joined(separator: ".")

    // MARK: - Mutation 1 — the reading taken when the question goes up

    /// **A question on a panel nobody can answer is deferred, and nothing is written down.**
    ///
    /// The control and the case are in one test on purpose: an assertion that "nothing was
    /// delivered" is satisfied just as well by a loop that never asks anything, so the same
    /// fixture shape is driven twice and the difference between the two is the whole claim.
    ///
    /// Gated on the compiled catalogs because the overflow is produced by real copy: in the
    /// inner loop the String Catalog is not processed, `Is {subject} part of {task}?` resolves to
    /// its key, and a panel of 191 points is not the layout this is about. The gate lane compiles
    /// it, which is the lane this must hold in.
    @Test(
        "a question on a panel whose answers are out of reach is deferred, never delivered",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func aQuestionNobodyCouldAnswerIsDeferred() throws {
        // The control: an ordinary subject, an ordinary panel, one delivered question.
        let ordinary = try NudgeHostFixture()
        defer { ordinary.tearDown() }
        ordinary.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()

        #expect(ordinary.host.deliveredCount == 1)
        #expect(ordinary.host.deferredCount == 0)
        #expect(ordinary.panel.isVisible)
        #expect(
            ordinary.panel
                .decisionSurfaceReading(offering: QueryPresentation.actionOrder.map(\.rawValue))
                .everyActionIsReachable
        )

        // The case: the same loop, the same surface, a question whose three answers are below
        // the fold. Nothing is delivered, nothing is counted, and the subject stays askable.
        let overflowing = try NudgeHostFixture()
        defer { overflowing.tearDown() }
        overflowing.host.consider(
            NudgeHostFixture.uncertainJudgement(subject: Self.overflowingSubject)
        )
        NudgeHostFixture.settle()

        let reading = overflowing.panel.decisionSurfaceReading(
            offering: QueryPresentation.actionOrder.map(\.rawValue)
        )
        #expect(
            !reading.unreachableActions.isEmpty,
            "the fixture did not build an unreachable panel: \(reading.summary)"
        )

        #expect(
            overflowing.host.deliveredCount == 0,
            "a question nobody could answer was counted as asked"
        )
        #expect(overflowing.host.deferredCount == 1)
        #expect(!overflowing.panel.isVisible, "the panel was left up carrying an unanswerable question")

        let rows = try overflowing.interventions()
        #expect(rows.count == 1)
        #expect(rows.first?.dispositionRaw == InterventionDisposition.deferred.rawValue)
        // A deferral reached no surface, and the record says so rather than naming one.
        #expect(rows.first?.surfaceRaw.isEmpty == true)

        // And the question is still askable: no receipt, and the slot was given back.
        #expect(try overflowing.receipts().isEmpty)
        #expect(overflowing.host.pendingPopoverQuery == nil)
    }

    // MARK: - Mutation 2 — the badge is an invitation, not a delivery

    /// **A badge question reaches nobody until the popover is open on it.**
    ///
    /// `SurfaceRouter.routeQuery(…)` sends a question to the badge on three ordinary conditions,
    /// and the popover opens **only** when a person clicks the status item. The loop used to mark
    /// such a question presentable having read nothing at all.
    @Test("a badge question is not delivered until the popover is open on it")
    func aBadgeQuestionWaitsForTheClick() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        // Reduced interruption is one of the three conditions that route a question to the badge.
        fixture.host.preferences = NudgePreferences(voice: .standard, reducedInterruption: true)

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()

        guard case .ask(_, .surface(.popoverBadge)) = fixture.host.lastDecision else {
            Issue.record("the question was not routed to the badge: \(String(describing: fixture.host.lastDecision))")
            return
        }

        // The invitation is up…
        #expect(fixture.host.pendingPopoverQuery != nil)
        // …and nothing has been delivered, counted or written, because nobody has looked.
        #expect(
            fixture.host.deliveredCount == 0,
            "a question sitting behind a click was counted as asked"
        )
        #expect(try fixture.interventions().isEmpty)
        #expect(!fixture.menuBar.isPopoverShown)

        // The click. This is the whole of the badge route: the menu bar is the only object that
        // knows it happened, and `onPopoverDidShow` is the only wire that tells the loop.
        try MenuBarStage.open(
            fixture.menuBar,
            showing: MenuBarPresentation(status: .uncertain, pendingQuery: fixture.host.pendingPopoverQuery),
            onDidShow: { fixture.host.popoverPresentedTheQuestion() }
        )

        #expect(fixture.menuBar.isShowingQuery)
        #expect(fixture.host.deliveredCount == 1, "the popover opened on the question and nothing counted it")
        let rows = try fixture.interventions()
        #expect(rows.count == 1)
        #expect(rows.first?.dispositionRaw == InterventionDisposition.delivered.rawValue)
        #expect(rows.first?.surfaceRaw == NudgeSurface.popoverBadge.rawValue)
    }

    /// **…and a badge question nobody ever opened is not written down** — which is what stops it
    /// being silenced for the life of the priority.
    @Test("a badge question nobody opened leaves no receipt when the session ends")
    func aBadgeQuestionNobodySawStaysAskable() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        fixture.host.preferences = NudgePreferences(voice: .standard, reducedInterruption: true)

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        #expect(fixture.host.pendingPopoverQuery != nil)

        // The session ends with the popover never having been opened.
        fixture.host.sessionEnded()

        #expect(
            try fixture.receipts().isEmpty,
            "a receipt was written about a question nobody was ever shown"
        )
        #expect(
            !(try fixture.ledger.hasAsked(
                priorityID: fixture.priorityID,
                subjectKind: .app,
                subject: Self.subject
            )),
            "gate 11 would now suppress a question that was never asked"
        )
    }

    // MARK: - Mutation 3 — a surface that has gone cannot be re-read

    /// **A question whose surface has gone is not written down** (focus-kby).
    ///
    /// The panel is taken off screen by something that is not the loop — which is exactly the
    /// case the `unknowable` value exists for. The old shape answered `true` for it, and the
    /// consequence is permanent: an immutable receipt about a question the person never got to
    /// answer, and gate 11 silences the subject for the life of the priority.
    ///
    /// The answered path is unaffected and is asserted beside it, because a rule that refused
    /// *every* write would be a rule that broke R-78's transaction.
    @Test("a question whose panel has gone is not written down, but an answered one always is")
    func aQuestionOnAVanishedPanelStaysAskable() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        #expect(fixture.host.deliveredCount == 1)
        #expect(fixture.panel.isVisible)

        // The surface goes, and the loop is not told. Nothing can be established about it now.
        fixture.panel.hide()
        #expect(!fixture.panel.isVisible)

        fixture.host.sessionEnded()
        #expect(
            try fixture.receipts().isEmpty,
            "a receipt was written about a panel nothing could re-read"
        )

        // The control: a person's own answer is its own proof of readability and always writes.
        let answered = try NudgeHostFixture()
        defer { answered.tearDown() }
        answered.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        answered.host.answer(.notNow)
        #expect(try answered.receipts().count == 1)
    }

    // MARK: - The panel never outlives the presentation gate (R-84, F-35, P-130)

    /// The executable form of a scan that used to look for the words `suppressesOverlays` and
    /// `withdrawForPresentation()` in this file. A panel is deliberately sticky, so one shown
    /// before a full-screen space opens is still there — and still flagged — when it does.
    @Test("an open panel is taken off a display a presentation has claimed")
    func anOpenPanelIsWithdrawnForAPresentation() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()
        #expect(fixture.panel.isVisible)

        // The gate closes under a panel that is already up. The host hears about it on the next
        // corroboration tick, which is the same cadence every other nudge decision runs at.
        let presenting = PresentationState(
            signals: PresentationSignals(
                frontmostWindowFillsAScreen: true,
                presentationOptionsSayFullScreen: true,
                menuBarHidden: true
            ),
            isUserExcluded: false,
            isPresenting: true
        )
        fixture.host.surroundings = { [clock = fixture.clock] in
            NudgeHostFixture.surroundings(monotonic: clock.elapsed, presentation: presenting)
        }
        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.subject))
        NudgeHostFixture.settle()

        #expect(!fixture.panel.isVisible, "a panel was left on a display a presentation had claimed")
        #expect(!fixture.panel.properties.isFullScreenAuxiliary)
        // The reading was taken before the window went, so the asking is recorded rather than
        // lost — a question whose receipt was never written is a question that comes back.
        #expect(try fixture.receipts().count == 1)
    }
}
