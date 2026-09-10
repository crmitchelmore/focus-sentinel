import Foundation
import SwiftData

/// **The three things a person sets in the Intervention pane**, as one value.
///
/// A value rather than a live row, for the reason `SensingSettingsValue` is one: whatever
/// reads these — the nudge loop, the settings pane, a second launch — should be handed a
/// snapshot it can compare and test, not a `@Model` object whose fields change underneath it.
///
/// It is deliberately **not** `NudgePreferences`. That type is what the loop runs on, and its
/// `reducedInterruption` is the person's choice *or* what macOS Reduce Motion forces
/// (focus-w7v). Only the choice is stored: writing a forced flag into the person's row would
/// mean that turning Reduce Motion off later left them with a setting they never chose, which
/// is the "two writers, one field" defect focus-zrs removed from the notification
/// authorisation.
public struct InterventionPreferences: Sendable, Equatable, Hashable {
    /// One of the four static decks. `standard` until the person picks another.
    public var voice: NudgeVoice
    /// F-148's flag as the person set it, never as the Mac forces it.
    public var reducedInterruption: Bool
    /// The local-time window nudges are held inside, or `nil` for no window — which is the
    /// shipped default (R-85) and a real answer rather than an absent one.
    public var quietHours: QuietHoursWindow?
    /// **Whether the stored deck was one this build could read.**
    ///
    /// A named fact beside the value, rather than a `voice` that is secretly two things — the
    /// same split `PriorityHost` made for a store it cannot open. `false` means the row held a
    /// raw value this build has never heard of, `voice` is therefore `standard`, and the app
    /// owes the person a fault in the log and a reading in the self-check rather than a silent
    /// reinterpretation. It is deliberately **not** part of what a writer sets: nothing writes
    /// an unreadable deck, so the setter path always leaves this `true`.
    public var storedVoiceWasRecognised: Bool

    public init(
        voice: NudgeVoice = .standard,
        reducedInterruption: Bool = false,
        quietHours: QuietHoursWindow? = InterventionPolicy.quietHoursDefault,
        storedVoiceWasRecognised: Bool = true
    ) {
        self.voice = voice
        self.reducedInterruption = reducedInterruption
        self.quietHours = quietHours
        self.storedVoiceWasRecognised = storedVoiceWasRecognised
    }

    /// What the app believes before it has read anything: the neutral deck, full panels, and
    /// no opinion about anybody's evenings.
    public static let defaults = InterventionPreferences()
}

extension FocusStore {
    /// The stored intervention preferences, or the defaults when nothing has been stored yet.
    ///
    /// Defaults rather than `nil`, for the reason `sensingSettings(in:)` answers them: a first
    /// launch has real preferences, they are simply the ones the app ships with, and a caller
    /// that had to handle "no preferences" would be handling a state that does not exist from
    /// the person's point of view.
    @MainActor
    public static func interventionPreferences(in context: ModelContext) -> InterventionPreferences {
        guard let row = nudgePreferencesRow(in: context) else { return .defaults }
        return InterventionPreferences(
            voice: row.voice,
            reducedInterruption: row.reducedInterruption,
            quietHours: row.quietHours,
            storedVoiceWasRecognised: row.voiceWasRecognised
        )
    }

    /// Write all three, creating the row if this is the first time the app has been asked to
    /// remember any of them.
    ///
    /// `now` is passed in rather than read from a clock here, so that every timestamp in this
    /// programme comes from an injected one and a test can pin it.
    @MainActor
    @discardableResult
    public static func setInterventionPreferences(
        _ preferences: InterventionPreferences,
        in context: ModelContext,
        now: Date
    ) throws -> FocusSchemaV5.NudgePreferencesRecord {
        let row: FocusSchemaV5.NudgePreferencesRecord
        if let existing = nudgePreferencesRow(in: context) {
            row = existing
        } else {
            row = FocusSchemaV5.NudgePreferencesRecord(touchedAt: now)
            context.insert(row)
        }

        row.voice = preferences.voice
        row.reducedInterruption = preferences.reducedInterruption
        row.quietHours = preferences.quietHours
        row.touchedAt = now

        try context.save()
        return row
    }

    /// Set the voice, leaving the other two alone.
    ///
    /// A named verb rather than a read-modify-write at each call site, for the reason
    /// `setSensingPaused(_:in:now:)` is one: a partial write from a surface that had read one
    /// field would silently reset the two it never drew.
    @MainActor
    @discardableResult
    public static func setNudgeVoice(
        _ voice: NudgeVoice,
        in context: ModelContext,
        now: Date
    ) throws -> FocusSchemaV5.NudgePreferencesRecord {
        var preferences = interventionPreferences(in: context)
        preferences.voice = voice
        return try setInterventionPreferences(preferences, in: context, now: now)
    }

    /// Set *"Interrupt me less"*, leaving the other two alone.
    @MainActor
    @discardableResult
    public static func setReducedInterruption(
        _ reduced: Bool,
        in context: ModelContext,
        now: Date
    ) throws -> FocusSchemaV5.NudgePreferencesRecord {
        var preferences = interventionPreferences(in: context)
        preferences.reducedInterruption = reduced
        return try setInterventionPreferences(preferences, in: context, now: now)
    }

    /// Set or clear the quiet-hours window, leaving the other two alone.
    @MainActor
    @discardableResult
    public static func setQuietHours(
        _ window: QuietHoursWindow?,
        in context: ModelContext,
        now: Date
    ) throws -> FocusSchemaV5.NudgePreferencesRecord {
        var preferences = interventionPreferences(in: context)
        preferences.quietHours = window
        return try setInterventionPreferences(preferences, in: context, now: now)
    }

    /// The preferences row, if the store has one.
    @MainActor
    public static func nudgePreferencesRow(
        in context: ModelContext
    ) -> FocusSchemaV5.NudgePreferencesRecord? {
        var descriptor = FetchDescriptor<FocusSchemaV5.NudgePreferencesRecord>(
            sortBy: [SortDescriptor(\.touchedAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return try? context.countedFetch(descriptor).first
    }
}
