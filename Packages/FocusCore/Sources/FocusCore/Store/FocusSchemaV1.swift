import Foundation
import SwiftData

/// Which phase a focus session is in.
///
/// Stored as `FocusSessionRecord.phaseRaw`, a `String`. Every enum-backed field in this
/// schema is stored as its string raw value and never as an ordinal, so that reordering a
/// Swift enum can never silently reinterpret persisted data.
public enum SessionPhase: String, Sendable, CaseIterable, Codable, Hashable {
    case running
    case paused
    case onBreak
    case ended
}

/// The user's appearance choice, as persisted.
///
/// `matchSystem` is a real third state, not the absence of a choice: the app must be able
/// to tell "follow the Mac" from "I picked light and the Mac happens to be light".
public enum AppearancePreference: String, Sendable, CaseIterable, Codable, Hashable {
    case matchSystem
    case light
    case dark

    /// The colour scheme to render, given what the system currently reports.
    public func resolvedColorScheme(system: AppearanceColorScheme) -> AppearanceColorScheme {
        switch self {
        case .matchSystem: system
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Schema version 1 of the Focus Sentinel store.
///
/// The `@Model` classes are nested **inside** the versioned schema on purpose. That is what
/// makes v2 a rename of a namespace (`FocusSchemaV1.PriorityTask` →
/// `FocusSchemaV2.PriorityTask`) rather than a rewrite of every call site, and it is why
/// `FocusMigrationPlan` can be declared now with an empty `stages` array and grow a stage
/// later instead of being retrofitted.
///
/// All five tables are declared in v1 even though only one of them is written in e01. A
/// table added later is a migration; a table declared now and left empty is not.
public enum FocusSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        [
            PriorityTask.self,
            FocusSessionRecord.self,
            ActivityEvent.self,
            RelevanceRule.self,
            AppSettingsRecord.self
        ]
    }

    /// The single highest-priority thing the user is trying to do.
    ///
    /// `revision` is present from v1 because the verdict cache keys on it: when the user
    /// edits their priority, every cached judgement about the old wording must become
    /// stale, and a monotonically increasing revision is what makes that cheap.
    @Model
    public final class PriorityTask {
        public var id: UUID
        /// What the user wrote, in their own words.
        public var intent: String
        /// The user's own completion criterion, if they gave one.
        public var doneWhen: String?
        /// Exactly one task is active at a time; the app enforces that, not the store.
        public var isActive: Bool
        public var createdAt: Date
        public var completedAt: Date?
        /// Bumped whenever `intent` or `doneWhen` changes.
        public var revision: Int

        public init(
            id: UUID = UUID(),
            intent: String,
            doneWhen: String? = nil,
            isActive: Bool = false,
            createdAt: Date,
            completedAt: Date? = nil,
            revision: Int = 1
        ) {
            self.id = id
            self.intent = intent
            self.doneWhen = doneWhen
            self.isActive = isActive
            self.createdAt = createdAt
            self.completedAt = completedAt
            self.revision = revision
        }
    }

    /// One stretch of focused work.
    @Model
    public final class FocusSessionRecord {
        public var id: UUID
        /// The priority this session was about, if there was one.
        public var taskID: UUID?
        public var startedAt: Date
        public var endedAt: Date?
        /// `SessionPhase` raw value.
        public var phaseRaw: String

        public init(
            id: UUID = UUID(),
            taskID: UUID? = nil,
            startedAt: Date,
            endedAt: Date? = nil,
            phaseRaw: String
        ) {
            self.id = id
            self.taskID = taskID
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.phaseRaw = phaseRaw
        }
    }

    /// One normalised observation.
    ///
    /// **Normalised evidence only, never raw captured content.** `detail` holds a short
    /// non-identifying descriptor — a `scheme://host` origin, a token set — and never a
    /// window title verbatim, a full URL or anything read off the screen.
    @Model
    public final class ActivityEvent {
        public var id: UUID
        public var at: Date
        /// The observation kind's raw value. The vocabulary itself lives in `FocusSensing`,
        /// which `FocusCore` must not import; the store keeps the string.
        public var kindRaw: String
        public var bundleID: String?
        public var detail: String?

        public init(
            id: UUID = UUID(),
            at: Date,
            kindRaw: String,
            bundleID: String? = nil,
            detail: String? = nil
        ) {
            self.id = id
            self.at = at
            self.kindRaw = kindRaw
            self.bundleID = bundleID
            self.detail = detail
        }
    }

    /// One stored user judgement about a subject.
    ///
    /// The scope and verdict vocabularies live in `FocusRules`; the store keeps their raw
    /// values, so `FocusCore` stays free of sibling imports.
    @Model
    public final class RelevanceRule {
        public var id: UUID
        /// `RuleScope` raw value.
        public var scopeRaw: String
        /// Normalised subject: a bundle identifier, a `scheme://host` origin, or a token.
        public var subject: String
        /// `RuleVerdict` raw value.
        public var verdictRaw: String
        public var createdAt: Date

        public init(
            id: UUID = UUID(),
            scopeRaw: String,
            subject: String,
            verdictRaw: String,
            createdAt: Date
        ) {
            self.id = id
            self.scopeRaw = scopeRaw
            self.subject = subject
            self.verdictRaw = verdictRaw
            self.createdAt = createdAt
        }
    }

    /// The app's own persisted settings — a single row.
    ///
    /// It is also the row that proves the store is live at e01: the shell writes it on
    /// first launch and reads it back on every launch after that.
    @Model
    public final class AppSettingsRecord {
        public var id: UUID
        /// `AppearancePreference` raw value.
        public var appearancePreferenceRaw: String
        /// When the schema last wrote this row. Distinguishes "never opened" from
        /// "opened and left at defaults".
        public var schemaTouchedAt: Date

        public init(
            id: UUID = UUID(),
            appearancePreferenceRaw: String,
            schemaTouchedAt: Date
        ) {
            self.id = id
            self.appearancePreferenceRaw = appearancePreferenceRaw
            self.schemaTouchedAt = schemaTouchedAt
        }
    }
}

extension FocusSchemaV1.AppSettingsRecord {
    /// The stored preference, decoded. Falls back to `matchSystem` if the stored string is
    /// not a value this build knows — a forward-compatible read, never a crash.
    public var appearancePreference: AppearancePreference {
        get { AppearancePreference(rawValue: appearancePreferenceRaw) ?? .matchSystem }
        set { appearancePreferenceRaw = newValue.rawValue }
    }
}

extension FocusSchemaV1.FocusSessionRecord {
    /// The stored phase, decoded. Falls back to `ended` for an unknown string: a session
    /// this build cannot interpret is over as far as it is concerned, which is the safe
    /// reading.
    public var phase: SessionPhase {
        get { SessionPhase(rawValue: phaseRaw) ?? .ended }
        set { phaseRaw = newValue.rawValue }
    }
}
