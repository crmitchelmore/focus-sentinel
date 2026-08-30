import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **A correction aimed at the glyph must not silently destroy the question on the panel**
/// (focus-h0s, U-1).
///
/// ## The defect
///
/// `resolve(_:snoozeDuration:)` ends with *"a question ends here only if it was sharing the rung's
/// surface"*, and it ended it with `closeSurfaces(endingAnyQuestionAs: .worldMovedOn)`.
/// `closeSurfaces` calls `endOpenQuestion(_:)`, which wrote **nothing**. Every other producer of
/// `.worldMovedOn` called `expireOpenQuestion()` first — `sessionEnded()`, `phaseLeftFocus()`,
/// `priorityChanged()`, `withdrawForPresentation()`. `resolve` was the fifth and the only one that
/// did not.
///
/// The comment above it assumed a question on the panel was sharing the accusation's surface. It
/// is not: an ambient rung lands on the menu-bar glyph, which does not hold the interruption slot,
/// so a question is asked afterwards and takes the panel independently. Ctrl-Cmd-R — *"This is
/// relevant"*, whose whole subject is the **rung** — then took a question the person was looking
/// at off the screen, wrote no receipt, and left the asking to happen again.
///
/// ## Why the repair is not a fifth call to `expireOpenQuestion()`
///
/// Four call sites remembering and one forgetting is the by-hand parity that produced the badge
/// beads. `QuestionExit` already existed to name every way a question can end, and its own header
/// says an exit is *"a place where three things have to happen together — the record, the slot,
/// and the surface"*. Two of the three were inside the door; the record was outside it. It is
/// inside now, and `QuestionExit.recordsAnExpiry` is what each exit answers.
@Suite("A correction aimed at the rung leaves the question a record", .serialized)
@MainActor
struct NudgeHostResolveExpiryTests {
    /// The application the rung is about.
    static let drifting = NudgeHostFixture.decoy
    /// A different application, so the question and the accusation are about different things —
    /// which is the whole situation: one nudge is dismissed and the other is destroyed.
    static let asked = "com.example.Reader"

