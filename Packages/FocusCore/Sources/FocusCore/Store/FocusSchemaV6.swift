import Foundation
import SwiftData

/// Schema version 6 of the Focus Sentinel store.
///
/// **Three facts the shell has to remember between launches, and none of them had anywhere to
/// live** (focus-odz.4, focus-odz.6, focus-odz.7):
///
/// * whether the first-run explanation has been shown — a screen that must appear exactly once,
///   on a store the app has never seen before;
/// * whether the launch-at-login offer has been put in front of somebody — D-12 says it is
///   offered once, after a first completed session, and never nagged;
/// * which windows were open when the application last quit, so the Keyboard Shortcuts window a
///   person left open comes back.
///
/// ## Why one entity rather than three columns on `AppSettingsRecord`
///
/// `AppSettingsRecord` is declared by `FocusSchemaV3` and reused unchanged by v4 and v5. Editing
/// it would edit a **migration source** — v1, v2 and v3 are the stores earlier builds actually
/// wrote, and `MigrationV4Tests` states in as many words that a source you have edited is not a
/// source. So v6 does what v4 and v5 did: it re-declares nothing, names v5's thirteen classes and
/// adds **one** of its own.
///
/// ## Why the three live together
///
/// Because they are one kind of thing. This is not a preference — nobody sets any of it — it is
/// what the shell remembers about itself between launches. A person's *choices* are
/// `AppSettingsRecord` and `NudgePreferencesRecord`; this is the app's own memory, and keeping
/// the two apart is what stops a "reset my settings" verb in a later epic from also forgetting
/// that somebody has already read the explanation.
///
/// ## Why the v5 → v6 stage is the first custom one since v1 → v2
///
/// A **fresh** store and a **migrated** store are indistinguishable by the absence of a row, and
/// the whole of focus-odz.7 turns on telling them apart: a person upgrading must never be shown a
/// first-run screen. Migration stages run only when there is an older store on disk, so the stage
/// inserts the row itself with `firstRunExplanationShownAt` already set — *"this store has been
/// used; the explanation is not owed"*. A store created at v6 runs no stage, has no row, and is
/// owed the explanation exactly once.
///
/// A lightweight stage plus a heuristic — "does this store already hold priorities?" — was the
/// alternative and is worse in both directions: it would show the screen to somebody whose first
/// launch crashed before they typed anything, and hide it from somebody's genuinely first launch
/// after a restore. The stage knows the answer; a heuristic guesses it.
public enum FocusSchemaV6: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(6, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        FocusSchemaV5.models + [ShellStateRecord.self]
    }

    /// **What the shell remembers about itself between launches.**
    ///
    /// Singleton by convention rather than by constraint, exactly as `AppSettingsRecord` and
    /// `NudgePreferencesRecord` are: SwiftData has no "exactly one row" facility, so the read
    /// takes the earliest-touched row and the write reuses it, and a store that somehow acquired
    /// two converges on one instead of flip-flopping.
    ///
    /// Every column is optional or carries a property default, which is P-51's condition for a
    /// lightweight stage — the stage is custom for the reason above, not because the shape
    /// required it.
    ///
    /// The three date columns are **dates and not booleans** on purpose. "Shown" and "when it was
    /// shown" cost the same to store, and only one of them can answer *"was this before or after
    /// the change that broke it?"* when somebody reports that they saw a screen twice.
    @Model
    public final class ShellStateRecord {
        public var id: UUID
        /// When the first-run explanation was shown. `nil` means it is still owed (focus-odz.7).
        public var firstRunExplanationShownAt: Date?
        /// When the launch-at-login offer was last put in front of somebody. `nil` means never,
        /// which is the only state in which it may appear (D-12, focus-odz.4).
        public var launchAtLoginOfferedAt: Date?
        /// The scene ids that were open when the application last quit, comma-joined and sorted
        /// (focus-odz.6). `nil` means the app has never recorded a quit — a first launch, or one
        /// after a crash — which is a real state and not an empty list: an empty list means
        /// *"every window was closed"*.
        public var openWindowsAtLastQuitRaw: String?
        /// When the schema last wrote this row.
        public var touchedAt: Date

        public init(
            id: UUID = UUID(),
            firstRunExplanationShownAt: Date? = nil,
            launchAtLoginOfferedAt: Date? = nil,
            openWindowsAtLastQuitRaw: String? = nil,
            touchedAt: Date
        ) {
            self.id = id
            self.firstRunExplanationShownAt = firstRunExplanationShownAt
            self.launchAtLoginOfferedAt = launchAtLoginOfferedAt
            self.openWindowsAtLastQuitRaw = openWindowsAtLastQuitRaw
            self.touchedAt = touchedAt
        }
    }
}

// MARK: - Typed accessors
//
// The one `…Raw` column read and written through a decoder, so no call site joins or splits a
// string by hand — the rule every enum-backed column in this store already follows.

extension FocusSchemaV6.ShellStateRecord {
    /// The scene ids that were open at the last quit, or `nil` when no quit has been recorded.
    ///
    /// **A missing value and an empty list are two different facts**, and the app acts differently
    /// on them: nothing recorded means restore nothing and leave the scene graph alone, and an
    /// empty list means the person had closed everything. Encoding the second as `""` rather than
    /// as `nil` is what keeps them apart across a round trip.
    public var openWindowsAtLastQuit: [String]? {
        get {
            guard let raw = openWindowsAtLastQuitRaw else { return nil }
            if raw.isEmpty { return [] }
            return raw.split(separator: ",").map(String.init)
        }
        set {
            openWindowsAtLastQuitRaw = newValue.map { $0.sorted().joined(separator: ",") }
        }
    }
}
