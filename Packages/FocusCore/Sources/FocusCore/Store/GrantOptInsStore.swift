import Foundation
import SwiftData

extension FocusStore {
    /// Which grants the person has switched on (focus-exdi.4). No rows is "nothing".
    @MainActor
    public static func grantOptIns(in context: ModelContext) -> GrantOptIns {
        var enabled: Set<GrantOptIn> = []
        for row in grantOptInRows(in: context) {
            guard let grant = row.grant else { continue }
            enabled.insert(grant)
        }
        return GrantOptIns(enabled: enabled)
    }

    /// Switch one grant on or off. Off deletes the row: "switched off" and "never switched on"
    /// are one state, because they are one promise.
    @MainActor
    public static func setGrantOptIn(
        _ grant: GrantOptIn,
        to isEnabled: Bool,
        in context: ModelContext,
        now: Date
    ) throws {
        let existing = grantOptInRows(in: context).filter { $0.key == grant.rawValue }
        if isEnabled {
            if let row = existing.first {
                row.touchedAt = now
                for duplicate in existing.dropFirst() { context.delete(duplicate) }
            } else {
                context.insert(FocusSchemaV10.GrantOptInRecord(key: grant.rawValue, touchedAt: now))
            }
        } else {
            for row in existing { context.delete(row) }
        }
        try context.save()
    }

    @MainActor
    static func grantOptInRows(in context: ModelContext) -> [FocusSchemaV10.GrantOptInRecord] {
        let descriptor = FetchDescriptor<FocusSchemaV10.GrantOptInRecord>(
            sortBy: [SortDescriptor(\.touchedAt, order: .forward)]
        )
        return (try? context.countedFetch(descriptor)) ?? []
    }
}
