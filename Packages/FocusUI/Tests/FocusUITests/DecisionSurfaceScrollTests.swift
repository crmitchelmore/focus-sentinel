import FocusCore
import SwiftUI
import Testing

@testable import FocusUI

/// **A decision surface never scrolls its decision** (focus-din).
///
/// ## The defect, and why a scenario cannot prove this
///
/// A ceiling and a scroll (focus-nu6, focus-5yu) made sure nothing is cut off;
/// `DecisionSurfaceReachability` refuses to count a nudge whose offered actions are not inside
/// the content the person can see (focus-vpu). Both are right, and together they made a surface
/// that can never be charged: an action scrolled below the fold is not reachable, **nothing
/// re-takes the reading when the person scrolls**, so a nudge on a scrolling surface was never
/// delivered however long they looked at it. Measured through the shipping layout on a
/// 1920 × 1080 display: at `accessibilityLarge` **every** popover state scrolls, so for a
/// large-text user a badge rung was never delivered, `openRung` stayed unpaid, and the ladder
/// parked.
///
/// The bead's own vacuity warning is why this suite is shaped the way it is: *"a person who
/// scrolls and then answers"* passes a scenario, because `answer(_:)`/`resolve(_:)` are a
/// different path that writes `.answered`, while the unclicked case still parks. So this proves
/// nothing about clicking. It folds over **every decision surface in the inventory, in every
/// content state, at both text sizes, on displays that force each of the three ways a surface can
/// give way**, and asserts one thing: a surface that had to give way still puts every action it
/// offers inside the content the person can see — unless the decision itself does not fit, which
/// is the honest residual and is named.
@Suite("A decision surface never scrolls its decision")
@MainActor
struct DecisionSurfaceScrollTests {
    // MARK: - The space

    /// The machine the bead's numbers were read on: 1920 × 1080, visible frame 961.
    static let display = PopoverSpace.display
    /// A display short enough that even the actions will not fit, so the third way of giving way
    /// is reachable from a lane rather than only being described.
    static let shortDisplay = PopoverSpace.shortDisplay

    /// A display of a stated height, for reaching a branch that lives on a particular ceiling.
    static func cramped(_ id: Int, visibleHeight: Double) -> DisplayGeometry {
        DisplayGeometry(
            displayID: id,
            screenIndex: 0,
            isPrimary: true,
            frame: ScreenRect(x: 0, y: 0, width: 1440, height: visibleHeight + 89),
            visibleFrame: ScreenRect(x: 0, y: 89, width: 1440, height: visibleHeight),
            backingScaleFactor: 2
        )
    }

    /// Every display the whole-space fold is taken on: the machine the bead was measured on, two
    /// cramped ones, and one too small for any decision at all.
    static let displays: [[DisplayGeometry]] = [
        [display], [cramped(3, visibleHeight: 548)], [cramped(4, visibleHeight: 330)],
        [shortDisplay]
    ]

    // MARK: - Reaching the pinned branch without hard-coding a height

    /// **A display on which this cell's decision is pinned — derived, never guessed.**
    ///
    /// The middle branch lives on a ceiling strictly between the decision's own height plus the
    /// context floor and the whole surface's height, and both of those are properties of the
    /// content in the environment it is measured in. Hard-coded displays do not survive that: the
    /// same fixtures measure 537 points under `swift test`, where a String Catalog is not
    /// compiled and every label resolves to its key, and less under `xcodebuild`, where the
    /// catalog is compiled and the sentences are real — so a display chosen from one lane's
    /// numbers puts the other lane's cells in a different branch and the proof stops proving
    /// anything, silently.
    ///
    /// `nil` when the cell cannot be pinned at any ceiling: its context is thinner than the floor
    /// the decision must leave it, so every ceiling that clears the decision also clears the whole
    /// surface. That is a fact about the content, and the caller counts them rather than skipping
    /// them quietly.
    static func pinningDisplay(for cell: Cell) -> DisplayGeometry? {
        let heights = measuredHeights(of: cell)
        let floor = heights.decision + DecisionSurfaceLayout.minimumContextHeight
        // Two points of slack on each side, because the commitment itself carries a one-point
        // tolerance and a ceiling landing exactly on a boundary is a coin toss.
        guard floor + 4 < heights.whole else { return nil }
        let ceiling = (floor + heights.whole) / 2
        return cramped(9, visibleHeight: ceiling + chromeReserved(by: cell.surface))
    }

