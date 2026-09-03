import FocusCore
import SwiftUI
import Testing

@testable import FocusUI

/// The space every assertion below is folded over, at file scope because it is data rather than
/// a fixture of the suite: the same cells are read by the unit lane here and named by the
/// self-check's own popover survey.
enum PopoverSpace {

    /// The rig every measurement below is taken on: a 1920 × 1080 display whose visible frame is
    /// 1920 × 961, which is the machine the bead's numbers were read on.
    static let display = DisplayGeometry(
        displayID: 1,
        screenIndex: 0,
        isPrimary: true,
        frame: ScreenRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: ScreenRect(x: 0, y: 89, width: 1920, height: 961),
        backingScaleFactor: 2
    )

    /// A display with almost nothing on it, for the half of the claim the big one cannot reach:
    /// content past the ceiling has to **scroll**, and an action that scrolled away has to read
    /// as out of reach rather than as reachable-because-it-is-in-the-layout.
    static let shortDisplay = DisplayGeometry(
        displayID: 2,
        screenIndex: 0,
        isPrimary: true,
        frame: ScreenRect(x: 0, y: 0, width: 1920, height: 400),
        visibleFrame: ScreenRect(x: 0, y: 89, width: 1920, height: 300),
        backingScaleFactor: 2
    )

    /// A priority a person really types.
    static let shortPriority = "Write the Q3 proposal"

    /// **The longest priority the validator permits**, which is any length at all.
    ///
    /// `IntentValidator` bounds the sentence from **below** — two tokens and three characters —
    /// and there is no maximum anywhere in the capture path, which is exactly why the popover's
    /// ideal width used to be whatever the person typed. `theValidatorBoundsThePriorityFromBelowOnly`
    /// below asserts that rather than trusting this comment.
    static let longPriority = ([shortPriority] + Array(
        repeating: "and send the finance summary to the board before the review", count: 4
    )).joined(separator: " ")

    /// One cell of the space: a content, a text size and an appearance.
    struct Cell: Sendable, CustomTestStringConvertible {
        let name: String
        let presentation: MenuBarPresentation
        let scale: ShellTextScale
        let traits: AppearanceTraits

        var testDescription: String { name }
    }

    /// Every content this surface can hold, at both text sizes, in both appearances, at both
    /// priority lengths.
    ///
    /// **The `both` cell is the one nothing in the repository drew.** `NudgeHost` says in as many
    /// words that a badge question waiting behind a click does not hold the slot, so an accusation
    /// can be on the panel while one pends — and the popover draws both when it happens. It is
    /// also the tallest thing this surface can be, which is to say the one most likely to run off
    /// the bottom of a display.
    static let space: [Cell] = {
        let contents: [(String, QueryPresentation?, AccusationPresentation?, [MenuBarSnooze])] = [
            ("empty", nil, nil, []),
            ("question", MenuBarFixture.query, nil, []),
            ("accusation", nil, MenuBarFixture.accusation, []),
            ("both", MenuBarFixture.query, MenuBarFixture.accusation, []),
            (
                "bothAndSnoozed",
                MenuBarFixture.query,
                MenuBarFixture.accusation,
                [MenuBarSnooze(subject: AccusationFixture.safari, remaining: .seconds(305))]
            )
        ]
        let priorities = [("short", shortPriority), ("long", longPriority)]
        let scales: [(String, ShellTextScale)] = [
            ("standard", .standard), ("accessibilityLarge", .accessibilityLarge)
        ]
        let appearances: [(String, AppearanceTraits)] = [
            ("light", .light), ("dark", .dark)
        ]

        return contents.flatMap { content in
            priorities.flatMap { priority in
                scales.flatMap { scale in
                    appearances.map { appearance in
                        Cell(
                            name: "\(content.0).\(priority.0).\(scale.0).\(appearance.0)",
                            presentation: MenuBarPresentation(
                                status: .unrelated,
                                priorityIntent: priority.1,
                                elapsed: .seconds(1_505),
                                snoozes: content.3,
                                pendingQuery: content.1,
                                pendingAccusation: content.2,
                                rung: .panel,
                                rungSurface: .popoverBadge,
                                band: .medium
                            ),
                            scale: scale.1,
                            traits: appearance.1
                        )
                    }
                }
            }
        }
    }()

}

