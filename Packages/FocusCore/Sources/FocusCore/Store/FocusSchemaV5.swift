import Foundation
import SwiftData

/// Schema version 5 of the Focus Sentinel store.
///
/// **One fact has to survive a relaunch and has no home in v4: what the person set in the
/// Intervention pane** (focus-z7g, focus-40i). The voice, *"Interrupt me less"* and the quiet-
/// hours window were in-memory properties on `NudgeHost` and nothing else — no column, no
/// `UserDefaults` key, no write of any kind — so a person who picked *Warm*, asked for fewer
/// interruptions, or set an evening window got `neutral`, full panels and no window back on
/// the next launch. Reduced interruption decides **where** a nudge lands, so the one that read
/// as cosmetic was the one that silently restored the panel for somebody who had asked for
/// quiet.
///
/// ## Why one new entity rather than four columns on `AppSettingsRecord`
///
/// The settings row is declared by `FocusSchemaV3` and *reused* by v4. Editing it would edit a
/// **migration source** — v1, v2 and v3 are the stores earlier builds actually wrote, and
/// `MigrationV4Tests` states in as many words that a source you have edited is not a source.
/// So v5 does what v4 did, for the reason v4 did it: it re-declares nothing, names v4's twelve
/// classes and adds **one** of its own. Every existing call site keeps fetching the entity it
/// already knew, and the v4 → v5 stage is lightweight honestly rather than by assertion.
///
/// ## Why the row is not a copy of `InterventionSettings`
///
/// Three types with three jobs, and the reason they are not one is that only one of them is
/// the person's choice. `InterventionPreferences` is what they **set**;
/// `NudgePreferences` is what the *loop* runs on, which is that plus what the Mac forces
/// (`accessibilityDisplayShouldReduceMotion` can turn reduced interruption on and nothing may
/// write that back to the person's row); `InterventionSettings` is the whole of what the pane
/// **draws**, which is those plus today's usage and the exclusion list. A single type would
/// have to persist a forced flag as though the person had chosen it — the "two writers, one
/// field" shape `focus-zrs` and `focus-w7v` both removed.
public enum FocusSchemaV5: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(5, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        FocusSchemaV4.models + [NudgePreferencesRecord.self]
    }

    /// **What the person set in the Intervention pane** — a single row, and only what they
    /// chose.
    ///
    /// Singleton by convention rather than by constraint, exactly as `AppSettingsRecord` is:
    /// SwiftData has no "exactly one row" facility, so the read takes the earliest-touched row
    /// and the write reuses it, and a store that somehow acquired two converges on one instead
    /// of flip-flopping.
    ///
    /// Every attribute carries a **property default** and the two quiet-hours columns are
    /// optional, which is the condition probe P-51 measured for a lightweight stage.
    ///
    /// The window is stored as its two minute-of-day offsets rather than as an encoded string,
    /// because that is what `QuietHoursWindow` *is*: a pair of integers whose evaluation —
    /// wrapping midnight, an injected `Calendar`, DST — belongs to `QuietHours` and to no
    /// column. `nil` on either side means **no window**, which is the shipped default (R-85)
    /// and a real state rather than a missing value: "Focus has no opinion about your
    /// evenings" is a thing the app is saying, not a thing it has forgotten.
    @Model
    public final class NudgePreferencesRecord {
        public var id: UUID
        /// `NudgeVoice` raw value, read through `NudgeVoice.decode(_:)` and never
        /// `init(rawValue:)`.
        public var voiceRaw: String = NudgeVoice.standard.rawValue
        /// F-148's flag **as the person set it**. What the Mac forces on top of it is derived
        /// at the point of use and is never written here.
        public var reducedInterruption: Bool = false
        /// Minutes since local midnight, inclusive. `nil` when there is no window.
        public var quietHoursStartMinuteOfDay: Int?
        /// Minutes since local midnight, exclusive. May be *less* than the start, which is a
        /// window that wraps midnight and is the common case.
        public var quietHoursEndMinuteOfDay: Int?
        /// When the schema last wrote this row.
        public var touchedAt: Date

        public init(
            id: UUID = UUID(),
            voiceRaw: String = NudgeVoice.standard.rawValue,
            reducedInterruption: Bool = false,
            quietHoursStartMinuteOfDay: Int? = nil,
            quietHoursEndMinuteOfDay: Int? = nil,
            touchedAt: Date
        ) {
            self.id = id
            self.voiceRaw = voiceRaw
            self.reducedInterruption = reducedInterruption
            self.quietHoursStartMinuteOfDay = quietHoursStartMinuteOfDay
            self.quietHoursEndMinuteOfDay = quietHoursEndMinuteOfDay
            self.touchedAt = touchedAt
        }
    }
}

