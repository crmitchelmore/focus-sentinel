import AppIntents
import FocusCore
import FocusUI
import Foundation

/// **Why an intent refused** (F-141, focus-mn7).
///
/// A closed vocabulary rather than a caught error, so every refusal has a sentence a person hears
/// out of Shortcuts and the unit lane can fold over the set. The sentences live in `FocusUI`'s
/// catalog with every other word this app says (F-149: `FocusHost` declares no keys).
public enum FocusIntentRefusal: Error, Equatable, Hashable, Sendable {
    /// The app is not running its composition root, so there is nothing to ask.
    case notRunning
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
        case .notRunning: .notRunning
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
        guard commit(trimmed) else { throw FocusIntentRefusal.notRunning }
    }

    /// **Start a session**, exactly when the menu bar would offer to.
    public func startSession() throws {
        guard PriorityCommand.startSession.isAvailable(in: world()) else {
            throw FocusIntentRefusal.sessionAlreadyRunning
        }
        guard send(.startSession).willLand else { throw FocusIntentRefusal.notRunning }
    }

    /// **Finish the session**, exactly when the menu bar would offer to — which is the refusal
    /// the bead names: with no session there is nothing to finish, and an intent that reported
    /// success would be an intent that lied to a shortcut.
    public func finishSession() throws {
        guard PriorityCommand.completeSession.isAvailable(in: world()) else {
            throw FocusIntentRefusal.noSessionToFinish
        }
        guard send(.completeSession).willLand else { throw FocusIntentRefusal.notRunning }
    }
}

extension FocusIntentRunner {
    /// **The one the shipping intents use.**
    ///
    /// The world and the send are the command host's own — the same object and the same two
    /// calls the menu bar makes — so an intent and a menu item can never disagree about whether
    /// a verb would do anything. The commit reaches the priority host, which is the only route
    /// in this application that writes a commitment.
    public static var live: FocusIntentRunner {
        FocusIntentRunner(
            world: { FocusCommandCenter.shared.world },
            send: { FocusCommandCenter.shared.send($0) },
            commit: { text in
                AppComposition.shared.priorityHost.setPriority(intent: text, doneWhen: nil)
                return AppComposition.shared.priorityHost.state.priority?.intent == text
            }
        )
    }
}

/// **Set what you are working on**, from Shortcuts or from Siri.
@available(macOS 26.0, *)
public struct SetFocusPriorityIntent: AppIntent {
    public static var title: LocalizedStringResource { FocusIntentCopy.setPriorityTitle }
    public static var description: IntentDescription {
        IntentDescription(FocusIntentCopy.setPriorityDescription)
    }

    @Parameter(title: FocusIntentCopy.priorityParameterTitle)
    public var priority: String

    public init() {}

    public init(priority: String) { self.priority = priority }

    @MainActor
    public func perform() async throws -> some IntentResult {
        try FocusIntentRunner.live.setPriority(priority)
        return .result()
    }
}

/// **Start a session**, exactly when the File menu would offer to.
@available(macOS 26.0, *)
public struct StartFocusSessionIntent: AppIntent {
    public static var title: LocalizedStringResource { FocusIntentCopy.startSessionTitle }
    public static var description: IntentDescription {
        IntentDescription(FocusIntentCopy.startSessionDescription)
    }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        try FocusIntentRunner.live.startSession()
        return .result()
    }
}

/// **Finish the session**, and refuse when there is none — the refusal the bead names.
@available(macOS 26.0, *)
public struct FinishFocusSessionIntent: AppIntent {
    public static var title: LocalizedStringResource { FocusIntentCopy.finishSessionTitle }
    public static var description: IntentDescription {
        IntentDescription(FocusIntentCopy.finishSessionDescription)
    }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        try FocusIntentRunner.live.finishSession()
        return .result()
    }
}

/// The three, as Shortcuts sees them.
@available(macOS 26.0, *)
public struct FocusAppShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetFocusPriorityIntent(),
            phrases: ["Set my \(.applicationName) priority"],
            shortTitle: FocusIntentCopy.setPriorityTitle,
            systemImageName: "target"
        )
        AppShortcut(
            intent: StartFocusSessionIntent(),
            phrases: ["Start a \(.applicationName) session"],
            shortTitle: FocusIntentCopy.startSessionTitle,
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: FinishFocusSessionIntent(),
            phrases: ["Finish my \(.applicationName) session"],
            shortTitle: FocusIntentCopy.finishSessionTitle,
            systemImageName: "checkmark.circle"
        )
    }
}