    /// What each surface's ceiling reserves out of the display's visible frame, so a target
    /// ceiling can be turned back into a display. Read from the surfaces' own constants rather
    /// than written down, so a change to either arrives here.
    static func chromeReserved(by surface: DecisionSurface) -> Double {
        switch surface {
        case .menuBarPopover:
            MenuBarController.popoverChromeAllowance + MenuBarController.popoverEdgeMargin
        case .accusationPanel, .questionPanel:
            NudgePanelController.edgeMargin + NudgePanelController.edgeMargin
        }
    }

    /// The wrapped heights of this cell's whole surface and of its decision alone, at the width
    /// the surface commits to — the same two numbers the shipping layout functions take.
    static func measuredHeights(of cell: Cell) -> (whole: Double, decision: Double) {
        let width: Double
        let inset: Double
        switch cell.surface {
        case .menuBarPopover:
            width = MenuBarController.popoverContentWidth
            inset = MenuBarController.popoverContentInset
        case .accusationPanel, .questionPanel:
            width = NudgePanelController.contentWidth
            inset = NudgePanelController.contentInset
        }
        func measure(_ part: AnyView) -> Double {
            NSHostingController(
                rootView: AnyView(
                    NudgePanelContent(
                        inset: inset,
                        overflow: .nothingScrolls,
                        layout: .undivided(part),
                        onFrames: { _ in }
                    )
                )
            )
            .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            .height
        }
        return (measure(cell.layout.whole), measure(cell.layout.decision))
    }

    /// One thing to lay out: which surface it is, what it is carrying, and the environment.
    struct Cell {
        let surface: DecisionSurface
        let name: String
        let layout: DecisionSurfaceLayout
        /// The identifiers this surface says it is offering. Empty for a surface offering
        /// nothing, which is a true statement and never a reachable one.
        let offering: [String]

        var testDescription: String { "\(surface.rawValue).\(name)" }
    }

    static func environment(
        _ layout: DecisionSurfaceLayout,
        scale: ShellTextScale,
        traits: AppearanceTraits
    ) -> DecisionSurfaceLayout {
        layout.modified { $0.appearanceTraits(traits).shellTextScale(scale) }
    }

    /// Every accusation the panel can draw, at both text sizes.
    static func accusationCells() -> [Cell] {
        let contents: [(String, AccusationPresentation)] = [
            ("rungTwo", AccusationFixture.rungTwo()),
            ("mixedDrift", AccusationFixture.mixed),
            ("noReturnTarget", AccusationFixture.noReturnTarget),
            ("longTask", AccusationPresentation(
                rung: .panel,
                task: PopoverSpace.longPriority,
                subject: AccusationFixture.safari,
                dwelled: .seconds(600),
                returnTarget: "Pages",
                snoozeRemaining: .seconds(305),
                hasOpenSession: true
            ))
        ]
        return cells(surface: .accusationPanel, contents: contents) { presentation in
            (AccusationPanelView(presentation: presentation), presentation.offeredActionIdentifiers)
        }
    }

    /// Every question the panel can draw, at both text sizes.
    static func questionCells() -> [Cell] {
        let contents: [(String, QueryPresentation)] = [
            ("noNegativeBasis", QueryFixture.noNegativeBasis()),
            ("mixedUse", QueryFixture.mixedUse),
            ("longTask", QueryPresentation(
                task: PopoverSpace.longPriority,
                subject: QueryFixture.word,
                reason: .noNegativeBasis,
                dwelled: .seconds(90)
            ))
        ]
        return cells(surface: .questionPanel, contents: contents) { presentation in
            (QueryPanelView(presentation: presentation), presentation.offeredAnswerIdentifiers)
        }
    }

