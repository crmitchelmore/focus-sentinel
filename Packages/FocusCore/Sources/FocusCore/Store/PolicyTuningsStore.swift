import Foundation
import SwiftData

extension FocusStore {
    /// The defaults with every stored override on top (focus-exdi).
    ///
    /// Rows whose key the app no longer knows are skipped, not deleted: a downgrade that then
    /// upgrades again finds them where they were.
    @MainActor
    public static func policyTunings(in context: ModelContext) -> PolicyTunings {
        var overrides: [PolicyTuning: Double] = [:]
        for row in policyTuningRows(in: context) {
            guard let tuning = row.tuning else { continue }
            overrides[tuning] = row.value
        }
        return PolicyTunings(overrides: overrides)
    }

    /// Set one dial. A value that lands on the shipped constant deletes the row rather than
    /// storing it, so "reset by hand" and "never touched" are one state.
    @MainActor
    public static func setPolicyTuning(
        _ tuning: PolicyTuning,
        to candidate: Double,
        in context: ModelContext,
        now: Date
    ) throws {
        let value = tuning.clamped(candidate)
        let existing = policyTuningRows(in: context).filter { $0.key == tuning.rawValue }
        if value == tuning.shippedValue {
            for row in existing { context.delete(row) }
        } else if let row = existing.first {
            row.value = value
            row.touchedAt = now
            for duplicate in existing.dropFirst() { context.delete(duplicate) }
        } else {
            context.insert(
                FocusSchemaV9.PolicyTuningRecord(key: tuning.rawValue, value: value, touchedAt: now)
            )
        }
        try context.save()
    }

    /// Every dial back to its shipped value: every row deleted.
    @MainActor
    public static func resetPolicyTunings(in context: ModelContext) throws {
        for row in policyTuningRows(in: context) { context.delete(row) }
        try context.save()
    }

    @MainActor
    static func policyTuningRows(in context: ModelContext) -> [FocusSchemaV9.PolicyTuningRecord] {
        let descriptor = FetchDescriptor<FocusSchemaV9.PolicyTuningRecord>(
            sortBy: [SortDescriptor(\.touchedAt, order: .forward)]
        )
        return (try? context.countedFetch(descriptor)) ?? []
    }
}