/// **The popover's committed size, folded over the space rather than driven down a scenario**
/// (focus-5yu, focus-vpu).
///
/// ## Why this suite is a cross product and not a case
///
/// Three rounds of this defect were closed by a proof that drove exactly the scenario the bead
/// described, and each was blind one step out. The popover's own version of that mistake is
/// already in the repository: every committed `menuBarPopover.*.png` baseline is rendered at a
/// width the *test* supplies, so no picture of this surface can ever show its width being wrong,
/// and the one lane that iterates the text sizes renders the popover with **no nudge in it** —
/// the one state that has nothing to grow.
///
/// So the claim here is not about a case. It is: **for every content this surface can hold, at
/// either text size, in either appearance, at any priority the validator accepts, the popover is
/// the width it committed to, no taller than the display can hold, and every action it offers is
/// somewhere a person can click.** The suite enumerates that space and folds the same three
/// assertions over all of it.
///
/// ## What it measures
///
/// `MenuBarController.popoverLayout(measuring:screens:)` and
/// `DecisionSurfaceReachability.evaluate(…)` — the shipping layout function and the shipping
/// predicate, on the shipping view. Nothing here supplies a width, and the frames are the ones
/// the layout itself publishes through `nudgeActionTarget(_:)`.
@Suite("The popover's committed size")
@MainActor
struct MenuBarPopoverLayoutTests {
    // MARK: - The three assertions, folded over all of it

