import FocusCore
import Foundation

/// **Why an intent refused** (F-141, focus-mn7).
///
/// A closed vocabulary rather than a caught error, so every refusal has a sentence a person hears
/// out of Shortcuts and the unit lane can fold over the set. The sentences live in `FocusUI`'s
/// catalog with every other word this app says (F-149: `FocusHost` declares no keys).
public enum FocusIntentRefusal: Error, Equatable, Hashable, Sendable {
    /// The command host is unavailable or could not persist the requested change.
    case unavailable
    /// The person gave no priority to commit to.
    case emptyPriority
    /// A session is already running, so there is nothing to start.
    case sessionAlreadyRunning
    /// There is no session to finish.
    case noSessionToFinish

    /// The same case, named in `FocusUI` where the sentence lives. An exhaustive `switch`, so a
    /// refusal added here without a sentence does not compile.
    public var copy: FocusIntentCopy.Refusal {
        switch self {
        case .unavailable: .unavailable
        case .emptyPriority: .emptyPriority
        case .sessionAlreadyRunning: .sessionAlreadyRunning
        case .noSessionToFinish: .noSessionToFinish
        }
    }

    /// The sentence, resolved in `FocusUI` and handed over already drawn.
    public var reason: String { copy.sentence }
}

extension FocusIntentRefusal: CustomLocalizedStringResourceConvertible {
    /// **What a person hears when the app refuses**, out of Shortcuts, with nothing on screen.
    /// Without this they hear *"the operation could not be completed"*, which is what an intent
    /// says when nobody wrote it a reason.
    public var localizedStringResource: LocalizedStringResource { copy.resource }
}

/// **The one route the three intents take** (F-141, focus-mn7).
///
/// ## Why it is a value with three closures rather than a call to `AppComposition.shared`
///
/// The brief for every one of these is *"perform through the same command host the menu bar
/// uses"*, and the menu bar's route is `FocusCommandCenter`: the item asks the world whether a
/// command would do anything, draws itself enabled or disabled from the answer, and sends the
/// command. An intent that reached past that into the hosts would be a second implementation of
/// three verbs whose *availability* is the interesting part — and the two would disagree, which
/// is exactly the defect `focus-6uf` measured in the menu itself.
///
/// So the runner asks the same `ShellCommandWorld` the menu asks and sends the same
/// `PriorityCommand` the menu sends. What it adds is the one thing a menu item does not have: a
/// piece of text.
///
/// The closures are what make it drivable. `AppIntent.perform()` runs inside a process the unit
/// lane does not own, so the lane drives **this** against a store it owns, and the intents are a
/// three-line shell over it.
@MainActor
public struct FocusIntentRunner {
    /// What the app can honestly do right now — the same reading the menu bar draws from.
    let world: () -> ShellCommandWorld
    /// The command host's own send. `undeliverable` means nothing was listening and nothing is
    /// coming, which is a refusal and not a silence: a caller that reported success after seeing
    /// it would be reporting something that did not happen.
    let send: (PriorityCommand) -> CommandDelivery
    /// The one thing a command cannot carry: the words the person committed to.
    let commit: (String) -> Bool

    public init(
        world: @escaping () -> ShellCommandWorld,
        send: @escaping (PriorityCommand) -> CommandDelivery,
        commit: @escaping (String) -> Bool
    ) {
        self.world = world
        self.send = send
        self.commit = commit
    }

    /// **Set the priority.** Refuses an empty one: a commitment nobody wrote is not a commitment,
    /// and `IntentValidator` already refuses one typed into the capture field.
    public func setPriority(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FocusIntentRefusal.emptyPriority }
        guard commit(trimmed) else { throw FocusIntentRefusal.unavailable }
    }

    /// **Start a session**, exactly when the menu bar would offer to.
    public func startSession() throws {
        guard PriorityCommand.startSession.isAvailable(in: world()) else {
            throw FocusIntentRefusal.sessionAlreadyRunning
        }
        guard send(.startSession) == .delivered else { throw FocusIntentRefusal.unavailable }
    }

    /// **Finish the session**, exactly when the menu bar would offer to — which is the refusal
    /// the bead names: with no session there is nothing to finish, and an intent that reported
    /// success would be an intent that lied to a shortcut.
    public func finishSession() throws {
        guard PriorityCommand.completeSession.isAvailable(in: world()) else {
            throw FocusIntentRefusal.noSessionToFinish
        }
        guard send(.completeSession) == .delivered else { throw FocusIntentRefusal.unavailable }
    }
}

extension FocusIntentRunner {
    public init(center: FocusCommandCenter) {
        self.init(
            world: { center.world },
            send: { center.performIntentSession($0) ? .delivered : .undeliverable },
            commit: { center.commitPriority($0) }
        )
    }

    public static var live: FocusIntentRunner { FocusIntentRunner(center: .shared) }
}