extension NudgeVoice {
    /// The stored deck, decoded through an exhaustive `switch`, **and whether this build could
    /// read it**.
    ///
    /// Unreadable ⇒ `standard`, which is what the app ships with: a row this build cannot
    /// interpret makes it speak in its default voice, never crash and never silently
    /// reinterpret one deck as another — which is exactly what `init(rawValue:)` over a
    /// reordered enum would do, and why R-45 bans that spelling for the phases.
    ///
    /// **The second half of the pair is what "fails loudly" means here** (D4). A `throw` was
    /// considered and rejected on three grounds. The shipped remedy for the same shape — a
    /// store the app cannot use — splits one boolean into a *named fact* and blocks only the
    /// action that would lose data (`PriorityHost`, `StoreUnavailableSheet`); it does not
    /// refuse to launch, and an uninterpretable preference row loses nothing. Every sibling
    /// decoder in this schema is total, so a throwing `NudgeVoice` would be the sole exception
    /// to R-45's doctrine. And refusing to open would brick the app on a downgrade, after a
    /// newer build had written a raw value this one has never heard of. So the loudness is a
    /// fact the caller can read, log as a fault, and put in the self-check — not a refusal.
    ///
    /// `playful` is **recognised**: it is a retired deck (`focus-0nm`, 2026-08-29) whose rows
    /// read as `warm`, the nearest surviving register, and the person who chose it keeps a
    /// gentler voice rather than being quietly returned to the default. Without this arm the
    /// row would fall to `default` and become `neutral` with nobody the wiser, which is the
    /// silent reinterpretation the doc above forbids.
    public static func decode(_ raw: String) -> (voice: NudgeVoice, wasRecognised: Bool) {
        switch raw {
        case "neutral": (.neutral, true)
        case "warm": (.warm, true)
        case "direct": (.direct, true)
        case "playful": (.warm, true)
        case "silentVisual": (.silentVisual, true)
        default: (.standard, false)
        }
    }
}

// MARK: - Typed accessors
//
// Every stored column read through its decoder and written through its raw value, so no call
// site touches a `…Raw` string or reassembles the window by hand.

extension FocusSchemaV5.NudgePreferencesRecord {
    public var voice: NudgeVoice {
        get { NudgeVoice.decode(voiceRaw).voice }
        set { voiceRaw = newValue.rawValue }
    }

    /// Whether this build could read the deck the row holds.
    ///
    /// The other half of `decode(_:)`'s pair, kept as its own accessor so a caller reading the
    /// voice cannot read it without being able to ask. `false` is not a corruption and not a
    /// reason to refuse the row: it is a raw value this build has never heard of — a downgrade
    /// after a newer build wrote one — and the app speaks in `standard` and **says so**.
    public var voiceWasRecognised: Bool { NudgeVoice.decode(voiceRaw).wasRecognised }

    /// The window, as the value the suppression stack evaluates.
    ///
    /// **Both columns or neither.** A half-written window is not half a window — it is a
    /// window whose other boundary the app would have to invent — so a row holding one is read
    /// as no window at all, and the setter writes both sides or clears both.
    public var quietHours: QuietHoursWindow? {
        get {
            guard
                let start = quietHoursStartMinuteOfDay,
                let end = quietHoursEndMinuteOfDay
            else { return nil }
            return QuietHoursWindow(startMinuteOfDay: start, endMinuteOfDay: end)
        }
        set {
            quietHoursStartMinuteOfDay = newValue?.startMinuteOfDay
            quietHoursEndMinuteOfDay = newValue?.endMinuteOfDay
        }
    }
}
