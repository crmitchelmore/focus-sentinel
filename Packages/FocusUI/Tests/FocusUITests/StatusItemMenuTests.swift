import AppKit
import FocusCore
import Testing

@testable import FocusUI

/// **The status item's secondary menu** (focus-odz.2).
///
/// The defect: the item had one gesture. A left click toggles the popover, and the popover has no
/// Quit, no Settings and no way to resume watching once it has been paused — so a person running
/// the app with the cockpit shut, which is the state the menu bar exists for, could not leave it
/// from anything they could see.
///
/// Everything asserted here is a **fold over `StatusItemMenuItem.allCases`**, because that is what
/// stops a fifth item shipping with no title, no action or no rule about when it may be offered.
/// What each action then *does* is `MenuBarActionTotalityTests`' — the two new `MenuBarAction`
/// cases are inside its exhaustive table, which is the whole reason they are `MenuBarAction`s.
@Suite("The status item's secondary menu")
@MainActor
struct StatusItemMenuTests {
    /// The order a person reads down. Written out rather than derived, because the order is a
    /// design decision — the destructive-by-consequence item last, under a separator — and a
    /// decision nobody wrote down is a decision the next edit can silently reverse.
    static let expectedOrder: [StatusItemMenuItem] = [
        .openCockpit, .watching, .settings, .quit
    ]

    @Test("the menu is the four declared items, in the order a person reads them")
    func theOrderIsDeclared() {
        #expect(StatusItemMenuItem.allCases == Self.expectedOrder)
        #expect(StatusItemMenuItem.allCases.filter(\.isPrecededBySeparator) == [.quit])
    }

    /// Every item has a title in **both** watching states, and no two items share one.
    ///
    /// Keys rather than resolved strings, and that is the lane rule rather than a shortcut: under
    /// `swift test` SwiftPM copies String Catalogs instead of compiling them, so
    /// `ShellStrings.string(_:)` answers the key itself. What the keys *say* is asserted where a
    /// compiled catalog exists — the self-check pins all four rendered titles, in both states.
    @Test("every item has a distinct title in both watching states")
    func everyItemIsTitled() {
        for paused in [false, true] {
            let keys = StatusItemMenuItem.allCases.map { $0.titleKey(sensingPaused: paused) }
            #expect(Set(keys).count == keys.count, "two items share a title at paused=\(paused)")
        }
    }

    /// **The one item whose label follows the state, and the three that do not.**
    ///
    /// A control labelled with the state it is in rather than the act it performs is the shape a
    /// person misreads, so this is the assertion that the title moves — and that nothing else's
    /// does, which is what stops a future edit making every label state-dependent by accident.
    @Test("only the watching item changes its title when watching is paused")
    func onlyWatchingFollowsTheState() {
        let watching = StatusItemMenuItem.allCases.map { $0.titleKey(sensingPaused: false) }
        let paused = StatusItemMenuItem.allCases.map { $0.titleKey(sensingPaused: true) }

        let moved = zip(watching, paused).enumerated()
            .filter { $0.element.0 != $0.element.1 }
            .map { StatusItemMenuItem.allCases[$0.offset] }
        #expect(moved == [.watching])

        #expect(StatusItemMenuItem.watching.titleKey(sensingPaused: false) == .commandPauseSensing)
        #expect(StatusItemMenuItem.watching.titleKey(sensingPaused: true) == .menuBarResumeWatching)
    }

    /// The switch asks for a **state**, not a flip, so a menu built a moment ago cannot invert it.
    @Test("every item has an action, and the switch names the state it asks for")
    func everyItemActs() {
        for paused in [false, true] {
            let actions = StatusItemMenuItem.allCases.map { $0.action(sensingPaused: paused) }
            #expect(Set(actions).count == actions.count)
        }
        #expect(StatusItemMenuItem.watching.action(sensingPaused: false) == .setSensingPaused(true))
        #expect(StatusItemMenuItem.watching.action(sensingPaused: true) == .setSensingPaused(false))
        #expect(StatusItemMenuItem.quit.action(sensingPaused: false) == .quit)
        #expect(StatusItemMenuItem.settings.action(sensingPaused: false) == .openSettings)
        #expect(StatusItemMenuItem.openCockpit.action(sensingPaused: false) == .openCockpit)
    }

