import Foundation

/// **Every word the three App Intents say** (F-141, focus-mn7).
///
/// It lives here rather than beside the intents for the reason
/// `PrivacySettingsAction.importRefusedTitle` does: `FocusHost` declares and references no
/// catalog keys (F-149), and `AppIntents` cannot be imported by this package — so the intents
/// ask for their titles and their refusals already resolved, and every sentence in the
/// application is still in one catalog.
///
/// The refusals are a **fold over the vocabulary**, so a refusal added without a sentence does
/// not compile. That matters more here than anywhere else in the shell: a person hears these out
/// of Shortcuts with the app nowhere on screen, and *"the operation could not be completed"* is
/// what an intent says when nobody wrote it a reason.
public enum FocusIntentCopy {
    public static var setPriorityTitle: LocalizedStringResource {
        ShellStrings.resource(.intentSetPriorityTitle)
    }
    public static var setPriorityDescription: LocalizedStringResource {
        ShellStrings.resource(.intentSetPriorityDescription)
    }
    public static var priorityParameterTitle: LocalizedStringResource {
        ShellStrings.resource(.intentPriorityParameter)
    }
    public static var startSessionTitle: LocalizedStringResource {
        ShellStrings.resource(.intentStartSessionTitle)
    }
    public static var startSessionDescription: LocalizedStringResource {
        ShellStrings.resource(.intentStartSessionDescription)
    }
    public static var finishSessionTitle: LocalizedStringResource {
        ShellStrings.resource(.intentFinishSessionTitle)
    }
    public static var finishSessionDescription: LocalizedStringResource {
        ShellStrings.resource(.intentFinishSessionDescription)
    }

    /// The four refusals, named. A closed vocabulary spelled here rather than in `FocusHost`,
    /// mirrored by `FocusIntentRefusal` — and `FocusIntentTests` folds the two against each
    /// other in both directions, so neither can grow a case the other has never heard of.
    public enum Refusal: String, Sendable, CaseIterable, Hashable {
        case notRunning
        case emptyPriority
        case sessionAlreadyRunning
        case noSessionToFinish

        public var key: ShellStringKey {
            switch self {
            case .notRunning: .intentRefusalNotRunning
            case .emptyPriority: .intentRefusalEmptyPriority
            case .sessionAlreadyRunning: .intentRefusalSessionRunning
            case .noSessionToFinish: .intentRefusalNoSession
            }
        }

        public var resource: LocalizedStringResource { ShellStrings.resource(key) }
        public var sentence: String { ShellStrings.string(key) }
    }
}
