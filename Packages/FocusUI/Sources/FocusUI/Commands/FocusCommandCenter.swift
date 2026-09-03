import SwiftUI

/// Something the menu bar asks the cockpit to do.
///
/// Typed, and declared beside the registry that binds the key equivalents, so a menu item and
/// the surface that answers it cannot disagree about what the command *is*.
///
/// From e03 it carries session and sensing verbs as well as priority ones, and they stay in one
/// enum for one reason: the cockpit answers all of them, so they travel down one channel to one
/// registered handler. A second command type would mean a second buffer, and two buffers would
/// eventually deliver two commands in an order neither of them chose.
public enum PriorityCommand: String, Sendable, CaseIterable, Hashable {
    /// Put the cursor in the capture field, ready for a new sentence.
    case newPriority
    /// Open the completion sheet for the current priority.
    case completePriority
    /// Open the file importer for the current priority's context pack.
    case addFilesToContext
    /// Begin a session on the active priority (F-98).
    case startSession
    /// The person's own pause. Sends `paused(cause: .user)`, which only a `.user` resume lifts.
    case pauseSession
    /// Finish the session. Deliberately a different verb from *Complete Priority*: a task can
    /// span many sessions, so ending one is not finishing the other.
    case completeSession
    /// F-119's global switch, from the menu bar. It detaches every observer rather than setting
    /// a flag, and the same stored value drives the cockpit's own control.
    case pauseSensing

    // The e05 verbs. Every one of them is an action a person can already take by clicking a
    // nudge, and F-145's rule is that a click is never the *only* way: an affordance reachable
    // only with a mouse is an affordance somebody cannot reach.
    //
    // Two of the panel's six actions are deliberately **not** here, because they already are:
    // "Pause" is `pauseSession` and "Change priority" is `newPriority`, which opens e02's
    // capture surface. A second command for either would be a second name for one act.

    /// "This is relevant" — the durable task-authority rule, from the keyboard.
    case thisIsRelevant
    /// Snooze the subject the current nudge is about, for the shortest of
    /// `InterventionPolicy.snoozeDurations`. The menu cannot offer three spans without three
    /// items, and the shortest is the least presumptuous default.
    case snoozeNudge
    /// **F-81's one command.** Take every overlay off the screen at once, without answering
    /// anything and without writing anything. It is the panic key, and it is exactly as
    /// non-coercive as every other surface: it hides, it does not silence.
    case hideOverlays
    /// Open the menu-bar popover from the keyboard, so the command centre is not mouse-only.
    case showMenuBar

    /// Whether this command needs the cockpit window in front of it.
    ///
    /// The three capture-and-context verbs and the four session verbs all land **in** the
    /// cockpit, so it comes forward first — that is what makes ⌘N from a closed window put the
    /// cursor in the capture field. The e05 verbs do not: hiding an overlay by opening a window
    /// on top of the person's work would be the opposite of what they asked for.
    public var opensCockpit: Bool {
        switch self {
        case .newPriority, .completePriority, .addFilesToContext,
             .startSession, .pauseSession, .completeSession, .pauseSensing:
            true
        case .thisIsRelevant, .snoozeNudge, .hideOverlays, .showMenuBar:
            false
        }
    }
}

/// How a menu item reaches the cockpit.
///
/// A menu action and the window that carries it out are in different parts of the scene graph
/// — `Commands` cannot see a `Window`'s state — so something has to sit between them. This is
/// that something, and it is deliberately the smallest thing that works: one registered
/// handler, and one command buffered for the moment there is none.
///
/// **The buffer is a feature, not a queue.** ⌘N with the cockpit closed should open the
/// cockpit and land in the capture field; the window takes a run loop turn to exist, so the
/// command waits for it. Only the most recent command is held — a person who presses ⌘N and
/// then ⌘O before the window appears meant the second one.
///
/// A single instance, because the app has a single cockpit: `Window`, not `WindowGroup`, so
/// there is exactly one surface that could ever register.
///
/// ## The buffer is armed by a window opening, and by nothing else (focus-mwm)
///
/// "The window takes a run loop turn to exist, so the command waits for it" is the **whole**
/// justification for holding a command, and it is only true when something has actually asked a
/// window to exist. It was not true of every other caller: `send` stored the command whenever no
/// handler was registered, so the menu-bar popover's four buttons and the nudge panel's Pause and
/// Change priority — none of which opened anything — dropped their commands into a buffer that
/// would be emptied the next time the person happened to open the cockpit, or never.
///
/// So the raise moved **into** this object. `send` opens the cockpit itself for every command
/// whose `opensCockpit` is true, which is one place instead of one per caller, and it buffers
/// only when it actually did so. Everything else it cannot deliver it **refuses**, out loud, in
/// its return value — which is not `@discardableResult`, so a caller cannot fail to have an
/// opinion about a command that went nowhere.
@MainActor
public final class FocusCommandCenter {
    public static let shared = FocusCommandCenter()

