import Foundation

/// What `PriorityStore` can refuse to do.
///
/// Every case names the row it could not find, because a facade that throws
/// "something went wrong" is a facade whose caller has to guess. `Equatable` so a test can
/// assert on the exact refusal rather than on "it threw".
public enum PriorityStoreError: Error, Sendable, Equatable, Hashable {
    /// No `PriorityTask` with that identifier is in the store.
    case taskNotFound(UUID)
    /// No `ContextItem` with that identifier is in the store.
    case contextItemNotFound(UUID)
    /// No `RelevanceRule` with that identifier is in the store.
    case ruleNotFound(UUID)
    /// The intent was empty, or only whitespace.
    ///
    /// This is the one refusal in the whole capture path, and it is not the validator's:
    /// `IntentValidator` **explains** and never blocks (R-20). A priority with no words in it
    /// is not a vague priority, it is the absence of one.
    case emptyIntent
}

extension PriorityStoreError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .taskNotFound(let id): "No priority task with id \(id)"
        case .contextItemNotFound(let id): "No context item with id \(id)"
        case .ruleNotFound(let id): "No relevance rule with id \(id)"
        case .emptyIntent: "An intent must contain at least one non-whitespace character"
        }
    }
}
