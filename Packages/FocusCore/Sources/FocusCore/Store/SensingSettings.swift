import Foundation
import SwiftData

/// The five sensing settings, as one value.
///
/// A value rather than a live row, for the same reason `CockpitState` is one: whatever reads
/// these — the observer graph, the pause switch, the Privacy surface — should be handed a
/// snapshot it can compare and test, not a `@Model` object whose fields can change underneath
/// it. Every one of them is injected everywhere it is used; nothing in this programme reads a
/// threshold from a constant at the point of use.
public struct SensingSettingsValue: Sendable, Equatable, Hashable {
    /// F-119's one global switch. It is not a boolean handlers consult — turning it on
    /// **detaches every observer** — but the state they are detached from is this single value,
    /// bound identically to the menu bar, the cockpit and (in e09) the notch.
    public var sensingPaused: Bool

    /// Seconds of no **hardware** input above which the person is treated as away (R-36).
    /// Default 180.
    public var idleThresholdSeconds: Int

    /// How often the corroboration tick re-evaluates the signals that have no reliable
    /// notification (R-38). Default 5.
    ///
    /// It exists because two of this epic's signals were measured to have no usable
    /// notification at all: `activeSpaceDidChangeNotification` **never fired** across four
    /// full-screen cycles and two bundle identifiers (probe P-92). Five seconds is affordable
    /// because a window-list read costs 0.296 ms at the median (probe P-76).
    public var corroborationTickSeconds: Int

    /// F-169's launcher: **off by default**, and open-only when on.
    public var launchContextOnSessionStart: Bool

    /// Whether a running microphone suppresses an intervention. The camera never does, on any
    /// Mac in v1 (R-40).
    public var mediaSuppressionEnabled: Bool

    public init(
        sensingPaused: Bool = false,
        idleThresholdSeconds: Int = FocusSchemaV3.defaultIdleThresholdSeconds,
        corroborationTickSeconds: Int = FocusSchemaV3.defaultCorroborationTickSeconds,
        launchContextOnSessionStart: Bool = false,
        mediaSuppressionEnabled: Bool = true
    ) {
        self.sensingPaused = sensingPaused
        self.idleThresholdSeconds = idleThresholdSeconds
        self.corroborationTickSeconds = corroborationTickSeconds
        self.launchContextOnSessionStart = launchContextOnSessionStart
        self.mediaSuppressionEnabled = mediaSuppressionEnabled
    }

    /// What the app believes before it has read anything — the schema's own defaults, which
    /// are the same figures the plan measured against.
    public static let defaults = SensingSettingsValue()

    /// The idle threshold as a `Double`, which is what `IdleReading` compares against.
    public var idleThresholdInterval: Double { Double(idleThresholdSeconds) }

    /// The tick as a `Duration`, which is what a scheduler wants. A tick of zero or less would
    /// be a spin, so it is clamped to one second — the stored value is the person's, but a
    /// value that would burn the battery is not honoured literally.
    public var corroborationTick: Duration { .seconds(max(1, corroborationTickSeconds)) }
}

extension FocusStore {
    /// The stored sensing settings, or the defaults when nothing has been stored yet.
    ///
    /// Defaults rather than `nil`: a first launch has real settings, they are simply the ones
    /// the schema declares, and a caller that had to handle "no settings" would be handling a
    /// state that does not exist from the user's point of view.
    @MainActor
    public static func sensingSettings(in context: ModelContext) -> SensingSettingsValue {
        guard let row = settingsRow(in: context) else { return .defaults }
        return SensingSettingsValue(
            sensingPaused: row.sensingPaused,
            idleThresholdSeconds: row.idleThresholdSeconds,
            corroborationTickSeconds: row.corroborationTickSeconds,
            launchContextOnSessionStart: row.launchContextOnSessionStart,
            mediaSuppressionEnabled: row.mediaSuppressionEnabled
        )
    }

    /// Write the sensing settings, creating the row if this is the first time the app has been
    /// asked to remember anything.
    ///
    /// `now` is passed in rather than read from a clock here, so that every timestamp in this
    /// programme comes from an injected one and a test can pin it.
    @MainActor
    @discardableResult
    public static func setSensingSettings(
        _ settings: SensingSettingsValue,
        in context: ModelContext,
        now: Date
    ) throws -> FocusSchemaV3.AppSettingsRecord {
        let row: FocusSchemaV3.AppSettingsRecord
        if let existing = settingsRow(in: context) {
            row = existing
        } else {
            // The same singleton-by-convention row the appearance preference lives on. Created
            // through the same shape so that two writers can never make two rows.
            row = FocusSchemaV3.AppSettingsRecord(
                appearancePreferenceRaw: AppearancePreference.matchSystem.rawValue,
                schemaTouchedAt: now
            )
            context.insert(row)
        }

        row.sensingPaused = settings.sensingPaused
        row.idleThresholdSeconds = settings.idleThresholdSeconds
        row.corroborationTickSeconds = settings.corroborationTickSeconds
        row.launchContextOnSessionStart = settings.launchContextOnSessionStart
        row.mediaSuppressionEnabled = settings.mediaSuppressionEnabled
        row.schemaTouchedAt = now

        try context.save()
        return row
    }

    /// Flip the one global switch, leaving every other setting alone.
    ///
    /// A named verb rather than a read-modify-write at each call site, because this one is
    /// bound to three surfaces and a partial write from any of them would silently reset the
    /// other four settings to whatever that surface last read.
    @MainActor
    @discardableResult
    public static func setSensingPaused(
        _ paused: Bool,
        in context: ModelContext,
        now: Date
    ) throws -> FocusSchemaV3.AppSettingsRecord {
        var settings = sensingSettings(in: context)
        settings.sensingPaused = paused
        return try setSensingSettings(settings, in: context, now: now)
    }
}