    private var handler: ((PriorityCommand) -> Void)?
    private var pending: PriorityCommand?

    /// How the cockpit window is brought into existence and to the front.
    ///
    /// Supplied by `ShellCommands`, which is the one thing in the application that holds
    /// SwiftUI's `openWindow` — and it has to be SwiftUI's. Measured in the shipping process by
    /// `SelfCheck.cockpitRenderingReport`: a launch that inherits a closed cockpit has **no
    /// `NSWindow` for it at all**, so there is nothing for AppKit to order front; only
    /// `openWindow(id:)` can create one. This is deliberately not `NSApp.activate` or
    /// `makeKeyAndOrderFront` — R-96e bans both outside two pinned files, and a window this app
    /// opens because the person pressed a button labelled *"Open Focus Sentinel"* needs neither.
    private var cockpitOpener: (() -> Void)?

    /// **How the shell asks what the app can be asked to do** (focus-6uf).
    ///
    /// A closure rather than a stored value, and that is the whole design. The menu bar reads
    /// `world` inside a `Commands` body; the closure the composition root installs reads
    /// `priorityHost.state`, `sessionHost.snapshot` and the nudge loop — all `@Observable` — so
    /// SwiftUI's observation follows the read straight through to the hosts and the menu is
    /// re-evaluated when any of them moves. A pushed value would need somebody to remember to
    /// push it, and *"a rule held in step by memory"* is the shape this repair exists to delete.
    private var worldProvider: (() -> ShellCommandWorld)?

    /// What the app can be asked to do right now.
    ///
    /// `nothingIsCommitted` until a root installs a provider, which is the honest answer for a
    /// unit process and a preview: no priority, no session, no nudge, and every verb that needs
    /// one withdrawn.
    public var world: ShellCommandWorld { worldProvider?() ?? .nothingIsCommitted }

    /// Install the one reading of the world.
    ///
    /// Idempotent and root-owned, in the shape `registerCockpitOpener` already established:
    /// there is one composition root and it is the only object that can see all three facts.
    public func provideWorld(_ read: @escaping () -> ShellCommandWorld) {
        worldProvider = read
    }

    /// Whether anything in this process can raise the cockpit.
    ///
    /// Read by the self-check, because "the opener was installed" is a wire like any other and a
    /// wire nobody asserts is a wire that goes quiet. `false` in a unit process, which is what
    /// makes `.undeliverable` a state the unit lane can drive.
    public var canRaiseCockpit: Bool { cockpitOpener != nil }

    /// How many times the cockpit has been asked to come forward.
    ///
    /// Observable whether an opener is installed or not, so a test can prove the *request* was
    /// made without a scene graph to answer it.
    public private(set) var cockpitRequests = 0
    /// Additional listeners, delivered **after** the registered handler.
    ///
    /// Not a second buffer — that is the thing this type's documentation rules out, and the
    /// reason is that two buffers eventually deliver two commands in an order neither of them
    /// chose. There is still exactly one queue and exactly one ordering; what e05 adds is that
    /// one command can reach two places, because the cockpit answers the capture and session
    /// verbs and the nudge loop answers the nudge ones.
    private var observers: [(PriorityCommand) -> Void] = []

    public init() {}

    /// Whether a surface is currently listening.
    public var isConnected: Bool { handler != nil }

