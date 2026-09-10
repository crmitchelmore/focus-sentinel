import Foundation
import SwiftData

/// **What the person set in the Privacy pane**, as one value (F-115, focus-l7n).
///
/// A value rather than a live row, for the reason `InterventionPreferences` is one: whatever
/// reads this — the retention sweep, the settings pane, a second launch — should be handed a
/// snapshot it can compare and test, not a `@Model` object whose fields change underneath it.
public struct PrivacyPreferences: Sendable, Equatable, Hashable {
    /// How long the app keeps what it wrote down.
    public var retention: RetentionWindow
    /// **Whether the stored window was one this build could read.**
    ///
    /// A named fact beside the value rather than a `retention` that is secretly two things —
    /// the split `InterventionPreferences.storedVoiceWasRecognised` makes for the same reason.
    /// `false` means the column held a number this build has never heard of, `retention` is
    /// therefore the committed default, and the app owes the person a reading in the self-check
    /// rather than a silent reinterpretation. It is deliberately **not** part of what a writer
    /// sets: nothing writes an unreadable window, so the setter path always leaves this `true`.
    public var storedWindowWasRecognised: Bool

    public init(
        retention: RetentionWindow = .committedDefault,
        storedWindowWasRecognised: Bool = true
    ) {
        self.retention = retention
        self.storedWindowWasRecognised = storedWindowWasRecognised
    }

    /// What the app believes before it has read anything: ninety days, which is what every build
    /// before the control kept.
    public static let defaults = PrivacyPreferences()
}

extension FocusStore {
    /// The stored privacy preferences, or the defaults when nothing has been stored yet.
    ///
    /// Defaults rather than `nil`, for the reason `interventionPreferences(in:)` answers them: a
    /// first launch has a real retention window, it is simply the one the app ships with, and a
    /// caller that had to handle "no window" would be handling a state that does not exist from
    /// the person's point of view — the sweep has always kept ninety days.
    @MainActor
    public static func privacyPreferences(in context: ModelContext) -> PrivacyPreferences {
        guard let row = privacyPreferencesRow(in: context) else { return .defaults }
        let decoded = row.retentionWindow
        return PrivacyPreferences(
            retention: decoded.window,
            storedWindowWasRecognised: decoded.wasRecognised
        )
    }

    /// The retention policy the sweep should keep, as the person set it.
    ///
    /// The one call the sweep makes. It is a separate verb from `privacyPreferences(in:)` so the
    /// sweep does not have to know that a window is one field of a preferences row, and so the
    /// route from the column to the cutoff is a single named thing a test can point at.
    @MainActor
    public static func retentionPolicy(in context: ModelContext) -> RetentionPolicy {
        RetentionPolicy(window: privacyPreferences(in: context).retention)
    }

    /// Set the retention window, creating the row if this is the first time the app has been
    /// asked to remember it.
    ///
    /// `now` is passed in rather than read from a clock here, so that every timestamp in this
    /// programme comes from an injected one and a test can pin it.
    @MainActor
    @discardableResult
    public static func setRetentionWindow(
        _ window: RetentionWindow,
        in context: ModelContext,
        now: Date
    ) throws -> FocusSchemaV8.PrivacyPreferencesRecord {
        let row: FocusSchemaV8.PrivacyPreferencesRecord
        if let existing = privacyPreferencesRow(in: context) {
            row = existing
        } else {
            row = FocusSchemaV8.PrivacyPreferencesRecord(touchedAt: now)
            context.insert(row)
        }

        row.setRetentionWindow(window)
        row.touchedAt = now

        try context.save()
        return row
    }

    /// The preferences row, if the store has one.
    @MainActor
    public static func privacyPreferencesRow(
        in context: ModelContext
    ) -> FocusSchemaV8.PrivacyPreferencesRecord? {
        var descriptor = FetchDescriptor<FocusSchemaV8.PrivacyPreferencesRecord>(
            sortBy: [SortDescriptor(\.touchedAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return try? context.countedFetch(descriptor).first
    }
}
