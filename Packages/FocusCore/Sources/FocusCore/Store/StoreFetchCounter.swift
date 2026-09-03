import Foundation
import SwiftData

/// **How many times this process has asked SwiftData for rows** (focus-tzj.2).
///
/// ## Why a counter and not a stopwatch
///
/// The five-second corroboration tick used to fetch every `PriorityTask` in the store, the
/// settings row, today's whole intervention log and a query receipt — on every tick, whether or
/// not anything had moved, and whether or not there was a commitment for any of it to be about.
/// None of that is visible in a wall-clock reading: a store with four rows in it answers
/// instantly, and the defect only becomes a stutter on somebody's hundredth day. A **count** is
/// the same fact measured where it is true from the first tick, and it is a number the gate can
/// pin.
///
/// ## Why it lives here rather than at the call sites
///
/// A counter incremented by hand next to each `context.fetch(…)` would be a counter that a new
/// fetch could quietly not join, which is the shape of assertion this repository exists to get
/// rid of. So the count is taken *inside* the only two functions the packages are allowed to
/// fetch through — `ModelContext.countedFetch(_:)` and `countedFetchCount(_:)` below — and
/// `check-forbidden.sh` (R-97) bans the bare calls everywhere but in this file. A fetch that is
/// not counted does not compile past the gate.
///
/// ## Isolation
///
/// Deliberately not `@MainActor`. Most of the stores are, but `FocusMigrationPlan` runs its
/// stages wherever SwiftData opens the container, and a counter that could not be touched from
/// there would be a counter with a hole in it exactly where the heaviest reads live. The lock is
/// uncontended in every real use — one process, one context, one main thread.
public enum StoreFetchCounter {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var fetches = 0

    /// Every fetch this process has made since the last `reset()`.
    public static var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return fetches
    }

    /// Start counting again from zero. Called by a survey immediately before the thing it is
    /// measuring, and by nothing in the shipping paths — a counter the product reset itself
    /// would be a counter the product could zero on the way past a reading.
    public static func reset() {
        lock.lock()
        fetches = 0
        lock.unlock()
    }

    /// Record one. `internal` on purpose: the two `ModelContext` helpers below are the only
    /// callers, and a store that could increment without fetching could also fetch without
    /// incrementing.
    static func countOne() {
        lock.lock()
        fetches += 1
        lock.unlock()
    }
}

extension ModelContext {
    /// `fetch(_:)`, counted. **The only fetch the packages may make** (R-97, focus-tzj.2).
    public func countedFetch<T>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
        StoreFetchCounter.countOne()
        return try fetch(descriptor)
    }

    /// `fetchCount(_:)`, counted. It is a round trip to the store like any other — cheaper per
    /// row and exactly as expensive to make on a tick that had nothing to ask about.
    public func countedFetchCount<T>(_ descriptor: FetchDescriptor<T>) throws -> Int {
        StoreFetchCounter.countOne()
        return try fetchCount(descriptor)
    }
}