    /// Start answering commands. Any command that arrived while nothing was listening is
    /// delivered immediately.
    public func register(_ handler: @escaping (PriorityCommand) -> Void) {
        self.handler = handler
        if let pending {
            self.pending = nil
            handler(pending)
        }
    }

    public func unregister() {
        handler = nil
    }

    /// Listen to every command, without claiming the buffer.
    ///
    /// An observer never receives a *pending* command: the buffer exists so a key equivalent can
    /// outlive a closed window, and an observer that is always present has nothing to wait for.
    public func observe(_ observer: @escaping (PriorityCommand) -> Void) {
        observers.append(observer)
    }

    /// Install the one route to the cockpit window.
    ///
    /// Idempotent: `ShellCommands` installs it every time its `body` is evaluated, and the
    /// closure it installs is the same closure over the same scene.
    public func registerCockpitOpener(_ open: @escaping () -> Void) {
        cockpitOpener = open
    }

    /// Take the route away again.
    ///
    /// The symmetric half of `register`/`unregister`, and it exists for the same reason: a test
    /// that installs an opener on the shared centre — which is the object the app delegate's
    /// reopen handler reaches, so a test of that handler has no choice — must be able to put the
    /// process back the way it found it. Without it, `canRaiseCockpit` would be `true` for every
    /// suite that ran afterwards, and `send(_:)` would start buffering commands nothing was ever
    /// going to answer.
    public func unregisterCockpitOpener() {
        cockpitOpener = nil
    }

    /// **Bring the cockpit forward**, and say whether anything could.
    ///
    /// A verb of its own because one surface asks for exactly this and nothing else: the
    /// popover's *"Open Focus Sentinel"* button, whose string's own comment reads *"bring the
    /// main window forward"*. It used to send `.newPriority` — which, with the cockpit closed,
    /// went into the buffer and did nothing at all, and with the cockpit open behind another
    /// application set `isCapturing` on a window nobody could see.
    @discardableResult
    public func requestCockpit() -> Bool {
        cockpitRequests += 1
        guard let cockpitOpener else { return false }
        cockpitOpener()
        return true
    }

    /// Deliver a command, and say what became of it.
    ///
    /// The result is **not** `@discardableResult` on purpose. Every caller has to say what it
    /// means to do about a command that landed nowhere, because the defect this shape replaces
    /// was five callers that had never been asked the question.
    public func send(_ command: PriorityCommand) -> CommandDelivery {
        // **The raise is here, once, rather than at each call site.** `ShellCommands.perform`
        // used to do it, and it was the only caller that did; the two that did not are the ones
        // a person reaches with the main window shut.
        if command.opensCockpit {
            requestCockpit()
        }

        if let handler {
            handler(command)
            notify(command)
            return .delivered
        }

        notify(command)

        // Held **only** because a window is on its way to answer it. Without an opener there is
        // no window coming, and storing the command would be storing it for ever.
        if command.opensCockpit, canRaiseCockpit {
            pending = command
            return .awaitingCockpit
        }
        // The e05 verbs are the nudge loop's, and the loop listens as an observer for the life of
        // the process — so "no handler" is not "nowhere to land" for them.
        return observers.isEmpty ? .undeliverable : .delivered
    }

    private func notify(_ command: PriorityCommand) {
        for observer in observers { observer(command) }
    }
}

/// **What became of a command.** Total, and returned rather than logged, because the three
/// outcomes are three different facts about somebody's click (focus-mwm).
public enum CommandDelivery: String, Sendable, Equatable, CaseIterable {
    /// A live listener performed it — the cockpit's registered handler, an observer, or both.
    case delivered
    /// Nothing was listening, the cockpit has been asked to open, and it will be delivered the
    /// moment that window registers. The one case the buffer was written for.
    case awaitingCockpit
    /// Nothing was listening and nothing is coming. **It will never land**, and a caller that
    /// records an effect after seeing this is recording something that did not happen.
    case undeliverable

    /// Whether the person's click reached, or will reach, something that can carry it out.
    public var willLand: Bool { self != .undeliverable }
}
