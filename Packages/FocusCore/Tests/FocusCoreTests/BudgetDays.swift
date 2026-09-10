import Foundation

@testable import FocusCore

/// **A day's spend, built the only way the app can build one** (focus-d6r).
///
/// `InterruptionBudget`'s memberwise initialiser is private and `interruptionsToday` is derived,
/// so a suite can no longer state a day in which the shared budget is spent and neither per-kind
/// counter has moved. That state — eight interruptions, nought accusations, nought questions, and
/// `permits` false on both kinds — is the whole of focus-d6r, and every one of these suites used
/// to be able to write it down. Several of them did: `queryNeverSpendsTheReservedUnit` folded the
/// reserve over exactly that grid, so the rule was proved over states the app cannot be in and
/// left unproved over the states it can.
///
/// Every day is therefore folded from `InterruptionCharge`s, which exist only for sentences. What
/// a suite chooses is how many questions were asked under **this** commitment, how many under
/// another one — the distinction `dailyQueryCapAllPriorities` exists for — and how many
/// accusations were made.
enum BudgetDay {
    /// The commitment the caps are summed against.
    static let priority = UUID(uuidString: "B0D6E700-0000-4000-8000-000000000001")!
    /// A different commitment, for the questions that count against the day and not against this
    /// priority.
    static let otherPriority = UUID(uuidString: "B0D6E700-0000-4000-8000-000000000002")!

    static func spending(
        queries: Int = 0,
        otherPriorityQueries: Int = 0,
        accusations: Int = 0
    ) -> InterruptionBudget {
        var charges: [InterruptionCharge] = []
        charges += (0..<queries).map { _ in InterruptionCharge(.query, priorityID: priority) }
        charges += (0..<otherPriorityQueries).map { _ in
            InterruptionCharge(.query, priorityID: otherPriority)
        }
        charges += (0..<accusations).map { _ in
            InterruptionCharge(.accusation, priorityID: priority)
        }
        return .spent(charges, underPriority: priority)
    }
}
