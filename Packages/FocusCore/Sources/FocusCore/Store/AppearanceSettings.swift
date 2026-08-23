import Foundation
import SwiftData

extension FocusStore {
    /// Reads the user's stored appearance preference.
    ///
    /// The settings row is a singleton by convention rather than by constraint: SwiftData
    /// has no "exactly one row" facility, so the read takes the earliest-touched row and the
    /// write reuses it. A store that somehow acquired two rows therefore converges on one
    /// instead of flip-flopping between them.
    ///
    /// `matchSystem` when nothing has been stored yet — a real third state, not the absence
    /// of a choice: the app must be able to tell "follow the Mac" from "I picked light and
    /// the Mac happens to be light".
    @MainActor
    public static func appearancePreference(in context: ModelContext) -> AppearancePreference {
        settingsRow(in: context)?.appearancePreference ?? .matchSystem
    }

    /// Writes the user's appearance preference, creating the settings row if this is the
    /// first time the app has been asked to remember anything.
    ///
    /// `now` is passed in rather than read from `Date()` so that every timestamp in this
    /// programme comes from an injected clock and a test can pin it.
    @MainActor
    @discardableResult
    public static func setAppearancePreference(
        _ preference: AppearancePreference,
        in context: ModelContext,
        now: Date
    ) throws -> FocusSchemaV3.AppSettingsRecord {
        let row: FocusSchemaV3.AppSettingsRecord
        if let existing = settingsRow(in: context) {
            row = existing
        } else {
            row = FocusSchemaV3.AppSettingsRecord(
                appearancePreferenceRaw: preference.rawValue,
                schemaTouchedAt: now
            )
            context.insert(row)
        }
        row.appearancePreference = preference
        row.schemaTouchedAt = now
        try context.save()
        return row
    }

    /// The settings row, if the store has one.
    @MainActor
    public static func settingsRow(in context: ModelContext) -> FocusSchemaV3.AppSettingsRecord? {
        var descriptor = FetchDescriptor<FocusSchemaV3.AppSettingsRecord>(
            sortBy: [SortDescriptor(\.schemaTouchedAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
