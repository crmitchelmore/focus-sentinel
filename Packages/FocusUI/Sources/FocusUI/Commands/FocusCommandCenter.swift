import SwiftUI

/// Something the menu bar asks the cockpit to do.
///
/// Typed, and declared beside the registry that binds the key equivalents, so a menu item and
/// the surface that answers it cannot disagree about what the command *is*.
public enum PriorityCommand: String, Sendable, CaseIterable, Hashable {
    /// Put the cursor in the capture field, ready for a new sentence.
    case newPriority
    /// Open the completion sheet for the current priority.
    case completePriority
    /// Open the file importer for the current priority's context pack.
    case addFilesToContext
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

    public func send(_ command: PriorityCommand) {
        if let handler {
            handler(command)
        } else {
            pending = command
        }
    }
}