    /// The popover, over the space `MenuBarPopoverLayoutTests` already enumerates — every content
    /// it can hold, at both priority lengths, both text sizes and both appearances.
    ///
    /// Two cells per popover cell, because the popover can be carrying two nudges at once and the
    /// reading is taken **per nudge**: an accusation's corrections and a question's answers are
    /// two different sets that both have to be in reach.
    static func popoverCells() -> [Cell] {
        PopoverSpace.space.flatMap { cell -> [Cell] in
            let layout = environment(
                MenuBarPopoverView(presentation: cell.presentation).surfaceLayout,
                scale: cell.scale,
                traits: cell.traits
            )
            return [MenuBarNudge.accusation, .query].map { nudge in
                Cell(
                    surface: .menuBarPopover,
                    name: "\(cell.name).\(nudge)",
                    layout: layout,
                    offering: offered(nudge, in: cell.presentation)
                )
            }
        }
    }

    static func offered(_ nudge: MenuBarNudge, in presentation: MenuBarPresentation) -> [String] {
        switch nudge {
        case .query: presentation.pendingQuery?.offeredAnswerIdentifiers ?? []
        case .accusation: presentation.pendingAccusation?.offeredActionIdentifiers ?? []
        }
    }

    static func cells<Presentation, Surface: DecisionSurfaceContent>(
        surface: DecisionSurface,
        contents: [(String, Presentation)],
        build: (Presentation) -> (Surface, [String])
    ) -> [Cell] {
        let scales: [(String, ShellTextScale)] = [
            ("standard", .standard), ("accessibilityLarge", .accessibilityLarge)
        ]
        return contents.flatMap { name, presentation in
            scales.map { scaleName, scale in
                let (view, offering) = build(presentation)
                return Cell(
                    surface: surface,
                    name: "\(name).\(scaleName)",
                    layout: environment(view.surfaceLayout, scale: scale, traits: .light),
                    offering: offering
                )
            }
        }
    }

    // MARK: - The content-height space (focus-0nm)

    /// **A priority long enough to drive the panel to a stated multiple of its own ceiling.**
    ///
    /// The fixtures above are the contents the app really draws, and they are the right cells to
    /// fold over — but they are four heights that happen to exist rather than a *space*. A pinned
    /// action shelf is a claim about what happens when the content grows without bound, and the
    /// only honest way to make it is to grow the content without bound and look.
    ///
    /// The multiplier is applied to the sentence, not to a measured height: heights differ
    /// between the two lanes — under `swift test` every label resolves to its key — so a cell
    /// built from a number read in one lane lands in a different branch in the other. Built from
    /// the text, the space spans the same shape in both, and `theContentSpaceReachesThreeCeilings`
    /// asserts what it actually spanned rather than assuming it.
    static func tallPriority(_ multiple: Int) -> String {
        ([PopoverSpace.longPriority] + Array(
            repeating: "and then reconcile the figures against last quarter before anything else",
            count: multiple
        )).joined(separator: " ")
    }

