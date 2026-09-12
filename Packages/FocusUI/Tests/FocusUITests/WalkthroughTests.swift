import FocusCore
import Foundation
import Testing

@testable import FocusUI

/// **The walkthrough's pages, steps and anchors are closed vocabularies, and this holds them
/// closed** (focus-u6de).
///
/// What a unit process can prove about the sheet and the tour is what they are built from: the
/// step order, the keys each step draws, the anchors each step points at, and that the catalog
/// and the steps agree in both directions. What it cannot prove is the picture, which is the
/// snapshot lane's, and what the steps do to the app, which `WalkthroughTourTests` holds
/// through the composition root.
@Suite("The walkthrough")
struct WalkthroughTests {
    /// **The first page is the privacy statement, unchanged**, and it is the sheet's. focus-odz.7
    /// shipped one screen that says what the app looks at; every claim the product rests on is
    /// on it, and a walkthrough that opened on anything else would be putting the features
    /// before the posture.
    @Test("the first page is the first-run explanation, with its store path, and offers no step")
    func theFirstPageIsThePrivacyStatement() {
        let first = WalkthroughPage.first
        #expect(first == .watches)
        #expect(WalkthroughSheet.page == first)
        #expect(first.titleKey == .firstRunTitle)
        #expect(first.paragraphs.map(\.key) == [.firstRunObserves, .firstRunNever, .firstRunPermissions])
        #expect(first.showsStoreLocation)
        #expect(first.actions.isEmpty)
        for page in WalkthroughPage.allCases where page != first {
            #expect(!page.showsStoreLocation, "\(page.rawValue) draws the store path")
        }
    }