    @Test("every cell is the width the popover committed to, whatever the person typed",
          arguments: PopoverSpace.space)
    func everyCellIsTheCommittedWidth(cell: PopoverSpace.Cell) {
        let layout = Self.layout(of: cell)
        #expect(
            Double(layout.size.width) == MenuBarController.popoverContentWidth,
            "\(cell.name) was laid out at \(layout.size.width), not the committed width"
        )
    }

    @Test("no cell is laid out taller than the display can hold", arguments: PopoverSpace.space)
    func noCellExceedsTheCeiling(cell: PopoverSpace.Cell) throws {
        let ceiling = try #require(
            MenuBarController.popoverMaximumContentHeight(screens: [PopoverSpace.display])
        )
        let layout = Self.layout(of: cell)
        #expect(
            Double(layout.size.height) <= ceiling + MenuBarController.popoverSizeTolerance,
            "\(cell.name) is \(layout.size.height) tall on a display that can hold \(ceiling)"
        )
        // …and a height that had to be clamped is a content that scrolls, never one that is cut
        // off at the clamp: the two are the same picture and only one of them is answerable.
        if layout.scrolls { #expect(Double(layout.size.height) == ceiling) }
    }

    /// **Every action the popover offers is drawn, and reachable exactly when the content fits.**
    ///
    /// Two claims, and the second one is conditional on purpose. `unreportedActions` empty is the
    /// unconditional half — focus-uru's "the top rung on the badge has answers", generalised from
    /// the one fixture it was proved on to every content at every size in either appearance, at
    /// any priority length. `everyActionIsReachable` is the half that decides a **charge**, and
    /// it is asserted for the cells that fit inside the display: a content that had to scroll has
    /// actions below the fold, and the panel's ledger has refused to charge for those since
    /// focus-vpu. `whatScrolledAwayIsOutOfReach` below is the same claim from the other side.
    @Test("every action the popover offers is drawn, and reachable when the content fits",
          arguments: PopoverSpace.space)
    func everyOfferedActionIsDrawnAndReachableWhenItFits(cell: PopoverSpace.Cell) {
        let layout = Self.layout(of: cell)
        let frames = Self.actionFrames(of: cell, layout: layout)

        for nudge in MenuBarNudge.allCases where cell.presentation.isCarrying(nudge) {
            let offered = Self.offeredIdentifiers(of: nudge, in: cell.presentation)
            #expect(!offered.isEmpty, "\(cell.name) carries a \(nudge) that offers nothing")
            let reading = Self.reading(offering: offered, frames: frames, layout: layout)
            #expect(
                reading.unreportedActions.isEmpty,
                "\(cell.name) [\(nudge)] drew no target at all for \(reading.unreportedActions)"
            )
            guard !layout.scrolls else { continue }
            #expect(
                reading.everyActionIsReachable,
                "\(cell.name) [\(nudge)]: \(reading.summary)"
            )
        }
    }

    /// **The fold is not vacuous in either direction.**
    ///
    /// The space contains popovers that fit inside the display and popovers that do not, so
    /// neither branch of the assertion above is a branch nothing takes. Measured on the rig
    /// display (ceiling 911): everything at the standard text size fits except the fullest
    /// popover at the longest priority, and **every** cell at `accessibilityLarge` scrolls —
    /// the fullest of them wants 1184 points of content on a display that can show 911.
    @Test("the space holds both a popover that fits and one that has to scroll")
    func theSpaceHoldsBothSidesOfTheClamp() {
        let scrolling = PopoverSpace.space.filter { Self.layout(of: $0).scrolls }
        #expect(!scrolling.isEmpty, "no cell in the space is ever clamped")
        #expect(scrolling.count < PopoverSpace.space.count, "every cell in the space is clamped")
        // The one that must always be in the scrolling half, because it is the tallest content
        // this surface can hold at the largest text: an accusation, a question and a snooze row.
        #expect(scrolling.contains { $0.name == "bothAndSnoozed.long.accessibilityLarge.light" })
        // …and the one that must always be in the other half, because it is the plainest thing
        // the popover ever draws.
        #expect(!scrolling.contains { $0.name == "empty.short.standard.light" })
    }

    /// **The height is a measurement of the content**, which is what the panel's own repair had
    /// to establish about itself: a fuller popover is a taller popover, until the display stops
    /// it. A committed height that ignored its content would be the second shape focus-vpu
    /// rejected — the constant 380 x 190 the panel was clipped into.
    @Test("a fuller popover is a taller popover")
    func aFullerPopoverIsTaller() throws {
        func height(_ name: String) throws -> CGFloat {
            let cell = try #require(PopoverSpace.space.first { $0.name == name })
            return Self.layout(of: cell).size.height
        }
        let empty = try height("empty.short.standard.light")
        let accusation = try height("accusation.short.standard.light")
        let both = try height("both.short.standard.light")
        #expect(empty < accusation)
        #expect(accusation < both)
    }

    // MARK: - The witnesses: each of the three can go red

    /// **The width is a commitment, and this is what it is a commitment against.**
    ///
    /// The same view, measured with nothing proposing a width — which is precisely what
    /// `popoverController()` used to hand `NSPopover`. If the commitment were removed, the
    /// surface would be this wide, and on the long priority it is multiples of the display's own
    /// column. A test that only asserted "the width is 300" would pass on a view that could never
    /// be anything else.
    @Test("without the commitment the person's own sentence sets the width", arguments: PopoverSpace.space)
    func theUnconstrainedWidthIsTheSentence(cell: PopoverSpace.Cell) {
        guard cell.name.contains(".long.") else { return }
        let unconstrained = NSHostingController(
            rootView: Self.surface(of: cell).whole
        ).view.fittingSize
        #expect(
            Double(unconstrained.width) > MenuBarController.popoverContentWidth * 2,
            "\(cell.name) measured \(unconstrained.width) unconstrained — the commitment is doing nothing"
        )
    }

    /// **The reading can fail**, which is the only reason a green one means anything.
    ///
    /// On a display that can hold 250 points of content, the fullest popover has to scroll — and
    /// an action that scrolled below the fold is not one a person can click without scrolling
    /// first. It is reported, so this is not the "no frames" failure; it is out of reach, which
    /// is the failure the panel's ledger has refused to charge for since focus-vpu and the badge's
    /// charged happily until focus-5yu.
    @Test("content past the ceiling scrolls, and what scrolled away is out of reach")
    func whatScrolledAwayIsOutOfReach() throws {
        let cell = try #require(PopoverSpace.space.first { $0.name == "both.long.standard.light" })
        let layout = MenuBarController.popoverLayout(
            measuring: Self.surface(of: cell),
            screens: [PopoverSpace.shortDisplay]
        )
        let ceiling = try #require(
            MenuBarController.popoverMaximumContentHeight(screens: [PopoverSpace.shortDisplay])
        )

        #expect(layout.scrolls, "the fullest popover fits on a 300-point display")
        #expect(Double(layout.size.height) == ceiling)
        #expect(Double(layout.size.width) == MenuBarController.popoverContentWidth)

        let frames = Self.actionFrames(of: cell, layout: layout)
        let offered = Self.offeredIdentifiers(of: .accusation, in: cell.presentation)
        let reading = Self.reading(offering: offered, frames: frames, layout: layout)

        #expect(
            !reading.everyActionIsReachable,
            "every correction was in reach in a popover clamped to \(ceiling) points"
        )
        #expect(
            !reading.unreachableActions.isEmpty,
            "the corrections scrolled away were reported as drawn nowhere rather than as out of reach"
        )
    }

    /// A Mac between display configurations has no display to be bounded by, and the width is
    /// still committed: the person's sentence cannot set it in the one state where nothing else
    /// is known either.
    @Test("with no display at all the width is still the width")
    func noDisplayStillCommitsTheWidth() throws {
        let cell = try #require(PopoverSpace.space.first { $0.name == "both.long.accessibilityLarge.dark" })
        #expect(MenuBarController.popoverMaximumContentHeight(screens: []) == nil)
        let layout = MenuBarController.popoverLayout(measuring: Self.surface(of: cell), screens: [])
        #expect(Double(layout.size.width) == MenuBarController.popoverContentWidth)
        #expect(!layout.scrolls, "a surface bounded by nothing acquired a scroll view anyway")
    }

    /// **The validator bounds the priority from below and never from above** — the fact that made
    /// the person's own sentence an unbounded input to this layout.
    @Test("nothing in the capture path bounds the priority's length")
    func theValidatorBoundsThePriorityFromBelowOnly() {
        let locale = Locale(identifier: "en_US")
        #expect(PopoverSpace.longPriority.count > 200)
        // The long sentence is assessed **exactly** as the short one it is built from: length is
        // not a dimension this validator has an opinion about in the direction that matters.
        #expect(
            IntentValidator.assess(PopoverSpace.longPriority, locale: locale)
                == IntentValidator.assess(PopoverSpace.shortPriority, locale: locale)
        )
    }

    /// The ceiling is the display's, and it leaves room for the popover's own chrome and its
    /// margin — not the whole visible frame, which would put the bottom of a full popover on the
    /// edge of the screen.
    @Test("the ceiling is what the display can hold, less the chrome and the margin")
    func theCeilingIsTheDisplays() throws {
        let ceiling = try #require(
            MenuBarController.popoverMaximumContentHeight(screens: [PopoverSpace.display])
        )
        #expect(
            ceiling == PopoverSpace.display.visibleFrame.height
                - MenuBarController.popoverChromeAllowance
                - MenuBarController.popoverEdgeMargin
        )
        #expect(ceiling < PopoverSpace.display.visibleFrame.height)
    }

    // MARK: - The instruments

    /// The shipping view, split the way the shipping controller splits it, with the appearance
    /// and the text size of this cell — and no width (focus-din).
    ///
    /// The environment goes through `modified(_:)` rather than onto the view, so all three
    /// renderings and the measurement taken of them are in one environment. That is exactly what
    /// `MenuBarController.popoverController()` does.
    static func surface(of cell: PopoverSpace.Cell) -> DecisionSurfaceLayout {
        MenuBarPopoverView(presentation: cell.presentation)
            .surfaceLayout
            .modified { $0.appearanceTraits(cell.traits).shellTextScale(cell.scale) }
    }

    /// The shipping layout function, on the shipping view, against the rig display.
    static func layout(of cell: PopoverSpace.Cell) -> MenuBarController.PopoverLayout {
        MenuBarController.popoverLayout(
            measuring: surface(of: cell),
            screens: [PopoverSpace.display]
        )
    }

    /// Where the layout actually put each action, collected through the preference the rows
    /// publish — the same channel `MenuBarController.decisionSurfaceReading(of:)` reads on the
    /// live popover, laid out at the size the live popover is laid out at.
    static func actionFrames(
        of cell: PopoverSpace.Cell,
        layout: MenuBarController.PopoverLayout
    ) -> [String: CGRect] {
        var collected: [String: CGRect] = [:]
        let content = NudgePanelContent(
            inset: MenuBarController.popoverContentInset,
            overflow: layout.overflow,
            layout: surface(of: cell),
            onFrames: { collected.merge($0.frames) { _, latest in latest } }
        )
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        _ = renderer.cgImage
        return collected
    }

    /// The shipping predicate, over the size the shipping layout committed to.
    static func reading(
        offering identifiers: [String],
        frames: [String: CGRect],
        layout: MenuBarController.PopoverLayout
    ) -> DecisionSurfaceReading {
        DecisionSurfaceReachability.evaluate(
            isVisible: true,
            surfaceFrame: ScreenRect(
                x: 0,
                y: 0,
                width: layout.size.width,
                height: layout.size.height
            ),
            screens: MenuBarController.popoverContainers([PopoverSpace.display]),
            contentBounds: ScreenRect(
                x: 0,
                y: 0,
                width: layout.size.width,
                height: layout.size.height
            ),
            actionTargets: frames.map { identifier, rect in
                ActionHitTarget(
                    identifier: identifier,
                    frame: ScreenRect(
                        x: rect.origin.x,
                        y: rect.origin.y,
                        width: rect.width,
                        height: rect.height
                    )
                )
            },
            offering: identifiers
        )
    }

    static func offeredIdentifiers(
        of nudge: MenuBarNudge,
        in presentation: MenuBarPresentation
    ) -> [String] {
        switch nudge {
        case .query: presentation.pendingQuery?.offeredAnswerIdentifiers ?? []
        case .accusation: presentation.pendingAccusation?.offeredActionIdentifiers ?? []
        }
    }
}