    /// **The enabled state is the app menu's predicate, not a second one** (focus-6uf).
    ///
    /// Asserted by reading them side by side over every world this suite can build, so the day the
    /// app menu withdraws the watching switch and this menu does not is the day this goes red.
    @Test("the watching item is offered exactly when the app menu's own verb is")
    func enabledStateComesFromTheOnePredicate() {
        let worlds: [ShellCommandWorld] = [
            .nothingIsCommitted,
            ShellCommandWorld(hasPriority: true),
            ShellCommandWorld(hasPriority: true, sessionPhase: .focus),
            ShellCommandWorld(hasPriority: true, sessionPhase: .complete, hasOpenNudge: true)
        ]
        for world in worlds {
            #expect(
                StatusItemMenuItem.watching.isAvailable(in: world)
                    == PriorityCommand.pauseSensing.isAvailable(in: world)
            )
            // The other three are always offered, and each `true` is reasoned at the declaration.
            // An application a person cannot leave is the one that matters.
            for item in [StatusItemMenuItem.openCockpit, .settings, .quit] {
                #expect(item.isAvailable(in: world))
            }
        }
    }

    /// **The built menu, not the table it was built from.**
    ///
    /// `secondaryMenu()` is what a person clicks, and three things about it are separately
    /// gettable wrong: an item with no target performs nothing, `autoenablesItems` left at its
    /// default has AppKit overrule `isAvailable(in:)`, and a separator drawn in the wrong place is
    /// a Quit somebody hits by muscle memory.
    @Test("the built menu carries a live target for every item and enables them itself")
    func theBuiltMenuIsLive() {
        let controller = MenuBarController()
        controller.commandWorld = { .nothingIsCommitted }
        let menu = controller.secondaryMenu()

        #expect(menu.autoenablesItems == false)
        let items = menu.items.filter { !$0.isSeparatorItem }
        #expect(items.count == StatusItemMenuItem.allCases.count)
        #expect(menu.items.filter(\.isSeparatorItem).count == 1)
        // The separator sits immediately above Quit.
        #expect(menu.items[menu.items.count - 2].isSeparatorItem)

        for (item, entry) in zip(items, StatusItemMenuItem.allCases) {
            #expect(item.representedObject as? String == entry.rawValue)
            #expect(item.target === controller, "\(entry) has nobody to perform it")
            #expect(item.action != nil)
            #expect(item.isEnabled == entry.isAvailable(in: .nothingIsCommitted))
        }
    }

    /// **Which gesture asked for the menu** (focus-odz.2).
    ///
    /// A right-click, or a left-click with Control held — the Mac's two spellings of one gesture.
    /// A person who knows only the second must not find half a status item, and a plain left click
    /// must still reach the popover, which is the primary affordance.
    @Test("a right-click and a control-click are the secondary gesture; a plain click is not")
    func theSecondaryGestureIsBothSpellings() {
        #expect(MenuBarController.isSecondaryClick(Self.event(.rightMouseUp, modifiers: [])))
        #expect(MenuBarController.isSecondaryClick(Self.event(.leftMouseUp, modifiers: .control)))
        #expect(!MenuBarController.isSecondaryClick(Self.event(.leftMouseUp, modifiers: [])))
        #expect(!MenuBarController.isSecondaryClick(Self.event(.leftMouseUp, modifiers: .command)))
        // No event at all is not a right-click: a synthesised `performClick(nil)` must reach the
        // popover rather than opening the menu underneath itself.
        #expect(!MenuBarController.isSecondaryClick(nil))
    }

    static func event(_ type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }
}
