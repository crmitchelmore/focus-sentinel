import AppIntents
import FocusUI
import Foundation

/// **Set what you are working on**, from Shortcuts or from Siri.
@available(macOS 26.0, *)
public struct SetFocusPriorityIntent: AppIntent {
    public static var title: LocalizedStringResource { LocalizedStringResource("shell.intent.setPriority.title") }
    public static var description: IntentDescription {
        IntentDescription(LocalizedStringResource("shell.intent.setPriority.description"))
    }

    @Parameter(title: LocalizedStringResource("shell.intent.setPriority.parameter"))
    public var priority: String

    public init() {}

    public static var openAppWhenRun: Bool { true }

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
    public static var title: LocalizedStringResource { LocalizedStringResource("shell.intent.startSession.title") }
    public static var description: IntentDescription {
        IntentDescription(LocalizedStringResource("shell.intent.startSession.description"))
    }

    public static var openAppWhenRun: Bool { true }

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
    public static var title: LocalizedStringResource { LocalizedStringResource("shell.intent.finishSession.title") }
    public static var description: IntentDescription {
        IntentDescription(LocalizedStringResource("shell.intent.finishSession.description"))
    }

    public static var openAppWhenRun: Bool { true }

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
            shortTitle: LocalizedStringResource("shell.intent.setPriority.title"),
            systemImageName: "target"
        )
        AppShortcut(
            intent: StartFocusSessionIntent(),
            phrases: ["Start a \(.applicationName) session"],
            shortTitle: LocalizedStringResource("shell.intent.startSession.title"),
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: FinishFocusSessionIntent(),
            phrases: ["Finish my \(.applicationName) session"],
            shortTitle: LocalizedStringResource("shell.intent.finishSession.title"),
            systemImageName: "checkmark.circle"
        )
    }
}
