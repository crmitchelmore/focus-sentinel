import Foundation
import SwiftData

/// Schema version 2 of the Focus Sentinel store.
///
/// The `@Model` classes are nested **inside** the versioned schema, exactly as v1's are: that
/// is what makes a version bump a rename of a namespace rather than a rewrite of every call
/// site. `FocusSchemaV1` stays in the repository unchanged and untouched — it is the
/// migration source and the committed fixture's schema, and a migration source you have
/// edited proves nothing.
///
/// ## What changed against v1
///
/// * `PriorityTask` **loses `isActive`** and gains the timebox, completion-reflection and
///   history fields, plus three relationships. The active priority is now a pointer row (see
///   `ActivePriority`), so a stored `isActive` column would be a second source of truth about
///   the one question the whole app is organised around.
/// * `ActivePriority` is new: the single-active-priority invariant, enforced by the database.
/// * `ContextItem` is new: F-09's scope-trimmed context pack — apps, domains, keywords and
///   files, and no fifth kind.
/// * `RelevanceRule` gains `task`, so a rule is either global (`nil`) or scoped to one
///   priority.
/// * `AppSettingsRecord` gains the ritual's local-day key and the stored quick-capture
///   shortcut. The three non-optional additions carry property defaults, which is what makes
///   them migrate without a custom stage of their own (probe P-51).
/// * `FocusSessionRecord` and `ActivityEvent` are unchanged; e03 owns them.
///
/// Enum-backed fields remain `String` raw values (e01's R-05): reordering a Swift enum can
/// never silently reinterpret a persisted row.
public enum FocusSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        [
            PriorityTask.self,
            ActivePriority.self,
            ContextItem.self,
            FocusSessionRecord.self,
            ActivityEvent.self,
            RelevanceRule.self,
            AppSettingsRecord.self
        ]
    }

    /// `keyCode 49` is the Space bar. The default quick-capture shortcut is ⌃⌥⌘Space.
    ///
    /// ⌘Space is deliberately *not* the default: probe P-55 measured that
    /// `RegisterEventHotKey` will happily take Spotlight's combination and report success,
    /// so the app must not be able to steal a system shortcut by shipping one as its default.
    public static let defaultHotKeyKeyCode = 49

    /// `control | option | command`, as `NSEvent.ModifierFlags` raw values
    /// (`1 << 18 | 1 << 19 | 1 << 20`).
    ///
    /// The integer is stored rather than a symbolic value because `FocusCore` may not import
    /// AppKit; `FocusSensing`'s registrar translates it to the Carbon mask it needs.
    public static let defaultHotKeyModifierFlags = (1 << 18) | (1 << 19) | (1 << 20)

    /// The single highest-priority thing the user is trying to do.
    ///
    /// There is no `isActive` column. The active priority is whichever task the one
    /// `ActivePriority` row points at, and `isActive` is a projection of that pointer.
    /// Two sources of truth for "which task am I doing" is the bug this shape prevents.
    ///
    /// `revision` is bumped whenever `intent` or `doneWhen` changes, because the verdict
    /// cache e04 adds keys on it: when the user edits their priority, every cached judgement
    /// about the old wording must become stale.
    @Model
    public final class PriorityTask {
        public var id: UUID
        /// What the user wrote, in their own words.
        public var intent: String
        /// The user's own completion criterion, if they gave one.
        public var doneWhen: String?
        public var createdAt: Date
        public var completedAt: Date?
        /// Bumped whenever `intent` or `doneWhen` changes.
        public var revision: Int
        /// The optional timebox, in seconds. `nil` is "no timebox", which is a real answer.
        public var timeboxSeconds: Int?
        /// When the timebox started running. Wall clock, deliberately: a timebox is a promise
        /// about the clock on the wall, so a Mac that slept for an hour has spent that hour.
        public var startedAt: Date?
        /// F-22's first reflection field: what shipped. Optional, and completion never waits
        /// for it.
        public var shipped: String?
        /// F-22's second reflection field: where to restart.
        public var restartPoint: String?
        /// When this task was last made the active priority. F-15's history orders by it.
        public var lastActivatedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \ContextItem.task)
        public var contextItems: [ContextItem] = []

        @Relationship(deleteRule: .cascade, inverse: \RelevanceRule.task)
        public var rules: [RelevanceRule] = []

        @Relationship(deleteRule: .cascade, inverse: \ActivePriority.task)
        public var activePointer: ActivePriority?

        /// Whether this is the active priority — a projection of the pointer, never a column.
        public var isActive: Bool { activePointer != nil }

        public init(
            id: UUID = UUID(),
            intent: String,
            doneWhen: String? = nil,
            createdAt: Date,
            completedAt: Date? = nil,
            revision: Int = 1,
            timeboxSeconds: Int? = nil,
            startedAt: Date? = nil,
            shipped: String? = nil,
            restartPoint: String? = nil,
            lastActivatedAt: Date? = nil
        ) {
            self.id = id
            self.intent = intent
            self.doneWhen = doneWhen
            self.createdAt = createdAt
            self.completedAt = completedAt
            self.revision = revision
            self.timeboxSeconds = timeboxSeconds
            self.startedAt = startedAt
            self.shipped = shipped
            self.restartPoint = restartPoint
            self.lastActivatedAt = lastActivatedAt
        }
    }

    /// The single-active-priority invariant, enforced by the store rather than by a code path
    /// someone could forget.
    ///
    /// `slot` is always `"active"` and is unique, so the database cannot hold two of these. A
    /// second activation therefore *replaces*, never queues — and because the row that gets
    /// replaced is a pointer, nothing the user wrote is ever what the constraint destroys.
    ///
    /// The application must never insert a second row to provoke that replacement:
    /// `PriorityStore.activate(_:)` re-points the existing row. Inserting a colliding row whose
    /// target already owns one is a **process fatal error** in SwiftData
    /// ("This relationship already has a value but it's not the target"), and re-activating the
    /// current priority is an ordinary thing for a person to do.
    @Model
    public final class ActivePriority {
        @Attribute(.unique) public var slot: String
        public var task: PriorityTask?
        public var activatedAt: Date

        public init(
            slot: String = ActivePriority.singletonSlot,
            task: PriorityTask?,
            activatedAt: Date
        ) {
            self.slot = slot
            self.task = task
            self.activatedAt = activatedAt
        }

        public static let singletonSlot = "active"
    }

    /// One item in a task's context pack.
    ///
    /// Four kinds and no fifth: an application, a normalised web origin, a keyword, or a file.
    /// `kindRaw` is a string so that a build which does not know a stored kind renders it as
    /// an inert chip rather than dropping the row or crashing on it.
    ///
    /// `value` for a file is the path **at the time of adding**, kept for display only; the
    /// durable handle is `bookmark`, a `.withSecurityScope` bookmark. A path is not a file.
    @Model
    public final class ContextItem {
        public var id: UUID
        /// `ContextItemKind` raw value.
        public var kindRaw: String
        /// The normalised subject: a bundle identifier, a `scheme://host[:port]` origin, a
        /// lowercased keyword, or a file path recorded when the item was added.
        public var value: String
        /// What the chip shows: an application's display name, a host, the keyword, or a file
        /// name.
        public var displayName: String
        /// A security-scoped bookmark, for file items only.
        public var bookmark: Data?
        public var addedAt: Date
        public var task: PriorityTask?

        public init(
            id: UUID = UUID(),
            kindRaw: String,
            value: String,
            displayName: String,
            bookmark: Data? = nil,
            addedAt: Date,
            task: PriorityTask? = nil
        ) {
            self.id = id
            self.kindRaw = kindRaw
            self.value = value
            self.displayName = displayName
            self.bookmark = bookmark
            self.addedAt = addedAt
            self.task = task
        }
    }

    /// One stretch of focused work. Unchanged from v1; e03 owns it.
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

    /// One normalised observation. Unchanged from v1; e03 owns it.
    ///
    /// **Normalised evidence only, never raw captured content.**
    @Model
    public final class ActivityEvent {
        public var id: UUID
        public var at: Date
        /// The observation kind's raw value.
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
    /// New in v2: `task`. A rule is either **global** (`task == nil`, which is what e04's
    /// engine reads) or scoped to exactly one priority, in which case it cascades away with
    /// that priority.
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
        /// The priority this rule is scoped to, or `nil` for a global rule.
        public var task: PriorityTask?

        public init(
            id: UUID = UUID(),
            scopeRaw: String,
            subject: String,
            verdictRaw: String,
            createdAt: Date,
            task: PriorityTask? = nil
        ) {
            self.id = id
            self.scopeRaw = scopeRaw
            self.subject = subject
            self.verdictRaw = verdictRaw
            self.createdAt = createdAt
            self.task = task
        }
    }

    /// The app's own persisted settings — a single row.
    ///
    /// The three non-optional additions carry **property defaults**. That is not a style
    /// choice: probe P-51 measured that a new non-optional attribute with a default migrates
    /// under a lightweight rule, and one without a default does not.
    @Model
    public final class AppSettingsRecord {
        public var id: UUID
        /// `AppearancePreference` raw value.
        public var appearancePreferenceRaw: String
        /// When the schema last wrote this row.
        public var schemaTouchedAt: Date
        /// The `LocalDay` key the daily ritual last ran on, or `nil` if it never has.
        /// A local day, keyed through an injected calendar — never a UTC day.
        public var lastRitualLocalDay: String?
        /// Whether the daily ritual banner is offered at all.
        public var ritualEnabled: Bool = true
        /// The quick-capture hot key's virtual key code. 49 is Space.
        public var hotKeyKeyCode: Int = FocusSchemaV2.defaultHotKeyKeyCode
        /// The quick-capture hot key's modifiers, as `NSEvent.ModifierFlags` raw values.
        public var hotKeyModifierFlags: Int = FocusSchemaV2.defaultHotKeyModifierFlags

        public init(
            id: UUID = UUID(),
            appearancePreferenceRaw: String,
            schemaTouchedAt: Date,
            lastRitualLocalDay: String? = nil,
            ritualEnabled: Bool = true,
            hotKeyKeyCode: Int = FocusSchemaV2.defaultHotKeyKeyCode,
            hotKeyModifierFlags: Int = FocusSchemaV2.defaultHotKeyModifierFlags
        ) {
            self.id = id
            self.appearancePreferenceRaw = appearancePreferenceRaw
            self.schemaTouchedAt = schemaTouchedAt
            self.lastRitualLocalDay = lastRitualLocalDay
            self.ritualEnabled = ritualEnabled
            self.hotKeyKeyCode = hotKeyKeyCode
            self.hotKeyModifierFlags = hotKeyModifierFlags
        }
    }
}

extension FocusSchemaV2.AppSettingsRecord {
    /// The stored preference, decoded. Falls back to `matchSystem` if the stored string is
    /// not a value this build knows — a forward-compatible read, never a crash.
    public var appearancePreference: AppearancePreference {
        get { AppearancePreference(rawValue: appearancePreferenceRaw) ?? .matchSystem }
        set { appearancePreferenceRaw = newValue.rawValue }
    }
}

extension FocusSchemaV2.FocusSessionRecord {
    /// The stored phase, decoded through the one sanctioned decoder — see the identical note
    /// on `FocusSchemaV1.FocusSessionRecord.phase`.
    public var phase: SessionPhase {
        get { SessionPhase.decode(phaseRaw) }
        set { phaseRaw = newValue.rawValue }
    }
}