    /// Panel cells over a parameterised content height, both surfaces, both text sizes.
    ///
    /// `0` is a priority that fits under the ceiling with room to spare; the largest is well past
    /// three times it. Every one of them is folded into `space`, so the pinned-shelf invariant is
    /// asserted over the whole range rather than over the four heights the fixtures happen to be.
    static func tallContentCells() -> [Cell] {
        let multiples = [0, 2, 6, 14, 30]
        let accusations: [(String, AccusationPresentation)] = multiples.map { multiple in
            ("tall\(multiple)", AccusationPresentation(
                rung: .panel,
                task: tallPriority(multiple),
                subject: AccusationFixture.safari,
                dwelled: .seconds(600),
                returnTarget: "Pages",
                snoozeRemaining: .seconds(305),
                hasOpenSession: true
            ))
        }
        let questions: [(String, QueryPresentation)] = multiples.map { multiple in
            ("tall\(multiple)", QueryPresentation(
                task: tallPriority(multiple),
                subject: QueryFixture.word,
                reason: .noNegativeBasis,
                dwelled: .seconds(90)
            ))
        }
        return cells(surface: .accusationPanel, contents: accusations) { presentation in
            (AccusationPanelView(presentation: presentation), presentation.offeredActionIdentifiers)
        } + cells(surface: .questionPanel, contents: questions) { presentation in
            (QueryPanelView(presentation: presentation), presentation.offeredAnswerIdentifiers)
        }
    }

    static let space: [Cell] =
        accusationCells() + questionCells() + tallContentCells() + popoverCells()

    // MARK: - The instruments

    /// What the shipping layout function commits to for this cell on this display, and what gives
    /// way. The panel's and the popover's, each on its own surface — the same two functions the
    /// two controllers call.
    static func laidOut(
        _ cell: Cell,
        on screens: [DisplayGeometry]
    ) -> (size: CGSize, overflow: DecisionSurfaceOverflow, inset: Double) {
        switch cell.surface {
        case .menuBarPopover:
            let layout = MenuBarController.popoverLayout(measuring: cell.layout, screens: screens)
            return (layout.size, layout.overflow, MenuBarController.popoverContentInset)
        case .accusationPanel, .questionPanel:
            let layout = NudgePanelController.panelLayout(measuring: cell.layout, screens: screens)
            return (layout.size, layout.overflow, NudgePanelController.contentInset)
        }
    }

    /// Where the layout actually put every action, collected through the preference the rows
    /// publish — the channel both controllers' `decisionSurfaceReading` reads, laid out at the
    /// size the shipping surface is laid out at.
    static func actionFrames(
        _ cell: Cell,
        size: CGSize,
        overflow: DecisionSurfaceOverflow,
        inset: Double
    ) -> [String: CGRect] {
        var collected: [String: CGRect] = [:]
        let content = NudgePanelContent(
            inset: inset,
            overflow: overflow,
            layout: cell.layout,
            onFrames: { collected.merge($0.frames) { _, latest in latest } }
        )
        .frame(width: size.width, height: size.height, alignment: .topLeading)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        _ = renderer.cgImage
        return collected
    }

    /// The shipping predicate, over the size the shipping layout committed to.
    static func reading(_ cell: Cell, on screens: [DisplayGeometry]) -> (
        reading: DecisionSurfaceReading, overflow: DecisionSurfaceOverflow
    ) {
        let (size, overflow, inset) = laidOut(cell, on: screens)
        let frames = actionFrames(cell, size: size, overflow: overflow, inset: inset)
        let bounds = ScreenRect(x: 0, y: 0, width: size.width, height: size.height)
        return (
            DecisionSurfaceReachability.evaluate(
                isVisible: true,
                surfaceFrame: bounds,
                screens: MenuBarController.popoverContainers(screens),
                contentBounds: bounds,
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
                offering: cell.offering
            ),
            overflow
        )
    }

    // MARK: - The one claim, folded over the whole space

