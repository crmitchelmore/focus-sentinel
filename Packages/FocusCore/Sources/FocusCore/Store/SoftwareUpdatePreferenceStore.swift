import Foundation
import SwiftData

extension FocusStore {
    /// Whether the person switched automatic update checks on (focus-h8jf). No row is `false`.
    @MainActor
    public static func softwareUpdateChecksEnabled(in context: ModelContext) -> Bool {
        softwareUpdatePreferenceRows(in: context).first?.checksAutomatically ?? false
    }

    /// Record the person's choice. The state they asked **for**, not a toggle, for the rule
    /// every other switch in this store states: a pane built a moment ago cannot invert it.
    ///
    /// Off keeps the row and writes `false` rather than deleting it, unlike a grant: "switched
    /// off" and "never asked" are two facts here, because the first means the updater was once
    /// started in this store and the second means it never was.
    @MainActor
    public static func setSoftwareUpdateChecksEnabled(
        _ isEnabled: Bool,
        in context: ModelContext,
        now: Date
    ) throws {
        let rows = softwareUpdatePreferenceRows(in: context)
        if let row = rows.first {
            row.checksAutomatically = isEnabled
            row.touchedAt = now
            for duplicate in rows.dropFirst() { context.delete(duplicate) }
        } else {
            context.insert(
                FocusSchemaV11.SoftwareUpdatePreferenceRecord(
                    checksAutomatically: isEnabled,
                    touchedAt: now
                )
            )
        }
        try context.save()
    }

    @MainActor
    static func softwareUpdatePreferenceRows(
        in context: ModelContext
    ) -> [FocusSchemaV11.SoftwareUpdatePreferenceRecord] {
        let descriptor = FetchDescriptor<FocusSchemaV11.SoftwareUpdatePreferenceRecord>(
            sortBy: [SortDescriptor(\.touchedAt, order: .forward)]
        )
        return (try? context.countedFetch(descriptor)) ?? []
    }
}