// MARK: - e07a: no column is narrower than its longest word (focus-0q4)

/// **The rule the popover's rows are laid out by, folded over state × size** (focus-0q4).
///
/// The committed `accessibilityLarge` pictures all showed the same two defects: the badge and
/// the belief row broke mid-word — `Unr / elat / ed`, `Curr / ent / nudg / e` — because both were
/// `HStack`s whose columns took a fraction of 300 points, and the global switch read *"Watch
/// what I a…"* because the bordered button limits its label to one line. The rows stack now, so
/// every label has the full content width to wrap at a word boundary, and the switch's label may
/// wrap. What a fold can hold is the precondition that makes stacking sufficient: **no label the
/// popover draws has a word wider than the content width at any text size** — a string that
/// grew one would be the next mid-word break, and it would arrive under a green gate.
///
/// What this cannot see is a truncation the button style imposes; that half is the re-recorded
/// pictures, read by eye, which is where the defect was found.
@Suite("The popover's columns are never narrower than their longest word")
@MainActor
struct MenuBarPopoverWordWidthTests {
    /// The width a stacked label is granted: the committed content width less the column's own
    /// padding on each side, at the cell's text scale.
    static func grantedWidth(at scale: ShellTextScale) -> CGFloat {
        CGFloat(MenuBarController.popoverContentWidth) - 2 * DesignTokens.spacing(10, scale: scale)
    }