    /// **The invariant.** On either display, for every surface in the inventory and every content
    /// it can hold: either the decision itself does not fit — `everythingScrolls`, the honest
    /// residual, where the reading refuses the charge and says why — or every action the surface
    /// offers is inside the content the person can see, **without scrolling**.
    ///
    /// That second clause is the whole repair, and it is what makes the answer work for a person
    /// who never scrolls as well as one who does: there is no scroll offset at which the reading
    /// differs, because the decision is not in the scroll view.
    @Test("a surface that gives way still puts every action in reach")
    func aSurfaceThatGivesWayKeepsItsActionsInReach() {
        // One test rather than one per cell because `DecisionSurfaceLayout` carries `AnyView` and
        // is therefore not `Sendable`; the space is still folded over in full, and every cell that
        // fails names itself.
        for cell in Self.space {
            for screens in Self.displays {
                let (reading, overflow) = Self.reading(cell, on: screens)
                guard overflow != .everythingScrolls else { continue }
                #expect(
                    reading.everyActionIsReachable,
                    """
                    \(cell.testDescription) on a \(screens[0].visibleFrame.height)-point display \
                    gave way as \(overflow.rawValue) and left actions out of reach: \(reading.summary)
                    """
                )
            }
        }
        #expect(Self.space.count > 40, "the space collapsed to \(Self.space.count) cells")
    }

    /// **The content space really does run from under the ceiling to past three times it.**
    ///
    /// Without this the fold above is satisfied by twenty cells that all fit, which is the shape
    /// the fixtures alone had. The ceiling is read from the shipping constant and the display's
    /// own geometry — never written down — because the two numbers this claim used to be
    /// expressed in, 648 and 737, were measurements of a rung that no longer exists (U-2) and of a
    /// text size on one machine. A ceiling that is a literal is a ceiling that outlives what it
    /// measured.
    @Test("the content space runs from under the panel's ceiling to past three times it")
    func theContentSpaceReachesThreeCeilings() {
        let ceiling = min(
            NudgePanelController.absoluteMaximumHeight,
            Self.display.visibleFrame.height - Self.chromeReserved(by: .accusationPanel)
        )
        var shortest = Double.greatestFiniteMagnitude
        var tallest = 0.0
        for cell in Self.tallContentCells() {
            let whole = Self.measuredHeights(of: cell).whole
            shortest = min(shortest, whole)
            tallest = max(tallest, whole)
        }
        #expect(
            shortest < ceiling,
            """
            the shortest cell (\(shortest)) already exceeds the ceiling (\(ceiling)), so nothing \
            in the space tests a surface that fits
            """
        )
        #expect(
            tallest >= ceiling * 3,
            """
            the tallest cell is \(tallest) against a ceiling of \(ceiling): the space does not \
            reach three ceilings, so the shelf is never asked the hard question
            """
        )
    }

    /// **What the ceiling is a bound on**, measured rather than remembered.
    ///
    /// `absoluteMaximumHeight` is 800 and its doc comment used to justify that with 737 — the
    /// recommitment rung at the largest accessibility text size, on one machine, for a rung U-2
    /// deleted. Re-measured here: the contents the app really draws fit at `accessibilityLarge`
    /// with room to spare, and the deliberately long priority does not, which is what makes the
    /// ceiling a bound on pathology rather than a size anything ordinary is squeezed into.
    ///
    /// Both directions, because either alone is satisfiable by a layout that has stopped
    /// measuring: if nothing exceeded the ceiling the scroll branches would be unreachable, and
    /// if the ordinary contents exceeded it the panel would be scrolling for everybody.
    @Test("the ordinary contents fit under the ceiling and the pathological one does not")
    func theCeilingIsABoundOnPathology() {
        let ceiling = NudgePanelController.absoluteMaximumHeight
        let large = (Self.accusationCells() + Self.questionCells())
            .filter { $0.name.hasSuffix("accessibilityLarge") }
        var exceeded = 0
        for cell in large {
            let whole = Self.measuredHeights(of: cell).whole
            if cell.name.hasPrefix("longTask") {
                if whole > ceiling { exceeded += 1 }
                continue
            }
            #expect(
                whole <= ceiling,
                """
                \(cell.testDescription) is \(whole) points at the largest text size, past a \
                ceiling of \(ceiling): an ordinary nudge has started scrolling
                """
            )
        }
        #expect(
            exceeded > 0,
            "no content in the suite exceeds the ceiling, so the scroll branches are unreachable"
        )
    }

    /// **Every offered action is in reach at `accessibilityLarge`, over the whole content space.**
    ///
    /// The same claim as the whole-space fold, taken alone at the text size that breaks layouts,
    /// so a regression there names itself instead of arriving inside a fold of two hundred cells.
    @Test("at the largest text size every action stays in reach however tall the content grows")
    func theShelfHoldsAtTheLargestTextSize() {
        let cells = Self.tallContentCells().filter { $0.name.hasSuffix("accessibilityLarge") }
        #expect(!cells.isEmpty, "the content space no longer contains a large-text panel")
        var gaveWay = 0
        for cell in cells {
            let (reading, overflow) = Self.reading(cell, on: [Self.display])
            if overflow == .theContextScrolls { gaveWay += 1 }
            guard overflow != .everythingScrolls else { continue }
            #expect(
                reading.everyActionIsReachable,
                "\(cell.testDescription) left actions out of reach: \(reading.summary)"
            )
        }
        #expect(
            gaveWay > 0,
            """
            not one large-text cell had to pin its shelf, so this proof is measuring a set of \
            panels that all fit
            """
        )
    }

    /// **The bead's own table, inverted.** It measured that every popover state scrolls at
    /// `accessibilityLarge` on a 1080-point display and concluded that a large-text user's badge
    /// rung is therefore never delivered. Every one of those cells is still a surface that has to
    /// give way — asserted, so this is not a claim that the clamp went away — and every one of
    /// them is now chargeable.
    @Test("at the largest text size on a 1080-point display the popover is chargeable")
    func theLargeTextPopoverIsChargeable() {
        // Every state the loop leaves standing: the popover carrying **one** nudge. The two-nudge
        // states are the residual `theTwoNudgePopoverIsTheResidual` names and measures.
        let cells = Self.popoverCells().filter {
            $0.name.contains("accessibilityLarge")
                && !$0.offering.isEmpty
                && !$0.name.hasPrefix("both")
        }
        #expect(!cells.isEmpty, "the space no longer contains a large-text popover carrying a nudge")
        var gaveWay = 0
        for cell in cells {
            let (reading, overflow) = Self.reading(cell, on: [Self.display])
            if overflow != .nothingScrolls { gaveWay += 1 }
            #expect(
                reading.everyActionIsReachable,
                "\(cell.testDescription) is still unchargeable: \(reading.summary)"
            )
        }
        // **And the claim is not satisfied by a popover that happens to fit.** The bead's table
        // was read on this display with the shipping strings; a lane that resolves labels to
        // their keys measures different heights, so the number that must hold everywhere is that
        // the surface really is one that has to give way — asserted per cell on a display derived
        // from that cell's own measurements, below — and that on the bead's own display at least
        // one of them still does.
        #expect(
            gaveWay > 0,
            """
            not one of \(cells.count) large-text popover cells had to give way on the display the \
            bead was measured on, so this proof is measuring something else
            """
        )

        var pinned = 0
        for cell in cells {
            guard let display = Self.pinningDisplay(for: cell) else { continue }
            let (reading, overflow) = Self.reading(cell, on: [display])
            #expect(
                overflow == .theContextScrolls,
                "\(cell.testDescription) answered \(overflow.rawValue) on a display derived to pin it"
            )
            #expect(
                reading.everyActionIsReachable,
                "\(cell.testDescription) pinned its decision and left it out of reach: \(reading.summary)"
            )
            pinned += 1
        }
        #expect(
            pinned == cells.count,
            """
            \(cells.count - pinned) of \(cells.count) large-text popover cells carrying one nudge \
            cannot be pinned at any ceiling — their context is thinner than the floor it must keep
            """
        )
    }

    // MARK: - Completeness, and non-vacuity

    /// **The live controller takes the split, not an undivided view** (focus-din).
    ///
    /// Everything above measures through `panelLayout(measuring:screens:)` and
    /// `popoverLayout(measuring:screens:)`. This closes the one gap that leaves: `update(_:)` has
    /// two overloads — one for a `DecisionSurfaceContent` and one for any `View` that wraps its
    /// argument as `undivided` — and an `undivided` layout can never reach `theContextScrolls`.
    /// If the shipping call sites bound to the wrong one, every proof above would still pass while
    /// the running panel scrolled its actions away exactly as before.
    ///
    /// So this drives the real controller, on the cramped display the accusation's numbers put the
    /// branch on, and reads what it committed to.
    @Test("the shipping panel controller pins the decision it was handed")
    func theShippingControllerPinsTheDecision() throws {
        let cell = try #require(
            Self.accusationCells().first { $0.name.contains("accessibilityLarge") }
        )
        let display = try #require(
            Self.pinningDisplay(for: cell),
            "the accusation panel's context is thinner than the floor it must keep"
        )

        // The panels are real AppKit windows. A test that leaves them behind leaves a window
        // per run for every later test in the process to be slowed by, and this suite makes two.
        let controller = NudgePanelController()
        defer { controller.hide() }
        controller.displays = { [display] }
        controller.update(showing: .accusation, layout: cell.layout, traits: .light)
        #expect(
            controller.currentOverflow == .theContextScrolls,
            """
            the live controller answered \(controller.currentOverflow.rawValue) for the content \
            and the display this cell's own measurements put the pinned branch on
            """
        )

        // And a display with room for the whole panel gives way to nothing, so the branch is
        // reached by the content rather than by the controller always choosing it.
        let roomy = NudgePanelController()
        defer { roomy.hide() }
        roomy.displays = { [Self.display] }
        roomy.update(showing: .accusation, layout: cell.layout, traits: .light)
        #expect(roomy.currentOverflow == .nothingScrolls)
    }

    /// **The self-referential half** (repair doctrine, clause 2).
    ///
    /// The inventory is `DecisionSurface.allCases` and the fold has to cover it, so a fourth
    /// surface added to that enum and not driven here fails. The bijection underneath it is the
    /// other direction: the three conformers claim three distinct cases, so a fourth
    /// `DecisionSurfaceContent` cannot quietly reuse one and inherit a proof about somebody else.
    @Test("every surface in the inventory is driven, and every conformer claims one")
    func everySurfaceIsDriven() {
        let driven = Set(Self.space.map(\.surface))
        #expect(
            driven == Set(DecisionSurface.allCases),
            "surfaces in the inventory that nothing here lays out: \(Set(DecisionSurface.allCases).subtracting(driven))"
        )
        let claimed: [DecisionSurface] = [
            AccusationPanelView.decisionSurface,
            QueryPanelView.decisionSurface,
            MenuBarPopoverView.decisionSurface
        ]
        #expect(Set(claimed).count == claimed.count, "two surfaces claim the same case")
        #expect(Set(claimed) == Set(DecisionSurface.allCases))
    }

    /// **The non-vacuity guard.** The invariant above is satisfied trivially by a space in which
    /// nothing ever gives way — which is what the space would become if a future ceiling grew, or
    /// if a fixture stopped being tall. So all three ways of giving way have to be reached, and
    /// the middle one — the repair itself — has to be reached by every surface in the inventory.
    @Test("all three ways of giving way are reached, and the pinned one by every surface")
    func allThreeWaysAreReached() {
        var reached: Set<DecisionSurfaceOverflow> = []
        var pinnedPerSurface: Set<DecisionSurface> = []
        for cell in Self.space {
            // The fixed displays first, then the one derived from this cell's own measurements —
            // which is what makes "every surface reaches the pinned branch" a claim about the
            // rule rather than about whichever display heights happened to be written down.
            let derived = Self.pinningDisplay(for: cell).map { [$0] }
            for screens in Self.displays + (derived.map { [$0] } ?? []) {
                let overflow = Self.laidOut(cell, on: screens).overflow
                reached.insert(overflow)
                if overflow == .theContextScrolls { pinnedPerSurface.insert(cell.surface) }
            }
        }
        #expect(
            reached == Set(DecisionSurfaceOverflow.allCases),
            "never reached: \(Set(DecisionSurfaceOverflow.allCases).subtracting(reached))"
        )
        #expect(
            pinnedPerSurface == Set(DecisionSurface.allCases),
            """
            a surface never reached the branch this repair added, so the fold says nothing \
            about it: \(Set(DecisionSurface.allCases).subtracting(pinnedPerSurface))
            """
        )
    }

    /// **What this proof would still be green for** (repair doctrine, clause 3).
    ///
    /// * **A person clicking.** Nothing here presses anything. `answer(_:)` and
    ///   `resolve(_:snoozeDuration:)` are a different path that writes `.answered` or
    ///   `.corrected`, and the bead's own warning is that a scenario which scrolls and then clicks
    ///   passes while the unclicked case still parks. This suite is entirely about the unclicked
    ///   case.
    /// * **The charge itself.** It proves the surface is one a person can decide on; that the loop
    ///   then charges the rung is `NudgeHost`'s, and `MenuBarPopoverReadingTests` and
    ///   `NudgeChargingInvariantTests` are where the ledger is read.
    /// * **`everythingScrolls`.** The invariant is skipped there by construction, so a regression
    ///   that pushed every cell into that branch would pass the fold — which is exactly why the
    ///   guard above requires every surface to reach `theContextScrolls`, and why the popover's
    ///   large-text cells are asserted reachable by name.
    /// * **The live window.** Every measurement here is `ImageRenderer` and a hosting controller.
    ///   That a real `NSPanel` and a real `NSPopover` are laid out at these sizes is
    ///   `MenuBarPopoverReadingTests`' and the self-check's.
    @Test("the residual is a real branch, and it refuses the charge rather than excusing it")
    func theResidualRefusesTheCharge() {
        let tallest = Self.popoverCells().filter {
            $0.name.hasPrefix("bothAndSnoozed") && $0.name.contains("accessibilityLarge")
                && !$0.offering.isEmpty
        }
        #expect(!tallest.isEmpty)
        for cell in tallest {
            let (reading, overflow) = Self.reading(cell, on: [Self.shortDisplay])
            #expect(
                overflow == .everythingScrolls,
                "\(cell.testDescription) claimed to pin its decision inside a 300-point display"
            )
            #expect(
                !reading.everyActionIsReachable,
                "a surface whose actions cannot fit reported them as reachable"
            )
        }
    }

    /// **The one state this repair does not reach, measured rather than assumed** (focus-cxb).
    ///
    /// A popover carrying an accusation **and** a question at the largest text size has a decision
    /// of both nudges' actions together — over 815 points against a 911-point ceiling — so there
    /// is no room to pin it and the surface scrolls whole. Neither nudge is chargeable in that
    /// state, exactly as before this repair.
    ///
    /// It is not the bead's park: the two-nudge state is transient — the question is answered or
    /// expires and the popover returns to a single nudge, which the fold above proves chargeable
    /// — where the bead's park was every state, permanently, for every large-text user. It is
    /// asserted here rather than left as an unmeasured corner, so the day somebody changes what
    /// gets pinned this test says whether it improved.
    @Test("a popover carrying two nudges at the largest text size can pin neither")
    func theTwoNudgePopoverIsTheResidual() {
        let both = Self.popoverCells().filter {
            $0.name.hasPrefix("both") && $0.name.contains("accessibilityLarge")
                && !$0.offering.isEmpty
        }
        #expect(!both.isEmpty)
        for cell in both {
            #expect(
                Self.laidOut(cell, on: [Self.display]).overflow == .everythingScrolls,
                "\(cell.testDescription) now pins its decision — this test is out of date, in the good direction"
            )
        }
    }
}
