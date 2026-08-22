import SwiftUI

/// Which menu an action belongs to.
///
/// Typed rather than stringly, because "which menu is this in" is a question the keyboard
/// reachability test asks of every action, and an action with no menu is a bug this enum
/// makes unrepresentable.
public enum MenuPlacement: String, Sendable, CaseIterable, Hashable {
    case app
    case file
    case edit
    case view
    case window
    case help

    /// The menu bar's own left-to-right order, so anything built from placements — the
    /// shortcut reference in particular — reads in the order the menus do.
    public static let menuBarOrder: [MenuPlacement] = [.app, .file, .edit, .view, .window, .help]

    /// The heading this group carries in the Keyboard Shortcuts window, or `nil` for a menu
    /// the shell adds nothing to.
    ///
    /// e01 registers actions in `file` and `help` only; the other four menus are entirely
    /// the system's, so there is no heading to invent for them. A test asserts that every
    /// placement the registry actually populates has a heading, so the epic that first adds
    /// an action to another menu is told to add its heading rather than shipping an unnamed
    /// group.
    public var headingKey: ShellStringKey? {
        switch self {
        case .file: .helpGroupFile
        case .help: .helpGroupHelp
        case .app, .edit, .view, .window: nil
        }
    }
}

/// A window the app declares as a scene.
///
/// The ids live here rather than in the app target because a menu item that opens a window
/// and the scene that declares it must agree, and the only way to make that structural is
/// for both to read the same table. `FocusSentinelApp` declares one scene per case.
public enum ShellWindow: String, Sendable, CaseIterable, Hashable, Identifiable {
    case cockpit
    case help

    public var id: String { rawValue }

    /// The window's title, which is also how it appears in the Window menu.
    public var titleKey: ShellStringKey {
        switch self {
        case .cockpit: .cockpitWindowTitle
        case .help: .helpWindowTitle
        }
    }
}

/// What an action does.
///
/// Behaviour lives in the registry alongside the title and the shortcut, so the menu bar and
/// the shortcut reference are built from one description of the action rather than from a
/// title table on one side and a switch statement on the other.
public enum ShellActionEffect: Sendable, Equatable, Hashable {
    /// Close the frontmost window, as ⌘W does in every Mac app.
    case closeKeyWindow
    /// Open one of the app's declared scenes.
    case openWindow(ShellWindow)
}

/// A key equivalent, as a value the tests can compare and the help window can draw.
///
/// The character and the modifier mask are stored, not `SwiftUI.KeyEquivalent`, so that the
/// type is `Hashable` — the uniqueness assertion over the whole registry needs to put these
/// in a `Set`.
public struct Shortcut: Sendable, Equatable, Hashable {
    public let character: Character
    private let modifierRawValue: Int

    public init(_ character: Character, modifiers: EventModifiers = .command) {
        self.character = character
        self.modifierRawValue = modifiers.rawValue
    }

    public var modifiers: EventModifiers { EventModifiers(rawValue: modifierRawValue) }

    /// The SwiftUI value, built on demand at the one call site that needs it.
    public var keyEquivalent: KeyEquivalent { KeyEquivalent(character) }

    /// How the shortcut is drawn in the Keyboard Shortcuts window — `⌘W`, `⌥⌘W`, `⌘?`.
    ///
    /// Modifier order is the Mac's own: Control, Option, Shift, Command.
    public var glyphs: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += Self.glyph(for: character)
        return result
    }

    private static func glyph(for character: Character) -> String {
        switch character {
        case " ": "Space"
        case "\t": "⇥"
        case "\r", "\n": "↩"
        case "\u{1b}": "⎋"
        default: String(character).uppercased()
        }
    }
}

/// One shell action: what it is called, what it is bound to, where it lives, and what it
/// does.
public struct ShellAction: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let titleKey: ShellStringKey
    /// The key equivalent, or `nil` for an action that is reachable but not bound. Per the
    /// Court's ruling not every action needs a shortcut; every action must stay *reachable*.
    public let shortcut: Shortcut?
    public let placement: MenuPlacement
    public let effect: ShellActionEffect

    public init(
        id: String,
        titleKey: ShellStringKey,
        shortcut: Shortcut?,
        placement: MenuPlacement,
        effect: ShellActionEffect
    ) {
        self.id = id
        self.titleKey = titleKey
        self.shortcut = shortcut
        self.placement = placement
        self.effect = effect
    }

    /// The localised title, from `FocusUI`'s own catalog.
    public var title: LocalizedStringResource { ShellStrings.resource(titleKey) }
}

/// The single source of truth for every shell action.
///
/// The menu bar is built from it and the Keyboard Shortcuts window is rendered from it, so
/// the two cannot drift: there is one table, one test over that table, and two consumers.
/// The runtime half of the same contract is the app's `--focus-self-check`, which hands
/// synthesised key events to `NSApp.mainMenu` and reports which ones the menu bar claimed.
public struct CommandRegistry: Sendable, Equatable {
    public let actions: [ShellAction]

    public init(actions: [ShellAction]) {
        self.actions = actions
    }

    /// The actions e01 ships. Exactly two, and both are real:
    ///
    /// * **Close Window ⌘W.** Not decoration. A `Window`-scene app that replaces `.newItem`
    ///   with nothing gets no File menu at all and leaves ⌘W unbound — a closable window
    ///   with no keyboard close, which is a HIG defect. Registering this one action
    ///   materialises the File menu; AppKit then adds its own `Close` and `Close All ⌥⌘W`
    ///   beneath it.
    /// * **Focus Sentinel Help ⌘?.** Replaces SwiftUI's default Help item, which points at a
    ///   help book that does not exist. A menu item that leads nowhere is a defect; this one
    ///   opens the in-app shortcut reference.
    ///
    /// Nothing else is here, because nothing else has behaviour today. e02 adds
    /// "New Priority… ⌘N" to the same `file` group.
    public static let shell = CommandRegistry(actions: [
        ShellAction(
            id: "shell.closeWindow",
            titleKey: .commandCloseWindow,
            shortcut: Shortcut("w", modifiers: .command),
            placement: .file,
            effect: .closeKeyWindow
        ),
        ShellAction(
            id: "shell.help",
            titleKey: .commandHelp,
            shortcut: Shortcut("?", modifiers: .command),
            placement: .help,
            effect: .openWindow(.help)
        )
    ])

    /// The actions in one menu, in registry order.
    public func actions(in placement: MenuPlacement) -> [ShellAction] {
        actions.filter { $0.placement == placement }
    }

    /// The placements that actually carry an action, in menu-bar order.
    ///
    /// The shortcut reference groups by this, so a menu with no shell action of its own
    /// never becomes an empty heading.
    public var populatedPlacements: [MenuPlacement] {
        MenuPlacement.menuBarOrder.filter { !actions(in: $0).isEmpty }
    }

    public func action(id: String) -> ShellAction? {
        actions.first { $0.id == id }
    }

    /// Key equivalents the system owns, which no app action may claim.
    ///
    /// ⌘W is deliberately **not** on this list. It belongs to the app, and a `Window`-scene
    /// app that fails to claim it ships a window with no keyboard close — measured, not
    /// assumed.
    public static let systemReservedShortcuts: Set<Shortcut> = [
        Shortcut("q", modifiers: .command),
        Shortcut("m", modifiers: .command),
        Shortcut("h", modifiers: .command),
        Shortcut(",", modifiers: .command),
        Shortcut("\t", modifiers: .command),
        Shortcut(" ", modifiers: .command)
    ]
}
