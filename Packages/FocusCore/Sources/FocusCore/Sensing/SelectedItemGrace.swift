import Foundation

/// **Hold the last item through a read that failed** (issue #27).
///
/// The dwell clock is keyed by the item (`JudgeableSubject.dwellKey`), so a single read that
/// timed out — a busy application, a tree too big for the budget — would otherwise turn "the
/// same chat" into "the bare application" for one tick and restart the dwell. A failed read is
/// "could not tell", not "nothing is selected", so the item read a moment ago stands for
/// `holdFor`. A read that *succeeded* and named nothing is an answer and clears the hold at once.
///
/// Held in memory only, for one process at a time; nothing here is stored.
public struct SelectedItemGrace: Sendable {
    /// How long a failed read may keep the last item. Two corroboration ticks and a little.
    public static let holdFor: Duration = .seconds(12)

    /// What one read came back with.
    public enum Reading: Sendable, Equatable {
        /// The application named an item.
        case item(SelectedItem)
        /// The application answered and named nothing.
        case nothing
        /// The read did not complete: a timeout, an error, a search that ran out of budget.
        case failed
    }

    private var last: (pid: Int32, item: SelectedItem, at: Duration)?

    public init() {}

    /// Fold one reading in and say which item stands.
    public mutating func resolve(_ reading: Reading, pid: Int32, now: Duration) -> SelectedItem? {
        switch reading {
        case let .item(item):
            last = (pid, item, now)
            return item
        case .nothing:
            last = nil
            return nil
        case .failed:
            // Measured from the last read that succeeded: failures never extend the hold.
            guard let held = last, held.pid == pid, now - held.at <= Self.holdFor else {
                last = nil
                return nil
            }
            return held.item
        }
    }

    /// Forget the held item: the person switched the ask off, or macOS withdrew the grant.
    public mutating func clear() {
        last = nil
    }
}
