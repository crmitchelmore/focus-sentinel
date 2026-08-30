import AppKit
import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **The badge route's three wires, with the popover actually open** (focus-kby, U-1).
///
/// ## Why these are here and not in `MenuBarTests`
///
/// They need a popover that is really on screen, and `NSPopover.show(…)` does nothing unless the
/// application is active. `MenuBarTests` deliberately never activates the process — every focus
/// reading in `FocusUITests` would be vacuous if it did — so the two assertions it makes about
/// this route are both taken with the popover **closed**:
///
/// * `isDrawing(.query)` is `popover.isShown && presentation.pendingQuery != nil`, and both of its
///   cases there have `isShown == false`. Deleting the `pendingQuery` half left the suite green.
/// * `onPopoverDidShow` was asserted only in the case where it must *not* fire. Deleting the
///   call in `togglePopover()` left the suite green, and so did replacing the "a question
///   arrived while the popover was open" branch in `update(_:)` with `if false` — the wire the
///   whole badge route rests on, proved by nothing.
///
/// This suite activates a process of its own and opens the real popover, so each of those three
/// is exercised in the state it is about.
@Suite("The badge route, with the popover open", .serialized)
@MainActor
struct MenuBarPopoverTests {
    static func query() -> QueryPresentation {
        QueryPresentation(
            task: "Write the Q3 proposal for Acme",
            subject: NudgeSubject.named("com.example.Reader", runningName: "Reader")!,
            reason: .noNegativeBasis,
            dwelled: .seconds(120)
        )
    }

    /// All three wires, in the order a person produces them: they click the item, and then a
    /// question arrives while they are looking at it.
    @Test("an open popover shows a question only once it is carrying one, and says so both times")
    func theOpenPopoverAnswersForWhatItIsCarrying() throws {
        let controller = MenuBarController()
        defer {
            controller.closePopover()
            controller.remove()
        }
        var announcements = 0

        // The click, on a popover carrying no question.
        try MenuBarStage.open(
            controller,
            showing: MenuBarPresentation(status: .uncertain),
            onDidShow: { announcements += 1 }
        )

        #expect(controller.isPopoverShown)
        // **Both halves of the reading.** The popover is open, and it is showing snoozes and a
        // status — not a question. A reading that answered `true` here would mark a badge
        // question readable for the whole time it sat behind a click nobody had made.
        #expect(
            !controller.isDrawing(.query),
            "an open popover with no question in it counted as showing one"
        )
        // …and the loop was told the popover opened, which is the only way it can ever learn it.
        #expect(
            announcements >= 1,
            "the popover opened and nothing in the programme was told"
        )

        // The question arrives while the popover is already open. That is a question the person
        // is looking at, and the loop is told for the same reason it is told about an opening.
        let beforeTheQuestion = announcements
        controller.update(MenuBarPresentation(status: .uncertain, pendingQuery: Self.query()))

        #expect(
            announcements > beforeTheQuestion,
            "a question appeared in an open popover and the loop was never told"
        )
        #expect(controller.isDrawing(.query))
    }

    /// The same three wires as one consequence, through the loop that depends on them: a badge
    /// question that arrives while the popover is already open is delivered at that moment.
    @Test("a question arriving in an already-open popover is delivered there and then")
    func aQuestionArrivingInAnOpenPopoverIsDelivered() throws {
        let fixture = try NudgeHostFixture()
        defer { fixture.tearDown() }
        fixture.host.choose(reducedInterruption: true)

        // The popover is opened first, on nothing in particular.
        try MenuBarStage.open(
            fixture.menuBar,
            showing: MenuBarPresentation(status: .uncertain),
            onDidShow: { fixture.host.popoverPresented() }
        )
        #expect(fixture.host.deliveredCount == 0)

        // Then the question is routed to the badge…
        fixture.host.consider(NudgeHostFixture.uncertainJudgement(subject: "com.example.Reader"))
        NudgeHostFixture.settle()
        try #require(fixture.host.pendingPopoverQuery != nil)

        // …and the menu bar is redrawn from the same projection every other surface reads, which
        // is what puts the question in front of somebody who is already looking.
        fixture.menuBar.update(
            MenuBarPresentation(status: .uncertain, pendingQuery: fixture.host.pendingPopoverQuery)
        )

        #expect(
            fixture.host.deliveredCount == 1,
            "the question appeared in an open popover and was never counted as asked"
        )
        let rows = try fixture.interventions()
        #expect(rows.count == 1)
        #expect(rows.first?.surfaceRaw == NudgeSurface.popoverBadge.rawValue)
    }
}
