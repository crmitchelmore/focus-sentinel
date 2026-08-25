import AppKit
import FocusCore
import Foundation
import SwiftUI
import Testing

@testable import FocusUI

enum MenuBarFixture {
    static func presentation(
        status: FocusStatus = .relevant,
        snoozes: [MenuBarSnooze] = [],
        pendingQuery: QueryPresentation? = nil,
        differentiateWithoutColor: Bool = false,
        sensingPaused: Bool = false
    ) -> MenuBarPresentation {
        MenuBarPresentation(
            status: status,
            priorityIntent: "Write the Q3 proposal",
            elapsed: .seconds(1_505),
            remaining: nil,
            timerFormat: .minuteSecond,
            snoozes: snoozes,
            pendingQuery: pendingQuery,
            rung: .panel,
            band: .medium,
            sensingPaused: sensingPaused,
            differentiateWithoutColor: differentiateWithoutColor
        )
    }

    static let snoozed = presentation(
        snoozes: [MenuBarSnooze(subject: "com.apple.Safari", remaining: .seconds(305))]
    )

    static let query = QueryPresentation(
        task: "Write the Q3 proposal",
        subject: "com.figma.Desktop",
        reason: .noNegativeBasis,
        dwelled: .seconds(90)
    )

    static let withQuestion = presentation(status: .uncertain, pendingQuery: query)
}

/// **The menu bar, and the two measurements that shape it** (R-91, P-132, P-133).
@Suite("The menu-bar command centre")
@MainActor
struct MenuBarTests {
    // MARK: - Five states, five silhouettes (P-132, F-83, F-146)

    /// P-132 put all five status items in the real menu bar at once and read the frame: five
    /// distinct silhouettes, legible in monochrome at menu-bar size. This is the half of that
    /// which can be asserted headlessly — that every symbol **resolves**, that no two states
    /// share one, and that every glyph is template-rendered so the silhouette is the signal.
    @Test("all five states resolve to a distinct template glyph", arguments: FocusStatus.allCases)
    func everyStateHasAGlyph(status: FocusStatus) throws {
        let image = try #require(MenuBarController.glyph(for: status))
        #expect(image.isTemplate)
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test("no two states share a symbol or a shape")
    func silhouettesAreDistinct() {
        let symbols = Set(FocusStatus.allCases.map(\.symbolName))
        let shapes = Set(FocusStatus.allCases.map(\.shape))
        #expect(symbols.count == FocusStatus.allCases.count)
        #expect(shapes.count == FocusStatus.allCases.count)
        #expect(FocusStatus.allCases.count == 5)
    }

    /// F-146: under "Differentiate without colour" the short label stops being decoration and
    /// becomes the channel the person is relying on, so it is drawn in the menu bar itself
    /// rather than only in the popover.
    @Test(
        "the short label joins the glyph when colour is not available to the person",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func labelAccompaniesTheGlyphWithoutColour() {
        let plain = MenuBarController.buttonTitle(MenuBarFixture.presentation())
        let differentiated = MenuBarController.buttonTitle(
            MenuBarFixture.presentation(differentiateWithoutColor: true)
        )

        #expect(plain == "25:05")
        #expect(differentiated.hasSuffix("25:05"))
        #expect(differentiated.contains(FocusStatus.relevant.shortLabel))
        // VoiceOver hears the label whatever the setting says: the visual channel is what the
        // preference is about, and a spoken figure with no name is a figure with no meaning.
        #expect(
            MenuBarController.accessibilityLabel(MenuBarFixture.presentation())
                .contains(FocusStatus.relevant.shortLabel)
        )
    }

    // MARK: - The timer's width does not move (P-133)

    /// **The measurement, re-run on the shipping font.**
    ///
    /// P-133 measured `00:00`, `11:11`, `59:59` and `88:88` at **31.302734375 pt — identical to
    /// the last digit** — in `NSFont.monospacedDigitSystemFont(ofSize: .smallSystemFontSize)`,
    /// against a **7.69 pt** jitter on the proportional face between `11:11` and `88:88`. That
    /// jitter is the difference between a stable menu bar and one that twitches once a second,
    /// and this asserts it on the font the app actually draws with rather than on a number in a
    /// document.
    @Test("every four-digit timer draws at exactly the same width")
    func timerWidthIsInvariant() {
        let widths = ["00:00", "11:11", "59:59", "88:88"].map(MenuBarTitle.width(of:))
        #expect(Set(widths).count == 1)
        #expect(abs((widths.first ?? 0) - 31.302734375) < 0.0001)
    }

    /// The proportional face is what makes the monospaced one necessary, so the comparison is
    /// asserted rather than assumed: if a future macOS made the system font monospaced-by-digit
    /// this test would say so instead of the requirement quietly becoming decorative.
    @Test("the proportional face really would jitter, which is why the app does not use it")
    func proportionalFaceJitters() {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        func width(_ text: String) -> Double {
            Double(NSAttributedString(string: text, attributes: [.font: font]).size().width)
        }
        #expect(abs(width("88:88") - width("11:11")) > 7.0)
    }

    /// Width tracks the digit **count**, which is why the form is chosen once per session
    /// rather than allowed to grow at the hour mark.
    @Test("the long form is a different width, which is the whole reason it is chosen once")
    func longFormIsWider() {
        #expect(MenuBarTitle.width(of: "1:00:00") > MenuBarTitle.width(of: "59:59"))
        #expect(abs(MenuBarTitle.width(of: "1:00:00") - 41.6259765625) < 0.0001)
        #expect(
            MenuBarTitle.width(of: "1:00:00")
                == MenuBarTitle.width(of: "9:59:59")
        )
    }

