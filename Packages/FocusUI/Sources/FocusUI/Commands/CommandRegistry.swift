import FocusCore
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
    /// e01 registered actions in `file` and `help` only; the other four menus were entirely
    /// the system's, so there was no heading to invent for them. A test asserts that every
    /// placement the registry actually populates has a heading, so the epic that first adds an
    /// action to another menu is told to add its heading rather than shipping an unnamed group
    /// — and **e05 is that epic**: the four nudge verbs live in `view`, which is where a person
    /// looks for "hide this", and `view` therefore gains a heading here.
    public var headingKey: ShellStringKey? {
        switch self {
        case .file: .helpGroupFile
        case .view: .helpGroupView
        case .help: .helpGroupHelp
        case .app, .edit, .window: nil
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
    /// e09a. The day's ledger. A **window**, not a sidebar row: the shell has two destinations
    /// and no split view, and `ShellActionEffect` has no "select destination" member — adding
    /// one is uncosted work the epic review left to e09b. History is reached from the cockpit
    /// and from the View menu, which is the route that exists today.
    case history

    public var id: String { rawValue }

    /// The window's title, which is also how it appears in the Window menu.
    public var titleKey: ShellStringKey {
        switch self {
        case .cockpit: .cockpitWindowTitle
        case .help: .helpWindowTitle
        case .history: .historyWindowTitle
        }
    }

    /// **The size a window opens at when nothing has been saved for it**, in points
    /// (focus-2er).
    ///
    /// Here rather than as two literals in the scene, because `App/` is not a package and a
    /// number nobody can read is a number nobody can defend. Measured against the real window:
    /// with e03's session controls and sensing status added, the cockpit outgrew the 704-point
    /// window e02 shipped and the footer was clipped below the fold. A window whose last two
    /// lines are unreachable is a defect however good the lines are.
    ///
    /// **The Keyboard Shortcuts window has one too now, and it is measured** (focus-odz.6).
    ///
    /// It was `nil`, on the argument that *"the reference is one column of rows, and giving it a
    /// fixed frame would mean choosing a size for text whose length the person's own type settings
    /// decide"*. That argument is about a **fixed frame**; `defaultSize` is the size a window
    /// opens at when nothing has been saved for it, and it stays freely resizable afterwards. The
    /// alternative to this app choosing an opening size is not the person choosing one — it is
    /// AppKit choosing, which it does badly for a content-sized SwiftUI scene.
    ///
    /// 520 × 720 is read off the committed baselines rather than chosen by eye:
    /// `shortcutsHelp.light.standard` is **520 × 689.5** points since e07a added the three
    /// answers to the View menu (it was 623.5), so the window opens wide enough that no row
    /// wraps its glyphs under its label and tall enough that the whole reference is on screen at
    /// standard type. At `accessibilityLarge` the same content is far taller and does not fit —
    /// which is right, and is what a resizable window is for. Opening at the size the largest
    /// type setting needs would give everybody else a window two-thirds empty.
    public var defaultSize: (width: Double, height: Double)? {
        switch self {
        case .cockpit: (width: 560, height: 900)
        case .help: (width: 520, height: 720)
        // Wider than the reference and as tall: a ledger row carries a label, a subject, a
        // reason and — on a silent interval — a button, and at 520 the reason wraps under the
        // subject on every row. Read off the committed `history.light.standard` baseline the
        // same way the two above were.
        case .history: (width: 620, height: 720)
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
    /// Ask the cockpit to do something. The cockpit window is brought forward first, so a
    /// command is never a key press that appears to do nothing because the window was closed.
    case priority(PriorityCommand)
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

/// **What the app can be asked to do right now** (focus-6uf).
///
/// The facts the command guards read, as one value, so the question *"would this verb do
/// anything?"* has one answer rather than one per surface. Every field is something the
/// composition root already knows and something an `@Observable` host publishes, which is what
/// lets the menu bar read it during its own layout and redraw when it moves.
///
/// It carries **only** the facts a command's availability actually turns on. A world with a field
/// nothing reads is a field that drifts, and the surfaces that would keep it in step are the two
/// this type exists to stop disagreeing.
public struct ShellCommandWorld: Sendable, Equatable, Hashable {
    /// Whether a commitment exists for the priority verbs to act on.
    public var hasPriority: Bool
    /// The phase of the session the person is in, or `nil` when there is none.
    ///
    /// The phase rather than three booleans: *"there is a session"*, *"it is paused"* and *"it is
    /// over"* are three readings of one value, and three booleans are three things to keep in
    /// step. `SessionControls.verbButtons` already draws from the phase for the same reason.
    public var sessionPhase: SessionPhase?
    /// Whether an **accusation** is on screen for the two verbs that answer one.
    public var hasOpenNudge: Bool
    /// **Whether a question is on screen for the three verbs that answer one** (e07a T1).
    ///
    /// A second field rather than a widening of `hasOpenNudge`, because the loop that publishes
    /// them keeps the two nudges apart and the five verbs are not interchangeable: *Mark as
    /// Relevant* answers an accusation and *Yes, it's part of it* answers a question, and a menu
    /// that offered either whenever the other was up would be back to the permanently-enabled
    /// items focus-6uf measured.
    public var hasOpenQuestion: Bool

    public init(
        hasPriority: Bool = false,
        sessionPhase: SessionPhase? = nil,
        hasOpenNudge: Bool = false,
        hasOpenQuestion: Bool = false
    ) {
        self.hasPriority = hasPriority
        self.sessionPhase = sessionPhase
        self.hasOpenNudge = hasOpenNudge
        self.hasOpenQuestion = hasOpenQuestion
    }

    /// **The world a process that has been told nothing is in**, and the honest default.
    ///
    /// Not a permissive one. A unit process, a preview and the moment before the composition root
    /// installs its provider all have no priority, no session and no nudge — so every verb that
    /// needs one is withdrawn, which is what the person would see if it really were true. A
    /// default that answered *"everything is possible"* would put the defect back for exactly the
    /// callers nobody drives.
    public static let nothingIsCommitted = ShellCommandWorld()
}

extension PriorityCommand {
    /// **Whether this verb would do anything, in this world** (focus-6uf).
    ///
    /// The guards were written three times — `CockpitView.perform(_:)` for the priority and
    /// session verbs, `NudgeHost.perform(_:)` for the nudge ones, and nowhere at all for the menu
    /// item that sends them, which is why all thirteen items were permanently enabled and six of
    /// them silently did nothing in the state a person is in the first time they open the menu.
    /// `CockpitView.swift` states the rule it broke in its own comment: *"a shortcut that
    /// silently does nothing is a shortcut people stop trusting."*
    ///
    /// This is that rule, once. The menu disables what it cannot do; the two `perform`
    /// implementations refuse the same thing by asking the same question, so a key equivalent
    /// that slipped through a stale menu still cannot perform a verb the app would reject.
    ///
    /// **The three `true`s are decisions, not omissions.**
    ///
    /// * `newPriority` and `addFilesToContext` always land: with no commitment the second one
    ///   opens the capture field rather than a file panel with nowhere to put its result, which
    ///   is an effect and not a no-op.
    /// * `pauseSensing` is a switch, and a switch has both positions in every state.
    /// * `hideOverlays` is F-81's panic key. A person presses it *because* they do not know what
    ///   is on their screen, and a panic key that greys itself out when the app believes nothing
    ///   is showing would be unavailable in precisely the case where the app is wrong.
    /// * `showMenuBar` opens the popover, which exists for the life of the process.
    public func isAvailable(in world: ShellCommandWorld) -> Bool {
        switch self {
        case .newPriority, .addFilesToContext, .pauseSensing, .hideOverlays, .showMenuBar:
            true
        case .completePriority:
            world.hasPriority
        // **The three session verbs, from the phase, exactly as the cockpit already draws them.**
        //
        // `SessionControls.verbButtons` is the sibling the bead names: it draws only the verbs
        // the machine would accept from the phase the session is in. The menu duplicated those
        // verbs and kept `CockpitView.perform(_:)`'s guards instead, and the two disagreed in
        // both directions — with a finished session the guards offered *Pause* (the machine would
        // reject it) and refused *Start* (the cockpit draws its Start button for exactly that
        // phase, so ⌃⌘S did nothing while the button beside it worked).
        //
        // The phase is the whole rule. A terminal session is over, so the only verb left is
        // beginning again; a paused one may be finished but not paused twice; and with no session
        // at all there is nothing to pause or finish.
        case .startSession:
            world.sessionPhase.map(\.isTerminal) ?? true
        case .pauseSession:
            world.sessionPhase.map { !$0.isTerminal && $0 != .paused } ?? false
        case .completeSession:
            world.sessionPhase.map { !$0.isTerminal } ?? false
        // The two that answer a nudge. With none on screen there is nothing to be relevant and
        // nothing to snooze, and the loop's own guards say so.
        case .thisIsRelevant, .snoozeNudge:
            world.hasOpenNudge
        // The three that answer a question — on the *question's* field, not the accusation's.
        // The two nudges are separate values in the loop, and a menu that read one for the other
        // would offer all five whenever either was up and drop three of them silently, which is
        // the defect focus-6uf repaired.
        case .answerYes, .answerNo, .answerNotNow:
            world.hasOpenQuestion
        }
    }
}

extension ShellActionEffect {
    /// Whether the action carrying this effect would do anything, in this world.
    ///
    /// **`closeKeyWindow` and `openWindow` are always available, and both are reasoned.**
    /// Opening a declared scene works with or without a window already on screen. ⌘W is the
    /// registry's claim on the Mac's own close key — the File menu exists at all because
    /// something had to claim it (see `CommandRegistry.shell`) — and AppKit contributes its own
    /// validated `Close` beside it, which is the item that greys out when there is nothing to
    /// close. Gating this one on a `NSApp.keyWindow` read would bind a key equivalent to a fact
    /// no observation reports, so the menu would keep whatever answer it last computed and ⌘W
    /// would go dead after a window closed.
    public func isAvailable(in world: ShellCommandWorld) -> Bool {
        switch self {
        case .closeKeyWindow, .openWindow:
            true
        case .priority(let command):
            command.isAvailable(in: world)
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

    /// **Whether this item may be offered at all, in this world** (focus-6uf).
    ///
    /// Read by `ShellActionButton` to decide `.disabled(…)`, by the two `perform`
    /// implementations to refuse a verb they would otherwise silently drop, and by the
    /// self-check so the gate can assert every item's `isEnabled` against it rather than
    /// against a constant.
    public func isAvailable(in world: ShellCommandWorld) -> Bool { effect.isAvailable(in: world) }
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

    /// Every action the shell ships, in menu order. All five are real:
    ///
    /// * **New Priority ⌘N.** The app's primary act. It brings the cockpit forward and puts
    ///   the cursor in the capture field.
    /// * **Add Files to Context… ⌘O.** ⌘O is the Mac's "open something" key, and in an app
    ///   with no documents the thing being opened is an attachment for the current priority.
    /// * **Complete Priority ⌃⌘⏎.** Deliberately *not* ⌘⏎: plain Return commits the sentence
    ///   in whatever field has focus, and finishing the thing you are working on must not be
    ///   one modifier away from typing.
    /// * **Close Window ⌘W.** Not decoration. A `Window`-scene app that replaces `.newItem`
    ///   with nothing gets no File menu at all and leaves ⌘W unbound — a closable window
    ///   with no keyboard close, which is a HIG defect. Registering a File action
    ///   materialises the File menu; AppKit then adds its own `Close` and `Close All ⌥⌘W`
    ///   beneath it.
    /// * **Focus Sentinel Help ⌘?.** Replaces SwiftUI's default Help item, which points at a
    ///   help book that does not exist. A menu item that leads nowhere is a defect; this one
    ///   opens the in-app shortcut reference.
    ///
    /// e03 adds four more, all real:
    ///
    /// * **Start Session ⌃⌘S**, **Pause Session ⌃⌘P** and **Finish Session ⌃⌘F.** Session verbs
    ///   the cockpit's own controls also offer, reached from anywhere.
    /// * **Pause Watching ⌃⌘E.** F-119's global switch. It is *not* ⇧⌘W, which is what it was
    ///   first bound to: the self-check measured a plain ⌘W reaching that item and flipping the
    ///   stored switch on three consecutive runs, so the app would have been quietly taking
    ///   ⌘W away from the person.
    ///
    /// `Complete Priority` reuses the cockpit button's own title key rather than declaring a
    /// second one: the menu item and the button are the same action, and two keys reading
    /// "Complete Priority" would be two things to keep in step for no gain. The three session
    /// items do the same with `session.action.*`.
    public static let shell = CommandRegistry(actions: [
        ShellAction(
            id: "priority.new",
            titleKey: .commandNewPriority,
            shortcut: Shortcut("n", modifiers: .command),
            placement: .file,
            effect: .priority(.newPriority)
        ),
        ShellAction(
            id: "context.addFiles",
            titleKey: .commandAddFilesToContext,
            shortcut: Shortcut("o", modifiers: .command),
            placement: .file,
            effect: .priority(.addFilesToContext)
        ),
        ShellAction(
            id: "priority.complete",
            titleKey: .priorityActionComplete,
            shortcut: Shortcut("\r", modifiers: [.control, .command]),
            placement: .file,
            effect: .priority(.completePriority)
        ),
        // The four e03 verbs, all ⌃⌘ combinations rather than plain ⌘ ones, for the reason
        // `priority.complete` already gives: this window is full of text fields, and a session
        // verb one modifier away from typing is a session verb somebody will trigger by
        // accident.
        //
        // **Pause Watching was ⇧⌘W and is not, and the reason is measured.** The app's own
        // `--focus-self-check` hands `NSApp.mainMenu` a synthesised ⌘W and reports what the menu
        // bar claimed. With Pause Watching on ⇧⌘W, three consecutive runs came back with the
        // stored watching switch flipped every time — a plain ⌘W was reaching the shifted item
        // as well as Close Window. An app that takes ⌘W away from a person because it wanted a
        // nearby shortcut is exactly the HIG defect the Court's review of the File menu was
        // about, so the base character moved off `w` entirely rather than the modifier being
        // adjusted. No two actions in this registry now share a base character.
        ShellAction(
            id: "session.start",
            titleKey: .sessionActionStart,
            shortcut: Shortcut("s", modifiers: [.control, .command]),
            placement: .file,
            effect: .priority(.startSession)
        ),
        ShellAction(
            id: "session.pause",
            titleKey: .sessionActionPause,
            shortcut: Shortcut("p", modifiers: [.control, .command]),
            placement: .file,
            effect: .priority(.pauseSession)
        ),
        ShellAction(
            id: "session.complete",
            titleKey: .sessionActionComplete,
            shortcut: Shortcut("f", modifiers: [.control, .command]),
            placement: .file,
            effect: .priority(.completeSession)
        ),
        ShellAction(
            id: "sensing.pause",
            titleKey: .commandPauseSensing,
            shortcut: Shortcut("e", modifiers: [.control, .command]),
            placement: .file,
            effect: .priority(.pauseSensing)
        ),
        ShellAction(
            id: "shell.closeWindow",
            titleKey: .commandCloseWindow,
            shortcut: Shortcut("w", modifiers: .command),
            placement: .file,
            effect: .closeKeyWindow
        ),
        // --- e05: every nudge action is reachable from the keyboard (F-145) ------------------
        //
        // Four, in the View menu, all on ⌃⌘ for the reason `priority.complete` already gives:
        // a nudge lands while somebody is typing, and a verb one modifier away from typing is a
        // verb somebody will trigger by accident. No two actions in this registry share a base
        // character, which is the rule the ⇧⌘W defect taught (see the note above).
        //
        // **"Hide All Overlays" is not a bare Escape**, and F-81 does not ask for one. Escape is
        // already the panel's own dismissal through `NudgePanel.cancelOperation(_:)`, where it
        // reaches the surface the person is looking at; binding it as a *menu* key equivalent
        // would take the Escape key away from every text field in the application.
        ShellAction(
            id: "nudge.relevant",
            titleKey: .commandThisIsRelevant,
            shortcut: Shortcut("r", modifiers: [.control, .command]),
            placement: .view,
            effect: .priority(.thisIsRelevant)
        ),
        ShellAction(
            id: "nudge.snooze",
            titleKey: .commandSnoozeNudge,
            shortcut: Shortcut("z", modifiers: [.control, .command]),
            placement: .view,
            effect: .priority(.snoozeNudge)
        ),
        ShellAction(
            id: "nudge.hideOverlays",
            titleKey: .commandHideOverlays,
            shortcut: Shortcut("h", modifiers: [.control, .command]),
            placement: .view,
            effect: .priority(.hideOverlays)
        ),
        ShellAction(
            id: "nudge.menuBar",
            titleKey: .commandShowMenuBar,
            shortcut: Shortcut("m", modifiers: [.control, .command]),
            placement: .view,
            effect: .priority(.showMenuBar)
        ),
        // --- e07a: a question can be answered with no mouse (U-1, F-145) --------------------
        //
        // Three more, beside the accusation's two, and the reason they are *menu* items rather
        // than keys on the panel is measured: `NudgePanel` is a `.nonactivatingPanel`, shown with
        // `orderFrontRegardless()` and never made key, so no `.keyboardShortcut` on its content
        // would ever be evaluated and its Escape reaches the person's editor. A menu key
        // equivalent fires while Focus is active, which is one ⌘-Tab away — and activating Focus
        // leaves the question standing (`KeyboardAnswerTests`). A global hot key was rejected:
        // `CarbonHotKeyRegistrar` is one registration, and P-55 measured that the API reports no
        // system collision at all.
        //
        // ⌃⌘ for the reason every nudge verb is, and Y, U and L because no other action in this
        // registry has those base characters — the rule the ⇧⌘W defect taught.
        ShellAction(
            id: "nudge.answerYes",
            titleKey: .commandAnswerYes,
            shortcut: Shortcut("y", modifiers: [.control, .command]),
            placement: .view,
            effect: .priority(.answerYes)
        ),
        ShellAction(
            id: "nudge.answerNo",
            titleKey: .commandAnswerNo,
            shortcut: Shortcut("u", modifiers: [.control, .command]),
            placement: .view,
            effect: .priority(.answerNo)
        ),
        ShellAction(
            id: "nudge.answerNotNow",
            titleKey: .commandAnswerNotNow,
            shortcut: Shortcut("l", modifiers: [.control, .command]),
            placement: .view,
            effect: .priority(.answerNotNow)
        ),

        // --- e09a: the day's ledger, in the View menu (F-104, focus-tee.5) ------------------
        //
        // ⌃⌘D like every other verb a person reaches while working, and D because no other
        // action in this registry has that base character — the rule the ⇧⌘W defect taught.
        ShellAction(
            id: "shell.history",
            titleKey: .commandShowHistory,
            shortcut: Shortcut("d", modifiers: [.control, .command]),
            placement: .view,
            effect: .openWindow(.history)
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
