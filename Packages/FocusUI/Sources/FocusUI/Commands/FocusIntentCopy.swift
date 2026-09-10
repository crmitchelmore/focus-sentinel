import Foundation

/// Localised runtime refusals for the Shortcuts actions. Metadata titles live in
/// the app bundle because Apple's metadata processor requires that location.
public enum FocusIntentCopy {
    /// The four refusals, named. A closed vocabulary spelled beside the runner,
    /// mirrored by `FocusIntentRefusal` — and `FocusIntentTests` folds the two against each
    /// other in both directions, so neither can grow a case the other has never heard of.
    public enum Refusal: String, Sendable, CaseIterable, Hashable {
        case unavailable
        case emptyPriority
        case sessionAlreadyRunning
        case noSessionToFinish

        public var key: ShellStringKey {
            switch self {
            case .unavailable: .intentRefusalUnavailable
            case .emptyPriority: .intentRefusalEmptyPriority
            case .sessionAlreadyRunning: .intentRefusalSessionRunning
            case .noSessionToFinish: .intentRefusalNoSession
            }
        }

        public var resource: LocalizedStringResource { ShellStrings.resource(key) }
        public var sentence: String { ShellStrings.string(key) }
    }
}