    // MARK: - The format changes at most once per session

    @Test("a session's form is chosen from its plan, and a long plan never changes form")
    func formChosenFromThePlan() {
        #expect(MenuBarTimerFormat.chosen(forPlanned: nil) == .minuteSecond)
        #expect(MenuBarTimerFormat.chosen(forPlanned: .seconds(1_500)) == .minuteSecond)
        #expect(MenuBarTimerFormat.chosen(forPlanned: .seconds(3_600)) == .hourMinuteSecond)
        #expect(MenuBarTimerFormat.chosen(forPlanned: .seconds(7_200)) == .hourMinuteSecond)

        // A planned two-hour session starts long and stays long: zero changes, not one.
        var format = MenuBarTimerFormat.chosen(forPlanned: .seconds(7_200))
        for minute in stride(from: 0, through: 120, by: 5) {
            format = format.advanced(elapsed: .seconds(minute * 60))
            #expect(format == .hourMinuteSecond)
        }
    }

    /// An open-ended session crosses the hour once, so its form changes **once** — and the
    /// transition is monotone, so a session that ran for three hours still changed it once.
    @Test("an open-ended session widens exactly once and never narrows again")
    func openEndedSessionWidensOnce() {
        var format = MenuBarTimerFormat.chosen(forPlanned: nil)
        var changes = 0

        for minute in stride(from: 0, through: 240, by: 1) {
            let next = format.advanced(elapsed: .seconds(minute * 60))
            if next != format { changes += 1 }
            format = next
        }

        #expect(changes == 1)
        #expect(format == .hourMinuteSecond)
        // Monotone: the long form never goes back, however small the reading becomes.
        #expect(MenuBarTimerFormat.hourMinuteSecond.advanced(elapsed: .zero) == .hourMinuteSecond)
    }

    @Test("each form renders the shape it names")
    func formsRenderTheirShape() {
        #expect(MenuBarTimerFormat.minuteSecond.render(.seconds(3_599)) == "59:59")
        #expect(MenuBarTimerFormat.hourMinuteSecond.render(.seconds(3_600)) == "1:00:00")
        #expect(MenuBarTimerFormat.hourMinuteSecond.render(.seconds(45_296)) == "12:34:56")
    }

    // MARK: - What the item counts

    /// A running snooze outranks the session's own figure: it is the thing the person most
    /// recently asked for, and it is the one with a deadline (R-87).
    @Test("the timed span is the snooze, then the timebox, then the session")
    func timedSpanPrecedence() {
        let session = MenuBarPresentation(status: .relevant, elapsed: .seconds(600))
        #expect(session.timedSpan == .seconds(600))

        let timeboxed = MenuBarPresentation(
            status: .relevant, elapsed: .seconds(600), remaining: .seconds(900)
        )
        #expect(timeboxed.timedSpan == .seconds(900))

        let snoozed = MenuBarPresentation(
            status: .relevant,
            elapsed: .seconds(600),
            remaining: .seconds(900),
            snoozes: [MenuBarSnooze(subject: "com.apple.Safari", remaining: .seconds(120))]
        )
        #expect(snoozed.timedSpan == .seconds(120))

        // Nothing to count is a glyph alone, which is honest and narrower.
        #expect(MenuBarPresentation(status: .paused).timedSpan == nil)
        #expect(MenuBarPresentation(status: .paused).timerText.isEmpty)
    }

    // MARK: - The popover reports and performs nothing

    @Test("every popover control reports its own typed request")
    func popoverReportsActions() {
        var seen: [MenuBarAction] = []
        let view = MenuBarPopoverView(presentation: MenuBarFixture.snoozed) { seen.append($0) }

        view.onAction(.openCockpit)
        view.onAction(.startSession)
        view.onAction(.pauseSession)
        view.onAction(.completeSession)
        view.onAction(.setSensingPaused(true))
        view.onAction(.cancelSnooze(subject: "com.apple.Safari"))
        view.onAction(.answerQuery(.yesAddIt))

        #expect(seen.count == 7)
        #expect(seen.contains(.cancelSnooze(subject: "com.apple.Safari")))
        #expect(seen.contains(.setSensingPaused(true)))
        #expect(seen.contains(.answerQuery(.yesAddIt)))
    }

