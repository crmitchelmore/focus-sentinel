import Foundation
import SwiftData

/// **The two facts the launch read and nothing could write** (focus-d3g, focus-tee.6).
///
/// `AppComposition.storedHotKeySpec()` fed the quick-capture shortcut to `registerHotKey` at
/// every launch, and `PriorityHost.shouldPromptRitual()` handed the ritual switch to
/// `DailyRitualGate` — three columns with a reader apiece and **no writer anywhere in the
/// repository**. So the only value either could ever hold was the schema's default, and the
/// consequences were user-reachable: probe P-55 measured that `RegisterEventHotKey` hands over a
/// combination another application already owns without complaint, so somebody whose Mac binds
/// ⌃⌥⌘Space had no route to a different one; and the daily ritual banner — whose column comment
/// says *"whether the daily ritual banner is offered at all"* — could not be turned off.
///
/// **Writers rather than deletions**, and the reason is arithmetic rather than taste. Removing
/// the columns means re-declaring `AppSettingsRecord` at a new version with a stage, while v1…v7
/// keep the declarations anyway under the schema-source rule — so deleting costs a migration and
/// leaves the declarations standing. A writer costs no migration at all: the columns have
/// carried defaults since v2, so there is nothing to carry across and nothing to get wrong.
///
/// Both verbs are **narrow**: each writes its own column and leaves the other eleven exactly as
/// they were. That is `FocusStore.recordOpenWindows`'s rule and it is here for the same reason —
/// a "save the settings" verb that took the whole row is a verb that resets whatever its caller
/// had not read.
extension FocusStore {
    /// Whether the daily ritual banner may be offered at all.
    ///
    /// **A legacy preference with no runtime reader** (focus-g9iw). The banner asked the same
    /// question the cockpit's capture field already asks, so it was retired and its General
    /// switch with it. The column stays — removing it costs a migration for nothing — and a
    /// settings document still carries it, so a file written by an older build round-trips
    /// rather than losing a value somebody chose. Nothing in the app consults it.
    @MainActor
    public static func ritualEnabled(in context: ModelContext) -> Bool {
        settingsRow(in: context)?.ritualEnabled ?? true
    }

    /// Turn the daily ritual banner on or off — a legacy preference, written only by a settings
    /// import now (focus-g9iw).
    ///
    /// This is a different fact from `lastRitualLocalDay`, which records that *today's* ritual
    /// has been answered. One is a preference and the other is a diary entry, and folding them
    /// into one column would make "I do not want this feature" indistinguishable from "I have
    /// already done it today".
    @discardableResult
    @MainActor
    public static func setRitualEnabled(
        _ isEnabled: Bool,
        in context: ModelContext,
        now: Date
    ) throws -> FocusSchemaV3.AppSettingsRecord {
        let row = try touchedSettingsRow(in: context, now: now)
        row.ritualEnabled = isEnabled
        try context.save()
        return row
    }

    /// The stored quick-capture shortcut, or the default when the store has no row.
    @MainActor
    public static func hotKeySpec(in context: ModelContext) -> HotKeySpec {
        guard let row = settingsRow(in: context) else { return .quickCaptureDefault }
        return HotKeySpec(keyCode: row.hotKeyKeyCode, modifierFlags: row.hotKeyModifierFlags)
    }

    /// Store a quick-capture shortcut.
    ///
    /// **A shortcut the platform would not take is refused here**, before anything is written:
    /// `HotKeySpec.refusal` names ⌘Space, ⌘Q, a bare key and a key this app cannot draw, and P-55
    /// measured that `RegisterEventHotKey` will not refuse any of them for us. Storing one would
    /// leave the person with a row the next launch reads, hands to the platform, and silently
    /// fails to bind — a setting that looks set and does nothing.
    ///
    /// - Throws: `CaptureSettingsError.unregistrableShortcut` carrying the refusal, so the
    ///   surface can say *why* rather than greying a control out.
    @discardableResult
    @MainActor
    public static func setHotKeySpec(
        _ spec: HotKeySpec,
        in context: ModelContext,
        now: Date
    ) throws -> FocusSchemaV3.AppSettingsRecord {
        guard let refusal = spec.refusal else {
            let row = try touchedSettingsRow(in: context, now: now)
            row.hotKeyKeyCode = spec.keyCode
            row.hotKeyModifierFlags = spec.modifierFlags
            try context.save()
            return row
        }
        throw CaptureSettingsError.unregistrableShortcut(refusal)
    }

    /// The settings row, created if the store has none, with its stamp moved.
    ///
    /// Shared by both verbs above so that "the row exists" is decided in one place: two copies
    /// of a find-or-create are two chances to insert a second row into a table that is a
    /// singleton by convention.
    @MainActor
    private static func touchedSettingsRow(
        in context: ModelContext,
        now: Date
    ) throws -> FocusSchemaV3.AppSettingsRecord {
        if let existing = settingsRow(in: context) {
            existing.schemaTouchedAt = now
            return existing
        }
        let row = FocusSchemaV3.AppSettingsRecord(
            appearancePreferenceRaw: AppearancePreference.matchSystem.rawValue,
            schemaTouchedAt: now
        )
        context.insert(row)
        return row
    }
}

/// Why a capture setting was refused.
public enum CaptureSettingsError: Error, Equatable, Sendable {
    /// The platform would take this combination and then not bind it, or would take it away
    /// from something the person needs. `HotKeySpec.refusal` says which.
    case unregistrableShortcut(HotKeyRefusal)
}
