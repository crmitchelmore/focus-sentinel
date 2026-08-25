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
@MainActor
public final class FocusCommandCenter {
    public static let shared = FocusCommandCenter()

    private var handler: ((PriorityCommand) -> Void)?
    private var pending: PriorityCommand?
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

    public func send(_ command: PriorityCommand) {
        if let handler {
            handler(command)
        } else {
            pending = command
        }
        for observer in observers { observer(command) }
    }
}