    /// The switch carries the value the person asked **for**, not a toggle — so a popover drawn
    /// from a stale presentation cannot invert F-119's global switch.
    @Test("the sensing switch is absolute, never a toggle")
    func sensingSwitchIsAbsolute() {
        let paused = MenuBarAction.setSensingPaused(true)
        let watching = MenuBarAction.setSensingPaused(false)
        #expect(paused != watching)
    }

    // MARK: - A question in a closed popover is a question nobody has seen (focus-kby, U-1)

    /// **The badge route's whole readability reading.**
    ///
    /// `SurfaceRouter.routeQuery(…)` sends a question here on three ordinary conditions — the
    /// `silentVisual` deck, reduced interruption (forced on by Reduce Motion) and a live
    /// microphone or camera — and the popover opens **only** when a person clicks the status
    /// item. The nudge loop used to mark such a question presentable having read nothing, and a
    /// receipt about a question nobody saw silences it for the life of the priority.
    ///
    /// Both halves of the reading are asserted, because both were knowable and neither was read:
    /// a closed popover shows nothing whatever it is carrying, and an open popover carrying no
    /// question is not showing one.
    @Test("a question is only 'showing' when the popover is open and carrying it")
    func aQuestionIsShowingOnlyWhenThePopoverIsOpenOnIt() {
        let controller = MenuBarController()

        // Nothing installed, nothing open: the popover cannot be showing anything.
        controller.update(MenuBarFixture.presentation(pendingQuery: MenuBarFixture.query))
        #expect(!controller.isPopoverShown)
        #expect(
            !controller.isShowingQuery,
            "a question in a popover nobody has opened counted as a question somebody read"
        )

        // …and neither can an open one with no question in it.
        controller.update(MenuBarFixture.presentation(pendingQuery: nil))
        #expect(!controller.isShowingQuery)
    }

    /// The one wire that lets the nudge loop hear the click. Without it the popover can open on a
    /// question and nothing in the programme is any the wiser.
    @Test("the popover announces itself when a question arrives while it is open")
    func theLoopIsToldWhenTheQuestionAppears() {
        let controller = MenuBarController()
        var announcements = 0
        controller.onPopoverDidShow = { announcements += 1 }

        // Closed: a new question is not an appearance, because nobody is looking at it.
        controller.update(MenuBarFixture.presentation(pendingQuery: MenuBarFixture.query))
        #expect(announcements == 0)
    }
}

@Suite("Menu-bar popover snapshots", .enabled(if: LocalizationLane.catalogsAreCompiled))
@MainActor
struct MenuBarSnapshotTests {
    static let popoverWidth: CGFloat = 300

    /// **All five states.** The popover is where the label always accompanies the glyph, so this
    /// is the surface on which "distinguishable without colour" is a picture rather than a claim.
    @Test("every status draws its own popover", arguments: FocusStatus.allCases, ["light"])
    func everyStatus(status: FocusStatus, variant: String) throws {
        try SnapshotHarness.assertSnapshot(
            MenuBarPopoverView(presentation: MenuBarFixture.presentation(status: status)),
            component: "menuBarPopover.\(status.rawValue)",
            variant: variant,
            width: Self.popoverWidth
        )
    }

    @Test("the popover survives the appearance variants at both text sizes",
          arguments: ["dark", "increasedContrast", "reduceTransparency"], SnapshotTypeSize.allCases)
    func appearanceVariants(variant: String, size: SnapshotTypeSize) throws {
        try SnapshotHarness.assertSnapshot(
            MenuBarPopoverView(presentation: MenuBarFixture.presentation()),
            component: "menuBarPopover",
            variant: variant,
            textScale: size.textScale,
            width: Self.popoverWidth
        )
    }

    @Test("the two states that add a section", arguments: ["light"])
    func statefulVariants(variant: String) throws {
        let cases: [(String, MenuBarPresentation)] = [
            ("snoozed", MenuBarFixture.snoozed),
            ("question", MenuBarFixture.withQuestion),
            ("paused", MenuBarFixture.presentation(status: .paused, sensingPaused: true))
        ]
        for (name, presentation) in cases {
            try SnapshotHarness.assertSnapshot(
                MenuBarPopoverView(presentation: presentation),
                component: "menuBarPopover.\(name)",
                variant: variant,
                width: Self.popoverWidth
            )
        }
    }

    /// The question routed to the popover is the **same** question the panel draws (R-92), so
    /// the popover with one in it must differ from the popover without.
    @Test("a waiting question changes the picture")
    func questionChangesThePicture() throws {
        let without = try SnapshotHarness.render(
            MenuBarPopoverView(presentation: MenuBarFixture.presentation(status: .uncertain)),
            traits: SnapshotHarness.variantTraits(named: "light"),
            width: Self.popoverWidth,
            name: "menuBarPopover.distinctness.noQuestion"
        )
        let with = try SnapshotHarness.render(
            MenuBarPopoverView(presentation: MenuBarFixture.withQuestion),
            traits: SnapshotHarness.variantTraits(named: "light"),
            width: Self.popoverWidth,
            name: "menuBarPopover.distinctness.question"
        )
        #expect(PNGCompare.areDistinct(without.pixels, with.pixels))
    }
}