    @Test("the pages read in the order a person meets the app")
    func thePagesAreInOrder() {
        #expect(WalkthroughPage.allCases == [
            .watches, .priority, .time, .desk, .nudges, .menuBar, .settings
        ])
        #expect(WalkthroughPage.last == .settings)
    }

    /// Every page has a heading and something under it. A page with no paragraphs would be a
    /// title and two buttons.
    @Test("every page has a title and at least one paragraph, each with a symbol")
    func everyPageHasContent() {
        for page in WalkthroughPage.allCases {
            #expect(!page.paragraphs.isEmpty, "\(page.rawValue) is empty")
            for paragraph in page.paragraphs {
                #expect(!paragraph.symbol.isEmpty, "\(paragraph.key.rawValue) has no symbol")
            }
        }
    }

    /// **The steps walk the app in the order a person uses it**: set the priority, say when it
    /// is done, give it time, start, furnish the desk, see what a nudge is, find the menu bar,
    /// find Settings, and only then finish. The finish is last and nowhere else, because a
    /// finish halfway would be a second exit with different consequences from Escape.
    @Test("the steps are in order, and the finish is the last")
    func theStepsAreInOrder() {
        #expect(WalkthroughAction.steps == [
            .setDemoPriority, .setDemoDoneWhen, .setDemoTimebox, .startDemoSession,
            .addDemoDesk, .addDemoRule, .showDemoNudge, .showDemoQuestion,
            .openMenuBar, .openPrivacySettings, .finishDemo
        ])
        #expect(WalkthroughAction.firstStep == .setDemoPriority)
        #expect(WalkthroughAction.steps.last == .finishDemo)
        #expect(WalkthroughAction.finishDemo.nextStep == nil)
        #expect(WalkthroughAction.firstStep.previousStep == nil)
    }

    /// **Every step belongs to exactly one page**, whose title the panel draws over it, and every
    /// page after the first has at least one step: a page with none would be a heading nobody
    /// reaches.
    @Test("the steps and the pages agree")
    func stepsAndPagesAgree() {
        var placed: [WalkthroughAction] = []
        for page in WalkthroughPage.allCases { placed.append(contentsOf: page.actions) }
        #expect(Set(placed).count == placed.count, "a step is on two pages")
        #expect(Set(placed) == Set(WalkthroughAction.allCases))
        for page in WalkthroughPage.allCases where page != .first {
            #expect(!page.actions.isEmpty, "\(page.rawValue) has no step")
        }
        // Page order and step order agree: a step on a later page never comes before one on an
        // earlier page.
        let pageOrdinals = WalkthroughAction.steps.map { WalkthroughPage.allCases.firstIndex(of: $0.page) ?? -1 }
        #expect(pageOrdinals == pageOrdinals.sorted())
    }

    /// Every step asks for one thing and says what changed, except the finish, which closes the
    /// panel and has nothing to say afterwards.
    @Test("every step has an instruction, and every step but the finish a done sentence")
    func stepsHaveWords() {
        for step in WalkthroughAction.allCases {
            #expect(step.instructionKey.rawValue.hasPrefix("shell.walkthrough.step."), Comment(rawValue: step.rawValue))
            if step == .finishDemo {
                #expect(step.doneKey == nil)
                #expect(step.fallbackTitleKey == .walkthroughActionFinishDemo)
            } else {
                #expect(step.doneKey?.rawValue.hasPrefix("shell.walkthrough.done.") == true, Comment(rawValue: step.rawValue))
                #expect(step.fallbackTitleKey != nil, Comment(rawValue: step.rawValue))
            }
        }
    }

    /// **A step that points at a control points at one that exists**, and the steps that point at
    /// nothing are exactly the ones whose subject is not a cockpit control: the two demo nudges,
    /// the menu bar and the finish. A cockpit step with no anchor would be a panel beside the
    /// window saying "over there".
    @Test("every cockpit step names at least one anchor, and only the off-cockpit steps name none")
    func stepsPointAtControls() {
        let unanchored = Set(WalkthroughAction.allCases.filter { $0.anchors.isEmpty })
        #expect(unanchored == [.showDemoNudge, .showDemoQuestion, .openMenuBar, .finishDemo])
        for step in WalkthroughAction.allCases {
            #expect(Set(step.anchors).count == step.anchors.count, Comment(rawValue: step.rawValue))
        }
        // Every anchor is pointed at by some step: an anchor reported by the cockpit that no step
        // reads is a frame kept for nothing.
        var pointedAt = Set<WalkthroughAnchor>()
        for step in WalkthroughAction.allCases { pointedAt.formUnion(step.anchors) }
        #expect(pointedAt == Set(WalkthroughAnchor.allCases))
        // The nudges are the steps performed on arrival: they exist to be looked at.
        let onArrival = Set(WalkthroughAction.allCases.filter(\.performsOnArrival))
        #expect(onArrival == [.showDemoNudge, .showDemoQuestion])
        for step in onArrival { #expect(step.fallbackTitleKey == .walkthroughShowItAgain) }
    }

    /// The registry: a report is a rectangle, a clear is its absence, and each tells the tour.
    @Test("the anchor registry reports, clears and converts through the window")
    @MainActor
    func theRegistryReportsAndClears() {
        let registry = WalkthroughAnchorRegistry()
        var changes = 0
        registry.onChange = { changes += 1 }
        #expect(!registry.isPresent(.captureField))
        registry.report(.captureField, rect: CGRect(x: 10, y: 20, width: 100, height: 30))
        #expect(registry.isPresent(.captureField))
        #expect(changes == 1)
        // The same rectangle again is not a change.
        registry.report(.captureField, rect: CGRect(x: 10, y: 20, width: 100, height: 30))
        #expect(changes == 1)
        registry.clear(.captureField)
        #expect(!registry.isPresent(.captureField))
        #expect(changes == 2)
        registry.clear(.captureField)
        #expect(changes == 2)
        // With no window there is no screen: the tour falls back to the window's edge.
        registry.report(.rules, rect: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(registry.screenRect(of: .rules, in: nil) == nil)
    }

    /// **The panel goes beside the control, never over it, always on the screen.** Right when
    /// there is room on the right, else left, else below, else above; and clamped.
    @Test("placement prefers the right, then the left, then below, then above, and stays on screen")
    func placementPrefersTheRight() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = CGSize(width: 360, height: 240)
        let gap = WalkthroughPlacement.gap + WalkthroughHighlightWindow.padding

        let middle = CGRect(x: 400, y: 400, width: 200, height: 40)
        let right = WalkthroughPlacement.place(panel: panel, beside: middle, within: screen)
        #expect(right.side == .right)
        #expect(right.origin.x == middle.maxX + gap)
        #expect(right.origin.y == middle.midY - panel.height / 2)

        let atRightEdge = CGRect(x: 1200, y: 400, width: 200, height: 40)
        let left = WalkthroughPlacement.place(panel: panel, beside: atRightEdge, within: screen)
        #expect(left.side == .left)
        #expect(left.origin.x == atRightEdge.minX - gap - panel.width)

        let wide = CGRect(x: 100, y: 500, width: 1300, height: 40)
        let below = WalkthroughPlacement.place(panel: panel, beside: wide, within: screen)
        #expect(below.side == .below)
        #expect(below.origin.y == wide.minY - gap - panel.height)

        let wideLow = CGRect(x: 100, y: 10, width: 1300, height: 40)
        let above = WalkthroughPlacement.place(panel: panel, beside: wideLow, within: screen)
        #expect(above.side == .above)
        #expect(above.origin.y == wideLow.maxY + gap)

        // Never off the screen, whatever the target.
        let corner = CGRect(x: 1400, y: 880, width: 200, height: 200)
        let clamped = WalkthroughPlacement.place(panel: panel, beside: corner, within: screen)
        #expect(screen.contains(CGRect(origin: clamped.origin, size: panel)))
    }

    /// One sentence, one page. A paragraph drawn on two pages is a paragraph somebody will read
    /// twice and wonder whether the second is different.
    @Test("no key is drawn on two pages or two steps")
    func keysAreUnique() {
        var keys: [ShellStringKey] = []
        for page in WalkthroughPage.allCases {
            keys.append(page.titleKey)
            keys.append(contentsOf: page.paragraphs.map(\.key))
        }
        for step in WalkthroughAction.allCases {
            keys.append(step.instructionKey)
            if let done = step.doneKey { keys.append(done) }
        }
        #expect(Set(keys).count == keys.count)
    }

    /// **The bijection over the catalog prefix.** Every `shell.walkthrough.` key is either drawn
    /// by exactly one page, the instruction or the done-sentence of exactly one step, one of the
    /// three button titles, one of the demo priority's two sentences, or chrome. A key added to
    /// the catalog with no drawer fails here; a page or step naming a key outside the namespace
    /// fails here.
    @Test("every walkthrough key in the catalog is drawn by a page, a step, a button, the demo priority or the chrome")
    func catalogAndPagesAgree() {
        let chrome: Set<ShellStringKey> = [
            .walkthroughBack, .walkthroughNext, .walkthroughContinue, .walkthroughContinueNote,
            .walkthroughPosition, .walkthroughPanelTitle
        ]
        let buttons: Set<ShellStringKey> = [
            .walkthroughDoItForMe, .walkthroughShowItAgain, .walkthroughActionFinishDemo
        ]
        let demo: Set<ShellStringKey> = [.walkthroughDemoIntent, .walkthroughDemoDoneWhen]
        let carriedOver: Set<ShellStringKey> = [
            .firstRunTitle, .firstRunObserves, .firstRunNever, .firstRunPermissions
        ]
        let inNamespace = Set(
            ShellStringKey.allCases.filter { $0.rawValue.hasPrefix("shell.walkthrough.") }
        )
        var drawnByPages = Set<ShellStringKey>()
        for page in WalkthroughPage.allCases {
            drawnByPages.insert(page.titleKey)
            drawnByPages.formUnion(page.paragraphs.map(\.key))
        }
        var drawnBySteps = Set<ShellStringKey>()
        var pressed = Set<ShellStringKey>()
        for step in WalkthroughAction.allCases {
            drawnBySteps.insert(step.instructionKey)
            if let done = step.doneKey { drawnBySteps.insert(done) }
            if let title = step.fallbackTitleKey { pressed.insert(title) }
        }

        #expect(chrome.isSubset(of: inNamespace))
        #expect(demo.isSubset(of: inNamespace))
        #expect(pressed == buttons)
        #expect(drawnByPages.isDisjoint(with: chrome))
        #expect(drawnByPages.isDisjoint(with: drawnBySteps))
        let accounted = drawnByPages.subtracting(carriedOver).union(drawnBySteps).union(buttons)
        #expect(accounted == inNamespace.subtracting(chrome).subtracting(demo))
    }

    @Test("next and previous walk the whole list and stop at both ends")
    func navigationWalksTheList() {
        var walked: [WalkthroughAction] = [.firstStep]
        while let next = walked[walked.count - 1].nextStep { walked.append(next) }
        #expect(walked == WalkthroughAction.steps)
        var back: [WalkthroughAction] = [.finishDemo]
        while let previous = back[back.count - 1].previousStep { back.append(previous) }
        #expect(back == WalkthroughAction.steps.reversed())
        #expect(WalkthroughAction.steps.map(\.ordinal) == Array(1...WalkthroughAction.steps.count))
    }

    /// The snapshot lane photographs the sheet and every step, and this is the half that says it
    /// does: a step added here without a component is a step nobody has seen at the largest text
    /// size.
    @Test("the sheet and every step have a snapshot component")
    func everyStepIsPhotographed() {
        let components = SnapshotComponent.allCases.filter { $0.rawValue.hasPrefix("walkthrough") }
        #expect(components.first == .walkthroughWatches)
        let photographed = components.dropFirst().map(\.walkthroughStep)
        #expect(Array(photographed) == WalkthroughAction.steps)
    }

    /// The tour panel's buttons are in the Tab order, in the order the panel draws them.
    @Test("the tour panel has a focus contract with no default field and Escape as its way out")
    func theTourPanelHasAContract() {
        let contract = FocusTraversal.contract(for: .walkthroughTour)
        #expect(contract.order == [.walkthroughAction, .walkthroughBack, .walkthroughNext])
        #expect(contract.defaultField == nil)
        #expect(contract.cancel == .dismissWindow)
    }

    @Test(
        "every string the walkthrough draws resolves to real text",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func stringsResolve() {
        var keys: [ShellStringKey] = []
        for page in WalkthroughPage.allCases {
            keys.append(page.titleKey)
            keys.append(contentsOf: page.paragraphs.map(\.key))
        }
        for step in WalkthroughAction.allCases {
            keys.append(step.instructionKey)
            if let done = step.doneKey { keys.append(done) }
            if let title = step.fallbackTitleKey { keys.append(title) }
        }
        let chrome: [ShellStringKey] = [
            .walkthroughBack, .walkthroughNext, .walkthroughContinue, .walkthroughContinueNote,
            .walkthroughPosition, .walkthroughPanelTitle, .walkthroughDemoIntent,
            .walkthroughDemoDoneWhen, .commandShowWalkthrough, .settingsShowWalkthroughNote
        ]
        keys.append(contentsOf: chrome)
        for key in keys {
            let resolved = ShellStrings.string(key)
            #expect(!resolved.isEmpty)
            #expect(resolved != key.rawValue, "\(key.rawValue) echoes its key")
        }
        #expect(ShellStrings.string(.commandShowWalkthrough) == "Show walkthrough")
        #expect(String(format: ShellStrings.string(.walkthroughPosition), arguments: ["2", "11"]) == "2 of 11")
    }
}