    /// A glyph rung standing while a question holds the panel.
    ///
    /// The order is load-bearing and is the reason this state exists at all: an ambient rung lands
    /// on `.menuBar`, which `NudgeSurface.holdsTheInterruptionSlot` says false for, so the
    /// question that follows is admitted and takes the panel for itself.
    static func rungOnTheGlyphAndQuestionOnThePanel(_ fixture: NudgeHostFixture) throws {
        fixture.host.consider(NudgeHostFixture.unrelatedJudgement(subject: Self.drifting))
        NudgeHostFixture.settle()
        try #require(
            fixture.host.landedRungSurface == .menuBar,
            "no rung is on the glyph, so this is not the state focus-h0s is about"
        )

        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: Self.asked))
        NudgeHostFixture.settle()
        try #require(
            fixture.panel.isVisible && fixture.panel.showing == .question,
            "no question is on the panel, so there is nothing for the correction to destroy"
        )
    }

    /// **Ctrl-Cmd-R on the glyph's rung: the question it takes down is written down.**
    ///
    /// Driven through `perform(_:)`, which is the View menu's own entry point and the path the
    /// key equivalent takes, rather than by calling `resolve` directly — the shortcut is what the
    /// bead is about, and a test that called the inner function would be proving the inner
    /// function.
    ///
    /// Before the fix: zero receipts, and `askedCount` for the subject zero, so the question came
    /// back as though it had never been asked.
    @Test(
        "the correction records the question it destroys",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func theCorrectionRecordsTheQuestionItDestroys() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try Self.rungOnTheGlyphAndQuestionOnThePanel(fixture)

        #expect(try fixture.receipts().isEmpty)

        // The shortcut, aimed at the rung on the glyph.
        fixture.host.perform(.thisIsRelevant)
        NudgeHostFixture.settle()

        let receipts = try fixture.receipts()
        #expect(
            receipts.count == 1,
            "the question was destroyed and left no receipt: \(receipts.map(\.outcomeRaw))"
        )
        #expect(receipts.first?.subject == Self.asked)
        #expect(receipts.first?.outcomeRaw == AskedQuestionOutcome.expired.rawValue)

        // **Recorded is not settled** (focus-qds). An expiry is not an answer, so the subject
        // stays askable — a correction about a different application must not spend the app's one
        // licensed asking about this one.
        #expect(
            try fixture.ledger.settledReceipt(
                priorityID: fixture.priorityID, subjectKind: .app, subject: Self.asked
            ) == nil,
            "a correction aimed at the rung settled a question about something else"
        )
        // And it really is off the screen, with nothing left offering answers the loop would drop.
        #expect(fixture.host.orphanedNudgeSurfaces.isEmpty)
    }

    /// **Every producer of `.worldMovedOn` writes the same row** (focus-h0s).
    ///
    /// The class rather than the instance. `resolve` was the fifth of five and the odd one out, so
    /// the assertion is the agreement across all five — a sixth producer added without a record is
    /// a red run here rather than a sixth round of this bead.
    ///
    /// `hideOverlays()` is deliberately **not** in this list and is asserted separately below: it
    /// is F-81 and writes nothing, which is why it stopped travelling as `.worldMovedOn` at all.
    @Test(
        "every way the world ends a question writes it down, the correction included",
        .enabled(if: LocalizationLane.catalogsAreCompiled),
        arguments: WorldMovedOn.allCases
    )
    func everyWorldMovedOnProducerWritesTheExpiry(producer: WorldMovedOn) throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try Self.rungOnTheGlyphAndQuestionOnThePanel(fixture)

        producer.drive(fixture)
        NudgeHostFixture.settle()

        let receipts = try fixture.receipts()
        #expect(
            receipts.count == 1,
            """
            \(producer.rawValue) ended the question and wrote \(receipts.count) receipt(s) — \
            a question the person saw and did not answer is a fact about their day
            """
        )
        #expect(receipts.first?.outcomeRaw == AskedQuestionOutcome.expired.rawValue)
    }

    /// **F-81 still writes nothing, and now says so** (focus-h0s).
    ///
    /// The negative control the fold above needs, and the reason `screenReclaimed` exists: "hide
    /// my overlays" is a request about the screen, not a thing to tell the app. It travelled as
    /// `.worldMovedOn` and wrote nothing only because the panel had already been ordered out and
    /// `QuestionLedgerPolicy` refused a receipt it could not prove readable — a rule holding by
    /// accident of statement order. With the record inside the door, that accident would have
    /// become a write.
    @Test(
        "asking for the screen back writes nothing, and the question stays askable",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func reclaimingTheScreenWritesNothing() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        try Self.rungOnTheGlyphAndQuestionOnThePanel(fixture)

        fixture.host.perform(.hideOverlays)
        NudgeHostFixture.settle()

        #expect(try fixture.receipts().isEmpty, "F-81 wrote a receipt")
        #expect(fixture.host.orphanedNudgeSurfaces.isEmpty)
        #expect(!fixture.panel.isVisible)
    }

    /// The five ways the world ends a question on the panel, as a driver each.
    ///
    /// A `CaseIterable` list rather than five tests, so the one that was missing could not have
    /// been written as four.
    enum WorldMovedOn: String, CaseIterable, Sendable {
        case sessionEnded
        case phaseLeftFocus
        case priorityChanged
        case presentationClaimedTheDisplay
        /// The fifth, and the one focus-h0s is about.
        case correctionAimedAtTheRung

        @MainActor
        func drive(_ fixture: NudgeHostFixture) {
            switch self {
            case .sessionEnded: fixture.host.sessionEnded()
            case .phaseLeftFocus: fixture.host.phaseLeftFocus()
            case .priorityChanged: fixture.host.priorityChanged()
            case .presentationClaimedTheDisplay:
                // The gate closing under a panel that is already up, heard on the next
                // corroboration tick — the same cadence every other nudge decision runs at.
                let presenting = PresentationState(
                    signals: PresentationSignals(
                        frontmostWindowFillsAScreen: true,
                        presentationOptionsSayFullScreen: true,
                        menuBarHidden: true
                    ),
                    isUserExcluded: false,
                    isPresenting: true
                )
                fixture.host.surroundings = {
                    [clock = fixture.clock, commitment = fixture.commitment] in
                    NudgeHostFixture.surroundings(
                        monotonic: clock.elapsed,
                        commitment: commitment,
                        presentation: presenting
                    )
                }
                fixture.host.consider(
                    NudgeHostFixture.unrelatedJudgement(
                        subject: NudgeHostResolveExpiryTests.drifting
                    )
                )
            case .correctionAimedAtTheRung: fixture.host.perform(.thisIsRelevant)
            }
        }
    }
}