    @Test(
        "every label the popover draws fits its longest word in the content width, in every state at every size",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func noLabelIsWiderThanItsColumn() {
        var measured = 0
        for cell in PopoverSpace.space {
            let granted = Self.grantedWidth(at: cell.scale)
            for label in MenuBarPopoverView.drawnLabels(for: cell.presentation) {
                let font = NSFont.systemFont(ofSize: DesignTokens.pointSize(label.role, scale: cell.scale))
                let widest = label.text
                    .split(whereSeparator: \.isWhitespace)
                    .map { NSAttributedString(string: String($0), attributes: [.font: font]).size().width }
                    .max() ?? 0
                measured += 1
                #expect(
                    widest <= granted,
                    """
                    \(cell.testDescription): a word of "\(label.text)" is \(widest) points at \
                    \(cell.scale), wider than the \(granted)-point column — it will break mid-word
                    """
                )
            }
        }
        // The fold is over something: every cell draws at least the status label and the five
        // command-centre labels, and the space has both text sizes in it.
        #expect(measured >= PopoverSpace.space.count * 6)
        #expect(PopoverSpace.space.contains { $0.scale == .accessibilityLarge })
    }

    /// **The pin, held against the ruling rather than a picture** (focus-cxb). With one nudge the
    /// decision is that nudge; with both it is the question, and only the question.
    @Test("the decision is the question whenever a question is drawn, and the accusation only when it is alone")
    func theDecisionSectionsFollowTheRuling() {
        for cell in PopoverSpace.space {
            let sections = MenuBarPopoverView(presentation: cell.presentation).decisionSections
            let hasQuestion = cell.presentation.pendingQuery != nil
            let hasAccusation = cell.presentation.pendingAccusation != nil
            if hasQuestion {
                #expect(sections == [.question], "\(cell.testDescription) pins \(sections)")
            } else if hasAccusation {
                #expect(sections == [.accusation], "\(cell.testDescription) pins \(sections)")
            } else {
                #expect(sections.isEmpty, "\(cell.testDescription) pins \(sections) with no nudge")
            }
        }
    }
}
