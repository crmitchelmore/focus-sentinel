import Foundation
import SwiftData

/// Schema version 8 of the Focus Sentinel store.
///
/// **One fact has to survive a relaunch and has no home in v7: how long the person asked the app
/// to remember things for** (F-115, focus-l7n). `RetentionPolicy.committedDefault` was a
/// constant — ninety days for everybody, with a doc comment promising a picker in a later epic —
/// and `RetentionSweep` was built once at launch with that constant baked in. A person could not
/// shorten the window, and the sweep could not have read a shorter one if they had.
///
/// ## Why one new entity rather than a column on `AppSettingsRecord` or the nudge row
///
/// The settings row is declared by `FocusSchemaV3` and reused by v4…v7; the nudge preferences
/// row is declared by v5. Editing either would edit a **migration source** — v1…v7 are the
/// stores earlier builds actually wrote, and `MigrationV4Tests` states in as many words that a
/// source you have edited is not a source. v7 re-declared a class to add a column and paid for
/// it with a re-declaration invariant; there is nothing to pay here, because a retention window
/// is not a fact about the nudge loop or about the shell's appearance. So v8 does what v4, v5
/// and v6 did: it re-declares **nothing**, names v7's fourteen classes, and adds one of its own.
/// The v7 → v8 stage is lightweight honestly rather than by assertion.
///
/// ## Why the column is a day count and not an enum name
///
/// `retentionDays` stores `RetentionWindow.storedDays` — 7, 30, 90, or 0 for forever — so the
/// number in the column is the number in the promise, and a person reading their own sqlite file
/// needs no table to interpret it. It carries a **property default** of ninety, which is both the
/// condition probe P-51 measured for a lightweight stage and the answer an upgrading store must
/// give: somebody who has been using the app for a year must not find their history shortened by
/// the arrival of a control they have never touched.
public enum FocusSchemaV8: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(8, 0, 0)
    }

    /// v7's fourteen, plus one. Built from `FocusSchemaV7.models` rather than by re-listing, for
    /// v7's own reason: a hand-written list is a list that silently loses an entity.
    public static var models: [any PersistentModel.Type] {
        FocusSchemaV7.models + [PrivacyPreferencesRecord.self]
    }

    /// **What the person set in the Privacy pane** — a single row, and only what they chose.
    ///
    /// Singleton by convention rather than by constraint, exactly as `AppSettingsRecord` and
    /// `NudgePreferencesRecord` are: SwiftData has no "exactly one row" facility, so the read
    /// takes the earliest-touched row and the write reuses it, and a store that somehow acquired
    /// two converges on one instead of flip-flopping.
    ///
    /// It holds one column today. That is not an argument for putting it somewhere else: the two
    /// other things the Privacy pane can do — reveal the store, delete everything — are actions
    /// rather than settings and have nothing to persist, and the pane's next stored preference
    /// belongs beside this one rather than in the nudge loop's row.
    @Model
    public final class PrivacyPreferencesRecord {
        public var id: UUID
        /// `RetentionWindow.storedDays`: 7, 30, 90, or 0 for forever. Read through
        /// `RetentionWindow.decode(_:)` and never `init(rawValue:)`, so a value written by a
        /// newer build falls to the committed default with the caller told it did.
        public var retentionDays: Int = RetentionWindow.committedDefault.storedDays
        /// When the schema last wrote this row.
        public var touchedAt: Date

        public init(
            id: UUID = UUID(),
            retentionDays: Int = RetentionWindow.committedDefault.storedDays,
            touchedAt: Date
        ) {
            self.id = id
            self.retentionDays = retentionDays
            self.touchedAt = touchedAt
        }
    }
}

// MARK: - Typed accessors
//
// The stored column read through its decoder and written through its raw value, so no call site
// touches `retentionDays` directly or invents its own meaning for zero.

extension FocusSchemaV8.PrivacyPreferencesRecord {
    /// The stored window, and whether this build could read what was in the column.
    public var retentionWindow: (window: RetentionWindow, wasRecognised: Bool) {
        RetentionWindow.decode(retentionDays)
    }

    /// Write the window. Never writes a value `decode(_:)` would not recognise.
    public func setRetentionWindow(_ window: RetentionWindow) {
        retentionDays = window.storedDays
    }
}
