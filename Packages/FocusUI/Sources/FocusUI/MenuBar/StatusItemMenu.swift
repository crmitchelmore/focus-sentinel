import AppKit

/// **What a right-click on the status item offers** (focus-odz.2).
///
/// ## Why this is a table rather than four lines in the controller
///
/// The status item had one action — a left click, which toggles the popover — and the popover
/// has no Quit, no Settings and no way to resume watching once it has been paused from the menu
/// bar. So a person running the app with the cockpit shut, which is the state the menu bar exists
/// for, could not quit it from anything they could see.
///
/// The four items are declared here, `CaseIterable`, because everything the gate asks about them
/// is a fold: every item has a title in **both** watching states, every item has a
/// `MenuBarAction` behind it, and every item's enabled state comes from the same predicate the
/// app menu's items are disabled on (focus-6uf). A menu built inline in `install()` would answer
/// none of those questions without somebody re-writing the menu in the test.
///
/// ## Why the actions are `MenuBarAction`s and not `PriorityCommand`s
///
/// Because that is the channel the popover's own controls use, and it is the one that works with
/// the main window closed. `FocusCommandCenter.send(_:)` delivers to a handler only
/// `CockpitView.onAppear` registers — measured in `MenuBarActionTotalityTests`, whose whole
/// subject is that "no handler" is exactly "the cockpit is shut". Routing these four the same way
/// is also what puts them inside that suite's existing fold: `effect(of:)` is exhaustive over
/// `MenuBarAction`, so the two cases this bead adds stop the build until the table names what
/// they do.
public enum StatusItemMenuItem: String, Sendable, CaseIterable, Hashable, Identifiable {
    /// Bring the main window forward — the popover's own first button, in the menu that is
    /// reachable without opening the popover.
    case openCockpit
    /// F-119's switch. **One item, two titles**: a control whose label names the state it is in
    /// rather than the act it performs is the shape a person misreads, so this says *Pause
    /// Watching* while watching and *Resume Watching* while paused.
    case watching
    /// The ⌘, idiom, from the menu bar. It performs the app menu's own Settings item rather than
    /// opening a window of its own, so there is exactly one route to the Settings scene.
    case settings
    /// **The exit that had no door.** `applicationShouldTerminateAfterLastWindowClosed` answers
    /// `false`, so with the cockpit shut the only way out was the Dock icon's own menu — which is
    /// AppKit's, not the app's, and says nothing about the nudge loop's last write.
    case quit

    public var id: String { rawValue }

    /// The catalog key this item's title is drawn from, in the watching state it is drawn in.
    ///
    /// `sensingPaused` is a parameter rather than a stored field for the reason
    /// `MenuBarAction.setSensingPaused` carries a value rather than being a toggle: a title
    /// computed from state the caller passes in cannot go stale, and a stored one can.
    public func titleKey(sensingPaused: Bool) -> ShellStringKey {
        switch self {
        case .openCockpit: .menuBarOpenCockpit
        // The pausing half reuses the menu item's own key rather than declaring a second one
        // reading "Pause Watching": the app menu's ⌃⌘E and this item are the same act.
        case .watching: sensingPaused ? .menuBarResumeWatching : .commandPauseSensing
        case .settings: .menuBarSettings
        case .quit: .menuBarQuit
        }
    }

    /// What a click asks the composition root for.
    public func action(sensingPaused: Bool) -> MenuBarAction {
        switch self {
        case .openCockpit: .openCockpit
        // What the person asked *for*, not a toggle, so a menu built a moment ago cannot invert
        // it — the same rule `setSensingPaused`'s own documentation states.
        case .watching: .setSensingPaused(!sensingPaused)
        case .settings: .openSettings
        case .quit: .quit
        }
    }

    /// **Whether this item may be offered at all, in this world** (focus-6uf).
    ///
    /// The same question the app menu asks, answered from the same place wherever there is a
    /// shared verb: *Pause Watching* is `PriorityCommand.pauseSensing`, so it reads that
    /// predicate rather than restating it, and the day the app menu withdraws the switch this
    /// menu withdraws it too.
    ///
    /// **The other three are `true`, and each is a decision.** They are exactly the shape
    /// `ShellActionEffect.isAvailable` already answers `true` for: opening a declared scene works
    /// with or without a window on screen, and *Quit* is the one item that must never be
    /// unavailable — an application a person cannot leave is worse than one that does the wrong
    /// thing when they do.
    public func isAvailable(in world: ShellCommandWorld) -> Bool {
        switch self {
        case .watching: PriorityCommand.pauseSensing.isAvailable(in: world)
        case .openCockpit, .settings, .quit: true
        }
    }

    /// Whether a separator is drawn **above** this item.
    ///
    /// One, above Quit, which is where every Mac app puts it: the destructive-by-consequence item
    /// is not adjacent to the one somebody reaches for by muscle memory.
    public var isPrecededBySeparator: Bool { self == .quit }
}
